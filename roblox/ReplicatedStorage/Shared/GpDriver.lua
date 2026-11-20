-- GpDriver.lua
-- The Junk GP's simulated driver: race bots (Modules/GpBots) and the
-- offline lap sim (tools/gp_sim.luau, spec gp) drive with it, through the
-- same GpCar step as players. Pure, no Roblox types.
--
--   local d = GpDriver.new(spec, skill)          -- skill: share of the grip used
--   local input = GpDriver.input(d, st, x, z, yaw, hintSeg)
--
-- It follows the centerline (pure pursuit) at a speed profile: each node's
-- corner speed (GpCar.cornerSpeed with `skill` of the grip), braked back
-- from the next slower one.

local Constants = require(script.Parent.Constants)
local GpCar = require(script.Parent.GpCar)
local GpLayout = require(script.Parent.GpLayout)

local GpDriver = {}

GpDriver.SPAN = 3          -- nodes either side for a bend's radius
GpDriver.BRAKE_USE = 0.7   -- share of the brakes the profile counts on (Studio: the fastest bot overshot T7 at 0.8 and rolled)
-- traffic (Studio 2026-11-19: bots drove into each other and were put back
-- in pairs, "stuck", at the same moment)
GpDriver.CAR_W = 7         -- lateral room a car needs beside another
GpDriver.CAR_L = 11        -- nose to tail room
GpDriver.LINE_MAX = 9      -- furthest off the centerline a pass goes (road half 14)
GpDriver.LINE_RATE = 5     -- studs/s the line moves across
GpDriver.HOLD = 2.5        -- s a pass line is kept after the car ahead is out of the way

local function heading(a, b)
	return math.atan2(-(b[1] - a[1]), -(b[2] - a[2]))   -- yaw facing from a to b
end

--- Where each node is along the lap (studs; node i at nodeS()[i]). Nodes
-- are 8-10 studs apart, so a node's index is not its distance / STEP.
local _nodeS
function GpDriver.nodeS()
	if _nodeS then return _nodeS end
	local N = GpLayout.nodes()
	local out, acc = { 0 }, 0
	for i = 2, #N - 1 do
		acc += math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2)
		out[i] = acc
	end
	_nodeS = out
	return out
end

--- The node at distance s along the lap.
function GpDriver.nodeAt(s)
	local S = GpDriver.nodeS()
	local n = #S
	s = s % GpLayout.lapLength()
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if S[mid] <= s then lo = mid else hi = mid - 1 end
	end
	return lo
end

--- Bend radius at every node (from the heading change over ±SPAN nodes
-- and the real distance between them).
local _radii
function GpDriver.radii()
	if _radii then return _radii end
	local N = GpLayout.nodes()
	local n = #N - 1
	local out = {}
	local function dist(i, j)
		local a, b = N[(i - 1) % n + 1], N[(j - 1) % n + 1]
		return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	end
	for i = 1, n do
		local a = N[(i - 1 - GpDriver.SPAN) % n + 1]
		local b = N[(i - 1) % n + 1]
		local c = N[(i - 1 + GpDriver.SPAN) % n + 1]
		local h1, h2 = heading(a, b), heading(b, c)
		local d = math.abs(GpCar.wrap(h2 - h1))
		local len = 0
		for k = i - GpDriver.SPAN, i + GpDriver.SPAN - 1 do len += dist(k, k + 1) end
		out[i] = d > 1e-4 and (len / 2) / d or math.huge
	end
	_radii = out
	return out
end

--- The speed profile (studs/s per node) of a car at `skill`.
function GpDriver.profile(spec, skill)
	local R = GpDriver.radii()
	local n = #R
	local v = {}
	for i = 1, n do v[i] = GpCar.cornerSpeed(spec, R[i], skill) end
	local dec = spec.brake * GpDriver.BRAKE_USE
	local S = GpDriver.nodeS()
	local L = GpLayout.lapLength()
	for _ = 1, 2 do
		for i = n, 1, -1 do
			local j = i % n + 1
			local gap = (S[j] - S[i]) % L
			v[i] = math.min(v[i], math.sqrt(v[j] * v[j] + 2 * dec * gap))
		end
	end
	return v
end

function GpDriver.new(spec, skill)
	return { spec = spec, skill = skill or 0.9, profile = GpDriver.profile(spec, skill or 0.9), seg = nil }
end

--- Steering, gas and brake toward a point (x, z) with a target speed.
function GpDriver.toward(d, st, x, z, yaw, tx, tz, target, dist)
	local spec = d.spec
	local want = math.atan2(-(tx - x), -(tz - z))
	local alpha = GpCar.wrap(want - yaw)
	local v = math.max(st.speed or 0, 1)
	local L = math.max(dist or 1, 1)
	local yawRate = 2 * v * math.sin(alpha) / L
	local maxYaw = math.min(spec.turn, Constants.GP.OVERDRIVE * spec.grip * GpCar.tyreGrip(st.tyre or 1) / v)
	local steer = math.clamp(yawRate / math.max(maxYaw, 1e-3), -1, 1)
	local throttle, brake = 0, 0
	local sp = st.speed or 0
	if sp < target - 1.5 then
		throttle = 1
	elseif sp > target + 1 then
		brake = math.clamp((sp - target) / 4, 0.3, 1)
	else
		throttle = 0.4
	end
	return { throttle = throttle, brake = brake, steer = steer }
