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
local BiomeConfig       = require(ServerScriptService.Modules.BiomeConfig)
local CheckpointService = require(ServerScriptService.Modules.CheckpointService)
local RaceProgress      = require(ReplicatedStorage.Shared.RaceProgress)
local Passives          = require(ReplicatedStorage.Shared.Passives)
local CarImpact         = require(ReplicatedStorage.Shared.CarImpact)
local EffectFx          = require(ServerScriptService.Modules.EffectFx)
local Telemetry         = require(ServerScriptService.Modules.Telemetry)
local VehicleTuning     = require(ServerScriptService.Modules.VehicleTuning)
local RaceEffects       = require(ServerScriptService.Modules.RaceEffects)
local RaceStart         = require(ServerScriptService.Modules.RaceStart)

local P = Constants.PASSIVES

-- ─── State ────────────────────────────────────────────────────────────────────

local _active      = false
local _biome       = nil
local _startTick   = 0
local _finishOrder = {}   -- { { userId, time } }
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

local function _flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- ─── Progress ─────────────────────────────────────────────────────────────────

local function _progressFor(player, vehicle)
	if not vehicle or not vehicle.PrimaryPart or not _biome then return 0 end
	local ps = _physState[player.UserId]
	local pos = vehicle.PrimaryPart.Position
	local s, seg = RaceProgress.progress(_biome, pos.X, pos.Z, ps and ps.progressSeg)
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
		_spawnY(), ps and ps.progressSeg)

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
	-- SKY: hover target follows the respawn point
	local hover = primary:FindFirstChild("HoverPosition")
	if hover then hover.Position = primary.Position end
	task.wait(0.1)
	primary.Anchored = false
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
		local partY    = vehicle.PrimaryPart.Position.Y
		local submerge = math.max(0, waterY - partY)
		local floatStat = (pdata.vehicleStats and pdata.vehicleStats.floatability) or 20
		local bf = vehicle.PrimaryPart:FindFirstChild("BuoyancyForce")
		if submerge > 0 or partY < waterY + 1 then
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

local function _connectUpdraft(part)
	local function handle(hit, entering)
		if not _active then return end
		local player, vehicle = _ownerOf(hit)
		if not player or not vehicle.PrimaryPart then return end
		local wasIn, isIn = _zoneTouch(player, "updraft", part, hit, entering)
		if wasIn == isIn then return end
		local bf = vehicle.PrimaryPart:FindFirstChild("UpdraftForce")
		if isIn then
			local pdata = SessionManager.getData(player)
			local flyStat = (pdata.vehicleStats and pdata.vehicleStats.flyability) or 10
			if not bf then
				bf = Instance.new("BodyForce")
				bf.Name   = "UpdraftForce"
				bf.Parent = vehicle.PrimaryPart
			end
			bf.Force = Vector3.new(0, Constants.UPDRAFT_BASE_FORCE * (flyStat / 20), 0)
			RemoteEvents.ScreenEffect:FireClient(player, "updraftWarning", {})
		elseif bf then
			bf:Destroy()
		end
	end
	_once(part, "updraftIn", "Touched", function(hit) handle(hit, true) end)
	_once(part, "updraftOut", "TouchEnded", function(hit) handle(hit, false) end)
end

-- ─── Kill plane (all biomes) ──────────────────────────────────────────────────

local _respawnCooldown = {}   -- { [userId] = expireTick }

RunService.Heartbeat:Connect(function()
	if not _active then return end
	local cfg = _biome and BiomeConfig[_biome]
	local killY = (cfg and cfg.killPlaneY) or -50
	for _, player in ipairs(Players:GetPlayers()) do
		local pdata = SessionManager.getData(player)
		local vehicle = pdata and pdata.vehicleModel
		if not vehicle or not vehicle.PrimaryPart then continue end
		if vehicle.PrimaryPart.Position.Y < killY then
			local now = tick()
			if (_respawnCooldown[player.UserId] or 0) > now then continue end
			_respawnCooldown[player.UserId] = now + 3
			task.spawn(_respawnVehicle, player, "kill_plane")
		end
	end
end)

-- ─── Manual respawn (R key from client) ───────────────────────────────────────

local _manualRespawnCooldown = {}   -- { [userId] = expireTick }

RemoteEvents.RequestRespawn.OnServerInvoke = function(player)
	if not _active then return "denied: not racing" end
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

	local primary = vehicle.PrimaryPart
	if primary then
		local away = _flat(primary.Position - part.Position)
		if away.Magnitude > 1e-3 then
			local bv = Instance.new("BodyVelocity")
			bv.Velocity = away.Unit * 30
			bv.MaxForce = Vector3.new(1e5, 1e4, 1e5)
			bv.Parent   = primary
			Debris:AddItem(bv, 0.25)
		end
	end
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

