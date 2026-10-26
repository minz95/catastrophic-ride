-- SkyMap.lua (ModuleScript; called by MapBuilders/SkyMapBuilder.server.lua)
-- Builds the SKY biome map per racetrack spec §4:
--   - planar centerline: two 270° cloud bends (an S, never crossing
--     itself) + canyon + descent
--     Z = 1500 → -2000 at altitude Y = 80
--   - 50-wide cloud road on a continuous floor, fenced by a see-through air
--     barrier with a cloud rail at flyer height, cloud puffs along the edges, invisible ceiling
--   - CP1 at bend A's western extent, CP2 at bend B's eastern extent
--
-- Every position and size comes from ReplicatedStorage.Shared.Tracks.SkyTrack.
-- The parts all tracks share (floor, fence, triggers, finish, start) come
-- from Modules.Maps.TrackKit; this file adds the sky and the scenery.
-- Resolves: Issue #10, #97, #130

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Tracks.SkyTrack)
local BiomeConfig = require(script.Parent.Parent.BiomeConfig)
local TrackKit = require(script.Parent.TrackKit)

local KIT = TrackKit.new(Track)
local _part, _wedge, _tag = TrackKit.part, TrackKit.wedge, TrackKit.tag

local C = {
	CLOUD_FLAT   = Color3.fromRGB(240, 245, 255),
	CLOUD_PUFF   = Color3.fromRGB(255, 255, 255),
	CLOUD_SHADOW = Color3.fromRGB(230, 233, 248),
	-- the road: a soft sky blue, darker than the white clouds round it (a
	-- near-white road under the sun was glaring and did not stand out)
	ROAD         = Color3.fromRGB(160, 190, 236),
	ROAD2        = Color3.fromRGB(150, 182, 232),
	ROAD_EDGE    = Color3.fromRGB(246, 206, 120),   -- gold edge line
	BARRIER      = Color3.fromRGB(170, 210, 250),   -- air barrier (see-through)
	RAIL         = Color3.fromRGB(212, 228, 250),   -- cloud rail
	SEA          = Color3.fromRGB(176, 200, 236),   -- cloud sea far below
	PLATFORM     = Color3.fromRGB(175, 155, 218),
	PLATFORM2    = Color3.fromRGB(135, 115, 188),
	PLATFORM3    = Color3.fromRGB(200, 180, 240),
	CRYSTAL      = Color3.fromRGB(155, 110, 255),
	CRYSTAL2     = Color3.fromRGB(100, 180, 255),
	CRYSTAL3     = Color3.fromRGB(255, 130, 220),
	BOOST        = Color3.fromRGB(195, 150, 255),
	BOOST_RING   = Color3.fromRGB(255, 200, 240),
	STAR         = Color3.fromRGB(255, 240, 100),
	ARCH         = Color3.fromRGB(175, 95, 255),
	ARROW        = Color3.fromRGB(255, 220, 80),
	UPDRAFT      = Color3.fromRGB(115, 200, 255),
	DRIFT_GLOW   = Color3.fromRGB(255, 130, 220),
}

local MAT = {
	CLOUD   = Enum.Material.SmoothPlastic,
	ROCK    = Enum.Material.Rock,
	CRYSTAL = Enum.Material.Neon,
	NEON    = Enum.Material.Neon,
}

local SKY_BASE_Y = Track.trackTop   -- floor top surface
local CORRIDOR_W = Track.width
local NODES      = Track.nodes

