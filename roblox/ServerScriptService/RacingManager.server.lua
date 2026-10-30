-- RacingManager.server.lua
-- Race state, position tracking, biome physics (mud/buoyancy/updraft/drift),
-- obstacle/boost-pad collision, HEAD/TAIL passives, finish detection.
-- Resolves: Issue #30, #31, #32, #33, #34, #35, #37, #66
--
-- Rules that keep this file correct across rounds (see tests/specs):
--   * Every speed / turn change goes through Modules/VehicleTuning (named
--     multipliers), never by saving and restoring VehicleSeat values.
--   * Touched handlers are connected ONCE per part (_once) and check _active,
--     so a second round does not double every effect.
--   * Harmful effects ask RaceEffects.blocksHit first (shields, Rubber Duck).

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris              = game:GetService("Debris")

local Constants         = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents      = require(ReplicatedStorage.RemoteEvents)
local GameManager       = require(ServerScriptService.GameManager)
local SessionManager    = require(ServerScriptService.SessionManager)
local CatchUp           = require(ReplicatedStorage.Shared.CatchUp)
local RaceBots          = require(ServerScriptService.Modules.RaceBots)
local RaceGrid          = require(ServerScriptService.Modules.RaceGrid)
local BiomeConfig       = require(ServerScriptService.Modules.BiomeConfig)
local CheckpointService = require(ServerScriptService.Modules.CheckpointService)
local RaceProgress      = require(ReplicatedStorage.Shared.RaceProgress)
local VehicleController = require(ReplicatedStorage.Shared.VehicleController)
local Passives          = require(ReplicatedStorage.Shared.Passives)
local CarImpact         = require(ReplicatedStorage.Shared.CarImpact)
local EffectFx          = require(ServerScriptService.Modules.EffectFx)
local Telemetry         = require(ServerScriptService.Modules.Telemetry)
local VehicleLift       = require(ServerScriptService.Modules.VehicleLift)
local VehicleTuning     = require(ServerScriptService.Modules.VehicleTuning)
local RaceEffects       = require(ServerScriptService.Modules.RaceEffects)
local RaceStart         = require(ServerScriptService.Modules.RaceStart)
local RaceSeat          = require(ServerScriptService.Modules.RaceSeat)
local BoostGauge        = require(ServerScriptService.Modules.BoostGauge)

local P = Constants.PASSIVES

-- ─── State ────────────────────────────────────────────────────────────────────

local _active      = false
local _biome       = nil
local _startTick   = 0
local _finishOrder = {}   -- { { userId, time } }
local _racers = {}        -- userId → true for the players racing this round (they had a car)
local _totalRacers = 0
local _raceSeed    = 0    -- broadcast to clients for per-race variation
local _activePads  = {}   -- [BoostPad part] = true for this race

-- _physState[userId] = {
--   zones = { mud = {[part]=true}, slow = {...}, updraft = {...} },
--   boostCooldownEnd, obstaclePenaltyEnd, progressSeg, cleanSince,
--   head = {...}, tail = {...}, slots = {...},
-- }
local _physState = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function _seatOf(vehicle)
	return vehicle and vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
end

-- Records a MaxSpeed change so overlapping effects can be audited later.
local function _logSpeed(player, effect, phase, before, after)
	Telemetry.record("speed_effect", {
		userId = player.UserId, effect = effect, phase = phase,
		before = before, after = after,
	})
end

-- Applies a named MaxSpeed multiplier through VehicleTuning and logs it.
local function _speed(player, seat, id, mult, duration)
	if not seat then return end
	local before = seat.MaxSpeed
	VehicleTuning.set(seat, "MaxSpeed", id, mult, duration)
	_logSpeed(player, id, "enter", before, seat.MaxSpeed)
	if duration then
		task.delay(duration, function()
			if seat.Parent then _logSpeed(player, id, "expire", nil, seat.MaxSpeed) end
		end)
	end
end

local function _unspeed(player, seat, id)
	if not seat or not VehicleTuning.has(seat, "MaxSpeed", id) then return end
	local before = seat.MaxSpeed
	VehicleTuning.remove(seat, "MaxSpeed", id)
	_logSpeed(player, id, "exit", before, seat.MaxSpeed)
end

-- The racer whose vehicle contains `hit`, plus that vehicle.
local _updraftUntil = setmetatable({}, { __mode = "k" })   -- [vehicle] = os.clock() a lift ends

local function _ownerOf(hit)
	local node = hit
	while node and node ~= workspace do
		if node:IsA("Model") then
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == node then
					return player, node
				end
			end
		end
		node = node.Parent
	end
	return nil
end

-- Connects `fn` to part.Touched (or another signal) only once per part.
local _connected = setmetatable({}, { __mode = "k" })
local function _once(part, key, signalName, fn)
	_connected[part] = _connected[part] or {}
	if _connected[part][key] then return end
	_connected[part][key] = true
	part[signalName]:Connect(fn)
end

local _creditProgress   -- below (finish check)

local function _flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- ─── Progress ─────────────────────────────────────────────────────────────────

local function _progressFor(player, vehicle)
	if not vehicle or not vehicle.PrimaryPart or not _biome then return 0 end
	local ps = _physState[player.UserId]
	local pos = vehicle.PrimaryPart.Position
	local s, seg = RaceProgress.progress(_biome, pos.X, pos.Z, ps and ps.progressSeg, pos.Y)
	if ps then ps.progressSeg = seg end
	return s
end

-- ─── Respawn ──────────────────────────────────────────────────────────────────

local function _spawnY()
	local cfg = _biome and BiomeConfig[_biome]
	return (cfg and cfg.raceStartY) or 2
end

-- Puts the vehicle back on the track centerline 30 studs behind its progress,
-- facing along the track.
local function _respawnVehicle(player, reason)
	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return end

	local primary = vehicle.PrimaryPart
	local ps = _physState[player.UserId]
	local x, y, z, yaw = RaceProgress.respawnPoint(_biome, primary.Position.X, primary.Position.Z,
		_spawnY(), ps and ps.progressSeg, primary.Position.Y)

	Telemetry.record("respawn", {
		userId = player.UserId,
		reason = reason or "unknown",
		s = math.floor(_progressFor(player, vehicle)),
		from = Telemetry.vec(primary.Position),
		to = { x = x, y = y, z = z },
	})

	primary.Anchored = true
	vehicle:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
	primary.AssemblyLinearVelocity  = Vector3.zero
	primary.AssemblyAngularVelocity = Vector3.zero
	-- the held height (SKY hover, OCEAN water line) starts at the respawn
	-- point, on a raised road too
	VehicleController.resetRide(primary, (RaceProgress.roadRise(_biome, x, z, nil, y)))
	task.wait(0.1)
	-- before GO the car stays held on the grid (RaceStart lets it go)
	if RaceStart.isGo() then primary.Anchored = false end
	if ps then ps.cleanSince = tick() end

	RemoteEvents.ScreenEffect:FireClient(player, "respawn", {})
