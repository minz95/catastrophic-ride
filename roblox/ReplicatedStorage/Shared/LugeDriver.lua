-- LugeDriver.lua
-- The Alpine Luge's simulated rider: the offline sim (tools/luge_sim.luau,
-- spec luge) and the Studio harness's autopilot (LugeClient, attribute
-- LugeAuto) ride with it, through the same LugeCart step as players. Pure.
--
--   local d = LugeDriver.new(spec, skill)       -- skill: share of the grip used
--   local input = LugeDriver.input(d, st, x, z, yaw, at, traffic)
--
-- It follows the centerline (pure pursuit) under a speed plan: each node's
-- bend speed at `skill` of the grip, braked back from the next slower one.
-- Above 1 it asks for more than the grip: it scrapes the lips and goes over
-- them (a careless rider). It keeps its distance behind a slower cart
-- (traffic: { { s, lateral, speed } }) unless `blind`.

local Constants = require(script.Parent.Constants)
local LugeLayout = require(script.Parent.LugeLayout)

local LugeDriver = {}

LugeDriver.BRAKE_USE = 0.6

local _S
local function nodeS()
	if _S then return _S end
	local N = LugeLayout.nodes()
	local out, acc = { 0 }, 0
	for i = 2, #N do
		acc += math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2)
		out[i] = acc
	end
	_S = out
	return out
end

local function nodeAt(s)
	local S = nodeS()
	local lo, hi = 1, #S
	s = math.clamp(s, 0, S[#S])
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if S[mid] <= s then lo = mid else hi = mid - 1 end
	end
	return lo
end
LugeDriver.nodeAt = nodeAt

--- The speed plan (studs/s per node) of a cart with `spec` at `skill`.
function LugeDriver.profile(spec, skill)
	local L = Constants.LUGE
	local C = LugeLayout.curves()
	local S = nodeS()
	local n = #C
	local v = {}
	for i = 1, n do
		local k = math.abs(C[i])
		v[i] = k > 1e-4 and math.min(L.TOP, math.sqrt(spec.grip * skill / k)) or L.TOP
	end
	-- the bends' speed over a few nodes (the curvature is noisy)
	local raw = table.clone(v)
	for i = 1, n do
		local m = raw[i]
		for j = math.max(1, i - 3), math.min(n, i + 3) do m = math.min(m, raw[j]) end
		v[i] = m
	end
	local dec = L.BRAKE * LugeDriver.BRAKE_USE
	for i = n - 1, 1, -1 do
		local gap = S[i + 1] - S[i]
		v[i] = math.min(v[i], math.sqrt(v[i + 1] * v[i + 1] + 2 * dec * gap))
	end
	return v
end

function LugeDriver.new(spec, skill, blind)
	return { spec = spec, skill = skill or 0.9, profile = LugeDriver.profile(spec, skill or 0.9), blind = blind }
end

--- The input for this frame: cart at offset (x, z), nose `yaw`, `at` =
-- LugeLayout.at() for it.
function LugeDriver.input(d, st, x, z, yaw, at, traffic)
	local geo = LugeLayout.geometry()
	local v = st.speed or 0
	local target = d.profile[nodeAt(at.s + v * 0.35)]
	-- a slower cart ahead in the way: stay behind it
	if not d.blind then
		for _, o in ipairs(traffic or {}) do
			local ds = o.s - at.s
			if ds > 0 and ds < 12 + v * 0.8 and math.abs(o.lateral - at.lateral) < 5 then
				target = math.min(target, math.max((o.speed or 0) - 1, 0))
			end
		end
	end
	-- back in the trough from the grass: head for it, slowly
	local ahead = 6 + v * 0.35
	local s = math.min(at.s + ahead, geo.length)
	local tx, tz = geo:pointAt(s)
	if st.off then
		target = math.min(target, 8)
	end
	local want = math.atan2(-(tx - x), -(tz - z))
	local alpha = LugeLayout.wrapYaw(want - yaw)
	local L = Constants.LUGE
	local rate = 2 * math.max(v, 1) * math.sin(alpha) / math.max(ahead, 1)
	local maxYaw = math.min(L.TURN, L.OVERDRIVE * d.spec.grip / math.max(v, 1))
	local steer = math.clamp(rate / math.max(maxYaw, 1e-3), -1, 1)
	local throttle, brake = 0, 0
	if v < target - 1 then
		throttle = 1
	elseif v > target + 1 then
		brake = math.clamp((v - target) / 5, 0.15, 1)
	end
	return { throttle = throttle, brake = brake, steer = steer }
end

return LugeDriver
