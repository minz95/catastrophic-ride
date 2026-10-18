-- Runner.lua
-- Entry points for running the Studio test harness from a plugin, the
-- command bar, or an AI agent through the Roblox Studio MCP server.
--
-- From MCP (run_code / execute_luau), in EDIT mode:
--
--   local Runner = require(game.ServerScriptService.TestHarness.Runner)
--   return Runner.runRace({ profiles = { "average" }, seconds = 120 })
--   return Runner.runRace({ mode = "run", visibility = "intended" })
--   return Runner.runMatch({ players = 4, rounds = 1 })
--
-- Every function returns a compact text summary first and the full report as
-- JSON second, so an agent can read the summary and parse the JSON.
--
-- Modes
--   runRace{ mode = "step" } (default) – edit mode, StepPhysics, faster than
--       real time. Note: Studio caches require() results in edit mode, so
--       after changing game code use mode = "run" (fresh session) or reopen
--       the place.
--   runRace{ mode = "run" } – StudioTestService:ExecuteRunModeAsync: a fresh
--       server-only session (latest code), physics in real time.
--   runMatch{} – StudioTestService:ExecuteMultiplayerTestAsync: a server plus
--       N real clients driven by BotDriver through the whole game loop.

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local Runner = {}

local function encode(t)
	local ok, s = pcall(function() return HttpService:JSONEncode(t) end)
	return ok and s or ("{\"error\":\"JSON encode failed: " .. tostring(s) .. "\"}")
end

local function studioTestService()
	local ok, sts = pcall(function() return game:GetService("StudioTestService") end)
	assert(ok and sts, "StudioTestService is not available (Studio only)")
	return sts
end

--- Single-car race simulation. See RaceSim.runOne for options.
function Runner.runRace(opts)
	opts = opts or {}
	if opts.mode == "run" then
		local args = { harness = "race", autoStart = false, race = opts }
		args.race.mode = "heartbeat"
		local report = studioTestService():ExecuteRunModeAsync(args)
		if type(report) ~= "table" then
			return "RaceSim run-mode session returned nothing (did HarnessEntry run?)", "{}"
		end
		local RaceSim = require(ServerScriptService.TestHarness.RaceSim)
		return report.summary or RaceSim.summarize(report), encode(report)
	end
	local RaceSim = require(ServerScriptService.TestHarness.RaceSim)
	local o = table.clone(opts)
	o.mode = "step"
	local report = RaceSim.run(o)
	return RaceSim.summarize(report), encode(report)
end

--- Full multiplayer match with bot clients.
-- opts: { players = 4, rounds = 1, biome = "FOREST",
--         durations = { FARMING = 60, CRAFTING = 20, RACING = 180, RESULTS = 5 },
--         farmProfiles = { "sweaty", "casual" }, driverProfiles = { "expert", "average", "novice" },
--         maxSeconds = 600 }
function Runner.runMatch(opts)
	opts = opts or {}
	local players = opts.players or 4
	local args = {
		harness = "match",
		biome = opts.biome or "FOREST",
		players = players,
		rounds = opts.rounds or 1,
		lobbyDelay = 3,
		joinTimeout = 90,
		durations = opts.durations or { FARMING = 60, CRAFTING = 20, RACING = 180, RESULTS = 5 },
		maxSeconds = opts.maxSeconds or 900,
		bots = {
			farmProfiles = opts.farmProfiles or { "sweaty", "casual" },
			driverProfiles = opts.driverProfiles or { "expert", "average", "novice" },
		},
	}
	local report = studioTestService():ExecuteMultiplayerTestAsync(players, args)
	if type(report) ~= "table" then
		return "Match session returned nothing (did MatchHarness end the test?)", "{}"
	end
	local MatchHarness = require(ServerScriptService.TestHarness.MatchHarness)
	return MatchHarness.summarize(report), encode(report)
end

return Runner
