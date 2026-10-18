--!nocheck
-- Fires EVERY item's ability through the real AbilityManager during a race,
-- with an opponent nearby, and checks nothing errors and the effect lands.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local function abilityServer()
	local srv = Server.boot({
		players = 2,
		swallowErrors = true,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.AbilityManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 900 } },
	})
	local env = srv.env
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local cars = {}
	for i, player in ipairs(srv.players) do
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 520 - (i - 1) * 6), {})
		model.Parent = env.workspace
		srv.SessionManager.setVehicle(player, model, stats)
		cars[i] = { player = player, model = model, seat = model:FindFirstChildWhichIsA("VehicleSeat", true) }
	end
	srv.advance(0.5)
	return srv, cars
end

R.describe("abilities (real AbilityManager)", function()
	local srv, cars = abilityServer()
	local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local names = {}
	for name, cfg in pairs(ItemConfig) do
		if type(cfg) == "table" and cfg.slotType then table.insert(names, name) end
	end
	table.sort(names)

	R.it("every item's ability can be used while racing without errors", function()
		local bad = {}
		for _, name in ipairs(names) do
			local result = srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, name)
			srv.advance(0.2)
			if result ~= "ok" then table.insert(bad, name .. ": " .. tostring(result)) end
		end
		srv.advance(10)
		for _, e in ipairs(srv.mock.errors) do table.insert(bad, "error: " .. e:sub(1, 200)) end
		for _, e in ipairs(srv.Telemetry.events("ability_unhandled")) do
			table.insert(bad, "unhandled: " .. e.item)
		end
		R.expect(bad).toBeEmpty("abilities that failed")
	end)

	R.it("every speed and turn effect wears off", function()
		local bad = {}
		for _, c in ipairs(cars) do
			local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
			for _, prop in ipairs({ "MaxSpeed", "TurnSpeed" }) do
				local base = VehicleTuning.base(c.seat, prop)
				if math.abs(c.seat[prop] - base) > 1e-6 then
					table.insert(bad, string.format("%s %s = %.2f (base %.2f)", c.player.Name, prop, c.seat[prop], base))
				end
			end
		end
		R.expect(bad).toBeEmpty("seats left changed after every effect expired")
	end)

	R.it("the client is told which effect played", function()
		local calls = rawget(srv.RemoteEvents.AbilityActivated, "_calls") or {}
		local last = calls[#calls]
		R.expect(last ~= nil).toBe(true)
		R.expect(type(last.args[4])).toBe("string")
	end)
end)

R.describe("ability protection", function()
	R.it("a Cardboard Box disguise cannot be targeted", function()
		local srv, cars = abilityServer()
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[2].player, "Cardboard Box")
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Cup Noodle")
		R.expect(cars[2].seat.MaxSpeed).toBeNear(srv.env.requirePath("ServerScriptService.Modules.VehicleTuning").base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)

	R.it("an Umbrella shield blocks the next enemy ability", function()
		local srv, cars = abilityServer()
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[2].player, "Umbrella")
		srv.advance(0.1)
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Cup Noodle")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)

	R.it("Flower removes active slowdowns", function()
		local srv, cars = abilityServer()
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Cup Noodle")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeLessThan(VehicleTuning.base(cars[2].seat, "MaxSpeed"))
		srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[2].player, "Flower")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)
end)
