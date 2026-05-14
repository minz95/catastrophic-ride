-- OceanMapBuilder.server.lua
-- Procedurally builds the OCEAN biome map per racetrack spec §3:
--   - 3400-stud centerline (arc-S + island detour + reef U-bend) along Z=600 → -1500
--   - 60-wide channel with solid above-water reef walls both sides (height 12 above waterPlaneY=2)
--   - Enlarged palm island anchors the S2 arc; reef formation anchors the S4 U-bend
--   - Buoys reduced to centerline decoration only (CanCollide false)
--   - CP1 inside S2 island arc, CP2 inside S4 reef U-bend
-- Resolves: Issue #9, #114, #129

local CollectionService = game:GetService("CollectionService")

local C = {
	WATER       = Color3.fromRGB(30,  90,  180),
	WATER_DEEP  = Color3.fromRGB(8,   35,  90),
	WATER_MID   = Color3.fromRGB(12,  55,  140),
	WATER_TOP   = Color3.fromRGB(25,  105, 210),
	WATER_FOAM  = Color3.fromRGB(120, 200, 255),
	DOCK        = Color3.fromRGB(140, 100, 60),
	SAND        = Color3.fromRGB(220, 190, 120),
	BOOST       = Color3.fromRGB(60,  200, 255),
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
	METAL  = Enum.Material.Metal,
	NEON   = Enum.Material.Neon,
	LEAVES = Enum.Material.LeafyGrass,
	GRASS  = Enum.Material.Grass,
	ROCK   = Enum.Material.Rock,
}

local WATER_Y  = 2     -- water surface Y
local LANE_W   = 60    -- channel width (spec §3 table)
local WALL_H   = 12    -- reef wall height above water (spec §3.4)
local FINISH_Z = -1500 -- matches Constants.TRACK.OCEAN.zFinish

local function _part(parent, props)
	local p = Instance.new("Part")
	p.Anchored   = true
	p.CanCollide = true
	for k, v in pairs(props) do pcall(function() p[k] = v end) end
	p.Parent = parent
	return p
end

local function _tag(part, tagName)
	CollectionService:AddTag(part, tagName)
end

local function _getOrCreateMap()
	local maps = workspace:FindFirstChild("Maps") or (function()
		local f = Instance.new("Folder"); f.Name = "Maps"; f.Parent = workspace; return f
	end)()
	local existing = maps:FindFirstChild("OceanMap")
	if existing then existing:Destroy() end
	local model = Instance.new("Model")
	model.Name   = "OceanMap"
	model.Parent = maps
	return model
end

-- ─── Channel centerline (spec §3.1, arc-S + island detour + reef U-bend) ─────

local NODES = {
	-- S1 Harbor Launch (~350)
	{   0,  600 }, -- N1  start dock
	{   0,  250 }, -- N2  enter S2

	-- S2 Island Arc east around enlarged palm island (~600)
	{  60,  200 }, -- N3
	{ 140,  100 }, -- N4
	{ 180,    0 }, -- N5  CP1 zone (apex east)
	{ 160, -100 }, -- N6
	{  80, -180 }, -- N7
	{   0, -200 }, -- N8  exit S2

	-- S3 Open Channel (chicane + jump skill-shot) (~520)
	{   0, -300 }, -- N9
	{  40, -400 }, -- N10
	{   0, -500 }, -- N11
	{ -40, -600 }, -- N12
	{   0, -700 }, -- N13

	-- S4 Reef U-bend east around reef formation (~900)
	{  40,  -730 }, -- N14
	{ 180,  -730 }, -- N15
	{ 330,  -800 }, -- N16
	{ 380,  -900 }, -- N17  CP2 zone (apex south-east)
	{ 330, -1000 }, -- N18
	{ 180, -1010 }, -- N19
	{  40, -1000 }, -- N20

	-- S5 Return Channel + Finish Lagoon (~720)
	{   0, -1080 }, -- N21
	{  80, -1150 }, -- N22
	{   0, -1220 }, -- N23
	{ -80, -1290 }, -- N24
	{   0, -1360 }, -- N25
	{  80, -1430 }, -- N26
	{   0, -1500 }, -- N27 FinishLine sensor at zFinish
	{   0, -1560 }, -- N28 runoff past finish
}

local function _segCF(ax, az, bx, bz, y)
	local mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
	local rotY   = math.atan2(bx - ax, bz - az)
	return CFrame.new(mx, y, mz) * CFrame.Angles(0, rotY, 0)
