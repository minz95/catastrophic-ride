-- Progression.lua
-- Levels, coins and the daily bonus as pure functions over a player's saved
-- record (Modules/PlayerStore keeps it, ProgressionManager calls these at
-- RESULTS). Numbers: Constants.PROGRESSION.

local Constants = require(script.Parent.Constants)

local P = Constants.PROGRESSION
local Progression = {}

Progression.VERSION = 1

--- A new player's record.
function Progression.newRecord()
	return {
		v = Progression.VERSION,
		xp = 0,          -- XP into the current level
		level = 1,
		coins = 0,
		rounds = 0, wins = 0,
		lastDay = nil,   -- UTC day number of the last daily bonus
		streak = 0,      -- days in a row with a round
		owned = {},      -- cosmetics: { [id] = true }
		equipped = {},   -- cosmetics: { [category] = id }
	}
end

--- Fills fields a record saved by an older version lacks (never drops data).
function Progression.migrate(rec)
	if type(rec) ~= "table" then return Progression.newRecord() end
	for k, v in pairs(Progression.newRecord()) do
		if rec[k] == nil then rec[k] = v end
	end
	rec.v = Progression.VERSION
	return rec
end

--- XP needed to go from `level` to the next one.
function Progression.xpToNext(level)
	return P.XP_BASE + P.XP_STEP * (math.max(1, level) - 1)
end

--- Adds XP; returns the number of levels gained.
function Progression.addXp(rec, xp)
	rec.xp += math.max(0, math.floor(xp))
	local gained = 0
	while rec.xp >= Progression.xpToNext(rec.level) do
		rec.xp -= Progression.xpToNext(rec.level)
		rec.level += 1
		gained += 1
	end
	return gained
end

--- XP and coins for one round. place: 1-based finish place, or nil (DNF).
function Progression.roundReward(place)
	local xp, coins = P.PLAY_XP, P.PLAY_COINS
	if place then
		xp += P.FINISH_XP + (P.PLACE_XP[place] or 0)
		coins += P.FINISH_COINS + (P.PLACE_COINS[place] or 0)
	end
	return xp, coins
end

--- UTC day number for a unix time.
function Progression.dayOf(unixTime)
	return math.floor(unixTime / 86400)
end

--- Daily bonus for a round played on `day`: coins (0 if already paid
-- today) and the streak. Updates rec.lastDay / rec.streak.
function Progression.daily(rec, day)
	if rec.lastDay == day then return 0, rec.streak end
	if rec.lastDay == day - 1 then
		rec.streak = math.min(rec.streak + 1, P.DAILY_STREAK_MAX)
	else
		rec.streak = 1
	end
	rec.lastDay = day
	return P.DAILY_COINS + P.DAILY_STREAK_COINS * (rec.streak - 1), rec.streak
end

--- Applies one round to the record. Returns what the player is shown:
-- { xp, coins, daily, streak, levelsGained, level, xpInLevel, xpToNext, totalCoins, place }
function Progression.applyRound(rec, place, day)
	local xp, coins = Progression.roundReward(place)
	local daily, streak = Progression.daily(rec, day)
	rec.coins += coins + daily
	rec.rounds += 1
	if place == 1 then rec.wins += 1 end
	local gained = Progression.addXp(rec, xp)
	return {
		xp = xp, coins = coins, daily = daily, streak = streak, place = place,
		levelsGained = gained, level = rec.level, xpInLevel = rec.xp,
		xpToNext = Progression.xpToNext(rec.level), totalCoins = rec.coins,
	}
end

return Progression
