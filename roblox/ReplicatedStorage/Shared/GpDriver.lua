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

local function heading(a, b)
	return math.atan2(-(b[1] - a[1]), -(b[2] - a[2]))   -- yaw facing from a to b
end

--- Bend radius at every node (from the heading change over ±SPAN nodes).
local _radii
function GpDriver.radii()
	if _radii then return _radii end
	local N = GpLayout.nodes()
	local n = #N - 1
	local out = {}
	for i = 1, n do
		local a = N[(i - 1 - GpDriver.SPAN) % n + 1]
		local b = N[(i - 1) % n + 1]
		local c = N[(i - 1 + GpDriver.SPAN) % n + 1]
		local h1, h2 = heading(a, b), heading(b, c)
		local d = math.abs(GpCar.wrap(h2 - h1))
		local len = GpDriver.SPAN * GpLayout.STEP
		out[i] = d > 1e-4 and len / d or math.huge
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
	for _ = 1, 2 do
		for i = n, 1, -1 do
			local nxt = v[i % n + 1]
			v[i] = math.min(v[i], math.sqrt(nxt * nxt + 2 * dec * GpLayout.STEP))
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

--- The input for this frame on the circuit (offsets x, z; the nose yaw).
function GpDriver.input(d, st, x, z, yaw)
	local geo = GpLayout.geometry()
	local p = geo:project(x, z)
	d.seg = p.seg
	local v = st.speed or 0
	local ahead = 14 + v * 0.32
	local s = (p.s + ahead) % geo.length
	local tx, tz = geo:pointAt(s)
	-- the speed wanted a little ahead (the car needs time to react)
	local n = #d.profile
	local i = math.floor(((p.s + v * 0.25) % geo.length) / geo.length * n) + 1
	local target = d.profile[math.clamp(i, 1, n)]
	return GpDriver.toward(d, st, x, z, yaw, tx, tz, target, ahead), p
end

return GpDriver
