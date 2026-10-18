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
