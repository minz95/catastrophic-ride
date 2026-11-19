-- GpCar.lua
-- How a car drives at the Junk Grand Prix (Constants.GP): one pure step for
-- players (GpClient), race bots (GpBots) and the offline specs. No Roblox
-- types.
--
--   local spec = GpCar.spec(RideRating.rate(slots, "FOREST").bars, width / height)
--   local st = GpCar.newState()
--   local out = GpCar.step(spec, st, { throttle, brake, steer }, { dt, yaw, surface, actual, pit })
--
-- The model
--   * Speed ramps up with spec.accel × (1 - (v / top)²), brakes at BRAKE,
--     coasts with DRAG. The car's real speed along its path (ctx.actual)
--     holds the command back: a car on a wall does not store speed, and a
--     sudden loss of CRASH_DROP or more is a crash that throws it over.
--   * Steering asks for a yaw rate; the path can bend only as far as the
--     grip allows (spec.grip × tyres × surface). Ask for more and the nose
--     turns past the path (up to OVERSTEER × the grip): a slide, which
--     scrubs speed and wears the tyres.
--   * Load = sideways acceleration over the rollover limit (grip × the car's
--     STABILITY × surface roll; kerbs lower it). Over LIFT_AT a wheel lifts
--     (out.lift, the body leans far over); over 1 for FLIP_HOLD s the car
--     goes over (out.flip, once). Tall narrow cars have the lowest limit.
--   * Tyres wear with speed, load and sliding; worn tyres grip less
--     (down to TYRE.MIN_GRIP). A pit stop sets st.tyre back to 1.

local Constants = require(script.Parent.Constants)

local GpCar = {}

local function lerp(r, f) return r[1] + (r[2] - r[1]) * math.clamp(f, 0, 1) end

local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
GpCar.wrap = wrap

--- A car's numbers from its RideRating bars (0..1: speed, accel, handling)
-- and its shape (visible width over height). Every number is in the spec.
function GpCar.spec(bars, shape)
	local G = Constants.GP
	bars = bars or {}
	local s = math.clamp(((shape or 1) - G.SHAPE[1]) / (G.SHAPE[2] - G.SHAPE[1]), 0, 1)
	return {
		top = lerp(G.TOP, bars.speed or 0.5),
		accel = lerp(G.ACCEL, bars.accel or 0.5),
		grip = lerp(G.GRIP, bars.handling or 0.5),
		brake = G.BRAKE,
		turn = G.TURN,
		stability = lerp(G.STABILITY, s),
	}
end

function GpCar.newState()
	return { speed = 0, travelYaw = nil, tyre = 1, over = 0, flipped = false, lastActual = nil }
end

--- Tyre grip share for wear `t` (1 new … 0 gone).
function GpCar.tyreGrip(t)
	local T = Constants.GP.TYRE
	return T.MIN_GRIP + (1 - T.MIN_GRIP) * math.clamp(t, 0, 1) ^ 0.8
end

