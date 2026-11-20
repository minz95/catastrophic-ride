--!nocheck
-- tools/luge_sim.luau — rides down the Alpine Luge with the simulated rider
-- (Shared/LugeDriver through Shared/LugeCart): the layout's numbers, then
-- run times, top speed, scrapes, hops over the lip and resets for careful
-- to careless riders, narrow and wide carts; two friends one behind the
-- other (blind: they bump, the server's CarBump between them).
--   lune run tools/luge_sim.luau
local Loader = require("../tests/lib/loader")
local env = Loader.boot()
local LugeCart = env.requirePath("ReplicatedStorage.Shared.LugeCart")
local LugeDriver = env.requirePath("ReplicatedStorage.Shared.LugeDriver")
local LugeLayout = env.requirePath("ReplicatedStorage.Shared.LugeLayout")
local CarBump = env.requirePath("ReplicatedStorage.Shared.CarBump")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

local L = Constants.LUGE
local geo = LugeLayout.geometry()
local N = LugeLayout.nodes()

-- ── the layout ──────────────────────────────────────────────────────────────
local maxGrade, trestle, drop = 0, 0, N[1][3] - N[#N][3]
for i = 2, #N do
	local d = math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2)
	maxGrade = math.max(maxGrade, (N[i - 1][3] - N[i][3]) / d)
	trestle = math.max(trestle, N[i][3] - LugeLayout.ROAD - LugeLayout.ground(N[i][2]))
end
-- the closest two stretches come (not neighbours along the trough)
local S, acc = { 0 }, 0
for i = 2, #N do acc += math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2) S[i] = acc end
local closest, where = math.huge, nil
for i = 1, #N, 2 do
	for j = i + 1, #N, 2 do
		if S[j] - S[i] > 60 then
			local d = math.sqrt((N[i][1] - N[j][1]) ^ 2 + (N[i][2] - N[j][2]) ^ 2)
			if d < closest then closest, where = d, { N[i][1], N[i][2] } end
		end
	end
end
print(string.format("trough %.0f studs, %d nodes, drop %.1f, steepest %.1f%%, highest trestle %.1f, closest stretches %.1f apart at (%.0f, %.0f)",
	geo.length, #N, drop, maxGrade * 100, trestle, closest, where[1], where[2]))

-- ── rides ───────────────────────────────────────────────────────────────────
local function newCart(spec, skill, startS, blind, human)
	local x, z, dx, dz = geo:pointAt(startS or 2)
	return { spec = spec, st = LugeCart.newState(), d = LugeDriver.new(spec, skill, blind), x = x, z = z,
		yaw = math.atan2(-dx, -dz), hint = nil, at = nil, t = 0, maxV = 0, scrapes = 0, hops = 0, resets = 0,
		offT = 0, done = nil, human = human, queue = {}, steer = 0 }
end

local function stepCart(c, dt, traffic, kick)
	local at = LugeLayout.at(c.x, c.z, nil, c.hint)
	c.hint = at.seg
	c.at = at
	local input = LugeDriver.input(c.d, c.st, c.x, c.z, c.yaw, at, traffic)
	if c.human then
		-- like a person on a keyboard: sees it REACTION s late, presses A / D
		-- fully or not at all (eased in like LugeClient's keys)
		table.insert(c.queue, input)
		local late = c.queue[1]
		if #c.queue > math.floor(c.human / dt) then table.remove(c.queue, 1) end
		local want = (late.steer > 0.3 and 1) or (late.steer < -0.3 and -1) or 0
		local rate = (math.abs(want) > math.abs(c.steer) and 5 or 9) * dt
		c.steer += math.clamp(want - c.steer, -rate, rate)
		input = { throttle = late.throttle > 0.5 and 1 or 0, brake = late.brake > 0.3 and 1 or 0, steer = c.steer }
	end
	local out = LugeCart.step(c.spec, c.st, input, { dt = dt, yaw = c.yaw, at = at, kick = kick })
	if out.event == "scrape" then c.scrapes += 1 end
	if out.event == "hop" then c.hops += 1 end
	if c.st.off then c.offT += dt end
	if out.wantReset then
		c.resets += 1
		local s = math.max(2, at.s - 10)
		local x, z, dx, dz = geo:pointAt(s)
		c.x, c.z, c.yaw = x, z, math.atan2(-dx, -dz)
		c.st = LugeCart.newState()
		c.hint = nil
		return
	end
	c.yaw = LugeCart.wrap(c.yaw + out.yawRate * dt)
	c.x += -math.sin(out.travelYaw) * out.speed * dt
	c.z += -math.cos(out.travelYaw) * out.speed * dt
	c.maxV = math.max(c.maxV, out.speed)
	c.t += dt
	if not c.done and at.s >= LugeLayout.finishS() then c.done = c.t end
end

local function ride(name, spec, skill, human)
	local c = newCart(spec, skill, nil, nil, human)
	local dt = 1 / 60
	while not c.done and c.t < 240 do stepCart(c, dt) end
	print(string.format("%-34s %s  avg %4.1f  top %4.1f  scrapes %2d  hops %d  off %.1fs  resets %d",
		name, c.done and string.format("%5.1fs", c.done) or "  DNF", c.done and LugeLayout.finishS() / c.done or 0, c.maxV,
		c.scrapes, c.hops, c.offT, c.resets))
	return c
end

for _, sk in ipairs({ 0.8, 0.95, 1.1, 1.3, 1.6 }) do
	for _, w in ipairs({ { "narrow", 1.1, 0.3 }, { "wide", 2.4, 0.8 } }) do
		ride(string.format("skill %.2f %s (half %.1f)", sk, w[1], w[2]), LugeCart.spec({ handling = w[3] }, w[2]), sk)
	end
end

for _, sk in ipairs({ 0.9, 1.1, 1.3 }) do
	for _, lag in ipairs({ 0.15, 0.3 }) do
		ride(string.format("keys, %.2fs late, skill %.2f", lag, sk), LugeCart.spec({ handling = 0.5 }, 1.8), sk, lag)
	end
end

-- ── two friends ─────────────────────────────────────────────────────────────
local function friends(skillA, skillB, gap, blind)
	local a = newCart(LugeCart.spec({ handling = 0.5 }, 1.8), skillA, 2, blind)
	local b = newCart(LugeCart.spec({ handling = 0.5 }, 1.8), skillB, 2, blind)
	local dt = 1 / 60
	local t, bumps, maxPower, lastBump = 0, 0, 0, -1
	local kickA, kickB
	while t < 240 and not (a.done and b.done) do
		t += dt
		if not a.done then stepCart(a, dt, { b.at and { s = b.at.s, lateral = b.at.lateral, speed = b.st.speed } or nil }, kickA) end
		kickA = nil
		if t > gap and not b.done then stepCart(b, dt, { a.at and { s = a.at.s, lateral = a.at.lateral, speed = a.st.speed } or nil }, kickB) end
		kickB = nil
		if t > gap and t - lastBump > L.BUMP.GAP then
			local hits = CarBump.find({
				{ id = "a", x = a.x, z = a.z, vx = -math.sin(a.st.travelYaw or 0) * a.st.speed, vz = -math.cos(a.st.travelYaw or 0) * a.st.speed, yaw = a.yaw, length = 7, width = 3.6 },
				{ id = "b", x = b.x, z = b.z, vx = -math.sin(b.st.travelYaw or 0) * b.st.speed, vz = -math.cos(b.st.travelYaw or 0) * b.st.speed, yaw = b.yaw, length = 7, width = 3.6 },
			}, L.BUMP)
			for _, h in ipairs(hits) do
				bumps += 1
				maxPower = math.max(maxPower, h.power)
				kickA, kickB = { x = h.ax, z = h.az }, { x = h.bx, z = h.bz }
				lastBump = t
			end
		end
	end
	print(string.format("friends %.2f ahead, %.2f %.1fs behind%s: bumps %d (hardest %.1f), A %s hops %d resets %d, B %s hops %d resets %d",
		skillA, skillB, gap, blind and " (blind)" or "", bumps, maxPower,
		a.done and string.format("%.1fs", a.done) or "DNF", a.hops, a.resets, b.done and string.format("%.1fs", b.done - gap) or "DNF", b.hops, b.resets))
end
friends(0.8, 1.05, 1.5, false)
friends(0.8, 1.05, 1.5, true)
friends(0.9, 0.9, 0.8, true)

-- ── Many riders (lune run tools/luge_sim.luau many [n]) ───────────────────────
-- random skill, reaction, cart width and grip, alone and in random pairs:
-- anything that does not finish, needs the marshals, or bumps too hard
local process = require("@lune/process")
if process.args[1] == "many" then
	local n = tonumber(process.args[2] or "") or 200
	-- (Lune has no Random: a small seeded generator)
	local seed = 7
	local rnd = { NextNumber = function(_, a, b)
		seed = (seed * 1103515245 + 12345) % 2147483648
		local f = seed / 2147483648
		if a == nil then return f end
		return a + (b - a) * f
	end }
	local times, dnf, resets, hopsT, worst = {}, 0, 0, 0, nil
	for k = 1, n do
		local skill = rnd:NextNumber(0.6, 1.6)
		local late = rnd:NextNumber() < 0.6 and rnd:NextNumber(0.05, 0.35) or nil
		local half, handling = rnd:NextNumber(0.9, 2.6), rnd:NextNumber(0, 1)
		local c = newCart(LugeCart.spec({ handling = handling }, half), skill, nil, nil, late)
		while not c.done and c.t < 240 do stepCart(c, 1 / 60) end
		if not c.done then
			dnf += 1
			print(string.format("  DNF: skill %.2f late %s half %.1f handling %.2f at s %.0f", skill, tostring(late), half, handling, c.at and c.at.s or -1))
		else
			table.insert(times, c.done)
		end
		resets += c.resets
		hopsT += c.hops
		if c.resets > 0 and (not worst or c.resets > worst.resets) then
			worst = { resets = c.resets, skill = skill, late = late, half = half }
		end
	end
	table.sort(times)
	print(string.format("%d riders: %d finished (%.1f / %.1f / %.1f s: fastest, median, slowest), %d DNF, %d hops, %d marshal resets",
		n, #times, times[1] or 0, times[#times // 2 + 1] or 0, times[#times] or 0, dnf, hopsT, resets))
	if worst then print(string.format("  most resets: %d (skill %.2f, late %s, half %.1f)", worst.resets, worst.skill, tostring(worst.late), worst.half)) end
	local hardest, pairsDone = 0, 0
	for k = 1, n // 4 do
		local a = newCart(LugeCart.spec({ handling = rnd:NextNumber() }, rnd:NextNumber(0.9, 2.6)), rnd:NextNumber(0.6, 1.2), 2, true)
		local b = newCart(LugeCart.spec({ handling = rnd:NextNumber() }, rnd:NextNumber(0.9, 2.6)), rnd:NextNumber(0.9, 1.6), 2, true,
			rnd:NextNumber() < 0.5 and rnd:NextNumber(0.05, 0.3) or nil)
		local gap = rnd:NextNumber(0.3, 3)
		local dt, t, last, ka, kb = 1 / 60, 0, -1, nil, nil
		while t < 240 and not (a.done and b.done) do
			t += dt
			if not a.done then stepCart(a, dt, nil, ka) end
			ka = nil
			if t > gap and not b.done then stepCart(b, dt, nil, kb) end
			kb = nil
			if t > gap and t - last > L.BUMP.GAP then
				local function box(c, id)
					local ty = c.st.travelYaw or c.yaw
					return { id = id, x = c.x, z = c.z, vx = -math.sin(ty) * c.st.speed, vz = -math.cos(ty) * c.st.speed, yaw = c.yaw, length = 7, width = c.spec.half * 2 }
				end
				for _, h in ipairs(CarBump.find({ box(a, "a"), box(b, "b") }, L.BUMP)) do
					hardest = math.max(hardest, h.power)
					ka, kb, last = { x = h.ax, z = h.az }, { x = h.bx, z = h.bz }, t
				end
			end
		end
		if a.done and b.done then pairsDone += 1 end
	end
	print(string.format("%d friend pairs (blind, close behind): %d both finished, hardest closing speed %.1f", n // 4, pairsDone, hardest))
end
