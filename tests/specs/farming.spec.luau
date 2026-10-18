--!nocheck
-- FARMING and CRAFTING with the real server scripts and bots.
local R = require("../lib/runner")
local Server = require("../lib/server")
local MatchSim = require("../lib/matchsim")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

R.describe("farming match (6 bots, real FarmingManager/CraftingManager)", function()
	local m = MatchSim.run({ players = 6, seed = 11 })

	R.it("runs without server script errors", function()
		R.expect(m.serverErrors).toBeEmpty("errors raised inside server scripts")
	end)

	R.it("every bot collects items and gets a car", function()
		local bad = {}
		for _, p in ipairs(m.results) do
			if #p.inventory == 0 then table.insert(bad, p.name .. " collected nothing") end
			if not p.maxSpeed then table.insert(bad, p.name .. " has no car") end
		end
		R.expect(bad).toBeEmpty("bots without items or cars")
	end)

	R.it("pickups never exceed the 100 spawned items", function()
		local total = 0
		for _, p in ipairs(m.results) do total += p.farm.pickups end
		R.expect(total).toBeAtMost(100)
	end)
end)

-- Small focused scenarios on a bare server.
local function farmServer(nPlayers)
	local srv = Server.boot({
		players = nPlayers,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = nPlayers, lobbyDelay = 0,
			durations = { FARMING = 60, CRAFTING = 5, RACING = 600 } },
	})
	srv.advance(0.5)
	return srv
end

R.describe("farming rules", function()
	R.it("two players at one item get a contest that resolves to one winner", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local item
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then item = d break end
		end
		local pos = item.Parent.Position
		a.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		b.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		local res = srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, item.Value)
		R.expect(res).toBe("contested")
		for i = 1, 30 do
			srv.advance(0.1)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, a, item.Value, i * 2)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, b, item.Value, i)
		end
		local results = srv.Telemetry.events("contest_result")
		R.expect(#results).toBe(1)
		R.expect(results[1].winner).toBe(a.UserId)
		R.expect(#srv.SessionManager.getData(a).inventory).toBe(1)
		R.expect(#srv.SessionManager.getData(b).inventory).toBe(0)
	end)

	R.it("a steal never pushes the thief past the 8-slot inventory",
		function()
			local srv = farmServer(2)
			local thief, victim = srv.players[1], srv.players[2]
			local td, vd = srv.SessionManager.getData(thief), srv.SessionManager.getData(victim)
			for i = 1, 8 do td.inventory[i] = "Pizza" end
			vd.inventory[1] = "Kettle"
			thief.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 850)
			victim.Character.HumanoidRootPart.Position = Vector3.new(2, 3, 850)
			srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, victim.UserId)
			srv.advance(1.5)
			R.expect(#td.inventory).toBeAtMost(8)
		end)

	R.it("auto-submit puts items in matching slots",
		function()
			local srv = farmServer(1)
			local p = srv.players[1]
			local data = srv.SessionManager.getData(p)
			srv.advance(60) -- FARMING ends → CRAFTING
			data.inventory = { "Kettle", "Trophy", "Log" } -- ENGINE, SPECIAL, BODY
			srv.advance(6) -- CRAFTING timer expires → auto-submit
			local slots = data.vehicleStats and data.vehicleStats.slotAssignments or {}
			local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
			local wrong = {}
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				local item = slots[slot]
				if item and ItemConfig[item].slotType ~= slot then
					table.insert(wrong, slot .. " ← " .. item .. " (" .. ItemConfig[item].slotType .. ")")
				end
			end
			R.expect(wrong).toBeEmpty("auto-assigned items in the wrong slot")
		end)
end)
