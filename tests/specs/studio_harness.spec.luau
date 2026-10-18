--!nocheck
-- Smoke tests for the Studio-only harness code (TestHarness.*). The mock has
-- no real physics, so these only prove the code runs end to end and returns
-- well-formed reports — they say nothing about how the car really drives.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local MatchSim = require("../lib/matchsim")

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
