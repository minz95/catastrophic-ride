--!nocheck
-- Unusual sessions (issue #54) and crowded pickups (issue #42) with the real
-- server scripts: solo play, players leaving or joining mid-round, ten
-- players on one item, a hundred items for ten players.
local R = require("../lib/runner")
local Server = require("../lib/server")
local MatchSim = require("../lib/matchsim")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function farmServer(n, durations)
	local srv = Server.boot({
		players = n,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = n, lobbyDelay = 0,
			durations = durations or { FARMING = 120, CRAFTING = 5, RACING = 600 } },
	})
	srv.advance(0.5)
	return srv
end

local function items(srv)
	local out = {}
	for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
		if d.Name == "ItemId" then table.insert(out, d) end
	end
	return out
end

local function at(player, pos)
	player.Character.HumanoidRootPart.Position = pos
end

R.describe("crowded pickups (#42)", function()
	R.it("ten players asking for one item at once: one contest, one owner, one pickup", function()
		local srv = farmServer(10)
		local item = items(srv)[1]
		local pos = item.Parent.Position
		for i, p in ipairs(srv.players) do
			at(p, pos + Vector3.new(math.cos(i) * 3, 2, math.sin(i) * 3))
		end
		local replies = {}
		for _, p in ipairs(srv.players) do
			table.insert(replies, (srv.invoke("RequestPickup", p, item.Value)))
		end
		srv.advance(6)
		local owners = 0
		for _, e in ipairs(srv.Telemetry.events("item_pickup")) do
			if e.itemId == item.Value then owners += 1 end
		end
		R.expect(owners).toBe(1)
		R.expect(#srv.Telemetry.events("contest_result")).toBe(1)
		for _, r in ipairs(replies) do R.expect(r == "contested" or r == "ok").toBe(true) end
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("while a contest runs, nobody else can take the item, even after the two walk away", function()
		local srv = farmServer(3)
		local a, b, c = srv.players[1], srv.players[2], srv.players[3]
		local item = items(srv)[1]
		local pos = item.Parent.Position
		at(a, pos + Vector3.new(2, 2, 0))
		at(b, pos + Vector3.new(-2, 2, 0))
		at(c, pos + Vector3.new(0, 2, 60))
		R.expect(srv.invoke("RequestPickup", a, item.Value)).toBe("contested")
		at(a, pos + Vector3.new(80, 2, 0))
		at(b, pos + Vector3.new(-80, 2, 0))
		at(c, pos + Vector3.new(0, 2, 2))
		R.expect(srv.invoke("RequestPickup", c, item.Value)).toBe("contested")
		srv.advance(6)
		local res = srv.Telemetry.events("contest_result")
		R.expect(#res).toBe(1)
		local pick = srv.Telemetry.events("item_pickup")
		R.expect(#pick).toBe(1)
		R.expect(pick[1].userId).toBe(res[1].winner)
	end)

	R.it("if the contest winner left, the other contestant gets the item", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local item = items(srv)[1]
		local pos = item.Parent.Position
		at(a, pos + Vector3.new(2, 2, 0))
		at(b, pos + Vector3.new(-2, 2, 0))
		srv.invoke("RequestPickup", a, item.Value)
		for i = 1, 5 do srv.invoke("RequestContest", a, item.Value, i * 3) end
		srv.mock.removePlayer(a)
		srv.advance(6)
		local pick = srv.Telemetry.events("item_pickup")
		R.expect(#pick).toBe(1)
		R.expect(pick[1].userId).toBe(b.UserId)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("ten players grabbing a hundred items: every item has at most one owner, inventories add up", function()
		local srv = farmServer(10)
		local all = items(srv)
		R.expect(#all).toBeGreaterThan(20)
		for round = 1, 4 do
			for i, it in ipairs(all) do
				if it.Parent then
					local p = srv.players[((i + round) % 10) + 1]
					at(p, it.Parent.Position + Vector3.new(0, 2, 0))
					srv.invoke("RequestPickup", p, it.Value)
				end
			end
			srv.advance(6)
		end
		local seen, dup = {}, {}
		for _, e in ipairs(srv.Telemetry.events("item_pickup")) do
			if seen[e.itemId] then table.insert(dup, e.itemId) end
			seen[e.itemId] = true
		end
		R.expect(dup).toBeEmpty("items picked twice")
		local held = 0
		for _, p in ipairs(srv.players) do
			local inv = srv.SessionManager.getData(p).inventory
			R.expect(#inv <= 8).toBe(true)
			held += #inv
		end
		local picks = #srv.Telemetry.events("item_pickup")
		local dropped = #srv.Telemetry.events("item_drop")
		R.expect(held).toBe(picks - dropped)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("unusual sessions (#54)", function()
	R.it("one player alone farms, crafts and drives a whole race", function()
		local m = MatchSim.run({ players = 1, seed = 5, farming = 30 })
		R.expect(m.serverErrors).toBeEmpty("server errors")
		R.expect(#m.results).toBe(1)
		R.expect(m.results[1].maxSpeed ~= nil).toBe(true)
		R.expect(m.results[1].race.finished).toBe(true)
	end)

	R.it("a player with nothing farmed and nothing placed gets the default car", function()
		local srv = farmServer(1, { FARMING = 0.5, CRAFTING = 0.5, RACING = 600 })
		srv.advance(3)
		local data = srv.SessionManager.getData(srv.players[1])
		R.expect(#data.inventory).toBe(0)
		R.expect(data.vehicleModel ~= nil).toBe(true)
		R.expect(data.vehicleStats ~= nil).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a full inventory with only some slots placed still builds a car from what was placed", function()
		local srv = farmServer(1, { FARMING = 0.5, CRAFTING = 2, RACING = 600 })
		local p = srv.players[1]
		local data = srv.SessionManager.getData(p)
		data.inventory = { "Barrel", "Log", "Fan", "Rocket", "Pizza", "Trophy", "Kite", "Compass" }
		srv.advance(1)
		R.expect(srv.GameManager.getPhase()).toBe("CRAFTING")
		local res = srv.invoke("SubmitCraft", p, { ENGINE = "Rocket" })
		R.expect(type(res) == "string" and res:sub(1, 2) == "ok").toBe(true)
		srv.advance(3)
		R.expect(data.vehicleModel ~= nil).toBe(true)
		R.expect(data.vehicleStats.slotAssignments.ENGINE).toBe("Rocket")
	end)
end)

-- Racing with real RacingManager: cars are given, checkpoints touched by hand.
local function raceServer(n)
	local srv = Server.boot({
		players = n,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = n, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 2 } },
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
	local cars = {}
	for i, p in ipairs(srv.players) do
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
		cars[i] = model
	end
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RACING")
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	srv.advance(C.RACE_COUNTDOWN + 0.5)
	local function finish(i)
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			srv.mock.CollectionService:GetTagged(tag)[1].Touched:Fire(cars[i].PrimaryPart)
			srv.advance(0.1)
		end
	end
	return srv, cars, finish, C
end

R.describe("who races (Studio load-8p, 2026-10-23)", function()
	-- CraftingManager builds cars just after RACING begins; counting cars at
	-- that moment found one and ended the race at the first finish.
	local function lateCars(n, withCar)
		local srv = Server.boot({
			players = n,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = n, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 5 } },
		})
		local e = srv.env
		local C = e.requirePath("ReplicatedStorage.Shared.Constants")
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
		srv.advance(0.25)
		assert(srv.GameManager.getPhase() == "RACING")
		local cars = {}
		for i, p in ipairs(srv.players) do
			if withCar[i] then
				local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
				model.Parent = e.workspace
				srv.SessionManager.setVehicle(p, model, stats)
				cars[i] = model
			end
		end
		srv.advance(C.RACE_COUNTDOWN + 0.5)
		local function finish(i)
			for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
				srv.mock.CollectionService:GetTagged(tag)[1].Touched:Fire(cars[i].PrimaryPart)
				srv.advance(0.1)
			end
		end
		return srv, finish, C
	end

	R.it("cars built just after RACING starts all race: the first finish starts the grace, not the results", function()
		local srv, finish = lateCars(3, { true, true, true })
		finish(1)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		finish(2)
		finish(3)
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
	end)

	R.it("someone still without a car at GO watches and is not waited for", function()
		local srv, finish = lateCars(3, { true, true, false })
		R.expect(srv.players[3]:GetAttribute("Spectating")).toBe(true)
		finish(1)
		finish(2)
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("leaving and joining during a race (#54)", function()
	R.it("a solo race ends at the finish and shows the results", function()
		local srv, _, finish = raceServer(1)
		finish(1)
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a racer who leaves is not waited for: the others finishing ends the race at once", function()
		local srv, cars, finish = raceServer(3)
		srv.mock.removePlayer(srv.players[3])
		R.expect(cars[3].Parent).toBe(nil)    -- their car is cleaned up
		finish(1)
		finish(2)
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("everyone leaving mid-race: the race still ends on its timer and the server goes back to the lobby", function()
		local srv, _, _, C = raceServer(2)
		for _, p in ipairs(table.clone(srv.players)) do srv.mock.removePlayer(p) end
		srv.advance(C.RACING_TIMEOUT + 10)
		local phase = srv.GameManager.getPhase()
		R.expect(phase == "LOBBY" or phase == "RESULTS").toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("someone joining mid-race watches (marked Spectating), is not waited for, and plays the next round", function()
		local srv, _, finish = raceServer(2)
		local late = srv.mock.addPlayer("Late", 9001, Vector3.new(0, 3, 0))
		srv.advance(0.5)
		R.expect(late:GetAttribute("Spectating")).toBe(true)
		finish(1)
		finish(2)
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local calls = rawget(srv.RemoteEvents.RaceFinished, "_calls")
		for _, entry in ipairs(calls[#calls].args[1]) do
			R.expect(entry.userId ~= late.UserId).toBe(true)
		end
		local atFarming = nil
		srv.GameManager.onPhaseChanged(function(phase)
			if phase == "FARMING" and atFarming == nil then atFarming = late:GetAttribute("Spectating") end
		end)
		srv.advance(5)   -- RESULTS → LOBBY → FARMING of round 2
		R.expect(srv.GameManager.getRound()).toBe(2)
		R.expect(atFarming).toBe(false)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
