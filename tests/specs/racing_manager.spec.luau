--!nocheck
-- Runs the REAL RacingManager script in the mock engine and fires the same
-- Touched events a car would, to check speed effects when they overlap.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

-- Boots a server that goes straight to RACING with one player in a car.
local function raceServer(boostDuration)
	local srv = Server.boot({
		players = 1,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 600 } },
	})
	local env, Mock = srv.env, srv.mock
	local player = srv.players[1]

	-- A tagged obstacle the car can bump (FOREST has none by default).
	local ob = Mock.Instance.new("Part")
	ob.Name = "TestObstacle"
	ob.Size = Vector3.new(4, 4, 4)
	ob.CFrame = CFrame.new(0, 3, 400)
	ob.Parent = env.workspace
	Mock.CollectionService:AddTag(ob, "Obstacle")

	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
	if boostDuration then stats.boostDuration = boostDuration end
	local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 590), {})
	model.Parent = env.workspace
	srv.SessionManager.setVehicle(player, model, stats)

	srv.advance(0.5) -- LOBBY → FARMING → CRAFTING → RACING
	assert(srv.GameManager.getPhase() == "RACING", "expected RACING, got " .. tostring(srv.GameManager.getPhase()))

	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local function part(tag)
		return Mock.CollectionService:GetTagged(tag)[1]
	end
	return {
		srv = srv, seat = seat, chassis = model.PrimaryPart, base = seat.MaxSpeed,
		mud = part("MudZone"), pad = nil, obstacle = ob, player = player,
		touch = function(p) p.Touched:Fire(model.PrimaryPart) end,
		untouch = function(p) p.TouchEnded:Fire(model.PrimaryPart) end,
	}
end

