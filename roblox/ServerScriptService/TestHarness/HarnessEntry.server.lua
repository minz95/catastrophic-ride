-- HarnessEntry.server.lua
-- Starts a harness inside a StudioTestService session. In live servers and in
-- ordinary Studio playtests HarnessConfig returns nil and this script exits.

local ServerScriptService = game:GetService("ServerScriptService")

local HarnessConfig = require(ServerScriptService.Modules.HarnessConfig)

local args = HarnessConfig.get()
if not args then return end

local function endTest(result)
	local ok, sts = pcall(function() return game:GetService("StudioTestService") end)
	if ok and sts then
		sts:EndTest(result)
	else
		warn("[HarnessEntry] StudioTestService unavailable; result:", result)
	end
end

if args.harness == "race" then
	local RaceSim = require(ServerScriptService.TestHarness.RaceSim)
	local opts = args.race or {}
	opts.mode = "heartbeat"
	local ok, report = pcall(RaceSim.run, opts)
	if ok then
		report.summary = RaceSim.summarize(report)
		print(report.summary)
		endTest(report)
	else
		warn("[HarnessEntry] RaceSim failed:", report)
		endTest({ error = tostring(report) })
	end

elseif args.harness == "match" then
	require(ServerScriptService.TestHarness.MatchHarness).start(args, endTest)
end
