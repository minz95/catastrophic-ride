-- OceanMap.lua (ModuleScript; was MapBuilders/OceanMapBuilder.server.lua)
-- Procedurally builds the OCEAN biome map per racetrack spec §3:
--   - 3400-stud centerline (arc-S + island detour + reef U-bend) along Z=600 → -1530
--   - 60-wide channel with solid above-water reef walls both sides (height 12 above waterPlaneY=2)
--   - Enlarged palm island anchors the S2 arc; reef formation anchors the S4 U-bend
--   - Buoys reduced to centerline decoration only (CanCollide false)
--   - CP1 inside S2 island arc, CP2 inside S4 reef U-bend
-- Resolves: Issue #9, #114, #129

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Tracks.OceanTrack)
local TrackGeometry = require(ReplicatedStorage.Shared.TrackGeometry)

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

local WATER_Y  = Track.trackTop  -- water surface Y
local LANE_W   = Track.width     -- channel width (spec §3 table)
local WALL_H   = 12              -- reef wall height above water (spec §3.4)
local WALL_T   = 3               -- reef wall thickness
local FINISH_Z = Track.finishZ   -- matches Constants.TRACK.OCEAN.zFinish

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

local NODES = Track.nodes
local GEO   = TrackGeometry.new(NODES, LANE_W)

-- Inside the channel (with a small margin)?
local function _inLane(x, z)
	return GEO:project(x, z).dist < LANE_W / 2 + 2
end

-- Track heading (Roblox yaw) near a point, averaged over a few studs so a
-- prop placed on a node faces the bisector of the turn.
local function _trackYawNear(x, z)
	local s = GEO:project(x, z).s
	local ax, az = GEO:pointAt(s - 4)
	local bx, bz = GEO:pointAt(s + 4)
	return math.atan2(-(bx - ax), -(bz - az))
end

-- CFrame at (x, y, z) whose local -Z faces down the track (LookVector = travel).
local function _trackCF(x, y, z)
	return CFrame.new(x, y, z) * CFrame.Angles(0, _trackYawNear(x, z), 0)
end

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

-- Wall is broken into sub-walls separated by gaps every WALL_GAP_INTERVAL studs
-- of cumulative track-arc distance. Player can swim/sail through the doorway
-- onto open water; the SlowZone outside (_buildSlowZones) imposes a speed mult.

local WALL_GAP_INTERVAL   = 48
local WALL_GAP_HALF_WIDTH = 4   -- 8-stud opening

-- Same rationale as FOREST/SKY: BodyVelocity propulsion means wall contact
-- is pure drag. Low friction makes boats glide along the reef instead of pinning.
local LOW_FRICTION_SURFACE = PhysicalProperties.new(1, 0.05, 0.1, 100, 1)

local function _wallPieces(arcStart, segLen)
	local pieces = {}
	local cursor = 0
	local firstGapK = math.ceil((arcStart - WALL_GAP_HALF_WIDTH) / WALL_GAP_INTERVAL)
	local k = firstGapK
	while true do
		local gapArc = k * WALL_GAP_INTERVAL
		local gapStartArc = gapArc - WALL_GAP_HALF_WIDTH
		local gapEndArc   = gapArc + WALL_GAP_HALF_WIDTH
		if gapStartArc >= arcStart + segLen then break end
		if gapEndArc > arcStart then
			local relStart = math.max(0, gapStartArc - arcStart)
			local relEnd   = math.min(segLen, gapEndArc - arcStart)
			if relStart > cursor then
				table.insert(pieces, { cursor, relStart })
			end
			cursor = math.max(cursor, relEnd)
		end
		k = k + 1
	end
	if cursor < segLen then
		table.insert(pieces, { cursor, segLen })
	end
	return pieces
end

