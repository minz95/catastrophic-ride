-- RaceBots.lua
-- Server-driven racers that fill an empty grid on live servers: with fewer
-- than Constants.BOTS.FILL_TO racers, bots in random builds take the free
-- grid slots and race with the same driver (Shared/Autopilot) and drive rule
-- (Shared/VehicleController) as everyone else; the server owns their cars.
-- RacingManager starts them, counts their finishes and lists them in the
-- results (name, bot = true); they earn nothing. They are the farm bots
-- (Modules/FarmBots: same ids and names, SessionManager bot proxies): a bot
-- that farmed races the auto craft of its bag, others a random build. Their
-- car is the proxy's vehicleModel, so abilities and race effects hit them
-- like anyone (shoves arrive through RaceBots.knock). They fire their own
-- abilities too, through AbilityManager's request handler (the same checks
-- as a player's E): self buffs when ready, aimed ones with a car in range.
-- Off in harness sessions unless HarnessConfig `fillBots` asks for them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Autopilot = require(Shared.Autopilot)
local VehicleController = require(Shared.VehicleController)
local RaceProgress = require(Shared.RaceProgress)
local CatchUp = require(Shared.CatchUp)
local RoadHazards = require(Shared.RoadHazards)
local CraftingRules = require(Shared.CraftingRules)
local Cosmetics = require(Shared.Cosmetics)
local ItemTypes = require(Shared.ItemTypes)
local VehicleStats = require(Shared.VehicleStats)
local BiomeConfig = require(ServerScriptService.Modules.BiomeConfig)
local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
local VehicleTuning = require(ServerScriptService.Modules.VehicleTuning)
local RaceStart = require(ServerScriptService.Modules.RaceStart)
local Telemetry = require(ServerScriptService.Modules.Telemetry)
local SessionManager = require(ServerScriptService.SessionManager)
local FarmBots = require(ServerScriptService.Modules.FarmBots)
local SeatedRider = require(ServerScriptService.Modules.SeatedRider)
local BoostGauge = require(ServerScriptService.Modules.BoostGauge)
local EffectFx = require(ServerScriptService.Modules.EffectFx)
local AbilityConfig = require(ServerScriptService.Modules.AbilityConfig)
local AbilitySlots = require(Shared.AbilitySlots)

local RaceBots = {}

RaceBots.ID_BASE = FarmBots.ID_BASE   -- bot ids: ID_BASE - n (never a real UserId)
RaceBots.list = {}           -- bots of the current race

local _conn = nil
local _onFinish = nil
local _otherProgress = nil   -- fn() → best progress of the players (catch-up)
local _useAbility = nil      -- fn(proxy, item) → "ok" | "denied: …" (AbilityManager)
local _rng = Random.new()

local TRIGGERS = { "Checkpoint1", "Checkpoint2", "FinishLine", "DriftCorner" }

--- fn(bot) when a bot crosses the line (RacingManager).
function RaceBots.onFinish(fn) _onFinish = fn end
--- fn() → the leading player's progress, for the bots' catch-up.
function RaceBots.setLeaderProgress(fn) _otherProgress = fn end
--- fn(proxy, item) fires an ability for a bot (AbilityManager registers it).
function RaceBots.setAbilityHandler(fn) _useAbility = fn end

-- Another racer's car within `range` of `pos`?
local function carNear(bot, pos, range)
	for _, other in ipairs(SessionManager.actors()) do
		local d = other ~= bot.proxy and SessionManager.getData(other)
		local m = d and d.vehicleModel
		local p = m and m.Parent and m.PrimaryPart
		if p and (p.Position - pos).Magnitude <= range then return true end
	end
	return false
end

-- Now and then, an ability: the next ready item in E order. Aimed ones
-- (targetType "nearest", "random_enemy", "all_in_radius") wait for a car in range.
-- How far the road turns over the next `ahead` studs from `s` (rad, the
-- largest heading change from here).
local function turnAhead(biome, s, ahead)
	local geo = RaceProgress.geometry(biome)
	if not geo then return 0 end
	local _, _, dx0, dz0 = geo:pointAt(s)
	local h0 = math.atan2(dx0, dz0)
	local most = 0
	for d = 10, ahead, 10 do
		local _, _, dx, dz = geo:pointAt(s + d)
		local diff = math.abs((math.atan2(dx, dz) - h0 + math.pi) % (2 * math.pi) - math.pi)
		most = math.max(most, diff)
	end
	return most
