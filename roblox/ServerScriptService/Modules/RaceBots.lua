-- RaceBots.lua
-- Server-driven racers that fill an empty grid on live servers: with fewer
-- than Constants.BOTS.FILL_TO racers, bots in random builds take the free
-- grid slots and race with the same driver (Shared/Autopilot) and drive rule
-- (Shared/VehicleController) as everyone else; the server owns their cars.
-- RacingManager starts them, counts their finishes and lists them in the
-- results (name, bot = true); they earn nothing and abilities ignore them.
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

local RaceBots = {}

RaceBots.ID_BASE = -100000   -- bot ids: ID_BASE - n (never a real UserId)
RaceBots.list = {}           -- bots of the current race

local _conn = nil
local _onFinish = nil
local _otherProgress = nil   -- fn() → best progress of the players (catch-up)
local _rng = Random.new()

local TRIGGERS = { "Checkpoint1", "Checkpoint2", "FinishLine" }

--- fn(bot) when a bot crosses the line (RacingManager).
function RaceBots.onFinish(fn) _onFinish = fn end
--- fn() → the leading player's progress, for the bots' catch-up.
function RaceBots.setLeaderProgress(fn) _otherProgress = fn end

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
		local slots = RaceBots.randomSlots(_rng)
		local stats = statsFor(slots, biome)
		local paints = Cosmetics.ITEMS.paint
		local paint = paints[_rng:NextInteger(1, #paints)]
		local model = VehicleBuilder.build(stats, biome, cf, slots, { paint = paint.body and paint or nil })
		local name = B.NAMES[((k - 1) % #B.NAMES) + 1]
		local id = RaceBots.ID_BASE - k
		model.Name = "Bot_" .. name
		model:SetAttribute("BotRacer", true)
		model:SetAttribute("BotName", name)
		model:SetAttribute("OwnerUserId", id)
		model.Parent = workspace
		local primary = model.PrimaryPart
		nameTag(primary, name)
		local hover = primary:FindFirstChild("HoverPosition")
		if hover then hover.Position = primary.Position end
		VehicleController.resetRide(primary, 0)
		RaceStart.hold(primary)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { model }
		rayParams.RespectCanCollide = true
		local profileName = B.PROFILES[((k - 1) % #B.PROFILES) + 1]
		local bot = {
			id = id, name = name, model = model, primary = primary,
			seat = model:FindFirstChildWhichIsA("VehicleSeat", true),
			ap = geo and Autopilot.new(geo, Autopilot.PROFILES[profileName] or Autopilot.PROFILES.average, k * 977),
			profile = profileName, drive = VehicleController.newState(), rayParams = rayParams,
			cp = { false, false }, s = 0, finished = false, riseSeg = nil, t = 0, owned = false,
		}
		table.insert(RaceBots.list, bot)
		Telemetry.record("race_bot", { id = id, name = name, profile = profileName, slots = table.clone(slots),
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
		bot.blockedFor = (bot.blockedFor or 0) + dt
		if bot.blockedFor > 1 then
			bot.blockedFor = -3
			local hit = workspace:Raycast(pos, primary.CFrame.LookVector * 8, bot.rayParams)
			Telemetry.record("bot_blocked", { userId = bot.id, s = math.floor(bot.s), x = math.floor(pos.X), z = math.floor(pos.Z),
				part = hit and hit.Instance and hit.Instance:GetFullName() or "?" })
		end
	elseif (bot.blockedFor or 0) > 0 then
		bot.blockedFor = 0
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

function RaceBots.clear()
	if _conn then _conn:Disconnect(); _conn = nil end
	for _, b in ipairs(RaceBots.list) do
		if b.model and b.model.Parent then b.model:Destroy() end
	end
	RaceBots.list = {}
end

return RaceBots
