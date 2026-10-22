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
local PhysicsService    = game:GetService("PhysicsService")

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
local TerrainPainter   = require(ServerScriptService.Modules.TerrainPainter)

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

RaceSim.MAP_WAIT = 20

-- In a running session the MapBuilders scripts build every map at start, and
-- TrackKit.newMap replaces a map of the same name. A map RaceSim built first
-- was then destroyed mid-race with its checkpoint triggers (cars drove the
-- whole track and never finished; Studio 2026-10-20). So in a running session
-- wait for the server's build and use it.
-- All three builders must have run, not only this biome's: every map shares
-- world coordinates, and a map built after applyRacingState hid the others
-- stayed solid (OCEAN boats stopped against ForestMap walls; Studio 2026-10-20).
local function serverMap(biome)
	local function allBuilt()
		for b in pairs(RaceSim.TRACKS) do
			if ServerScriptService:GetAttribute("MapBuilt_" .. b) == nil then return false end
		end
		return true
	end
	local waited = 0
	while not allBuilt() and waited < RaceSim.MAP_WAIT do
		task.wait(0.2)
		waited += 0.2
	end
	local maps = workspace:FindFirstChild("Maps")
	return maps and maps:FindFirstChild(MapVisibility.mapName(biome))
end

--- Builds (or, in a running session, takes the server's) map and applies the
-- RACING visibility state.
-- visibility: "shipped" (MapVisibility exactly as the server runs it) or
-- "intended" (authored CanCollide/Transparency restored).
-- mode: "heartbeat" (running session: wait for and reuse the server's map)
-- or "step" (edit mode: build it).
function RaceSim.prepareMap(biome, visibility, mode)
	local entry = RaceSim.TRACKS[biome]
	assert(entry, "RaceSim: no track data for " .. tostring(biome))
	local map = (mode == "heartbeat" and serverMap(biome)) or require(entry.builder).build()
	TerrainPainter.paint(biome, true)
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

-- Harness cars in "heartbeat" mode share one world. Unless opts.contact is
-- true they are put in a collision group that ignores itself, so a slow car
-- on the grid does not block the others (each car's run must stay comparable
-- with the offline single-car sim). runMatch is the place for car contact.
RaceSim.CAR_GROUP = "HarnessCars"

local function ghostCars(parts)
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(RaceSim.CAR_GROUP) then
			PhysicsService:RegisterCollisionGroup(RaceSim.CAR_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(RaceSim.CAR_GROUP, RaceSim.CAR_GROUP, false)
	end)
	if not ok then return end
	for _, p in ipairs(parts) do p.CollisionGroup = RaceSim.CAR_GROUP end
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
--   contact = false (true: harness cars collide with each other),
--   spawn = { s = 1200, lateral = 0, yawOffset = 0 } (start mid-track instead
--     of on the grid; lateral is + right of travel, yawOffset in degrees),
--   stopAt = progress at which the run counts as done (with spawn: escape tests),
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
		map, track = RaceSim.prepareMap(biome, opts.visibility or "shipped", mode)
	end
	local geo = TrackGeometry.new(track.nodes, track.width, track.trackTop)

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
	if opts.spawn then
		local sp = opts.spawn
		local px, pz = geo:offsetPoint(sp.s or 0, sp.lateral or 0)
		local yaw = geo:yawAt(sp.s or 0) + math.rad(sp.yawOffset or 0)
		local rise = geo:heightAt(sp.s or 0) - (track.trackTop or 0)
		spawnCF = CFrame.new(px, startY + rise + (sp.lift or 0), pz) * CFrame.Angles(0, yaw, 0)
	end

	local model = VehicleBuilder.build(stats, biome, spawnCF, slots)
	model.Name = "HarnessCar_" .. (opts.profile or "average")
	addBallast(model, opts.driverMass)
	model.Parent = workspace
	local primary = model.PrimaryPart
	-- spawned part-way up a raised road (escape cases): the held height
	-- already includes the road's rise there (else the first frame adds it
	-- again and the car shoots up to the lid)
	VehicleController.resetRide(primary, geo:heightAt(opts.spawn and opts.spawn.s or 0) - (track.trackTop or 0))
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local parts = vehicleParts(model)
	if not opts.contact then ghostCars(parts) end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.RespectCanCollide = true   -- like RacingClient: only solid ground carries the car

	local triggers = triggerParts(map)
	assert(#triggers > 0, "RaceSim: the map has no trigger parts (checkpoints, finish)")
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = triggers

	local ap = Autopilot.new(geo, Autopilot.PROFILES[opts.profile or "average"], opts.seed or 1)
	local driveState = VehicleController.newState()
	local mods = SpeedModifiers.new(seat.MaxSpeed, Constants.SPEED_STACK_MAX)

	local res = {
		engine = mode == "step" and "studio-stepphysics" or "studio-heartbeat",
		profile = opts.profile or "average", car = opts.car or "p50",
		maxSpeed = seat.MaxSpeed, turnSpeed = seat.TurnSpeed, mass = round(primary.AssemblyMass, 2),
		visibility = opts.visibility or "shipped", respawnMode = respawnMode,
		spawn = opts.spawn, stopAt = opts.stopAt, reached = nil,
		finished = false, checkpoints = {}, respawns = {}, blocked = {}, samples = {},
		effects = {}, airborne = 0, trackLength = round(geo.length, 0),
		maxTilt = 0, topSpeed = 0, slots = slots,
	}

	local cp = { false, false }
	local inside = {}
	local padCooldown = {}
	local gauge, boostCooldownEnd = 1, 0
	local lastSample, blockedFor = -1, 0
	local maxS = 0
	local riseSeg = nil   -- segment hint for the road height (OCEAN / SKY ride height)
	local t = 0
	local steps = math.floor(seconds / dt)

	local function respawn(reason, s)
		local pos = primary.Position
		local lx, ly, lz, lyaw = RaceProgress.respawnPoint(biome, pos.X, pos.Z, startY, ap.segHint, pos.Y)
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
		VehicleController.resetRide(primary, (RaceProgress.roadRise(biome, target.Position.X, target.Position.Z, nil, target.Position.Y)))
		riseSeg = nil
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
			x = pos.X, z = pos.Z, y = pos.Y, yaw = yaw, speed = speed,
			forward = vel:Dot(primary.CFrame.LookVector),
			maxSpeed = seat.MaxSpeed, turnSpeed = VehicleController.turnRate(seat.TurnSpeed, isSky), t = t,
			isSky = isSky, biome = biome, travelYaw = driveState.travelYaw,
		})
		if info.s > maxS then maxS = info.s end
		if opts.stopAt and not res.reached and info.s >= opts.stopAt then
			res.reached = round(t, 2)
		end

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
		if pos.Y < (BiomeConfig[biome].killPlaneY or -50)
			or pos.Y < geo:heightAt(info.s) - RaceProgress.FALL_BELOW then
			respawn("fell", info.s)
			return
		end

		-- Drive exactly like RacingClient (drift rule and mini-turbo included)
		local input = VehicleController.readKeys(keys)
		local change, level = VehicleController.updateDrift(driveState, input, speed, maxSpeed, isSky)
		if change == "enter" then
			res.drifts = (res.drifts or 0) + 1
		elseif level then
			local tb = Constants.DRIVE.DRIFT_TURBO[level]
			mods:set("driftTurbo", tb.mult, t + tb.duration)
			res.turbos = (res.turbos or 0) + 1
			maxSpeed = mods:value(t)
		end
		local _, yawNow = primary.CFrame:ToEulerAnglesYXZ()
		local tdx, tdz = VehicleController.travelDir(driveState, yawNow)
		local cmd = VehicleController.command(input, {
			maxSpeed = maxSpeed, turnSpeed = seat.TurnSpeed, isSky = isSky,
			drifting = driveState.drifting, biome = biome, yaw = yawNow,
			torque = seat.Torque, dt = dt, actualForward = vel.X * tdx + vel.Z * tdz,
		}, driveState)
		local rise = nil
		if biome ~= "FOREST" then
			rise, riseSeg = RaceProgress.roadRise(biome, pos.X, pos.Z, riseSeg, pos.Y)
		end
		VehicleController.apply(primary, cmd, {
			biome = biome, altitudeDt = dt, roadRise = rise,
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

		local tilt = math.deg(math.acos(math.clamp(primary.CFrame.UpVector.Y, -1, 1)))
		if tilt > res.maxTilt then res.maxTilt = round(tilt, 1) end
		if speed > res.topSpeed then res.topSpeed = round(speed, 1) end

		local ground = workspace:Raycast(pos, Vector3.new(0, -8, 0), rayParams)
		if not ground then res.airborne += dt end

		if t - lastSample >= (opts.sampleEvery or 0.5) then
			lastSample = t
			table.insert(res.samples, { t = round(t, 2), x = round(pos.X), z = round(pos.Z), s = math.floor(info.s), speed = round(speed),
				y = round(pos.Y, 1), roadY = round(geo:heightAt(info.s), 1), hit = ground and ground.Instance.Name or nil,
				hitY = ground and round(ground.Position.Y, 1) or nil })
		end
	end

	local yieldEvery = opts.yieldEvery or 600
	if mode == "step" then
		for i = 1, steps do
			step()
			if res.finished or res.reached then break end
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
			if res.finished or res.reached or t >= seconds then
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

--- Escape cases: cars dropped where a driver can get stuck, each must drive
-- ESCAPE_GAIN studs further along the track within ESCAPE_SECONDS.
--   wall-left / wall-right  nose into the wall at 70°, touching it
--   backwards               on the centerline facing the wrong way
--   feature                 on each jump ramp, mud zone and drift corner, angled 30°
-- One position every ESCAPE_SPACING studs of track, plus every feature.
RaceSim.ESCAPE_SPACING = 500
RaceSim.ESCAPE_GAIN    = 120
RaceSim.ESCAPE_SECONDS = 25

function RaceSim.escapeCases(biome, track)
	track = track or require(RaceSim.TRACKS[biome].data)
	local geo = TrackGeometry.new(track.nodes, track.width, track.trackTop)
	local edge = track.width / 2 - 4
	local cases = {}
	local function add(label, s, lateral, yawOffset)
		if s + RaceSim.ESCAPE_GAIN > geo.length - 20 then return end
		table.insert(cases, { label = label, spawn = { s = math.floor(s), lateral = lateral, yawOffset = yawOffset } })
	end
	local s = 150
	while s < geo.length do
		add(string.format("wall-left@%d", s), s, -edge, 70)
		add(string.format("wall-right@%d", s), s, edge, -70)
		add(string.format("backwards@%d", s), s, 0, 180)
		s += RaceSim.ESCAPE_SPACING
	end
	for _, key in ipairs({ "jumpRamps", "mudZones", "driftCorners" }) do
		for i, f in ipairs(track[key] or {}) do
			local p = geo:project(f[1], f[2])
			add(string.format("%s%d", key, i), math.max(p.s - 10, 0), p.lateral, 30)
		end
	end
	return cases
end

--- Vehicle cases: many item combinations driven from the grid for
-- VEHICLE_DISTANCE studs (the look must not change how a car drives).
-- Every BODY item once (with random other slots), a car with no items and
-- `extra` fully random builds. Deterministic for a given seed.
RaceSim.VEHICLE_DISTANCE = 700
RaceSim.VEHICLE_SECONDS = 45

function RaceSim.vehicleCases(biome, extra, seed)
	local ItemTypes = require(Shared.ItemTypes)
	local byType, all = { BODY = {}, ENGINE = {}, SPECIAL = {} }, {}
	for _, it in ipairs(ItemTypes.ALL) do
		table.insert(byType[it.slotType], it.name)
		table.insert(all, it.name)
	end
	local rng = Random.new(seed or 1)
	local function pick(list) return list[rng:NextInteger(1, #list)] end
	local function full(body)
		return { BODY = body or pick(byType.BODY), ENGINE = pick(byType.ENGINE), SPECIAL = pick(byType.SPECIAL),
			MOBILITY = pick(all), HEAD = pick(all), TAIL = pick(all) }
	end
	local cases = { { label = "no items", car = {} } }
	for _, body in ipairs(byType.BODY) do
		table.insert(cases, { label = body, car = full(body) })
	end
	for i = 1, extra or 6 do
		table.insert(cases, { label = "random" .. i, car = full() })
	end
	for i, c in ipairs(cases) do
		c.stopAt = RaceSim.VEHICLE_DISTANCE
		c.seconds = RaceSim.VEHICLE_SECONDS
		c.slot = (i - 1) % 10 + 1
	end
	return cases
end

--- Runs several profiles on one prepared map. In "heartbeat" mode the cars
-- run concurrently (one coroutine each); in "step" mode one after another.
function RaceSim.run(opts)
	opts = opts or {}
	local biome = opts.biome or "FOREST"
	local visibility = opts.visibility or "shipped"
	local map, track = RaceSim.prepareMap(biome, visibility, opts.mode or "step")
	local profiles = opts.profiles or { "expert", "average", "novice" }
	local results = {}
	local started = os.clock()
	-- opts.cases: list of per-car overrides ({ label, spawn, stopAt, seconds,
	-- profile }) or "escape" for RaceSim.escapeCases. One car per case.
	local cases = opts.cases
	if cases == "vehicles" then
		cases = RaceSim.vehicleCases(biome, opts.extra, opts.seed)
	elseif cases == "escape" then
		cases = RaceSim.escapeCases(biome, track)
		for _, c in ipairs(cases) do
			c.stopAt = c.spawn.s + RaceSim.ESCAPE_GAIN
			c.seconds = opts.seconds or RaceSim.ESCAPE_SECONDS
		end
	end
	if cases then
		local function runCase(i, c)
			local o = table.clone(opts)
			o.cases = nil
			for k, v in pairs(c) do o[k] = v end
			o.profile = c.profile or (opts.profiles and opts.profiles[1]) or "average"
			o.map, o.track, o.seed = map, track, (opts.seed or 1) + i
			local r = RaceSim.runOne(o)
			r.label = c.label or ("case" .. i)
			return r
		end
		if (opts.mode or "step") == "heartbeat" then
			local pending = #cases
			for i, c in ipairs(cases) do
				task.spawn(function()
					local ok, r = pcall(runCase, i, c)
					results[i] = ok and r or { label = c.label, error = tostring(r), blocked = {}, respawns = {}, checkpoints = {} }
					pending -= 1
				end)
			end
			while pending > 0 do task.wait(0.2) end
		else
			for i, c in ipairs(cases) do results[i] = runCase(i, c) end
		end
		return {
			biome = biome, visibility = visibility, wallSeconds = round(os.clock() - started, 1),
			kind = (opts.cases == "escape" or opts.cases == "vehicles") and "escape" or "cases",
			results = results,
		}
	end
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
	if report.kind == "escape" then
		local drove, respawned, stuck = 0, 0, {}
		for _, r in ipairs(report.results) do
			if r.reached and #r.respawns == 0 then drove += 1
			elseif r.reached or r.finished then respawned += 1
			else table.insert(stuck, string.format("%s (s=%s→%s)", tostring(r.label),
				r.spawn and tostring(r.spawn.s) or "?", tostring(r.maxProgress))) end
		end
		table.insert(lines, string.format("  cases %d: drove out %d, needed a respawn %d, stuck %d",
			#report.results, drove, respawned, #stuck))
		for _, r in ipairs(report.results) do
			if not (r.reached and #r.respawns == 0) then
				table.insert(lines, string.format("    %-22s %s respawns %d%s", tostring(r.label),
					r.reached and ("reached in " .. r.reached .. "s") or ("STUCK at " .. tostring(r.maxProgress)),
					#(r.respawns or {}), r.blocked and r.blocked[1] and (" blocked by " .. r.blocked[1].part) or ""))
			end
		end
		return table.concat(lines, "\n")
	end
	for _, r in ipairs(report.results) do
		local outcome = r.finished and (r.time .. "s") or string.format("stopped at %d/%d", r.maxProgress, r.trackLength)
		local firstBlock = r.blocked[1]
		table.insert(lines, string.format("  %-8s%s car=%s max=%.0f mass=%s → %s | CPs %d | respawns %d | blocked %d%s",
			r.profile, r.label and (" [" .. r.label .. "]") or "", tostring(r.car), r.maxSpeed, tostring(r.mass), outcome, #r.checkpoints, #r.respawns, #r.blocked,
			firstBlock and (" (first: " .. firstBlock.part .. " at s=" .. firstBlock.s .. ")") or ""))
	end
	return table.concat(lines, "\n")
end

return RaceSim