end

-- ─── Zones (mud / slow / updraft): entered while any car part touches ─────────

-- zones[kind][zonePart] = { [car part touching it] = true }. The car is "in"
-- while any of its parts touches any zone of that kind, so a wheel leaving the
-- mud while the chassis is still in it does not end the effect.
local function _zoneTouch(player, kind, zonePart, hitPart, entering)
	local ps = _physState[player.UserId]
	if not ps then return false, false end
	ps.zones[kind] = ps.zones[kind] or {}
	local zones = ps.zones[kind]
	local wasIn = next(zones) ~= nil
	local hits = zones[zonePart]
	if entering then
		if not hits then
			hits = {}
			zones[zonePart] = hits
		end
		hits[hitPart] = true
	elseif hits then
		hits[hitPart] = nil
		if next(hits) == nil then zones[zonePart] = nil end
	end
	return wasIn, next(zones) ~= nil
end

local function _connectSpeedZone(part, kind, mult, warning)
	local function handle(hit, entering)
		if not _active then return end
		local player, vehicle = _ownerOf(hit)
		if not player then return end
		local wasIn, isIn = _zoneTouch(player, kind, part, hit, entering)
		if wasIn == isIn then return end
		local seat = _seatOf(vehicle)
		if isIn then
			if RaceEffects.has(player, "dig") then return end   -- Drill ignores mud / slow ground
			_speed(player, seat, kind, mult)
			if warning then RemoteEvents.ScreenEffect:FireClient(player, warning, {}) end
		else
			_unspeed(player, seat, kind)
		end
	end
	_once(part, kind .. "In", "Touched", function(hit) handle(hit, true) end)
	_once(part, kind .. "Out", "TouchEnded", function(hit) handle(hit, false) end)
end

-- ─── Buoyancy (OCEAN) ─────────────────────────────────────────────────────────

local function _waterY()
	local cfg = BiomeConfig.get("OCEAN")
	return (cfg.waterPlaneY or 0) + (workspace:GetAttribute("WaterLevelOffset") or 0)
end

RunService.Heartbeat:Connect(function()
	if not _active or _biome ~= "OCEAN" then return end
	local waterY = _waterY()
	for userId, pdata in pairs(SessionManager.getAllData()) do
		local vehicle = pdata.vehicleModel
		if not vehicle or not vehicle.PrimaryPart or not _physState[userId] then continue end
		local pos      = vehicle.PrimaryPart.Position
		local partY    = pos.Y
		-- a raised flume carries its own water at the road height
		local ps = _physState[userId]
		local rise = ps.progressSeg and RaceProgress.roadRise(_biome, pos.X, pos.Z, ps.progressSeg, partY) or 0
		local submerge = math.max(0, waterY + rise - partY)
		local floatStat = (pdata.vehicleStats and pdata.vehicleStats.floatability) or 20
		local bf = vehicle.PrimaryPart:FindFirstChild("BuoyancyForce")
		if submerge > 0 or partY < waterY + rise + 1 then
			if not bf then
				bf = Instance.new("BodyForce")
				bf.Name   = "BuoyancyForce"
				bf.Parent = vehicle.PrimaryPart
			end
			bf.Force = Vector3.new(0, submerge * 300 + floatStat * 15, 0)
		elseif bf then
			bf:Destroy()
		end
	end
end)

-- ─── Updraft zones (SKY) ──────────────────────────────────────────────────────

-- Updrafts (SKY): a column of rising air on the lane lifts a plane by
-- Constants.UPDRAFT.LIFT studs for DURATION s through Modules/VehicleLift
-- (the held flying height; an upward BodyForce could not beat it, so the
-- old updrafts did nothing). Planes with more flyability ride it higher.
local function _connectUpdraft(part)
	_once(part, "updraftIn", "Touched", function(hit)
		if not _active then return end
		local player, vehicle = _ownerOf(hit)
		local stats
		if player then
			local pdata = SessionManager.getData(player)
			stats = pdata and pdata.vehicleStats
		else
			for _, bot in ipairs(RaceBots.list) do
				if bot.model and hit:IsDescendantOf(bot.model) then vehicle, stats = bot.model, bot.stats end
			end
		end
		if not vehicle or not vehicle.PrimaryPart then return end
		local U = Constants.UPDRAFT
		local key = vehicle
		if (_updraftUntil[key] or 0) > os.clock() then return end   -- one lift per pass
		_updraftUntil[key] = os.clock() + U.DURATION
		local fly = (stats and stats.flyability) or U.FLY_REF
		local studs = U.LIFT * math.clamp(fly / U.FLY_REF, U.MIN_SCALE, U.MAX_SCALE)
		VehicleLift.set(vehicle, "updraft", studs, U.DURATION)
		Telemetry.record("updraft", { userId = player and player.UserId or nil, bot = player == nil, zone = part.Name,
			lift = math.floor(studs * 10) / 10 })
		if player then RemoteEvents.ScreenEffect:FireClient(player, "updraftWarning", {}) end
	end)
end

-- ─── Kill plane (all biomes) ──────────────────────────────────────────────────

local _respawnCooldown = {}   -- { [userId] = expireTick }
local _seatCheckAt = 0

