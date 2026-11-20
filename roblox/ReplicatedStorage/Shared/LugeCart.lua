-- LugeCart.lua
-- How a car rolls down the Alpine Luge (Constants.LUGE): one pure step for
-- the rider's client (LugeClient), the offline sim and the specs. No
-- Roblox types.
--
--   local spec = LugeCart.spec(RideRating.rate(slots, "FOREST").bars, halfWidth)
--   local st = LugeCart.newState()
--   local out = LugeCart.step(spec, st, { throttle, brake, steer },
--       { dt, yaw, at = LugeLayout.at(...), kick })
--
-- The model
--   * No engine: gravity pulls along the trough (GRAVITY × its grade, along
--     the way the cart travels), rolling resistance and air hold it back,
--     the governor stops it at TOP. The gas only paddles at a crawl (PUSH:
--     the start, the run-out), the brake slows it.
--   * Steering asks for a yaw rate; the path bends only as far as the grip
--     lets it (a little less for a car with a poor handling bar). Asked for
--     more, the nose turns past the path: a slide that scrubs speed.
--   * The lips: at the trough's edge, moving outward, the cart bounces back
--     (most of its sideways speed gone, a little speed lost, the nose swung
--     back along the trough: event "scrape"). Into a lip faster than HOP
--     sideways (the high lip on the outside of a tight bend takes more),
--     it goes over onto the grass ("hop"): slow, steer back in ("back"), or
--     the marshals put it back after OFF.RESET s / OFF.FAR studs out
--     (out.wantReset). A cart never rolls over.
--   * A touch from another cart (ctx.kick, Shared/CarBump from the server)
--     changes speed and path; the nose stays.

local Constants = require(script.Parent.Constants)
local CarBump = require(script.Parent.CarBump)

local LugeCart = {}

local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
LugeCart.wrap = wrap

--- A cart's numbers: grip from the handling bar (0..1), half its width.
function LugeCart.spec(bars, half)
	local L = Constants.LUGE
	local h = (bars and bars.handling) or 0.5
	return { grip = L.GRIP[1] + (L.GRIP[2] - L.GRIP[1]) * math.clamp(h, 0, 1), half = math.clamp(half or 1.5, 0.8, 2.6) }
end

function LugeCart.newState()
	return { speed = 0, travelYaw = nil, off = false, offT = 0, align = 0 }
end

--- How far from the centerline a cart's side reaches the lip.
function LugeCart.edge(spec)
	return Constants.LUGE.WIDTH / 2 - spec.half
end