-- Solid stretches of segment i's wall, segment-local (0 = start node):
-- TrackGeometry:boundaryRuns (outer corners closed, inner corners and lane
-- overlaps clipped) minus the doorways. Extensions past the nodes get no
-- doorway.
local function _wallStretches(i, side, arcStart, segLen)
	-- builder side +1 = left of travel (_segCF local +X); TrackGeometry uses +1 = right
	local runs = GEO:boundaryRuns(i, -side, LANE_W / 2 + WALL_T / 2, LANE_W / 2 + WALL_T)
	local solid = { { -math.huge, 0 } }
	for _, piece in ipairs(_wallPieces(arcStart, segLen)) do
		local last = solid[#solid]
		if piece[1] <= last[2] + 1e-6 then
			last[2] = math.max(last[2], piece[2])
		else
			table.insert(solid, { piece[1], piece[2] })
		end
	end
	local last = solid[#solid]
	if last[2] >= segLen - 1e-6 then
		last[2] = math.huge
	else
		table.insert(solid, { segLen, math.huge })
	end
	local out = {}
	for _, r in ipairs(runs) do
		for _, sp in ipairs(solid) do
			local lo, hi = math.max(r[1], sp[1]), math.min(r[2], sp[2])
			if hi - lo >= 0.5 then table.insert(out, { lo, hi }) end
		end
	end
	return out
end

local function _buildReefWalls(root)
	local arcStart = 0
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		if segLen < 0.1 then continue end
		local cf     = _segCF(a[1], a[2], b[1], b[2], WATER_Y + WALL_H / 2)

		for _, side in ipairs({ -1, 1 }) do
			for _, piece in ipairs(_wallStretches(i, side, arcStart, segLen)) do
				local pStart, pEnd = piece[1], piece[2]
				local pLen = pEnd - pStart
				local pMid = (pStart + pEnd) / 2 - segLen / 2

				local wall = _part(root, {
					Name     = "ReefWall",
					Size     = Vector3.new(WALL_T, WALL_H, pLen),
					Color    = C.REEF,
					Material = MAT.ROCK,
				})
				wall.CustomPhysicalProperties = LOW_FRICTION_SURFACE
				wall.CFrame = cf * CFrame.new(side * (LANE_W / 2 + WALL_T / 2), 0, pMid)

				local cap = _part(root, {
					Name     = "ReefWallCap",
					Size     = Vector3.new(WALL_T + 0.4, 0.6, pLen),
					Color    = C.REEF_TOP,
					Material = MAT.NEON,
					CastShadow = false,
				})
				cap.CFrame = cf * CFrame.new(side * (LANE_W / 2 + WALL_T / 2), WALL_H / 2 + 0.3, pMid)
			end
		end
		arcStart = arcStart + segLen
	end
end

-- ─── Slow zones outside the reef walls (rough water / chop) ─────────────────

-- Built in short chunks; a chunk is skipped when any corner of it reaches
-- the channel, so the inside of a turn never slows boats that stay in lane.
local SZ_CHUNK = 12

local function _buildSlowZones(root)
	local SZ_WIDTH  = 50
	local SZ_HEIGHT = 4
	local SZ_OFFSET = LANE_W / 2 + WALL_T + SZ_WIDTH / 2 + 2
	for i = 1, #NODES - 1 do
		local a, b   = NODES[i], NODES[i + 1]
		local segLen = _segLen(a[1], a[2], b[1], b[2])
		if segLen < 0.1 then continue end
		local cf = _segCF(a[1], a[2], b[1], b[2], WATER_Y + SZ_HEIGHT / 2)
		local chunks = math.max(1, math.ceil(segLen / SZ_CHUNK))
		local chunkLen = segLen / chunks
		for c = 1, chunks do
			local mid = -segLen / 2 + (c - 0.5) * chunkLen
			for _, side in ipairs({ -1, 1 }) do
				local centre = cf * CFrame.new(side * SZ_OFFSET, 0, mid)
				local clear = true
				for _, cu in ipairs({ -1, 1 }) do
					for _, cv in ipairs({ -1, 1 }) do
						local corner = centre * Vector3.new(cu * SZ_WIDTH / 2, 0, cv * chunkLen / 2)
						if _inLane(corner.X, corner.Z) then clear = false end
					end
				end
				if clear then
					local sz = _part(root, {
						Name = "SlowZone_" .. i .. "_" .. c .. (side > 0 and "R" or "L"),
						Size = Vector3.new(SZ_WIDTH, SZ_HEIGHT, chunkLen + 0.5),
						Color = C.WATER_FOAM,
						Material = MAT.NEON,
						CanCollide = false,
						Transparency = 0.65,
						CastShadow = false,
					})
					sz.CFrame = centre
					_tag(sz, "SlowZone")
				end
			end
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
		local cf = _trackCF(cx, WATER_Y + 2, cz)
		local isRedSide = (buoyIdx % 2 == 0)
		for _, side in ipairs({ -1, 1 }) do
			local isRed = (side == 1) == isRedSide
			_part(root, {
				Name     = "Buoy_" .. buoyIdx .. (side > 0 and "R" or "L"),
				Size     = Vector3.new(2.5, 4, 2.5),
				-- inside the wall, on the lane edge, across the track direction
				CFrame   = cf * CFrame.new(side * (LANE_W / 2 - 6), 0, 0),
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
	-- Shifted west from cx=90 to cx=40 so the island's east edge (45) sits
	-- well inside the chord but doesn't intrude into the S2 arc nodes.
	-- The arc passes through N4(140, 100); with cx=90 (east edge 145) the
	-- arc clipped 5 stud into the island and boats couldn't reach CP1 at N5.
	-- New east edge: 40 + 110/2 = 95, giving N4 a 45-stud clearance.
	local cx, cz = 40, 0
	_part(root, {
		Name = "Palm_IslandBase", Size = Vector3.new(110, 8, 220),
		Position = Vector3.new(cx, WATER_Y - 2, cz),
		Color = C.SAND, Material = MAT.SAND,
	})
	-- Beach surface (sand, not grass): ocean biome shouldn't look like farmland,
	-- and Material.Grass renders blades that persisted even with low transparency.
	-- Slightly lighter sand differentiates the dry top from the sand base.
	_part(root, {
		Name = "Palm_IslandTop", Size = Vector3.new(95, 1.5, 200),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = Color3.fromRGB(235, 210, 150),
		Material = MAT.SAND,
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
	for i, c in ipairs(Track.driftCorners) do
		local cx, cz = c[1], c[2]
		_part(root, {
			Name = "WakeRing_" .. i, Size = Vector3.new(LANE_W - 4, 0.3, 42),
			CFrame = _trackCF(cx, WATER_Y + 0.3, cz),
			Color = C.DRIFT_GLOW, Material = MAT.NEON,
			CanCollide = false, CastShadow = false, Transparency = 0.5,
		})
		local trigger = _part(root, {
			Name = "DriftCorner_" .. i, Size = Vector3.new(LANE_W + 20, 8, 46),
			CFrame = _trackCF(cx, WATER_Y + 2, cz),
			CanCollide = false, Transparency = 1,
		})
		_tag(trigger, "DriftCorner")
	end
end

-- ─── Jump ramps (2 per spec — post-S2 wave swell + mid-S3 skill-shot) ────────

local function _buildJumpRamps(root)
	for i, r in ipairs(Track.jumpRamps) do
		local rx, rz = r[1], r[2]
		_part(root, {
			Name = "WaveRamp_" .. i, Size = Vector3.new(LANE_W - 12, 1.5, 14),
			CFrame = _trackCF(rx, WATER_Y + 1, rz),
			Color = C.WATER_FOAM, Material = MAT.NEON,
			CanCollide = false, CastShadow = false, Transparency = 0.3,
		})
		local jz = _part(root, {
			Name = "JumpZone_" .. i, Size = Vector3.new(LANE_W - 6, 8, 12),
			CFrame = _trackCF(rx, WATER_Y + 4, rz),
			CanCollide = false, Transparency = 1,
		})
		_tag(jz, "JumpZone")
	end
end

-- ─── Boost pads (4 per spec §3.3) ────────────────────────────────────────────

local function _buildBoostPads(root)
	for i, pd in ipairs(Track.boostPads) do
		local pad = _part(root, {
			Name = "BoostPad_" .. i, Size = Vector3.new(12, 0.4, 8),
			CFrame = _trackCF(pd[1], WATER_Y + 0.4, pd[2]),
			Color = C.BOOST, Material = MAT.NEON, CanCollide = false,
		})
		_tag(pad, "BoostPad")
		_part(root, {
			Name = "BoostRing_" .. i, Size = Vector3.new(16, 0.2, 12),
			CFrame = _trackCF(pd[1], WATER_Y + 0.3, pd[2]),
			Color = Color3.fromRGB(100, 240, 255), Material = MAT.NEON,
			Transparency = 0.5, CanCollide = false,
		})
	end
end

-- ─── Checkpoints (spec §3.6) ─────────────────────────────────────────────────

local function _buildCheckpointGate(root, x, z, cpIndex, archColor)
	local baseY = WATER_Y + 1
	local archTop = baseY + 20
	local gateCF = _trackCF(x, 0, z)
	for _, side in ipairs({ -1, 1 }) do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Pillar" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(2.4, archTop - baseY, 2.4),
			CFrame = gateCF * CFrame.new(side * (LANE_W / 2 - 2), (baseY + archTop) / 2, 0),
			Color = archColor, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
	end
	for i = -1, 1 do
		_part(root, {
			Name = "CPGate" .. cpIndex .. "Top" .. (i + 2),
			Size = Vector3.new(LANE_W / 3 + 2, 2, 2.4),
			CFrame = gateCF * CFrame.new(i * (LANE_W / 3), archTop + (i == 0 and 2 or 0.5), 0),
			Color = archColor, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
	end
	local labelAnchor = _part(root, {
		Name = "CPGate" .. cpIndex .. "Label",
		Size = Vector3.new(1, 1, 1),
		CFrame = gateCF * CFrame.new(0, archTop + 8, 0),
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
	lbl.Text = "CP " .. cpIndex
	lbl.TextColor3 = archColor
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.2
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Parent = bb
end

-- Trigger is wider than the channel and 10 deep, turned to the track, so no
-- line through the gate misses it.
local CHECKPOINT_DEPTH = 10

local function _buildCheckpoints(root)
	local colors = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 200, 100) }
	for i, c in ipairs(Track.checkpoints) do
		local cp = _part(root, {
			Name = "Checkpoint" .. i, Size = Vector3.new(LANE_W + 4, 12, CHECKPOINT_DEPTH),
			CFrame = _trackCF(c[1], WATER_Y + 5, c[2]),
			CanCollide = false, Transparency = 1,
		})
		_tag(cp, "Checkpoint" .. i)
		_buildCheckpointGate(root, c[1], c[2], i, colors[i])
	end
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
	-- SmoothPlastic (not Grass) — Material.Grass renders blades that survive
	-- MapManager's Transparency=1 hide, so during racing the FarmGrass blades
	-- were still bleeding through onto the channel water, making OCEAN look
	-- like a swamp. Same workaround applied to PalmIslandTop earlier.
	_part(root, {
		Name = "FarmGrass", Size = Vector3.new(160, 1, 230),
		Position = Vector3.new(cx, WATER_Y + 2.5, cz),
		Color = C.GRASS, Material = Enum.Material.SmoothPlastic,
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
			-- in the wall line, outside the channel
			Position = Vector3.new(side * (LANE_W / 2 + WALL_T / 2), WATER_Y + 5, 588),
			Color = C.BUOY_WHITE, Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "StartBanner", Size = Vector3.new(LANE_W + WALL_T, 2, 1),
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
			-- in the wall line, outside the channel
			Position = Vector3.new(side * (LANE_W / 2 + WALL_T / 2), WATER_Y + 9, FINISH_Z),
			Color = C.BUOY_WHITE, Material = MAT.METAL,
		})
	end
	_part(root, {
		Name = "FinishArch", Size = Vector3.new(LANE_W + WALL_T + 1.5, 2.5, 1.5),
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
	_buildSlowZones(trackSub)
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

return {
	build = buildOcean,
}
