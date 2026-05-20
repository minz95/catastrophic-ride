-- ForestMapBuilder.server.lua
-- Procedurally builds the FOREST biome map per racetrack spec §2:
--   - 4700-stud centerline (figure-3 + U-bend) along Z = +600 → -2000
--   - 40-wide corridor with continuous 8-stud-tall walls both sides
--   - Bridge crosses S3 sweeper; rock outcrops/mud relocated OUTSIDE walls
--   - CP1 inside S3 sweeper, CP2 inside S4 U-bend (#126 CheckpointService)
--   - Ramps + boost pads as thin floor-only (no side collision on props)
-- Resolves: Issue #8, #83, #66, #87, #97, #128

local CollectionService = game:GetService("CollectionService")

local C = {
	GRASS        = Color3.fromRGB(76,  120, 50),
	DIRT         = Color3.fromRGB(120, 85,  50),
	MUD          = Color3.fromRGB(80,  55,  30),
	TRACK        = Color3.fromRGB(55,  50,  45),
	TRACK_EDGE   = Color3.fromRGB(240, 240, 240),
	RIVER        = Color3.fromRGB(55,  110, 200),
	BRIDGE       = Color3.fromRGB(140, 100, 55),
	ROCK         = Color3.fromRGB(110, 100, 90),
	ROCK_DARK    = Color3.fromRGB(80,  72,  65),
	BOOST_PAD    = Color3.fromRGB(255, 200, 40),
	RAMP         = Color3.fromRGB(150, 125, 80),
	WALL         = Color3.fromRGB(95,  68,  42),
	WALL_TOP     = Color3.fromRGB(200, 60,  40),
	BARN_WALL    = Color3.fromRGB(165, 55,  40),
	BARN_ROOF    = Color3.fromRGB(80,  60,  45),
	CROP_GREEN   = Color3.fromRGB(70,  160, 55),
	FENCE        = Color3.fromRGB(180, 150, 100),

	PINE_TRUNK   = Color3.fromRGB(85,  60,  40),
	PINE_LEAF    = Color3.fromRGB(35,  100, 35),
	PINE_LEAF2   = Color3.fromRGB(25,  80,  28),
	OAK_TRUNK    = Color3.fromRGB(110, 75,  45),
	OAK_LEAF     = Color3.fromRGB(65,  140, 45),
	OAK_LEAF2    = Color3.fromRGB(50,  110, 35),
	BIRCH_TRUNK  = Color3.fromRGB(215, 210, 195),
	BIRCH_LEAF   = Color3.fromRGB(95,  175, 65),
}

local MAT = {
	GRASS  = Enum.Material.Grass,
	DIRT   = Enum.Material.Ground,
	MUD    = Enum.Material.Ground,
	TRACK  = Enum.Material.Asphalt,
	WOOD   = Enum.Material.Wood,
	LEAVES = Enum.Material.LeafyGrass,
	METAL  = Enum.Material.Metal,
	NEON   = Enum.Material.Neon,
	ROCK   = Enum.Material.Rock,
	WATER  = Enum.Material.SmoothPlastic,
}

local TRACK_W   = 40       -- corridor width (spec §2 table)
local WALL_H    = 8        -- wall height (spec §2 table; cars hop ramps and clear 5)
local TRACK_TOP = 1.0      -- Y of track surface (Part top)

local function _part(parent, props)
	local p = Instance.new("Part")
	p.Anchored   = true
	p.CanCollide = true
	p.CastShadow = true
	for k, v in pairs(props) do pcall(function() p[k] = v end) end
	p.Parent = parent
	return p
end

local function _wedge(parent, props)
	local p = Instance.new("WedgePart")
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
	local existing = maps:FindFirstChild("ForestMap")
	if existing then existing:Destroy() end
	local model = Instance.new("Model")
	model.Name   = "ForestMap"
	model.Parent = maps
	return model
end

-- ─── Track node layout (spec §2.1, figure-3 + U-bend) ─────────────────────────
-- Centerline path ~4500-4700 studs; Z-extent 600 → -2050; net path/Z ratio ~1.8.
-- Race direction: vehicle starts at N1 (Z=600) and progresses toward Nlast (Z=-2050).
--
-- S1 (Starting Straight)         : N1  → N2     (~400)
-- S2 (Outcrop Hairpin, right 90°): N2  → N8     (~600)
-- S3 (River Sweeper, left 120°)  : N8  → N15    (~1100), bridge at N10
-- S4 (Farm U-Bend, 180° around)  : N15 → N23    (~1400)
-- S5 (Mud S-Chicane + finish)    : N23 → N30    (~1200)

local NODES = {
	-- S1
	{   0,   600 }, -- N1  start grid line
	{   0,   200 }, -- N2  end of S1 / S2 entry

	-- S2 right 90° around rock outcrop
	{   0,   100 }, -- N3  approach
	{  20,    60 }, -- N4  arc enter
	{  60,    30 }, -- N5  arc apex (outcrop sits at +X side, decor only)
	{ 120,    20 }, -- N6  arc exit
	{ 300,    20 }, -- N7  departure straight
	{ 450,     0 }, -- N8  end of S2

	-- S3 long left 120° sweeper, bridge at N10
	{ 550,  -120 }, -- N9
	{ 580,  -300 }, -- N10 bridge crosses centerline here
	{ 550,  -480 }, -- N11
	{ 460,  -640 }, -- N12
	{ 310,  -750 }, -- N13
	{ 130,  -820 }, -- N14 CP1 zone
	{ -50,  -830 }, -- N15 end of S3

	-- S4 U-bend around farm island (peak at N19)
	{ -220, -870  }, -- N16
	{ -360, -970  }, -- N17
	{ -450, -1130 }, -- N18
	{ -470, -1310 }, -- N19 U peak (CP2 zone)
	{ -420, -1450 }, -- N20
	{ -280, -1530 }, -- N21
	{ -100, -1530 }, -- N22
	{   50, -1500 }, -- N23 end of S4

	-- S5 S-chicane (right→left), then 230-stud finish straight at X=0
	{  180, -1550 }, -- N24 chicane right curve
	{  130, -1620 }, -- N25 return
	{    0, -1640 }, -- N26 crossover
	{ -100, -1670 }, -- N27 chicane left peak
	{  -30, -1740 }, -- N28 return
	{    0, -1770 }, -- N29 onto finish straight (X=0 from here)
	{    0, -2000 }, -- N30 FinishLine sensor at Z=-2000 (Constants.TRACK.FOREST.zFinish)
	{    0, -2050 }, -- N31 runoff past finish
}

-- Finish-line Z (FinishLine sensor / arch). Must match Constants.TRACK.FOREST.zFinish (-2000 ± approach).
local FINISH_Z = -2000

-- ─── Segment helpers ──────────────────────────────────────────────────────────

local function _segCF(ax, az, bx, bz)
	local mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
	local rotY   = math.atan2(bx - ax, bz - az)
	return CFrame.new(mx, 0.5, mz) * CFrame.Angles(0, rotY, 0)
end

local function _segLen(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

-- ─── Ground plane ─────────────────────────────────────────────────────────────

local function _buildGround(root)
	-- Large grass plane covering full track bbox plus generous margin.
	_part(root, {
		Name     = "Ground",
		Size     = Vector3.new(1400, 4, 3200),
		Position = Vector3.new(0, -2, -700),
		Color    = C.GRASS,
		Material = MAT.GRASS,
	})

	local rng = Random.new(77)
	for _ = 1, 60 do
		_part(root, {
			Name       = "GrassDetail",
			Size       = Vector3.new(rng:NextNumber(15, 40), 0.3, rng:NextNumber(10, 25)),
			Position   = Vector3.new(rng:NextNumber(-600, 600), 0.2, rng:NextNumber(-2100, 700)),
			Color      = Color3.fromRGB(55, 100, 38),
			Material   = MAT.GRASS,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- ─── Farm area (used only during FARMING phase; hidden during RACING) ─────────
-- Relocated behind the start grid (Z=700–1000) so its props never sit inside
-- the racing corridor.

local FARM_CX, FARM_CZ = 0, 850

local function _buildFarmArea(root)
	_part(root, {
		Name     = "FarmGround",
		Size     = Vector3.new(220, 2, 320),
		Position = Vector3.new(FARM_CX, 0, FARM_CZ),
		Color    = C.DIRT,
		Material = MAT.DIRT,
	})

	for row = 0, 7 do
		for col = -3, 3 do
			_part(root, {
				Name       = "CropRow",
				Size       = Vector3.new(18, 1.5, 3),
				Position   = Vector3.new(FARM_CX + col * 22, 0.8, FARM_CZ - 100 + row * 30),
				Color      = C.CROP_GREEN,
				Material   = MAT.LEAVES,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end

	_part(root, {
		Name     = "BarnWall",
		Size     = Vector3.new(25, 14, 18),
		Position = Vector3.new(FARM_CX - 80, 7, FARM_CZ),
		Color    = C.BARN_WALL,
		Material = MAT.WOOD,
	})
	local r1 = _wedge(root, {
		Name = "BarnRoof", Size = Vector3.new(12, 8, 18),
		Color = C.BARN_ROOF, Material = MAT.WOOD, CanCollide = false,
	})
	r1.CFrame = CFrame.new(FARM_CX - 86, 18, FARM_CZ) * CFrame.Angles(0,  math.pi/2, 0)
	local r2 = _wedge(root, {
		Name = "BarnRoof2", Size = Vector3.new(12, 8, 18),
		Color = C.BARN_ROOF, Material = MAT.WOOD, CanCollide = false,
	})
	r2.CFrame = CFrame.new(FARM_CX - 74, 18, FARM_CZ) * CFrame.Angles(0, -math.pi/2, 0)

	-- Fence boundary (cosmetic; CanCollide false)
	local fences = {
		{ Vector3.new(222, 5, 1.5), Vector3.new(FARM_CX,     2.5, FARM_CZ - 160) },
		{ Vector3.new(222, 5, 1.5), Vector3.new(FARM_CX,     2.5, FARM_CZ + 160) },
		{ Vector3.new(1.5, 5, 322), Vector3.new(FARM_CX - 111, 2.5, FARM_CZ) },
		{ Vector3.new(1.5, 5, 322), Vector3.new(FARM_CX + 111, 2.5, FARM_CZ) },
	}
	for _, fd in ipairs(fences) do
		local f = _part(root, { Name="Fence", Size=fd[1], Position=fd[2], Color=C.FENCE, Material=MAT.WOOD })
		f.CanCollide   = false
		f.Transparency = 0.2
	end
	for px = -100, 100, 20 do
		_part(root, {
			Name = "FencePost", Size = Vector3.new(1.5, 7, 1.5),
			Position = Vector3.new(FARM_CX + px, 3.5, FARM_CZ - 160),
			Color = C.FENCE, Material = MAT.WOOD,
		})
	end

	-- FarmSpawn tags (item-spawn anchor points). Spread across crop rows.
	local cols = { -80, -40, 0, 40, 80 }
	local rows = { FARM_CZ - 60, FARM_CZ + 20 }
	for _, rz in ipairs(rows) do
		for _, cx in ipairs(cols) do
			local sp = _part(root, {
				Name = "FarmSpawnPoint", Size = Vector3.new(4, 0.5, 4),
				Position = Vector3.new(FARM_CX + cx, 1.5, rz),
				Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
				CanCollide = false, CastShadow = false, Transparency = 0.5,
			})
			_tag(sp, "FarmSpawn")
		end
	end
end

-- ─── Track surface ────────────────────────────────────────────────────────────
-- One TrackSeg per node-pair, slightly elongated by +2 studs on each end so
-- adjacent segments overlap at the joints (no thin gap visible at corners).

local function _buildTrack(root)
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		local cf     = _segCF(a[1], a[2], b[1], b[2])

		local seg = _part(root, {
			Name     = "TrackSeg_" .. i,
			Size     = Vector3.new(TRACK_W, 1, segLen + 4),
			Color    = C.TRACK,
			Material = MAT.TRACK,
		})
		seg.CFrame = cf

		-- White outer-edge stripe (visual only).
		for _, side in ipairs({ -1, 1 }) do
			local edge = _part(root, {
				Name       = "TrackEdge",
				Size       = Vector3.new(1.5, 1.1, segLen + 4),
				Color      = C.TRACK_EDGE,
				Material   = MAT.METAL,
				CanCollide = false,
				CastShadow = false,
			})
			edge.CFrame = cf * CFrame.new(side * (TRACK_W / 2 - 1), 0.05, 0)
		end

		-- Dashed centre line
		local dashCount = math.max(1, math.floor(segLen / 30))
		for d = 0, dashCount - 1 do
			local dz = -segLen / 2 + (d + 0.5) * (segLen / dashCount)
			local dash = _part(root, {
				Name     = "CentreDash",
				Size     = Vector3.new(1, 1.15, 14),
				Color    = Color3.fromRGB(255, 220, 60),
				Material = MAT.NEON,
				CanCollide = false,
				CastShadow = false,
			})
			dash.CFrame = cf * CFrame.new(0, 0.05, dz)
		end
	end
end

-- ─── Continuous track walls (spec §2.4) ───────────────────────────────────────
-- Walls span exactly segLen. An earlier +8 extension caused the wall from
-- segment N to jut 4 studs past its endpoint along its own direction at
-- sharp kinks (S2 arc N4–N6, S4 U-bend N17–N21, S5 chicane N23–N29),
-- intruding into the next segment's lane.

local function _buildWalls(root)
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		local cf     = _segCF(a[1], a[2], b[1], b[2])

		for _, side in ipairs({ -1, 1 }) do
			local wall = _part(root, {
				Name     = "TrackWall",
				Size     = Vector3.new(2, WALL_H, segLen),
				Color    = C.WALL,
				Material = MAT.WOOD,
			})
			wall.CFrame = cf * CFrame.new(side * (TRACK_W / 2 + 1), WALL_H / 2, 0)

			local cap = _part(root, {
				Name     = "TrackWallCap",
				Size     = Vector3.new(2.4, 0.6, segLen),
				Color    = C.WALL_TOP,
				Material = MAT.NEON,
			})
			cap.CFrame = cf * CFrame.new(side * (TRACK_W / 2 + 1), WALL_H + 0.3, 0)
			cap.CastShadow = false
		end
	end
end

-- ─── River + bridge across S3 (between N10 and centerline) ───────────────────

local function _buildRiverBridge(root)
	local riverZ = -300                       -- aligns with N10 mid-sweep
	local centerX = 580                       -- approx N10 x
	-- Wide cross-river belt (east-west under the corridor). Track surface
	-- continues over the water; bridge planks visually overlay.
	_part(root, {
		Name         = "RiverWater",
		Size         = Vector3.new(1200, 2, 60),
		Position     = Vector3.new(0, -1, riverZ),
		Color        = C.RIVER,
		Material     = MAT.WATER,
		Transparency = 0.35,
		CanCollide   = false,
	})

	-- Riverbanks (decorative wedges, outside the corridor only)
	for _, side in ipairs({ -1, 1 }) do
		_wedge(root, {
			Name     = "RiverBank",
			Size     = Vector3.new(1200, 3, 14),
			Position = Vector3.new(0, -0.5, riverZ + side * 36),
			Color    = C.DIRT,
			Material = MAT.DIRT,
			CanCollide = false,
		})
	end

	-- Bridge planks over the corridor segment crossing the river.
	for plank = -16, 16, 4 do
		_part(root, {
			Name     = "BridgePlank",
			Size     = Vector3.new(4, 0.6, 60),
			Position = Vector3.new(centerX + plank, 1.3, riverZ),
			Color    = C.BRIDGE,
			Material = MAT.WOOD,
			CanCollide = false,
		})
	end

	-- Bridge railings live OUTSIDE the corridor walls (cosmetic, non-collidable).
	for _, side in ipairs({ -1, 1 }) do
		_part(root, {
			Name     = "BridgeRailing",
			Size     = Vector3.new(0.6, 3, 64),
			Position = Vector3.new(centerX + side * (TRACK_W / 2 + 3), 3, riverZ),
			Color    = C.BRIDGE,
			Material = MAT.WOOD,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- ─── Mud zones (S5 chicane area only — outside the racing line) ──────────────

local function _buildMudZones(root)
	-- Mud patches in the S-chicane apex sides (rewards apex cutting).
	local zones = {
		{ 230, -1560 },   -- outer of right chicane peak
		{ -150, -1660 },  -- outer of left chicane peak
		{   0, -1810 },   -- centerline mud just before finish straight (skill check)
		{  50, -1700 },   -- inside chicane
	}
	for i, mz in ipairs(zones) do
		local mud = _part(root, {
			Name     = "MudZone_" .. i,
			Size     = Vector3.new(20, 0.4, 16),
			Position = Vector3.new(mz[1], 1.1, mz[2]),
			Color    = C.MUD,
			Material = MAT.MUD,
		})
		mud.CanCollide = false
		mud.CastShadow = false
		_tag(mud, "MudZone")
	end
end

-- ─── Rock outcrop decor (S2 apex, OUTSIDE the wall) ──────────────────────────

local function _buildRockDecor(root)
	-- One landmark rock pile per drift corner / hairpin apex, all positioned
	-- outside the corridor so vehicles cannot collide with them mid-race.
	local piles = {
		{ 110, -10 },      -- S2 outcrop (outer of right hairpin)
		{ 620, -300 },     -- S3 outer bend at river mouth
		{ -540, -1310 },   -- S4 U peak outer
		{ 230, -1570 },    -- S5 chicane outer
		{ -30,  100 },     -- S2 inner (left of corridor)
	}
	for i, rp in ipairs(piles) do
		local bx, bz = rp[1], rp[2]
		_part(root, {
			Name = "RockBase_" .. i, Size = Vector3.new(7, 5, 7),
			Position = Vector3.new(bx, 2.5, bz),
			Color = C.ROCK, Material = MAT.ROCK,
		})
		_wedge(root, {
			Name = "RockChip_" .. i, Size = Vector3.new(4, 3, 4),
			Position = Vector3.new(bx + 2.5, 6.5, bz - 1.5),
			Color = C.ROCK_DARK, Material = MAT.ROCK,
		})
		_part(root, {
			Name = "Moss_" .. i, Size = Vector3.new(7.2, 0.6, 7.2),
			Position = Vector3.new(bx, 5.3, bz),
			Color = Color3.fromRGB(55, 110, 40), Material = MAT.LEAVES,
			CanCollide = false, CastShadow = false,
		})
	end
end

-- ─── Jump ramps (2 per spec, mid-S3 and pre-S5) ──────────────────────────────
-- Ramp pieces are floor-only: thin wedge sitting on the track surface, no
-- side collision walls (spec §2.4 fix for the "snag on prop side" cheese).

local function _buildJumpRamps(root)
	local ramps = {
		{  490, -550, math.rad(35) },   -- mid-S3 over creek tributary
		{    0, -1850, math.rad(0)  },  -- pre-finish straight (after chicane)
	}
	for i, r in ipairs(ramps) do
		local rx, rz, yaw = r[1], r[2], r[3]
		local ramp = _wedge(root, {
			Name     = "JumpRamp_" .. i,
			Size     = Vector3.new(TRACK_W - 4, 4, 14),
			Color    = C.RAMP,
			Material = MAT.DIRT,
		})
		ramp.CFrame = CFrame.new(rx, 3, rz) * CFrame.Angles(0, yaw + math.pi, 0)

		-- Landing pad (flat slab matching track top — purely cosmetic since
		-- the underlying TrackSeg already covers this Z).
		_part(root, {
			Name = "LandingPad_" .. i,
			Size = Vector3.new(TRACK_W - 4, 0.2, 22),
			Position = Vector3.new(rx, TRACK_TOP + 0.1, rz - 17 * math.cos(yaw)),
			Color = C.RAMP, Material = MAT.DIRT,
			CanCollide = false, CastShadow = false,
		})

		local jz = _part(root, {
			Name = "JumpZone_" .. i, Size = Vector3.new(TRACK_W, 10, 14),
			Position = Vector3.new(rx, 6, rz),
			CanCollide = false, Transparency = 1,
		})
		_tag(jz, "JumpZone")
	end
end

-- ─── Boost pads (4 per spec) ─────────────────────────────────────────────────
-- Pads sit on the track surface as thin floor strips, CanCollide false.

local function _buildBoostPads(root)
	local pads = {
		{   0,  400 },    -- S1 launch
		{ 560, -380 },    -- S3 mid-sweep (rewards apex)
		{ -380, -1500 },  -- S4 U exit
		{   0, -1920 },   -- S5 onto finish straight
	}
	for i, pd in ipairs(pads) do
		local pad = _part(root, {
			Name = "BoostPad_" .. i,
			Size = Vector3.new(10, 0.3, 8),
			Position = Vector3.new(pd[1], TRACK_TOP + 0.2, pd[2]),
			Color = C.BOOST_PAD, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
		_tag(pad, "BoostPad")

		local arrow = _wedge(root, {
			Name = "BoostArrow_" .. i,
			Size = Vector3.new(5, 0.4, 5),
			Color = Color3.fromRGB(255, 240, 80), Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
		arrow.CFrame = CFrame.new(pd[1], TRACK_TOP + 0.4, pd[2] - 5) * CFrame.Angles(0, math.pi, 0)
	end
end

-- ─── Drift corner zones (4 per spec §2.3) ────────────────────────────────────

local function _buildDriftCorners(root)
	local corners = {
		{  60,   30 }, -- S2 outcrop apex
		{ 580, -300 }, -- S3 river bridge entry
		{ -470, -1310 }, -- S4 U peak
		{ 180, -1550 }, -- S5 chicane entry
	}
	for i, c in ipairs(corners) do
		local cx, cz = c[1], c[2]
		_part(root, {
			Name         = "DriftStrip_" .. i,
			Size         = Vector3.new(TRACK_W - 2, 0.2, 38),
			Position     = Vector3.new(cx, TRACK_TOP + 0.12, cz),
			Color        = Color3.fromRGB(255, 165, 20),
			Material     = MAT.NEON,
			CanCollide   = false,
			CastShadow   = false,
			Transparency = 0.55,
		})
		local trigger = _part(root, {
			Name         = "DriftCorner_" .. i,
			Size         = Vector3.new(TRACK_W, 5, 40),
			Position     = Vector3.new(cx, 3.5, cz),
			CanCollide   = false,
			Transparency = 1,
		})
		_tag(trigger, "DriftCorner")
	end
end

-- ─── Checkpoints (CP1 inside S3 sweeper, CP2 inside S4 U-bend) ───────────────
-- Per spec §2.6: positioned so any straight-line outside-the-corridor path
-- geometrically misses the trigger volumes. CheckpointService (#126) gates the
-- FinishLine on cp1 && cp2.

local function _buildCheckpointGate(root, x, z, cpIndex, archColor)
	local groundY = 0
	local archTop = groundY + 18
	for _, side in ipairs({ -1, 1 }) do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Pillar" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(2.4, archTop, 2.4),
			Position = Vector3.new(x + side * (TRACK_W / 2 - 2), groundY + archTop / 2, z),
			Color = archColor, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
	end
	for i = -1, 1 do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Top" .. (i + 2),
			Size = Vector3.new(TRACK_W / 3 + 2, 2, 2.4),
			Position = Vector3.new(x + i * (TRACK_W / 3), archTop + (i == 0 and 2 or 0.5), z),
			Color = archColor, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
	end
	local labelAnchor = _part(root, {
		Name = "CPGate" .. cpIndex .. "Label",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x, archTop + 8, z),
		Transparency = 1, CanCollide = false, CastShadow = false,
	})
	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.new(0, 120, 0, 32)
	bb.MaxDistance    = 300
	bb.LightInfluence = 0
	bb.Parent         = labelAnchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "체크포인트 " .. cpIndex
	lbl.TextColor3 = archColor
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.2
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Parent = bb
end

local function _buildCheckpoints(root)
	local cp1 = _part(root, {
		Name         = "Checkpoint1",
		Size         = Vector3.new(TRACK_W, 12, 6),
		Position     = Vector3.new(130, 7, -820),  -- N14, inside S3 sweeper apex
		CanCollide   = false,
		Transparency = 1,
	})
	_tag(cp1, "Checkpoint1")
	_buildCheckpointGate(root, 130, -820, 1, Color3.fromRGB(120, 220, 255))

	local cp2 = _part(root, {
		Name         = "Checkpoint2",
		Size         = Vector3.new(TRACK_W, 12, 6),
		Position     = Vector3.new(-470, 7, -1310), -- N19, inside U-bend peak
		CanCollide   = false,
		Transparency = 1,
	})
	_tag(cp2, "Checkpoint2")
	_buildCheckpointGate(root, -470, -1310, 2, Color3.fromRGB(255, 200, 100))
end

-- ─── Three tree species (relocated OUTSIDE walls per §2.7) ───────────────────

local function _buildTrees(root)
	local rng = Random.new(42)

	local function _pine(parent, tx, tz)
		local h = rng:NextNumber(14, 24)
		_part(parent, {
			Name = "PineTrunk", Size = Vector3.new(1, h, 1),
			Position = Vector3.new(tx, h / 2, tz),
			Color = C.PINE_TRUNK, Material = MAT.WOOD, CanCollide = false,
		})
		for layer = 0, 2 do
			local layerR = (3 - layer) * 2.5
			local layerY = h * (0.65 + layer * 0.15)
			_part(parent, {
				Name = "PineLeaf", Size = Vector3.new(layerR * 2, layerR * 0.9, layerR * 2),
				Position = Vector3.new(tx, layerY, tz),
				Color = layer % 2 == 0 and C.PINE_LEAF or C.PINE_LEAF2,
				Material = MAT.LEAVES, CanCollide = false, CastShadow = false,
			})
		end
	end

	local function _oak(parent, tx, tz)
		local h = rng:NextNumber(8, 15)
		local r = rng:NextNumber(4, 8)
		_part(parent, {
			Name = "OakTrunk", Size = Vector3.new(r * 0.45, h, r * 0.45),
			Position = Vector3.new(tx, h / 2, tz),
			Color = C.OAK_TRUNK, Material = MAT.WOOD, CanCollide = false,
		})
		for blob = 0, 1 do
			_part(parent, {
				Name = "OakLeaf", Size = Vector3.new(r * 2.2, r * 1.4, r * 2.2),
				Position = Vector3.new(tx, h + r * (0.4 + blob * 0.5), tz),
				Color = blob == 0 and C.OAK_LEAF or C.OAK_LEAF2,
				Material = MAT.LEAVES, CanCollide = false, CastShadow = false,
			})
		end
	end

	local function _birch(parent, tx, tz)
		local h = rng:NextNumber(10, 18)
		_part(parent, {
			Name = "BirchTrunk", Size = Vector3.new(0.7, h, 0.7),
			Position = Vector3.new(tx, h / 2, tz),
			Color = C.BIRCH_TRUNK, Material = MAT.WOOD, CanCollide = false,
		})
		_part(parent, {
			Name = "BirchLeaf", Size = Vector3.new(6, 7, 6),
			Position = Vector3.new(tx, h + 2, tz),
			Color = C.BIRCH_LEAF, Material = MAT.LEAVES,
			CanCollide = false, CastShadow = false,
		})
	end

	-- Helper: reject tree positions that fall within the corridor bbox.
	local function _insideTrack(tx, tz)
		-- Approximate: trees too close to any node are likely on the track.
		for _, n in ipairs(NODES) do
			local dx, dz = tx - n[1], tz - n[2]
			if dx * dx + dz * dz < 35 * 35 then  -- 35-stud buffer (track is 40 wide)
				return true
			end
		end
		return false
	end

	local builders = { _pine, _pine, _oak, _oak, _birch }
	local zones = {
		-- (xMin, xMax, zMin, zMax, count)
		{ -550, -100,   100,  700, 30 },  -- left of S1/farm
		{  100,  550,   100,  700, 30 },  -- right of S1/farm
		{ -550,    0,  -700,    0, 35 },  -- inside arc of S2/S3 sweeper (left)
		{  650, 1100,  -500,  100, 25 },  -- right of S3 outer sweep
		{ -800, -550, -1700, -700, 35 },  -- outside U-bend west side
		{  100,  700, -1700, -700, 30 },  -- inside U-bend east side
		{ -500,  500, -2200, -1700, 30 }, -- around finish-line approach
	}

	for _, zone in ipairs(zones) do
		local xMin, xMax, zMin, zMax, count = zone[1], zone[2], zone[3], zone[4], zone[5]
		local placed, attempts = 0, 0
		while placed < count and attempts < count * 6 do
			attempts = attempts + 1
			local tx = rng:NextNumber(xMin, xMax)
			local tz = rng:NextNumber(zMin, zMax)
			if not _insideTrack(tx, tz) then
				local fn = builders[rng:NextInteger(1, #builders)]
				fn(root, tx, tz)
				placed = placed + 1
			end
		end
	end
end

-- ─── Finish line ──────────────────────────────────────────────────────────────

local function _buildFinishLine(root)
	-- Checker tiles either side of the finish sensor.
	for col = -18, 18, 4 do
		for row = 0, 1 do
			_part(root, {
				Name = "FinishTile",
				Size = Vector3.new(4, 0.3, 4),
				Position = Vector3.new(col, TRACK_TOP + 0.15, FINISH_Z + row * 4),
				Color = (math.floor(col / 4) + row) % 2 == 0
					and Color3.new(1,1,1) or Color3.new(0,0,0),
				Material = MAT.METAL,
				CanCollide = false,
			})
		end
	end

	local finish = _part(root, {
		Name         = "FinishLine",
		Size         = Vector3.new(TRACK_W, 10, 2),
		Position     = Vector3.new(0, 6, FINISH_Z),
		CanCollide   = false,
		Transparency = 1,
	})
	_tag(finish, "FinishLine")

	for side = -1, 1, 2 do
		_part(root, {
			Name = "FinishPole",
			Size = Vector3.new(1.5, 18, 1.5),
			Position = Vector3.new(side * (TRACK_W / 2 + 1), 10, FINISH_Z),
			Color = Color3.fromRGB(240, 240, 240), Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "FinishArch", Size = Vector3.new(TRACK_W + 4, 2.5, 1.5),
		Position = Vector3.new(0, 20, FINISH_Z),
		Color = Color3.fromRGB(220, 55, 55), Material = MAT.NEON,
		CanCollide = false,
	})
	for bx = -20, 20, 8 do
		_part(root, {
			Name = "ArchBanner",
			Size = Vector3.new(8, 4, 0.4),
			Position = Vector3.new(bx, 16, FINISH_Z),
			Color = math.abs(bx) % 16 == 0 and Color3.new(1,1,1) or Color3.new(0,0,0),
			Material = MAT.METAL, CanCollide = false,
		})
	end
end

-- ─── Start grid (matches BiomeConfig.FOREST.raceStartZ = 590) ────────────────

local function _buildStartGrid(root)
	local cols = { -14, -7, 0, 7, 14 }
	local rows = { 590, 598 }
	for ri, z in ipairs(rows) do
		for ci, x in ipairs(cols) do
			local idx = (ri - 1) * 5 + ci
			_part(root, {
				Name     = "StartBox_" .. idx,
				Size     = Vector3.new(7, 0.2, 7),
				Position = Vector3.new(x, TRACK_TOP + 0.05, z),
				Color    = Color3.fromRGB(60, 120, 255),
				Material = MAT.NEON,
				CanCollide = false,
			})
		end
	end
end

-- ─── Main build ───────────────────────────────────────────────────────────────

local function buildForest()
	local root = _getOrCreateMap()

	local farmSub  = Instance.new("Model"); farmSub.Name  = "FarmArea";  farmSub.Parent  = root
	local trackSub = Instance.new("Model"); trackSub.Name = "RaceTrack"; trackSub.Parent = root

	_buildGround(root)
	_buildTrees(root)
	_buildFarmArea(farmSub)

	_buildTrack(trackSub)
	_buildWalls(trackSub)
	_buildRiverBridge(trackSub)
	_buildMudZones(trackSub)
	_buildRockDecor(trackSub)
	_buildJumpRamps(trackSub)
	_buildBoostPads(trackSub)
	_buildDriftCorners(trackSub)
	_buildCheckpoints(trackSub)
	_buildFinishLine(trackSub)
	_buildStartGrid(trackSub)

	CollectionService:AddTag(root, "BiomeMap")
	root:SetAttribute("Biome", "FOREST")

	print("[ForestMapBuilder] Built FOREST map (" .. #root:GetDescendants() .. " descendants)")
	return root
end

local ok, err = pcall(buildForest)
if not ok then warn("[ForestMapBuilder] Build failed: " .. tostring(err)) end