end

-- Boost (F) like a player: a full gauge (BoostGauge: drift corners fill
-- it), off cooldown, going straight at speed, and the road stays straight
-- for the whole boost (Studio 2026-10-26: a novice boosted into the next
-- corner, hit the wall and was stuck there).
local function tryBoost(bot, speed, info, biome)
	local R = Constants.BOTS.RACE
	if bot.t < (bot.boostReady or 0) or speed < R.MIN_SPEED then return end
	if math.abs(info.err or 1) > R.BOOST_MAX_ERR or not BoostGauge.ready(bot.id) then return end
	local duration = (bot.stats and bot.stats.boostDuration) or Constants.BOOST_DURATION
	local ahead = speed * Constants.BOOST_MULTIPLIER * (duration + R.BOOST_SETTLE)
	if biome and info.s and turnAhead(biome, info.s, ahead) > R.BOOST_MAX_TURN then return end
	BoostGauge.spend(bot.id)
	bot.boostReady = bot.t + Constants.BOOST_COOLDOWN
	VehicleTuning.set(bot.seat, "MaxSpeed", "boost", Constants.BOOST_MULTIPLIER, duration)
	EffectFx.play("boost", bot.proxy, duration)
	Telemetry.record("boost", { userId = bot.id, bot = true })
end

RaceBots.tryBoost = tryBoost   -- tests: nothing drives offline