end

local function _segLen(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

-- ─── Water plane (large, covers full bbox of all nodes plus reef walls) ──────

local function _buildWater(root)
	-- Deep ocean floor
	_part(root, {
		Name = "OceanFloor", Size = Vector3.new(1400, 2, 2600),
		Position = Vector3.new(0, WATER_Y - 14, -400),
		Color = C.WATER_DEEP, Material = Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false,
	})
	-- Mid water volume
	_part(root, {
		Name = "WaterVolume", Size = Vector3.new(1300, 12, 2500),
		Position = Vector3.new(0, WATER_Y - 8, -400),
		Color = C.WATER_MID, Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15, CanCollide = false, CastShadow = false,
	})
	-- Surface
	_part(root, {
		Name = "WaterPlane", Size = Vector3.new(1200, 4, 2400),
		Position = Vector3.new(0, WATER_Y - 2, -400),
		Color = C.WATER_TOP, Material = MAT.WATER,
		Transparency = 0.35, CanCollide = false,
	})
	-- Foam shimmer overlay
	_part(root, {
		Name = "WaterShimmer", Size = Vector3.new(1200, 0.25, 2400),
		Position = Vector3.new(0, WATER_Y, -400),
		Color = C.WATER_FOAM, Material = MAT.NEON,
		Transparency = 0.82, CanCollide = false, CastShadow = false,
	})
end

-- ─── Channel "lane" cosmetic strip (slightly tinted water on centerline) ─────

local function _buildLaneStrip(root)
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		local cf     = _segCF(a[1], a[2], b[1], b[2], WATER_Y - 0.05)
		local strip = _part(root, {
			Name     = "LaneStrip_" .. i,
			Size     = Vector3.new(LANE_W - 4, 0.15, segLen + 4),
			Color    = Color3.fromRGB(80, 180, 255),
			Material = MAT.NEON,
			Transparency = 0.6,
			CanCollide = false,
			CastShadow = false,
		})
		strip.CFrame = cf
	end
end

-- ─── Reef walls (spec §3.4): solid above-water at ±30 stud offset ────────────

local function _buildReefWalls(root)
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		local cf     = _segCF(a[1], a[2], b[1], b[2], WATER_Y + WALL_H / 2)

		for _, side in ipairs({ -1, 1 }) do
			local wall = _part(root, {
				Name     = "ReefWall",
				Size     = Vector3.new(3, WALL_H, segLen + 8),  -- +8: adjacent walls overlap at joints
				Color    = C.REEF,
				Material = MAT.ROCK,
			})
			wall.CFrame = cf * CFrame.new(side * (LANE_W / 2 + 1.5), 0, 0)

			-- Red top stripe for visibility
			local cap = _part(root, {
				Name     = "ReefWallCap",
				Size     = Vector3.new(3.4, 0.6, segLen + 8),
				Color    = C.REEF_TOP,
				Material = MAT.NEON,
				CastShadow = false,
			})
			cap.CFrame = cf * CFrame.new(side * (LANE_W / 2 + 1.5), WALL_H / 2 + 0.3, 0)
		end
	end
end

-- ─── Buoyancy zones covering the entire channel bbox ─────────────────────────

local function _buildBuoyancyZones(root)
	local z = _part(root, {
		Name = "BuoyancyZone_Main", Size = Vector3.new(1200, 8, 2400),
		Position = Vector3.new(0, WATER_Y - 1, -400),
		CanCollide = false, Transparency = 1,
	})
	_tag(z, "BuoyancyZone")
end

-- ─── Buoys (decorative only — CanCollide false, centerline guidance) ─────────

local function _buildCourseBuoys(root)
	-- Place pairs at evenly-spaced node positions
	local buoyIdx = 0
	for i = 2, #NODES - 1, 2 do
		buoyIdx = buoyIdx + 1
		local cx, cz = NODES[i][1], NODES[i][2]
		local isRedSide = (buoyIdx % 2 == 0)
		for _, side in ipairs({ -1, 1 }) do
			local isRed = (side == 1) == isRedSide
			local bx = cx + side * (LANE_W / 2 - 6)  -- inside the wall, on the lane edge
			_part(root, {
				Name     = "Buoy_" .. buoyIdx .. (side > 0 and "R" or "L"),
				Size     = Vector3.new(2.5, 4, 2.5),
				Position = Vector3.new(bx, WATER_Y + 2, cz),
				Color    = isRed and C.BUOY_RED or C.BUOY_WHITE,
				Material = MAT.NEON,
				CanCollide = false,  -- decorative per spec §3.4
				CastShadow = false,
			})
		end
	end
end

-- ─── Palm island (S2 inside arc, enlarged so arc-cut is solid land) ─────────
-- Inside the S2 arc, X≈+90 Z≈0; island prevents straight-line shortcut.

local function _buildPalmIsland(root)
	local cx, cz = 90, 0  -- inside the arc's east bulge
	_part(root, {
		Name = "Palm_IslandBase", Size = Vector3.new(110, 8, 220),
		Position = Vector3.new(cx, WATER_Y - 2, cz),
		Color = C.SAND, Material = MAT.SAND,
	})
	_part(root, {
		Name = "Palm_IslandGrass", Size = Vector3.new(95, 1.5, 200),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = C.GRASS, Material = MAT.GRASS,
	})

	local rng = Random.new(99)
	for _ = 1, 8 do
		local tx = rng:NextNumber(cx - 40, cx + 40)
		local tz = rng:NextNumber(cz - 90, cz + 90)
		local h  = rng:NextNumber(8, 14)
		_part(root, {
			Name = "PalmTrunk", Size = Vector3.new(1.2, h, 1.2),
			Position = Vector3.new(tx, WATER_Y + 2.5 + h / 2, tz),
			Color = C.PALM_TRUNK, Material = MAT.WOOD, CanCollide = false,
		})
		for i = 0, 4 do
			local angle = (i / 5) * math.pi * 2
			_part(root, {
				Name = "PalmLeaf", Size = Vector3.new(0.6, 0.3, 8),
				Color = C.PALM_LEAF, Material = MAT.LEAVES,
				CFrame = CFrame.new(tx + math.cos(angle)*2, WATER_Y + 2.5 + h + 0.5, tz + math.sin(angle)*2)
					* CFrame.Angles(0, angle, math.rad(-20)),
				CanCollide = false,
			})
		end
	end
end

-- ─── Reef formation (S4 inside U-bend; visual landmark / shortcut blocker) ──

local function _buildReefFormation(root)
	-- Inside the U-bend at approximately (220, -870)
	local cx, cz = 220, -870
	-- Submerged base
	_part(root, {
		Name = "ReefBase", Size = Vector3.new(80, 6, 140),
		Position = Vector3.new(cx, WATER_Y - 3, cz),
		Color = C.REEF, Material = MAT.ROCK,
	})
	-- Spires above water (above waterPlaneY, visible)
	for i = 1, 5 do
		local sx = cx + (i - 3) * 14
		local sz = cz + math.sin(i) * 30
		_part(root, {
			Name = "ReefSpire_" .. i,
			Size = Vector3.new(8, 10, 8),
			Position = Vector3.new(sx, WATER_Y + 4, sz),
			Color = C.REEF, Material = MAT.ROCK,
		})
		_part(root, {
			Name = "ReefSpireTip_" .. i,
			Size = Vector3.new(4, 4, 4),
			Position = Vector3.new(sx, WATER_Y + 10, sz),
			Color = C.REEF_TOP, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
	end
end

-- ─── Drift corners (3 per spec §3.3) ─────────────────────────────────────────

local function _buildDriftCorners(root)
	local corners = {
		{ 180,    0 }, -- S2 island arc apex (N5)
		{ 380, -900 }, -- S4 reef U-bend apex (N17)
		{   0, -1220 }, -- S5 return channel mid-zigzag (N23)
	}
	for i, c in ipairs(corners) do
		local cx, cz = c[1], c[2]
		_part(root, {
			Name = "WakeRing_" .. i, Size = Vector3.new(LANE_W - 4, 0.3, 42),
			Position = Vector3.new(cx, WATER_Y + 0.3, cz),
			Color = C.DRIFT_GLOW, Material = MAT.NEON,
			CanCollide = false, CastShadow = false, Transparency = 0.5,
		})
		local trigger = _part(root, {
			Name = "DriftCorner_" .. i, Size = Vector3.new(LANE_W + 20, 8, 46),
			Position = Vector3.new(cx, WATER_Y + 2, cz),
			CanCollide = false, Transparency = 1,
		})
		_tag(trigger, "DriftCorner")
	end
end

-- ─── Jump ramps (2 per spec — post-S2 wave swell + mid-S3 skill-shot) ────────

local function _buildJumpRamps(root)
	local ramps = {
		{ 0, -240 },   -- post-S2 wave swell (between N8 and N9)
		{ 0, -500 },   -- mid-S3 skill shot (N11)
	}
	for i, r in ipairs(ramps) do
		local rx, rz = r[1], r[2]
		_part(root, {
			Name = "WaveRamp_" .. i, Size = Vector3.new(LANE_W - 12, 1.5, 14),
			Position = Vector3.new(rx, WATER_Y + 1, rz),
			Color = C.WATER_FOAM, Material = MAT.NEON,
			CanCollide = false, CastShadow = false, Transparency = 0.3,
		})
		local jz = _part(root, {
			Name = "JumpZone_" .. i, Size = Vector3.new(LANE_W - 6, 8, 12),
			Position = Vector3.new(rx, WATER_Y + 4, rz),
			CanCollide = false, Transparency = 1,
		})
		_tag(jz, "JumpZone")
	end
end

-- ─── Boost pads (4 per spec §3.3) ────────────────────────────────────────────

local function _buildBoostPads(root)
	local pads = {
		{   0,  500 },   -- S1 launch
		{ 150,    0 },   -- S2 inner apex (rewards tight line)
		{   0, -550 },   -- S3 mid-channel
		{   0, -1080 },  -- post-S4 U-bend exit (N21)
	}
	for i, pd in ipairs(pads) do
		local pad = _part(root, {
			Name = "BoostPad_" .. i, Size = Vector3.new(12, 0.4, 8),
			Position = Vector3.new(pd[1], WATER_Y + 0.4, pd[2]),
			Color = C.BOOST, Material = MAT.NEON, CanCollide = false,
		})
		_tag(pad, "BoostPad")
		_part(root, {
			Name = "BoostRing_" .. i, Size = Vector3.new(16, 0.2, 12),
			Position = Vector3.new(pd[1], WATER_Y + 0.3, pd[2]),
			Color = Color3.fromRGB(100, 240, 255), Material = MAT.NEON,
			Transparency = 0.5, CanCollide = false,
		})
	end
end

-- ─── Checkpoints (spec §3.6) ─────────────────────────────────────────────────

local function _buildCheckpoints(root)
	local cp1 = _part(root, {
		Name = "Checkpoint1", Size = Vector3.new(LANE_W, 12, 6),
		Position = Vector3.new(180, WATER_Y + 5, 0),  -- N5 inside island arc
		CanCollide = false, Transparency = 1,
	})
	_tag(cp1, "Checkpoint1")

	local cp2 = _part(root, {
		Name = "Checkpoint2", Size = Vector3.new(LANE_W, 12, 6),
		Position = Vector3.new(380, WATER_Y + 5, -900),  -- N17 inside reef U-bend
		CanCollide = false, Transparency = 1,
	})
	_tag(cp2, "Checkpoint2")
end

-- ─── Farm area (FARMING phase only; hidden during RACING) ────────────────────
-- Relocated to a separate island behind the start dock (Z=700–1000).

local function _buildFarmIsland(root)
	local cx, cz = 0, 850
	_part(root, {
		Name = "FarmIsland", Size = Vector3.new(180, 6, 260),
		Position = Vector3.new(cx, WATER_Y - 1, cz),
		Color = C.SAND, Material = MAT.SAND,
	})
	_part(root, {
		Name = "FarmGrass", Size = Vector3.new(160, 1, 230),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = C.GRASS, Material = MAT.GRASS,
	})

	local cols = { -60, -30, 0, 30, 60 }
	local rows = { cz - 50, cz + 50 }
	for _, rz in ipairs(rows) do
		for _, cxx in ipairs(cols) do
			local sp = _part(root, {
				Name = "FarmSpawnPoint", Size = Vector3.new(4, 0.5, 4),
				Position = Vector3.new(cx + cxx, WATER_Y + 3.5, rz),
				Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
				CanCollide = false, Transparency = 0.5,
			})
			_tag(sp, "FarmSpawn")
		end
	end

	local rng = Random.new(7)
	for _ = 1, 8 do
		local tx = rng:NextNumber(cx - 70, cx + 70)
		local tz = rng:NextNumber(cz - 100, cz + 100)
		local h  = rng:NextNumber(8, 14)
		_part(root, {
			Name = "PalmTrunk", Size = Vector3.new(1.2, h, 1.2),
			Position = Vector3.new(tx, WATER_Y + 2.5 + h / 2, tz),
			Color = C.PALM_TRUNK, Material = MAT.WOOD, CanCollide = false,
		})
		_part(root, {
			Name = "PalmCanopy", Size = Vector3.new(6, 4, 6),
			Position = Vector3.new(tx, WATER_Y + 2.5 + h + 1, tz),
			Color = C.PALM_LEAF, Material = MAT.LEAVES, CanCollide = false,
		})
	end
end

-- ─── Start grid (matches BiomeConfig.OCEAN.raceStartZ = 590) ─────────────────

local function _buildStartGrid(root)
	_part(root, {
		Name = "StartDock", Size = Vector3.new(LANE_W - 6, 1, 24),
		Position = Vector3.new(0, WATER_Y + 0.5, 595),
		Color = C.DOCK, Material = MAT.WOOD,
	})
	for side = -1, 1, 2 do
		_part(root, {
			Name = "StartPole" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(1.5, 10, 1.5),
			Position = Vector3.new(side * (LANE_W / 2 - 3), WATER_Y + 5, 588),
			Color = C.BUOY_WHITE, Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "StartBanner", Size = Vector3.new(LANE_W - 4, 2, 1),
		Position = Vector3.new(0, WATER_Y + 10, 588),
		Color = Color3.fromRGB(255, 220, 40), Material = MAT.NEON, CanCollide = false,
	})
end

-- ─── Finish line ─────────────────────────────────────────────────────────────

local function _buildFinishLine(root)
	for col = -(LANE_W / 2), (LANE_W / 2) - 4, 4 do
		for row = 0, 1 do
			_part(root, {
				Name = "FinishTile", Size = Vector3.new(4, 0.4, 4),
				Position = Vector3.new(col + 2, WATER_Y + 0.4, FINISH_Z + row * 4),
				Color = (math.floor((col + LANE_W / 2) / 4) + row) % 2 == 0
					and Color3.new(1,1,1) or Color3.new(0,0,0),
				Material = MAT.METAL, CanCollide = false,
			})
		end
	end

	local finish = _part(root, {
		Name = "FinishLine", Size = Vector3.new(LANE_W - 4, 10, 2),
		Position = Vector3.new(0, WATER_Y + 5, FINISH_Z),
		CanCollide = false, Transparency = 1,
	})
	_tag(finish, "FinishLine")

	for side = -1, 1, 2 do
		_part(root, {
			Name = "FinishPole" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(1.5, 18, 1.5),
			Position = Vector3.new(side * (LANE_W / 2 - 2), WATER_Y + 9, FINISH_Z),
			Color = C.BUOY_WHITE, Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "FinishArch", Size = Vector3.new(LANE_W, 2.5, 1.5),
		Position = Vector3.new(0, WATER_Y + 18, FINISH_Z),
		Color = Color3.fromRGB(40, 160, 255), Material = MAT.NEON, CanCollide = false,
	})
end

-- ─── Main build ──────────────────────────────────────────────────────────────

local function buildOcean()
	local root = _getOrCreateMap()

	local farmSub  = Instance.new("Model"); farmSub.Name  = "FarmArea";  farmSub.Parent  = root
	local trackSub = Instance.new("Model"); trackSub.Name = "RaceTrack"; trackSub.Parent = root

	_buildWater(root)
	_buildBuoyancyZones(root)
	_buildFarmIsland(farmSub)

	_buildPalmIsland(trackSub)
	_buildReefFormation(trackSub)
	_buildLaneStrip(trackSub)
	_buildReefWalls(trackSub)
	_buildCourseBuoys(trackSub)
	_buildBoostPads(trackSub)
	_buildJumpRamps(trackSub)
	_buildDriftCorners(trackSub)
	_buildCheckpoints(trackSub)
	_buildStartGrid(trackSub)
	_buildFinishLine(trackSub)

	CollectionService:AddTag(root, "BiomeMap")
	root:SetAttribute("Biome", "OCEAN")

	print("[OceanMapBuilder] Built OCEAN map (" .. #root:GetDescendants() .. " descendants)")
	return root
end

local ok, err = pcall(buildOcean)
if not ok then warn("[OceanMapBuilder] Build failed: " .. tostring(err)) end
