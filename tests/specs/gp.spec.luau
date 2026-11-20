--!nocheck
-- Junk Grand Prix (2026-11-19, "a car you bought earns you the right to
-- race: the town's racing experience, F1 thrills, box box, your car's real
-- performance, the feeling of nearly rolling over"): the circuit's layout,
-- how a GP car drives (Shared/GpCar), lap timing (Shared/GpTiming), the
-- simulated driver lapping every bot build, and a session in a server
-- (GpManager): no car no race, the gate, the garage, the lights, laps,
-- the pit stop, back to town with the best lap on the board and saved.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

R.describe("Junk GP: the circuit", function()
	local env = Loader.boot()
	local L = env.requirePath("ReplicatedStorage.Shared.GpLayout")
	local Lobby = env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
	local Driver = env.requirePath("ReplicatedStorage.Shared.GpDriver")
	local N = L.nodes()
	local geo = L.geometry()

	R.it("is one closed lap of 2 800 - 3 600 studs starting on the line, every corner rounded with room for its arc", function()
		R.expect(N[1][1]).toBe(N[#N][1])
		R.expect(N[1][2]).toBe(N[#N][2])
		R.expect(geo.length > 2800 and geo.length < 3600).toBe(true, tostring(geo.length))
		R.expect(math.abs(N[1][1] + 360) < 1 and math.abs(N[1][2] - L.LINE_Z) < L.STEP).toBe(true)
		for i, f in ipairs(L.fillets()) do
			R.expect(f.room >= 0).toBe(true, "corner " .. i .. " overlaps the next")
		end
		-- no bend tighter than the barriers allow on its inside
		local tight = math.huge
		for _, r in ipairs(Driver.radii()) do tight = math.min(tight, r) end
		R.expect(tight > 22).toBe(true, tostring(tight))
	end)

	R.it("never crosses or comes near itself: other stretches stay two barrier widths away", function()
		local n = #N - 1
		local close = {}
		for i = 1, n, 2 do
			for j = i + 2, n, 2 do
				local gap = math.min(j - i, n - (j - i)) * L.STEP
				if gap > 150 then
					local d = math.sqrt((N[i][1] - N[j][1]) ^ 2 + (N[i][2] - N[j][2]) ^ 2)
					if d < 62 then table.insert(close, string.format("%d/%d %.0f", i, j, d)) end
				end
			end
		end
		R.expect(close).toBeEmpty("stretches too close")
	end)

	R.it("the pit lane: every box in it, off the road; garages and the grandstand clear of the track; the grounds clear of town", function()
		for k = 1, L.PIT.boxes do
			local stop, garage = L.box(k)
			R.expect(L.inPit(stop.X, stop.Z)).toBe(true, "box " .. k)
			R.expect(geo:project(stop.X, stop.Z).dist > L.WIDTH / 2 + L.KERB + 2).toBe(true, "box " .. k .. " on the road")
			R.expect(geo:project(garage.X, garage.Z).dist > 30).toBe(true, "garage " .. k)
		end
		-- the pit lane's ends meet the road
		local path = L.pitPath()
		R.expect(geo:project(path[1].X, path[1].Z).dist < L.WIDTH / 2).toBe(true)
		R.expect(geo:project(path[#path].X, path[#path].Z).dist < L.WIDTH / 2).toBe(true)
		-- grandstand: behind the catch fence, east of the barrier, in the walk-in area
		local Gs = L.GRANDSTAND
		R.expect(Gs.x[1] > L.CATCH_FENCE).toBe(true)
		R.expect(geo:project(Gs.x[1], 0).dist >= 30 - 1).toBe(true)
		local S = Lobby.STREET.stand
		R.expect(Gs.x[1] >= S[1] and Gs.x[2] <= S[2] and Gs.z[1] >= S[3] and Gs.z[2] <= S[4]).toBe(true)
		-- people may walk there (the respawn net leaves them), not onto the grass
		local O = Lobby.ORIGIN
		R.expect(Lobby.inTown(O + Vector3.new(-315, 3, 100))).toBe(true)
		R.expect(Lobby.inTown(O + Vector3.new(-360, 3, 100))).toBe(false)
		R.expect(Lobby.inTown(O + Vector3.new(-700, 3, 0))).toBe(false)
		-- the grounds: west of town, far from every race track (|x| < 900)
		R.expect(L.GROUND[2] <= Lobby.STREET.lot[1] + 1).toBe(true)
		R.expect(O.X + L.GROUND[1] > 900).toBe(true)
		-- the gate stands on Auto Street
		R.expect(Lobby.onStreet(O + L.ENTRANCE + Vector3.new(0, 3, 0))).toBe(true)
		R.expect(Lobby.onStreet(O + L.EXIT + Vector3.new(0, 3, 0))).toBe(true)
	end)
end)

R.describe("Junk GP: how a car drives (GpCar)", function()
	local env = Loader.boot()
	local GpCar = env.requirePath("ReplicatedStorage.Shared.GpCar")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local G = Constants.GP
	local mid = GpCar.spec({ speed = 0.5, accel = 0.5, handling = 0.5 }, 1)

	local function run(spec, input, ctx, seconds)
		local st = GpCar.newState()
		local out
		for _ = 1, math.floor(seconds * 60) do
			out = GpCar.step(spec, st, input, ctx or { dt = 1 / 60, yaw = 0 })
		end
		return st, out
	end

	-- a steady bend at speed v: steer so the path bends at the grip limit share `f`
	local function bend(spec, v, f, surface, tyre)
		local st = GpCar.newState()
		st.speed, st.tyre = v, tyre or 1
		local yaw = 0
		local flipped, lifted, maxLoad = false, false, 0
		for _ = 1, 120 do
			local grip = spec.grip * GpCar.tyreGrip(st.tyre) * (G.SURFACE[surface or "road"].grip)
			local steer = math.min(1, f * grip / v / math.min(spec.turn, G.OVERDRIVE * grip / v))
			st.speed = v
			local out = GpCar.step(spec, st, { throttle = 0.5, steer = steer }, { dt = 1 / 60, yaw = yaw, surface = surface })
			yaw += out.yawRate / 60
			flipped = flipped or out.flip
			lifted = lifted or out.lift
			maxLoad = math.max(maxLoad, out.load)
		end
		return flipped, lifted, maxLoad
	end

	R.it("a better build is much quicker: top speed, acceleration and grip spread wide", function()
		local lo = GpCar.spec({ speed = 0, accel = 0, handling = 0 }, 1)
		local hi = GpCar.spec({ speed = 1, accel = 1, handling = 1 }, 1)
		R.expect(hi.top / lo.top > 1.5).toBe(true)
		R.expect(hi.grip / lo.grip > 1.5).toBe(true)
		local stLo = run(lo, { throttle = 1 }, nil, 4)
		local stHi = run(hi, { throttle = 1 }, nil, 4)
		R.expect(stHi.speed > stLo.speed * 1.4).toBe(true)
		-- flat out it settles at its top speed
		local st = run(mid, { throttle = 1 }, nil, 20)
		R.expect(math.abs(st.speed - mid.top) < 1).toBe(true)
	end)

	R.it("the pit lane limiter, grass slows a car (never to a stop), brakes stop it", function()
		local st = run(mid, { throttle = 1 }, { dt = 1 / 60, yaw = 0, pit = true }, 10)
		R.expect(math.abs(st.speed - G.PIT_LIMIT) < 0.5).toBe(true)
		local g = run(mid, { throttle = 1 }, { dt = 1 / 60, yaw = 0, surface = "grass" }, 10)
		R.expect(g.speed < mid.top * 0.6 and g.speed >= G.CRAWL).toBe(true, tostring(g.speed))
		local s2 = GpCar.newState()
		s2.speed = 100
		for _ = 1, 120 do GpCar.step(mid, s2, { brake = 1 }, { dt = 1 / 60, yaw = 0 }) end
		R.expect(s2.speed).toBe(0)
	end)

	R.it("a tall narrow car rolls over held at the grip limit; a low wide one only leans; the warning comes first", function()
		local tall = GpCar.spec({ speed = 0.5, accel = 0.5, handling = 0.5 }, G.SHAPE[1])
		local low = GpCar.spec({ speed = 0.5, accel = 0.5, handling = 0.5 }, G.SHAPE[2])
		local fT, lT = bend(tall, 80, 1)
		local fL, lL, loadL = bend(low, 80, 1)
		R.expect(fT).toBe(true)
		R.expect(lT).toBe(true)
		R.expect(fL).toBe(false)
		R.expect(lL).toBe(false)
		R.expect(loadL < G.LIFT_AT).toBe(true)
		-- backed off a little, the tall car only leans with a wheel up
		local f2, l2 = bend(tall, 80, 0.9)
		R.expect(f2).toBe(false)
		R.expect(l2).toBe(true)
		-- kerbs lower the limit: a middle car (width / height 1.25, an Old TV)
		-- at the limit lifts a wheel on a kerb, not on the road
		local middle = GpCar.spec({ speed = 0.5, accel = 0.5, handling = 0.5 }, 1.25)
		R.expect(select(2, bend(middle, 80, 1, "road"))).toBe(false)
		R.expect(select(2, bend(middle, 80, 1, "kerb"))).toBe(true)
		-- the real cars (Studio gp-drive measured them): only the tallest can go
		-- over on the road, a flat one never lifts even on a kerb
		R.expect((bend(GpCar.spec({ handling = 0.5 }, 0.75), 80, 1))).toBe(true)              -- Toilet
		R.expect((bend(GpCar.spec({ handling = 0.5 }, 1.05), 80, 1))).toBe(false)             -- Rubber Duck, road
		R.expect(select(2, bend(GpCar.spec({ handling = 0.5 }, 1.66), 80, 1, "kerb"))).toBe(false)  -- Red Sofa
	end)

	R.it("asking for more than the grip slides the car and scrubs speed; worn tyres grip less", function()
		local st = GpCar.newState()
		st.speed = 90
		local yaw, slide = 0, 0
		for _ = 1, 60 do
			st.speed = math.max(st.speed, 0)
			local out = GpCar.step(mid, st, { throttle = 1, steer = 1 }, { dt = 1 / 60, yaw = yaw })
			yaw += out.yawRate / 60
			slide = math.max(slide, out.slide)
		end
		R.expect(slide > 0.05).toBe(true, tostring(slide))
		local straight = GpCar.newState()
		straight.speed = 90
		for _ = 1, 60 do GpCar.step(mid, straight, { throttle = 1 }, { dt = 1 / 60, yaw = 0 }) end
		R.expect(st.speed < straight.speed - 2).toBe(true, string.format("%.1f vs %.1f", st.speed, straight.speed))
		R.expect(GpCar.tyreGrip(0.2) < GpCar.tyreGrip(1) * 0.75).toBe(true)
		-- a hard lap wears a fifth to a third of the tyre
		local st2 = GpCar.newState()
		st2.speed = 80
		local y2 = 0
		for k = 1, 60 * 40 do
			local out = GpCar.step(mid, st2, { throttle = 1, steer = (k % 240 < 120) and 0.6 or 0 }, { dt = 1 / 60, yaw = y2 })
			y2 += out.yawRate / 60
		end
		R.expect(st2.tyre < 0.85 and st2.tyre > 0.5).toBe(true, tostring(st2.tyre))
	end)

	R.it("a crash (a big sudden loss of speed) throws the car over", function()
		local st = GpCar.newState()
		st.speed = 100
		GpCar.step(mid, st, { throttle = 1 }, { dt = 1 / 60, yaw = 0, actual = 100 })
		local out = GpCar.step(mid, st, { throttle = 1 }, { dt = 1 / 60, yaw = 0, actual = 20 })
		R.expect(out.flip).toBe(true)
		R.expect(out.crash).toBe(true)
	end)
end)

R.describe("Junk GP: lap timing (GpTiming)", function()
	local env = Loader.boot()
	local T = env.requirePath("ReplicatedStorage.Shared.GpTiming")
	local L = env.requirePath("ReplicatedStorage.Shared.GpLayout")

	-- drives lap shares from `from` to `to` over `secs` seconds starting at t
	local function drive(t, from, to, secs, lateral, state, out)
		local n = 200
		for k = 1, n do
			local share = (from + (to - from) * k / n) % 1
			for _, e in ipairs(T.feed(state, share, lateral or 0, t + secs * k / n, false)) do table.insert(out, e) end
		end
		return t + secs
	end

	R.it("the out lap is not timed; then laps line to line with three sectors; a cut or a reverse does not count", function()
		local st = T.new(0)
		local ev = {}
		local t = drive(0, 0.5, 1.0, 10, 0, st, ev)          -- out lap to the line
		t = drive(t, 0.0, 1.0, 40, 0, st, ev)                -- lap 1
		local laps, sectors, started = {}, 0, 0
		for _, e in ipairs(ev) do
			if e.kind == "lap" then table.insert(laps, e) end
			if e.kind == "sector" then sectors += 1 end
			if e.kind == "start" then started += 1 end
		end
		R.expect(started).toBe(1)
		R.expect(#laps).toBe(1)
		R.expect(math.abs(laps[1].time - 40) < 0.5).toBe(true)
		R.expect(laps[1].valid).toBe(true)
		R.expect(sectors).toBe(2)
		local sum = laps[1].sectors[1] + laps[1].sectors[2] + laps[1].sectors[3]
		R.expect(math.abs(sum - laps[1].time) < 1e-6).toBe(true)
		R.expect(st.best).toBe(laps[1].time)
		-- a short cut: from sector 1 straight to the line (a share jump the sectors miss)
		local ev2 = {}
		local st2 = T.new(0)
		local t2 = drive(0, 0.9, 1.0, 1, 0, st2, ev2)
		for _, e in ipairs(T.feed(st2, 0.2, 0, t2 + 20, false)) do table.insert(ev2, e) end
		for _, e in ipairs(T.feed(st2, 0.5, 0, t2 + 21, false)) do table.insert(ev2, e) end   -- (skips)
		for _, e in ipairs(T.feed(st2, 0.95, 0, t2 + 30, false)) do table.insert(ev2, e) end
		for _, e in ipairs(T.feed(st2, 0.02, 0, t2 + 31, false)) do table.insert(ev2, e) end
		local cut
		for _, e in ipairs(ev2) do if e.kind == "lap" then cut = e end end
		R.expect(cut ~= nil and cut.valid == false and cut.counted == false).toBe(true)
		R.expect(st2.best).toBe(nil)
		-- too quick for any car
		R.expect(T.minLap() > 15).toBe(true)
	end)

	R.it("track limits spoil the lap (shown, never a best); the pit lane is not track limits", function()
		local st = T.new(0)
		local ev = {}
		local t = drive(0, 0.5, 1.0, 10, 0, st, ev)
		t = drive(t, 0.0, 0.3, 10, 0, st, ev)
		t = drive(t, 0.3, 0.32, 1, 30, st, ev)               -- wide
		t = drive(t, 0.32, 1.0, 30, 0, st, ev)
		local lap, limits = nil, 0
		for _, e in ipairs(ev) do
			if e.kind == "lap" then lap = e end
			if e.kind == "limits" then limits += 1 end
		end
		R.expect(limits).toBe(1)
		R.expect(lap.valid).toBe(false)
		R.expect(lap.counted).toBe(true)
		R.expect(st.best).toBe(nil)
		local st2 = T.new(0)
		local ev2 = {}
		T.feed(st2, 0.99, 0, 0, false)
		T.feed(st2, 0.01, 0, 1, false)
		for _, e in ipairs(T.feed(st2, 0.02, 40, 2, true)) do table.insert(ev2, e) end
		R.expect(#ev2).toBe(0)
	end)

	R.it("colours: purple the session's best, green your own best, yellow slower; the board ranks best laps", function()
		R.expect(T.colour(40, nil, nil)).toBe("purple")
		R.expect(T.colour(40, 41, 39)).toBe("green")
		R.expect(T.colour(42, 41, 39)).toBe("yellow")
		R.expect(T.colour(38, 41, 39)).toBe("purple")
		R.expect(T.format(42.3456)).toBe("42.346")
		R.expect(T.format(62.5)).toBe("1:02.500")
		local list = T.ranked({ a = { name = "A", time = 41 }, b = { name = "B", time = 39 }, c = { name = "C", time = 45 } }, 2)
		R.expect(#list).toBe(2)
		R.expect(list[1].name).toBe("B")
	end)
end)

R.describe("Junk GP: the simulated driver laps every bot build", function()
	local env = Loader.boot()
	local GpCar = env.requirePath("ReplicatedStorage.Shared.GpCar")
	local GpDriver = env.requirePath("ReplicatedStorage.Shared.GpDriver")
	local GpLayout = env.requirePath("ReplicatedStorage.Shared.GpLayout")
	local RideRating = env.requirePath("ReplicatedStorage.Shared.RideRating")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

	local function laps(spec, skill, n)
		local geo = GpLayout.geometry()
		local x, z, dx, dz = geo:pointAt(1)
		local yaw = math.atan2(-dx, -dz)
		local st = GpCar.newState()
		local d = GpDriver.new(spec, skill)
		local t, lap, lastS, lapT, flips, off = 0, 0, 0, 0, 0, 0
		local times = {}
		while lap < n and t < 200 do
			local input, p = GpDriver.input(d, st, x, z, yaw)
			local a = math.abs(p.lateral)
			local surface = a <= 14 and "road" or (a <= 17 and "kerb" or "grass")
			if a > Constants.GP.TRACK_LIMIT then off += 1 / 60 end
			local r = GpCar.step(spec, st, input, { dt = 1 / 60, yaw = yaw, surface = surface })
			if r.flip then flips += 1 st.flipped = false st.over = 0 end
			yaw = GpCar.wrap(yaw + r.yawRate / 60)
			x += -math.sin(r.travelYaw) * r.speed / 60
			z += -math.cos(r.travelYaw) * r.speed / 60
			t += 1 / 60
			if lastS > geo.length * 0.9 and p.s < geo.length * 0.1 then
				lap += 1
				table.insert(times, t - lapT)
				lapT = t
			end
			lastS = p.s
		end
		return times, flips, off
	end

	R.it("two laps each, 30 - 55 s a lap, no rollovers on fresh tyres, hardly off the road; the faster build is faster", function()
		local Bots = { { BODY = "Toilet", ENGINE = "Rocket" }, { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" },
			{ BODY = "Bathtub", ENGINE = "Fan" }, { BODY = "Red Sofa", ENGINE = "Hair Dryer" }, { BODY = "Shopping Cart" } }
		local best = {}
		for i, slots in ipairs(Bots) do
			local spec = GpCar.spec(RideRating.rate(slots, "FOREST").bars, 1.1)
			local times, flips, off = laps(spec, 0.9, 2)
			R.expect(#times).toBe(2)
			for _, lt in ipairs(times) do R.expect(lt > 30 and lt < 55).toBe(true, string.format("%s %.1f", slots.BODY, lt)) end
			R.expect(flips).toBe(0)
			R.expect(off < 3).toBe(true, string.format("%s off %.1f s", slots.BODY, off))
			best[i] = times[2]
		end
		local fast = GpCar.spec({ speed = 1, accel = 1, handling = 1 }, 1.1)
		local slow = GpCar.spec({ speed = 0.1, accel = 0.1, handling = 0.1 }, 1.1)
		local tf = laps(fast, 0.9, 1)[1]
		local ts = laps(slow, 0.9, 1)[1]
		R.expect(ts - tf > 8).toBe(true, string.format("%.1f vs %.1f", tf, ts))
	end)

	R.it("a tall car at 0.95 of its grip laps three times without going over (the speed plan lines up with the road)", function()
		-- nodes are 8 - 10 studs apart: the plan read by index / STEP was up
		-- to 48 studs off, the bots came into corners too fast and the
		-- tallest rolled at the same corner every lap (Studio gp-drive)
		for _, slots in ipairs({ { BODY = "Toilet", ENGINE = "Rocket" }, { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" } }) do
			local spec = GpCar.spec(RideRating.rate(slots, "FOREST").bars, 0.6)
			local times, flips, off = laps(spec, 0.95, 3)
			R.expect(#times).toBe(3)
			R.expect(flips).toBe(0, slots.BODY)
			R.expect(off < 1).toBe(true, string.format("%s off %.1f s", slots.BODY, off))
		end
	end)

	-- cars on the circuit together through GpDriver's traffic; contacts =
	-- two closer than 6 studs, passes = changes of order
	local function together(list, seconds)
		local geo = GpLayout.geometry()
		local L = geo.length
		local cars = {}
		for i, c in ipairs(list) do
			local x, z, dx, dz = geo:pointAt(1)
			cars[i] = { spec = c.spec, st = GpCar.newState(), d = GpDriver.new(c.spec, c.skill),
				x = x, z = z, yaw = math.atan2(-dx, -dz), startAt = c.startAt, s = 0, lateral = 0, dist = 0 }
		end
		local dt = 1 / 60
		local contacts, flips, passes, near, order = 0, 0, 0, {}, {}
		for t = 0, seconds, dt do
			local live = {}
			for _, c in ipairs(cars) do
				if t >= c.startAt then table.insert(live, { car = c, s = c.s, lateral = c.lateral, speed = c.st.speed }) end
			end
			for _, c in ipairs(cars) do
				if t >= c.startAt then
					local others = {}
					for _, o in ipairs(live) do if o.car ~= c then table.insert(others, o) end end
					local input, p = GpDriver.input(c.d, c.st, c.x, c.z, c.yaw, others, dt)
					local a = math.abs(p.lateral)
					local r = GpCar.step(c.spec, c.st, input, { dt = dt, yaw = c.yaw, surface = a <= 14 and "road" or "kerb" })
					if r.flip then flips += 1 c.st.flipped = false c.st.over = 0 end
					c.yaw = GpCar.wrap(c.yaw + r.yawRate * dt)
					c.x += -math.sin(r.travelYaw) * r.speed * dt
					c.z += -math.cos(r.travelYaw) * r.speed * dt
					c.dist += (p.s - c.s + L / 2) % L - L / 2
					c.s, c.lateral = p.s, p.lateral
				end
			end
			for i = 1, #cars do
				for j = i + 1, #cars do
					local a, b = cars[i], cars[j]
					if t >= a.startAt and t >= b.startAt then
						local key = i * 10 + j
						local close = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) < 6
						if close and not near[key] then contacts += 1 end
						near[key] = close
						local ahead = a.dist > b.dist
						if order[key] ~= nil and order[key] ~= ahead then passes += 1 end
						order[key] = ahead
					end
				end
			end
		end
		return contacts, flips, passes, cars, L
	end

	R.it("five bots together, the fastest starting last, close behind: they never touch or go over", function()
		-- Studio 2026-11-19: without traffic sense they drove into each other
		-- and were put back in pairs ("stuck" at the same moment)
		local Bots = { { BODY = "Toilet", ENGINE = "Rocket" }, { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" },
			{ BODY = "Bathtub", ENGINE = "Fan" }, { BODY = "Red Sofa", ENGINE = "Hair Dryer" }, { BODY = "Shopping Cart" } }
		local S = Constants.GP.BOT_SKILL
		local list = {}
		for i, slots in ipairs(Bots) do
			list[i] = { spec = GpCar.spec(RideRating.rate(slots, "FOREST").bars, 0.8),
				skill = S[1] + (S[2] - S[1]) * (i - 1) / 4, startAt = (#Bots - i) * 1.5 }
		end
		local contacts, flips, _, cars, L = together(list, 200)
		R.expect(contacts).toBe(0)
		R.expect(flips).toBe(0)
		for _, c in ipairs(cars) do R.expect(c.dist / L > 3.5).toBe(true, string.format("%.1f laps", c.dist / L)) end
	end)

	R.it("a fast car a second behind a slow one passes it without touching", function()
		local slow = GpCar.spec({ speed = 0, accel = 0, handling = 0.2 }, 1.1)
		local fast = GpCar.spec({ speed = 1, accel = 1, handling = 1 }, 1.1)
		local contacts, flips, passes, cars = together({ { spec = slow, skill = 0.9, startAt = 0 }, { spec = fast, skill = 0.95, startAt = 1 } }, 120)
		R.expect(contacts).toBe(0)
		R.expect(flips).toBe(0)
		R.expect(passes > 0).toBe(true)
		R.expect(cars[2].dist > cars[1].dist).toBe(true)
	end)
end)

R.describe("Junk GP in a server", function()
	local SCRIPTS = {
		"ServerScriptService.GameBootstrap",
		"ServerScriptService.MapManager",
		"ServerScriptService.CharacterManager",
		"ServerScriptService.ProgressionManager",
		"ServerScriptService.ShopManager",
		"ServerScriptService.LegendManager",
		"ServerScriptService.LobbyManager",
		"ServerScriptService.GpManager",
	}
	local function boot(gp)
		local srv = Server.boot({
			players = 2, scripts = SCRIPTS,
			harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 600, gp = gp ~= false, autoStart = false },
		})
		srv.advance(23)   -- the circuit, the place mode, the item models' wait, the bots
		local e = srv.env
		return srv, {
			L = e.requirePath("ReplicatedStorage.Shared.GpLayout"),
			Lobby = e.requirePath("ReplicatedStorage.Shared.LobbyLayout"),
			Constants = e.requirePath("ReplicatedStorage.Shared.Constants"),
			PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore"),
			RE = e.requirePath("ReplicatedStorage.RemoteEvents"),
			circuit = e.workspace:FindFirstChild("JunkGP"),
		}
	end
	local function events(m, player, kind)
		local out = {}
		for _, c in ipairs(rawget(m.RE.GpEvent, "_calls") or {}) do
			if c.method == "FireClient" and c.args[1] == player and c.args[2].kind == kind then table.insert(out, c.args[2]) end
		end
		return out
	end
	local function prompt(circuit)
		for _, d in ipairs(circuit:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d:GetAttribute("GpAction") == "enter" then return d end
		end
	end
	local function carOf(m, player)
		for _, c in ipairs(m.circuit.Cars:GetChildren()) do
			if c:GetAttribute("UserId") == player.UserId then return c end
		end
	end

	R.it("is built with seats in the grandstand, a desk at the gate and the bots in their garages", function()
		local srv, m = boot()
		R.expect(m.circuit ~= nil).toBe(true)
		R.expect(prompt(m.circuit) ~= nil).toBe(true)
		local seats, parts = 0, 0
		for _, d in ipairs(m.circuit:GetDescendants()) do
			if d:IsA("Seat") and not d:IsA("VehicleSeat") then seats += 1 end
			if d:IsA("BasePart") then parts += 1 end
		end
		R.expect(seats > 100).toBe(true, tostring(seats))
		R.expect(parts < 6000).toBe(true, "parts " .. parts)
		-- no barrier by the road: none at an inside apex (Studio: cars cutting
		-- one stuck there), none across another stretch (judged on the pieces'
		-- data: Lune's CFrame.lookAt mirrors Z, so built parts read wrong here)
		local geo = m.L.geometry()
		local GpCircuit = srv.env.requirePath("ServerScriptService.Modules.Maps.GpCircuit")
		local close = {}
		for _, b in ipairs(GpCircuit.barrierPieces()) do
			for _, f in ipairs({ 0, 0.5, 1 }) do
				local x, z = b[1] + (b[3] - b[1]) * f, b[2] + (b[4] - b[2]) * f
				if geo:project(x, z).dist < 27 then
					table.insert(close, string.format("%.0f, %.0f", x, z))
					break
				end
			end
		end
		R.expect(close).toBeEmpty("barriers by the road")
		local bots = 0
		for _, c in ipairs(m.circuit.Cars:GetChildren()) do if c:GetAttribute("Bot") then bots += 1 end end
		R.expect(bots).toBe(m.Constants.GP.BOTS)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("no car, no race: the desk turns you away; a car you own gets you a garage, a helmet and the lights", function()
		local srv, m = boot()
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		rec.cars, rec.legend = {}, {}
		prompt(m.circuit).Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(#events(m, p, "denied")).toBe(1)
		R.expect(events(m, p, "denied")[1].reason).toBe("no_car")
		R.expect(carOf(m, p)).toBe(nil)
		rec.cars = { ["Rubber Duck"] = true }
		-- (the mock's characters have no head: give it one for the helmet)
		local head = srv.env.mock.Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.CFrame = p.Character.HumanoidRootPart.CFrame * CFrame.new(0, 1.6, 0)
		head.Parent = p.Character
		prompt(m.circuit).Triggered:Fire(p)
		srv.advance(3)
		local car = carOf(m, p)
		R.expect(car ~= nil).toBe(true)
		R.expect(car:GetAttribute("Title")).toBe("Rubber Duck")
		R.expect(p:GetAttribute("GpCar")).toBe(true)
		R.expect(p.Character:FindFirstChild("GpHelmet") ~= nil).toBe(true)
		local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
		R.expect(seat.Occupant).toBe(p.Character:FindFirstChildOfClass("Humanoid"))
		local session = events(m, p, "session")[1]
		R.expect(session ~= nil and session.laps == m.Constants.GP.LAPS).toBe(true)
		local box = car:GetAttribute("Box")
		R.expect(box >= 1 and box <= m.Constants.GP.MAX_CARS).toBe(true)
		-- in the garage, held until the lights go out
		R.expect(car.PrimaryPart.Anchored).toBe(true)
		srv.advance(8)
		R.expect(car.PrimaryPart.Anchored).toBe(false)
		-- the lobby's net leaves a driver alone (Studio: it put the driver, and
		-- the car with them, back on the plaza at the lights)
		local root = p.Character.HumanoidRootPart
		R.expect(m.Lobby.onPlaza(root.Position)).toBe(false)
		-- a lost helmet goes back on (Studio record-gp: a character that
		-- respawned just after entering raced bareheaded)
		p.Character:FindFirstChild("GpHelmet"):Destroy()
		srv.advance(0.5)
		R.expect(p.Character:FindFirstChild("GpHelmet") ~= nil).toBe(true)
		-- a second player gets another box
		srv.players[2]:SetAttribute("x", 1)
		m.PlayerStore.get(srv.players[2]).cars = { Toilet = true }
		prompt(m.circuit).Triggered:Fire(srv.players[2])
		srv.advance(1)
		R.expect(carOf(m, srv.players[2]):GetAttribute("Box") ~= box).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("laps are timed from the car's position: a pit stop on your mark, LAPS laps, back in town with the best saved and on the board", function()
		local srv, m = boot()
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		rec.cars = { Toilet = true }
		prompt(m.circuit).Triggered:Fire(p)
		srv.advance(9)
		local car = carOf(m, p)
		local chassis = car.PrimaryPart
		local O = m.Lobby.ORIGIN
		local geo = m.L.geometry()
		local y = chassis.Position.Y
		-- drive along the centerline: `secs` for a whole lap
		local function lapAlong(fromS, toS, secs)
			local steps = math.floor(secs * 10)
			for k = 1, steps do
				local s = (fromS + (toS - fromS) * k / steps) % geo.length
				local x, z = geo:pointAt(s)
				chassis.CFrame = CFrame.new(O.X + x, y, O.Z + z)
				srv.advance(0.1)
			end
		end
		lapAlong(geo.length * 0.6, geo.length, 12)          -- out lap from the pit exit side
		lapAlong(0, geo.length, 40)                          -- lap 1
		R.expect(#events(m, p, "start")).toBe(1)
		R.expect(#events(m, p, "lap")).toBe(1)
		R.expect(#events(m, p, "sector") >= 3).toBe(true)
		-- into the pits: stop on the mark
		local stop = O + m.L.box(car:GetAttribute("Box"))
		chassis.CFrame = CFrame.new(stop.X, y, stop.Z)
		srv.advance(0.5)
		R.expect(#events(m, p, "pit")).toBe(1)
		local crew = 0
		for _, c in ipairs(rawget(m.RE.GpEvent, "_calls") or {}) do
			if c.method == "FireAllClients" and c.args[1].kind == "crew" and c.args[1].car == car then crew += 1 end
		end
		R.expect(crew).toBe(1)
		srv.advance(3.5)
		R.expect(#events(m, p, "pit")).toBe(2)
		-- (the test put the car on its mark by hand: that lap is spoiled, a jump no car makes)
		lapAlong(0, geo.length, 36)
		R.expect(#events(m, p, "lap")).toBe(m.Constants.GP.LAPS)
		local done = events(m, p, "done")[1]
		R.expect(done ~= nil).toBe(true)
		R.expect(math.abs(done.best - 36) < 1).toBe(true, tostring(done.best))
		R.expect(done.laps[2].valid).toBe(false)
		R.expect(rec.gp.best).toBe(done.best)
		R.expect(rec.gp.car).toBe("Toilet")
		-- the board has the player's line
		local board = srv.env.game.ReplicatedStorage:GetAttribute("GpBoard")
		R.expect(board:find(p.DisplayName, 1, true) ~= nil).toBe(true)
		-- after the card: back in town, the car gone, no helmet
		srv.advance(m.Constants.GP.DONE_SECONDS + 1)
		R.expect(carOf(m, p)).toBe(nil)
		R.expect(p:GetAttribute("GpCar")).toBe(nil)
		local root = p.Character.HumanoidRootPart
		R.expect(m.Lobby.onStreet(root.Position)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a car off the grounds is put back on the road; LEAVE ends the run; leaving the game frees the box", function()
		local srv, m = boot()
		local p = srv.players[1]
		m.PlayerStore.get(p).cars = { Toilet = true }
		prompt(m.circuit).Triggered:Fire(p)
		srv.advance(9)
		local car = carOf(m, p)
		local O = m.Lobby.ORIGIN
		car.PrimaryPart.CFrame = CFrame.new(O.X - 700, O.Y - 60, O.Z)
		srv.advance(1)
		local resets = events(m, p, "reset")
		R.expect(#resets).toBe(1)
		R.expect(resets[1].reason).toBe("off_grounds")
		R.expect(m.L.onCircuit(car.PrimaryPart.Position)).toBe(true)
		-- a car pinned against the armco (the client asks: there is no reverse)
		srv.advance(2.5)
		R.expect(srv.invoke("GpAction", p, "reset", "pinned")).toBe("ok")
		resets = events(m, p, "reset")
		R.expect(#resets).toBe(2)
		R.expect(resets[2].reason).toBe("pinned")
		R.expect(srv.invoke("GpAction", p, "leave")).toBe("ok")
		srv.advance(0.5)
		R.expect(carOf(m, p)).toBe(nil)
		R.expect(#events(m, p, "ended")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("closed outside the hub: the circuit stands, the desk says so, no bots", function()
		local srv, m = boot(false)
		local p = srv.players[1]
		m.PlayerStore.get(p).cars = { Toilet = true }
		prompt(m.circuit).Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(events(m, p, "denied")[1].reason).toBe("closed")
		R.expect(#m.circuit.Cars:GetChildren()).toBe(0)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
