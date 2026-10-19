--!nocheck
-- Smoke tests for the Studio-only harness code (TestHarness.*). The mock has
-- no real physics, so these only prove the code runs end to end and returns
-- well-formed reports — they say nothing about how the car really drives.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local MatchSim = require("../lib/matchsim")
local Vector3 = require("@lune/roblox").Vector3

R.describe("TestHarness.RaceSim (smoke, mock physics)", function()
	local env = Loader.boot()
	local RaceSim = env.requirePath("ServerScriptService.TestHarness.RaceSim")

	R.it("runs a short StepPhysics race and returns a report", function()
		local report = RaceSim.run({ profiles = { "average" }, seconds = 8, visibility = "intended", yieldEvery = 1e9 })
		R.expect(#report.results).toBe(1)
		local r = report.results[1]
		R.expect(r.engine).toBe("studio-stepphysics")
		R.expect(#r.samples).toBeGreaterThan(5)
		R.expect(r.maxProgress).toBeGreaterThan(50)
		R.expect(type(RaceSim.summarize(report))).toBe("string")
	end)

	for _, biome in ipairs({ "OCEAN", "SKY" }) do
		R.it("runs on " .. biome, function()
			local report = RaceSim.run({ biome = biome, profiles = { "average" }, seconds = 4, visibility = "intended", yieldEvery = 1e9 })
			R.expect(#report.results).toBe(1)
			R.expect(#report.results[1].samples).toBeGreaterThan(3)
			R.expect(RaceSim.summarize(report):find("RaceSim " .. biome) ~= nil).toBe(true)
		end)
	end

	-- Studio 2026-10-20: the MapBuilders script replaced the map RaceSim had
	-- built, checkpoint triggers included, and no car could finish.
	R.it("in a running session it races on the server's map instead of building a copy", function()
		local SSS = env.game.ServerScriptService
		local built = {}
		for _, b in ipairs({ "Forest", "Ocean", "Sky" }) do
			built[b] = env.requirePath("ServerScriptService.Modules.Maps." .. b .. "Map").build()
			SSS:SetAttribute("MapBuilt_" .. b:upper(), true)
		end
		local map = RaceSim.prepareMap("OCEAN", "shipped", "heartbeat")
		R.expect(map == built.Ocean).toBe(true)
		R.expect(built.Ocean.Parent ~= nil).toBe(true)
		-- the other maps (same world coordinates) must not collide
		local solid = {}
		for _, d in ipairs(built.Forest:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then table.insert(solid, d.Name) if #solid > 3 then break end end
		end
		R.expect(solid).toBeEmpty("solid ForestMap parts during an OCEAN race")
	end)

	R.it("escape cases cover every biome, start on the lane and face the stated way", function()
		local TG = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
		for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
			local track = env.requirePath("ReplicatedStorage.Shared.Tracks." .. biome:sub(1, 1) .. biome:sub(2):lower() .. "Track")
			local geo = TG.new(track.nodes, track.width)
			local cases = RaceSim.escapeCases(biome, track)
			R.expect(#cases).toBeGreaterThan(8)
			local off = {}
			for _, c in ipairs(cases) do
				local x, z = geo:offsetPoint(c.spawn.s, c.spawn.lateral)
				local d = geo:project(x, z).dist
				if d > track.width / 2 then table.insert(off, string.format("%s %s %.0f studs off", biome, c.label, d)) end
			end
			R.expect(off).toBeEmpty("escape spawns outside the lane")
		end
	end)

	R.it("Runner.runEscape runs one car per case and summarizes them", function()
		local Runner = env.requirePath("ServerScriptService.TestHarness.Runner")
		local summary, json = Runner.runEscape({ biome = "FOREST", seconds = 0.5, yieldEvery = 1e9 })
		R.expect(summary:find("cases %d+: drove out") ~= nil).toBe(true)
		R.expect(json:find("wall%-left@150") ~= nil).toBe(true)
	end)

	R.it("Runner.runRace returns a summary and JSON", function()
		local Runner = env.requirePath("ServerScriptService.TestHarness.Runner")
		local summary, json = Runner.runRace({ profiles = { "novice" }, seconds = 3, yieldEvery = 1e9 })
		R.expect(summary:find("RaceSim FOREST") ~= nil).toBe(true)
		R.expect(json:sub(1, 1)).toBe("{")
	end)
end)

R.describe("TestHarness.MatchHarness (smoke, real server scripts)", function()
	R.it("ends the test with a report after one round", function()
		local ended
		local srv = Server.boot({
			players = 3,
			swallowErrors = true,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.MapManager",
				"ServerScriptService.FarmingManager",
				"ServerScriptService.CraftingManager",
				"ServerScriptService.RacingManager",
			},
			harness = { harness = "match", biome = "FOREST", players = 3, lobbyDelay = 0, rounds = 1,
				durations = { FARMING = 5, CRAFTING = 2, RACING = 5, RESULTS = 1 } },
		})
		local MatchHarness = srv.env.requirePath("ServerScriptService.TestHarness.MatchHarness")
		MatchHarness.start(srv.GameManager.getHarness(), function(result) ended = result end)
		srv.advance(30, 0.5, function() end)
		R.expect(ended ~= nil).toBe(true)
		R.expect(#ended.rounds).toBe(1)
		R.expect(#ended.rounds[1].players).toBe(3)
		R.expect(type(ended.summary)).toBe("string")
		for _, p in ipairs(srv.players) do
			R.expect(p:GetAttribute("HarnessBot")).toBe(true)
		end
		R.expect(srv.mock.errors).toBeEmpty("server script errors during the match")
	end)
end)

R.describe("TestHarness.MatchHarness farming / crafting report", function()
	R.it("stopAfter CRAFTING ends at the race start with farm and craft stats", function()
		local ended
		local srv = Server.boot({
			players = 3,
			swallowErrors = true,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.MapManager",
				"ServerScriptService.FarmingManager",
				"ServerScriptService.CraftingManager",
			},
			harness = { harness = "match", biome = "FOREST", players = 3, lobbyDelay = 0, rounds = 1, stopAfter = "CRAFTING",
				durations = { FARMING = 6, CRAFTING = 2, RACING = 60, RESULTS = 1 } },
		})
		local MatchHarness = srv.env.requirePath("ServerScriptService.TestHarness.MatchHarness")
		MatchHarness.start(srv.GameManager.getHarness(), function(result) ended = result end)
		srv.advance(1)
		local a, b = srv.players[1], srv.players[2]
		srv.SessionManager.getData(a).inventory = {}
		srv.SessionManager.getData(b).inventory = { "Log" }
		a.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 850)
		b.Character.HumanoidRootPart.Position = Vector3.new(2, 3, 850)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, a, b.UserId)
		srv.advance(20, 0.5, function() end)
		R.expect(ended ~= nil).toBe(true)
		R.expect(ended.endReason).toBe("stopAfter CRAFTING")
		local r = ended.rounds[1]
		R.expect(r.farm.attempts.stolen).toBe(1)
		R.expect(r.farm.players[tostring(a.UserId)].stolen).toBe(1)
		R.expect(#r.craft[tostring(a.UserId)].rejected).toBe(0)
		R.expect(r.craft[tostring(a.UserId)].auto).toBe(true)
		R.expect(ended.summary:find("steal attempts: stolen=1") ~= nil).toBe(true)
	end)
end)

R.describe("BotBrain.pickVictim", function()
	local env = Loader.boot()
	local BotBrain = env.requirePath("ReplicatedStorage.Shared.BotBrain")
	local others = { { userId = 1, x = 3, z = 0, items = 2 }, { userId = 2, x = 30, z = 0, items = 2 }, { userId = 3, x = 1, z = 0, items = 0 } }
	R.it("picks the nearest player with items in reach; hunters reach further", function()
		R.expect(BotBrain.pickVictim(BotBrain.PROFILES.casual, { x = 0, z = 0, items = 1 }, others).userId).toBe(1)
		R.expect(BotBrain.pickVictim(BotBrain.PROFILES.casual, { x = 20, z = 0, items = 1 }, others)).toBe(nil)
		R.expect(BotBrain.pickVictim(BotBrain.PROFILES.sweaty, { x = 20, z = 0, items = 1 }, others).userId).toBe(2)
	end)
	R.it("never when the bot cannot steal or is full", function()
		R.expect(BotBrain.pickVictim(BotBrain.PROFILES.afk, { x = 0, z = 0, items = 1 }, others)).toBe(nil)
		R.expect(BotBrain.pickVictim(BotBrain.PROFILES.sweaty, { x = 0, z = 0, items = 8 }, others)).toBe(nil)
	end)
end)
