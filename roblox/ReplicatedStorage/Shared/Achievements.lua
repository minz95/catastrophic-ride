-- Achievements.lua
-- Lifelong goals (2026-11-16: "a reason to come back, something to show
-- off"). Each pays a look nobody can buy: a hat, a trail or a ride pose
-- (Cosmetics items with `achievement = key`), equipped the moment it is
-- earned. Progress lives in the saved record (rec.achievements). Pure:
-- AchievementManager feeds it Telemetry events, ShopUI's Awards tab shows
-- `view`.
--
-- Per achievement:
--   ev       what counts (Achievements.eventsOf)
--   goal     how many
--   distinct count each `ev` value once (World Tour: one win per biome)
--   reward   the Cosmetics id it unlocks
--   badge    Roblox badge id (Creator Dashboard; 0 = off)
--   ugc      Marketplace avatar items the achievement gives: { { item, id } },
--            `item` the model in assets/ugc/<item>/ (an achievement hat or a
--            ride-on toy car), `id` its asset id once the owner uploaded it as
--            a free, experience-only item (0 = off). Earned → Roblox's
--            get-item prompt for each, so it is worn outside the game too
--            (docs/ugc.md).

local Achievements = {}

Achievements.LIST = {
	{ key = "races10",   name = "Road Rookie",    text = "Finish 10 races",                       goal = 10, ev = "finish",
		reward = "pose_handsup", badge = 0, ugc = { { item = "ride_cart", id = 0 } } },
	{ key = "races50",   name = "Road Warrior",   text = "Finish 50 races",                       goal = 50, ev = "finish",
		reward = "pose_lean", badge = 0, ugc = { { item = "helmet_pot", id = 0 } } },
	{ key = "wins10",    name = "Speed Legend",   text = "Win 10 races",                          goal = 10, ev = "win",
		reward = "trail_gold", badge = 0, ugc = { { item = "ride_racer", id = 0 } } },
	{ key = "tour",      name = "World Tour",     text = "Win in the Forest, at Sea and in the Sky", goal = 3, ev = "win_biome",
		distinct = true, reward = "hat_medal", badge = 0, ugc = { { item = "hat_medal", id = 0 } } },
	{ key = "flush",     name = "Royal Flush",    text = "Win a race riding a Toilet",            goal = 1,  ev = "win_toilet",
		reward = "hat_plunger", badge = 0, ugc = { { item = "hat_plunger", id = 0 }, { item = "ride_toilet", id = 0 } } },
	{ key = "funniest",  name = "Funniest Ride",  text = "Win the ride show vote",                goal = 1,  ev = "vote_win",
		reward = "hat_junkcrown", badge = 0, ugc = { { item = "hat_junkcrown", id = 0 }, { item = "ride_duck", id = 0 } } },
	{ key = "funniest5", name = "Crowd Favorite", text = "Win the ride show vote 5 times",        goal = 5,  ev = "vote_win",
		reward = "hat_goldduck", badge = 0, ugc = { { item = "hat_goldduck", id = 0 } } },
	{ key = "thief",     name = "Master Thief",   text = "Steal 20 items on the farm",            goal = 20, ev = "steal",
		reward = "hat_mask", badge = 0, ugc = { { item = "hat_mask", id = 0 } } },
	{ key = "brawler",   name = "Brawler",        text = "Knock out 10 rivals on the farm",       goal = 10, ev = "knockout",
		reward = "pose_flex", badge = 0, ugc = { { item = "belt_champion", id = 0 } } },
}

local _byKey = {}
for _, a in ipairs(Achievements.LIST) do _byKey[a.key] = a end
function Achievements.get(key) return _byKey[key] end

--- The achievement whose reward is Cosmetics id `id`, or nil.
function Achievements.forReward(id)
	for _, a in ipairs(Achievements.LIST) do
		if a.reward == id then return a end
	end
	return nil
end

--- Turns a Telemetry event into achievement events: { { userId, ev, value? } }.
-- `ctx`: { biome, bodyOf = function(userId) → BODY item or nil }.
-- Bots (ids ≤ 0, or bot = true) earn nothing.
function Achievements.eventsOf(kind, e, ctx)
	ctx = ctx or {}
	local out = {}
	local function add(uid, ev, value)
		if type(uid) == "number" and uid > 0 and not e.bot then
			table.insert(out, { userId = uid, ev = ev, value = value })
		end
	end
	if kind == "finish" then
		add(e.userId, "finish")
		if e.place == 1 then
			add(e.userId, "win")
			if ctx.biome then add(e.userId, "win_biome", ctx.biome) end
			if ctx.bodyOf and ctx.bodyOf(e.userId) == "Toilet" then add(e.userId, "win_toilet") end
		end
	elseif kind == "ride_vote" then add(e.userId, "vote_win")
	elseif kind == "steal" then add(e.thief, "steal")
	elseif kind == "punch" and e.result == "knockout" then add(e.attacker, "knockout")
	end
	return out
end

--- The record's achievement state.
function Achievements.state(rec)
	local s = rec.achievements
	if type(s) ~= "table" then
		s = {}
		rec.achievements = s
	end
	s.progress = s.progress or {}
	s.done = s.done or {}
	s.seen = s.seen or {}   -- distinct ones: { [key] = { [value] = true } }
	return s
end

--- Counts `ev` (`value` for distinct ones). Unlocks each reward finished
-- now (rec.owned, equipped in its category). Returns the achievements
-- finished now (the LIST entries).
function Achievements.step(rec, ev, value)
	local s = Achievements.state(rec)
	local earned = {}
	for _, a in ipairs(Achievements.LIST) do
		if a.ev == ev and not s.done[a.key] then
			local counts = true
			if a.distinct then
				local seen = s.seen[a.key] or {}
				s.seen[a.key] = seen
				if value == nil or seen[value] then
					counts = false
				else
					seen[value] = true
				end
			end
			if counts then
				s.progress[a.key] = math.min(a.goal, (s.progress[a.key] or 0) + 1)
				if s.progress[a.key] >= a.goal then
					s.done[a.key] = true
					Achievements.grant(rec, a)
					table.insert(earned, a)
				end
			end
		end
	end
	return earned
end

--- Gives achievement `a`'s reward and puts it on.
function Achievements.grant(rec, a)
	local Cosmetics = require(script.Parent.Cosmetics)
	local it = Cosmetics.get(a.reward)
	if not it then return end
	rec.owned = rec.owned or {}
	rec.owned[it.id] = true
	rec.equipped = rec.equipped or {}
	rec.equipped[it.category] = it.id
end

--- The uploaded avatar item ids of `a` (ids 0 left out).
function Achievements.ugcIds(a)
	local out = {}
	for _, u in ipairs(a.ugc or {}) do
		if type(u.id) == "number" and u.id > 0 then table.insert(out, u.id) end
	end
	return out
end

function Achievements.hasUgc(a)
	return #Achievements.ugcIds(a) > 0
end

--- For the screen: { { key, name, text, progress, goal, done, reward, ugc } }.
function Achievements.view(rec)
	local s = Achievements.state(rec)
	local list = {}
	for _, a in ipairs(Achievements.LIST) do
		table.insert(list, { key = a.key, name = a.name, text = a.text, progress = s.progress[a.key] or 0,
			goal = a.goal, done = s.done[a.key] == true, reward = a.reward, ugc = Achievements.hasUgc(a) })
	end
	return list
end

return Achievements
