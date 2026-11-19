--!nocheck
-- tools/gp_sim.luau — laps of the Junk GP with the simulated driver
-- (Shared/GpDriver through Shared/GpCar): lap times, tyre wear, the most
-- load and flips for the weakest, a middle and the best build, tall and low.
--   lune run tools/gp_sim.luau [laps]
local process = require("@lune/process")
local Loader = require("../tests/lib/loader")
local env = Loader.boot()
local GpCar = env.requirePath("ReplicatedStorage.Shared.GpCar")
local GpDriver = env.requirePath("ReplicatedStorage.Shared.GpDriver")
local GpLayout = env.requirePath("ReplicatedStorage.Shared.GpLayout")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local RideRating = env.requirePath("ReplicatedStorage.Shared.RideRating")

local LAPS = tonumber(process.args[1] or "") or 3

local function surfaceAt(lat, seg)
	local a = math.abs(lat)
	local half = GpLayout.WIDTH / 2
	if a <= half then return "road" end
	if a <= half + GpLayout.KERB then return "kerb" end
	return "grass"
end

local function run(name, spec, skill)
	local geo = GpLayout.geometry()
	local x, z = geo:pointAt(1)
	local _, _, dx, dz = geo:pointAt(1)
	local yaw = math.atan2(-dx, -dz)
	local st = GpCar.newState()
	st.speed = spec.top * 0.6
	local d = GpDriver.new(spec, skill)
	local dt = 1 / 60
	local t, lap, lastS, lapT = 0, 0, 0, 0
	local maxLoad, flips, offs, lifts = 0, 0, 0, 0
	local tyre0 = st.tyre
	local out = {}
	while lap < LAPS and t < 600 do
		local input, p = GpDriver.input(d, st, x, z, yaw)
		local surface = surfaceAt(p.lateral, p.seg)
		if surface == "grass" then offs += dt end
		local r = GpCar.step(spec, st, input, { dt = dt, yaw = yaw, surface = surface })
		maxLoad = math.max(maxLoad, r.load)
		if r.lift then lifts += dt end
		if r.flip then flips += 1 st.flipped = false st.over = 0 end
		yaw = GpCar.wrap(yaw + r.yawRate * dt)
		x += -math.sin(r.travelYaw) * r.speed * dt
		z += -math.cos(r.travelYaw) * r.speed * dt
		t += dt
		if lastS > geo.length * 0.9 and p.s < geo.length * 0.1 then
			lap += 1
			table.insert(out, string.format("%.2fs (tyre %.0f%%)", t - lapT, st.tyre * 100))
			lapT = t
		end
		lastS = p.s
	end
	print(string.format("%-26s top %5.1f acc %4.1f grip %4.1f stab %.2f | %s | load max %.2f lift %.1fs flips %d off %.1fs",
		name, spec.top, spec.accel, spec.grip, spec.stability, table.concat(out, ", "), maxLoad, lifts, flips, offs))
end

print(string.format("lap %.0f studs, %d laps", GpLayout.lapLength(), LAPS))
local builds = {
	{ "Shopping Cart (new car)", { BODY = "Shopping Cart" } },
	{ "Toilet (new car)", { BODY = "Toilet" } },
	{ "Rubber Duck (new car)", { BODY = "Rubber Duck" } },
	{ "Piano+Rocket+Balloons", { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" } },
	{ "Toilet+Rocket", { BODY = "Toilet", ENGINE = "Rocket" } },
}
for _, b in ipairs(builds) do
	local r = RideRating.rate(b[2], "FOREST")
	for _, shape in ipairs({ 0.6, 1.4 }) do
		run(string.format("%s %s", b[1], shape < 1 and "tall" or "low"), GpCar.spec(r.bars, shape), 0.95)
	end
end
run("worst bars", GpCar.spec({ speed = 0, accel = 0, handling = 0 }, 1), 0.95)
run("best bars", GpCar.spec({ speed = 1, accel = 1, handling = 1 }, 1), 0.95)
