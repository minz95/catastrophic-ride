-- GpLayout.lua
-- Junk Grand Prix (2026-11-19, the user's idea: "a car you bought earns you
-- the right to race: the town's racing experience track, F1 thrills, box
-- box, the car's real Catastrophic Ride performance; feel like an F1
-- driver, the release of driving on the edge of rolling over"). An open
-- circuit west of Auto Street: anyone with a car drives in from the pit
-- lane, bots lap it all the time, a run is an out lap and Constants.GP.LAPS
-- timed laps, then you are back in town. Pure positions here (offsets from
-- LobbyLayout.ORIGIN); Modules/Maps/GpCircuit builds it, GpManager runs it.
--
--          north (-Z)
--   T1 ┌───────── esses ───────────┐ fast left
--      │                            │
--  main│ pit lane, garages     back │ straight
--  str.│ (infield, west)            │
--      └──── sweeper ── chicane ── hairpin
--          south (+Z)
-- Travel: north up the main straight (x = -360), west along the north
-- side, south down the back straight, east along the south side.
-- The town is east of the main straight (Auto Street's lot ends at x -300).

local GpLayout = {}

local V = Vector3.new

GpLayout.WIDTH = 28          -- the road
GpLayout.KERB = 3            -- kerb strip outside the road edge where it bends
GpLayout.KERB_RADIUS = 190   -- kerbs where the road bends tighter than this
GpLayout.GRAVEL_RADIUS = 120 -- gravel traps outside bends tighter than this
GpLayout.RUNOFF = 16         -- grass / gravel between the road edge and the barrier
GpLayout.STEP = 8            -- studs between centerline samples
GpLayout.GROUND = { -1190, -299, -330, 330 }   -- the circuit's grass (x0, x1, z0, z1 offsets)

-- the road: corners of a polygon in travel order { x, z, radius }, each
-- rounded by a circular arc of that radius (offsets from ORIGIN)
GpLayout.CORNERS = {
	{ -360, -255, 45 },     -- T1: left at the end of the main straight, heavy braking
	{ -590, -255, 50 },     -- T2: left, south into the infield
	{ -590, -90, 46 },      -- T3: right
	{ -800, -90, 44 },      -- T4: right, north again
	{ -800, -265, 40 },     -- T5: left onto the north straight
	{ -1130, -265, 110 },   -- T6: a fast left onto the back straight
	{ -1130, 285, 36 },     -- T7: left at the end of the back straight, the longest braking
	{ -950, 285, 30 },      -- the chicane: left …
	{ -915, 248, 26 },      -- … right …
	{ -878, 285, 30 },      -- … left
	{ -700, 285, 42 },      -- T8: left, north into the twisty bit
	{ -700, 80, 38 },       -- T9: right
	{ -520, 80, 38 },       -- T10: right, south
	{ -520, 290, 75 },      -- the sweeper: two lefts into one long bend, flat out
	{ -360, 290, 62 },      --   onto the main straight
}

-- start / finish line (z on the main straight) and the sector lines (share of the lap)
GpLayout.LINE_Z = 40
GpLayout.SECTORS = { 0.36, 0.68 }

-- the pit lane: in the infield beside the main straight, entered after the
-- last corner, rejoining before T1 (z ranges are offsets)
GpLayout.PIT = {
	x = -394,               -- the lane's middle
	width = 18,             -- fast lane (east) and working lane (west)
	z0 = -146, z1 = 190,    -- the lane (north end, south end)
	entryZ = 224,           -- leaves the track's west edge here …
	exitZ = -186,           -- … and joins it again here
	wallX = -379,           -- the pit wall between the lane and the straight
	wallZ = { -128, 176 },
	limit = 45,             -- studs/s in the lane
	garageX = { -406, -430 },
	boxes = 12,
	boxZ0 = 150, boxStep = -22,   -- box 1's z, then north
	boxX = -396,            -- where the car stops (the lane's west half, clear of the garages)
}

GpLayout.GRANDSTAND = { x = { -329, -309 }, z = { -170, 180 } }   -- east of the straight, by the town (walk-in, LobbyLayout.STREET.stand)
GpLayout.CATCH_FENCE = -331      -- x of the tall fence between the grandstand and the track
GpLayout.ENTRANCE = V(-290, 0, 0)    -- the GP gate at the road's west end (Auto Street)
GpLayout.EXIT = V(-280, 0, 0)        -- where a driver is put back in town

local function unit(x, z)
	local m = math.sqrt(x * x + z * z)
	return x / m, z / m
end

local _nodes
--- The centerline, closed: { {x, z} } offsets every ~STEP studs, the last
-- node equal to the first (TrackGeometry over it measures the whole lap).
-- Node 1 is on the start / finish line.
function GpLayout.nodes()
	if _nodes then return _nodes end
	local C = GpLayout.CORNERS
	local n = #C
	-- each corner: the straight ends at `entry`, an arc to `exit`
	local path = {}
	for i = 1, n do
		local p, v, q = C[(i - 2) % n + 1], C[i], C[i % n + 1]
		local ax, az = unit(v[1] - p[1], v[2] - p[2])
		local bx, bz = unit(q[1] - v[1], q[2] - v[2])
		local turn = math.atan2(ax * bz - az * bx, ax * bx + az * bz)   -- signed deflection
		local r = v[3]
		local t = r * math.tan(math.abs(turn) / 2)
		local ex, ez = v[1] - ax * t, v[2] - az * t
		-- the arc's centre: to the side the road turns
		local sx, sz
		if turn > 0 then sx, sz = -az, ax else sx, sz = az, -ax end
		local cx, cz = ex + sx * r, ez + sz * r
		local a0 = math.atan2(ez - cz, ex - cx)
		local steps = math.max(2, math.ceil(math.abs(turn) * r / 2))
		for k = 0, steps do
			local a = a0 + turn * k / steps
			table.insert(path, { cx + math.cos(a) * r, cz + math.sin(a) * r })
		end
	end
	-- start at the line: the point on the main straight nearest it
	local dense = {}
	for i = 1, #path do
		local a, b = path[i], path[i % #path + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local k = math.max(1, math.ceil(len / 2))
		for j = 0, k - 1 do
			table.insert(dense, { a[1] + dx * j / k, a[2] + dz * j / k })
		end
	end
	local first, best = 1, math.huge
	for i, p in ipairs(dense) do
		local d = math.abs(p[1] + 360) * 4 + math.abs(p[2] - GpLayout.LINE_Z)
		if d < best then first, best = i, d end
	end
	local ordered = {}
	for k = 0, #dense - 1 do table.insert(ordered, dense[(first - 1 + k) % #dense + 1]) end
	-- resample every STEP studs
	local out = { { ordered[1][1], ordered[1][2] } }
	local acc = 0
	for i = 2, #ordered do
		local a, b = ordered[i - 1], ordered[i]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		acc += math.sqrt(dx * dx + dz * dz)
		if acc >= GpLayout.STEP then
			table.insert(out, { b[1], b[2] })
			acc = 0
		end
	end
	table.insert(out, { out[1][1], out[1][2] })
	_nodes = out
	return out
end

--- Each corner's straight-to-arc distance (studs) and the straight it
-- leaves after it: { t, room } (room < 0: two arcs overlap).
function GpLayout.fillets()
	local C = GpLayout.CORNERS
	local n = #C
	local t = {}
	for i = 1, n do
		local p, v, q = C[(i - 2) % n + 1], C[i], C[i % n + 1]
		local ax, az = unit(v[1] - p[1], v[2] - p[2])
		local bx, bz = unit(q[1] - v[1], q[2] - v[2])
		local turn = math.atan2(ax * bz - az * bx, ax * bx + az * bz)
		t[i] = v[3] * math.tan(math.abs(turn) / 2)
	end
	local out = {}
	for i = 1, n do
		local v, q = C[i], C[i % n + 1]
		local len = math.sqrt((q[1] - v[1]) ^ 2 + (q[2] - v[2]) ^ 2)
		out[i] = { t = t[i], room = len - t[i] - t[i % n + 1] }
	end
	return out
end

local _geo
--- TrackGeometry over the closed centerline (offsets, baseY 0).
function GpLayout.geometry()
	if _geo then return _geo end
	local TrackGeometry = require(script.Parent.TrackGeometry)
	_geo = TrackGeometry.new(GpLayout.nodes(), GpLayout.WIDTH, 0)
	return _geo
end

function GpLayout.lapLength()
	return GpLayout.geometry().length
end

--- Signed bend radius at centerline node i (studs; + = left bend), from the
-- turn between its neighbours. math.huge on a straight.
function GpLayout.radiusAt(i)
	local N = GpLayout.nodes()
	local n = #N - 1
	local a, b, c = N[(i - 2) % n + 1], N[(i - 1) % n + 1], N[i % n + 1]
	local ax, az = b[1] - a[1], b[2] - a[2]
	local bx, bz = c[1] - b[1], c[2] - b[2]
	local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
	if la < 1e-6 or lb < 1e-6 then return math.huge end
	local cross = ax * bz - az * bx
	local dot = ax * bx + az * bz
	local ang = math.atan2(cross, dot)
	if math.abs(ang) < 1e-5 then return math.huge end
	-- facing +X, a turn toward -Z (left) has a negative cross product here
	return -((la + lb) / 2) / ang
end

--- Lap share (0..1) of offset (x, z), and the lateral offset (+ = right).
function GpLayout.where(x, z, hint)
	local geo = GpLayout.geometry()
	local p = geo:project(x, z, hint)
	return p.s / geo.length, p.lateral, p.seg
end

--- True when offset (x, z) is in the pit lane (lane, entry or exit road).
function GpLayout.inPit(x, z)
	local P = GpLayout.PIT
	local half = P.width / 2
	if math.abs(x - P.x) <= half + 1 and z >= P.z0 - 2 and z <= P.z1 + 2 then return true end
	-- the angled roads from the track's west edge to the lane's ends
	for _, ends in ipairs({ { P.z1, P.entryZ }, { P.z0, P.exitZ } }) do
		local zl, zt = ends[1], ends[2]
		local lo, hi = math.min(zl, zt), math.max(zl, zt)
		if z >= lo and z <= hi then
			local f = (z - zl) / (zt - zl)
			local cx = P.x + (-366 - P.x) * f
			if math.abs(x - cx) <= half + 2 then return true end
		end
	end
	return false
end

--- Box k's stop (offset) and the garage behind it; the car faces north.
function GpLayout.box(k)
	local P = GpLayout.PIT
	local z = P.boxZ0 + (k - 1) * P.boxStep
	return V(P.boxX, 0, z), V((P.garageX[1] + P.garageX[2]) / 2, 0, z)
end

--- The pit lane as a path to drive (offsets, south to north): entry road,
-- the lane, exit road. Bots follow it.
function GpLayout.pitPath()
	local P = GpLayout.PIT
	return {
		V(-366, 0, P.entryZ), V((P.x - 366) / 2, 0, (P.entryZ + P.z1) / 2), V(P.x - 4, 0, P.z1),
		V(P.x - 4, 0, P.z0), V((P.x - 366) / 2, 0, (P.z0 + P.exitZ) / 2), V(-366, 0, P.exitZ),
	}
end

--- World position of offset `p` (Vector3) or (x, z).
function GpLayout.world(x, z)
	local O = require(script.Parent.LobbyLayout).ORIGIN
	if typeof(x) == "Vector3" then return O + x end
	return O + V(x, 0, z)
end

--- Offset (x, z) of a world position.
function GpLayout.offset(pos)
	local O = require(script.Parent.LobbyLayout).ORIGIN
	return pos.X - O.X, pos.Z - O.Z
end

--- True when a world position is on the circuit's ground (cars only).
function GpLayout.onCircuit(pos)
	local O = require(script.Parent.LobbyLayout).ORIGIN
	local G = GpLayout.GROUND
	local dx, dz = pos.X - O.X, pos.Z - O.Z
	return dx >= G[1] and dx <= G[2] and dz >= G[3] and dz <= G[4] and pos.Y > O.Y - 20 and pos.Y < O.Y + 80
end

return GpLayout
