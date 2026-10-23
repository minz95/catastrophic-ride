--!nocheck
-- Server bots on the farm (Modules/FarmBots) and as ability targets in the
-- race: they farm through the same FarmingManager calls as players, can be
-- punched and robbed, race the car their bag makes, and abilities hit them.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function farm(fillBots)
	local srv = Server.boot({
		players = 1,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 90, CRAFTING = 5, RACING = 600 } },
	})
	local e = srv.env
	local FarmBots = e.requirePath("ServerScriptService.Modules.FarmBots")
	FarmBots.kinematic = true   -- no physics offline: walk by moving the root
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	tick(0.5)
	return srv, FarmBots, tick, e.requirePath("ReplicatedStorage.Shared.Constants")
end

R.describe("farm bots (live servers fill the farm)", function()
	R.it("live rule: bots fill to BOTS.FILL_TO; harness sessions only with fillBots", function()
		local srv, FarmBots, _, C = farm(nil)
		R.expect(FarmBots.wanted(1, nil)).toBe(C.BOTS.FILL_TO - 1)
		R.expect(FarmBots.wanted(1, { harness = "match" })).toBe(0)
		R.expect(#srv.SessionManager.bots()).toBe(0)
	end)

	R.it("one player: three bots join FARMING as tagged NPCs and pick items up", function()
		local srv, FarmBots, tick, C = farm(4)
		local bots = srv.SessionManager.bots()
		R.expect(#bots).toBe(3)
		R.expect(#srv.mock.CollectionService:GetTagged("FarmBot")).toBe(3)
		for _, b in ipairs(bots) do
			R.expect(b.UserId < -100000).toBe(true)
			R.expect(b.Character ~= nil and b.Character:FindFirstChild("HumanoidRootPart") ~= nil).toBe(true)
		end
		tick(30)
		for _, b in ipairs(bots) do
			R.expect(#srv.SessionManager.getData(b).inventory).toBeGreaterThan(0)
		end
		local picks = 0
		for _, ev in ipairs(srv.Telemetry.events("item_pickup")) do
			if ev.userId < -100000 then picks += 1 end
		end
		R.expect(picks).toBeGreaterThan(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a player can punch a bot until it drops an item", function()
		local srv, FarmBots, tick, C = farm(2)
		local player = srv.players[1]
		local bot = srv.SessionManager.bots()[1]
		srv.SessionManager.getData(bot).inventory = { "Kettle", "Log" }
		FarmBots.paused = true   -- hold still
		local F = C.FIGHT
		local results = {}
		for _ = 1, F.HITS_TO_DROP do
			player.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 850)
			bot.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 846)
			table.insert(results, (srv.mock.invoke(srv.RemoteEvents.RequestPunch, player)))
			tick(F.COOLDOWN + 0.05)
		end
		R.expect(results[#results]).toBe("knockout")
		R.expect(#srv.SessionManager.getData(bot).inventory).toBe(1)
		R.expect(#srv.Telemetry.events("item_dropped_world")).toBe(1)
	end)

	R.it("a player can rob a bot (the steal reaches the bot like a player)", function()
		local srv, FarmBots, tick = farm(2)
		local player = srv.players[1]
		local bot = srv.SessionManager.bots()[1]
		FarmBots.paused = true
		srv.SessionManager.getData(bot).inventory = { "Kettle", "Log" }
		player.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 850)
		bot.Character.HumanoidRootPart.Position = Vector3.new(1, 3, 850)
		tick(25)   -- past the steal-free start of the phase
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, player, bot.UserId)
		tick(2)
		local att = srv.Telemetry.events("steal_attempt")
		R.expect(#att).toBe(1)
		R.expect(att[1].victim).toBe(bot.UserId)
		R.expect(att[1].result == "stolen" or att[1].result == "defended").toBe(true)
	end)

	R.it("a bot contests an item with a player and the faster masher wins", function()
		local srv, FarmBots, tick = farm(2)
		local player = srv.players[1]
		local bot = srv.SessionManager.bots()[1]
		local item
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then item = d break end
		end
		local pos = item.Parent.Position
		FarmBots.paused = true
		srv.SessionManager.getData(bot).inventory = {}
		player.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		bot.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, player, item.Value)).toBe("contested")
		for i = 1, 30 do
			srv.mock.invoke(srv.RemoteEvents.RequestContest, player, item.Value, i * 3)
			tick(0.1)
		end
		local res = srv.Telemetry.events("contest_result")
		R.expect(#res).toBe(1)
		R.expect(res[1].winner).toBe(player.UserId)
		R.expect(res[1].loser).toBe(bot.UserId)
	end)

	R.it("CRAFTING: bots leave the farm with their bag; LOBBY: bots are gone", function()
		local srv, FarmBots, tick = farm(3)
		tick(20)
		local bags = 0
		for _, b in ipairs(srv.SessionManager.bots()) do bags += #srv.SessionManager.getData(b).inventory end
		R.expect(bags).toBeGreaterThan(0)
		srv.GameManager.shortenPhase("FARMING", 0)
		tick(1)
		R.expect(srv.GameManager.getPhase()).toBe("CRAFTING")
		R.expect(#srv.mock.CollectionService:GetTagged("FarmBot")).toBe(0)
		local after = 0
		for _, b in ipairs(srv.SessionManager.bots()) do after += #srv.SessionManager.getData(b).inventory end
		R.expect(after).toBe(bags)
	end)
end)

-- ─── Race: the bots race their bag, and abilities hit them ───────────────────

local function race()
	local srv = Server.boot({
		players = 1,
		swallowErrors = true,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.AbilityManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = 2,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 900 } },
	})
	local e = srv.env
	local FarmBots = e.requirePath("ServerScriptService.Modules.FarmBots")
	-- a bot that farmed: its bag decides its car
	local proxy = FarmBots.proxy(1)
	srv.SessionManager.getData(proxy).inventory = { "Bathtub", "Rocket", "Pizza" }
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
	stats.slotAssignments = {}
	local player = srv.players[1]
	local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 520), {})
	model.Parent = e.workspace
	srv.SessionManager.setVehicle(player, model, stats)
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	tick(C.RACE_COUNTDOWN + 1)
	return srv, player, stats, tick, e.requirePath("ServerScriptService.Modules.RaceBots"), C
end

R.describe("race bots are the farm bots, and abilities hit them", function()
	R.it("a bot that farmed races the auto craft of its bag", function()
		local srv, _, _, _, RaceBots = race()
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		R.expect(#RaceBots.list).toBe(1)
		local spawned = srv.Telemetry.events("race_bot")[1]
		R.expect(spawned.farmed).toBe(true)
		R.expect(spawned.slots.BODY).toBe("Bathtub")
		R.expect(spawned.name).toBe(srv.SessionManager.bots()[1].Name)
		R.expect(srv.SessionManager.getData(srv.SessionManager.bots()[1]).vehicleModel).toBe(RaceBots.list[1].model)
	end)

	R.it("a targeted ability (Magnet, Camera) lands on the nearest bot", function()
		local srv, player, stats, tick, RaceBots = race()
		local bot = RaceBots.list[1]
		-- put the bot right behind the player
		bot.model:PivotTo(CFrame.new(0, 2, 528))
		for _, item in ipairs({ "Magnet", "Camera" }) do
			local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
			stats.slotAssignments[ItemConfig[item].slotType] = item
			R.expect(srv.mock.invoke(srv.RemoteEvents.RequestAbility, player, item)).toBe("ok")
			tick(0.2)
		end
		local hits = {}
		for _, ev in ipairs(srv.Telemetry.events("ability_target")) do hits[ev.item] = ev end
		R.expect(hits.Magnet and hits.Magnet.target).toBe(bot.id)
		R.expect(hits.Camera and hits.Camera.target).toBe(bot.id)
		R.expect(hits.Camera.bot).toBe(true)
		-- the effects really land on the bot's car
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		R.expect(VehicleTuning.has(bot.seat, "TurnSpeed", "steerDisable")).toBe(true)
		R.expect(VehicleTuning.has(bot.seat, "MaxSpeed", "magnetPull")).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
