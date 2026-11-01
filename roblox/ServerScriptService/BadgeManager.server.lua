-- BadgeManager.server.lua
-- Hands out Roblox badges (Modules/Badges) for game moments: joining, a
-- first finish, a win, a steal, level 5. Reads Telemetry like
-- AnalyticsManager. Off in Studio and harness sessions.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Badges = require(ServerScriptService.Modules.Badges)
local HarnessConfig = require(ServerScriptService.Modules.HarnessConfig)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

Badges.enabled = not RunService:IsStudio() and HarnessConfig.get() == nil

local function joined(player)
	Badges.award(player, "welcome")
end
Players.PlayerAdded:Connect(joined)
for _, p in ipairs(Players:GetPlayers()) do joined(p) end

Players.PlayerRemoving:Connect(function(player)
	Badges.forget(player.UserId)
end)

Telemetry.onRecord(function(kind, e)
	for _, b in ipairs(Badges.forEvent(kind, e)) do
		local p = Players:GetPlayerByUserId(b.userId)
		if p then Badges.award(p, b.key) end
	end
end)
