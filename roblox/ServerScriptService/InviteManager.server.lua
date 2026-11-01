-- InviteManager.server.lua
-- Friend invites: pays the inviter when a new friend joins through the
-- invite (Modules/Referral) and logs the invites players send from the
-- INVITE FRIENDS button (Shared/Invite; telemetry "invite_sent" and
-- "referral", AnalyticsManager counts them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Referral = require(ServerScriptService.Modules.Referral)
local Telemetry = require(ServerScriptService.Modules.Telemetry)
local Shop = require(ServerScriptService.Modules.Shop)

PlayerStore.onLoaded(function(friend, friendRec)
	local inviterId = Referral.referrerOf(friend)
	if not inviterId then return end
	local inviter = Players:GetPlayerByUserId(inviterId)
	local rec = inviter and PlayerStore.get(inviter)
	local coins = Referral.credit(rec, friend.UserId, friendRec)
	Telemetry.record("referral", { userId = inviterId, friend = friend.UserId, coins = coins, here = inviter ~= nil })
	if coins <= 0 then return end
	local ls = inviter:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	if c then c.Value = rec.coins end
	RemoteEvents.InviteReward:FireClient(inviter, friend.DisplayName or friend.Name, coins)
	-- an open shop screen shows the new coins (it read them when it opened)
	RemoteEvents.ShopUpdated:FireClient(inviter, Shop.state(rec))
	task.spawn(PlayerStore.save, inviter)
end)

local _last = {}
RemoteEvents.InviteSent.OnServerEvent:Connect(function(player, n)
	local count = Referral.cleanCount(n)
	local now = os.clock()
	if count <= 0 or (_last[player.UserId] and now - _last[player.UserId] < Constants.INVITE.REPORT_GAP) then return end
	_last[player.UserId] = now
	Telemetry.record("invite_sent", { userId = player.UserId, count = count })
end)

Players.PlayerRemoving:Connect(function(player) _last[player.UserId] = nil end)
