-- SkyMapBuilder.server.lua
-- Procedurally builds the SKY biome map per racetrack spec §4:
--   - ~7500-stud planar figure-8 centerline (two 360° loops + plaza + canyon)
--     along Z=1500 → -2000 at altitude Y=80
--   - 50-wide corridor with continuous solid floor (no inter-platform gaps)
--   - Invisible vertical side walls at ±25 studs offset, Y 54 → 114
--   - Invisible ceiling at Y=120
--   - Crystal clusters relocated outside invisible barriers (decorative)
--   - CP1 inside S2 Loop A western extent, CP2 inside S4 Loop B eastern extent
-- Resolves: Issue #10, #97, #130

local CollectionService = game:GetService("CollectionService")

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
	STAR         = Color3.fromRGB(255, 240, 100),
	ARCH         = Color3.fromRGB(175, 95, 255),
	ARCH_RING    = Color3.fromRGB(255, 200, 80),
	UPDRAFT      = Color3.fromRGB(115, 200, 255),
	DRIFT_GLOW   = Color3.fromRGB(255, 130, 220),
}

local MAT = {
	CLOUD   = Enum.Material.SmoothPlastic,
	ROCK    = Enum.Material.Rock,
	CRYSTAL = Enum.Material.Neon,
	NEON    = Enum.Material.Neon,
	METAL   = Enum.Material.Metal,
}

local SKY_BASE_Y = 80      -- floor top surface
local FLOOR_TH   = 4       -- floor thickness
local CORRIDOR_W = 50      -- matches Constants.TRACK.SKY.width
local WALL_Y_LO  = 54      -- invisible side wall bottom (spec §4.4)
local WALL_Y_HI  = 114     -- invisible side wall top
local CEILING_Y  = 120
local FINISH_Z   = -2000   -- matches Constants.TRACK.SKY.zFinish

local function _part(parent, props)
	local p = Instance.new("Part")
	p.Anchored   = true
	p.CanCollide = true
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

local function _tag(part, tagName) CollectionService:AddTag(part, tagName) end

local function _getOrCreateMap()
	local maps = workspace:FindFirstChild("Maps") or (function()
		local f = Instance.new("Folder"); f.Name = "Maps"; f.Parent = workspace; return f
	end)()
	local existing = maps:FindFirstChild("SkyMap")
	if existing then existing:Destroy() end
	local model = Instance.new("Model")
	model.Name   = "SkyMap"
	model.Parent = maps
	return model
end

-- ─── Track centerline nodes (figure-8 per spec §4.1) ─────────────────────────
-- Two 360° loops (A west, B east) connected by a plaza, then canyon + descent.

