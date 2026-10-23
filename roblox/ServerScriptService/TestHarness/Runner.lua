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
-- From the command line (no MCP, no open Studio window): tools/studio/sim.py
-- runs saved scenarios through `RobloxStudio -task RunScript`.
--
-- Modes
--   runRace{ mode = "step" } (default) – edit mode, StepPhysics, faster than
--       real time. Note: Studio caches require() results in edit mode, so
--       after changing game code use mode = "run" (fresh session) or reopen
--       the place.
--   runRace{ mode = "run" } – StudioTestService:ExecuteRunModeAsync: a fresh
--       server-only session (latest code), physics in real time. The only
--       mode that works under `-task RunScript` (StepPhysics crashes Studio
--       there).
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

-- Seconds a session must last to count as a real run (see startSession).
Runner.MIN_SESSION_SECONDS = 5
Runner.SESSION_ATTEMPTS = 4

--- Starts a test session and returns its EndTest result.
-- The args also go into the ServerScriptService "HarnessArgs" attribute,
-- which the session's copy of the place inherits: GetTestArgs can return nil
-- for several seconds at session start (HarnessConfig polls only briefly, so
-- the game used to fall through to an ordinary LOBBY and hang). The attribute
-- is removed again when the session ends.
-- Right after a place opens (command line `-task RunScript`), the first
-- session can end at once with no result; that is retried.
local function startSession(args, run)
	local attr = HttpService:JSONEncode(args)
	local result
	for attempt = 1, Runner.SESSION_ATTEMPTS do
		ServerScriptService:SetAttribute("HarnessArgs", attr)
		local t0 = os.clock()
		local ok, res = pcall(run)
		ServerScriptService:SetAttribute("HarnessArgs", nil)
		if not ok then error(res, 0) end
		result = res
		if type(res) == "table" or os.clock() - t0 >= Runner.MIN_SESSION_SECONDS then
			break
		end
		warn(string.format("[Runner] session ended after %.1fs with no result; retrying (%d/%d)",
			os.clock() - t0, attempt, Runner.SESSION_ATTEMPTS))
		task.wait(3)
	end
	return result
end

--- Single-car race simulation. See RaceSim.runOne for options.
function Runner.runRace(opts)
	opts = opts or {}
	if opts.mode == "run" then
		local race = table.clone(opts)
		race.mode = "heartbeat"
		local args = { harness = "race", autoStart = false, race = race }
		local sts = studioTestService()
		local report = startSession(args, function() return sts:ExecuteRunModeAsync(args) end)
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

--- Escape test: a car dropped at every spot where drivers get stuck (nose in
-- the wall, facing backwards, on ramps / mud / drift corners) must drive
-- RaceSim.ESCAPE_GAIN studs on. opts as runRace plus { biome, profiles = { "average" } }.
function Runner.runEscape(opts)
	local o = table.clone(opts or {})
	o.cases = "escape"
	return Runner.runRace(o)
end

--- Audio check (edit mode): every SoundConfig id loads as a real Sound;
-- opts.search looks up Creator Store audio. See TestHarness/SoundCheck.
function Runner.runSounds(opts)
	local SoundCheck = require(ServerScriptService.TestHarness.SoundCheck)
	local report = SoundCheck.run(opts)
	return SoundCheck.summarize(report), encode(report)
end

--- Which engine members exist (edit mode): opts.members = { "AnalyticsService.LogEconomyEvent",
-- "Enum.AnalyticsEconomyFlowType.Source", ... } → { [name] = true | "missing: <error>" }.
function Runner.probeApi(opts)
	local out = {}
	for _, name in ipairs((opts or {}).members or {}) do
		local ok, err = pcall(function()
			local parts = string.split(name, ".")
			local v
			if parts[1] == "Enum" then
				v = Enum
			else
				v = game:GetService(parts[1])
			end
			for i = 2, #parts do v = v[parts[i]] end
			assert(v ~= nil, "nil")
		end)
		out[name] = ok or ("missing: " .. tostring(err))
	end
	local missing = 0
	for _, v in pairs(out) do if v ~= true then missing += 1 end end
	return string.format("probeApi: %d members, %d missing", #((opts or {}).members or {}), missing), encode({ kind = "probe", members = out })
end

--- Full multiplayer match with bot clients.
-- opts: { players = 4, rounds = 1, biome = "FOREST",
--         durations = { FARMING = 60, CRAFTING = 20, RACING = 240, RESULTS = 5 },
--         farmProfiles = { "sweaty", "casual" }, driverProfiles = { "expert", "average", "novice" },
--         maxSeconds = 600, stopAfter = "CRAFTING",
--         loadouts = { { { SPECIAL = "Pizza", ENGINE = "Rocket", BODY = "Log" }, ... }, ... } }
function Runner.runMatch(opts)
	opts = opts or {}
	local players = opts.players or 4
	local args = {
		harness = "match",
		biome = opts.biome or "FOREST",
		players = players,
		rounds = opts.rounds or 1,
		lobbyDelay = 3,
		joinTimeout = opts.joinTimeout or 90,
		stopAfter = opts.stopAfter,   -- "CRAFTING": end when the race would start
		durations = opts.durations or { FARMING = 60, CRAFTING = 20, RACING = 240, RESULTS = 5 },
		maxSeconds = opts.maxSeconds or 900,
		-- loadouts[round][botIndex] = slots: crafted as given (CraftingManager),
		-- whatever the bot farmed. For ability experiments.
		loadouts = opts.loadouts,
		bots = {
			farmProfiles = opts.farmProfiles or { "sweaty", "casual" },
			driverProfiles = opts.driverProfiles or { "expert", "average", "novice" },
		},
	}
	local sts = studioTestService()
	local report = startSession(args, function() return sts:ExecuteMultiplayerTestAsync(players, args) end)
	if type(report) ~= "table" then
		return "Match session returned nothing (did MatchHarness end the test?)", "{}"
	end
	local MatchHarness = require(ServerScriptService.TestHarness.MatchHarness)
	return MatchHarness.summarize(report), encode(report)
end

return Runner
