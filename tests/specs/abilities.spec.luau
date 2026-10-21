--!nocheck
-- Fires EVERY item's ability through the real AbilityManager during a race,
-- with an opponent nearby, and checks nothing errors and the effect lands.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local Constants -- set by abilityServer

-- Puts `item` into its own core slot on the player's car (as crafting does).
local function equip(srv, car, item)
	local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	car.stats.slotAssignments[ItemConfig[item].slotType] = item
end

-- Equips and fires `item` for car `c`.
local function fire(srv, c, item)
	equip(srv, c, item)
	return srv.mock.invoke(srv.RemoteEvents.RequestAbility, c.player, item)
end

local function abilityServer(opts)
	opts = opts or {}
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
		stats.slotAssignments = {}
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 520 - (i - 1) * 6), {})
		model.Parent = env.workspace
		srv.SessionManager.setVehicle(player, model, stats)
		cars[i] = { player = player, model = model, stats = stats, seat = model:FindFirstChildWhichIsA("VehicleSeat", true) }
	end
	Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	-- past the start countdown (Modules/RaceStart): abilities work from GO
	srv.advance(opts.beforeGo and 0.5 or (Constants.RACE_COUNTDOWN + 0.5))
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
			local result = fire(srv, cars[1], name)
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
		fire(srv, cars[2], "Cardboard Box")
		fire(srv, cars[1], "Cup Noodle")
		R.expect(cars[2].seat.MaxSpeed).toBeNear(srv.env.requirePath("ServerScriptService.Modules.VehicleTuning").base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)

	R.it("an Umbrella shield blocks the next enemy ability", function()
		local srv, cars = abilityServer()
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		fire(srv, cars[2], "Umbrella")
		srv.advance(0.1)
		fire(srv, cars[1], "Cup Noodle")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)

	R.it("Flower removes active slowdowns", function()
		local srv, cars = abilityServer()
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		fire(srv, cars[1], "Cup Noodle")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeLessThan(VehicleTuning.base(cars[2].seat, "MaxSpeed"))
		fire(srv, cars[2], "Flower")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed"), 1e-6)
	end)
end)

R.describe("ability rules", function()
	-- Before 2026-10-21 the server took any item name from the client.
	R.it("an item that is not on the car is refused", function()
		local srv, cars = abilityServer()
		local r = srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Rocket")
		R.expect(r).toBe("denied: not equipped")
		-- in the inventory but crafted into a non-ability slot: still refused
		cars[1].stats.slotAssignments.HEAD = "Rocket"
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Rocket")).toBe("denied: not equipped")
		cars[1].stats.slotAssignments.ENGINE = "Rocket"
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, "Rocket")).toBe("ok")
	end)

	R.it("nothing fires during the start countdown", function()
		local srv, cars = abilityServer({ beforeGo = true })
		R.expect(fire(srv, cars[1], "Rocket")).toBe("denied: countdown")
		srv.advance(Constants.RACE_COUNTDOWN)
		R.expect(fire(srv, cars[1], "Rocket")).toBe("ok")
	end)

	R.it("a bad item name from a client is refused, not an error", function()
		local srv, cars = abilityServer()
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestAbility, cars[1].player, { "x" })).toBe("denied: bad item")
		R.expect(#srv.mock.errors).toBe(0)
	end)

	R.it("the activator is told the cooldown (HUD, RacingClient)", function()
		local srv, cars = abilityServer()
		fire(srv, cars[1], "Rocket")
		local calls = rawget(srv.RemoteEvents.AbilityActivated, "_calls") or {}
		local info = calls[#calls].args[5]
		R.expect(type(info)).toBe("table")
		R.expect(info.cooldown > 0).toBe(true)
	end)
end)

R.describe("ability effects are announced to every client (EffectFx)", function()
	local srv, cars = abilityServer()
	local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local EffectLook = srv.env.requirePath("ReplicatedStorage.Shared.EffectLook")

	R.it("every item's ability draws something on a car", function()
		local names = {}
		for name, cfg in pairs(ItemConfig) do
			if type(cfg) == "table" and cfg.slotType then table.insert(names, name) end
		end
		table.sort(names)
		local silent = {}
		for _, name in ipairs(names) do
			local before = #(rawget(srv.RemoteEvents.EffectFx, "_calls") or {})
			fire(srv, cars[1], name)
			srv.advance(0.3)
			local after = #(rawget(srv.RemoteEvents.EffectFx, "_calls") or {})
			if after == before then table.insert(silent, name) end
			srv.advance(2)
		end
		R.expect(silent).toBeEmpty("abilities that showed nothing")
	end)

	R.it("every key sent has a look", function()
		local missing = {}
		for _, c in ipairs(rawget(srv.RemoteEvents.EffectFx, "_calls") or {}) do
			if not EffectLook.CAR[c.args[1]] then missing[c.args[1]] = true end
		end
		local list = {}
		for k in pairs(missing) do table.insert(list, k) end
		R.expect(list).toBeEmpty("EffectFx keys without an EffectLook.CAR entry")
	end)
end)

R.describe("lift abilities raise the car", function()
	-- Studio: an upward BodyForce of 2.5-5k could not beat the ride-height
	-- BodyPosition (P 1.2e4 / 5e4): F / P < 0.3 studs, nothing visible.
	R.it("Balloon Bunch sets LiftOffset for its duration, then clears it", function()
		local srv, cars = abilityServer()
		local VC = srv.env.requirePath("ReplicatedStorage.Shared.VehicleController")
		local roblox2 = require("@lune/roblox")
		R.expect(fire(srv, cars[1], "Balloon Bunch")).toBe("ok")
		srv.advance(0.1)
		local primary = cars[1].model.PrimaryPart
		local lift = primary:GetAttribute("LiftOffset")
		R.expect(lift).toBe(Constants.ABILITY_LIFT.rise)
		-- the driving code raises the suspension target by the lift (eased)
		for _ = 1, 120 do
			VC.apply(primary, { forwardSpeed = 0, yawRate = 0, climb = 0 }, {
				biome = "FOREST", altitudeDt = 1 / 60,
				raycast = function() return { Position = roblox2.Vector3.new(0, 1, 0) } end,
			})
		end
		R.expect(primary.SuspensionHover.Position.Y).toBeNear(1 + primary.Size.Y / 2 + 0.2 + lift, 1e-3)
		srv.advance(10)
		R.expect(primary:GetAttribute("LiftOffset")).toBe(nil)
	end)
end)
