-- RaceSim.lua
-- Drives simulated cars around a race track (FOREST, OCEAN or SKY) with REAL Roblox physics and
-- reports where they slow down, get stuck, respawn or finish.
--
-- Two stepping modes:
--   "step"      Edit mode (plugin / MCP run_code). Calls
--               workspace:StepPhysics(dt, vehicleParts) in a loop, so a 3-minute
--               race takes seconds. Requires plugin security.
--   "heartbeat" Inside a running session (StudioTestService Run mode, see
--               Runner.runRace{ mode = "run" }). Physics runs in real time and
--               the sim drives on every Heartbeat.
--
-- The cars are built by the real VehicleBuilder and driven by the shared
-- Autopilot → VehicleController path. RacingManager is NOT running, so track
-- effects (mud, slow zones, boost pads, boost) are emulated with
-- SpeedModifiers using the same constants. There is no seated character: an
-- optional ballast part stands in for its mass (opts.driverMass).
--
-- Usage (edit mode, e.g. MCP run_code):
--   return require(game.ServerScriptService.TestHarness.Runner).runRace({
--     profiles = { "average" }, seconds = 120,
--   })

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Constants        = require(Shared.Constants)
local ItemConfig       = require(Shared.ItemConfig)
local VehicleStats     = require(Shared.VehicleStats)
local TrackGeometry    = require(Shared.TrackGeometry)
local VehicleController = require(Shared.VehicleController)
local Autopilot        = require(Shared.Autopilot)
local SpeedModifiers   = require(Shared.SpeedModifiers)
local RaceProgress     = require(Shared.RaceProgress)
local BiomeConfig      = require(ServerScriptService.Modules.BiomeConfig)
local MapVisibility    = require(ServerScriptService.Modules.MapVisibility)
local VehicleBuilder   = require(ServerScriptService.Modules.VehicleBuilder)

local RaceSim = {}

RaceSim.TRACKS = {
	FOREST = { data = Shared.Tracks.ForestTrack, builder = ServerScriptService.Modules.Maps.ForestMap },
	OCEAN  = { data = Shared.Tracks.OceanTrack,  builder = ServerScriptService.Modules.Maps.OceanMap },
	SKY    = { data = Shared.Tracks.SkyTrack,    builder = ServerScriptService.Modules.Maps.SkyMap },
}

-- Named test cars (slots), matching the representative builds the offline
-- report picks (slowest / median / fastest top speed for FOREST). The same
-- slots are used on every biome; stats are derived for the chosen biome.
RaceSim.CARS = {
	slowest = { BODY = "Microwave", ENGINE = "Fan", SPECIAL = "Pizza" },
	p50     = { BODY = "Shopping Cart", ENGINE = "Magnifying Glass", SPECIAL = "Toilet Paper" },
	fastest = { BODY = "Skateboard", ENGINE = "Kettle", SPECIAL = "Umbrella", MOBILITY = "Alarm Clock" },
}

local TRIGGER_TAGS = { "Checkpoint1", "Checkpoint2", "FinishLine", "BoostPad", "DriftCorner", "MudZone", "SlowZone" }

local function round(n, d)
	local m = 10 ^ (d or 1)
	return math.floor(n * m + 0.5) / m
end

local function statsFor(slots, biome)
	local s = VehicleStats.calculate(
		slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	s = VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	s.slotAssignments = slots
	return s
end

--- Builds the map and applies the RACING visibility state.
-- visibility: "shipped" (MapVisibility exactly as the server runs it) or
-- "intended" (authored CanCollide/Transparency restored).
function RaceSim.prepareMap(biome, visibility)
	local entry = RaceSim.TRACKS[biome]
	assert(entry, "RaceSim: no track data for " .. tostring(biome))
	local map = require(entry.builder).build()
	local maps = workspace:FindFirstChild("Maps")
	MapVisibility.cacheOriginals(maps)
	MapVisibility.applyRacingState(maps, map)
	if visibility == "intended" then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") then
				local cc = d:GetAttribute("OriginalCanCollide")
				local tr = d:GetAttribute("OriginalTransparency")
				if cc ~= nil then d.CanCollide = cc end
				if tr ~= nil then d.Transparency = tr end
			end
		end
		MapVisibility.setSubVisible(map, "FarmArea", false)
	end
	return map, require(entry.data)
end

local function triggerParts(map)
	local out = {}
	for _, tag in ipairs(TRIGGER_TAGS) do
		for _, p in ipairs(CollectionService:GetTagged(tag)) do
			if p:IsDescendantOf(map) then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function vehicleParts(model)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

local function addBallast(model, mass)
	if not mass or mass <= 0 then return end
	local primary = model.PrimaryPart
	local ballast = Instance.new("Part")
	ballast.Name = "HarnessBallast"
	ballast.Size = Vector3.new(1, 1, 1)
	ballast.Transparency = 1
	ballast.CanCollide = false
	ballast.CanQuery = false
	-- mass = density * volume (1 stud³)
	ballast.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(mass, 0.01, 100), 0.3, 0.5)
	ballast.CFrame = primary.CFrame * CFrame.new(0, 1, 0)
	ballast.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primary
	weld.Part1 = ballast
	weld.Parent = ballast
