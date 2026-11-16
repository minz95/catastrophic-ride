-- LegendManager.server.lua
-- Legend Rides (Modules/LegendShop, Modules/LegendStore): reads the shared
-- listings, pays owners what their rides earned while they were away, and
-- keeps each player's worn ride round their waist (off while racing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GameManager = require(ServerScriptService.GameManager)
local LegendShop = require(ServerScriptService.Modules.LegendShop)
local LegendStore = require(ServerScriptService.Modules.LegendStore)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)

LegendStore.start()

local function hook(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		LegendShop.refresh(player)
	end)
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end

PlayerStore.onLoaded(function(player)
	LegendShop.claimFor(player)
	LegendShop.refresh(player)
end)

GameManager.onPhaseChanged(function(phase)
	for _, p in ipairs(Players:GetPlayers()) do
		-- off for the race (the avatar sits in the race car), back after
		task.defer(LegendShop.refresh, p)
		if phase == Constants.PHASES.RESULTS then task.defer(LegendShop.claimFor, p) end
	end
end)
