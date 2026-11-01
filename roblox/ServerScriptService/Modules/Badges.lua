-- Badges.lua
-- Roblox badges (Creator Dashboard → the experience → Engagement → Badges):
-- the list, which game moment earns which, and the award call. Create each
-- badge on the dashboard (picture: assets/badges/<key>.png, name and
-- description below), then put its id here. Badges with id 0 are off.
-- BadgeManager listens to Telemetry and calls Badges.award. Off in Studio
-- and harness sessions; tests set Badges.sink to record the calls.

local Badges = {}

Badges.LIST = {
	{ key = "welcome",      name = "Welcome, Rider!", id = 0,
		description = "Joined Catastrophic Ride. Grab junk, build a ride, race!" },
	{ key = "first_finish", name = "Finish Line",     id = 0,
		description = "Finished your first race." },
	{ key = "champion",     name = "Champion",        id = 0,
		description = "Won a race." },
	{ key = "sticky",       name = "Sticky Fingers",  id = 0,
		description = "Stole an item from another rider on the farm." },
	{ key = "level5",       name = "Level 5",         id = 0,
		description = "Reached level 5." },
}

Badges.LEVEL = 5   -- the "level5" badge

Badges.enabled = false
Badges.sink = nil   -- tests: function(userId, key, id) end

local _byKey = {}
for _, b in ipairs(Badges.LIST) do _byKey[b.key] = b end

function Badges.get(key)
	return _byKey[key]
end

--- Badges a Telemetry event earns: a list of { userId, key }. Pure.
function Badges.forEvent(kind, e)
	local out = {}
	if kind == "finish" and e.userId and e.userId > 0 then
		table.insert(out, { userId = e.userId, key = "first_finish" })
		if e.place == 1 then table.insert(out, { userId = e.userId, key = "champion" }) end
	elseif kind == "steal" and e.thief and e.thief > 0 then
		table.insert(out, { userId = e.thief, key = "sticky" })
	elseif kind == "reward" and e.userId and (e.level or 0) >= Badges.LEVEL then
		table.insert(out, { userId = e.userId, key = "level5" })
	end
	return out
end

local _given = {}   -- userId → { key = true } this server (one call each)

--- Awards `key` to the player once per server; a badge with id 0 is skipped.
function Badges.award(player, key)
	local b = _byKey[key]
	if not b or b.id == 0 or not player then return end
	local mine = _given[player.UserId]
	if not mine then mine = {}; _given[player.UserId] = mine end
	if mine[key] then return end
	mine[key] = true
	if Badges.sink then
		Badges.sink(player.UserId, key, b.id)
		return
	end
	if not Badges.enabled then return end
	task.spawn(function()
		local BadgeService = game:GetService("BadgeService")
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, b.id)
		if ok and has then return end
		local okAward, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, b.id)
		if not okAward then
			mine[key] = nil   -- try again next time it is earned
			warn("[Badges] " .. key .. ": " .. tostring(err))
		end
	end)
end

function Badges.forget(userId)
	_given[userId] = nil
end

return Badges
