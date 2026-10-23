-- ProgressionManager.server.lua
-- Levels and coins: loads each player's record (Modules/PlayerStore), shows
-- Level / Coins on the player list (leaderstats) and pays every racer at
-- RESULTS (Shared/Progression.applyRound), telling them through
-- RemoteEvents.RewardGranted (ResultsUI draws it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GameManager = require(ServerScriptService.GameManager)
local HarnessConfig = require(ServerScriptService.Modules.HarnessConfig)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local function stat(player, name)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local v = ls:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	return v
end

local function showStats(player, rec)
	stat(player, "Level").Value = rec.level
	stat(player, "Coins").Value = rec.coins
end

--- Pays everyone in `order` (GameManager.getLastResults). Returns the rewards by userId.
local function payRound(order, day)
	local paid = {}
	local place = 0
	for _, entry in ipairs(order or {}) do
		local player = Players:GetPlayerByUserId(entry.userId)
		local rec = player and PlayerStore.get(player)
		if rec and not paid[entry.userId] then
			local myPlace = nil
			if not entry.dnf then
				place += 1
				myPlace = place
			end
			local reward = Progression.applyRound(rec, myPlace, day)
			reward.saved = PlayerStore.isSaved(player)
			paid[entry.userId] = reward
			showStats(player, rec)
			RemoteEvents.RewardGranted:FireClient(player, reward)
			Telemetry.record("reward", {
				userId = entry.userId, place = myPlace, xp = reward.xp, coins = reward.coins,
				daily = reward.daily, level = reward.level, levelsGained = reward.levelsGained, saved = reward.saved,
			})
			task.spawn(PlayerStore.save, player)
		end
	end
	return paid
end

if HarnessConfig.get() then PlayerStore.setMemoryOnly(true) end
PlayerStore.onLoaded(showStats)
PlayerStore.start()

GameManager.onPhaseChanged(function(phase)
	if phase ~= Constants.PHASES.RESULTS then return end
	payRound(GameManager.getLastResults(), Progression.dayOf(os.time()))
end)