--- One step. ctx.at: LugeLayout.at() for the cart (s, lateral, yaw, grade,
-- curve). Returns { speed, yawRate, travelYaw, slide, lean, latV, event =
-- nil | "scrape" | "hop" | "back", power (sideways speed of a scrape or
-- hop), wantReset }.
function LugeCart.step(spec, st, input, ctx)
	local L = Constants.LUGE
	local dt = ctx.dt or 1 / 60
	local at = ctx.at
	local yaw = ctx.yaw or at.yaw
	local v = st.speed or 0
	local tyaw = st.travelYaw or yaw
	if ctx.kick then
		v, tyaw = CarBump.apply(v, tyaw, ctx.kick.x or 0, ctx.kick.z or 0)
	end
	-- the trough's frame
	local fx, fz = -math.sin(at.yaw), -math.cos(at.yaw)
	local rx, rz = -fz, fx
	local dx, dz = -math.sin(tyaw), -math.cos(tyaw)
	local along = dx * fx + dz * fz

	-- speed
	local a = L.GRAVITY * -(at.grade or 0) * along * (st.off and L.OFF.GRAVITY or 1)
	a -= L.ROLL + L.DRAG * v * v
	if st.off and v > L.OFF.TOP then a -= L.OFF.DRAG end
	local throttle = math.clamp(input.throttle or 0, 0, 1)
	if throttle > 0 and v < L.PUSH.UNTIL then a += L.PUSH.ACCEL * throttle end
	local brake = math.clamp(input.brake or 0, 0, 1)
	a -= L.BRAKE * brake
	if not st.off and v > L.TOP then a = math.min(a, -L.BRAKE * 0.5) end
	v = math.max(0, v + a * dt)

	-- steering and grip
	local grip = spec.grip * (st.off and L.OFF.GRIP or 1)
	local speedAbs = math.max(v, 1)
	local pathMax = grip / speedAbs
	local steer = math.clamp(input.steer or 0, -1, 1)
	local ask = steer * math.min(L.TURN, L.OVERDRIVE * grip / speedAbs)
	local noseMax = math.min(L.TURN, L.OVERSTEER * pathMax)
	local yawRate = math.clamp(ask, -noseMax, noseMax)
	-- the trough is a U: toward a side its wall turns the cart back in
	-- (nothing in the middle; most at the lip). Without it a person on a
	-- keyboard, a moment late, weaved from lip to lip and over (luge_sim)
	if not st.off then
		local lat0 = at.lateral or 0
		local w = math.clamp(math.abs(lat0) / math.max(LugeCart.edge(spec), 0.5), 0, 1) ^ 2
		if w > 0 then
			local rx0, rz0 = math.cos(at.yaw), -math.sin(at.yaw)   -- right of the trough
			local latV0 = v * (-math.sin(tyaw) * rx0 - math.cos(tyaw) * rz0)
			local wantLat = -lat0 * L.TROUGH.CENTER
			-- (+ yaw = left: turning left takes sideways speed off to the right)
			yawRate += math.clamp((latV0 - wantLat) / math.max(v, 4), -1, 1) * L.TROUGH.GUIDE * w
		end
	end
	if (st.align or 0) > 0 then
		-- just off a lip: the nose swings back along the trough
		st.align -= dt
		yawRate += math.clamp(wrap(at.yaw - yaw) * L.ALIGN, -L.ALIGN, L.ALIGN)
	end
	local open = wrap(yaw - tyaw)
	local bend = math.clamp(yawRate + open * L.TRAVEL_FOLLOW, -pathMax, pathMax)
	local want = wrap(yaw + yawRate * dt - tyaw)
	if math.abs(bend * dt) > math.abs(want) and want * bend > 0 then bend = want / dt end
	tyaw = wrap(tyaw + bend * dt)
	local slide = math.abs(wrap(yaw + yawRate * dt - tyaw))
	v = math.max(0, v - L.SLIDE_SCRUB * math.min(slide, 1) * dt)

	-- the lips
	dx, dz = -math.sin(tyaw), -math.cos(tyaw)
	local latV = v * (dx * rx + dz * rz)
	local edge = LugeCart.edge(spec)
	local lat = at.lateral or 0
	local event, power, wantReset
	if not st.off then
		if math.abs(lat) > edge and latV * lat > 0 then
			power = math.abs(latV)
			local hop = require(script.Parent.LugeLayout).highLip(lat, at.curve or 0) and L.HOP.HIGH or L.HOP.LOW
			if power > hop then
				st.off, st.offT = true, 0
				event = "hop"
			else
				-- bounce: most of the sideways speed gone, back the other way
				local vx, vz = dx * v - (1 + L.BOUNCE) * latV * rx, dz * v - (1 + L.BOUNCE) * latV * rz
				v = math.sqrt(vx * vx + vz * vz) * (1 - L.SCRAPE)
				if v > 0.5 then tyaw = math.atan2(-vx, -vz) end
				st.align = L.ALIGN_SECONDS
				event = "scrape"
			end
		end
	else
		st.offT = (st.offT or 0) + dt
		if math.abs(lat) < edge - 0.3 then
			st.off = false
			event = "back"
		elseif st.offT > L.OFF.RESET or math.abs(lat) > edge + L.OFF.FAR then
			wantReset = true
		end
	end

	st.speed = v
	st.travelYaw = tyaw
	latV = v * (-math.sin(tyaw) * rx - math.cos(tyaw) * rz)   -- after the lips
	-- leaning into the bend (the way the path turns), more near the grip
	local lean = -math.clamp(bend * v / math.max(grip, 1), -1, 1) * L.LEAN
	return { speed = v, yawRate = yawRate, travelYaw = tyaw, slide = slide, lean = lean, latV = latV,
		event = event, power = power, wantReset = wantReset }
end

return LugeCart