R.describe("RacingManager speed effects (real script)", function()
	R.it("mud halves MaxSpeed and leaving restores it", function()
		local r = raceServer()
		r.touch(r.mud)
		R.expect(r.seat.MaxSpeed).toBeNear(r.base * 0.5, 1e-6)
		r.untouch(r.mud)
		R.expect(r.seat.MaxSpeed).toBeNear(r.base, 1e-6)
	end)

	R.it("an obstacle bump slows for 1 s then restores", function()
		local r = raceServer()
		r.touch(r.obstacle)
		R.expect(r.seat.MaxSpeed).toBeNear(r.base * 0.5, 1e-6)
		r.srv.advance(1.1)
		R.expect(r.seat.MaxSpeed).toBeNear(r.base, 1e-6)
	end)

	R.it("overlapping obstacle + mud returns to the base MaxSpeed",
		function()
			local r = raceServer()
			r.touch(r.obstacle)          -- 0.5×, saves base
			r.touch(r.mud)               -- 0.25×
			r.srv.advance(1.1)           -- obstacle restores its saved base (mud forgotten)
			r.untouch(r.mud)             -- divides by 0.5 → 2× base
			R.expect(r.seat.MaxSpeed).toBeNear(r.base, 1e-6)
		end)

	R.it("boost during a boost pad returns to the base MaxSpeed",
		function()
			local r = raceServer(5) -- e.g. a Trophy/Soda build: boost lasts 5 s
			local pads = r.srv.mock.CollectionService:GetTagged("BoostPad")
			local livePad
			for _, p in ipairs(pads) do
				if p.Transparency < 0.75 then livePad = p break end
			end
			assert(livePad, "no active boost pad")
			r.touch(livePad)
			R.expect(r.seat.MaxSpeed).toBeNear(r.base * 1.4, 1e-6)
			r.srv.mock.invoke(r.srv.RemoteEvents.RequestBoost, r.player)
			r.srv.advance(10)
			R.expect(r.seat.MaxSpeed).toBeNear(r.base, 1e-6)
		end)

	R.it("telemetry records every MaxSpeed change", function()
		local r = raceServer()
		r.touch(r.mud)
		r.untouch(r.mud)
		local ev = r.srv.Telemetry.events("speed_effect")
		R.expect(#ev).toBe(2)
		R.expect(ev[1].effect).toBe("mud")
		R.expect(ev[1].phase).toBe("enter")
		R.expect(ev[2].phase).toBe("exit")
		R.expect(ev[2].after).toBeNear(r.base, 1e-6)
	end)
end)

-- ─── Two-car scenarios ────────────────────────────────────────────────────────

-- Boots a race with one car per entry in `cars` ({ slots = {...}, at = CFrame }).
local function multiServer(cars, extraScripts)
	local scripts = {
		"ServerScriptService.MapBuilders.ForestMapBuilder",
		"ServerScriptService.GameBootstrap",
		"ServerScriptService.RacingManager",
	}
	for _, sname in ipairs(extraScripts or {}) do table.insert(scripts, sname) end
	local srv = Server.boot({
		players = #cars, scripts = scripts,
		harness = { harness = "lune", biome = "FOREST", players = #cars, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 600 } },
	})
	local env = srv.env
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local out = { srv = srv, cars = {} }
	for i, car in ipairs(cars) do
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		stats.slotAssignments = car.slots or {}
		stats.boostDuration = car.boostDuration or stats.boostDuration
		local model = VehicleBuilder.build(stats, "FOREST", car.at or CFrame.new(i * 8, 2, 590), car.slots or {})
		model.Parent = env.workspace
		srv.SessionManager.setVehicle(srv.players[i], model, stats)
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		out.cars[i] = { player = srv.players[i], model = model, chassis = model.PrimaryPart, seat = seat, base = seat.MaxSpeed }
	end
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RACING")
	srv.advance(0.6) -- one position-sync tick so passives are set up
	return out
end

R.describe("HEAD / TAIL passives (real RacingManager)", function()
	R.it("Cactus HEAD slows the car it rear-ends; Cactus TAIL slows whoever rear-ends it", function()
		-- Car 1 directly behind car 2, both facing -Z (down the start straight)
		local m = multiServer({
			{ slots = { HEAD = "Cactus" }, at = CFrame.new(0, 2, 520) },
			{ slots = { TAIL = "Cactus" }, at = CFrame.new(0, 2, 512) },
		})
		local a, b = m.cars[1], m.cars[2]
		b.chassis.Touched:Fire(a.chassis)
		R.expect(b.seat.MaxSpeed).toBeNear(b.base * 0.5, 1e-6)  -- victim slowed by a's head
		R.expect(a.seat.MaxSpeed).toBeNear(a.base * 0.5, 1e-6)  -- attacker slowed by b's tail
		m.srv.advance(2)
		R.expect(a.seat.MaxSpeed).toBeNear(a.base, 1e-6)
		R.expect(b.seat.MaxSpeed).toBeNear(b.base, 1e-6)
	end)

	R.it("Balloon Bunch TAIL absorbs a rear-end", function()
		local m = multiServer({
			{ slots = { HEAD = "Cactus" }, at = CFrame.new(0, 2, 520) },
			{ slots = { TAIL = "Balloon Bunch" }, at = CFrame.new(0, 2, 512) },
		})
		m.cars[2].chassis.Touched:Fire(m.cars[1].chassis)
		R.expect(m.cars[2].seat.MaxSpeed).toBeNear(m.cars[2].base, 1e-6)
	end)

	R.it("Rubber Duck HEAD ignores the first obstacle hit of the race", function()
		local m = multiServer({ { slots = { HEAD = "Rubber Duck" } } })
		local car = m.cars[1]
		local ob = m.srv.mock.Instance.new("Part")
		ob.Size = Vector3.new(4, 4, 4)
		ob.CFrame = CFrame.new(0, 3, 400)
		ob.Parent = m.srv.env.workspace
		m.srv.mock.CollectionService:AddTag(ob, "Obstacle")
		ob.Touched:Fire(car.chassis)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base, 1e-6)
		m.srv.advance(1.2)
		ob.Touched:Fire(car.chassis)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base * 0.5, 1e-6)
	end)

	R.it("Rocket TAIL adds a second of boost", function()
		local m = multiServer({ { slots = { TAIL = "Rocket" }, boostDuration = 2 } })
		local car = m.cars[1]
		m.srv.mock.invoke(m.srv.RemoteEvents.RequestBoost, car.player)
		m.srv.advance(2.5)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base * 1.5, 1e-6)
		m.srv.advance(0.6)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base, 1e-6)
	end)

	R.it("Racing Flag HEAD gives the race leader +5%", function()
		local m = multiServer({
			{ slots = { HEAD = "Racing Flag" }, at = CFrame.new(0, 2, 300) },  -- further along
			{ slots = {}, at = CFrame.new(0, 2, 560) },
		})
		R.expect(m.cars[1].seat.MaxSpeed).toBeNear(m.cars[1].base * 1.05, 1e-6)
	end)