local NODES = {
	-- S1 Launch Tunnel (~700, Z 1500 → 800, straight)
	{   0, 1500 }, -- N1  start of corridor
	{   0, 1200 }, -- N2
	{   0,  950 }, -- N3
	{   0,  800 }, -- N4  entry to Loop A

	-- S2 Cloud Loop A (CW, ~1840, around center (-300, 800), R=300)
	{ -88,  588 }, -- N5
	{-300,  500 }, -- N6
	{-512,  588 }, -- N7
	{-600,  800 }, -- N8  CP1 (western extent — unreachable on straight-line path)
	{-512, 1012 }, -- N9
	{-300, 1100 }, -- N10 (Loop A apex / drift corner)
	{ -88, 1012 }, -- N11
	{   0,  800 }, -- N12 loop close (returns to N4 position)

	-- S3 Crossover Plaza (~400, Z 800 → 400, straight)
	{   0,  600 }, -- N13
	{   0,  400 }, -- N14 entry to Loop B

	-- S4 Cloud Loop B (CCW, ~1840, around center (300, 400), R=300)
	{  88,  188 }, -- N15
	{ 300,  100 }, -- N16 (Loop B apex / drift corner)
	{ 512,  188 }, -- N17
	{ 600,  400 }, -- N18 CP2 (eastern extent)
	{ 512,  612 }, -- N19
	{ 300,  700 }, -- N20
	{  88,  612 }, -- N21
	{   0,  400 }, -- N22 loop close

	-- S5 Crystal Canyon (~1800, zigzag Z 400 → -1000)
	{ -80,  220 }, -- N23
	{  80,   40 }, -- N24
	{ -80, -140 }, -- N25
	{  80, -320 }, -- N26
	{ -80, -500 }, -- N27
	{  80, -680 }, -- N28
	{ -80, -860 }, -- N29
	{   0,-1000 }, -- N30 end S5

	-- S6 Final Descent (~1000, straight Z -1000 → -2000)
	{   0,-1400 }, -- N31
	{   0,-1700 }, -- N32
	{   0,-2000 }, -- N33 FinishLine
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

-- ─── Sky backdrop + clouds ───────────────────────────────────────────────────

local function _buildClouds(root)
	-- Sky backdrop blocks the Baseplate from showing through
	_part(root, {
		Name = "SkyBackdrop", Size = Vector3.new(3000, 6, 5000),
		Position = Vector3.new(0, SKY_BASE_Y - 55, -250),
		Color = Color3.fromRGB(140, 165, 220),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false,
	})
	_part(root, {
		Name = "SkyHaze", Size = Vector3.new(3000, 4, 5000),
		Position = Vector3.new(0, SKY_BASE_Y - 48, -250),
		Color = Color3.fromRGB(175, 195, 235),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false, Transparency = 0.5,
	})

	local rng = Random.new(77)
	for _ = 1, 35 do
		local cx = rng:NextNumber(-1200, 1200)
		local cy = SKY_BASE_Y + rng:NextNumber(-45, -20)
		local cz = rng:NextNumber(-2200, 1800)
		local cw = rng:NextNumber(50, 140)
		local cd = rng:NextNumber(25, 70)
		_part(root, {
			Name = "CloudSlab", Size = Vector3.new(cw, rng:NextNumber(4, 8), cd),
			Position = Vector3.new(cx, cy, cz),
			Color = C.CLOUD_SHADOW, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false, Transparency = 0.55,
		})
		_part(root, {
			Name = "CloudSlabTop", Size = Vector3.new(cw * 0.85, 3, cd * 0.85),
			Position = Vector3.new(cx, cy + 4, cz),
			Color = C.CLOUD_FLAT, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false, Transparency = 0.45,
		})
	end
	for _ = 1, 45 do
		local px = rng:NextNumber(-1100, 1100)
		local py = SKY_BASE_Y + rng:NextNumber(-12, 25)
		local pz = rng:NextNumber(-2100, 1700)
		local pr = rng:NextNumber(10, 28)
		_part(root, {
			Name = "CloudPuff", Size = Vector3.new(pr * 2, pr, pr * 1.3),
			Position = Vector3.new(px, py, pz),
			Color = C.CLOUD_PUFF, Material = MAT.CLOUD,
			CanCollide = false, CastShadow = false, Transparency = 0.4,
		})
	end
end

-- ─── Continuous track floor (spec §4.4: no inter-platform gaps) ──────────────

-- Track surface friction. Roblox vehicles here use BodyVelocity-based
-- propulsion (RacingClient _driveLoop), so floor friction acts as pure drag,
-- not traction. Default Rock = 0.5 caused noticeable "sticky" sections —
-- 0.05 with frictionWeight=100 keeps the vehicle gliding.
local LOW_FRICTION_FLOOR = PhysicalProperties.new(1, 0.05, 0.1, 100, 1)

local function _buildFloor(root)
	local colors = { C.PLATFORM, C.PLATFORM2, C.PLATFORM3 }
	for i = 1, #NODES - 1 do
		local a, b = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		if segLen < 0.1 then continue end
		local cf = _segCF(a[1], a[2], b[1], b[2], SKY_BASE_Y - FLOOR_TH / 2)
		local floor = _part(root, {
			Name     = "TrackFloor_" .. i,
			Size     = Vector3.new(CORRIDOR_W, FLOOR_TH, segLen + 8),
			Color    = colors[((i - 1) % 3) + 1],
			Material = MAT.ROCK,
		})
		floor.CustomPhysicalProperties = LOW_FRICTION_FLOOR
		floor.CFrame = cf

		-- Edge glow stripes on both sides for visibility
		for _, side in ipairs({ -1, 1 }) do
			local stripe = _part(root, {
				Name = "EdgeGlow_" .. i .. (side > 0 and "R" or "L"),
				Size = Vector3.new(1.2, 0.6, segLen + 8),
				Color = (i % 2 == 0) and C.CRYSTAL or C.CRYSTAL2,
				Material = MAT.NEON, CanCollide = false, CastShadow = false,
			})
			stripe.CFrame = cf * CFrame.new(side * (CORRIDOR_W / 2 - 0.8), FLOOR_TH / 2 + 0.4, 0)
		end
	end
end

-- ─── Safety shoulder (catches vehicles that squeeze through pillar gaps) ────
-- Without a shoulder, threading a 4-stud doorway = immediate fall (kill plane).
-- A 6-stud solid ledge outside each pillar row gives a "yes you can shortcut,
-- but you have to commit to it" feel rather than instant death.

local SHOULDER_W = 6

local function _buildShoulders(root)
	for i = 1, #NODES - 1 do
		local a, b = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		if segLen < 0.1 then continue end
		local cf = _segCF(a[1], a[2], b[1], b[2], SKY_BASE_Y - FLOOR_TH / 2)
		for _, side in ipairs({ -1, 1 }) do
			local shoulder = _part(root, {
				Name = "Shoulder_" .. i .. (side > 0 and "R" or "L"),
				Size = Vector3.new(SHOULDER_W, FLOOR_TH, segLen + 8),
				Color = C.PLATFORM2,
				Material = MAT.ROCK,
				CastShadow = false,
			})
			shoulder.CustomPhysicalProperties = LOW_FRICTION_FLOOR
			-- Centerline of shoulder is at corridor edge + half width + tiny gap
			shoulder.CFrame = cf * CFrame.new(side * (CORRIDOR_W / 2 + SHOULDER_W / 2 + 0.2), 0, 0)
		end
	end
end

-- ─── Edge barriers (spec §4.4 revised: visible permeable pillars) ───────────
-- Replaces the original invisible CanCollide=true walls. Players reported the
-- mystery "I just stopped" effect with no way around. New design:
--   - Crystal pillars (2x2 stud, neon) along corridor edge — visible
--   - Pillar every PILLAR_SPACING studs along the track
--   - Every GAP_INTERVAL studs of *track-cumulative* distance, an opening of
--     2 * GAP_HALF_WIDTH studs is left for risky shortcuts
--   - Running-distance gap pattern (not per-segment) so even short segments at
--     sharp corners still get gaps — guarantees no impassable sub-section

-- SKY pillars: now a continuous solid fence with NO doorways. SKY vehicles
-- (flyers) have a ~1.5-stud-wide chassis hitbox, so any gap wide enough to be
-- visually "permeable" is physically passable. Players reported drifting
-- through 4-stud doorways into the kill plane. Doorways and pillar spacing
-- have been tightened so adjacent pillars touch:
--   - PILLAR_SPACING = 2 (pillar size, no gap between adjacent)
--   - No doorways (GAP_HALF_WIDTH = 0)
-- Slow-zone shortcut is no longer possible on SKY — falling off is genuinely
-- catastrophic so the wall is binary: stay on track or kill plane.
local PILLAR_SPACING = 2
local GAP_INTERVAL   = 1000  -- unused (GAP_HALF_WIDTH=0)
local GAP_HALF_WIDTH = 0

-- High frictionWeight + very low friction makes the vehicle slide *along*
-- the pillars (and other walls) instead of getting brake-pinned by them.
-- Roblox blends surface frictions weighted: with weight=100 and friction=0.05
-- on the wall vs default tire friction, contact friction ≈ 0.054.
local LOW_FRICTION = PhysicalProperties.new(1, 0.05, 0.1, 100, 1)

local function _isInGap(arcPos)
	local nearestGapCenter = math.floor(arcPos / GAP_INTERVAL + 0.5) * GAP_INTERVAL
	return math.abs(arcPos - nearestGapCenter) < GAP_HALF_WIDTH
end

local function _buildEdgeBarriers(root)
	local wallH = WALL_Y_HI - WALL_Y_LO
	local pillarColors = { C.CRYSTAL, C.CRYSTAL2 }
	local arcStart = 0  -- cumulative arc-distance at start of current segment
	for i = 1, #NODES - 1 do
		local a, b = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		if segLen < 0.1 then continue end
		local cf = _segCF(a[1], a[2], b[1], b[2], (WALL_Y_LO + WALL_Y_HI) / 2)
		local numPillars = math.max(1, math.floor(segLen / PILLAR_SPACING))
		for slot = 0, numPillars - 1 do
			local relAlong = (slot + 0.5) * PILLAR_SPACING       -- distance from seg start
			local arcPos   = arcStart + relAlong                 -- cumulative arc distance
			if _isInGap(arcPos) then continue end
			local localZ = relAlong - segLen / 2                 -- CFrame-local Z
			for _, side in ipairs({ -1, 1 }) do
				local pillar = _part(root, {
					Name = "EdgePillar_" .. i .. "_" .. slot .. (side > 0 and "R" or "L"),
					Size = Vector3.new(2, wallH, 2),
					Color = pillarColors[(slot % 2) + 1],
					Material = MAT.CRYSTAL,
					CanCollide = true, CastShadow = false,
				})
				pillar.CustomPhysicalProperties = LOW_FRICTION
				pillar.CFrame = cf * CFrame.new(side * (CORRIDOR_W / 2 + 1), 0, localZ)
			end
		end
		arcStart = arcStart + segLen
	end
end

-- ─── Invisible ceiling (spec §4.4: Y=120) ────────────────────────────────────

local function _buildInvisibleCeiling(root)
	_part(root, {
		Name = "InvisibleCeiling",
		Size = Vector3.new(2800, 2, 5000),
		Position = Vector3.new(0, CEILING_Y, -250),
		CanCollide = true, Transparency = 1, CastShadow = false,
	})
end

-- ─── Decorative crystal clusters (outside walls per spec §4.7) ───────────────

local function _buildCrystalClusters(root)
	local seeds = {
		-- S1 area decoration (X = ±90, north of N1)
		{  90, 1380 }, { -90, 1380 }, {  90, 1080 }, { -90, 1080 },
		-- Loop A outer ring (west of west boundary)
		{ -700,  800 }, { -680,  500 }, { -680, 1100 }, { -560, 1240 }, { -560,  360 },
		-- Loop B outer ring (east of east boundary)
		{  700,  400 }, {  680,  100 }, {  680,  700 }, {  560,  840 }, {  560,  -40 },
		-- S5 canyon outer (X ≈ ±150)
		{ -160,  100 }, {  160, -100 }, { -160, -340 }, {  160, -560 },
		{ -160, -800 }, {  160, -940 },
		-- S6 descent decoration
		{   90, -1500 }, {  -90, -1500 }, {   90, -1800 }, {  -90, -1800 },
	}
	local crystalColors = { C.CRYSTAL, C.CRYSTAL2, C.CRYSTAL3 }
	local rng = Random.new(33)
	for ci, cs in ipairs(seeds) do
		local baseY = SKY_BASE_Y - 5
		for s = 1, rng:NextInteger(3, 5) do
			local ox = cs[1] + rng:NextNumber(-12, 12)
			local oz = cs[2] + rng:NextNumber(-10, 10)
			local sh = rng:NextNumber(20, 50)
			local sw = rng:NextNumber(2, 5)
			local color = crystalColors[rng:NextInteger(1, 3)]
			_part(root, {
				Name = "CrystalSpire_" .. ci .. "_" .. s,
				Size = Vector3.new(sw, sh, sw),
				Position = Vector3.new(ox, baseY + sh / 2, oz),
				Color = color, Material = MAT.CRYSTAL,
				CanCollide = false, CastShadow = false,
			})
			local tip = _wedge(root, {
				Name = "CrystalTip_" .. ci .. "_" .. s,
				Size = Vector3.new(sw, sh * 0.35, sw),
				Color = color, Material = MAT.CRYSTAL,
				CanCollide = false, CastShadow = false,
			})
			tip.CFrame = CFrame.new(ox, baseY + sh + sh * 0.18, oz)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		end
	end
end

-- ─── Updraft zones (kept as physics zones; floor is now continuous) ──────────

local function _buildUpdraftZones(root)
	local zones = {
		{ -300,  800 },  -- inside Loop A center
		{  300,  400 },  -- inside Loop B center
		{    0, -1200 }, -- mid canyon recovery
	}
	for i, uz in ipairs(zones) do
		local ux, uz2 = uz[1], uz[2]
		local baseY = SKY_BASE_Y - 18
		_part(root, {
			Name = "UpdraftVisual_" .. i,
			Size = Vector3.new(14, 55, 14),
			Position = Vector3.new(ux, baseY, uz2),
			Color = C.UPDRAFT, Material = MAT.NEON,
			CanCollide = false, Transparency = 0.72, CastShadow = false,
		})
		local trigger = _part(root, {
			Name = "UpdraftZone_" .. i,
			Size = Vector3.new(18, 70, 18),
			Position = Vector3.new(ux, baseY, uz2),
			CanCollide = false, Transparency = 1,
		})
		_tag(trigger, "UpdraftZone")
	end
end

-- ─── Drift corners (3 per spec §4.3: loop apexes + canyon entry) ─────────────

local function _buildDriftCorners(root)
	local corners = {
		{ -300, 1100 },  -- N10 Loop A north apex
		{  300,  100 },  -- N16 Loop B south apex
		{  -80, -140 },  -- N25 canyon zigzag mid-entry
	}
	for i, c in ipairs(corners) do
		local rx, rz = c[1], c[2]
		local ry = SKY_BASE_Y + 4
		local ringR = 14
		for seg = 0, 7 do
			local angle = (seg / 8) * math.pi * 2
			local arc = _part(root, {
				Name = "DriftRingArc_" .. i .. "_" .. seg,
				Size = Vector3.new(2, 2, 8),
				Color = C.DRIFT_GLOW, Material = MAT.CRYSTAL,
				CanCollide = false, CastShadow = false,
			})
			arc.CFrame = CFrame.new(rx + math.cos(angle) * ringR, ry + math.sin(angle) * ringR, rz)
				* CFrame.Angles(0, 0, angle)
		end
		_part(root, {
			Name = "DriftRingStar_" .. i,
			Size = Vector3.new(4, 4, 0.5),
			Position = Vector3.new(rx, ry, rz),
			Color = C.STAR, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
		local trigger = _part(root, {
			Name = "DriftCorner_" .. i,
			Size = Vector3.new(ringR * 2 + 4, ringR * 2 + 4, 50),
			Position = Vector3.new(rx, ry, rz),
			CanCollide = false, Transparency = 1,
		})
		_tag(trigger, "DriftCorner")
	end
end

-- ─── Jump zones (3 per spec §4.3: S5 XZ boost dressed as ramps) ──────────────
-- Flyer is Y-locked at 84, so these apply forward-velocity boost (not vertical).

local function _buildJumpRamps(root)
	local ramps = {
		{  80,   40 },  -- N24 S5 entry
		{ -80, -500 },  -- N27 S5 mid
		{  80, -680 },  -- N28 S5 late
	}
	for i, r in ipairs(ramps) do
		local rx, rz = r[1], r[2]
		_part(root, {
			Name = "JumpRamp_" .. i,
			Size = Vector3.new(CORRIDOR_W - 14, 1.2, 14),
			Position = Vector3.new(rx, SKY_BASE_Y + 0.8, rz),
			Color = C.CLOUD_PUFF, Material = MAT.NEON,
			CanCollide = false, CastShadow = false, Transparency = 0.3,
		})
		local jz = _part(root, {
			Name = "JumpZone_" .. i,
			Size = Vector3.new(CORRIDOR_W - 6, 8, 12),
			Position = Vector3.new(rx, SKY_BASE_Y + 4, rz),
			CanCollide = false, Transparency = 1,
		})
		_tag(jz, "JumpZone")
	end
end

-- ─── Boost pads (5 per spec §4.3) ────────────────────────────────────────────

local function _buildBoostPads(root)
	local pads = {
		{   0, 1300 },  -- S1 launch
		{-300,  500 },  -- N6 Loop A south apex (rewards tight line)
		{   0,  600 },  -- S3 plaza
		{ 300,  700 },  -- N20 Loop B north apex
		{   0,-1400 },  -- S6 mid descent
	}
	for i, pd in ipairs(pads) do
		local pad = _part(root, {
			Name = "BoostPad_" .. i,
			Size = Vector3.new(12, 0.4, 8),
			Position = Vector3.new(pd[1], SKY_BASE_Y + 0.4, pd[2]),
			Color = C.BOOST, Material = MAT.NEON, CanCollide = false,
		})
		_tag(pad, "BoostPad")
		_part(root, {
			Name = "BoostRing_" .. i,
			Size = Vector3.new(16, 0.2, 12),
			Position = Vector3.new(pd[1], SKY_BASE_Y + 0.3, pd[2]),
			Color = Color3.fromRGB(255, 200, 240), Material = MAT.NEON,
			Transparency = 0.5, CanCollide = false,
		})
	end
end

-- ─── Checkpoints (spec §4.6) ─────────────────────────────────────────────────
-- Each checkpoint = invisible Touched trigger (gated by CheckpointService)
-- + visible glowing arch so players know where to drive through.

local function _buildCheckpointGate(root, x, z, cpIndex, archColor)
	local archY = SKY_BASE_Y + 22
	-- Two pillars at corridor edges
	for _, side in ipairs({ -1, 1 }) do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Pillar" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(2.4, 38, 2.4),
			Position = Vector3.new(x + side * (CORRIDOR_W / 2 - 2), SKY_BASE_Y + 19, z),
			Color = archColor, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
	end
	-- Curved top: 3 segments faking an arch
	local topY = archY + 6
	for i = -1, 1 do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Top" .. (i + 2),
			Size = Vector3.new(CORRIDOR_W / 3 + 2, 2, 2.4),
			Position = Vector3.new(x + i * (CORRIDOR_W / 3), topY + (i == 0 and 1.5 or 0), z),
			Color = archColor, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
	end
	-- Vertical beacon column — visible from anywhere on the map so players can
	-- always orient toward the next checkpoint
	local beaconHeight = 120
	_part(root, {
		Name = "CPGate" .. cpIndex .. "Beacon",
		Size = Vector3.new(1.4, beaconHeight, 1.4),
		Position = Vector3.new(x, topY + 6 + beaconHeight / 2, z),
		Color = archColor, Material = MAT.NEON,
		CanCollide = false, CastShadow = false,
		Transparency = 0.15,
	})
	-- Floating "CP1" / "CP2" label
	local labelAnchor = _part(root, {
		Name = "CPGate" .. cpIndex .. "Label",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x, topY + 6, z),
		Transparency = 1, CanCollide = false, CastShadow = false,
	})
	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.new(0, 180, 0, 48)
	bb.StudsOffset    = Vector3.new(0, 0, 0)
	bb.MaxDistance    = 1500   -- visible from across the map
	bb.LightInfluence = 0
	bb.AlwaysOnTop    = true
	bb.Parent         = labelAnchor
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = "CP " .. cpIndex
	lbl.TextColor3             = archColor
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.2
	lbl.Font                   = Enum.Font.GothamBlack
	lbl.TextScaled             = true
	lbl.Parent                 = bb
end

local function _buildCheckpoints(root)
	local cp1Pos = { x = -600, z = 800 }   -- N8 Loop A western extent
	local cp2Pos = { x = 600,  z = 400 }   -- N18 Loop B eastern extent

	local cp1 = _part(root, {
		Name = "Checkpoint1",
		Size = Vector3.new(CORRIDOR_W, 50, 6),
		Position = Vector3.new(cp1Pos.x, SKY_BASE_Y + 25, cp1Pos.z),
		CanCollide = false, Transparency = 1,
	})
	_tag(cp1, "Checkpoint1")
	_buildCheckpointGate(root, cp1Pos.x, cp1Pos.z, 1, Color3.fromRGB(120, 220, 255))

	local cp2 = _part(root, {
		Name = "Checkpoint2",
		Size = Vector3.new(CORRIDOR_W, 50, 6),
		Position = Vector3.new(cp2Pos.x, SKY_BASE_Y + 25, cp2Pos.z),
		CanCollide = false, Transparency = 1,
	})
	_tag(cp2, "Checkpoint2")
	_buildCheckpointGate(root, cp2Pos.x, cp2Pos.z, 2, Color3.fromRGB(255, 200, 100))
end

-- ─── Farm platform (relocated north of start, beyond track Z extent) ─────────

local function _buildFarmPlatform(root)
	local cx, cz = 0, 1850
	_part(root, {
		Name = "FarmPlatform",
		Size = Vector3.new(200, 9, 240),
		Position = Vector3.new(cx, SKY_BASE_Y - 4.5, cz),
		Color = C.PLATFORM3, Material = MAT.ROCK,
	})
	for _, side in ipairs({ -1, 1 }) do
		local bev = _wedge(root, {
			Name = "FarmBevel",
			Size = Vector3.new(200, 5, 6),
			Color = C.PLATFORM2, Material = MAT.ROCK, CanCollide = false,
		})
		bev.CFrame = CFrame.new(cx, SKY_BASE_Y - 7.5, cz + side * 125)
			* CFrame.Angles(0, side > 0 and 0 or math.pi, 0)
	end

	local pillarPositions = {
		{ cx - 85, cz - 105 }, { cx + 85, cz - 105 },
		{ cx - 85, cz       }, { cx + 85, cz       },
		{ cx - 85, cz + 105 }, { cx + 85, cz + 105 },
	}
	for _, pp in ipairs(pillarPositions) do
		_part(root, {
			Name = "CrystalPillar", Size = Vector3.new(5, 50, 5),
			Position = Vector3.new(pp[1], SKY_BASE_Y - 33, pp[2]),
			Color = C.CRYSTAL, Material = MAT.CRYSTAL,
			CanCollide = false, CastShadow = false,
		})
	end

	local cols = { -65, -32, 0, 32, 65 }
	local rows = { cz - 45, cz + 45 }
	for _, rz in ipairs(rows) do
		for _, ox in ipairs(cols) do
			local sp = _part(root, {
				Name = "FarmSpawnPoint",
				Size = Vector3.new(4, 0.5, 4),
				Position = Vector3.new(cx + ox, SKY_BASE_Y + 4.5, rz),
				Color = Color3.fromRGB(255, 220, 60), Material = MAT.NEON,
				CanCollide = false, Transparency = 0.5,
			})
			_tag(sp, "FarmSpawn")
		end
	end
end

-- ─── Start grid (matches BiomeConfig.SKY.raceStartZ = 1490) ──────────────────

local function _buildStartGrid(root)
	for side = -1, 1, 2 do
		_part(root, {
			Name = "StartPole" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(1.5, 18, 1.5),
			Position = Vector3.new(side * (CORRIDOR_W / 2 - 3), SKY_BASE_Y + 13, 1495),
			Color = C.ARCH, Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "StartBanner",
		Size = Vector3.new(CORRIDOR_W - 4, 2, 1),
		Position = Vector3.new(0, SKY_BASE_Y + 22, 1495),
		Color = Color3.fromRGB(255, 220, 40), Material = MAT.NEON, CanCollide = false,
	})
end

-- ─── Finish line (Z = -2000) ─────────────────────────────────────────────────

local function _buildFinishLine(root)
	for col = -(CORRIDOR_W / 2), (CORRIDOR_W / 2) - 4, 4 do
		for row = 0, 1 do
			_part(root, {
				Name = "FinishTile",
				Size = Vector3.new(4, 0.4, 4),
				Position = Vector3.new(col + 2, SKY_BASE_Y + 0.4, FINISH_Z + row * 4),
				Color = (math.floor((col + CORRIDOR_W / 2) / 4) + row) % 2 == 0
					and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
				Material = MAT.METAL, CanCollide = false,
			})
		end
	end

	local finish = _part(root, {
		Name = "FinishLine",
		Size = Vector3.new(CORRIDOR_W, 12, 2),
		Position = Vector3.new(0, SKY_BASE_Y + 6, FINISH_Z),
		CanCollide = false, Transparency = 1,
	})
	_tag(finish, "FinishLine")

	for side = -1, 1, 2 do
		_part(root, {
			Name = "FinishPole" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(1.8, 22, 1.8),
			Position = Vector3.new(side * (CORRIDOR_W / 2 - 3), SKY_BASE_Y + 11, FINISH_Z),
			Color = C.ARCH, Material = MAT.CRYSTAL,
		})
	end
	_part(root, {
		Name = "FinishArch",
		Size = Vector3.new(CORRIDOR_W - 4, 3, 1.8),
		Position = Vector3.new(0, SKY_BASE_Y + 22.5, FINISH_Z),
		Color = C.ARCH, Material = MAT.NEON, CanCollide = false,
	})
	-- Star burst decoration on arch
	for sx = -20, 20, 5 do
		local phase = sx * 0.6
		_part(root, {
			Name = "ArchStar",
			Size = Vector3.new(2.5, 2.5, 0.6),
			Position = Vector3.new(sx, SKY_BASE_Y + 23 + math.sin(phase) * 1.5, FINISH_Z - 0.5),
			Color = C.STAR, Material = MAT.NEON,
			CanCollide = false, CastShadow = false,
		})
	end
end

-- ─── Kill plane (Y = -200 per BiomeConfig.SKY.killPlaneY) ────────────────────

local function _buildKillPlane(root)
	local kill = _part(root, {
		Name = "KillPlane",
		Size = Vector3.new(3000, 4, 5000),
		Position = Vector3.new(0, -200, -250),
		CanCollide = false, Transparency = 1,
	})
	_tag(kill, "KillPlane")
end

-- ─── Main build ──────────────────────────────────────────────────────────────

local function buildSky()
	local root = _getOrCreateMap()

	local farmSub  = Instance.new("Model"); farmSub.Name  = "FarmArea";  farmSub.Parent  = root
	local trackSub = Instance.new("Model"); trackSub.Name = "RaceTrack"; trackSub.Parent = root

	_buildClouds(root)
	_buildUpdraftZones(root)
	_buildFarmPlatform(farmSub)

	_buildFloor(trackSub)
	_buildShoulders(trackSub)
	_buildEdgeBarriers(trackSub)
	_buildInvisibleCeiling(trackSub)
	_buildCrystalClusters(trackSub)
	_buildBoostPads(trackSub)
	_buildJumpRamps(trackSub)
	_buildDriftCorners(trackSub)
	_buildCheckpoints(trackSub)
	_buildStartGrid(trackSub)
	_buildFinishLine(trackSub)
	_buildKillPlane(trackSub)

	CollectionService:AddTag(root, "BiomeMap")
	root:SetAttribute("Biome", "SKY")

	print("[SkyMapBuilder] Built SKY map (" .. #root:GetDescendants() .. " descendants)")
	return root
end

local ok, err = pcall(buildSky)
if not ok then warn("[SkyMapBuilder] Build failed: " .. tostring(err)) end
