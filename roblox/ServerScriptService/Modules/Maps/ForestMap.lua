-- ForestMap.lua
-- ModuleScript: procedurally builds the FOREST biome map per racetrack spec §2.
-- Layout data (nodes, hazards, checkpoints, sizes) lives in
-- ReplicatedStorage.Shared.Tracks.ForestTrack so simulators and offline checks
-- read the same numbers. The parts every track shares (surface, walls, slow
-- zones, triggers, finish, start) come from Modules.Maps.TrackKit; this file
-- only adds the forest look. Called by MapBuilders/ForestMapBuilder.server.lua
-- at server start, and by the Studio harness / preview plugin in edit mode.
--
--   - 4700-stud centerline (figure-3 + U-bend) along Z = +600 → -2000
--   - 40-wide corridor with continuous 8-stud-tall walls both sides
--   - Bridge crosses S3 sweeper; rock outcrops/mud relocated OUTSIDE walls
--   - CP1 inside S3 sweeper, CP2 inside S4 U-bend (#126 CheckpointService)
--   - Ramps + boost pads as thin floor-only (no side collision on props)
-- Resolves: Issue #8, #83, #66, #87, #97, #128

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Tracks.ForestTrack)
local TrackKit = require(script.Parent.TrackKit)

local KIT = TrackKit.new(Track)

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

local TRACK_W   = Track.width       -- corridor width (spec §2 table)

local _part, _wedge, _tag = TrackKit.part, TrackKit.wedge, TrackKit.tag

local NODES = Track.nodes
local GEO   = KIT.geo

-- ─── Ground plane ─────────────────────────────────────────────────────────────

