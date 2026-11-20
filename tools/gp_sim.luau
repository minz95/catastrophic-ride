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

-- ── Traffic: the five race bots on the circuit together ──────────────────────
-- (Studio: bots without traffic sense drove into each other and were put
-- back in pairs). Contacts = two cars closer than a car's length and width.
local function traffic(seconds, shape, reverse, gap)
	local geo = GpLayout.geometry()
	local L = geo.length
	local BOTS = {
		{ "Turbo Tom", { BODY = "Toilet", ENGINE = "Rocket" } },
		{ "Vroom Vera", { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" } },
		{ "Lap Lenny", { BODY = "Bathtub", ENGINE = "Fan" } },
		{ "Nitro Nell", { BODY = "Red Sofa", ENGINE = "Hair Dryer" } },
		{ "Skid Sid", { BODY = "Shopping Cart" } },
	}
	local S = Constants.GP.BOT_SKILL
	local cars = {}
	for i, b in ipairs(BOTS) do
		local spec = GpCar.spec(RideRating.rate(b[2], "FOREST").bars, shape)
		local x, z, dx, dz = geo:pointAt(1)
		table.insert(cars, { name = b[1], spec = spec, st = GpCar.newState(), d = GpDriver.new(spec, S[1] + (S[2] - S[1]) * (i - 1) / 4),
			x = x, z = z, yaw = math.atan2(-dx, -dz), startAt = (reverse and (#BOTS - i) or (i - 1)) * (gap or 4), s = 0, lateral = 0, dist = 0, flips = 0, off = 0, lift = 0 })
	end
	local dt = 1 / 60
	local contacts, passes, touching = 0, 0, {}
	local order = {}
	for t = 0, seconds, dt do
		local list = {}
		for _, c in ipairs(cars) do
			if t >= c.startAt then table.insert(list, { car = c, s = c.s, lateral = c.lateral, speed = c.st.speed }) end
		end
		for _, c in ipairs(cars) do
			if t >= c.startAt then
				local others = {}
				for _, o in ipairs(list) do if o.car ~= c then table.insert(others, o) end end
				local input, p = GpDriver.input(c.d, c.st, c.x, c.z, c.yaw, others, dt)
				local a = math.abs(p.lateral)
				local surface = a <= 14 and "road" or (a <= 17 and "kerb" or "grass")
				if a > Constants.GP.TRACK_LIMIT then c.off += dt end
				local r = GpCar.step(c.spec, c.st, input, { dt = dt, yaw = c.yaw, surface = surface })
				if r.flip then c.flips += 1 c.st.flipped = false c.st.over = 0 end
				if r.lift then c.lift += dt end
				c.yaw = GpCar.wrap(c.yaw + r.yawRate * dt)
				c.x += -math.sin(r.travelYaw) * r.speed * dt
				c.z += -math.cos(r.travelYaw) * r.speed * dt
				local ds = (p.s - c.s + L / 2) % L - L / 2
				c.dist += ds
				c.s, c.lateral = p.s, p.lateral
			end
		end
		-- contacts and passes
		for i = 1, #cars do
			for j = i + 1, #cars do
				local a, b = cars[i], cars[j]
				if t >= a.startAt and t >= b.startAt then
					local key = i .. "-" .. j
					local close = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) < 6
					if close and not touching[key] then
						contacts += 1
						if process.env.GP_DEBUG then
							print(string.format("  contact t%.1f %s(s%.0f lat%.1f line%.1f v%.0f) %s(s%.0f lat%.1f line%.1f v%.0f)", t, a.name, a.s, a.lateral, a.d.line, a.st.speed, b.name, b.s, b.lateral, b.d.line, b.st.speed))
						end
					end
					touching[key] = close
					local ahead = a.dist > b.dist
					if order[key] ~= nil and order[key] ~= ahead then passes += 1 end
					order[key] = ahead
				end
			end
		end
	end
	print(string.format("traffic %ds (shape %.1f, %s, %ss apart): contacts %d, passes %d", seconds, shape, reverse and "slowest first" or "fastest first", tostring(gap or 4), contacts, passes))
	for _, c in ipairs(cars) do
		print(string.format("  %-11s laps %.1f flips %d off %.1fs lift %.1fs", c.name, c.dist / L, c.flips, c.off, c.lift))
	end
	return contacts, passes, cars
end
traffic(300, 0.8)
traffic(300, 0.8, true, 1.5)
traffic(300, 1.2, true, 1.5)