-- Racers stay in their car (Modules/RaceSeat): out of the seat or respawned
-- at the farm, they are put back in it.
local function _keepSeated()
	local now = tick()
	if now < _seatCheckAt then return end
	_seatCheckAt = now + Constants.RACE_SEAT.CHECK_EVERY
	for _, player in ipairs(Players:GetPlayers()) do
		if not _racers[player.UserId] then continue end
		local pdata = SessionManager.getData(player)
		local vehicle = pdata and pdata.vehicleModel
		local result = vehicle and RaceSeat.check(player, vehicle, now)
		if result then
			Telemetry.record("reseat", { userId = player.UserId, why = result })
			if result == "respawned" then
				RemoteEvents.VehicleSpawned:FireClient(player, player.UserId, vehicle)
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	if not _active then return end
	_keepSeated()
	local cfg = _biome and BiomeConfig[_biome]
	local killY = (cfg and cfg.killPlaneY) or -50
	for _, player in ipairs(Players:GetPlayers()) do
		local pdata = SessionManager.getData(player)
		local vehicle = pdata and pdata.vehicleModel
		if not vehicle or not vehicle.PrimaryPart then continue end
		local pos = vehicle.PrimaryPart.Position
		local reason = pos.Y < killY and "kill_plane" or nil
		if not reason then
			-- fell off a raised stretch of road onto the ground below it
			local ps = _physState[player.UserId]
			local s = ps and ps.progressSeg and RaceProgress.progress(_biome, pos.X, pos.Z, ps.progressSeg)
			local roadY = s and RaceProgress.roadY(_biome, s)
			if roadY and pos.Y < roadY - RaceProgress.FALL_BELOW then reason = "fell" end
			-- out of the lane (a boat on the open sea): back on the road
			if not reason and ps and not pdata.finishTime and RaceStart.isGo() then
				local beyond = RaceProgress.offLane(_biome, pos.X, pos.Z, ps.progressSeg, pos.Y)
				if RaceProgress.offLaneStep(ps, beyond, dt or 1 / 60) then reason = "off_lane" end
			end
		end
		if reason then
			local now = tick()
			if (_respawnCooldown[player.UserId] or 0) > now then continue end
			_respawnCooldown[player.UserId] = now + 3
			task.spawn(_respawnVehicle, player, reason)
		end
	end
end)

-- ─── Manual respawn (R key from client) ───────────────────────────────────────

local _manualRespawnCooldown = {}   -- { [userId] = expireTick }

RemoteEvents.RequestRespawn.OnServerInvoke = function(player)
	if not _active then return "denied: not racing" end
	for _, f in ipairs(_finishOrder) do
		if f.userId == player.UserId then return "denied: finished" end
	end
	if not RaceStart.isGo() then return "denied: countdown" end
	local now = tick()
	if (_manualRespawnCooldown[player.UserId] or 0) > now then
		return "denied: cooldown"
	end
	_manualRespawnCooldown[player.UserId] = now + 5   -- 5s between manual resets
	_respawnVehicle(player, "manual")
	return "ok"
end

-- ─── Obstacles (map parts and dynamic drops: Cactus, falling logs, …) ────────

local function _onObstacleTouched(part, hit)
	if not _active then return end
	local player, vehicle = _ownerOf(hit)
	if not player then return end
	local ps = _physState[player.UserId]
	if not ps or tick() < (ps.obstaclePenaltyEnd or 0) then return end
	ps.obstaclePenaltyEnd = tick() + Constants.OBSTACLE_BOUNCE_PENALTY_DURATION

	if RaceEffects.blocksHit(player) then
		Telemetry.record("hit_blocked", { userId = player.UserId, by = part.Name })
		return
	end
	ps.cleanSince = tick()
	Telemetry.record("hit", { userId = player.UserId, by = part.Name, s = math.floor(_progressFor(player, vehicle)) })

	_speed(player, _seatOf(vehicle), "obstacle",
		Constants.OBSTACLE_BOUNCE_SPEED_MULT, Constants.OBSTACLE_BOUNCE_PENALTY_DURATION)

	-- Bounce off: a knock away from the obstacle plus a little spin, sent to
	-- the driver like a car hit (a second body mover, as before, fought
	-- DriveVelocity and did almost nothing).
	local primary = vehicle.PrimaryPart
	if primary then
		local away = _flat(primary.Position - part.Position)
		if away.Magnitude > 1e-3 then
			local d = away.Unit * Constants.OBSTACLE_BOUNCE_PUSH
			local look = primary.CFrame.LookVector
			local side = look.X * away.Unit.Z - look.Z * away.Unit.X
			RemoteEvents.CarImpact:FireClient(player, d.X, d.Z, side * Constants.IMPACT.MAX_SPIN * 0.4, Constants.IMPACT.BIG_HIT)
		end
	end
	EffectFx.play("bump", player, nil)
	RemoteEvents.ScreenEffect:FireClient(player, "collision", {})
end

local function _connectObstacle(part)
	if not part:IsA("BasePart") then return end
	_once(part, "obstacle", "Touched", function(hit) _onObstacleTouched(part, hit) end)
end

for _, part in ipairs(CollectionService:GetTagged("Obstacle")) do
	_connectObstacle(part)
end
CollectionService:GetInstanceAddedSignal("Obstacle"):Connect(_connectObstacle)

-- ─── Boost pads ───────────────────────────────────────────────────────────────
-- Seed-driven subset selection: each race picks a different K-of-N subset of
-- placed BoostPads to be active. Inactive ones are dimmed.

local _padCooldowns = {}   -- [part][userId] = expireTick
local _driftCornerCount = 0   -- this race's DriftCorner zones (turbo cap)

local function _connectBoostPad(part)
	_once(part, "boostPad", "Touched", function(hit)
		if not _active or not _activePads[part] then return end
		local player, vehicle = _ownerOf(hit)
		if not player then return end
		_padCooldowns[part] = _padCooldowns[part] or {}
		local cds = _padCooldowns[part]
		if cds[player.UserId] and tick() < cds[player.UserId] then return end
		cds[player.UserId] = tick() + 5   -- 5s pad cooldown
		_speed(player, _seatOf(vehicle), "boostPad", 1.4, 2)
		RemoteEvents.ScreenEffect:FireClient(player, "boostPad", {})
	end)
end

-- The live biome's map (workspace.Maps.<Biome>Map); nil without one.
local function _activeMap()
	if not _biome then return nil end
	local maps = workspace:FindFirstChild("Maps")
	return maps and maps:FindFirstChild(_biome:sub(1, 1):upper() .. _biome:sub(2):lower() .. "Map")
end

