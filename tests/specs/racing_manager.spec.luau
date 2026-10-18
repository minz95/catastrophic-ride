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

	R.known("overlapping obstacle + mud returns to the base MaxSpeed",
		"each effect saves MaxSpeed and restores its saved copy later; bump → enter mud → bump restore → leave mud leaves the car at 2× its MaxSpeed for the rest of the race",
		function()
			local r = raceServer()
			r.touch(r.obstacle)          -- 0.5×, saves base
			r.touch(r.mud)               -- 0.25×
			r.srv.advance(1.1)           -- obstacle restores its saved base (mud forgotten)
			r.untouch(r.mud)             -- divides by 0.5 → 2× base
			R.expect(r.seat.MaxSpeed).toBeNear(r.base, 1e-6)
		end)

	R.known("boost during a boost pad returns to the base MaxSpeed",
		"pad saves base and sets 1.4×; boost saves 1.4× and sets 2.1×; pad restores base after 2 s; a boost longer than 2 s then restores 1.4× permanently",
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
		R.expect(ev[2].after).toBeNear(r.base, 1e-6)
	end)
end)
