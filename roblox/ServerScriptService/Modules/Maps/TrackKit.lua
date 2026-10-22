-- TrackKit.lua
-- The parts every race track has, built from a track data table
-- (ReplicatedStorage.Shared.Tracks.*Track). Biome builders (ForestMap,
-- OceanMap, SkyMap) call these with a style table (colours, materials, part
-- names) and add only their own decoration. All positions and sizes come from
-- the track data, so a map changes by editing data, not builder code.
--
--   local kit = TrackKit.new(Track)
--   kit:buildSurface(root, style)    lane floor + round joints at every node
--   kit:buildWalls(root, style)      side walls (boxes or a pillar fence)
--   kit:buildSlowZones(root, style)  off-track slow volumes, clipped off the lane
--   kit:buildCheckpoints(root, style)
--   kit:buildBoostPads(root, style)
--   kit:buildDriftCorners(root, style)
--   kit:buildJumpZones(root, style)
--   kit:buildFinish(root, style)
--   kit:buildStartGrid(root, style)
--   kit:buildStartApron(root, style)  floor + walls behind the start line
--
-- Geometry rules (checked by tests/lib/mapchecks.luau):
--   * walls follow TrackGeometry:boundaryRuns — closed on the outside of every
--     turn, never inside the lane (inside of turns, track crossings);
--     `Track.wallGapHalfWidth` > 0 cuts doorways every `wallGapInterval`
--     studs of track length, 0 = continuous walls;
--   * triggers are turned to face along the track and span the whole lane.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrackGeometry = require(ReplicatedStorage.Shared.TrackGeometry)

local TrackKit = {}
TrackKit.__index = TrackKit

-- Vehicles are pushed by BodyVelocity, so surface friction is pure drag.
-- Low friction with a high weight lets cars glide along floors and walls.
TrackKit.LOW_FRICTION = PhysicalProperties.new(1, 0.05, 0.1, 100, 1)

function TrackKit.part(parent, props)
	local p = Instance.new("Part")
	p.Anchored   = true
	p.CanCollide = true
	for k, v in pairs(props) do pcall(function() p[k] = v end) end
	p.Parent = parent
	return p
end

function TrackKit.wedge(parent, props)
	local p = Instance.new("WedgePart")
	p.Anchored   = true
	p.CanCollide = true
	for k, v in pairs(props) do pcall(function() p[k] = v end) end
	p.Parent = parent
	return p
end

function TrackKit.tag(part, tagName)
	CollectionService:AddTag(part, tagName)
end

--- New (or replaced) Workspace.Maps.<name> model with FarmArea / RaceTrack.
function TrackKit.newMap(name)
	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		maps = Instance.new("Folder")
		maps.Name = "Maps"
		maps.Parent = workspace
	end
	local existing = maps:FindFirstChild(name)
	if existing then existing:Destroy() end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = maps
	local farm = Instance.new("Model"); farm.Name = "FarmArea"; farm.Parent = model
	local race = Instance.new("Model"); race.Name = "RaceTrack"; race.Parent = model
	return model, farm, race
end

function TrackKit.new(track)
	local self = setmetatable({}, TrackKit)
	self.track = track
	self.nodes = track.nodes
	self.width = track.width
	self.half  = track.width / 2
	self.top   = track.trackTop
	self.geo   = TrackGeometry.new(track.nodes, track.width, track.trackTop)
	return self
end

--- Road surface Y at node i (nodes may carry a height: { x, z, y }).
function TrackKit:nodeY(i)
	return self.nodes[i][3] or self.top
end

--- How far the road at (x, z) is above trackTop. `y` (optional) picks the
-- layer where the road passes over itself (data entries { x, z, y }).
function TrackKit:riseAt(x, z, y)
	if not self.geo.hasHeights then return 0 end
	local p = self.geo:project(x, z, nil, nil, y)
	return self.geo:segHeight(p.seg, p.t) - self.top
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

