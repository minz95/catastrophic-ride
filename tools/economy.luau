--!nocheck
-- tools/economy.luau — shop economy simulation (Shared/Progression rewards,
-- Shared/Cosmetics prices and level gates). Three kinds of player play 30
-- days; for every shop item: on which day it is affordable and unlocked,
-- buying the cheapest wanted item first. Writes reports/economy.md.
--   lune run tools/economy.luau
local fs = require("@lune/fs")
local Loader = require("../tests/lib/loader")

local env = Loader.boot()
local Progression = env.requirePath("ReplicatedStorage.Shared.Progression")
local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

local DAYS = 30
local FIELD = 6   -- racers per round (bots fill the grid)

-- place distribution per kind of player (weights for places 1..FIELD, 0 = DNF)
local PLAYERS = {
	{ name = "casual",  why = "3 rounds on 4 days a week, mid-field", roundsPerDay = 3, daysPerWeek = 4,
		places = { 0.08, 0.12, 0.18, 0.22, 0.22, 0.13, dnf = 0.05 } },
	{ name = "regular", why = "8 rounds every day, mid-field", roundsPerDay = 8, daysPerWeek = 7,
		places = { 0.15, 0.18, 0.2, 0.18, 0.16, 0.11, dnf = 0.02 } },
	{ name = "skilled", why = "10 rounds every day, usually on the podium", roundsPerDay = 10, daysPerWeek = 7,
		places = { 0.4, 0.25, 0.15, 0.1, 0.06, 0.04, dnf = 0 } },
}

local function lcg(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function pickPlace(rand, w)
	local r = rand()
	if r < (w.dnf or 0) then return nil end
	r -= (w.dnf or 0)
	local total = 0
	for i = 1, FIELD do total += w[i] end
	local x = r / (1 - (w.dnf or 0)) * total
	for i = 1, FIELD do
		x -= w[i]
		if x <= 0 then return i end
	end
	return FIELD
end

local items = {}
for _, cat in ipairs(Cosmetics.CATEGORIES) do
	for i, it in ipairs(Cosmetics.ITEMS[cat]) do
		if i > 1 then table.insert(items, it) end
	end
end
table.sort(items, function(a, b) return a.price < b.price end)

local lines = {
	"# Shop economy (simulated)", "",
	"`lune run tools/economy.luau`: three kinds of player over " .. DAYS .. " days, rewards from",
	"`Shared/Progression` (" .. FIELD .. "-car races, daily streak), prices and level gates from",
	"`Shared/Cosmetics`. A player buys every item, cheapest first, as soon as it is",
	"affordable and unlocked. Day = the day it was bought (— = not within " .. DAYS .. " days).", "",
}

local header = "| Item | Category | Price | Level |"
local sep = "|---|---|---|---|"
for _, p in ipairs(PLAYERS) do header ..= " " .. p.name .. " |"; sep ..= "---|" end
local bought = {}
local summary = {}
for pi, p in ipairs(PLAYERS) do
	local rand = lcg(1000 + pi)
	local rec = Progression.newRecord()
	local day0 = 20000
	bought[p.name] = {}
	local rounds, levelAt = 0, {}
	for d = 1, DAYS do
		local plays = ((d - 1) % 7) < p.daysPerWeek
		if plays then
			for _ = 1, p.roundsPerDay do
				Progression.applyRound(rec, pickPlace(rand, p.places), day0 + d)
				rounds += 1
				for _, it in ipairs(items) do
					if not bought[p.name][it.id] and Cosmetics.canBuy(rec, it.id) == "ok" then
						Cosmetics.buy(rec, it.id)
						bought[p.name][it.id] = d
					end
				end
			end
		end
		levelAt[d] = rec.level
	end
	summary[p.name] = { rounds = rounds, level = rec.level, coins = rec.coins, level7 = levelAt[7] }
end

table.insert(lines, header)
table.insert(lines, sep)
for _, it in ipairs(items) do
	local row = string.format("| %s | %s | %d | %s |", it.name, Cosmetics.TITLES[it.category] or it.category, it.price, tostring(it.minLevel or 1))
	for _, p in ipairs(PLAYERS) do
		row ..= " " .. (bought[p.name][it.id] and ("day " .. bought[p.name][it.id]) or "—") .. " |"
	end
	table.insert(lines, row)
end
-- Saving for one item only: the day it is bought.
local function saveFor(p, pi, it)
	local rand = lcg(1000 + pi)
	local rec = Progression.newRecord()
	for d = 1, DAYS do
		if ((d - 1) % 7) < p.daysPerWeek then
			for _ = 1, p.roundsPerDay do
				Progression.applyRound(rec, pickPlace(rand, p.places), 20000 + d)
				if Cosmetics.canBuy(rec, it.id) == "ok" then return d end
			end
		end
	end
	return nil
end
table.insert(lines, "")
table.insert(lines, "Saving for just one item (the day it is bought):")
table.insert(lines, "")
table.insert(lines, header)
table.insert(lines, sep)
for _, it in ipairs(items) do
	local row = string.format("| %s | %s | %d | %s |", it.name, Cosmetics.TITLES[it.category] or it.category, it.price, tostring(it.minLevel or 1))
	for pi, p in ipairs(PLAYERS) do
		local d = saveFor(p, pi, it)
		row ..= " " .. (d and ("day " .. d) or "—") .. " |"
	end
	table.insert(lines, row)
end
table.insert(lines, "")
table.insert(lines, "| Player | Plays | Rounds in " .. DAYS .. " days | Level on day 7 | Level on day " .. DAYS .. " | Coins left |")
table.insert(lines, "|---|---|---|---|---|---|")
for _, p in ipairs(PLAYERS) do
	local s = summary[p.name]
	table.insert(lines, string.format("| %s | %s | %d | %d | %d | %d |", p.name, p.why, s.rounds, s.level7, s.level, s.coins))
end
table.insert(lines, "")
table.insert(lines, string.format("Rewards: play %d XP / %d coins, finish +%d / +%d, podium +%s XP; daily bonus %d coins + %d per streak day (max %d).",
	Constants.PROGRESSION.PLAY_XP, Constants.PROGRESSION.PLAY_COINS, Constants.PROGRESSION.FINISH_XP, Constants.PROGRESSION.FINISH_COINS,
	table.concat(Constants.PROGRESSION.PLACE_XP, "/"), Constants.PROGRESSION.DAILY_COINS, Constants.PROGRESSION.DAILY_STREAK_COINS,
	Constants.PROGRESSION.DAILY_STREAK_MAX))

pcall(fs.writeDir, "reports")
fs.writeFile("reports/economy.md", table.concat(lines, "\n") .. "\n")
print(table.concat(lines, "\n"))
