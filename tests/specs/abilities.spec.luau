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
		-- not slowed: only the canopy's own wind boost is on
		local AbilityConfig = srv.env.requirePath("ServerScriptService.Modules.AbilityConfig")
		local boost = AbilityConfig.get("Umbrella", "FOREST").selfSpeed or 1
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed") * boost, 1e-6)
	end)

	R.it("Flower removes active slowdowns", function()
		local srv, cars = abilityServer()
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		fire(srv, cars[1], "Cup Noodle")
		srv.advance(0.1)
		R.expect(cars[2].seat.MaxSpeed).toBeLessThan(VehicleTuning.base(cars[2].seat, "MaxSpeed"))
		fire(srv, cars[2], "Flower")
		srv.advance(0.1)
		local AbilityConfig = srv.env.requirePath("ServerScriptService.Modules.AbilityConfig")
		local boost = AbilityConfig.get("Flower", "FOREST").selfSpeed or 1
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed") * boost, 1e-6)
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

-- History (2026-10-22): drops were plain blocks / discs placed at car height
-- − 1.5 (floating or sunk), not the item that made them.
R.describe("items left on the track show the item, on the ground", function()
	local srv, cars = abilityServer()
	srv.env.run(srv.env.find("ServerScriptService.ItemModelPreloader"))
	local TrackDropsFolder = function() return srv.env.workspace:FindFirstChild("TrackDrops") end
	local DROPS = { "Pizza", "Gas Can", "Magnifying Glass", "Kettle", "Cactus", "Log" }

	R.it("each drop item leaves a copy of its model on the ground, ringed and labelled", function()
		local bad = {}
		for _, item in ipairs(DROPS) do
			local before = TrackDropsFolder() and #TrackDropsFolder():GetChildren() or 0
			local result = fire(srv, cars[1], item)
			srv.advance(0.3)
			local f = TrackDropsFolder()
			local drop = f and f:FindFirstChild("Drop_" .. item)
			if result ~= "ok" then
				table.insert(bad, item .. ": " .. tostring(result))
			elseif not drop or #f:GetChildren() <= before then
				table.insert(bad, item .. ": no drop")
			else
				local parts, lowest = 0, math.huge
				for _, d in ipairs(drop:GetDescendants()) do
					if d:IsA("BasePart") and not ({ DropHazard = 1, DropRing = 1, DropPuddle = 1 })[d.Name] then
						parts += 1
						local h = d.Size / 2
						for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
							lowest = math.min(lowest, (d.CFrame * roblox.Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)).Y)
						end end end
					end
				end
				if parts < 1 then table.insert(bad, item .. ": no item model") end
				if math.abs(lowest - 1) > 0.6 then
					table.insert(bad, ("%s: item bottom at Y %.1f, ground at 1"):format(item, lowest))
				end
				if not drop:FindFirstChild("DropRing") or not drop:FindFirstChild("DropLabel", true) then
					table.insert(bad, item .. ": no ring / label")
				end
			end
			srv.advance(Constants.RACE_COUNTDOWN)   -- next item off any shared cooldown
		end
		R.expect(bad).toBeEmpty("drops")
	end)

	R.it("obstacle drops collide with a hitbox the size of the model; slicks do not block", function()
		R.expect(fire(srv, cars[1], "Pizza")).toBe("ok")
		srv.advance(0.3)
		local f = TrackDropsFolder()
		local cactus = f and f:FindFirstChild("Drop_Cactus")
		local log = f and f:FindFirstChild("Drop_Log")
		local pizza = f and f:FindFirstChild("Drop_Pizza")
		R.expect(cactus and cactus.DropHazard.CanCollide).toBe(true)
		R.expect(srv.mock.CollectionService:HasTag(cactus.DropHazard, "Obstacle")).toBe(true)
		R.expect(log and log.DropHazard.CanCollide).toBe(true)
		R.expect(pizza and pizza.DropHazard.CanCollide).toBe(false)
	end)

	R.it("every drop is logged for the Studio harness", function()
		local logged = {}
		for _, e in ipairs(srv.Telemetry.events("drop_placed")) do logged[e.item] = e end
		for _, item in ipairs(DROPS) do
			R.expect(logged[item] ~= nil).toBe(true)
			R.expect(logged[item].onGround).toBe(true)
		end
	end)
end)
