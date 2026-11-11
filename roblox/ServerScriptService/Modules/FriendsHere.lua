-- FriendsHere.lua
-- Is a Roblox friend of this player in the server? (FarmingManager: the
-- friend bonus starter item, Shared/StarterItems.) Player:IsFriendsWith
-- yields and calls Roblox, so each pair is asked once per server and kept.

local Players = game:GetService("Players")

local FriendsHere = {}

local _known = {}   -- ["a:b"] (a < b) = true / false

--- Are players `a` and `b` (UserIds) friends? Tests replace it.
function FriendsHere.check(a, b)
	local pa = Players:GetPlayerByUserId(a)
	if not pa then return false end
	local ok, yes = pcall(function() return pa:IsFriendsWith(b) end)
	return ok and yes == true
end

local function key(a, b)
	if a > b then a, b = b, a end
	return a .. ":" .. b
end

--- True when another player in the server is a Roblox friend of `player`.
function FriendsHere.has(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.UserId > 0 and player.UserId > 0 then
			local k = key(player.UserId, other.UserId)
			if _known[k] == nil then _known[k] = FriendsHere.check(player.UserId, other.UserId) end
			if _known[k] then return true end
		end
	end
	return false
end

--- Forget what was asked (tests).
function FriendsHere.reset()
	_known = {}
end

return FriendsHere
