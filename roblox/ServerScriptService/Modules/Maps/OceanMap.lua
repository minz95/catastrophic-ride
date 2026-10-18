-- OceanMap.lua (ModuleScript; called by MapBuilders/OceanMapBuilder.server.lua)
-- Builds the OCEAN biome map per racetrack spec §3:
--   - centerline (arc-S + island detour + reef U-bend + zigzag) Z = 600 → -1590
--   - 60-wide channel between continuous reef walls
--   - palm island inside the S2 arc, reef formation inside the S4 U-bend
--   - CP1 at the island arc apex, CP2 at the reef U-bend apex
--
-- Every position and size comes from ReplicatedStorage.Shared.Tracks.OceanTrack.
-- The parts all tracks share (walls, slow zones, triggers, finish, start)
-- come from Modules.Maps.TrackKit; this file adds the water and the scenery.
-- Resolves: Issue #9, #114, #129

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Tracks.OceanTrack)
local TrackKit = require(script.Parent.TrackKit)

local KIT = TrackKit.new(Track)
local _part, _tag = TrackKit.part, TrackKit.tag

local C = {
	WATER_DEEP  = Color3.fromRGB(8,   35,  90),
	WATER_MID   = Color3.fromRGB(12,  55,  140),
	WATER_TOP   = Color3.fromRGB(25,  105, 210),
	WATER_FOAM  = Color3.fromRGB(120, 200, 255),
	LANE        = Color3.fromRGB(80,  180, 255),
	DOCK        = Color3.fromRGB(140, 100, 60),
	SAND        = Color3.fromRGB(220, 190, 120),
	SAND_DRY    = Color3.fromRGB(235, 210, 150),
	BOOST       = Color3.fromRGB(60,  200, 255),
	BOOST_RING  = Color3.fromRGB(100, 240, 255),
	PALM_TRUNK  = Color3.fromRGB(120, 85,  40),
	PALM_LEAF   = Color3.fromRGB(60,  160, 50),
	BUOY_RED    = Color3.fromRGB(220, 50,  50),
	BUOY_WHITE  = Color3.fromRGB(240, 240, 240),
	DRIFT_GLOW  = Color3.fromRGB(40,  220, 255),
	REEF        = Color3.fromRGB(95,  75,  55),
	REEF_TOP    = Color3.fromRGB(220, 60,  60),
	GRASS       = Color3.fromRGB(80,  160, 70),
}

local MAT = {
	WATER  = Enum.Material.Glass,
	WOOD   = Enum.Material.Wood,
	SAND   = Enum.Material.Sand,
	NEON   = Enum.Material.Neon,
	LEAVES = Enum.Material.LeafyGrass,
	ROCK   = Enum.Material.Rock,
}

local WATER_Y = Track.trackTop   -- water surface Y
local LANE_W  = Track.width
local NODES   = Track.nodes