end

--- The car this one would run into: the nearest ahead within a second or
-- so whose lateral is within CAR_W of `lat`. traffic: { { s, lateral, speed } }.
local function blocker(st, p, lat, traffic, L)
	local v = st.speed or 0
	local look = GpDriver.CAR_L + v * 0.9
	local best, bestDs
	for _, o in ipairs(traffic or {}) do
		local ds = (o.s - p.s) % L
		if ds > 0.5 and ds < look and math.abs(o.lateral - lat) < GpDriver.CAR_W then
			if not bestDs or ds < bestDs then best, bestDs = o, ds end
		end
	end
	return best, bestDs
end

--- The input for this frame on the circuit (offsets x, z; the nose yaw).
-- traffic (optional): the other cars, { { s, lateral, speed } }; a car
-- ahead in the way is passed on the side with room, or followed at its
-- speed while there is none. dt (optional) moves the line smoothly.
function GpDriver.input(d, st, x, z, yaw, traffic, dt)
	local geo = GpLayout.geometry()
	local L = geo.length
	local p = geo:project(x, z)
	d.seg = p.seg
	d.line = d.line or 0
	local v = st.speed or 0
	-- worn tyres: corners slower (corner speed goes with the square root of the grip)
	local target = d.profile[GpDriver.nodeAt(p.s + v * 0.25)] * math.sqrt(GpCar.tyreGrip(st.tyre or 1))
	-- traffic: pick a line clear of the car ahead, else hold back behind it
	local want = 0
	local o, ds = blocker(st, p, d.line, traffic, L)
	if o then
		local side = o.lateral >= 0 and -1 or 1
		local line = math.clamp(o.lateral + side * GpDriver.CAR_W * 1.2, -GpDriver.LINE_MAX, GpDriver.LINE_MAX)
		if math.abs(line - o.lateral) < GpDriver.CAR_W then
			line = math.clamp(o.lateral - side * GpDriver.CAR_W * 1.2, -GpDriver.LINE_MAX, GpDriver.LINE_MAX)
		end
		if math.abs(line - o.lateral) >= GpDriver.CAR_W and not blocker(st, p, line, traffic, L) then
			want = line
		else
			want = d.line
		end
		-- not beside it yet: no faster than it when close
		if math.abs(p.lateral - o.lateral) < GpDriver.CAR_W and ds < GpDriver.CAR_L + v * 0.45 then
			target = math.min(target, math.max((o.speed or 0) - 1, 0))
		end
		d.holdUntil = (d.clock or 0) + GpDriver.HOLD
	elseif d.line ~= 0 and (d.clock or 0) >= (d.holdUntil or 0) then
		-- back to the centerline once nobody is beside us there
		local besideCentre = false
		for _, c in ipairs(traffic or {}) do
			local dd = (c.s - p.s + L / 2) % L - L / 2
			if math.abs(dd) < GpDriver.CAR_L and math.abs(c.lateral) < GpDriver.CAR_W then besideCentre = true end
		end
		want = besideCentre and d.line or 0
	elseif d.line ~= 0 then
		want = d.line
	end
	-- never across onto a car alongside (in a bend two side by side touched)
	for _, c in ipairs(traffic or {}) do
		local dd = (c.s - p.s + L / 2) % L - L / 2
		if math.abs(dd) < GpDriver.CAR_L * 1.2 then
			if c.lateral >= p.lateral then
				want = math.min(want, c.lateral - GpDriver.CAR_W)
			else
				want = math.max(want, c.lateral + GpDriver.CAR_W)
			end
		end
	end
	want = math.clamp(want, -GpDriver.LINE_MAX - 2, GpDriver.LINE_MAX + 2)
	d.clock = (d.clock or 0) + (dt or 1 / 60)
	local step = GpDriver.LINE_RATE * (dt or 1 / 60)
	d.line += math.clamp(want - d.line, -step, step)
	-- off the centerline the bend is tighter on the inside: slower
	if d.line ~= 0 then
		local R = GpDriver.radii()[GpDriver.nodeAt(p.s + v * 0.5)] or math.huge
		if R < 1e6 then target *= math.sqrt(math.max(R - math.abs(d.line), 1) / R) end
	end
	local ahead = 14 + v * 0.32
	local tx, tz = geo:offsetPoint((p.s + ahead) % L, d.line)
	return GpDriver.toward(d, st, x, z, yaw, tx, tz, target, ahead), p
end

return GpDriver
