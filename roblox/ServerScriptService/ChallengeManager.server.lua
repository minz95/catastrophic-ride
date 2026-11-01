-- ChallengeManager.server.lua
-- Today's challenges (Shared/DailyChallenge): counts each player's
-- Telemetry events against them, pays the coins into the saved record when
-- one is done (RemoteEvents.ChallengeUpdate tells the player) and answers
-- the results screen (RemoteEvents.GetChallenges).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyChallenge = require(ReplicatedStorage.Shared.DailyChallenge)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GameManager = require(ServerScriptService.GameManager)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local function today() return Progression.dayOf(os.time()) end

Telemetry.onRecord(function(kind, e)
	local evs = DailyChallenge.eventsOf(kind, e)
	if #evs == 0 then return end
	local ctx = { biome = GameManager.getBiome(), weather = GameManager.getWeather() }
	for _, x in ipairs(evs) do
		local player = Players:GetPlayerByUserId(x.userId)
		local rec = player and PlayerStore.get(player)
		if rec then
			local day = today()
			local paid = DailyChallenge.step(rec, day, x.ev, ctx)
			if #paid > 0 then
				local ls = player:FindFirstChild("leaderstats")
				local c = ls and ls:FindFirstChild("Coins")
				if c then c.Value = rec.coins end
				PlayerStore.saveSoon(player)
				RemoteEvents.ChallengeUpdate:FireClient(player, DailyChallenge.view(rec, day), paid)
				for _, p in ipairs(paid) do
					-- task.defer: this runs inside Telemetry.record's loop
					task.defer(Telemetry.record, "challenge", { userId = x.userId, key = p.key, coins = p.coins, totalCoins = rec.coins })
				end
			end
		end
	end
end)

RemoteEvents.GetChallenges.OnServerInvoke = function(player)
	local rec = PlayerStore.get(player)
	if not rec then return nil end
	return DailyChallenge.view(rec, today())
end