local function _setupBoostPads()
	-- only the live map's pads: the hidden maps stand in the place too
	-- (OCEAN's pad at (0, 500) sat in FOREST's lane)
	local map = _activeMap()
	local pads = {}
	for _, part in ipairs(CollectionService:GetTagged("BoostPad")) do
		if not map or part:IsDescendantOf(map) then table.insert(pads, part) end
	end
	table.sort(pads, function(a, b) return a:GetFullName() < b:GetFullName() end)
	_activePads = {}
	_padCooldowns = {}
	if #pads == 0 then return end

	local rng = Random.new(_raceSeed)
	local shuffled = table.clone(pads)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local activeCount = math.max(1, math.ceil(#shuffled * Constants.RACE_BOOST_PAD_ACTIVE_RATIO))
	for i = 1, activeCount do _activePads[shuffled[i]] = true end

	for _, part in ipairs(pads) do
		_connectBoostPad(part)
		local base = part:GetAttribute("OriginalTransparency") or 0
		local ring = part.Parent and part.Parent:FindFirstChild(part.Name .. "Ring", true)
		-- Dimmed: MapVisibility.restore keeps it (MapManager may show the
		-- map after this runs)
		if _activePads[part] then
			part:SetAttribute("Dimmed", nil)
			part.Transparency = base
			if ring then
				ring:SetAttribute("Dimmed", nil)
				ring.Transparency = ring:GetAttribute("OriginalTransparency") or 0
			end
		else
			part:SetAttribute("Dimmed", 0.75)
			part.Transparency = math.max(base, 0.75)
			if ring then ring:SetAttribute("Dimmed", 0.9); ring.Transparency = 0.9 end
		end
	end
end

-- ─── Drift corner zones (all biomes) ─────────────────────────────────────────

local function _connectDriftCorner(part)
	_once(part, "drift", "Touched", function(hit)
		if not _active then return end
		local player = _ownerOf(hit)
		if not player then return end
		local amount = BoostGauge.corner(player.UserId, part, tick())
		if amount then RemoteEvents.DriftCharge:FireClient(player, amount) end
	end)
end

-- ─── HEAD / TAIL passives ─────────────────────────────────────────────────────

local function _carPose(vehicle)
	local cf = vehicle.PrimaryPart.CFrame
	local look = _flat(cf.LookVector)
	if look.Magnitude > 1e-3 then look = look.Unit end
	return { x = cf.Position.X, z = cf.Position.Z, lx = look.X, lz = look.Z }
end

local _contactCooldown = {}   -- ["a:b"] = expireTick (HEAD / TAIL passives)
local _impactCooldown  = {}   -- ["a:b"] = expireTick (the physical hit)

local function _body(vehicle)
	local pp = vehicle.PrimaryPart
	local v = pp.AssemblyLinearVelocity
	local look = _flat(pp.CFrame.LookVector)
	return {
		x = pp.Position.X, z = pp.Position.Z, vx = v.X, vz = v.Z,
		mass = pp.AssemblyMass, lx = look.X, lz = look.Z,
	}
end

-- HEAD / TAIL passives of a rear-end contact. Adjusts the victim's side of
-- the physical hit (`hit`, may be nil) instead of adding its own mover.
local function _rearEndPassives(attacker, victim, aVeh, vVeh, hitAttacker, hitVictim)
	local aps, vps = _physState[attacker.UserId], _physState[victim.UserId]
	local fx = Passives.contactEffects(aps and aps.slots, vps and vps.slots)
	local now = tick()
	if aps then aps.cleanSince = now end
	if vps then vps.cleanSince = now end

	local victimBlocked = (fx.victimPush > 0 or fx.victimSlow) and RaceEffects.blocksHit(victim)
	if victimBlocked then
		EffectFx.play("blocked", victim, nil)   -- Rubber Duck / shield ate the hit
		if hitVictim then hitVictim.dvx, hitVictim.dvz, hitVictim.spin = 0, 0, 0 end
	elseif fx.victimPush == 0 and not fx.victimSlow then
		EffectFx.play("bumperAbsorb", victim, nil, attacker)   -- Balloon Bunch TAIL
		if hitVictim then hitVictim.dvx, hitVictim.dvz, hitVictim.spin = 0, 0, 0 end
	else
		if fx.victimPush > P.RAM_PUSH then
			-- Shopping Cart HEAD: an extra shove on top of the hit
			EffectFx.play("cartShove", victim, nil, attacker)
			if hitVictim then
				local dir = _flat(aVeh.PrimaryPart.CFrame.LookVector)
				CarImpact.addPush(hitVictim, dir.X, dir.Z, fx.victimPush - P.RAM_PUSH)
			end
		elseif fx.victimPush > 0 then
			EffectFx.play("rammed", victim, nil, attacker)
		end
		if fx.victimSlow then
			EffectFx.play("cactusSting", victim, fx.victimSlow.duration, attacker)
			_speed(victim, _seatOf(vVeh), "cactusHead", fx.victimSlow.mult, fx.victimSlow.duration)
		end
	end
	if fx.attackerSlow and not RaceEffects.blocksHit(attacker) then
		EffectFx.play("cactusSting", attacker, fx.attackerSlow.duration, victim)
		_speed(attacker, _seatOf(aVeh), "cactusTail", fx.attackerSlow.mult, fx.attackerSlow.duration)
	end
	Telemetry.record("contact", {
		attacker = attacker.UserId, victim = victim.UserId,
		push = fx.victimPush, victimSlow = fx.victimSlow ~= nil and not victimBlocked,
		attackerSlow = fx.attackerSlow ~= nil,
	})
end

-- Any contact between two race cars: a physical hit for both (Shared/
-- CarImpact → RemoteEvents.CarImpact → VehicleController.knock on each
-- driver's client), plus the HEAD / TAIL passives when it was a rear-end.
-- The drive model sets each car's velocity every frame, so without this a
-- hit felt like touching a wall.
-- A race bot's car (RaceBots.list) that `hit` belongs to, or nil.
local function _botOf(hit)
	for _, bot in ipairs(RaceBots.list) do
		if bot.model and hit:IsDescendantOf(bot.model) then return bot end
	end
	return nil
end

-- A player's car meeting a race bot's: the same physical hit, the bot's
-- half through RaceBots.knock. Without it the two drive models pushed into
-- each other like into a wall: the player stopped dead, side-on, juddering
-- (playtest 2026-10-28, Studio record-sky: 0 km/h behind a bot in the dive).
local function _onBotContact(ownerA, vehicleA, bot)
	if not vehicleA.PrimaryPart or not bot.primary or not bot.primary.Parent then return end
	if RaceEffects.has(ownerA, "disguised") then return end
	local a, b = ownerA.UserId, bot.id
	local key = a .. ":" .. b
	local now = tick()
	if (_impactCooldown[key] or 0) > now then return end
	_impactCooldown[key] = now + Constants.IMPACT.PAIR_COOLDOWN
	local impact = CarImpact.resolve(_body(vehicleA), _body(bot.model))
	if not impact then return end
	RemoteEvents.CarImpact:FireClient(ownerA, impact.a.dvx, impact.a.dvz, impact.a.spin, impact.strength, b)
	RaceBots.knock(bot.id, impact.b.dvx, impact.b.dvz, impact.b.spin)
	if impact.strength >= Constants.IMPACT.BIG_HIT then
		EffectFx.play("bump", ownerA, nil, bot.proxy)
		EffectFx.play("bump", bot.proxy, nil, ownerA)
	end
	local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
	Telemetry.record("impact", {
		a = a, b = b, bot = true, strength = r1(impact.strength),
		dvA = r1(math.sqrt(impact.a.dvx ^ 2 + impact.a.dvz ^ 2)), spinA = r1(impact.a.spin),
		dvB = r1(math.sqrt(impact.b.dvx ^ 2 + impact.b.dvz ^ 2)), spinB = r1(impact.b.spin),
	})
end

local function _onCarContact(ownerA, vehicleA, hit)
	if not _active then return end
	local ownerB, vehicleB = _ownerOf(hit)
	if not ownerB then
		local bot = _botOf(hit)
		if bot then _onBotContact(ownerA, vehicleA, bot) end
		return
	end
	if ownerB == ownerA then return end
	if not vehicleA.PrimaryPart or not vehicleB.PrimaryPart then return end
	if RaceEffects.has(ownerA, "disguised") or RaceEffects.has(ownerB, "disguised") then return end

	local a, b = ownerA.UserId, ownerB.UserId
	local key = (a < b) and (a .. ":" .. b) or (b .. ":" .. a)
	local now = tick()
	if (_impactCooldown[key] or 0) > now then return end
	_impactCooldown[key] = now + Constants.IMPACT.PAIR_COOLDOWN

	local impact = CarImpact.resolve(_body(vehicleA), _body(vehicleB))

	-- Rear-end passives (own, longer cooldown)
	if (_contactCooldown[key] or 0) <= now then
		local who = Passives.rearEnd(_carPose(vehicleA), _carPose(vehicleB))
		if who then
			_contactCooldown[key] = now + P.CONTACT_COOLDOWN
			if who == "a" then
				_rearEndPassives(ownerA, ownerB, vehicleA, vehicleB, impact and impact.a, impact and impact.b)
			else
				_rearEndPassives(ownerB, ownerA, vehicleB, vehicleA, impact and impact.b, impact and impact.a)
			end
		end
	end

	if not impact then return end
	RemoteEvents.CarImpact:FireClient(ownerA, impact.a.dvx, impact.a.dvz, impact.a.spin, impact.strength, b)
	RemoteEvents.CarImpact:FireClient(ownerB, impact.b.dvx, impact.b.dvz, impact.b.spin, impact.strength, a)
	if impact.strength >= Constants.IMPACT.BIG_HIT then
		EffectFx.play("bump", ownerA, nil, ownerB)
		EffectFx.play("bump", ownerB, nil, ownerA)
	end
	local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
	Telemetry.record("impact", {
		a = a, b = b, strength = r1(impact.strength),
		dvA = r1(math.sqrt(impact.a.dvx ^ 2 + impact.a.dvz ^ 2)), spinA = r1(impact.a.spin),
		dvB = r1(math.sqrt(impact.b.dvx ^ 2 + impact.b.dvz ^ 2)), spinB = r1(impact.b.spin),
	})
end

-- Per-race passive setup for one player (vehicle may spawn after RACING starts).
local function _ensureRacer(player)
	local ps = _physState[player.UserId]
	if not ps then return nil end
	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return ps end
	if ps.vehicle ~= vehicle then
		ps.vehicle = vehicle
		local slots = (pdata.vehicleStats and pdata.vehicleStats.slotAssignments) or {}
		ps.slots = slots
		ps.head, ps.tail = Passives.forSlots(slots)
		ps.cleanSince = tick()
		if ps.head.absorbOneHit then
			RaceEffects.grant(player, "absorb")   -- Rubber Duck: one hit per race
		end
		_once(vehicle.PrimaryPart, "carContact", "Touched", function(hit)
			_onCarContact(player, vehicle, hit)
		end)
	end
	return ps
end

-- Lead bonus (Racing Flag), momentum (Flower) and slipstream (Toilet Paper).
local function _updatePassives(ranked)
	local now = tick()
	local leadS = ranked[1] and ranked[1].progress
	local botS = RaceBots.bestProgress()
	if botS and (not leadS or botS > leadS) then leadS = botS end
	for rank, entry in ipairs(ranked) do
		local player = entry.player
		local ps = _ensureRacer(player)
		local vehicle = ps and ps.vehicle
		local seat = _seatOf(vehicle)
		if not seat then continue end

		-- Catch-up (Shared/CatchUp): far behind the leader → a bit faster.
		local cu = leadS and CatchUp.mult(leadS - entry.progress) or 1
		if cu > 1 then
			VehicleTuning.set(seat, "MaxSpeed", "catchUp", cu)
		else
			VehicleTuning.remove(seat, "MaxSpeed", "catchUp")
		end

		local lead = ps.head and ps.head.leadSpeedBonus
		if lead then
			local leading = rank == 1 and #ranked > 1
			if leading and not ps.leadShown then
				EffectFx.play("leadFlag", player, nil, nil, { text = string.format("+%d%%", math.floor(lead * 100 + 0.5)) })
			end
			ps.leadShown = leading
			if leading then
				VehicleTuning.set(seat, "MaxSpeed", "leadFlag", 1 + lead)
			else
				VehicleTuning.remove(seat, "MaxSpeed", "leadFlag")
			end
		end

		local momentum = ps.head and ps.head.momentumBonus
		if momentum then
			local mult = Passives.momentumMult(now - (ps.cleanSince or now), momentum)
			if mult > (ps.momentumShown or 1) + 1e-6 then
				EffectFx.play("momentum", player, nil, nil, { text = string.format("+%d%%", math.floor((mult - 1) * 100 + 0.5)) })
			end
			ps.momentumShown = mult
			if mult > 1 then
				VehicleTuning.set(seat, "MaxSpeed", "momentum", mult)
			else
				VehicleTuning.remove(seat, "MaxSpeed", "momentum")
			end
		end

		local slip = ps.tail and ps.tail.slipstreamSlow
		if slip and vehicle.PrimaryPart then
			local leader = _carPose(vehicle)
			for _, other in ipairs(ranked) do
				if other.player ~= player then
					local ops = _physState[other.player.UserId]
					local ov = ops and ops.vehicle
					if ov and ov.PrimaryPart and Passives.isDirectlyBehind(leader, _carPose(ov)) then
						local key = "slip_" .. player.UserId
						if (ops[key] or 0) < now then
							EffectFx.play("slipstream", other.player, P.LEAD_PERIOD * 1.5, player)
						end
						ops[key] = now + P.LEAD_PERIOD * 2
						VehicleTuning.set(_seatOf(ov), "MaxSpeed", "slipstream_" .. player.UserId,
							1 - slip, P.LEAD_PERIOD * 1.5)
					end
				end
			end
		end
	end
end

-- ─── Driven distance (finish check) ──────────────────────────────────────────
-- Cars are moved by their driver's client, so a cheat can teleport one
-- through the checkpoints and the finish (launch audit 2026-10-30). Each
-- sync tick credits the progress made, up to what the fastest car could
-- drive in that time; a finish counts only with FINISH_CREDIT of the road
-- driven that way. Respawns go back, a lag spike loses a little credit.

local FINISH_CREDIT = 0.7     -- share of the road from the grid that must be credited
local CREDIT_SPEED  = 1.25    -- × the stacked top speed
local CREDIT_SLACK  = 25      -- studs per tick on top (jumps, a sync late)

_creditProgress = function(ps, progress, pdata)
	local now = tick()
	if ps.creditS and ps.creditT then
		local d = progress - ps.creditS
		if d > 0 then
			local top = Constants.maxSpeedFor(_biome, (pdata and pdata.vehicleStats) or {}) * Constants.SPEED_STACK_MAX
			ps.credit = (ps.credit or 0) + math.min(d, top * CREDIT_SPEED * (now - ps.creditT) + CREDIT_SLACK)
		end
	end
	ps.creditS, ps.creditT = progress, now
end

local function _finishCheckOn()
	local h = GameManager.getHarness()
	return h == nil or h.finishCheck == true
end

-- ─── Position sync loop ───────────────────────────────────────────────────────

-- One sync loop per race: a race that never reached RESULTS (a phase
-- error goes back to LOBBY) left its loop running next to the next one's.
local _syncGen = 0
local function _startPositionSync()
	_syncGen += 1
	local gen = _syncGen
	task.spawn(function()
		local length = RaceProgress.trackLength(_biome)
		local nextProgressLog = 0
		while _active and gen == _syncGen do
			-- Fun metrics (RaceMetrics) read one progress sample per racer per second.
			local logProgress = tick() - _startTick >= nextProgressLog
			if logProgress then nextProgressLog += Constants.FUN.PROGRESS_EVERY end
			local data, ranked = {}, {}
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel and _physState[player.UserId] then
					local progress = _progressFor(player, pdata.vehicleModel)
					table.insert(data, { userId = player.UserId, progress = progress, rank = 0 })
					-- When each car first leaves its grid spot (fair-start check).
					local ps = _physState[player.UserId]
					ps.gridS = ps.gridS or progress
					_creditProgress(ps, progress, pdata)
					if not ps.launched and progress - ps.gridS > 2 then
						ps.launched = true
						Telemetry.record("race_launch", { userId = player.UserId, afterGo = tick() - _startTick })
					end
					if logProgress then
						Telemetry.record("race_progress", { userId = player.UserId, s = math.floor(progress) })
					end
					table.insert(ranked, { player = player, progress = progress })
					local pp = pdata.vehicleModel.PrimaryPart
					if pp and Telemetry.detailed then
						local seatS = _seatOf(pdata.vehicleModel)
						Telemetry.sample("race_sample", {
							userId = player.UserId,
							x = math.floor(pp.Position.X * 10) / 10,
							y = math.floor(pp.Position.Y * 10) / 10,
							z = math.floor(pp.Position.Z * 10) / 10,
							speed = math.floor(pp.AssemblyLinearVelocity.Magnitude * 10) / 10,
							maxSpeed = seatS and seatS.MaxSpeed,
							progress = progress,
						})
					end
				end
			end
			-- Finished racers rank ahead of everyone still driving
			local finishedAt = {}
			for i, f in ipairs(_finishOrder) do finishedAt[f.userId] = i end
			local function key(e)
				local f = finishedAt[e.userId or e.player.UserId]
				return f and (1e9 - f) or e.progress
			end
			table.sort(data, function(a, b) return key(a) > key(b) end)
			table.sort(ranked, function(a, b) return key(a) > key(b) end)
			for rank, entry in ipairs(data) do
				entry.rank = rank
				entry.length = length
				local player = Players:GetPlayerByUserId(entry.userId)
				if player then SessionManager.setRaceProgress(player, entry.progress, rank) end
			end
			_updatePassives(ranked)
			RemoteEvents.PlayerPositionSync:FireAllClients(data)
			task.wait(Constants.POSITION_SYNC_RATE)
		end
	end)
end

-- ─── Drift mini-turbo ─────────────────────────────────────────────────────────
-- The client times the slide (VehicleController.updateDrift) and asks for
-- the turbo it earned; the server checks the level against the slide time it
-- reports and caps how often a car can claim one.

local DRIFT_TURBO_GAP = 1.0   -- s between two turbos of one car (a drift + release takes longer)

-- The slide time is the client's word, so the server bounds what it can
-- buy (launch audit 2026-10-30: DriftTurbo(2, 99) every second kept a car
-- at ×1.38 for the whole race): two releases are at least the slide the
-- level needs apart, never on SKY (planes do not drift), and a race pays
-- at most DRIFT_TURBOS_PER_CORNER per drift corner of the track (+ spare).
local DRIFT_TURBOS_PER_CORNER = 2
local DRIFT_TURBOS_SPARE = 4

RemoteEvents.DriftTurbo.OnServerEvent:Connect(function(player, level, slid)
	if not _active or not RaceStart.isGo() or _biome == "SKY" then return end
	if type(level) ~= "number" or type(slid) ~= "number" or slid ~= slid then return end
	local tb = Constants.DRIVE.DRIFT_TURBO[level]
	if not tb or slid < tb.time then return end
	local ps = _physState[player.UserId]
	if not ps then return end
	local now = tick()
	if now < (ps.driftTurboAt or 0) + math.max(DRIFT_TURBO_GAP, tb.time) then return end
	local cap = _driftCornerCount * DRIFT_TURBOS_PER_CORNER + DRIFT_TURBOS_SPARE
	if (ps.driftTurbos or 0) >= cap then return end
	ps.driftTurbos = (ps.driftTurbos or 0) + 1
	ps.driftTurboAt = now
	local pdata = SessionManager.getData(player)
	local seat = _seatOf(pdata and pdata.vehicleModel)
	if not seat then return end
	EffectFx.play(level >= 2 and "superTurbo" or "miniTurbo", player, tb.duration)
	_speed(player, seat, "driftTurbo", tb.mult, tb.duration)
	Telemetry.record("drift_turbo", { userId = player.UserId, level = level, slid = math.floor(slid * 10) / 10 })
end)

-- ─── Manual boost activation (F key) ─────────────────────────────────────────

RemoteEvents.RequestBoost.OnServerInvoke = function(player)
	if not _active then return "denied: not racing" end
	if not RaceStart.isGo() then return "denied: countdown" end
	local ps = _physState[player.UserId]
	if not ps then return "denied: no state" end

	local now = tick()
	if now < (ps.boostCooldownEnd or 0) then
		return "denied: cooldown"
	end

	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle then return "denied: no vehicle" end
	local seat = _seatOf(vehicle)
	if not seat then return "denied: no seat" end
	-- the gauge (drift corners fill it), kept here: the client's own copy
	-- only draws the bar
	if not BoostGauge.spend(player.UserId) then return "denied: gauge" end
	_ensureRacer(player)
	Telemetry.record("boost", { userId = player.UserId })

	local duration = (pdata.vehicleStats and pdata.vehicleStats.boostDuration)
		or Constants.BOOST_DURATION
	duration += (ps.tail and ps.tail.boostDurationAdd) or 0   -- Rocket TAIL

	ps.boostCooldownEnd = now + Constants.BOOST_COOLDOWN
	EffectFx.play((ps.tail and ps.tail.boostDurationAdd) and "boostRocket" or "boost", player, duration)
	_speed(player, seat, "boost", Constants.BOOST_MULTIPLIER, duration)

	-- Soda Bottle TAIL: the car right behind gets a face full of fizz
	if ps.tail and ps.tail.boostBlindTrail and vehicle.PrimaryPart then
		local me = _carPose(vehicle)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local od = SessionManager.getData(other)
				local ov = od and od.vehicleModel
				if ov and ov.PrimaryPart and Passives.isDirectlyBehind(me, _carPose(ov), P.SLIPSTREAM_RANGE * 1.5)
					and not RaceEffects.blocksHit(other) then
					EffectFx.play("steamed", other, P.BLIND_TIME, player)
					RemoteEvents.ScreenEffect:FireClient(other, "steamBlind", { duration = P.BLIND_TIME })
				end
			end
		end
	end
	return "ok"
end

-- ─── Finish line ──────────────────────────────────────────────────────────────

local _afterFinish   -- below

local function _onFinishTouched(hit)
	if not _active then return end
	local player = _ownerOf(hit)
	if not player then return end
	for _, entry in ipairs(_finishOrder) do
		if entry.userId == player.UserId then return end
	end

	-- Gate finish on checkpoint completion. If the active map has no
	-- checkpoints tagged, the gate is inactive and the finish counts.
	if CheckpointService.isActive() and not CheckpointService.hasCompleted(player) then
		Telemetry.record("finish_rejected", { userId = player.UserId, reason = "checkpoints" })
		return
	end
	if _finishCheckOn() then
		local ps = _physState[player.UserId]
		local _, car = _ownerOf(hit)
		if ps then _creditProgress(ps, _progressFor(player, car), SessionManager.getData(player)) end
		local need = (RaceProgress.trackLength(_biome) - ((ps and ps.gridS) or 0)) * FINISH_CREDIT
		if not ps or (ps.credit or 0) < need then
			local now = tick()
			if now > (ps and ps.finishWarnAt or 0) then
				if ps then ps.finishWarnAt = now + 5 end
				Telemetry.record("finish_rejected", { userId = player.UserId, reason = "not driven",
					credit = math.floor(ps and ps.credit or 0), need = math.floor(need) })
			end
			return
		end
	end

	local elapsed = tick() - _startTick
	table.insert(_finishOrder, { userId = player.UserId, name = player.Name, time = elapsed })
	SessionManager.setFinished(player, elapsed)
	-- Park the car: it brakes to a stop in the run-off past the line. (Studio
	-- 2026-10-22: finished cars kept driving, ran off the end of the road and
	-- fell, respawned at the end and fell again until the race ended.)
	local _, vehicle = _ownerOf(hit)
	local seat = vehicle and _seatOf(vehicle)
	if seat then
		VehicleTuning.set(seat, "MaxSpeed", "finished", 0)
		VehicleTuning.set(seat, "TurnSpeed", "finished", 0.5)
	end
	Telemetry.record("finish", { userId = player.UserId, time = elapsed, place = #_finishOrder })
	print(string.format("[RacingManager] %s finished #%d (%.1fs)", player.Name, #_finishOrder, elapsed))
	_afterFinish(elapsed)
end

-- After any finish (player or bot): tell everyone, end the race when all
-- racers are in, start the grace after the winner.
_afterFinish = function(elapsed)
	RemoteEvents.RaceFinished:FireAllClients(_finishOrder)
	if #_finishOrder >= math.max(1, _totalRacers) then
		_active = false
		GameManager.raceComplete(_finishOrder)
	elseif #_finishOrder == 1 then
		-- the winner is in: everyone else gets CatchUp.graceFor(winner) s
		-- (FINISH_GRACE at least), not the full timeout
		if GameManager.shortenPhase(Constants.PHASES.RACING, CatchUp.graceFor(elapsed)) then
			RemoteEvents.ScreenEffect:FireAllClients("finishGrace", { duration = 3 })
		end
	end
end

RaceBots.onFinish(function(bot)
	if not _active then return end
	local elapsed = tick() - _startTick
	table.insert(_finishOrder, { userId = bot.id, name = bot.name, bot = true, time = elapsed })
	Telemetry.record("finish", { userId = bot.id, time = elapsed, place = #_finishOrder, bot = true })
	_afterFinish(elapsed)
end)

RaceBots.setLeaderProgress(function()
	local best = nil
	for _, player in ipairs(Players:GetPlayers()) do
		local d = SessionManager.getData(player)
		if d and d.vehicleModel and d.raceProgress and (not best or d.raceProgress > best) then best = d.raceProgress end
	end
	return best
end)

-- Standings when the race ends on its timer: finishers in order, then the
-- rest by how far they got (time = nil → "DNF" on the results screen).
GameManager.setRaceStandings(function()
	local out, done = {}, {}
	for _, f in ipairs(_finishOrder) do
		table.insert(out, f)
		done[f.userId] = true
	end
	local rest = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local d = SessionManager.getData(player)
		if d and d.vehicleModel and not done[player.UserId] then
			table.insert(rest, { userId = player.UserId, dnf = true, progress = math.floor(d.raceProgress or 0) })
		end
	end
	for _, bot in ipairs(RaceBots.list) do
		if not done[bot.id] then
			table.insert(rest, { userId = bot.id, name = bot.name, bot = true, dnf = true, progress = math.floor(bot.s or 0) })
		end
	end
	table.sort(rest, function(a, b) return a.progress > b.progress end)
	for _, r in ipairs(rest) do table.insert(out, r) end
	Telemetry.record("race_timeout", { finished = #_finishOrder, dnf = #rest })
	return out
end)

local function _setupFinishLine()
	-- Prefer the active biome's map so another biome's sensor is never used.
	local finishPart
	if _biome then
		local mapName   = _biome:sub(1,1):upper() .. _biome:sub(2):lower() .. "Map"
		local mapsModel = workspace:FindFirstChild("Maps")
		local biomeMap  = mapsModel and mapsModel:FindFirstChild(mapName)
		finishPart = biomeMap and biomeMap:FindFirstChild("FinishLine", true)
	end
	finishPart = finishPart or workspace:FindFirstChild("FinishLine", true)
	if not finishPart then
		warn("[RacingManager] No FinishLine Part found in Workspace")
		return
	end
	_once(finishPart, "finish", "Touched", _onFinishTouched)
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

-- The race is over (RESULTS, or LOBBY after a phase error): stop the loops,
-- the GO hold and every car's speed multipliers.
local function _endRace()
	_active = false
	RaceStart.reset()
	for _, pdata in pairs(SessionManager.getAllData()) do
		VehicleTuning.clear(_seatOf(pdata.vehicleModel))
	end
	_physState = {}
	-- per-player maps that otherwise kept every visitor of the server
	BoostGauge.reset()
	_respawnCooldown, _manualRespawnCooldown = {}, {}
end

GameManager.onPhaseChanged(function(phase, biome)
	if phase == Constants.PHASES.RACING then
		_active      = true
		_biome       = biome
		-- The clock starts at GO: cars wait on the grid until then (RaceStart).
		RaceStart.begin(Constants.RACE_COUNTDOWN)
		_startTick   = tick() + Constants.RACE_COUNTDOWN
		_finishOrder = {}
		_physState   = {}
		RaceSeat.reset()
		-- Racers: everyone here when RACING starts except those who joined
		-- during a race (Spectating). CraftingManager builds the cars just
		-- after this, so whoever still has no car at GO watches instead and
		-- is not waited for (Studio load-8p: counting cars right here found
		-- one car and ended the race at the first finish).
		_racers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Spectating") ~= true then
				_racers[player.UserId] = true
			end
		end
		_totalRacers = 0
		for _ in pairs(_racers) do _totalRacers += 1 end
		-- Empty grid slots → bots (Modules/RaceBots; live servers, or harness fillBots)
		local nBots = RaceBots.wanted(_totalRacers, GameManager.getHarness())
		if nBots > 0 then
			-- a bot that fails to build must not skip the race's own set-up
			-- below (finish line, checkpoints, boost pads)
			local ok, err = pcall(function()
				local bots = RaceBots.spawn(biome, nBots, RaceGrid.cframes(biome), #Players:GetPlayers() + 1)
				_totalRacers += #bots
				RaceBots.run(biome)
			end)
			if not ok then warn("[RacingManager] race bots: " .. tostring(err)) end
		end
		local raceRacers = _racers
		task.delay(Constants.RACE_COUNTDOWN, function()
			if not _active or _racers ~= raceRacers then return end
			for uid in pairs(table.clone(_racers)) do
				local p = Players:GetPlayerByUserId(uid)
				local d = p and SessionManager.getData(p)
				if p and not (d and d.vehicleModel) then
					_racers[uid] = nil
					_totalRacers = math.max(1, _totalRacers - 1)
					p:SetAttribute("Spectating", true)
				end
			end
		end)
		_contactCooldown = {}
		_impactCooldown  = {}

		for _, player in ipairs(Players:GetPlayers()) do
			RaceEffects.reset(player)
			_physState[player.UserId] = {
				zones              = {},
				boostCooldownEnd   = 0,
				obstaclePenaltyEnd = 0,
				progressSeg        = nil,
				cleanSince         = tick(),
				head = {}, tail = {}, slots = {},
			}
			BoostGauge.start(player.UserId)   -- full, like the bar on the client
			_ensureRacer(player)
		end

		-- Per-race seed first — _setupBoostPads consumes it.
		_raceSeed = math.random(1, 1000000)

		_setupBoostPads()
		_driftCornerCount = 0
		local liveMap = _activeMap()
		for _, part in ipairs(CollectionService:GetTagged("DriftCorner")) do
			_connectDriftCorner(part)
			if not liveMap or part:IsDescendantOf(liveMap) then _driftCornerCount += 1 end
		end
		for _, part in ipairs(CollectionService:GetTagged("SlowZone")) do
			_connectSpeedZone(part, "slowZone", Constants.SLOW_ZONE_MULT, nil)
		end
		if biome == "FOREST" then
			for _, part in ipairs(CollectionService:GetTagged("MudZone")) do
				_connectSpeedZone(part, "mud", Constants.MUD_SPEED_MULT, "mudWarning")
			end
		elseif biome == "SKY" then
			for _, part in ipairs(CollectionService:GetTagged("UpdraftZone")) do _connectUpdraft(part) end
		end

		local racerIds = {}
		for uid in pairs(_racers) do table.insert(racerIds, uid) end
		table.sort(racerIds)
		Telemetry.record("race_start", {
			biome = biome, racers = racerIds, round = GameManager.getRound(),
			length = RaceProgress.trackLength(biome), timeout = Constants.RACING_TIMEOUT,
		})

		CheckpointService.resetAll()
		CheckpointService.setup()

		_setupFinishLine()
		_startPositionSync()

		RemoteEvents.RaceIntroShown:FireAllClients({ biome = biome })
		RemoteEvents.RaceSeedBroadcast:FireAllClients(_raceSeed)

	elseif phase == Constants.PHASES.RESULTS then
		_endRace()
	elseif phase == Constants.PHASES.LOBBY or phase == Constants.PHASES.FARMING then
		-- a race that never reached RESULTS (phase error → LOBBY) ends here
		if _active then _endRace() end
		RaceBots.clear()   -- bot cars stay parked through RESULTS
	end
end)

-- Handle player leaving mid-race
Players.PlayerRemoving:Connect(function(player)
	if not _active then return end
	_physState[player.UserId] = nil
	if not _racers[player.UserId] then return end   -- a spectator leaving changes nothing
	_racers[player.UserId] = nil
	-- a finisher stays in _finishOrder and in the count: dropping them
	-- ended the race while others still drove (launch audit 2026-10-30)
	for _, f in ipairs(_finishOrder) do
		if f.userId == player.UserId then return end
	end
	_totalRacers = math.max(1, _totalRacers - 1)
	if #_finishOrder >= _totalRacers then
		_active = false
		GameManager.raceComplete(_finishOrder)
	end
end)