--- Segment frame at height y (given for a flat road at trackTop): centred
-- between the nodes, local +Z along travel, local +X = LEFT of travel. On a
-- raised or sloped road it is lifted by the road's rise and pitched to its
-- grade, so anything placed in it follows the road.
function TrackKit:segCF(i, y)
	local a, b = self.nodes[i], self.nodes[i + 1]
	local mx, mz = (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5
	local ya, yb = self:nodeY(i), self:nodeY(i + 1)
	local rise = (ya + yb) * 0.5 - self.top
	local len = self.geo.segments[i].len
	return CFrame.new(mx, y + rise, mz) * CFrame.Angles(0, math.atan2(b[1] - a[1], b[2] - a[2]), 0)
		* CFrame.Angles(-math.atan2(yb - ya, math.max(len, 1e-6)), 0, 0)
end

--- Length of segment i along its slope.
function TrackKit:segLen3(i)
	local len = self.geo.segments[i].len
	local dy = self:nodeY(i + 1) - self:nodeY(i)
	return math.sqrt(len * len + dy * dy)
end

function TrackKit:segLen(i)
	return self.geo.segments[i].len
end

--- Track heading (Roblox yaw) near a point, averaged over a few studs so a
-- prop on a node faces the bisector of the turn.
function TrackKit:yawNear(x, z, layer)
	local s = self.geo:project(x, z, nil, nil, layer).s
	local ax, az = self.geo:pointAt(s - 4)
	local bx, bz = self.geo:pointAt(s + 4)
	return math.atan2(-(bx - ax), -(bz - az))
end

--- CFrame at (x, y, z) whose LookVector points down the track. y is given
-- for a flat road at trackTop; a raised road lifts it. `layer` (optional,
-- the Y of the road wanted) picks the stretch where the road passes over
-- itself.
function TrackKit:trackCF(x, y, z, layer)
	return CFrame.new(x, y + self:riseAt(x, z, layer), z) * CFrame.Angles(0, self:yawNear(x, z, layer), 0)
end

--- Inside the lane (plus a margin)?
function TrackKit:inLane(x, z, margin)
	return self.geo:project(x, z).dist < self.half + (margin or 0)
end

--- Lane-local offset of the wall centre line.
function TrackKit:wallOffset()
	return self.half + (self.track.wallThickness or 2) / 2
end

-- Doorway cut-outs along segment i (segment-local {from, to} pieces of
-- solid wall within [0, len]); no doorways when wallGapHalfWidth is 0.
local function doorwayPieces(arcStart, segLen, interval, halfGap)
	if not halfGap or halfGap <= 0 or not interval or interval <= 0 then
		return { { 0, segLen } }
	end
	local pieces, cursor = {}, 0
	local k = math.ceil((arcStart - halfGap) / interval)
	while true do
		local gapArc = k * interval
		local gs, ge = gapArc - halfGap, gapArc + halfGap
		if gs >= arcStart + segLen then break end
		if ge > arcStart then
			local rs, re = math.max(0, gs - arcStart), math.min(segLen, ge - arcStart)
			if rs > cursor then table.insert(pieces, { cursor, rs }) end
			cursor = math.max(cursor, re)
		end
		k += 1
	end
	if cursor < segLen then table.insert(pieces, { cursor, segLen }) end
	return pieces
end

--- Solid wall stretches of segment i on builder side `side` (+1 = left):
-- boundaryRuns minus doorways. Extensions past the nodes have no doorways.
function TrackKit:wallStretches(i, side, offset, reach)
	local segLen = self:segLen(i)
	local runs = self.geo:boundaryRuns(i, -side, offset, reach)
	local solid = { { -math.huge, 0 } }
	local arcStart = self.geo.segments[i].s0
	for _, piece in ipairs(doorwayPieces(arcStart, segLen, self.track.wallGapInterval, self.track.wallGapHalfWidth)) do
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

-- ─── Lane surface ─────────────────────────────────────────────────────────────

--- style: { name, thickness, colors = { ... } | color, material, overlap,
--           physics = true, joints = true, decorate = function(root, i, cf, len) }
-- Slabs are the lane width, `overlap` studs longer at each end; round joints
-- (cylinders of the lane width) fill the outside of every turn, 0.05 lower
-- than the slabs so they don't z-fight.
function TrackKit:buildSurface(root, style)
	local th = style.thickness or 1
	local overlap = style.overlap or 2
	local colors = style.colors or { style.color }
	for i = 1, #self.nodes - 1 do
		local len = self:segLen(i)
		if len < 0.1 then continue end
		local cf = self:segCF(i, self.top - th / 2)
		local color = colors[((i - 1) % #colors) + 1]
		local slab = TrackKit.part(root, {
			Name = style.name .. "_" .. i,
			Size = Vector3.new(self.width, th, self:segLen3(i) + overlap * 2),
			CFrame = cf, Color = color, Material = style.material,
		})
		slab:SetAttribute("TrackFloor", true)
		if style.physics ~= false then slab.CustomPhysicalProperties = TrackKit.LOW_FRICTION end
		if style.joints ~= false and i < #self.nodes - 1 then
			local b = self.nodes[i + 1]
			-- Where the grade changes the flat disc would stand proud of the
			-- slab on one side of the node: sink it by that much.
			local dg = math.abs(self.geo:grade(i + 1) - self.geo:grade(i))
			local sink = 0.05 + dg * self.half
			local joint = TrackKit.part(root, {
				Name = (style.jointName or (style.name .. "Joint")) .. "_" .. (i + 1),
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(th, self.width, self.width),
				CFrame = CFrame.new(b[1], self:nodeY(i + 1) - sink - th / 2, b[2]) * CFrame.Angles(0, 0, math.pi / 2),
				Color = color, Material = style.material,
			})
			joint:SetAttribute("TrackFloor", true)
			if style.physics ~= false then joint.CustomPhysicalProperties = TrackKit.LOW_FRICTION end
		end
		if style.decorate then style.decorate(root, i, cf, len) end
	end
end

-- ─── Start apron ─────────────────────────────────────────────────────────────

--- Floor behind the start line, closed by side walls and a back wall, so a
-- car knocked backwards at GO lands on track. (Studio, 2026-10-21: the floor
-- ended 4 studs behind the back grid row and cars nudged at GO fell to the
-- kill plane.) style = { length, floor = { name, color, material, thickness },
-- wall = { name, color, material, transparency } } — the wall is as tall as
-- the track walls (Track.wallHeight / wallBaseY).
function TrackKit:buildStartApron(root, style)
	local a, b = self.nodes[1], self.nodes[2]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local d = math.sqrt(dx * dx + dz * dz)
	dx, dz = dx / d, dz / d
	local L = style.length or 24
	local yaw = math.atan2(dx, dz)
	local f = style.floor
	local th = f.thickness or 1
	-- overlaps the first slab by 2 studs
	local cx, cz = a[1] - dx * (L / 2 - 1), a[2] - dz * (L / 2 - 1)
	local floor = TrackKit.part(root, {
		Name = f.name or "StartApron", Size = Vector3.new(self.width, th, L + 2),
		CFrame = CFrame.new(cx, self.top - th / 2, cz) * CFrame.Angles(0, yaw, 0),
		Color = f.color, Material = f.material,
	})
	floor.CustomPhysicalProperties = TrackKit.LOW_FRICTION
	local w = style.wall
	if not w then return end
	local t = self.track
	local thick = t.wallThickness or 2
	local h = t.wallHeight or 8
	local baseY = t.wallBaseY or (self.top - 0.5)
	local midY = baseY + h / 2
	local base = CFrame.new(cx, midY, cz) * CFrame.Angles(0, yaw, 0)
	local function wall(size, offset)
		local p = TrackKit.part(root, {
			Name = w.name or "StartApronWall", Size = size, CFrame = base * CFrame.new(offset),
			Color = w.color, Material = w.material, Transparency = w.transparency or 0,
		})
		p.CustomPhysicalProperties = TrackKit.LOW_FRICTION
	end
	local off = self.half + thick / 2
	wall(Vector3.new(thick, h, L + 2), Vector3.new(-off, 0, 0))
	wall(Vector3.new(thick, h, L + 2), Vector3.new(off, 0, 0))
	wall(Vector3.new(self.width + thick * 2, h, thick), Vector3.new(0, 0, -(L / 2 + 1) - thick / 2))
end

--- A wall across the lane at the end of the run-off past the finish, as tall
-- as the track walls, with chevrons facing the cars. (Studio, 2026-10-22:
-- the road just ended 0–70 studs past the line; cars that kept going fell
-- off and respawned at the end, again and again.) style = { name, color,
-- material, transparency, stripe }
function TrackKit:buildEndWall(root, style)
	local n = #self.nodes
	local a, b = self.nodes[n - 1], self.nodes[n]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local d = math.sqrt(dx * dx + dz * dz)
	dx, dz = dx / d, dz / d
	local t = self.track
	local thick = t.wallThickness or 2
	local h = t.wallHeight or 8
	local baseY = (t.wallBaseY or (self.top - 0.5)) + (self:nodeY(n) - self.top)
	local yaw = math.atan2(dx, dz)
	local cf = CFrame.new(b[1] - dx * thick / 2, baseY + h / 2, b[2] - dz * thick / 2) * CFrame.Angles(0, yaw, 0)
	local wall = TrackKit.part(root, {
		Name = style.name or "EndWall", Size = Vector3.new(self.width + thick * 2, h, thick), CFrame = cf,
		Color = style.color, Material = style.material, Transparency = style.transparency or 0,
	})
	wall.CustomPhysicalProperties = TrackKit.LOW_FRICTION
	-- chevrons on the side the cars come from (decoration)
	local stripe = style.stripe or Color3.fromRGB(255, 200, 40)
	local count = math.floor(self.width / 6)
	for i = 1, count do
		local x = -self.width / 2 + (i - 0.5) * self.width / count
		local p = TrackKit.part(root, {
			Name = "EndWallChevron", Size = Vector3.new(1.4, math.min(h, 6) * 0.7, 0.2),
			-- LookVector (−Z) points back down the road, at the cars coming in
			CFrame = cf * CFrame.new(x, 0, -(thick / 2 + 0.1)) * CFrame.Angles(0, 0, (i % 2 == 0) and 0.6 or -0.6),
			Color = stripe, Material = Enum.Material.Neon,
		})
		p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
	end
	return wall
end

-- ─── Walls ────────────────────────────────────────────────────────────────────

--- Box walls. style: { name, color, material, transparency,
--   cap = { name, color, material },
--   rail = { name, color, material, y, height } }   -- solid band from trackTop + y
-- Height and thickness come from Track.wallHeight / Track.wallThickness;
-- the wall stands on Track.wallBaseY (default trackTop - 0.5).
--
-- Pillar fence instead of boxes: style.pillars = { size, spacing, colors,
-- material, transparency, yLo, yHi }. Pillars are packed at <= spacing so no
-- gap opens; style.rail then adds a visual band per stretch (rail.collide
-- = true to make it solid). SKY: one colour, see-through glass (until
-- 2026-10-22 alternating neon colours: 60-stud stripes, hard on the eyes).
function TrackKit:buildWalls(root, style)
	local t = self.track
	local thick = t.wallThickness or 2
	local offset = self.half + thick / 2
	local reach = self.half + thick
	local pillars = style.pillars
	local h, baseY
	if pillars then
		h = pillars.yHi - pillars.yLo
		baseY = pillars.yLo
	else
		h = t.wallHeight
		baseY = t.wallBaseY or (self.top - 0.5)
	end
	local midY = baseY + h / 2
	for i = 1, #self.nodes - 1 do
		local len = self:segLen(i)
		if len < 0.1 then continue end
		local cf = self:segCF(i, midY)
		for _, side in ipairs({ -1, 1 }) do
			local slot = 0
			for _, run in ipairs(self:wallStretches(i, side, offset, reach)) do
				local runLen = run[2] - run[1]
				if pillars then
					local count = math.max(1, math.ceil(runLen / pillars.spacing))
					for k = 0, count - 1 do
						local along = run[1] + (k + 0.5) * runLen / count - len / 2
						local p = TrackKit.part(root, {
							Name = style.name .. i .. "_" .. slot .. (side > 0 and "R" or "L"),
							Size = Vector3.new(pillars.size, h, pillars.size),
							Color = pillars.colors[(slot % #pillars.colors) + 1],
							Material = pillars.material, Transparency = pillars.transparency or 0,
							CanCollide = true, CastShadow = false,
						})
						p.CustomPhysicalProperties = TrackKit.LOW_FRICTION
						p.CFrame = cf * CFrame.new(side * offset, 0, along)
						if self.geo.hasHeights then
							-- upright, at the road height where the pillar stands
							local rise = self.geo:segHeight(i, along + len / 2) - self.top
							p.CFrame = CFrame.new(p.Position.X, midY + rise, p.Position.Z)
								* CFrame.Angles(0, math.atan2(self.geo.segments[i].dx, self.geo.segments[i].dz), 0)
						end
						slot += 1
					end
					if style.rail then
						local r = style.rail
						local along = (run[1] + run[2]) / 2 - len / 2
						local rail = TrackKit.part(root, {
							Name = r.name, Size = Vector3.new(pillars.size + 0.6, r.height, runLen),
							Color = r.color, Material = r.material, CastShadow = false,
							CanCollide = r.collide == true,
						})
						rail.CFrame = cf * CFrame.new(side * offset, (self.top + r.y + r.height / 2) - midY, along)
					end
				else
					local along = (run[1] + run[2]) / 2 - len / 2
					local wall = TrackKit.part(root, {
						Name = style.name, Size = Vector3.new(thick, h, runLen),
						Color = style.color, Material = style.material,
						Transparency = style.transparency or 0,
						CastShadow = not style.transparency,
					})
					wall.CustomPhysicalProperties = TrackKit.LOW_FRICTION
					wall.CFrame = cf * CFrame.new(side * offset, 0, along)
					if style.cap then
						local cap = TrackKit.part(root, {
							Name = style.cap.name, Size = Vector3.new(thick + 0.4, 0.6, runLen),
							Color = style.cap.color, Material = style.cap.material,
							CastShadow = false,
						})
						cap.CFrame = cf * CFrame.new(side * offset, h / 2 + 0.3, along)
					end
					if style.rail then
						-- solid band at vehicle height (for see-through walls:
						-- the edge stays easy to read)
						local r = style.rail
						local rail = TrackKit.part(root, {
							Name = r.name, Size = Vector3.new(thick + 0.6, r.height, runLen),
							Color = r.color, Material = r.material, CastShadow = false,
						})
						rail.CustomPhysicalProperties = TrackKit.LOW_FRICTION
						rail.CFrame = cf * CFrame.new(side * offset, (self.top + r.y + r.height / 2) - midY, along)
					end
				end
			end
		end
	end
end

-- ─── Slow zones ───────────────────────────────────────────────────────────────

--- Off-track slow volumes beside the walls, in SZ_CHUNK pieces; a piece is
-- skipped when any corner comes within the lane of ANY part of the track.
-- Size from Track.slowZoneWidth / slowZoneHeight (width 0 = none).
-- style: { color, material, transparency }
TrackKit.SZ_CHUNK = 12

function TrackKit:buildSlowZones(root, style)
	local t = self.track
	local w, h = t.slowZoneWidth or 0, t.slowZoneHeight or 4
	if w <= 0 then return end
	local offset = self.half + (t.wallThickness or 2) + w / 2 + 2
	for i = 1, #self.nodes - 1 do
		local len = self:segLen(i)
		if len < 0.1 then continue end
		local cf = self:segCF(i, self.top - 0.4 + h / 2)
		local chunks = math.max(1, math.ceil(len / TrackKit.SZ_CHUNK))
		local chunkLen = len / chunks
		for c = 1, chunks do
			local mid = -len / 2 + (c - 0.5) * chunkLen
			-- none beside a raised road (they would hang in the air)
			if self.geo:segHeight(i, mid + len / 2) - self.top > 2 then continue end
			for _, side in ipairs({ -1, 1 }) do
				local centre = cf * CFrame.new(side * offset, 0, mid)
				local clear = true
				for _, cu in ipairs({ -1, 1 }) do
					for _, cv in ipairs({ -1, 1 }) do
						local corner = centre * Vector3.new(cu * w / 2, 0, cv * chunkLen / 2)
						if self:inLane(corner.X, corner.Z, 2) then clear = false end
					end
				end
				if clear then
					local sz = TrackKit.part(root, {
						Name = "SlowZone_" .. i .. "_" .. c .. (side > 0 and "R" or "L"),
						Size = Vector3.new(w, h, chunkLen + 0.5),
						CFrame = centre,
						Color = style.color, Material = style.material,
						CanCollide = false, CastShadow = false,
						Transparency = style.transparency or 0.6,
					})
					TrackKit.tag(sz, "SlowZone")
				end
			end
		end
	end
end

-- ─── Checkpoints ──────────────────────────────────────────────────────────────

TrackKit.CHECKPOINT_COLORS = {
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(255, 200, 100),
}

--- Trigger (Track.checkpointSize = { across, height, depth }) turned to the
-- track, plus a neon arch. style: { archHeight, beacon (studs, optional),
-- labelDistance }
function TrackKit:buildCheckpoints(root, style)
	style = style or {}
	local size = self.track.checkpointSize
	local archH = style.archHeight or 18
	for idx, cp in ipairs(self.track.checkpoints) do
		local x, z = cp[1], cp[2]
		local gateCF = self:trackCF(x, self.top, z, cp[3])
		local color = TrackKit.CHECKPOINT_COLORS[idx] or TrackKit.CHECKPOINT_COLORS[1]
		local trigger = TrackKit.part(root, {
			Name = "Checkpoint" .. idx,
			Size = Vector3.new(size[1], size[2], size[3]),
			CFrame = gateCF * CFrame.new(0, size[2] / 2 - 1, 0),
			CanCollide = false, Transparency = 1,
		})
		TrackKit.tag(trigger, "Checkpoint" .. idx)

		for _, side in ipairs({ -1, 1 }) do
			TrackKit.part(root, {
				Name = "CPGate" .. idx .. "Pillar" .. (side > 0 and "R" or "L"),
				Size = Vector3.new(2.4, archH, 2.4),
				CFrame = gateCF * CFrame.new(side * (self.half - 2), archH / 2, 0),
				Color = color, Material = Enum.Material.Neon,
				CanCollide = false, CastShadow = false,
			})
		end
		for k = -1, 1 do
			TrackKit.part(root, {
				Name = "CPGate" .. idx .. "Top" .. (k + 2),
				Size = Vector3.new(self.width / 3 + 2, 2, 2.4),
				CFrame = gateCF * CFrame.new(k * (self.width / 3), archH + (k == 0 and 2 or 0.5), 0),
				Color = color, Material = Enum.Material.Neon,
				CanCollide = false, CastShadow = false,
			})
		end
		if style.beacon then
			TrackKit.part(root, {
				Name = "CPGate" .. idx .. "Beacon",
				Size = Vector3.new(1.4, style.beacon, 1.4),
				CFrame = gateCF * CFrame.new(0, archH + 8 + style.beacon / 2, 0),
				Color = color, Material = Enum.Material.Neon,
				CanCollide = false, CastShadow = false, Transparency = 0.15,
			})
		end
		local anchor = TrackKit.part(root, {
			Name = "CPGate" .. idx .. "Label", Size = Vector3.new(1, 1, 1),
			CFrame = gateCF * CFrame.new(0, archH + 8, 0),
			Transparency = 1, CanCollide = false, CastShadow = false,
		})
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 150, 0, 40)
		bb.MaxDistance = style.labelDistance or 300
		bb.LightInfluence = 0
		bb.AlwaysOnTop = style.labelDistance ~= nil
		bb.Parent = anchor
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "CP " .. idx
		lbl.TextColor3 = color
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.2
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.Parent = bb
	end
end

-- ─── Boost pads ───────────────────────────────────────────────────────────────

--- Pads (Track.boostPadSize) turned to the track with an arrow pointing the
-- way to go. style: { color, arrowColor, ringColor (optional) }
function TrackKit:buildBoostPads(root, style)
	local ps = self.track.boostPadSize
	for i, pd in ipairs(self.track.boostPads) do
		local cf = self:trackCF(pd[1], self.top + ps[2] / 2, pd[2], pd[3])
		local pad = TrackKit.part(root, {
			Name = "BoostPad_" .. i, Size = Vector3.new(ps[1], ps[2], ps[3]), CFrame = cf,
			Color = style.color, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
		TrackKit.tag(pad, "BoostPad")
		local arrow = TrackKit.wedge(root, {
			Name = "BoostArrow_" .. i, Size = Vector3.new(5, 0.4, 5),
			Color = style.arrowColor or Color3.fromRGB(255, 240, 80), Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false,
		})
		arrow.CFrame = cf * CFrame.new(0, 0.2, -(ps[3] / 2 + 1)) * CFrame.Angles(0, math.pi, 0)
		if style.ringColor then
			TrackKit.part(root, {
				Name = "BoostRing_" .. i, Size = Vector3.new(ps[1] + 4, 0.2, ps[3] + 4),
				CFrame = cf * CFrame.new(0, -0.1, 0),
				Color = style.ringColor, Material = Enum.Material.Neon,
				Transparency = 0.5, CanCollide = false, CastShadow = false,
			})
		end
	end
end

-- ─── Drift corners / jump zones ───────────────────────────────────────────────

--- Triggers (Track.driftCornerSize = { across, height, along }) turned to the
-- track. style.visual(root, cf, i) adds the biome's marker.
function TrackKit:buildDriftCorners(root, style)
	local s = self.track.driftCornerSize
	for i, c in ipairs(self.track.driftCorners) do
		local cf = self:trackCF(c[1], self.top, c[2], c[3])
		local trigger = TrackKit.part(root, {
			Name = "DriftCorner_" .. i, Size = Vector3.new(s[1], s[2], s[3]),
			CFrame = cf * CFrame.new(0, s[2] / 2, 0),
			CanCollide = false, Transparency = 1,
		})
		TrackKit.tag(trigger, "DriftCorner")
		if style and style.visual then style.visual(root, cf, i) end
	end
end

--- Jump triggers (Track.jumpZoneSize = { across, height, along }) turned to
-- the track. style.visual(root, cf, i, ramp) adds the ramp / marker; `ramp`
-- is the data entry ({ x, z [, yaw] }).
function TrackKit:buildJumpZones(root, style)
	local s = self.track.jumpZoneSize
	for i, r in ipairs(self.track.jumpRamps) do
		local cf = self:trackCF(r[1], self.top, r[2])
		local jz = TrackKit.part(root, {
			Name = "JumpZone_" .. i, Size = Vector3.new(s[1], s[2], s[3]),
			CFrame = cf * CFrame.new(0, s[2] / 2, 0),
			CanCollide = false, Transparency = 1,
		})
		TrackKit.tag(jz, "JumpZone")
		if style and style.visual then style.visual(root, cf, i, r) end
	end
end

-- ─── Finish line ──────────────────────────────────────────────────────────────

--- Finish trigger across the lane where the track reaches Track.finishZ
-- (Track.finishSize = { across, height, depth }), checker tiles, poles in the
-- wall line, arch. style: { poleColor, poleMaterial, archColor }
function TrackKit:buildFinish(root, style)
	local t = self.track
	local x = t.finishX or 0
	local z = t.finishZ
	local cf = self:trackCF(x, self.top, z)
	local fs = t.finishSize
	local finish = TrackKit.part(root, {
		Name = "FinishLine", Size = Vector3.new(fs[1], fs[2], fs[3]),
		CFrame = cf * CFrame.new(0, fs[2] / 2, 0),
		CanCollide = false, Transparency = 1,
	})
	TrackKit.tag(finish, "FinishLine")

	local cols = math.floor(self.width / 4)
	for col = 0, cols - 1 do
		for row = 0, 1 do
			TrackKit.part(root, {
				Name = "FinishTile", Size = Vector3.new(4, 0.3, 4),
				CFrame = cf * CFrame.new(-self.width / 2 + 2 + col * 4, 0.15, -2 + row * 4),
				Color = (col + row) % 2 == 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
				Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false,
			})
		end
	end
	local poleX = self:wallOffset()
	local poleH = 18
	for _, side in ipairs({ -1, 1 }) do
		TrackKit.part(root, {
			Name = "FinishPole" .. (side > 0 and "R" or "L"),
			Size = Vector3.new(1.5, poleH, 1.5),
			CFrame = cf * CFrame.new(side * poleX, poleH / 2, 0),
			Color = style.poleColor or Color3.fromRGB(240, 240, 240),
			Material = style.poleMaterial or Enum.Material.Metal,
		})
	end
	TrackKit.part(root, {
		Name = "FinishArch", Size = Vector3.new(poleX * 2 + 1.5, 2.5, 1.5),
		CFrame = cf * CFrame.new(0, poleH + 1, 0),
		Color = style.archColor or Color3.fromRGB(220, 55, 55), Material = Enum.Material.Neon,
		CanCollide = false,
	})
end

-- ─── Start grid ───────────────────────────────────────────────────────────────

--- Start boxes on Track.startGrid, poles in the wall line and a banner.
-- style: { boxColor, poleColor, bannerColor }
function TrackKit:buildStartGrid(root, style)
	local g = self.track.startGrid
	for ri, z in ipairs(g.rows) do
		for ci, x in ipairs(g.cols) do
			TrackKit.part(root, {
				Name = "StartBox_" .. ((ri - 1) * #g.cols + ci), Size = Vector3.new(6, 0.2, 6),
				Position = Vector3.new(x, (style.boxY or self.top) + 0.1, z),
				Color = style.boxColor or Color3.fromRGB(60, 120, 255), Material = Enum.Material.Neon,
				CanCollide = false, CastShadow = false, Transparency = 0.3,
			})
		end
	end
	-- start gate just ahead of the front row (race runs toward lower s)
	local front = self.geo:project(0, g.rows[1])
	local gx, gz = self.geo:pointAt(math.max(front.s, 0) + 4)
	local cf = self:trackCF(gx, self.top, gz)
	local poleX = self:wallOffset()
	for _, side in ipairs({ -1, 1 }) do
		TrackKit.part(root, {
			Name = "StartPole" .. (side > 0 and "R" or "L"), Size = Vector3.new(1.5, 14, 1.5),
			CFrame = cf * CFrame.new(side * poleX, 7, 0),
			Color = style.poleColor or Color3.fromRGB(240, 240, 240), Material = Enum.Material.Metal,
		})
	end
	TrackKit.part(root, {
		Name = "StartBanner", Size = Vector3.new(poleX * 2 + 1.5, 2, 1),
		CFrame = cf * CFrame.new(0, 14, 0),
		Color = style.bannerColor or Color3.fromRGB(255, 220, 40), Material = Enum.Material.Neon,
		CanCollide = false,
	})
end

return TrackKit