-- A squashed ball (Ball parts stay round; a Sphere mesh follows the size).
local function _ellipsoid(root, props)
	props.Material = props.Material or MAT.CLOUD
	props.CanCollide = false
	props.CastShadow = false
	local p = _part(root, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Track bounding box (farm included) plus margin.
local function _bbox(margin)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, n in ipairs(NODES) do
		x0 = math.min(x0, n[1]); x1 = math.max(x1, n[1])
		z0 = math.min(z0, n[2]); z1 = math.max(z1, n[2])
	end
	z1 = math.max(z1, Track.farm.cz + Track.farm.size[2] / 2)
	return x0 - margin, x1 + margin, z0 - margin, z1 + margin
end

-- ─── Sky backdrop + clouds ───────────────────────────────────────────────────

local function _buildClouds(root)
	local x0, x1, z0, z1 = _bbox(600)
	local cx, cz, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
	-- Backdrop blocks the Baseplate from showing through
	_part(root, {
		Name = "SkyBackdrop", Size = Vector3.new(w, 6, d),
		Position = Vector3.new(cx, SKY_BASE_Y - 55, cz),
		Color = C.SEA, Material = MAT.CLOUD,
		CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	})
	_part(root, {
		Name = "SkyHaze", Size = Vector3.new(w, 4, d),
		Position = Vector3.new(cx, SKY_BASE_Y - 48, cz),
		Color = Color3.fromRGB(175, 195, 235), Material = MAT.CLOUD,
		CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 0.5,
	})
	-- Puffy cloud clusters: a cloud sea below the road and big clouds
	-- beside it at road height (only where they cannot touch the lane).
	local ix0, ix1, iz0, iz1 = _bbox(300)
	local rng = Random.new(77)
	local function cluster(px, py, pz, size, name)
		local n = rng:NextInteger(4, 7)
		for k = 1, n do
			local r = size * rng:NextNumber(0.45, 0.8)
			_ellipsoid(root, {
				Name = name, Size = Vector3.new(r * 2, r * 1.1, r * 1.7),
				Position = Vector3.new(px + rng:NextNumber(-size, size), py + rng:NextNumber(0, size * 0.35)
					- (k == 1 and 0 or size * 0.1), pz + rng:NextNumber(-size * 0.6, size * 0.6)),
				Color = (k % 3 == 0) and C.CLOUD_SHADOW or C.CLOUD_PUFF,
			})
		end
	end
	for _ = 1, 60 do
		cluster(rng:NextNumber(ix0, ix1), SKY_BASE_Y + rng:NextNumber(-50, -25), rng:NextNumber(iz0, iz1),
			rng:NextNumber(25, 55), "CloudSea")
	end
	local placed, tries = 0, 0
	while placed < 40 and tries < 600 do
		tries += 1
		local px, pz = rng:NextNumber(ix0, ix1), rng:NextNumber(iz0, iz1)
		local size = rng:NextNumber(14, 30)
		if not KIT:inLane(px, pz, size * 1.9 + 8) then
			placed += 1
			cluster(px, SKY_BASE_Y + rng:NextNumber(-10, 30), pz, size, "CloudPuff")
		end
	end
end

-- Cloud puffs hugging the outside of the barrier, so the road reads as a
-- road through the clouds. Decoration only: outside the lane, no collision.
local PUFF_EVERY = 26

local function _buildEdgePuffs(root)
	local rng = Random.new(91)
	local geo = KIT.geo
	local idx = 0
	for i, seg in ipairs(geo.segments) do
		local nx, nz = -seg.dz, seg.dx
		for t = PUFF_EVERY / 2, seg.len, PUFF_EVERY do
			local roadY = geo:segHeight(i, t)
			for _, side in ipairs({ -1, 1 }) do
				local off = CORRIDOR_W / 2 + rng:NextNumber(7, 14)
				local px = seg.ax + seg.dx * t + nx * side * off
				local pz = seg.az + seg.dz * t + nz * side * off
				local r = rng:NextNumber(9, 15)
				if not KIT:inLane(px, pz, r * 0.8 + 3) then
					idx += 1
					_ellipsoid(root, {
						Name = "EdgePuff_" .. idx, Size = Vector3.new(r * 1.6, r * 0.8, r * 1.3),
						Position = Vector3.new(px, roadY + rng:NextNumber(-2, 2), pz),
						Color = (idx % 3 == 0) and C.CLOUD_SHADOW or C.CLOUD_FLAT,
					})
				end
			end
		end
	end
end

-- ─── Floor, fence, ceiling (TrackKit) ────────────────────────────────────────

local function _buildCorridor(root)
	KIT:buildSurface(root, {
		name = "TrackFloor", jointName = "TrackFloorJoint", thickness = 4, overlap = 4,
		colors = { C.ROAD, C.ROAD2 }, material = MAT.CLOUD,
		decorate = function(r, i, cf, segLen)
			for _, side in ipairs({ -1, 1 }) do
				_part(r, {
					Name = "EdgeLine_" .. i .. (side > 0 and "R" or "L"),
					Size = Vector3.new(1.2, 0.3, segLen),
					CFrame = cf * CFrame.new(side * (CORRIDOR_W / 2 - 3), 2.1, 0),
					Color = C.ROAD_EDGE, Material = MAT.CLOUD, CanCollide = false, CastShadow = false,
				})
			end
		end,
	})
	-- Air barrier: the touching pillar fence (flyers are ~1.5 studs wide;
	-- any gap is passable and below is the kill plane), drawn as one
	-- see-through pale-blue glass wall, with a cloud rail at flyer height so
	-- the edge is easy to read. Until 2026-10-22 the pillars alternated two
	-- neon colours: 60-stud stripes on both sides, hard on the eyes and not
	-- like a sky. (One slab per stretch instead of pillars left a pocket at
	-- the old figure-8 crossings that trapped the offline sim's novice driver.)
	KIT:buildWalls(root, {
		name = "SkyBarrier_",
		pillars = {
			size = Track.wallThickness, spacing = Track.wallThickness,
			colors = { C.BARRIER }, material = Enum.Material.Glass, transparency = 0.85,
			yLo = Track.wallYLo, yHi = Track.wallYHi,
		},
		rail = { name = "CloudRail", color = C.RAIL, material = MAT.CLOUD,
			y = Track.wallRailY, height = Track.wallRailHeight },
	})
	_buildEdgePuffs(root)
	-- invisible lid ceilingY - trackTop above the road, per layer (the
	-- corkscrew passes over itself)
	KIT:buildCeiling(root, Track.ceilingY - Track.trackTop, { name = "InvisibleCeiling" })
end

-- ─── Wayfinding arrows ───────────────────────────────────────────────────────
-- At every node where the heading changes by 12°+ (pointing along the
-- outgoing segment), and every ARROW_EVERY studs along long straights, so the
-- first turn after a long straight never reads as a dead end.

local ARROW_EVERY = 300

local function _floorArrow(root, idx, x, z, yaw, y)
	local cf = CFrame.new(x, (y or SKY_BASE_Y) + 0.3, z) * CFrame.Angles(0, yaw, 0)
	_part(root, {
		Name = "WayArrowShaft_" .. idx, Size = Vector3.new(2.4, 0.6, 14), CFrame = cf,
		Color = C.ARROW, Material = MAT.NEON, CanCollide = false, CastShadow = false, Transparency = 0.15,
	})
	local head = _wedge(root, {
		Name = "WayArrowHead_" .. idx, Size = Vector3.new(5, 0.6, 5),
		Color = C.ARROW, Material = MAT.NEON, CanCollide = false, CastShadow = false, Transparency = 0.15,
	})
	head.CFrame = cf * CFrame.new(0, 0, -9.5) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function _buildWayfindingArrows(root)
	local geo = KIT.geo
	local idx = 0
	for _, d in ipairs(geo:deflections()) do
		if math.abs(d.angle) >= 12 then
			idx += 1
			local seg = geo.segments[d.node]
			_floorArrow(root, idx, seg.ax, seg.az, math.atan2(-seg.dx, -seg.dz), seg.ay + 0.3)
		end
	end
	for _, seg in ipairs(geo.segments) do
		if seg.len > ARROW_EVERY * 0.8 then
			for t = ARROW_EVERY / 2, seg.len - 60, ARROW_EVERY do
				idx += 1
				_floorArrow(root, idx, seg.ax + seg.dx * t, seg.az + seg.dz * t, math.atan2(-seg.dx, -seg.dz),
					geo:segHeight(seg.index, t) + 0.3)
			end
		end
	end
end

-- ─── Floating islands and balloons (decoration, off the corridor) ───────────
-- At Track.crystalSeeds (the old crystal spires: neon sticks that read as
-- glare, not sky). Every fourth seed is a hot-air balloon instead.

local ISLAND = {
	GRASS   = Color3.fromRGB(120, 190, 95),
	ROCK    = Color3.fromRGB(150, 130, 115),
	ROCK2   = Color3.fromRGB(120, 104, 94),
	TRUNK   = Color3.fromRGB(120, 85, 55),
	LEAVES  = Color3.fromRGB(80, 160, 85),
	BALLOON = { Color3.fromRGB(240, 120, 110), Color3.fromRGB(250, 205, 100), Color3.fromRGB(120, 175, 240) },
	BASKET  = Color3.fromRGB(150, 105, 60),
}

local function _disc(root, name, cf, radius, height, color, material)
	return _part(root, {
		Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = cf * CFrame.Angles(0, 0, math.pi / 2),
		Color = color, Material = material, CanCollide = false, CastShadow = false,
	})
end

local function _island(root, i, x, y, z, radius, rng)
	local cf = CFrame.new(x, y, z)
	_disc(root, "IslandGrass_" .. i, cf, radius, 2, ISLAND.GRASS, Enum.Material.Grass)
	-- rocky underside: shrinking discs
	for k = 1, 4 do
		local r = radius * (1 - k * 0.2)
		_disc(root, "IslandRock_" .. i, cf * CFrame.new(0, -1 - k * radius * 0.22, 0), r, radius * 0.24,
			(k % 2 == 0) and ISLAND.ROCK2 or ISLAND.ROCK, Enum.Material.Rock)
	end
	for t = 1, rng:NextInteger(1, 3) do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, radius * 0.5)
		local h = rng:NextNumber(6, 11)
		local tx, tz = x + math.cos(a) * d, z + math.sin(a) * d
		_part(root, {
			Name = "IslandTrunk_" .. i, Size = Vector3.new(1.2, h, 1.2),
			Position = Vector3.new(tx, y + 1 + h / 2, tz),
			Color = ISLAND.TRUNK, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false,
		})
		_ellipsoid(root, {
			Name = "IslandTree_" .. i, Size = Vector3.new(h * 0.8, h * 0.7, h * 0.8),
			Position = Vector3.new(tx, y + 1 + h, tz), Color = ISLAND.LEAVES, Material = Enum.Material.Grass,
		})
	end
end

local function _balloon(root, i, x, y, z, rng)
	local color = ISLAND.BALLOON[(i % #ISLAND.BALLOON) + 1]
	_ellipsoid(root, {
		Name = "Balloon_" .. i, Size = Vector3.new(16, 19, 16),
		Position = Vector3.new(x, y + 14, z), Color = color, Material = Enum.Material.SmoothPlastic,
	})
	_ellipsoid(root, {
		Name = "BalloonBand_" .. i, Size = Vector3.new(16.4, 4, 16.4),
		Position = Vector3.new(x, y + 14, z), Color = Color3.fromRGB(250, 248, 240), Material = Enum.Material.SmoothPlastic,
	})
	_part(root, {
		Name = "BalloonBasket_" .. i, Size = Vector3.new(3.5, 3, 3.5),
		Position = Vector3.new(x, y, z), Color = ISLAND.BASKET, Material = Enum.Material.WoodPlanks,
		CanCollide = false, CastShadow = false,
	})
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		_part(root, {
			Name = "BalloonRope_" .. i, Size = Vector3.new(0.2, 4.5, 0.2),
			Position = Vector3.new(x + c[1] * 1.6, y + 3.6, z + c[2] * 1.6),
			Color = Color3.fromRGB(90, 70, 50), CanCollide = false, CastShadow = false,
		})
	end
end

local function _buildCrystalClusters(root)
	local rng = Random.new(33)
	for ci, cs in ipairs(Track.crystalSeeds) do
		if ci % 4 == 0 then
			_balloon(root, ci, cs[1], SKY_BASE_Y + rng:NextNumber(15, 40), cs[2], rng)
		else
			local radius = rng:NextNumber(10, 18)
			while radius > 4 and KIT:inLane(cs[1], cs[2], radius + 4) do radius -= 2 end
			_island(root, ci, cs[1], SKY_BASE_Y - rng:NextNumber(4, 16), cs[2], radius, rng)
		end
	end
end

-- ─── Updraft zones (hazard) ──────────────────────────────────────────────────

local function _buildUpdraftZones(root)
	for i, uz in ipairs(Track.updraftZones) do
		local baseY = SKY_BASE_Y - 18 + KIT:riseAt(uz[1], uz[2])   -- on the dive too
		_part(root, {
			Name = "UpdraftVisual_" .. i, Size = Vector3.new(14, 55, 14),
			Position = Vector3.new(uz[1], baseY, uz[2]),
			Color = C.UPDRAFT, Material = MAT.NEON,
			CanCollide = false, Transparency = 0.72, CastShadow = false,
		})
		local trigger = _part(root, {
			Name = "UpdraftZone_" .. i, Size = Vector3.new(18, 70, 18),
			Position = Vector3.new(uz[1], baseY, uz[2]),
			CanCollide = false, Transparency = 1,
		})
		_tag(trigger, "UpdraftZone")
	end
end

-- ─── Sky tower inside the S6 corkscrew ──────────────────────────────────────

-- A white tower on a floating island, rising through the corkscrew, with a
-- golden beacon above the top turn. Decoration only (inside the inner wall).
local function _buildSkyTower(root)
	local st = Track.skyTower
	if not st then return end
	local base = SKY_BASE_Y - 30
	_island(root, "Tower", st.x, base, st.z, st.r, Random.new(5))
	local h = 150
	for k = 0, 4 do
		local r = st.r * (0.42 - k * 0.04)
		_part(root, {
			Name = "SkyTowerTier", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h / 5, r * 2, r * 2),
			CFrame = CFrame.new(st.x, base + h / 10 + k * h / 5, st.z) * CFrame.Angles(0, 0, math.pi / 2),
			Color = k % 2 == 0 and C.CLOUD_PUFF or C.CLOUD_SHADOW, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false,
		})
	end
	_part(root, {
		Name = "SkyTowerBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 16),
		Position = Vector3.new(st.x, base + h + 8, st.z),
		Color = C.ARCH, Material = MAT.NEON, CanCollide = false, CastShadow = false,
	})
end

-- ─── Triggers (TrackKit) ─────────────────────────────────────────────────────

local function _buildTriggers(root)
	KIT:buildDriftCorners(root, {
		-- a ring facing down the track, flown through at hover height
		visual = function(r, cf, i)
			local ringCF = cf * CFrame.new(0, 4, 0)
			local ringR = 14
			for seg = 0, 7 do
				local angle = (seg / 8) * math.pi * 2
				_part(r, {
					Name = "DriftRingArc_" .. i .. "_" .. seg, Size = Vector3.new(2, 2, 8),
					CFrame = ringCF * CFrame.new(math.cos(angle) * ringR, math.sin(angle) * ringR, 0) * CFrame.Angles(0, 0, angle),
					Color = C.DRIFT_GLOW, Material = MAT.CRYSTAL, CanCollide = false, CastShadow = false,
				})
			end
			_part(r, {
				Name = "DriftRingStar_" .. i, Size = Vector3.new(4, 4, 0.5), CFrame = ringCF,
				Color = C.STAR, Material = MAT.NEON, CanCollide = false, CastShadow = false,
			})
		end,
	})
	KIT:buildJumpZones(root, {
		-- flyers hold altitude, so jump zones give a forward boost; dressed as ramps
		visual = function(r, cf, i)
			_part(r, {
				Name = "JumpRamp_" .. i, Size = Vector3.new(CORRIDOR_W - 14, 1.2, 14),
				CFrame = cf * CFrame.new(0, 0.8, 0),
				Color = C.CLOUD_PUFF, Material = MAT.NEON,
				CanCollide = false, CastShadow = false, Transparency = 0.3,
			})
		end,
	})
	KIT:buildBoostPads(root, { color = C.BOOST, ringColor = C.BOOST_RING })
	-- beacon column visible from anywhere, label visible across the map
	KIT:buildCheckpoints(root, { archHeight = 34, beacon = 120, labelDistance = 1500 })
end

-- ─── Farm platform (FARMING phase only) ──────────────────────────────────────

local function _buildFarmPlatform(root)
	local farm = Track.farm
	local cx, cz, w, d = farm.cx, farm.cz, farm.size[1], farm.size[2]
	_part(root, {
		Name = "FarmPlatform", Size = Vector3.new(w, 9, d),
		Position = Vector3.new(cx, SKY_BASE_Y - 4.5, cz),
		Color = C.PLATFORM3, Material = MAT.ROCK,
	})
	for _, side in ipairs({ -1, 1 }) do
		local bev = _wedge(root, {
			Name = "FarmBevel", Size = Vector3.new(w, 5, 6),
			Color = C.PLATFORM2, Material = MAT.ROCK, CanCollide = false,
		})
		bev.CFrame = CFrame.new(cx, SKY_BASE_Y - 7.5, cz + side * (d / 2 + 5))
			* CFrame.Angles(0, side > 0 and 0 or math.pi, 0)
	end
	for _, ox in ipairs({ -1, 1 }) do
		for _, oz in ipairs({ -1, 0, 1 }) do
			_part(root, {
				Name = "CrystalPillar", Size = Vector3.new(5, 50, 5),
				Position = Vector3.new(cx + ox * (w / 2 - 15), SKY_BASE_Y - 33, cz + oz * (d / 2 - 15)),
				Color = C.CRYSTAL, Material = MAT.CRYSTAL, CanCollide = false, CastShadow = false,
			})
		end
	end
	for _, rz in ipairs({ cz - 45, cz + 45 }) do
		for _, ox in ipairs({ -65, -32, 0, 32, 65 }) do
			local sp = _part(root, {
				Name = "FarmSpawnPoint", Size = Vector3.new(4, 0.5, 4),
				Position = Vector3.new(cx + ox, SKY_BASE_Y + 4.5, rz),
				Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
				CanCollide = false, Transparency = 0.5,
			})
			_tag(sp, "FarmSpawn")
		end
	end
end

-- ─── Start, finish, kill plane ───────────────────────────────────────────────

local function _buildStartAndFinish(root)
	KIT:buildStartGrid(root, { poleColor = C.ARCH })
	KIT:buildStartApron(root, {
		length = 24,
		floor = { name = "StartApron", color = C.ROAD, material = MAT.CLOUD, thickness = 4 },
		wall = { name = "SkyBarrier_Apron", color = C.BARRIER, material = Enum.Material.Glass, transparency = 0.8 },
	})
	KIT:buildFinish(root, { poleColor = C.ARCH, poleMaterial = MAT.CRYSTAL, archColor = C.ARCH })
	KIT:buildEndWall(root, { name = "SkyBarrier_End", color = C.BARRIER, material = Enum.Material.Glass, transparency = 0.6 })
	local x0, x1, z0, z1 = _bbox(600)
	local kill = _part(root, {
		Name = "KillPlane", Size = Vector3.new(x1 - x0, 4, z1 - z0),
		Position = Vector3.new((x0 + x1) / 2, BiomeConfig.SKY.killPlaneY, (z0 + z1) / 2),
		CanCollide = false, Transparency = 1,
	})
	_tag(kill, "KillPlane")
end

-- ─── Main build ──────────────────────────────────────────────────────────────

local function buildSky()
	local root, farmSub, trackSub = TrackKit.newMap("SkyMap")

	_buildClouds(root)
	_buildUpdraftZones(root)
	_buildSkyTower(root)
	_buildFarmPlatform(farmSub)

	_buildCorridor(trackSub)
	_buildWayfindingArrows(trackSub)
	_buildCrystalClusters(trackSub)
	_buildTriggers(trackSub)
	_buildStartAndFinish(trackSub)

	TrackKit.tag(root, "BiomeMap")
	root:SetAttribute("Biome", "SKY")

	print("[SkyMapBuilder] Built SKY map (" .. #root:GetDescendants() .. " descendants)")
	return root
end

return {
	build = buildSky,
	track = Track,
}
