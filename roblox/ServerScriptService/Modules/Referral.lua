-- Referral.lua
-- Friend invites: a player who joins through someone's invite (Roblox puts
-- the inviter in the join data as ReferredByPlayerId) and has never played
-- a round pays the inviter Constants.INVITE.COINS, once per friend, for up
-- to MAX_REWARDED friends. InviteManager calls these; the rules are pure.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local I = Constants.INVITE
local Referral = {}

--- Who invited `player` (a UserId) or nil. Tests replace it.
function Referral.referrerOf(player)
	local ok, data = pcall(function() return player:GetJoinData() end)
	local id = ok and type(data) == "table" and data.ReferredByPlayerId
	if type(id) == "number" and id > 0 and id ~= player.UserId then return id end
	return nil
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

--- Pays the inviter's record for `friendId` if the friend is new (friendRec
-- has no rounds) and was not paid for before. Returns the coins paid (0).
function Referral.credit(inviterRec, friendId, friendRec)
	if not inviterRec or not friendRec or (friendRec.rounds or 0) > 0 then return 0 end
	inviterRec.referred = inviterRec.referred or {}
	local key = tostring(friendId)
	if inviterRec.referred[key] or count(inviterRec.referred) >= I.MAX_REWARDED then return 0 end
	inviterRec.referred[key] = true
	inviterRec.coins += I.COINS
	return I.COINS
end

--- A friends-picked count sent by a client, cleaned (0 = ignore).
function Referral.cleanCount(n)
	if type(n) ~= "number" or n ~= n then return 0 end
	return math.clamp(math.floor(n), 0, I.MAX_REPORT)
end

return Referral