local function _buildGround(root)
	-- Grass plane covering the track and farm bounding box plus a margin.
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, n in ipairs(NODES) do
		x0 = math.min(x0, n[1]); x1 = math.max(x1, n[1])
		z0 = math.min(z0, n[2]); z1 = math.max(z1, n[2])
	end
	z1 = math.max(z1, Track.farm.cz + 160)
	local M = 400
	_part(root, {
		Name     = "Ground",
		Size     = Vector3.new(x1 - x0 + M * 2, 4, z1 - z0 + M * 2),
		Position = Vector3.new((x0 + x1) / 2, -2, (z0 + z1) / 2),
		Color    = C.GRASS,
		Material = MAT.GRASS,
	})

	local rng = Random.new(77)
	for _ = 1, 60 do
		_part(root, {
			Name       = "GrassDetail",
			Size       = Vector3.new(rng:NextNumber(15, 40), 0.3, rng:NextNumber(10, 25)),
			Position   = Vector3.new(rng:NextNumber(x0 - M / 2, x1 + M / 2), 0.2, rng:NextNumber(z0 - M / 2, z1 + M / 2)),
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

local FARM_CX, FARM_CZ = Track.farm.cx, Track.farm.cz

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

-- ─── Track surface, walls, slow zones (TrackKit) ─────────────────────────────

local function _buildTrack(root)
	KIT:buildSurface(root, {
		name = "TrackSeg", jointName = "TrackSegJoint", thickness = 1, overlap = 2,
		color = C.TRACK, material = MAT.TRACK,
		decorate = function(r, i, cf, segLen)
			-- White edge stripes and a dashed centre line (visual only)
			for _, side in ipairs({ -1, 1 }) do
				_part(r, {
					Name = "TrackEdge", Size = Vector3.new(1.5, 1.1, segLen + 4),
					CFrame = cf * CFrame.new(side * (TRACK_W / 2 - 1), 0.05, 0),
					Color = C.TRACK_EDGE, Material = MAT.METAL,
					CanCollide = false, CastShadow = false,
				})
			end
			local dashCount = math.max(1, math.floor(segLen / 30))
			for d = 0, dashCount - 1 do
				_part(r, {
					Name = "CentreDash", Size = Vector3.new(1, 1.15, 14),
					CFrame = cf * CFrame.new(0, 0.05, -segLen / 2 + (d + 0.5) * (segLen / dashCount)),
					Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
					CanCollide = false, CastShadow = false,
				})
			end
		end,
	})
end

local function _buildWalls(root)
	KIT:buildWalls(root, {
		name = "TrackWall", color = C.WALL, material = MAT.WOOD,
		cap = { name = "TrackWallCap", color = C.WALL_TOP, material = MAT.NEON },
	})
end

local function _buildSlowZones(root)
	KIT:buildSlowZones(root, { color = C.MUD, material = MAT.MUD, transparency = 0.6 })
end

-- ─── River + bridge across S3 (between N10 and centerline) ───────────────────

local function _buildRiverBridge(root)
	local riverZ = Track.river.z              -- aligns with N10 mid-sweep
	local centerX = Track.river.bridgeX       -- approx N10 x
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
	local size = Track.mudZoneSize
	for i, mz in ipairs(Track.mudZones) do
		local mud = _part(root, {
			Name     = "MudZone_" .. i,
			Size     = Vector3.new(size[1], size[2], size[3]),
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
	for i, rp in ipairs(Track.rockPiles) do
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

-- ─── Jump ramps, boost pads, drift corners, checkpoints (TrackKit) ─────────
-- Ramp pieces are floor-only: thin wedge sitting on the track surface, no
-- side collision walls (spec §2.4 fix for the "snag on prop side" cheese).

local function _buildJumpRamps(root)
	local rs = Track.jumpRampSize
	KIT:buildJumpZones(root, {
		visual = function(r, cf, i, ramp)
			local yaw = ramp[3]
			local ramp3 = _wedge(r, {
				Name = "JumpRamp_" .. i, Size = Vector3.new(rs[1], rs[2], rs[3]),
				Color = C.RAMP, Material = MAT.DIRT,
			})
			ramp3.CFrame = CFrame.new(ramp[1], 3, ramp[2]) * CFrame.Angles(0, yaw + math.pi, 0)
			-- Landing pad 17 studs past the ramp (cosmetic; the TrackSeg is the floor)
			_part(r, {
				Name = "LandingPad_" .. i, Size = Vector3.new(TRACK_W - 4, 0.2, 22),
				CFrame = cf * CFrame.new(0, 0.1, -17),
				Color = C.RAMP, Material = MAT.DIRT, CanCollide = false, CastShadow = false,
			})
		end,
	})
end

local function _buildBoostPads(root)
	KIT:buildBoostPads(root, { color = C.BOOST_PAD })
end

local function _buildDriftCorners(root)
	KIT:buildDriftCorners(root, {
		visual = function(r, cf, i)
			_part(r, {
				Name = "DriftStrip_" .. i, Size = Vector3.new(TRACK_W - 2, 0.2, 38),
				CFrame = cf * CFrame.new(0, 0.12, 0),
				Color = Color3.fromRGB(255, 165, 20), Material = MAT.NEON,
				CanCollide = false, CastShadow = false, Transparency = 0.55,
			})
		end,
	})
end

local function _buildCheckpoints(root)
	KIT:buildCheckpoints(root, { archHeight = 17 })
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

	-- Reject tree positions near ANY part of the centerline (the old check
	-- only looked at node points, so trees grew inside long straights).
	local function _insideTrack(tx, tz)
		return GEO:project(tx, tz).dist < TRACK_W / 2 + 10
	end

	local builders = { _pine, _pine, _oak, _oak, _birch }
	local zones = Track.treeZones

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

-- ─── Finish line and start grid (TrackKit) ──────────────────────────────────

local function _buildFinishLine(root)
	KIT:buildFinish(root, { archColor = Color3.fromRGB(220, 55, 55) })
end

local function _buildStartGrid(root)
	KIT:buildStartGrid(root, { poleColor = Color3.fromRGB(240, 240, 240) })
	KIT:buildStartApron(root, {
		length = 24,
		floor = { name = "StartApron", color = C.TRACK, material = MAT.TRACK, thickness = 1 },
		wall = { name = "TrackWall", color = C.WALL, material = MAT.WOOD },
	})
end

-- ─── Main build ───────────────────────────────────────────────────────────────

local function buildForest()
	local root, farmSub, trackSub = TrackKit.newMap("ForestMap")

	_buildGround(root)
	_buildTrees(root)
	_buildFarmArea(farmSub)

	_buildTrack(trackSub)
	_buildWalls(trackSub)
	_buildSlowZones(trackSub)
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

return {
	build = buildForest,
	track = Track,
}
