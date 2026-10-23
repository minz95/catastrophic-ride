-- AnalyticsManager.server.lua
-- Turns Telemetry events into Roblox AnalyticsService events (Modules/
-- Analytics): the onboarding funnel for a player's first round ever, the
-- "Round" funnel every round, coins earned, levels and the day a player came
-- back on. Off in Studio and harness sessions.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require(ServerScriptService.Modules.Analytics)
local GameManager = require(ServerScriptService.GameManager)
local HarnessConfig = require(ServerScriptService.Modules.HarnessConfig)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

Analytics.enabled = not RunService:IsStudio() and HarnessConfig.get() == nil

local ONBOARDING = { "Joined", "First pickup", "Car built", "Raced", "Finished a race", "Got a reward" }
local ROUND = { "Farming", "Crafting", "Car built", "Racing", "Finished", "Results" }

-- one funnel session per server and round
local JOB_ID = (function()
	local ok, id = pcall(function() return game.JobId end)
	return ok and id or ""
end)()

local _onboardNext = {}   -- userId → next onboarding step (only for players with no round yet)
local _roundStep = {}     -- userId → last Round funnel step logged this round

local function onboard(player, step)
	local nextStep = _onboardNext[player.UserId]
	if not nextStep or step < nextStep then return end
	_onboardNext[player.UserId] = step + 1
	Analytics.onboarding(player, step, ONBOARDING[step])
	if step == #ONBOARDING then _onboardNext[player.UserId] = nil end
end

local function roundStep(player, step)
	if (_roundStep[player.UserId] or 0) >= step then return end
	_roundStep[player.UserId] = step
	Analytics.funnelStep(player, "Round", JOB_ID .. "-" .. tostring(GameManager.getRound()), step, ROUND[step])
end

local function byId(userId)
	return userId and Players:GetPlayerByUserId(userId)
end

local function joined(player, rec)
	if (rec.rounds or 0) == 0 and not _onboardNext[player.UserId] then
		_onboardNext[player.UserId] = 1
		onboard(player, 1)
	end
end
PlayerStore.onLoaded(joined)
-- players whose record loaded before this script started
for _, p in ipairs(Players:GetPlayers()) do
	local rec = PlayerStore.get(p)
	if rec then joined(p, rec) end
end

Players.PlayerRemoving:Connect(function(player)
	_onboardNext[player.UserId] = nil
	_roundStep[player.UserId] = nil
end)

Telemetry.onRecord(function(kind, e)
	if kind == "phase" then
		if e.phase == "FARMING" then
			_roundStep = {}
			for _, p in ipairs(Players:GetPlayers()) do roundStep(p, 1) end
		elseif e.phase == "CRAFTING" then
			for _, p in ipairs(Players:GetPlayers()) do roundStep(p, 2) end
		end
	elseif kind == "item_pickup" then
		local p = byId(e.userId)
		if p then onboard(p, 2) end
	elseif kind == "craft" then
		local p = byId(e.userId)
		if p then onboard(p, 3); roundStep(p, 3) end
	elseif kind == "race_start" then
		for _, uid in ipairs(e.racers or {}) do
			local p = byId(uid)
			if p then onboard(p, 4); roundStep(p, 4) end
		end
	elseif kind == "finish" then
		local p = byId(e.userId)
		if p then onboard(p, 5); roundStep(p, 5) end
	elseif kind == "reward" then
		local p = byId(e.userId)
		if not p then return end
		onboard(p, 6)
		roundStep(p, 6)
		local total = e.totalCoins or 0
		Analytics.earn(p, "Coins", e.coins or 0, total - (e.daily or 0), "Gameplay")
		Analytics.earn(p, "Coins", e.daily or 0, total, "TimedReward")
		if (e.levelsGained or 0) > 0 then Analytics.levelReached(p, e.level) end
		if e.returnDay then Analytics.custom(p, "ReturnDay", e.returnDay) end
		Analytics.custom(p, "RoundPlace", e.place or 0)
	end
end)
