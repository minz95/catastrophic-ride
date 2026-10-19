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

	R.it("a contest nobody presses in still ends when its time is up", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local item
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then item = d break end
		end
		local pos = item.Parent.Position
		a.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		b.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, item.Value)).toBe("contested")
		-- both players walk away without pressing
		srv.advance(5)
		R.expect(#srv.Telemetry.events("contest_result")).toBe(1)
		local got = #srv.SessionManager.getData(a).inventory + #srv.SessionManager.getData(b).inventory
		R.expect(got).toBe(1)
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

-- Steals with several players (Studio check 2026-10-20 found these by
-- reading FarmingManager; each case failed before the fix).
R.describe("steals with several players", function()
	local function setup(n)
		local srv = farmServer(n)
		for i, p in ipairs(srv.players) do
			p.Character.HumanoidRootPart.Position = Vector3.new(i, 3, 850)
			local d = srv.SessionManager.getData(p)
			d.inventory = { "Kettle", "Log" }
		end
		return srv
	end
	local function inv(srv, p) return #srv.SessionManager.getData(p).inventory end
	local function attempts(srv, result)
		local n = 0
		for _, e in ipairs(srv.Telemetry.events("steal_attempt")) do
			if result == nil or e.result == result then n += 1 end
		end
		return n
	end

	R.it("a DefendSteal sent before any attempt does not block the next steal", function()
		local srv = setup(2)
		local thief, victim = srv.players[1], srv.players[2]
		srv.mock.invoke(srv.RemoteEvents.DefendSteal, victim)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, victim.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, victim)).toBe(1)
		R.expect(inv(srv, thief)).toBe(3)
	end)

	R.it("one tap is not a defence; STEAL_DEFEND_PRESSES taps in the window are", function()
		local srv = setup(3)
		local thief, v1, v2 = srv.players[1], srv.players[2], srv.players[3]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, v1.UserId)
		srv.advance(0.2)
		srv.mock.invoke(srv.RemoteEvents.DefendSteal, v1)
		srv.advance(1.3)
		R.expect(inv(srv, v1)).toBe(1)

		srv.advance(10) -- thief cooldown
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, v2.UserId)
		srv.advance(0.2)
		for _ = 1, srv.env.requirePath("ReplicatedStorage.Shared.Constants").STEAL_DEFEND_PRESSES do
			srv.mock.invoke(srv.RemoteEvents.DefendSteal, v2)
		end
		srv.advance(1.3)
		R.expect(inv(srv, v2)).toBe(2)
		R.expect(attempts(srv, "defended")).toBe(1)
		R.expect(attempts(srv, "stolen")).toBe(1)
	end)

	R.it("a thief cannot run two steals at once", function()
		local srv = setup(3)
		local thief = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[2].UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[3].UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[3].UserId)
		srv.advance(1.5)
		R.expect(inv(srv, thief)).toBe(3)
		R.expect(inv(srv, srv.players[2]) + inv(srv, srv.players[3])).toBe(3)
	end)

	R.it("two thieves at one victim take one item; the victim is then protected", function()
		local srv = setup(3)
		local victim = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, srv.players[2], victim.UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, srv.players[3], victim.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, victim)).toBe(1)
		R.expect(attempts(srv, "stolen")).toBe(1)
	end)

	R.it("nobody can steal from themselves", function()
		local srv = setup(1)
		local p = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, p, p.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, p)).toBe(2)
		R.expect(attempts(srv, "stolen")).toBe(0)
	end)

	R.it("items are conserved: a steal moves an item, never copies or loses one", function()
		local srv = setup(4)
		local before = 0
		for _, p in ipairs(srv.players) do before += inv(srv, p) end
		for round = 1, 6 do
			for i, p in ipairs(srv.players) do
				local target = srv.players[(i + round - 1) % #srv.players + 1]
				srv.mock.invoke(srv.RemoteEvents.RequestSteal, p, target.UserId)
			end
			srv.advance(0.5)
			srv.mock.invoke(srv.RemoteEvents.DefendSteal, srv.players[round % 4 + 1])
			srv.advance(4)
		end
		local after = 0
		for _, p in ipairs(srv.players) do after += inv(srv, p) end
		R.expect(after).toBe(before)
		R.expect(attempts(srv, "stolen")).toBeGreaterThan(0)
	end)
end)

R.describe("crafting input from clients", function()
	local function craftServer()
		local srv = farmServer(2)
		srv.advance(60) -- FARMING → CRAFTING
		return srv
	end

	R.it("a malformed submission is refused without a server error", function()
		local srv = craftServer()
		local p = srv.players[1]
		local res = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, nil)
		srv.advance(0.1)
		R.expect(res).toBe("denied: bad slots")
		local res2 = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, "BODY")
		R.expect(res2).toBe("denied: bad slots")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("core slots only take items of their type; unknown slots are dropped", function()
		local srv = craftServer()
		local p = srv.players[1]
		local data = srv.SessionManager.getData(p)
		data.inventory = { "Kettle", "Log", "Trophy" } -- ENGINE, BODY, SPECIAL
		local res = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p,
			{ BODY = "Kettle", ENGINE = "Log", SPECIAL = "Trophy", WINGS = "Log" })
		R.expect(res).toBe("ok")
		local slots = data.vehicleStats.slotAssignments
		R.expect(slots.BODY).toBe(nil)
		R.expect(slots.ENGINE).toBe(nil)
		R.expect(slots.SPECIAL).toBe("Trophy")
		R.expect(slots.WINGS).toBe(nil)
		local craft = srv.Telemetry.events("craft")
		R.expect(#craft[#craft].rejected).toBe(3)
	end)

	R.it("one item cannot fill two slots", function()
		local srv = craftServer()
		local p = srv.players[1]
		local data = srv.SessionManager.getData(p)
		data.inventory = { "Log" }
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, { BODY = "Log", MOBILITY = "Log" })
		local slots = data.vehicleStats.slotAssignments
		local n = 0
		for _, v in pairs(slots) do if v == "Log" then n += 1 end end
		R.expect(n).toBe(1)
	end)

	R.it("players who do not submit get an auto craft, marked as such", function()
		local srv = craftServer()
		local a, b = srv.players[1], srv.players[2]
		srv.SessionManager.getData(a).inventory = { "Log" }
		srv.SessionManager.getData(b).inventory = { "Kettle" }
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, a, { BODY = "Log" })
		srv.advance(6) -- CRAFTING timer → RACING → auto submit
		local byUser = {}
		for _, e in ipairs(srv.Telemetry.events("craft")) do byUser[e.userId] = e end
		R.expect(byUser[a.UserId].auto).toBe(false)
		R.expect(byUser[b.UserId].auto).toBe(true)
		R.expect(byUser[b.UserId].slots.ENGINE).toBe("Kettle")
	end)
end)
