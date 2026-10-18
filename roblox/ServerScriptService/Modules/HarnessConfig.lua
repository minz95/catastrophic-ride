-- HarnessConfig.lua
-- Test-harness switches for the server. Returns nil in normal play, so live
-- servers and ordinary Studio playtests behave exactly as before.
--
-- Sources, first match wins:
--   1. ServerScriptService attribute "HarnessArgs" (JSON string). Lets an
--      offline test or a developer force harness mode without Studio APIs.
--   2. StudioTestService:GetTestArgs() — the args table that
--      TestHarness.Runner passes to ExecuteMultiplayerTestAsync /
--      ExecuteRunModeAsync. Studio only. GetTestArgs is known to return nil
--      for a moment right after the session starts, so it is polled briefly.
--
-- Recognised fields (all optional):
--   harness     = "match" | "race"   which harness is running
--   autoStart   = false              GameManager does not start the loop
--   biome       = "FOREST"           force the biome every round
--   players     = 4                  wait for this many players before FARMING
--   joinTimeout = 60                 give up waiting for players after N s
--   lobbyDelay  = 3                  seconds between players ready and FARMING
--   durations   = { FARMING = 30, CRAFTING = 10, RACING = 120, RESULTS = 3 }
--   rounds      = 1                  MatchHarness ends the test after N rounds
--   bots        = { skill = 0.7, ... } forwarded to BotDriver

local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local HarnessConfig = {}

local POLL_SECONDS = 2
local POLL_STEP    = 0.1

local _resolved = false
local _value    = nil

local function fromAttribute()
	local raw = ServerScriptService:GetAttribute("HarnessArgs")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and type(decoded) == "table" then
		return decoded
	end
	warn("[HarnessConfig] HarnessArgs attribute is not valid JSON; ignoring")
	return nil
end

local function fromStudioTestService()
	if not RunService:IsStudio() then
		return nil
	end
	local ok, sts = pcall(function()
		return game:GetService("StudioTestService")
	end)
	if not ok or not sts then
		return nil
	end
	local waited = 0
	while waited < POLL_SECONDS do
		local okArgs, args = pcall(function()
			return sts:GetTestArgs()
		end)
		if okArgs and type(args) == "table" and args.harness then
			return args
		end
		task.wait(POLL_STEP)
		waited += POLL_STEP
	end
	return nil
end

--- Returns the harness args table, or nil in normal play. May yield up to
-- POLL_SECONDS the first time it is called inside Studio.
function HarnessConfig.get()
	if _resolved then
		return _value
	end
	_value = fromAttribute() or fromStudioTestService()
	_resolved = true
	if _value then
		print("[HarnessConfig] Harness mode:", _value.harness or "custom")
	end
	return _value
end

--- Non-yielding read: nil until get() has resolved.
function HarnessConfig.peek()
	return _value
end

return HarnessConfig