--- One step. input: { throttle 0..1, brake 0..1, steer -1..1 (+ = left) }.
-- ctx: { dt, yaw (the nose; LookVector = (-sin, 0, -cos)), surface (a
--   Constants.GP.SURFACE key), actual (real speed along the path; optional),
--   pit (true in the pit lane: the speed limiter) }.
-- Returns { speed, yawRate, travelYaw, slide, load, lift, flip, lean,
--   grip, gear, rpm, crash }.
function GpCar.step(spec, st, input, ctx)
	local G = Constants.GP
	local dt = ctx.dt or 1 / 60
	local surf = G.SURFACE[ctx.surface or "road"] or G.SURFACE.road
	local v = st.speed or 0

	-- the real speed holds the command back; a big sudden loss is a crash
	local crash = false
	if ctx.actual then
		if st.lastActual and st.lastActual - ctx.actual >= G.CRASH_DROP and v > G.CRASH_DROP then
			crash = true
		end
		st.lastActual = ctx.actual
		v = math.clamp(v, ctx.actual - 8, ctx.actual + 8)
	end

	-- speed
	local top = spec.top * surf.top
	if ctx.pit then top = math.min(top, G.PIT_LIMIT) end
	local throttle = math.clamp(input.throttle or 0, 0, 1)
	local brake = math.clamp(input.brake or 0, 0, 1)
	if brake > 0 then
		v = math.max(0, v - spec.brake * brake * math.max(surf.grip, 0.5) * dt)
	elseif throttle > 0 and v < top then
		local a = spec.accel * (1 - (v / spec.top) ^ 2) + 4
		v = math.min(top, v + a * throttle * dt)
	else
		v = math.max(0, v - (G.DRAG * spec.top) * dt)
	end
	if v > top then v = math.max(top, v - (G.BRAKE * 0.6) * dt) end   -- off the road, into the limiter
	-- grass and gravel drag, never below a crawl (a car must get out again)
	if v > Constants.GP.CRAWL then v = math.max(Constants.GP.CRAWL, v - surf.drag * dt) end

	-- steering and grip
	local grip = spec.grip * GpCar.tyreGrip(st.tyre) * surf.grip
	local steer = math.clamp(input.steer or 0, -1, 1)
	local speedAbs = math.max(v, 1)
	local ask = steer * math.min(spec.turn, G.OVERDRIVE * grip / speedAbs)
	local pathMax = grip / speedAbs                  -- how fast the path can bend
	local yaw = ctx.yaw or 0
	local tyaw = st.travelYaw or yaw
	-- the nose turns as asked, but never further than OVERSTEER past the grip
	local noseMax = math.min(spec.turn, G.OVERSTEER * pathMax)
	local yawRate = math.clamp(ask, -noseMax, noseMax)
	-- the path turns with the nose (and closes an open slide), no faster
	-- than the grip lets it bend
	local open = wrap(yaw - tyaw)
	local bend = math.clamp(yawRate + open * G.TRAVEL_FOLLOW, -pathMax, pathMax)
	local want = wrap(yaw + yawRate * dt - tyaw)
	if math.abs(bend * dt) > math.abs(want) and want * bend > 0 then bend = want / dt end
	tyaw = wrap(tyaw + bend * dt)
	st.travelYaw = tyaw
	local slide = math.abs(wrap(yaw + yawRate * dt - tyaw))
	v = math.max(0, v - G.SLIDE_SCRUB * math.min(slide, 1) * dt)

	-- load: sideways acceleration over the rollover limit
	local lat = math.abs(bend) * v
	local rollLimit = spec.grip * spec.stability * surf.roll
	local load = lat / math.max(rollLimit, 1)
	local lift = load >= G.LIFT_AT
	local flip = false
	if not st.flipped then
		if load > 1 then
			st.over = (st.over or 0) + dt
		else
			st.over = math.max(0, (st.over or 0) - dt * 2)
		end
		if st.over >= G.FLIP_HOLD or crash then
			flip = true
			st.flipped = true
		end
	end
	-- the body leans out of the bend; far over with a wheel up
	local side = bend >= 0 and 1 or -1
	local lean = math.min(load / G.LIFT_AT, 1) * G.LEAN
	if lift then
		lean = G.LEAN + (G.LIFT_LEAN - G.LEAN) * math.clamp((load - G.LIFT_AT) / (1 - G.LIFT_AT), 0, 1)
	end
	lean *= side

	-- tyres
	local T = G.TYRE
	st.tyre = math.max(0, (st.tyre or 1) - dt * (T.BASE * v / spec.top + T.LOAD * (lat / spec.grip) ^ 2 + T.SLIDE * slide))

	st.speed = v
	local gear, rpm = GpCar.gear(spec, v)
	return {
		speed = v, yawRate = yawRate, travelYaw = tyaw, slide = slide, load = load, lift = lift,
		flip = flip, crash = crash, lean = lean, grip = grip, gear = gear, rpm = rpm,
	}
end

--- Gear (1 … GEARS) and rpm share (0..1) at speed v: each gear covers an
-- equal slice of the top speed.
function GpCar.gear(spec, v)
	local n = Constants.GP.GEARS
	local f = math.clamp(v / spec.top, 0, 0.9999) * n
	local gear = math.floor(f) + 1
	local rpm = 0.35 + 0.65 * (f - math.floor(f))
	if v < 1 then gear, rpm = 1, 0.2 end
	return gear, rpm
end

--- The fastest a car takes a bend of radius r (studs) with a share `margin`
-- of its grip and staying under its rollover limit.
function GpCar.cornerSpeed(spec, r, margin, tyre)
	local grip = spec.grip * GpCar.tyreGrip(tyre or 1) * (margin or 1)
	local roll = spec.grip * spec.stability * Constants.GP.LIFT_AT * (margin or 1)
	return math.min(spec.top, math.sqrt(math.min(grip, roll) * math.abs(r)))
end

return GpCar
