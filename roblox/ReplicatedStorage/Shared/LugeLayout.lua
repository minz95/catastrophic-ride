-- LugeLayout.lua
-- The Alpine Luge (2026-11-20, the user's idea: "a luge corner beside the
-- GP for the cars you buy; not F1 but a cheerful, homely ride down a
-- winding road; friends may bump, a cart may slip off the side"). A grassy
-- hill north of Junk Motors' showroom, east of the GP: a chairlift carries
-- your car up its east side, a concrete trough zigzags down in hairpins
-- (on wooden trestles where the hill drops faster than the trough may),
-- you roll back into the bottom station and the chairlift takes you again.
-- Pure positions here (offsets from LobbyLayout.ORIGIN; heights over its
-- floor); Modules/Maps/LugeHill builds it, LugeManager runs it.
--
--        north (-Z)          top station, start gate ─┐ chairlift
--   ┌──────────────────────────────── start ◄────────┤   │
--   └──► hairpin … eight legs, seven hairpins …       │   │
--   ◄──────────────────────────────────────────┐      │   │
--   └────────────────────────────────► finish ─┴► bottom station
--        south (+Z): the showroom, Auto Street

local LobbyLayout = require(script.Parent.LobbyLayout)

local LugeLayout = {}

local V = Vector3.new

LugeLayout.REGION = { -299, -116, -486, -74 }   -- the hill's grounds (x0, x1, z0, z1): meets the GP's grass and Auto Street's lot
LugeLayout.HILL = { top = 90, zTop = -452, zBottom = -112 }   -- the slope rises north from zBottom to zTop
LugeLayout.ROAD = 0.4          -- the trough's floor over the ground
LugeLayout.MAX_GRADE = 0.12    -- the trough never drops faster: where the hill does, it stands on trestles
LugeLayout.START_RISE = 2      -- the start gate stands on a little ramp
LugeLayout.STEP = 3            -- studs between centerline samples (tight hairpins)

-- the trough: corners in travel order { x, z, radius } (the first and last
-- points are its ends), each rounded by an arc of that radius
LugeLayout.CORNERS = {
	{ -146, -462 },              -- the start gate, heading west
	{ -272, -443, 11 },          -- hairpin 1
	{ -272, -413, 11 },
	{ -150, -394, 11 },          -- hairpin 2
	{ -150, -364, 11 },
	{ -196, -360, 34 },          -- an S on the way west
	{ -228, -350, 34 },
	{ -272, -345, 11 },          -- hairpin 3
	{ -272, -315, 11 },
	{ -211, -301, 70 },          -- a long sweep east
	{ -150, -296, 11 },          -- hairpin 4
	{ -150, -266, 11 },
	{ -272, -247, 11 },          -- hairpin 5
	{ -272, -217, 11 },
	{ -150, -198, 11 },          -- hairpin 6
	{ -150, -168, 11 },
	{ -272, -149, 11 },          -- hairpin 7
	{ -272, -119, 11 },
	{ -178, -102, 40 },          -- the last bend into the finish straight
	{ -134, -99 },               -- the run-out's end, by the bottom station
}
LugeLayout.FINISH_BACK = 36    -- the finish line, this far before the run-out's end

-- the chairlift up the hill's east side: where a car is hooked on at the
-- bottom station and let off at the top; the cable this high over them
LugeLayout.LIFT = {
	x = -124,
	bottom = V(-124, 0, -94),
	top = V(-124, 100, -470),   -- over the top station's deck (the line stays above the hill)
	hang = 10,                  -- the cable over the car's floor
	towerStep = 46,
}
LugeLayout.BOTTOM_STATION = { -136, -116, -108, -84 }   -- x0, x1, z0, z1
LugeLayout.TOP_STATION = { -140, -112, -484, -458 }
-- the desk in town: at the north end of the way between the showroom and
-- the lot's east wall (prompt LugeAction "enter"); back there after a ride
LugeLayout.DESK = V(-121, 0, -68)
LugeLayout.EXIT = V(-121, 0, -56)

function LugeLayout.wrapYaw(a) return (a + math.pi) % (2 * math.pi) - math.pi end

local function unit(x, z)
	local m = math.sqrt(x * x + z * z)
	return x / m, z / m
end

--- The ground's height (over ORIGIN.Y) at offset z.
function LugeLayout.ground(z)
	local H = LugeLayout.HILL
	local f = math.clamp((H.zBottom - z) / (H.zBottom - H.zTop), 0, 1)
	return H.top * f
end

local _nodes
--- The centerline from the start gate to the run-out's end: { {x, z, y} }
-- every ~STEP studs; y = the trough's floor (over ORIGIN.Y).
function LugeLayout.nodes()
	if _nodes then return _nodes end
	local C = LugeLayout.CORNERS
	local n = #C
	local path = { { C[1][1], C[1][2] } }
	for i = 2, n - 1 do
		local p, v, q = C[i - 1], C[i], C[i + 1]
		local ax, az = unit(v[1] - p[1], v[2] - p[2])
		local bx, bz = unit(q[1] - v[1], q[2] - v[2])
		local turn = math.atan2(ax * bz - az * bx, ax * bx + az * bz)
		local r = v[3]
		local t = r * math.tan(math.abs(turn) / 2)
		local ex, ez = v[1] - ax * t, v[2] - az * t
		local sx, sz
		if turn > 0 then sx, sz = -az, ax else sx, sz = az, -ax end
		local cx, cz = ex + sx * r, ez + sz * r
		local a0 = math.atan2(ez - cz, ex - cx)
		local steps = math.max(2, math.ceil(math.abs(turn) * r / 1.5))
		for k = 0, steps do
			local a = a0 + turn * k / steps
			table.insert(path, { cx + math.cos(a) * r, cz + math.sin(a) * r })
		end
	end
	table.insert(path, { C[n][1], C[n][2] })
	-- resample every STEP studs
	local out = { { path[1][1], path[1][2] } }
	local acc = 0
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local k = math.max(1, math.ceil(len / 0.5))
		for j = 1, k do
			acc += len / k
			if acc >= LugeLayout.STEP then
				table.insert(out, { a[1] + dx * j / k, a[2] + dz * j / k })
				acc = 0
			end
		end
	end
	local last = path[#path]
	local tail = out[#out]
	if (tail[1] - last[1]) ^ 2 + (tail[2] - last[2]) ^ 2 > 1 then table.insert(out, { last[1], last[2] }) end
	-- heights: on the ground, never dropping faster than MAX_GRADE (it
	-- stands on trestles there), never climbing
	-- the ground under the trough's higher side (crossing the slope, one
	-- side stands higher: the floor must clear it there; the other side gets
	-- an embankment, LugeHill)
	local reach = require(script.Parent.Constants).LUGE.WIDTH / 2 + 0.8
	local function floorAt(i)
		local a, b = out[math.max(1, i - 1)], out[math.min(#out, i + 1)]
		local dx, dz = unit(b[1] - a[1], b[2] - a[2])
		local z = out[i][2]
		return math.max(LugeLayout.ground(z + dx * reach), LugeLayout.ground(z - dx * reach), LugeLayout.ground(z)) + LugeLayout.ROAD
	end
	local y = floorAt(1) + LugeLayout.START_RISE
	out[1][3] = y
	for i = 2, #out do
		local a, b = out[i - 1], out[i]
		local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local floor = floorAt(i)
		y = math.max(floor, y - LugeLayout.MAX_GRADE * d)
		y = math.min(y, a[3])
		b[3] = y
	end
	_nodes = out
	return out
end

local _geo
--- TrackGeometry over the centerline (with heights; offsets, baseY 0).
function LugeLayout.geometry()
	if _geo then return _geo end
	local TrackGeometry = require(script.Parent.TrackGeometry)
	_geo = TrackGeometry.new(LugeLayout.nodes(), require(script.Parent.Constants).LUGE.WIDTH, 0)
	return _geo
end

function LugeLayout.length() return LugeLayout.geometry().length end
function LugeLayout.finishS() return LugeLayout.length() - LugeLayout.FINISH_BACK end

local _curve
--- Signed curvature at every node (1 / radius; + = the trough turns to the
-- right of travel), over ±2 nodes.
function LugeLayout.curves()
	if _curve then return _curve end
	local N = LugeLayout.nodes()
	local out = {}
	for i = 1, #N do
		local a, b = N[math.max(1, i - 2)], N[math.min(#N, i + 2)]
		local m = N[i]
		local ax, az = m[1] - a[1], m[2] - a[2]
		local bx, bz = b[1] - m[1], b[2] - m[2]
		local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
		if la < 1e-6 or lb < 1e-6 then
			out[i] = 0
		else
			-- right of travel is (-dz, dx): a turn toward it has cross(a, b) > 0 here
			local cross = ax * bz - az * bx
			local ang = math.atan2(cross, ax * bx + az * bz)
			out[i] = ang / ((la + lb) / 2)
		end
	end
	_curve = out
	return out
end

--- Where a cart is: { s, lateral (+ = right of travel), seg, yaw (the
-- trough's heading; LookVector = (-sin, 0, -cos)), grade (rise per stud
-- along the trough: negative downhill), curve (signed), y (the floor) }.
-- `y` is the cart's height (the trough passes near itself at hairpins),
-- `hint` the last seg.
function LugeLayout.at(x, z, y, hint)
	local geo = LugeLayout.geometry()
	local p = geo:project(x, z, hint, hint and 8 or nil, y)
	local seg = geo.segments[p.seg]
	local yaw = math.atan2(-seg.dx, -seg.dz)
	local N = LugeLayout.nodes()
	local C = LugeLayout.curves()
	return {
		s = p.s, lateral = p.lateral, seg = p.seg, dist = p.dist, yaw = yaw,
		grade = geo:grade(p.seg), curve = C[p.seg] or 0, floor = geo:heightAt(p.s),
		nodeY = N[p.seg][3],
	}
end

--- True when the lip at lateral `lat` on a stretch of curvature `curve` is
-- the high one (the outside of a tight bend).
function LugeLayout.highLip(lat, curve)
	local Constants = require(script.Parent.Constants)
	if math.abs(curve) < 1 / Constants.LUGE.HIGH_LIP_RADIUS then return false end
	-- the outside of a right turn is the left (lateral < 0)
	return (curve > 0 and lat < 0) or (curve < 0 and lat > 0)
end

--- A start slot at the gate: offset position and facing yaw (k = 1, 2:
-- left and right of the trough).
function LugeLayout.startSlot(k)
	local geo = LugeLayout.geometry()
	local s = 5
	local x, z, dx, dz = geo:offsetPoint(s, (k == 1) and -2.8 or 2.8)
	return V(x, geo:heightAt(s), z), math.atan2(-dx, -dz)
end

--- The chairlift: the car's floor position `f` (0 bottom … 1 top) along it.
function LugeLayout.liftAt(f)
	local L = LugeLayout.LIFT
	return L.bottom:Lerp(L.top, math.clamp(f, 0, 1))
end

function LugeLayout.liftLength()
	return (LugeLayout.LIFT.top - LugeLayout.LIFT.bottom).Magnitude
end

--- True when a world position is on the hill's grounds (carts only).
function LugeLayout.onGrounds(pos)
	local O = LobbyLayout.ORIGIN
	local R = LugeLayout.REGION
	local dx, dz = pos.X - O.X, pos.Z - O.Z
	return dx >= R[1] and dx <= R[2] and dz >= R[3] and dz <= R[4] and pos.Y > O.Y - 20 and pos.Y < O.Y + LugeLayout.HILL.top + 40
end

return LugeLayout
