--!nocheck
-- The Alpine Luge (2026-11-20): the hill and its trough (Shared/LugeLayout),
-- how a cart rolls (Shared/LugeCart), the simulated rider (Shared/LugeDriver)
-- from careful to careless and on a keyboard, two friends bumping
-- (Shared/CarBump), and a session in a server (LugeManager: the booth, the
-- chairlift, the gate, the run, the finish, again).

local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

R.describe("Alpine Luge: the hill and the trough", function()
	local env = Loader.boot()
	local LL = env.requirePath("ReplicatedStorage.Shared.LugeLayout")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local W = Constants.LUGE.WIDTH
	local N = LL.nodes()

	R.it("runs downhill all the way, never steeper than MAX_GRADE, on the ground or low trestles", function()
		local steep, trestle = 0, 0
		for i = 2, #N do
			local d = math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2)
			R.expect(N[i][3] <= N[i - 1][3] + 1e-9).toBe(true, "climbs at node " .. i)
			steep = math.max(steep, (N[i - 1][3] - N[i][3]) / d)
			-- never under the hill (the higher side of the trough clears it)
			R.expect(N[i][3] >= LL.ground(N[i][2]) + LL.ROAD - 1e-6).toBe(true, "under the grass at node " .. i)
			trestle = math.max(trestle, N[i][3] - LL.ground(N[i][2]))
		end
		R.expect(steep <= LL.MAX_GRADE + 1e-6).toBe(true, tostring(steep))
		R.expect(trestle < 8).toBe(true, tostring(trestle))
		R.expect(N[1][3] - N[#N][3] > 70).toBe(true, "drop " .. (N[1][3] - N[#N][3]))
	end)

	R.it("stays on its grounds, apart from itself, clear of the chairlift; starts by the top station, ends by the bottom one", function()
		local Rg = LL.REGION
		local S, acc = { 0 }, 0
		for i = 2, #N do acc += math.sqrt((N[i][1] - N[i - 1][1]) ^ 2 + (N[i][2] - N[i - 1][2]) ^ 2) S[i] = acc end
		for i, n in ipairs(N) do
			R.expect(n[1] - W / 2 > Rg[1] + 4 and n[1] + W / 2 < Rg[2] - 4 and n[2] > Rg[3] + 4 and n[2] < Rg[4] - 4).toBe(true, "outside at " .. i)
			-- (on the hill; the run-out ends by the lift's bottom station on purpose)
			if n[2] < LL.BOTTOM_STATION[3] - 10 then
				R.expect(math.abs(n[1] - LL.LIFT.x) > W / 2 + 8).toBe(true, "under the lift at " .. i)
			end
			for j = i + 1, #N do
				if S[j] - S[i] > 60 then
					local d = math.sqrt((n[1] - N[j][1]) ^ 2 + (n[2] - N[j][2]) ^ 2)
					R.expect(d > W + 18).toBe(true, string.format("stretches %d and %d %.1f apart", i, j, d))
				end
			end
		end
		local function near(p, r) return p[1] > r[1] - 30 and p[1] < r[2] + 30 and p[2] > r[3] - 30 and p[2] < r[4] + 30 end
		R.expect(near(N[1], LL.TOP_STATION)).toBe(true)
		R.expect(near(N[#N], LL.BOTTOM_STATION)).toBe(true)
		-- the hill meets the lot and the GP's grass, overlapping neither
		local Lobby = env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		R.expect(Rg[4] <= Lobby.STREET.lot[3] + 1e-6).toBe(true)
		R.expect(Rg[1] >= env.requirePath("ReplicatedStorage.Shared.GpLayout").GROUND[2] - 1e-6).toBe(true)
	end)

	R.it("the chairlift's cars clear the hill all the way up", function()
		for k = 0, 50 do
			local p = LL.liftAt(k / 50)
			R.expect(p.Y >= LL.ground(p.Z) - 1e-6).toBe(true, string.format("at %.0f: %.1f under %.1f", p.Z, p.Y, LL.ground(p.Z)))
		end
	end)

	R.it("high banked walls only outside the hairpins", function()
		local K = LL.curves()
		local hairpins, highs = 0, 0
		for i = 1, #N do
			if math.abs(K[i]) > 1 / 15 then hairpins += 1 end
			if LL.highLip(1, K[i]) or LL.highLip(-1, K[i]) then highs += 1 end
			R.expect(not (LL.highLip(1, K[i]) and LL.highLip(-1, K[i]))).toBe(true)
		end
		R.expect(hairpins > 30).toBe(true, tostring(hairpins))
		R.expect(highs >= hairpins).toBe(true)
	end)
end)

R.describe("Alpine Luge: how a cart rolls (LugeCart)", function()
	local env = Loader.boot()
	local Cart = env.requirePath("ReplicatedStorage.Shared.LugeCart")
	local L = env.requirePath("ReplicatedStorage.Shared.Constants").LUGE
	local spec = Cart.spec({ handling = 0.5 }, 1.5)
	-- a straight trough heading north (yaw 0)
	local function at(grade, lateral, curve) return { yaw = 0, grade = grade, lateral = lateral or 0, curve = curve or 0, s = 100 } end

	R.it("gravity rolls it downhill to a steady speed under the governor; on the flat it slows; the brake stops it", function()
		local st = Cart.newState()
		for _ = 1, 60 * 30 do Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(-0.08) }) end
		R.expect(st.speed > 30 and st.speed <= L.TOP + 1e-6).toBe(true, tostring(st.speed))
		local v = st.speed
		for _ = 1, 60 do Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(0) }) end
		R.expect(st.speed < v - 3).toBe(true)
		for _ = 1, 120 do Cart.step(spec, st, { brake = 1 }, { dt = 1 / 60, yaw = 0, at = at(-0.05) }) end
		R.expect(st.speed).toBe(0)
		-- the gas only paddles: on the flat, never past PUSH.UNTIL
		for _ = 1, 600 do Cart.step(spec, st, { throttle = 1 }, { dt = 1 / 60, yaw = 0, at = at(0) }) end
		R.expect(st.speed > 5 and st.speed <= L.PUSH.UNTIL + 0.5).toBe(true, tostring(st.speed))
	end)

	R.it("into a lip slowly it bounces back (a scrape); fast sideways it goes over (a hop); the high wall in a hairpin holds more", function()
		local edge = Cart.edge(spec)
		local function into(latV, curve)
			local st = Cart.newState()
			st.speed = 30
			-- travelling a little to the right (+lateral)
			local ang = math.asin(latV / 30)
			st.travelYaw = -ang
			return Cart.step(spec, st, {}, { dt = 1 / 60, yaw = -ang, at = at(-0.04, edge + 0.2, curve) }), st
		end
		local out, st = into(4)
		R.expect(out.event).toBe("scrape")
		R.expect(out.latV < 0).toBe(true)       -- now heading back in
		R.expect(st.off).toBe(false)
		out, st = into(L.HOP.LOW + 2)
		R.expect(out.event).toBe("hop")
		R.expect(st.off).toBe(true)
		-- the right side is the outside of a left hairpin (curve < 0): the high wall
		out = into(L.HOP.LOW + 2, -1 / 11)
		R.expect(out.event).toBe("scrape")
	end)

	R.it("on the grass it crawls, comes back in when steered there, and asks the marshals when it cannot", function()
		local edge = Cart.edge(spec)
		local st = Cart.newState()
		st.speed, st.off = 30, true
		for _ = 1, 120 do Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(-0.05, edge + 3) }) end
		R.expect(st.speed <= L.OFF.TOP + 1).toBe(true, tostring(st.speed))
		local out = Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(-0.05, edge - 1) })
		R.expect(out.event).toBe("back")
		R.expect(st.off).toBe(false)
		st.off, st.offT = true, 0
		local asked = false
		for _ = 1, math.ceil(60 * (L.OFF.RESET + 0.5)) do
			out = Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(0, edge + 3) })
			asked = asked or out.wantReset == true
		end
		R.expect(asked).toBe(true)
	end)

	R.it("a friend's bump changes speed and path, never throws it backwards", function()
		local st = Cart.newState()
		st.speed = 30
		local out = Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(-0.04), kick = { x = 6, z = 0 } })
		R.expect(out.latV > 3).toBe(true, tostring(out.latV))
		st = Cart.newState()
		st.speed = 10
		Cart.step(spec, st, {}, { dt = 1 / 60, yaw = 0, at = at(-0.04), kick = { x = 0, z = 40 } })
		R.expect(st.speed < 0.5).toBe(true, tostring(st.speed))
	end)