end)

R.describe("protection and track effects (real RacingManager)", function()
	R.it("an Umbrella shield blocks one obstacle hit", function()
		local m = multiServer({ { slots = {} } })
		local car = m.cars[1]
		local RaceEffects = m.srv.env.requirePath("ServerScriptService.Modules.RaceEffects")
		RaceEffects.grant(car.player, "shield", 3)
		local ob = m.srv.mock.Instance.new("Part")
		ob.Size = Vector3.new(4, 4, 4)
		ob.Parent = m.srv.env.workspace
		m.srv.mock.CollectionService:AddTag(ob, "Obstacle")
		ob.Touched:Fire(car.chassis)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base, 1e-6)
		R.expect(RaceEffects.has(car.player, "shield")).toBe(false)
	end)

	R.it("Drill dig mode ignores mud", function()
		local m = multiServer({ { slots = {} } })
		local car = m.cars[1]
		local RaceEffects = m.srv.env.requirePath("ServerScriptService.Modules.RaceEffects")
		RaceEffects.grant(car.player, "dig", 4)
		local mud = m.srv.mock.CollectionService:GetTagged("MudZone")[1]
		mud.Touched:Fire(car.chassis)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base, 1e-6)
	end)

	R.it("a wheel leaving the mud does not end the effect while the chassis is in it", function()
		local m = multiServer({ { slots = {} } })
		local car = m.cars[1]
		local wheel = car.model:FindFirstChild("Wheel")
		local mud = m.srv.mock.CollectionService:GetTagged("MudZone")[1]
		mud.Touched:Fire(car.chassis)
		mud.Touched:Fire(wheel)
		mud.TouchEnded:Fire(wheel)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base * 0.5, 1e-6)
		mud.TouchEnded:Fire(car.chassis)
		R.expect(car.seat.MaxSpeed).toBeNear(car.base, 1e-6)
	end)

	R.it("respawn puts the car on the track centerline facing along it", function()
		local m = multiServer({ { slots = {}, at = CFrame.new(580, 2, -300) } })  -- S3, X far from 0
		local car = m.cars[1]
		m.srv.mock.invoke(m.srv.RemoteEvents.RequestRespawn, car.player)
		m.srv.advance(0.2)
		local RaceProgress = m.srv.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
		local geo = RaceProgress.geometry("FOREST")
		local pos = car.chassis.Position
		local p = geo:project(pos.X, pos.Z)
		R.expect(p.dist).toBeLessThan(1)
		local _, _, dx, dz = geo:pointAt(p.s)
		local look = car.chassis.CFrame.LookVector
		R.expect(look.X * dx + look.Z * dz).toBeGreaterThan(0.9)
	end)
end)

R.describe("rounds", function()
	R.it("a second race does not apply track effects twice", function()
		local srv = Server.boot({
			players = 1,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 2, RESULTS = 0.5 } },
		})
		srv.advance(3.5)   -- round 1 races and times out; round 2 starts
		srv.advance(0.3)
		R.expect(srv.GameManager.getRound()).toBe(2)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local env = srv.env
		local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 590), {})
		model.Parent = env.workspace
		srv.SessionManager.setVehicle(srv.players[1], model, stats)
		local before = #srv.Telemetry.events("speed_effect")
		srv.mock.CollectionService:GetTagged("MudZone")[1].Touched:Fire(model.PrimaryPart)
		R.expect(#srv.Telemetry.events("speed_effect") - before).toBe(1)
	end)
end)

