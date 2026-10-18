-- SkyMap.lua (ModuleScript; called by MapBuilders/SkyMapBuilder.server.lua)
-- Builds the SKY biome map per racetrack spec §4:
--   - planar figure-8 centerline (two 360° loops + plaza + canyon + descent)
--     Z = 1500 → -2000 at altitude Y = 80
--   - 50-wide corridor on a continuous floor, fenced by touching crystal
--     pillars (open where the figure-8 crosses itself), invisible ceiling
--   - CP1 at Loop A's western extent, CP2 at Loop B's eastern extent
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
		Color = Color3.fromRGB(140, 165, 220), Material = MAT.CLOUD,
		CanCollide = false, CastShadow = false,
	})
	_part(root, {
		Name = "SkyHaze", Size = Vector3.new(w, 4, d),
		Position = Vector3.new(cx, SKY_BASE_Y - 48, cz),
		Color = Color3.fromRGB(175, 195, 235), Material = MAT.CLOUD,
		CanCollide = false, CastShadow = false, Transparency = 0.5,
	})
	local ix0, ix1, iz0, iz1 = _bbox(300)
	local rng = Random.new(77)
	for _ = 1, 35 do
		local px, pz = rng:NextNumber(ix0, ix1), rng:NextNumber(iz0, iz1)
		local py = SKY_BASE_Y + rng:NextNumber(-45, -20)
		local cw, cd = rng:NextNumber(50, 140), rng:NextNumber(25, 70)
		_part(root, {
			Name = "CloudSlab", Size = Vector3.new(cw, rng:NextNumber(4, 8), cd),
			Position = Vector3.new(px, py, pz),
			Color = C.CLOUD_SHADOW, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false, Transparency = 0.55,
		})
		_part(root, {
			Name = "CloudSlabTop", Size = Vector3.new(cw * 0.85, 3, cd * 0.85),
			Position = Vector3.new(px, py + 4, pz),
			Color = C.CLOUD_FLAT, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false, Transparency = 0.45,
		})
	end
	-- Puffs at corridor height only where they cannot sit on the corridor.
	local placed, tries = 0, 0
	while placed < 45 and tries < 400 do
		tries += 1
		local px, pz = rng:NextNumber(ix0, ix1), rng:NextNumber(iz0, iz1)
		local pr = rng:NextNumber(10, 28)
		local py = SKY_BASE_Y + rng:NextNumber(-12, 25)
		if not KIT:inLane(px, pz, pr * 1.3 + 4) then
			placed += 1
			_part(root, {
				Name = "CloudPuff", Size = Vector3.new(pr * 2, pr, pr * 1.3),
				Position = Vector3.new(px, py, pz),
				Color = C.CLOUD_PUFF, Material = MAT.CLOUD,
				CanCollide = false, CastShadow = false, Transparency = 0.4,
			})
		end
	end
end

-- ─── Floor, fence, ceiling (TrackKit) ────────────────────────────────────────

local function _buildCorridor(root)
	KIT:buildSurface(root, {
		name = "TrackFloor", jointName = "TrackFloorJoint", thickness = 4, overlap = 4,
		colors = { C.PLATFORM, C.PLATFORM2, C.PLATFORM3 }, material = MAT.ROCK,
		decorate = function(r, i, cf, segLen)
			for _, side in ipairs({ -1, 1 }) do
				_part(r, {
					Name = "EdgeGlow_" .. i .. (side > 0 and "R" or "L"),
					Size = Vector3.new(1.2, 0.6, segLen + 8),
					CFrame = cf * CFrame.new(side * (CORRIDOR_W / 2 - 0.8), 2.4, 0),
					Color = (i % 2 == 0) and C.CRYSTAL or C.CRYSTAL2,
					Material = MAT.NEON, CanCollide = false, CastShadow = false,
				})
			end
		end,
	})
	-- Crystal pillar fence, packed edge to edge (flyers are ~1.5 studs wide,
	-- any gap is passable and below is the kill plane).
	KIT:buildWalls(root, {
		name = "EdgePillar_",
		pillars = {
			size = Track.wallThickness, spacing = Track.wallThickness,
			colors = { C.CRYSTAL, C.CRYSTAL2 }, material = MAT.CRYSTAL,
			yLo = Track.wallYLo, yHi = Track.wallYHi,
		},
	})
	local x0, x1, z0, z1 = _bbox(200)
	_part(root, {
		Name = "InvisibleCeiling", Size = Vector3.new(x1 - x0, 2, z1 - z0),
		Position = Vector3.new((x0 + x1) / 2, Track.ceilingY, (z0 + z1) / 2),
		CanCollide = true, Transparency = 1, CastShadow = false,
	})
end

-- ─── Wayfinding arrows ───────────────────────────────────────────────────────
-- At every node where the heading changes by 12°+ (pointing along the
-- outgoing segment), and every ARROW_EVERY studs along long straights, so the
-- first turn after a long straight never reads as a dead end.

local ARROW_EVERY = 300

local function _floorArrow(root, idx, x, z, yaw)
	local cf = CFrame.new(x, SKY_BASE_Y + 0.3, z) * CFrame.Angles(0, yaw, 0)
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
			_floorArrow(root, idx, seg.ax, seg.az, math.atan2(-seg.dx, -seg.dz))
		end
	end
	for _, seg in ipairs(geo.segments) do
		if seg.len > ARROW_EVERY * 0.8 then
			for t = ARROW_EVERY / 2, seg.len - 60, ARROW_EVERY do
				idx += 1
				_floorArrow(root, idx, seg.ax + seg.dx * t, seg.az + seg.dz * t, math.atan2(-seg.dx, -seg.dz))
			end
		end
	end
end

-- ─── Crystal clusters (decoration, off the corridor) ─────────────────────────

local function _buildCrystalClusters(root)
	local crystalColors = { C.CRYSTAL, C.CRYSTAL2, C.CRYSTAL3 }
	local rng = Random.new(33)
	for ci, cs in ipairs(Track.crystalSeeds) do
		local baseY = SKY_BASE_Y - 5
		for s = 1, rng:NextInteger(3, 5) do
			local ox = cs[1] + rng:NextNumber(-12, 12)
			local oz = cs[2] + rng:NextNumber(-10, 10)
			local sh = rng:NextNumber(20, 50)
			local sw = rng:NextNumber(2, 5)
			local color = crystalColors[rng:NextInteger(1, 3)]
			_part(root, {
				Name = "CrystalSpire_" .. ci .. "_" .. s, Size = Vector3.new(sw, sh, sw),
				Position = Vector3.new(ox, baseY + sh / 2, oz),
				Color = color, Material = MAT.CRYSTAL, CanCollide = false, CastShadow = false,
			})
			local tip = _wedge(root, {
				Name = "CrystalTip_" .. ci .. "_" .. s, Size = Vector3.new(sw, sh * 0.35, sw),
				Color = color, Material = MAT.CRYSTAL, CanCollide = false, CastShadow = false,
			})
			tip.CFrame = CFrame.new(ox, baseY + sh + sh * 0.18, oz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		end
	end
end

-- ─── Updraft zones (hazard) ──────────────────────────────────────────────────

local function _buildUpdraftZones(root)
	for i, uz in ipairs(Track.updraftZones) do
		local baseY = SKY_BASE_Y - 18
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
	KIT:buildFinish(root, { poleColor = C.ARCH, poleMaterial = MAT.CRYSTAL, archColor = C.ARCH })
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