end)

R.describe("Alpine Luge: riders down the hill (LugeDriver)", function()
	local env = Loader.boot()
	local Cart = env.requirePath("ReplicatedStorage.Shared.LugeCart")
	local Driver = env.requirePath("ReplicatedStorage.Shared.LugeDriver")
	local LL = env.requirePath("ReplicatedStorage.Shared.LugeLayout")
	local CarBump = env.requirePath("ReplicatedStorage.Shared.CarBump")
	local L = env.requirePath("ReplicatedStorage.Shared.Constants").LUGE
	local geo = LL.geometry()

	local function rider(spec, skill, late, blind)
		local x, z, dx, dz = geo:pointAt(2)
		return { spec = spec, st = Cart.newState(), d = Driver.new(spec, skill, blind), x = x, z = z, yaw = math.atan2(-dx, -dz),
			late = late, queue = {}, steer = 0, t = 0, hops = 0, scrapes = 0, resets = 0, offT = 0 }
	end
	local function step(c, dt, traffic, kick)
		local at = LL.at(c.x, c.z, nil, c.hint)
		c.hint, c.at = at.seg, at
		local input = Driver.input(c.d, c.st, c.x, c.z, c.yaw, at, traffic)
		if c.late then
			table.insert(c.queue, input)
			local l = c.queue[1]
			if #c.queue > math.floor(c.late / dt) then table.remove(c.queue, 1) end
			local want = (l.steer > 0.3 and 1) or (l.steer < -0.3 and -1) or 0
			local rate = (math.abs(want) > math.abs(c.steer) and 5 or 9) * dt
			c.steer += math.clamp(want - c.steer, -rate, rate)
			input = { throttle = l.throttle > 0.5 and 1 or 0, brake = l.brake > 0.3 and 1 or 0, steer = c.steer }
		end
		local out = Cart.step(c.spec, c.st, input, { dt = dt, yaw = c.yaw, at = at, kick = kick })
		if out.event == "hop" then c.hops += 1 end
		if out.event == "scrape" then c.scrapes += 1 end
		if c.st.off then c.offT += dt end
		if out.wantReset then
			c.resets += 1
			local x, z, dx, dz = geo:pointAt(math.max(2, at.s - 10))
			c.x, c.z, c.yaw, c.st, c.hint = x, z, math.atan2(-dx, -dz), Cart.newState(), nil
			return
		end
		c.yaw = Cart.wrap(c.yaw + out.yawRate * dt)
		c.x += -math.sin(out.travelYaw) * out.speed * dt
		c.z += -math.cos(out.travelYaw) * out.speed * dt
		c.t += dt
		if not c.done and at.s >= LL.finishS() then c.done = c.t end
	end
	local function ride(spec, skill, late)
		local c = rider(spec, skill, late)
		while not c.done and c.t < 200 do step(c, 1 / 60) end
		return c
	end

	R.it("careful riders, narrow or wide, come down in 35 - 50 s and never leave the trough", function()
		for _, sk in ipairs({ 0.8, 1, 1.3 }) do
			for _, w in ipairs({ { 1.1, 0.2 }, { 2.4, 0.9 } }) do
				local c = ride(Cart.spec({ handling = w[2] }, w[1]), sk)
				R.expect(c.done ~= nil and c.done > 35 and c.done < 50).toBe(true, string.format("skill %.1f half %.1f: %s", sk, w[1], tostring(c.done)))
				R.expect(c.hops).toBe(0)
				R.expect(c.resets).toBe(0)
			end
		end
	end)

	R.it("someone on a keyboard, a moment late, scrapes the lips and may slip off, but always gets back in by themselves", function()
		local spec = Cart.spec({ handling = 0.5 }, 1.8)
		local fine = ride(spec, 0.95, 0.15)
		R.expect(fine.hops).toBe(0)
		R.expect(fine.done < 50).toBe(true, tostring(fine.done))
		local sloppy = ride(spec, 1.2, 0.3)
		R.expect(sloppy.done ~= nil and sloppy.done < 75).toBe(true, tostring(sloppy.done))
		R.expect(sloppy.scrapes > 0).toBe(true)
		R.expect(sloppy.resets).toBe(0)
	end)

	R.it("two friends close behind each other, not looking: they bump, gently, and both get down", function()
		local spec = Cart.spec({ handling = 0.5 }, 1.8)
		local a, b = rider(spec, 0.8, nil, true), rider(spec, 1.05, nil, true)
		local dt, t, bumps, hardest, last = 1 / 60, 0, 0, 0, -1
		local ka, kb
		while t < 200 and not (a.done and b.done) do
			t += dt
			if not a.done then step(a, dt, nil, ka) end
			ka = nil
			if t > 1.5 and not b.done then step(b, dt, nil, kb) end
			kb = nil
			if t > 1.5 and t - last > L.BUMP.GAP then
				local function box(c, id)
					local ty = c.st.travelYaw or c.yaw
					return { id = id, x = c.x, z = c.z, vx = -math.sin(ty) * c.st.speed, vz = -math.cos(ty) * c.st.speed, yaw = c.yaw, length = 7, width = 3.6 }
				end
				for _, h in ipairs(CarBump.find({ box(a, "a"), box(b, "b") }, L.BUMP)) do
					bumps += 1
					hardest = math.max(hardest, h.power)
					ka, kb, last = { x = h.ax, z = h.az }, { x = h.bx, z = h.bz }, t
				end
			end
		end
		R.expect(bumps > 0).toBe(true)
		R.expect(hardest < 15).toBe(true, tostring(hardest))
		R.expect(a.done ~= nil and b.done ~= nil).toBe(true)
		R.expect(a.resets + b.resets).toBe(0)
	end)
end)