end

--- Runs one car. Returns a JSON-friendly result table.
-- opts: {
--   biome = "FOREST", profile = "average", car = "p50" | slots table,
--   seconds = 180, dt = 1/60, mode = "step" | "heartbeat",
--   visibility = "shipped" | "intended", respawn = "legacy" | "track",
--   seed = 1, slot = 3, driverMass = 0, sampleEvery = 0.5, yieldEvery = 600,
--   map = (prepared map), track = (track data)
-- }
function RaceSim.runOne(opts)
	local biome = opts.biome or "FOREST"
	local dt = opts.dt or (1 / 60)
	local seconds = opts.seconds or Constants.RACING_TIMEOUT
	local mode = opts.mode or "step"
	local respawnMode = opts.respawn or "legacy"
	local map, track = opts.map, opts.track
	if not map then
		map, track = RaceSim.prepareMap(biome, opts.visibility or "shipped")
	end
	local geo = TrackGeometry.new(track.nodes, track.width)

	local slots = type(opts.car) == "table" and opts.car or RaceSim.CARS[opts.car or "p50"]
	local stats = statsFor(slots, biome)

	-- Start slot on the grid, facing down the track
	local slot = opts.slot or 3
	local cols, rows = track.startGrid.cols, track.startGrid.rows
	local col = ((slot - 1) % #cols) + 1
	local row = math.ceil(slot / #cols)
	local startY = BiomeConfig[biome].raceStartY or 2
	local yaw0 = geo:yawAt(0)
	local spawnCF = CFrame.new(cols[col], startY, rows[row] or rows[1]) * CFrame.Angles(0, yaw0, 0)

	local model = VehicleBuilder.build(stats, biome, spawnCF, slots)
	model.Name = "HarnessCar_" .. (opts.profile or "average")
	addBallast(model, opts.driverMass)
	model.Parent = workspace
	local primary = model.PrimaryPart
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local parts = vehicleParts(model)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = triggerParts(map)

	local ap = Autopilot.new(geo, Autopilot.PROFILES[opts.profile or "average"], opts.seed or 1)
	local driveState = VehicleController.newState()
	local mods = SpeedModifiers.new(seat.MaxSpeed)

	local res = {
		engine = mode == "step" and "studio-stepphysics" or "studio-heartbeat",
		profile = opts.profile or "average", car = opts.car or "p50",
		maxSpeed = seat.MaxSpeed, turnSpeed = seat.TurnSpeed, mass = round(primary.AssemblyMass, 2),
		visibility = opts.visibility or "shipped", respawnMode = respawnMode,
		finished = false, checkpoints = {}, respawns = {}, blocked = {}, samples = {},
		effects = {}, airborne = 0, trackLength = round(geo.length, 0),
	}

	local cp = { false, false }
	local inside = {}
	local padCooldown = {}
	local gauge, boostCooldownEnd = 1, 0
	local lastSample, blockedFor = -1, 0
	local maxS = 0
	local t = 0
	local steps = math.floor(seconds / dt)

	local function respawn(reason, s)
		local pos = primary.Position
		local lx, ly, lz, lyaw = RaceProgress.respawnPoint(biome, pos.X, pos.Z, startY, ap.segHint)
		local entry = { t = round(t, 2), reason = reason, s = math.floor(s), from = { x = round(pos.X), z = round(pos.Z) } }
		local target
		if respawnMode == "legacy" then
			-- exactly what RacingManager does
			target = CFrame.new(lx, ly, lz) * CFrame.Angles(0, lyaw, 0)
		else
			local ts = math.max(s - RaceProgress.RESPAWN_STEP_BACK, 0)
			local px, pz = geo:pointAt(ts)
			target = CFrame.new(px, ly, pz) * CFrame.Angles(0, geo:yawAt(ts), 0)
		end
		local check = geo:project(target.Position.X, target.Position.Z)
		entry.to = { x = round(target.Position.X), z = round(target.Position.Z), onTrack = check.dist <= track.width / 2 - 2 }
		primary.Anchored = true
		model:PivotTo(target)
		primary.AssemblyLinearVelocity = Vector3.zero
		primary.AssemblyAngularVelocity = Vector3.zero
		primary.Anchored = false
		VehicleController.reset(driveState)
		table.insert(res.respawns, entry)
		ap:resetTracking()
	end

	local function step()
		t += dt
		local pos = primary.Position
		local vel = primary.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
		local isSky = primary:FindFirstChild("HoverPosition") ~= nil
		local keys, info = ap:update({
			x = pos.X, z = pos.Z, yaw = yaw, speed = speed,
			forward = vel:Dot(primary.CFrame.LookVector),
			maxSpeed = seat.MaxSpeed, turnSpeed = VehicleController.turnRate(seat.TurnSpeed, isSky), t = t,
		})
		if info.s > maxS then maxS = info.s end

		-- Triggers touched this step (spatial query; works with CanCollide off)
		local touching = {}
		for _, p in ipairs(workspace:GetPartsInPart(primary, overlap)) do touching[p] = true end
		local nowMud, nowSlow = false, false
		for p in pairs(touching) do
			if CollectionService:HasTag(p, "Checkpoint1") and not cp[1] then
				cp[1] = true
				table.insert(res.checkpoints, { index = 1, t = round(t, 2) })
			elseif CollectionService:HasTag(p, "Checkpoint2") and cp[1] and not cp[2] then
				cp[2] = true
				table.insert(res.checkpoints, { index = 2, t = round(t, 2) })
			elseif CollectionService:HasTag(p, "FinishLine") and cp[1] and cp[2] then
				res.finished = true
				res.time = round(t, 2)
			elseif CollectionService:HasTag(p, "BoostPad") and p.Transparency < 0.75 then
				if (padCooldown[p] or 0) <= t then
					padCooldown[p] = t + 5
					mods:set("pad", 1.4, t + 2)
				end
			elseif CollectionService:HasTag(p, "DriftCorner") and not inside[p] then
				gauge = math.min(1, gauge + Constants.DRIFT_CHARGE_PER_CORNER)
			elseif CollectionService:HasTag(p, "MudZone") then
				nowMud = true
			elseif CollectionService:HasTag(p, "SlowZone") then
				nowSlow = true
			end
		end
		inside = touching
		if nowMud then mods:set("mud", Constants.MUD_SPEED_MULT) else mods:remove("mud") end
		if nowSlow then mods:set("slow", Constants.SLOW_ZONE_MULT) else mods:remove("slow") end
		if gauge >= 1 and t >= boostCooldownEnd and math.abs(info.err) < 0.1 and keys.W then
			gauge = 0
			boostCooldownEnd = t + Constants.BOOST_COOLDOWN
			mods:set("boost", Constants.BOOST_MULTIPLIER, t + (stats.boostDuration or 2))
		end
		local maxSpeed = mods:value(t)

		-- Respawn when the driver gives up, or the car fell off the world
		if info.respawn then
			respawn("stuck", info.s)
			return
		end
		if pos.Y < (BiomeConfig[biome].killPlaneY or -50) then
			respawn("fell", info.s)
			return
		end

		-- Drive exactly like RacingClient
		local input = VehicleController.readKeys(keys)
		local cmd = VehicleController.command(input, {
			maxSpeed = maxSpeed, turnSpeed = seat.TurnSpeed, isSky = isSky,
			torque = seat.Torque, dt = dt, actualForward = vel:Dot(primary.CFrame.LookVector),
		}, driveState)
		VehicleController.apply(primary, cmd, {
			biome = biome, altitudeDt = dt,
			raycast = function(origin, direction)
				return workspace:Raycast(origin, direction, rayParams)
			end,
		})

		-- Blocked: commanding speed but not moving → name what is in front
		if cmd.forwardSpeed > 10 and speed < cmd.forwardSpeed * 0.25 then
			blockedFor += dt
			if blockedFor > 0.5 then
				blockedFor = -2 -- report again after a while if still blocked
				local hit = workspace:Raycast(pos, primary.CFrame.LookVector * 6, rayParams)
				table.insert(res.blocked, {
					t = round(t, 2), s = math.floor(info.s), x = round(pos.X), z = round(pos.Z),
					part = hit and hit.Instance and hit.Instance:GetFullName() or "?",
				})
			end
		elseif blockedFor > 0 then
			blockedFor = 0
		end

		local ground = workspace:Raycast(pos, Vector3.new(0, -8, 0), rayParams)
		if not ground then res.airborne += dt end

		if t - lastSample >= (opts.sampleEvery or 0.5) then
			lastSample = t
			table.insert(res.samples, { t = round(t, 2), x = round(pos.X), z = round(pos.Z), s = math.floor(info.s), speed = round(speed) })
		end
	end

	local yieldEvery = opts.yieldEvery or 600
	if mode == "step" then
		for i = 1, steps do
			step()
			if res.finished then break end
			workspace:StepPhysics(dt, parts)
			if i % yieldEvery == 0 then task.wait() end
		end
	else
		local done = false
		local conn
		conn = RunService.Heartbeat:Connect(function(frameDt)
			if done then return end
			dt = frameDt
			step()
			if res.finished or t >= seconds then
				done = true
				conn:Disconnect()
			end
		end)
		while not done do task.wait(0.1) end
	end

	res.maxProgress = math.floor(maxS)
	res.endT = round(t, 2)
	res.airborne = round(res.airborne, 2)
	if not opts.keepCar then model:Destroy() end
	return res
end

--- Runs several profiles on one prepared map. In "heartbeat" mode the cars
-- run concurrently (one coroutine each); in "step" mode one after another.
function RaceSim.run(opts)
	opts = opts or {}
	local biome = opts.biome or "FOREST"
	local visibility = opts.visibility or "shipped"
	local map, track = RaceSim.prepareMap(biome, visibility)
	local profiles = opts.profiles or { "expert", "average", "novice" }
	local results = {}
	local started = os.clock()
	if (opts.mode or "step") == "heartbeat" then
		local pending = #profiles
		for i, profile in ipairs(profiles) do
			task.spawn(function()
				local o = table.clone(opts)
				o.profile, o.map, o.track, o.slot, o.seed = profile, map, track, i, (opts.seed or 1) + i
				results[i] = RaceSim.runOne(o)
				pending -= 1
			end)
		end
		while pending > 0 do task.wait(0.2) end
	else
		for i, profile in ipairs(profiles) do
			local o = table.clone(opts)
			o.profile, o.map, o.track, o.slot, o.seed = profile, map, track, 3, (opts.seed or 1) + i
			results[i] = RaceSim.runOne(o)
		end
	end
	return {
		biome = biome, visibility = visibility, wallSeconds = round(os.clock() - started, 1),
		results = results,
	}
end

--- One line per car, for printing in MCP / Output.
function RaceSim.summarize(report)
	local lines = { string.format("RaceSim %s (%s) — %ss wall time", report.biome, report.visibility, report.wallSeconds) }
	for _, r in ipairs(report.results) do
		local outcome = r.finished and (r.time .. "s") or string.format("stopped at %d/%d", r.maxProgress, r.trackLength)
		local firstBlock = r.blocked[1]
		table.insert(lines, string.format("  %-8s car=%s max=%.0f mass=%s → %s | CPs %d | respawns %d | blocked %d%s",
			r.profile, tostring(r.car), r.maxSpeed, tostring(r.mass), outcome, #r.checkpoints, #r.respawns, #r.blocked,
			firstBlock and (" (first: " .. firstBlock.part .. " at s=" .. firstBlock.s .. ")") or ""))
	end
	return table.concat(lines, "\n")
end

return RaceSim