-- Track bounding box (farm included) plus margin: the water covers it.
local function _waterBox(margin)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, n in ipairs(NODES) do
		x0 = math.min(x0, n[1]); x1 = math.max(x1, n[1])
		z0 = math.min(z0, n[2]); z1 = math.max(z1, n[2])
	end
	z1 = math.max(z1, Track.farm.cz + Track.farm.size[2] / 2)
	return (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0 + margin * 2, z1 - z0 + margin * 2
end

-- ─── Water ───────────────────────────────────────────────────────────────────

local function _buildWater(root)
	local cx, cz, w, d = _waterBox(250)
	_part(root, {
		Name = "OceanFloor", Size = Vector3.new(w + 200, 2, d + 200),
		Position = Vector3.new(cx, WATER_Y - 14, cz),
		Color = C.WATER_DEEP, Material = Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false,
	})
	_part(root, {
		Name = "WaterVolume", Size = Vector3.new(w + 100, 12, d + 100),
		Position = Vector3.new(cx, WATER_Y - 8, cz),
		Color = C.WATER_MID, Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15, CanCollide = false, CastShadow = false,
	})
	_part(root, {
		Name = "WaterPlane", Size = Vector3.new(w, 4, d),
		Position = Vector3.new(cx, WATER_Y - 2, cz),
		Color = C.WATER_TOP, Material = MAT.WATER,
		Transparency = 0.35, CanCollide = false,
	})
	_part(root, {
		Name = "WaterShimmer", Size = Vector3.new(w, 0.25, d),
		Position = Vector3.new(cx, WATER_Y, cz),
		Color = C.WATER_FOAM, Material = MAT.NEON,
		Transparency = 0.82, CanCollide = false, CastShadow = false,
	})
	local zone = _part(root, {
		Name = "BuoyancyZone_Main", Size = Vector3.new(w, 8, d),
		Position = Vector3.new(cx, WATER_Y - 1, cz),
		CanCollide = false, Transparency = 1,
	})
	_tag(zone, "BuoyancyZone")
end

-- ─── Channel: tinted lane strip, reef walls, rough water ─────────────────────

local function _buildChannel(root)
	-- Tinted water on the lane (visual only; boats float on the water).
	local strips = Instance.new("Folder")
	strips.Name = "LaneStrips"
	strips.Parent = root
	KIT:buildSurface(strips, {
		name = "LaneStrip", jointName = "LaneStripJoint", thickness = 0.15, overlap = 2,
		color = C.LANE, material = MAT.NEON, physics = false,
	})
	for _, d in ipairs(strips:GetChildren()) do
		d.CanCollide = false
		d.CastShadow = false
		d.Transparency = 0.6
		d.Parent = root
	end
	strips:Destroy()
	KIT:buildWalls(root, {
		name = "ReefWall", color = C.REEF, material = MAT.ROCK,
		cap = { name = "ReefWallCap", color = C.REEF_TOP, material = MAT.NEON },
	})
	KIT:buildSlowZones(root, { color = C.WATER_FOAM, material = MAT.NEON, transparency = 0.65 })
end

-- ─── Buoys (decorative lane-edge markers, CanCollide false) ──────────────────

local function _buildCourseBuoys(root)
	local buoyIdx = 0
	for i = 2, #NODES - 1, 2 do
		buoyIdx += 1
		local cf = KIT:trackCF(NODES[i][1], WATER_Y + 2, NODES[i][2])
		local isRedSide = (buoyIdx % 2 == 0)
		for _, side in ipairs({ -1, 1 }) do
			local isRed = (side == 1) == isRedSide
			_part(root, {
				Name     = "Buoy_" .. buoyIdx .. (side > 0 and "R" or "L"),
				Size     = Vector3.new(2.5, 4, 2.5),
				CFrame   = cf * CFrame.new(side * (LANE_W / 2 - 6), 0, 0),
				Color    = isRed and C.BUOY_RED or C.BUOY_WHITE,
				Material = MAT.NEON, CanCollide = false, CastShadow = false,
			})
		end
	end
end

-- ─── Palm island (inside the S2 arc; blocks the straight-line cut) ──────────

local function _palm(root, rng, tx, tz, groundY, leaves)
	local h = rng:NextNumber(8, 14)
	_part(root, {
		Name = "PalmTrunk", Size = Vector3.new(1.2, h, 1.2),
		Position = Vector3.new(tx, groundY + h / 2, tz),
		Color = C.PALM_TRUNK, Material = MAT.WOOD, CanCollide = false,
	})
	if leaves then
		for i = 0, 4 do
			local angle = (i / 5) * math.pi * 2
			_part(root, {
				Name = "PalmLeaf", Size = Vector3.new(0.6, 0.3, 8),
				Color = C.PALM_LEAF, Material = MAT.LEAVES,
				CFrame = CFrame.new(tx + math.cos(angle) * 2, groundY + h + 0.5, tz + math.sin(angle) * 2)
					* CFrame.Angles(0, angle, math.rad(-20)),
				CanCollide = false,
			})
		end
	else
		_part(root, {
			Name = "PalmCanopy", Size = Vector3.new(6, 4, 6),
			Position = Vector3.new(tx, groundY + h + 1, tz),
			Color = C.PALM_LEAF, Material = MAT.LEAVES, CanCollide = false,
		})
	end
end

local function _buildPalmIsland(root)
	local isl = Track.palmIsland
	local cx, cz, w, d = isl.cx, isl.cz, isl.size[1], isl.size[2]
	_part(root, {
		Name = "Palm_IslandBase", Size = Vector3.new(w, 8, d),
		Position = Vector3.new(cx, WATER_Y - 2, cz),
		Color = C.SAND, Material = MAT.SAND,
	})
	-- Sand, not Grass: Material.Grass renders blades that stay visible on water.
	_part(root, {
		Name = "Palm_IslandTop", Size = Vector3.new(w - 15, 1.5, d - 20),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = C.SAND_DRY, Material = MAT.SAND,
	})
	local rng = Random.new(isl.seed)
	for _ = 1, isl.palms do
		_palm(root, rng, rng:NextNumber(cx - w / 2 + 15, cx + w / 2 - 15),
			rng:NextNumber(cz - d / 2 + 20, cz + d / 2 - 20), WATER_Y + 2.5, true)
	end
end

-- ─── Reef formation (inside the S4 U-bend) ───────────────────────────────────

local function _buildReefFormation(root)
	local reef = Track.reef
	local cx, cz = reef.cx, reef.cz
	_part(root, {
		Name = "ReefBase", Size = Vector3.new(reef.size[1], 6, reef.size[2]),
		Position = Vector3.new(cx, WATER_Y - 3, cz),
		Color = C.REEF, Material = MAT.ROCK,
	})
	local mid = (reef.spires + 1) / 2
	for i = 1, reef.spires do
		local sx = cx + (i - mid) * 14
		local sz = cz + math.sin(i) * reef.size[2] * 0.2
		_part(root, {
			Name = "ReefSpire_" .. i, Size = Vector3.new(8, 10, 8),
			Position = Vector3.new(sx, WATER_Y + 4, sz),
			Color = C.REEF, Material = MAT.ROCK,
		})
		_part(root, {
			Name = "ReefSpireTip_" .. i, Size = Vector3.new(4, 4, 4),
			Position = Vector3.new(sx, WATER_Y + 10, sz),
			Color = C.REEF_TOP, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
	end
end

-- ─── Triggers (TrackKit) ─────────────────────────────────────────────────────

local function _buildTriggers(root)
	KIT:buildDriftCorners(root, {
		visual = function(r, cf, i)
			_part(r, {
				Name = "WakeRing_" .. i, Size = Vector3.new(LANE_W - 4, 0.3, 42),
				CFrame = cf * CFrame.new(0, 0.3, 0),
				Color = C.DRIFT_GLOW, Material = MAT.NEON,
				CanCollide = false, CastShadow = false, Transparency = 0.5,
			})
		end,
	})
	KIT:buildJumpZones(root, {
		visual = function(r, cf, i)
			_part(r, {
				Name = "WaveRamp_" .. i, Size = Vector3.new(LANE_W - 12, 1.5, 14),
				CFrame = cf * CFrame.new(0, 1, 0),
				Color = C.WATER_FOAM, Material = MAT.NEON,
				CanCollide = false, CastShadow = false, Transparency = 0.3,
			})
		end,
	})
	KIT:buildBoostPads(root, { color = C.BOOST, ringColor = C.BOOST_RING })
	KIT:buildCheckpoints(root, { archHeight = 20 })
end

-- ─── Farm island (FARMING phase only; hidden during RACING) ──────────────────

local function _buildFarmIsland(root)
	local farm = Track.farm
	local cx, cz, w, d = farm.cx, farm.cz, farm.size[1], farm.size[2]
	_part(root, {
		Name = "FarmIsland", Size = Vector3.new(w, 6, d),
		Position = Vector3.new(cx, WATER_Y - 1, cz),
		Color = C.SAND, Material = MAT.SAND,
	})
	-- SmoothPlastic, not Grass: grass blades survive the RACING hide.
	_part(root, {
		Name = "FarmGrass", Size = Vector3.new(w - 20, 1, d - 30),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = C.GRASS, Material = Enum.Material.SmoothPlastic,
	})
	for _, rz in ipairs({ cz - 50, cz + 50 }) do
		for _, ox in ipairs({ -60, -30, 0, 30, 60 }) do
			local sp = _part(root, {
				Name = "FarmSpawnPoint", Size = Vector3.new(4, 0.5, 4),
				Position = Vector3.new(cx + ox, WATER_Y + 3.5, rz),
				Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
				CanCollide = false, Transparency = 0.5,
			})
			_tag(sp, "FarmSpawn")
		end
	end
	local rng = Random.new(farm.seed)
	for _ = 1, farm.palms do
		_palm(root, rng, rng:NextNumber(cx - w / 2 + 20, cx + w / 2 - 20),
			rng:NextNumber(cz - d / 2 + 30, cz + d / 2 - 30), WATER_Y + 2.5, false)
	end
end

-- ─── Start dock + grid, finish (TrackKit) ────────────────────────────────────

local function _buildStartAndFinish(root)
	local dock = Track.startDock
	_part(root, {
		Name = "StartDock", Size = Vector3.new(LANE_W - 6, 1, dock.length),
		Position = Vector3.new(0, WATER_Y + 0.5, dock.z),
		Color = C.DOCK, Material = MAT.WOOD,
	})
	KIT:buildStartGrid(root, { boxY = WATER_Y + 1, poleColor = C.BUOY_WHITE })
	KIT:buildFinish(root, { poleColor = C.BUOY_WHITE, archColor = Color3.fromRGB(40, 160, 255) })
end

-- ─── Main build ──────────────────────────────────────────────────────────────

local function buildOcean()
	local root, farmSub, trackSub = TrackKit.newMap("OceanMap")

	_buildWater(root)
	_buildFarmIsland(farmSub)

	_buildPalmIsland(trackSub)
	_buildReefFormation(trackSub)
	_buildChannel(trackSub)
	_buildCourseBuoys(trackSub)
	_buildTriggers(trackSub)
	_buildStartAndFinish(trackSub)

	TrackKit.tag(root, "BiomeMap")
	root:SetAttribute("Biome", "OCEAN")

	print("[OceanMapBuilder] Built OCEAN map (" .. #root:GetDescendants() .. " descendants)")
	return root
end

return {
	build = buildOcean,
	track = Track,
}