local function _setupBoostPads()
	local pads = CollectionService:GetTagged("BoostPad")
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
		if _activePads[part] then
			part.Transparency = base
			if ring then ring.Transparency = ring:GetAttribute("OriginalTransparency") or 0 end
		else
			part.Transparency = math.max(base, 0.75)
			if ring then ring.Transparency = 0.9 end
		end
	end
end

-- ─── Drift corner zones (all biomes) ─────────────────────────────────────────

local _cornerCooldowns = {}   -- [part][userId] = expireTick

local function _connectDriftCorner(part)
	_once(part, "drift", "Touched", function(hit)
		if not _active then return end
		local player = _ownerOf(hit)
		if not player then return end
		_cornerCooldowns[part] = _cornerCooldowns[part] or {}
		local cds = _cornerCooldowns[part]
		local now = tick()
		if cds[player.UserId] and now < cds[player.UserId] then return end
		cds[player.UserId] = now + Constants.DRIFT_CORNER_COOLDOWN
		RemoteEvents.DriftCharge:FireClient(player, Constants.DRIFT_CHARGE_PER_CORNER)
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
local function _onCarContact(ownerA, vehicleA, hit)
	if not _active then return end
	local ownerB, vehicleB = _ownerOf(hit)
	if not ownerB or ownerB == ownerA then return end
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
	for rank, entry in ipairs(ranked) do
		local player = entry.player
		local ps = _ensureRacer(player)
		local vehicle = ps and ps.vehicle
		local seat = _seatOf(vehicle)
		if not seat then continue end

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

-- ─── Position sync loop ───────────────────────────────────────────────────────

local function _startPositionSync()
	task.spawn(function()
		local length = RaceProgress.trackLength(_biome)
		local nextProgressLog = 0
		while _active do
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

RemoteEvents.DriftTurbo.OnServerEvent:Connect(function(player, level, slid)
	if not _active or not RaceStart.isGo() then return end
	if type(level) ~= "number" or type(slid) ~= "number" then return end
	local tb = Constants.DRIVE.DRIFT_TURBO[level]
	if not tb or slid < tb.time then return end
	local ps = _physState[player.UserId]
	if not ps then return end
	local now = tick()
	if now < (ps.driftTurboAt or 0) + DRIFT_TURBO_GAP then return end
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
	_ensureRacer(player)

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

	local elapsed = tick() - _startTick
	table.insert(_finishOrder, { userId = player.UserId, time = elapsed })
	SessionManager.setFinished(player, elapsed)
	Telemetry.record("finish", { userId = player.UserId, time = elapsed, place = #_finishOrder })

	RemoteEvents.RaceFinished:FireAllClients(_finishOrder)
	print(string.format("[RacingManager] %s finished #%d (%.1fs)", player.Name, #_finishOrder, elapsed))

	if #_finishOrder >= math.max(1, _totalRacers) then
		_active = false
		GameManager.raceComplete(_finishOrder)
	end
end

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

GameManager.onPhaseChanged(function(phase, biome)
	if phase == Constants.PHASES.RACING then
		_active      = true
		_biome       = biome
		-- The clock starts at GO: cars wait on the grid until then (RaceStart).
		RaceStart.begin(Constants.RACE_COUNTDOWN)
		_startTick   = tick() + Constants.RACE_COUNTDOWN
		_finishOrder = {}
		_physState   = {}
		_totalRacers = #Players:GetPlayers()
		_contactCooldown = {}
		_impactCooldown  = {}
		_cornerCooldowns = {}

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
			_ensureRacer(player)
		end

		-- Per-race seed first — _setupBoostPads consumes it.
		_raceSeed = math.random(1, 1000000)

		_setupBoostPads()
		for _, part in ipairs(CollectionService:GetTagged("DriftCorner")) do _connectDriftCorner(part) end
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
		for _, player in ipairs(Players:GetPlayers()) do table.insert(racerIds, player.UserId) end
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
		_active = false
		RaceStart.reset()
		for _, pdata in pairs(SessionManager.getAllData()) do
			VehicleTuning.clear(_seatOf(pdata.vehicleModel))
		end
		_physState = {}
	end
end)

-- Handle player leaving mid-race
Players.PlayerRemoving:Connect(function(player)
	if not _active then return end
	_physState[player.UserId] = nil
	_totalRacers = math.max(1, _totalRacers - 1)
	if #_finishOrder >= _totalRacers then
		_active = false
		GameManager.raceComplete(_finishOrder)
	end
end)