R.describe("Alpine Luge in a server", function()
	local SCRIPTS = {
		"ServerScriptService.GameBootstrap",
		"ServerScriptService.MapManager",
		"ServerScriptService.CharacterManager",
		"ServerScriptService.ProgressionManager",
		"ServerScriptService.ShopManager",
		"ServerScriptService.LegendManager",
		"ServerScriptService.LobbyManager",
		"ServerScriptService.LugeManager",
	}
	local function boot(luge)
		local srv = Server.boot({
			players = 2, scripts = SCRIPTS,
			harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 600, luge = luge ~= false, autoStart = false },
		})
		srv.advance(23)   -- the hill, the place mode, the item models, the characters
		local e = srv.env
		return srv, {
			LL = e.requirePath("ReplicatedStorage.Shared.LugeLayout"),
			Lobby = e.requirePath("ReplicatedStorage.Shared.LobbyLayout"),
			Constants = e.requirePath("ReplicatedStorage.Shared.Constants"),
			PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore"),
			RE = e.requirePath("ReplicatedStorage.RemoteEvents"),
			hill = e.workspace:FindFirstChild("AlpineLuge"),
		}
	end
	local function events(m, player, kind)
		local out = {}
		for _, c in ipairs(rawget(m.RE.LugeEvent, "_calls") or {}) do
			if c.method == "FireClient" and c.args[1] == player and c.args[2].kind == kind then table.insert(out, c.args[2]) end
		end
		return out
	end
	local function prompt(hill)
		for _, d in ipairs(hill:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d:GetAttribute("LugeAction") == "enter" then return d end
		end
	end
	local function cartOf(m, player)
		for _, c in ipairs(m.hill.Carts:GetChildren()) do
			if c:GetAttribute("UserId") == player.UserId then return c end
		end
	end

	R.it("stands with its booth in town, the trough, the chairlift and its chairs, in a modest number of parts", function()
		local srv, m = boot()
		R.expect(m.hill ~= nil).toBe(true)
		local pp = prompt(m.hill)
		R.expect(pp ~= nil).toBe(true)
		R.expect(m.Lobby.onStreet(pp.Parent.Position)).toBe(true)
		local parts, trough = 0, 0
		for _, d in ipairs(m.hill:GetDescendants()) do
			if d:IsA("BasePart") then parts += 1 end
			if d.Name == "LugeTrough" then trough += 1 end
		end
		R.expect(trough > 50).toBe(true)
		R.expect(parts < 4000).toBe(true, "parts " .. parts)
		R.expect(#m.hill.LiftChairs:GetChildren() > 10).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("no car, no ride; with one: built at the bottom, seated in a helmet, up the chairlift, the gate, go", function()
		local srv, m = boot()
		local p = srv.players[1]
		prompt(m.hill).Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(events(m, p, "denied")[1].reason).toBe("no_car")
		m.PlayerStore.get(p).cars = { ["Rubber Duck"] = true }
		-- (the mock's characters have no head: give it one for the helmet)
		local head = srv.env.mock.Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.CFrame = p.Character.HumanoidRootPart.CFrame * CFrame.new(0, 1.6, 0)
		head.Parent = p.Character
		prompt(m.hill).Triggered:Fire(p)
		srv.advance(2)
		local cart = cartOf(m, p)
		R.expect(cart ~= nil).toBe(true)
		R.expect(p:GetAttribute("LugeCart")).toBe(true)
		R.expect(p.Character:FindFirstChild("GpHelmet") ~= nil).toBe(true)
		R.expect(#events(m, p, "session")).toBe(1)
		local lift = events(m, p, "lift")[1]
		R.expect(lift ~= nil).toBe(true)
		R.expect(cart.PrimaryPart.Anchored).toBe(true)
		local y0 = cart.PrimaryPart.Position.Y
		srv.advance(lift.secs / 2)
		R.expect(cart.PrimaryPart.Position.Y > y0 + 30).toBe(true, "half way up the hill")
		srv.advance(lift.secs / 2 + 2)
		R.expect(#events(m, p, "gate")).toBe(1)
		R.expect(srv.invoke("LugeAction", p, "ready")).toBe("ok")
		srv.advance(m.Constants.LUGE.START_HOLD + 0.5)
		R.expect(#events(m, p, "go")).toBe(1)
		R.expect(cart.PrimaryPart.Anchored).toBe(false)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("down the trough to the finish: the time, the best saved; the chairlift again; LEAVE puts you by the booth", function()
		local srv, m = boot()
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		rec.cars = { Toilet = true }
		prompt(m.hill).Triggered:Fire(p)
		srv.invoke("LugeAction", p, "ready")
		local cart
		for _ = 1, 400 do
			srv.advance(0.1)
			cart = cartOf(m, p)
			if #events(m, p, "go") > 0 then break end
		end
		R.expect(#events(m, p, "go")).toBe(1)
		local geo = m.LL.geometry()
		local O = m.Lobby.ORIGIN
		local chassis = cart.PrimaryPart
		-- rolled down (the test moves the car the way a client would)
		local steps = 400
		for k = 1, steps do
			local s = geo.length * k / steps
			local x, z = geo:pointAt(math.min(s, geo.length - 1))
			chassis.CFrame = CFrame.new(O.X + x, O.Y + geo:heightAt(s) + 1.2, O.Z + z)
			srv.advance(0.1)
			if #events(m, p, "finish") > 0 then break end
		end
		local fin = events(m, p, "finish")[1]
		R.expect(fin ~= nil).toBe(true)
		R.expect(fin.time > 20 and fin.time < 60).toBe(true, tostring(fin.time))
		R.expect(rec.luge.best).toBe(fin.time)
		R.expect(rec.luge.runs).toBe(1)
		srv.advance(m.Constants.LUGE.FINISH_HOLD + 1)
		R.expect(#events(m, p, "lift")).toBe(2)
		R.expect(srv.invoke("LugeAction", p, "leave")).toBe("ok")
		srv.advance(0.5)
		R.expect(cartOf(m, p)).toBe(nil)
		R.expect(p:GetAttribute("LugeCart")).toBe(nil)
		R.expect(m.Lobby.onStreet(p.Character.HumanoidRootPart.Position)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a rush down past the trough (a jump no cart makes) does not finish; a cart off the hill goes back in the trough", function()
		local srv, m = boot()
		local p = srv.players[1]
		m.PlayerStore.get(p).cars = { Toilet = true }
		prompt(m.hill).Triggered:Fire(p)
		srv.invoke("LugeAction", p, "ready")
		local cart
		for _ = 1, 400 do
			srv.advance(0.1)
			cart = cartOf(m, p)
			if #events(m, p, "go") > 0 then break end
		end
		local geo = m.LL.geometry()
		local O = m.Lobby.ORIGIN
		local x, z = geo:pointAt(geo.length - 5)
		cart.PrimaryPart.CFrame = CFrame.new(O.X + x, O.Y + geo:heightAt(geo.length - 5) + 1.2, O.Z + z)
		srv.advance(0.5)
		R.expect(#events(m, p, "finish")).toBe(0)
		cart.PrimaryPart.CFrame = CFrame.new(O.X - 700, O.Y - 60, O.Z)
		srv.advance(0.5)
		R.expect(events(m, p, "reset")[1].reason).toBe("off_grounds")
		R.expect(m.LL.onGrounds(cart.PrimaryPart.Position)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("two friends' carts touching: each gets a push (no physical contact between them)", function()
		local srv, m = boot()
		local a, b = srv.players[1], srv.players[2]
		for _, p in ipairs({ a, b }) do
			m.PlayerStore.get(p).cars = { Toilet = true }
			prompt(m.hill).Triggered:Fire(p)
			srv.invoke("LugeAction", p, "ready")
		end
		for _ = 1, 600 do
			srv.advance(0.1)
			if #events(m, a, "go") > 0 and #events(m, b, "go") > 0 then break end
		end
		R.expect(#events(m, b, "go")).toBe(1)
		local ca, cb = cartOf(m, a), cartOf(m, b)
		local geo = m.LL.geometry()
		local O = m.Lobby.ORIGIN
		local x, z = geo:pointAt(200)
		ca.PrimaryPart.CFrame = CFrame.new(O.X + x, O.Y + geo:heightAt(200) + 1.2, O.Z + z)
		cb:PivotTo(ca.PrimaryPart.CFrame * CFrame.new(0, 0, -(ca.PrimaryPart.Size.Z / 2 + cb.PrimaryPart.Size.Z / 2) + 0.8))
		ca.PrimaryPart.AssemblyLinearVelocity = ca.PrimaryPart.CFrame.LookVector * 25
		srv.env.game:GetService("RunService").Heartbeat:Fire(1 / 60)
		R.expect(#events(m, a, "bump")).toBe(1)
		R.expect(#events(m, b, "bump")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("filming: guests ride the chairlift and come down by themselves; one follows a player and catches them", function()
		local srv = Server.boot({
			players = 1, scripts = SCRIPTS,
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 600, autoStart = false,
				luge = { crowd = 3, follow = true } },
		})
		srv.advance(23)
		local e = srv.env
		local hill = e.workspace:FindFirstChild("AlpineLuge")
		local Crowd = e.requirePath("ServerScriptService.Modules.LugeCrowd")
		local guests = 0
		for _, c in ipairs(hill.Carts:GetChildren()) do if c:GetAttribute("Guest") then guests += 1 end end
		R.expect(guests).toBe(3)
		-- the first is at the bottom of the lift: up and off within the lift's time
		local hb = e.game:GetService("RunService").Heartbeat
		local LL = e.requirePath("ReplicatedStorage.Shared.LugeLayout")
		local secs = LL.liftLength() / e.requirePath("ReplicatedStorage.Shared.Constants").LUGE.LIFT_SPEED
		local riding = 0
		for _ = 1, math.ceil((secs + 4) * 10) do
			srv.advance(0.1, 1 / 30, function() hb:Fire(1 / 30) end)
			riding = math.max(riding, #Crowd.riding())
		end
		R.expect(riding >= 1).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