local function tryAbility(bot, biome, pos, speed)
	local R = Constants.BOTS.RACE
	if not _useAbility or bot.t < (bot.nextAbility or 0) then return end
	-- stuck or crawling: a drop would land in its own way after a respawn
	if speed < R.MIN_SPEED then return end
	bot.nextAbility = bot.t + R.ABILITY_EVERY * _rng:NextNumber(0.6, 1.4)
	if _rng:NextNumber() > R.ABILITY_CHANCE then return end
	local slots = bot.slots
	local items = AbilitySlots.list(slots)
	if #items == 0 then return end
	bot.abilityTurn = ((bot.abilityTurn or 0) % #items) + 1
	for k = 0, #items - 1 do
		local item = items[((bot.abilityTurn - 1 + k) % #items) + 1].item
		local cfg = AbilityConfig.get(item, biome)
		local aimed = cfg and (cfg.targetType == "nearest" or cfg.targetType == "random_enemy" or cfg.targetType == "all_in_radius")
		if cfg and (not aimed or carNear(bot, pos, R.TARGET_RANGE)) then
			local res = _useAbility(bot.proxy, item)
			if res == "ok" then
				Telemetry.record("bot_ability", { userId = bot.id, item = item, aimed = aimed or nil })
				return
			end
		end
	end
end

--- How many bots to add for `humans` racers (harness: args.fillBots).
function RaceBots.wanted(humans, harness)
	local B = Constants.BOTS
	local fillTo
	if harness then
		fillTo = harness.fillBots
		if type(fillTo) ~= "number" then return 0 end
	else
		fillTo = B.FILL_TO
	end
	return math.max(0, math.min(fillTo, Constants.MAX_PLAYERS) - humans)
end

--- A random build: 8 random items placed like an auto craft.
function RaceBots.randomSlots(rng)
	local inv = {}
	for _ = 1, Constants.INVENTORY_SIZE do
		table.insert(inv, ItemTypes.ALL[rng:NextInteger(1, #ItemTypes.ALL)].name)
	end
	return CraftingRules.autoSlots(inv, ItemConfig)
end

local function statsFor(slots, biome)
	local stats = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	stats = VehicleStats.applyMobility(stats, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	stats.headItem, stats.tailItem, stats.slotAssignments = slots.HEAD, slots.TAIL, slots
	return stats
end

local function nameTag(chassis, name)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BotName"
	gui.Size = UDim2.new(0, 140, 0, 26)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 150
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = "🤖 " .. name
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.TextStrokeTransparency = 0.3
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.Parent = gui
	gui.Parent = chassis
end

--- Spawns `count` bots on grid CFrames `slots` (from the end of the grid).
function RaceBots.spawn(biome, count, gridCFrames, firstSlot)
	RaceBots.clear()
	local B = Constants.BOTS
	local geo = RaceProgress.geometry(biome)
	local cfg = BiomeConfig[biome] or {}
	for k = 1, count do
		local cf = gridCFrames[firstSlot + k - 1]
		if not cf then break end
		local proxy = FarmBots.proxy(k)
		local data = SessionManager.getData(proxy)
		local farmed = data and #data.inventory > 0
		local slots = farmed and CraftingRules.autoSlots(data.inventory, ItemConfig) or RaceBots.randomSlots(_rng)
		local stats = statsFor(slots, biome)
		local paints = Cosmetics.ITEMS.paint
		local paint = paints[_rng:NextInteger(1, #paints)]
		local model = VehicleBuilder.build(stats, biome, cf, slots, { paint = paint.body and paint or nil })
		local name = proxy.Name
		local id = proxy.UserId
		if data then data.vehicleModel, data.vehicleStats = model, stats end
		model.Name = "Bot_" .. name
		model:SetAttribute("BotRacer", true)
		model:SetAttribute("BotName", name)
		model:SetAttribute("OwnerUserId", id)
		model.Parent = workspace
		local primary = model.PrimaryPart
		nameTag(primary, name)
		-- a driver in the seat, in the bot's farm shirt (massless: the car
		-- handles as before)
		SeatedRider.seat(model, model, FarmBots.shirt(proxy.index or k), { passenger = true, fallback = true })
		local hover = primary:FindFirstChild("HoverPosition")
		if hover then hover.Position = primary.Position end
		VehicleController.resetRide(primary, 0)
		RaceStart.hold(primary)
		local rayParams = RaycastParams.new()
		rayParams.IgnoreWater = true   -- OCEAN's Terrain water is not ground (TerrainPlan.WATER)
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { model }
		rayParams.RespectCanCollide = true
		local profileName = proxy.profile or B.PROFILES[((k - 1) % #B.PROFILES) + 1]
		local bot = {
			id = id, name = name, model = model, primary = primary,
			seat = model:FindFirstChildWhichIsA("VehicleSeat", true),
			ap = geo and Autopilot.new(geo, Autopilot.PROFILES[profileName] or Autopilot.PROFILES.average, k * 977),
			profile = profileName, drive = VehicleController.newState(), rayParams = rayParams, proxy = proxy, farmed = farmed,
			cp = { false, false }, s = 0, finished = false, riseSeg = nil, t = 0, owned = false,
			slots = slots, stats = stats, nextAbility = B.RACE.ABILITY_FIRST * _rng:NextNumber(0.7, 1.3),
		}
		table.insert(RaceBots.list, bot)
		BoostGauge.start(id)   -- full, like a player's
		Telemetry.record("race_bot", { id = id, name = name, profile = profileName, slots = table.clone(slots), farmed = farmed,
			maxSpeed = bot.seat and bot.seat.MaxSpeed })
	end
	return RaceBots.list
end

local function respawn(bot, biome, startY)
	local primary = bot.primary
	local pos = primary.Position
	local lx, ly, lz, lyaw = RaceProgress.respawnPoint(biome, pos.X, pos.Z, startY, bot.ap and bot.ap.segHint, pos.Y)
	primary.Anchored = true
	bot.model:PivotTo(CFrame.new(lx, ly, lz) * CFrame.Angles(0, lyaw, 0))
	primary.AssemblyLinearVelocity = Vector3.zero
	primary.AssemblyAngularVelocity = Vector3.zero
	VehicleController.resetRide(primary, (RaceProgress.roadRise(biome, lx, lz, nil, ly)))
	bot.riseSeg = nil
	primary.Anchored = false
	VehicleController.reset(bot.drive)
	if bot.ap then bot.ap:resetTracking() end
	Telemetry.record("respawn", { userId = bot.id, reason = "bot", s = math.floor(bot.s) })
end

local function step(bot, biome, dt, overlap, startY, killY, leadS, hazards)
	local primary, seat = bot.primary, bot.seat
	if bot.finished or not primary or not primary.Parent or not seat or not bot.ap then return end
	if not RaceStart.isGo() or primary.Anchored then return end
	if not bot.owned then
		bot.owned = true
		pcall(function() primary:SetNetworkOwner(nil) end)
	end
	bot.t += dt
	local pos, vel = primary.Position, primary.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
	local isSky = primary:FindFirstChild("HoverPosition") ~= nil
	local keys, info = bot.ap:update({
		hazards = RoadHazards.near(hazards, pos),
		x = pos.X, z = pos.Z, y = pos.Y, yaw = yaw, speed = speed,
		forward = vel:Dot(primary.CFrame.LookVector),
		maxSpeed = seat.MaxSpeed, turnSpeed = VehicleController.turnRate(seat.TurnSpeed, isSky), t = bot.t,
		isSky = isSky, biome = biome, travelYaw = bot.drive.travelYaw,
	})
	bot.s = info.s

	for _, p in ipairs(workspace:GetPartsInPart(primary, overlap)) do
		if CollectionService:HasTag(p, "Checkpoint1") then bot.cp[1] = true
		elseif CollectionService:HasTag(p, "Checkpoint2") and bot.cp[1] then bot.cp[2] = true
		elseif CollectionService:HasTag(p, "DriftCorner") then
			BoostGauge.corner(bot.id, p, tick())
		elseif CollectionService:HasTag(p, "FinishLine") and bot.cp[1] and bot.cp[2] then
			bot.finished = true
			VehicleTuning.set(seat, "MaxSpeed", "finished", 0)
			if _onFinish then task.spawn(_onFinish, bot) end
			return
		end
	end

	local geo = RaceProgress.geometry(biome)
	if info.respawn or pos.Y < killY or (geo and pos.Y < geo:heightAt(info.s) - RaceProgress.FALL_BELOW) then
		respawn(bot, biome, startY)
		return
	end
	-- out of the lane (OCEAN: a boat that slipped out floats on the open sea)
	local beyond = RaceProgress.offLane(biome, pos.X, pos.Z, bot.ap.segHint, pos.Y)
	if RaceProgress.offLaneStep(bot, beyond, dt) then
		Telemetry.record("off_lane", { userId = bot.id, bot = true, s = math.floor(bot.s),
			x = math.floor(pos.X), y = math.floor(pos.Y), z = math.floor(pos.Z) })
		respawn(bot, biome, startY)
		return
	end
	-- what lifts a bot high over its road (playtest: "bots shoot up into the sky")
	if geo and pos.Y > geo:heightAt(info.s) + Constants.BOTS.RACE.HIGH_LOG and (bot.highLogAt or -99) < bot.t - 3 then
		bot.highLogAt = bot.t
		Telemetry.record("bot_high", { userId = bot.id, s = math.floor(bot.s), above = math.floor(pos.Y - geo:heightAt(info.s)),
			vy = math.floor(vel.Y), lift = primary:GetAttribute("LiftOffset"), air = primary:GetAttribute("AirT") ~= nil,
			spring = primary:GetAttribute("SpringVY"), biome = biome })
	end

	tryAbility(bot, biome, pos, speed)
	tryBoost(bot, speed, info, biome)

	-- the same catch-up as the players (Shared/CatchUp)
	local cu = leadS and CatchUp.mult(leadS - bot.s) or 1
	if cu > 1 then VehicleTuning.set(seat, "MaxSpeed", "catchUp", cu) else VehicleTuning.remove(seat, "MaxSpeed", "catchUp") end

	local input = VehicleController.readKeys(keys)
	local maxSpeed = seat.MaxSpeed
	local change, level = VehicleController.updateDrift(bot.drive, input, speed, maxSpeed, isSky)
	if level and change ~= "enter" then
		local tb = Constants.DRIVE.DRIFT_TURBO[level]
		if tb then VehicleTuning.set(seat, "MaxSpeed", "driftTurbo", tb.mult, tb.duration) end
	end
	local _, yawNow = primary.CFrame:ToEulerAnglesYXZ()
	local tdx, tdz = VehicleController.travelDir(bot.drive, yawNow)
	local cmd = VehicleController.command(input, {
		maxSpeed = seat.MaxSpeed, turnSpeed = seat.TurnSpeed, isSky = isSky,
		drifting = bot.drive.drifting, biome = biome, yaw = yawNow,
		torque = seat.Torque, dt = dt, actualForward = vel.X * tdx + vel.Z * tdz,
	}, bot.drive)
	local rise = nil
	if biome ~= "FOREST" then
		rise, bot.riseSeg = RaceProgress.roadRise(biome, pos.X, pos.Z, bot.riseSeg, pos.Y)
	end
	VehicleController.apply(primary, cmd, {
		biome = biome, altitudeDt = dt, roadRise = rise,
		raycast = function(origin, direction) return workspace:Raycast(origin, direction, bot.rayParams) end,
	})

	-- progress like the players' (RaceMetrics), and what blocks a bot
	bot.nextLog = bot.nextLog or 0
	if bot.t >= bot.nextLog then
		bot.nextLog += Constants.FUN.PROGRESS_EVERY
		Telemetry.record("race_progress", { userId = bot.id, s = math.floor(bot.s), bot = true })
	end
	if cmd.forwardSpeed > 10 and speed < cmd.forwardSpeed * 0.25 then
		-- pinned against something (a cactus dropped in front, a wall): back
		-- on the line after STUCK_RESPAWN s, not after the Autopilot's longer wait
		bot.stuckFor = (bot.stuckFor or 0) + dt
		if bot.stuckFor > Constants.BOTS.RACE.STUCK_RESPAWN then
			bot.stuckFor = 0
			respawn(bot, biome, startY)
			return
		end
		bot.blockedFor = (bot.blockedFor or 0) + dt
		if bot.blockedFor > 1 then
			bot.blockedFor = -3
			local hit = workspace:Raycast(pos, primary.CFrame.LookVector * 8, bot.rayParams)
			Telemetry.record("bot_blocked", { userId = bot.id, s = math.floor(bot.s), x = math.floor(pos.X), z = math.floor(pos.Z),
				part = hit and hit.Instance and hit.Instance:GetFullName() or "?" })
		end
	else
		bot.stuckFor = 0
		if (bot.blockedFor or 0) > 0 then bot.blockedFor = 0 end
	end
end

--- Drives every bot each Heartbeat until RaceBots.clear().
function RaceBots.run(biome)
	if _conn then _conn:Disconnect() end
	local cfg = BiomeConfig[biome] or {}
	local startY = cfg.raceStartY or 2
	local killY = cfg.killPlaneY or -50
	local triggers = {}
	for _, tag in ipairs(TRIGGERS) do
		for _, p in ipairs(CollectionService:GetTagged(tag)) do table.insert(triggers, p) end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = triggers
	local hazards, hazardsAt = {}, -1
	_conn = RunService.Heartbeat:Connect(function(dt)
		-- the hazard scan is shared by all bots, 4 times a second
		if os.clock() - hazardsAt > 0.25 then
			hazards, hazardsAt = RoadHazards.all(), os.clock()
		end
		local lead = _otherProgress and _otherProgress() or nil
		for _, b in ipairs(RaceBots.list) do
			if not lead or b.s > lead then lead = math.max(lead or 0, b.s) end
		end
		for _, bot in ipairs(RaceBots.list) do
			local ok, err = pcall(step, bot, biome, dt, overlap, startY, killY, lead, hazards)
			if not ok then
				warn("[RaceBots] " .. tostring(err))
				bot.finished = true
			end
		end
	end)
end

--- Best progress among bots still driving (catch-up for players).
function RaceBots.bestProgress()
	local best = nil
	for _, b in ipairs(RaceBots.list) do
		if not best or b.s > best then best = b.s end
	end
	return best
end

--- A shove for bot `id` (what a player's client gets as RemoteEvents.CarImpact).
function RaceBots.knock(id, dvx, dvz, spin)
	for _, b in ipairs(RaceBots.list) do
		if b.id == id and b.primary and b.primary.Parent then
			local look = b.primary.CFrame.LookVector
			VehicleController.knock(b.drive, dvx or 0, dvz or 0, spin or 0, look.X, look.Z, b.seat and b.seat.MaxSpeed or 60)
			return true
		end
	end
	return false
end

function RaceBots.clear()
	if _conn then _conn:Disconnect(); _conn = nil end
	for _, b in ipairs(RaceBots.list) do
		if b.model and b.model.Parent then b.model:Destroy() end
		local d = b.proxy and SessionManager.getData(b.proxy)
		if d and d.vehicleModel == b.model then d.vehicleModel = nil end
	end
	RaceBots.list = {}
end

return RaceBots
