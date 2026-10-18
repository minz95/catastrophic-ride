-- TrackGeometry.lua
-- Pure 2D polyline math for race tracks (XZ plane). No Roblox types, so it
-- runs in Studio, on clients, and under Lune.
--
--   local geo = TrackGeometry.new(ForestTrack.nodes, ForestTrack.width)
--   local p = geo:project(x, z, hintSeg)  -- { s, lateral, seg, cx, cz, dist }
--   local x, z, dx, dz = geo:pointAt(s)
--
-- Conventions
--   s        arc length from node 1 along the centerline (studs)
--   lateral  signed distance from the centerline; positive = RIGHT of the
--            direction of travel (dx, dz) → right = (-dz, dx) on the XZ plane
--            as seen from above with +Y up.

local TrackGeometry = {}
TrackGeometry.__index = TrackGeometry

function TrackGeometry.new(nodes, width)
	assert(#nodes >= 2, "TrackGeometry.new: need at least 2 nodes")
	local self = setmetatable({}, TrackGeometry)
	self.nodes = nodes
	self.width = width or 40
	self.halfWidth = self.width / 2
	self.segments = {}
	local s = 0
	for i = 1, #nodes - 1 do
		local ax, az = nodes[i][1], nodes[i][2]
		local bx, bz = nodes[i + 1][1], nodes[i + 1][2]
		local dx, dz = bx - ax, bz - az
		local len = math.sqrt(dx * dx + dz * dz)
		local seg = {
			index = i,
			ax = ax, az = az, bx = bx, bz = bz,
			len = len,
			s0 = s,
			dx = len > 0 and dx / len or 0,
			dz = len > 0 and dz / len or 0,
		}
		table.insert(self.segments, seg)
		s += len
	end
	self.length = s
	-- Bisector normals at every node: segment k owns the region between the
	-- bisector at its start node and the one at its end node.
	self.bisectors = {}
	for k = 1, #self.segments + 1 do
		local prev, nxt = self.segments[k - 1], self.segments[k]
		local nx, nz
		if prev and nxt then
			nx, nz = prev.dx + nxt.dx, prev.dz + nxt.dz
		elseif nxt then
			nx, nz = nxt.dx, nxt.dz
		else
			nx, nz = prev.dx, prev.dz
		end
		local m = math.sqrt(nx * nx + nz * nz)
		if m < 1e-9 then
			nx, nz = (nxt or prev).dx, (nxt or prev).dz   -- 180° hairpin: use the outgoing direction
			m = 1
		end
		self.bisectors[k] = { nx / m, nz / m }
	end
	return self
end

local function projectOnSegment(seg, x, z)
	if seg.len == 0 then
		local ex, ez = x - seg.ax, z - seg.az
		return 0, seg.ax, seg.az, math.sqrt(ex * ex + ez * ez)
	end
	local t = ((x - seg.ax) * seg.dx + (z - seg.az) * seg.dz)
	t = math.clamp(t, 0, seg.len)
	local cx, cz = seg.ax + seg.dx * t, seg.az + seg.dz * t
	local ex, ez = x - cx, z - cz
	return t, cx, cz, math.sqrt(ex * ex + ez * ez)
end

--- Closest point on the centerline.
-- @param hintSeg optional segment index from the previous query. When given,
--   only segments within `window` of it are searched, so a car never "jumps"
--   to a different part of the track that happens to pass nearby.
function TrackGeometry:project(x, z, hintSeg, window)
	local lo, hi = 1, #self.segments
	if hintSeg then
		window = window or 3
		lo = math.max(1, hintSeg - window)
		hi = math.min(#self.segments, hintSeg + window)
	end
	local best
	for i = lo, hi do
		local seg = self.segments[i]
		local t, cx, cz, dist = projectOnSegment(seg, x, z)
		if not best or dist < best.dist - 1e-9 then
			best = { seg = i, t = t, cx = cx, cz = cz, dist = dist }
		end
	end
	local seg = self.segments[best.seg]
	-- Right of travel = (-dz, dx)
	local rx, rz = -seg.dz, seg.dx
	best.lateral = (x - best.cx) * rx + (z - best.cz) * rz
	best.s = seg.s0 + best.t
	return best
end

--- Distance along the track for ranking. Unlike project(), it is continuous
-- across kinks. Each segment owns the area between the angle bisectors at its
-- two nodes; inside it the position is the fraction of the way from the start
-- bisector to the end bisector:
--   u = d0 / (d0 + d1),  d0 / d1 = distance to the start / end bisector line
-- u is 0 on the start line and 1 on the end line, so neighbouring segments
-- agree at every bisector and a car driving forward never loses progress.
-- Returns s (clamped to [0, length]), segment index.
function TrackGeometry:progressAt(x, z, hintSeg, window)
	local lo, hi = 1, #self.segments
	if hintSeg then
		window = window or 3
		lo = math.max(1, hintSeg - window)
		hi = math.min(#self.segments, hintSeg + window)
	end
	local best, bestDist, bestS
	for k = lo, hi do
		local seg = self.segments[k]
		local b0, b1 = self.bisectors[k], self.bisectors[k + 1]
		local d0 = (x - seg.ax) * b0[1] + (z - seg.az) * b0[2]
		local d1 = (seg.bx - x) * b1[1] + (seg.bz - z) * b1[2]
		local inside = (d0 >= 0 or k == 1) and (d1 > 0 or k == #self.segments)
		if inside then
			local u
			if d0 + d1 <= 1e-9 then
				u = 0
			elseif d0 < 0 then
				u = d0 / seg.len            -- before the first node
			elseif d1 < 0 then
				u = 1 - d1 / seg.len        -- past the last node
			else
				u = d0 / (d0 + d1)
			end
			local perp = math.abs((x - seg.ax) * -seg.dz + (z - seg.az) * seg.dx)
			if not bestDist or perp < bestDist then
				best, bestDist, bestS = k, perp, seg.s0 + u * seg.len
			end
		end
	end
	if not best then
		-- Outside every region in the window (far off the track): nearest point
		local p = self:project(x, z, hintSeg, window)
		return p.s, p.seg
	end
	return math.clamp(bestS, 0, self.length), best
end

--- Point and unit direction at arc length s (clamped to the track).
function TrackGeometry:pointAt(s)
	s = math.clamp(s, 0, self.length)
	local segs = self.segments
	-- Binary search on s0
	local lo, hi = 1, #segs
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if segs[mid].s0 <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local seg = segs[lo]
	local t = s - seg.s0
	return seg.ax + seg.dx * t, seg.az + seg.dz * t, seg.dx, seg.dz, lo
end

--- Offset a point sideways (positive = right of travel).
function TrackGeometry:offsetPoint(s, lateral)
	local x, z, dx, dz, seg = self:pointAt(s)
	return x - dz * lateral, z + dx * lateral, dx, dz, seg
end

--- Signed deflection angle at each interior node, in degrees.
-- Positive = turning right, negative = turning left (seen from above).
function TrackGeometry:deflections()
	local out = {}
	for i = 2, #self.segments do
		local a, b = self.segments[i - 1], self.segments[i]
		local cross = a.dx * b.dz - a.dz * b.dx
		local dot = a.dx * b.dx + a.dz * b.dz
		-- With right = (-dz, dx), turning toward the right gives cross > 0.
		local ang = math.deg(math.atan2(cross, dot))
		table.insert(out, { node = i, angle = ang, lenIn = a.len, lenOut = b.len })
	end
	return out
end

--- Circumradius of three consecutive nodes: a curvature estimate for arcs that
-- are approximated by several short segments. math.huge for collinear nodes.
function TrackGeometry:nodeRadius(i)
	local n = self.nodes
	if i <= 1 or i >= #n then
		return math.huge
	end
	local ax, az = n[i - 1][1], n[i - 1][2]
	local bx, bz = n[i][1], n[i][2]
	local cx, cz = n[i + 1][1], n[i + 1][2]
	local abx, abz = bx - ax, bz - az
	local bcx, bcz = cx - bx, cz - bz
	local cax, caz = ax - cx, az - cz
	local a = math.sqrt(bcx * bcx + bcz * bcz)
	local b = math.sqrt(cax * cax + caz * caz)
	local c = math.sqrt(abx * abx + abz * abz)
	local area2 = math.abs(abx * (cz - az) - abz * (cx - ax))
	if area2 < 1e-9 then
		return math.huge
	end
	return (a * b * c) / (2 * area2)
end

--- Where a side wall of segment `i` should stand.
-- The wall line runs `offset` studs from the segment's centerline on side
-- `lat` (+1 = right of travel, -1 = left). It is extended past both nodes far
-- enough to close the outside of a turn for a wall whose outer face is `reach`
-- studs out, and every stretch whose line lies inside the lane (the inside of
-- a turn, or anywhere the track passes over itself) is dropped.
-- Returns runs { {t0, t1}, ... } in studs from the segment's start node along
-- its direction (t0 may be < 0 and t1 > len on the extensions).
function TrackGeometry:boundaryRuns(i, lat, offset, reach, step)
	step = step or 1
	reach = reach or offset
	local seg = self.segments[i]
	local half = self.halfWidth
	local function ext(a, b)
		if not a or not b or a.len == 0 or b.len == 0 then
			return 0
		end
		local dot = math.clamp(a.dx * b.dx + a.dz * b.dz, -1, 1)
		local theta = math.acos(dot)
		return math.min(reach * math.tan(theta / 2) + step, 3 * self.width)
	end
	local t0 = -ext(self.segments[i - 1], seg)
	local t1 = seg.len + ext(seg, self.segments[i + 1])
	local rx, rz = -seg.dz * lat, seg.dx * lat
	local runs, cur = {}, nil
	local n = math.max(1, math.ceil((t1 - t0) / step))
	for k = 0, n do
		local t = t0 + (t1 - t0) * k / n
		local px = seg.ax + seg.dx * t + rx * offset
		local pz = seg.az + seg.dz * t + rz * offset
		if self:project(px, pz).dist >= half then
			if cur then
				cur[2] = t
			else
				cur = { t, t }
			end
		elseif cur then
			table.insert(runs, cur)
			cur = nil
		end
	end
	if cur then
		table.insert(runs, cur)
	end
	-- Keep only runs that touch the segment itself: an extension that is cut
	-- off from it crossed another part of the lane (the inside wall of a sharp
	-- turn runs straight through the next segment) and would stand alone as
	-- a spur on the far side.
	local out = {}
	for _, r in ipairs(runs) do
		if r[2] - r[1] >= 0.5 and r[2] > 0 and r[1] < seg.len then
			table.insert(out, r)
		end
	end
	return out
end

--- Heading (radians, Roblox yaw convention: atan2(-dx, -dz)) at arc length s.
-- A CFrame with this yaw has LookVector = (dx, 0, dz).
function TrackGeometry:yawAt(s)
	local _, _, dx, dz = self:pointAt(s)
	return math.atan2(-dx, -dz)
end

--- Section name for a segment index, given a track's `sections` list.
function TrackGeometry.sectionOf(sections, segIndex)
	if not sections then
		return nil
	end
	for _, sec in ipairs(sections) do
		if segIndex >= sec.from and segIndex < sec.to then
			return sec.name
		end
	end
	return sections[#sections] and sections[#sections].name
end

return TrackGeometry
