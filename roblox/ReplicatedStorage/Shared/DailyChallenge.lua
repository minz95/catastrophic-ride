-- DailyChallenge.lua
-- Today's challenges: DailyChallenge.PER_DAY tasks drawn from POOL by the
-- UTC day (everyone gets the same three), each paying coins once, plus
-- ALL_BONUS for finishing all of them. Progress lives in the saved record
-- (rec.challenges, reset when the day changes). Pure: ChallengeManager feeds
-- it Telemetry events, ResultsUI shows `view`.

local DC = {}

DC.PER_DAY = 3
DC.ALL_BONUS = 50

-- ev: what counts (DailyChallenge.eventsOf); biome / wild: only a race
-- finished in that biome / in weather other than clear.
DC.POOL = {
	{ key = "finish3",   text = "Finish 3 races",                 goal = 3,  coins = 40, ev = "finish" },
	{ key = "win1",      text = "Win a race",                     goal = 1,  coins = 60, ev = "win" },
	{ key = "podium2",   text = "Finish in the top 3 twice",      goal = 2,  coins = 50, ev = "podium" },
	{ key = "turbo5",    text = "Get 5 drift turbos",             goal = 5,  coins = 40, ev = "turbo" },
	{ key = "steal2",    text = "Steal 2 items on the farm",      goal = 2,  coins = 50, ev = "steal" },
	{ key = "pickup20",  text = "Pick up 20 items",               goal = 20, coins = 30, ev = "pickup" },
	{ key = "ability5",  text = "Use 5 item abilities in races",  goal = 5,  coins = 40, ev = "ability" },
	{ key = "boost5",    text = "Boost 5 times",                  goal = 5,  coins = 30, ev = "boost" },
	{ key = "knockout1", text = "Knock out a rival on the farm",  goal = 1,  coins = 40, ev = "knockout" },
	{ key = "forest",    text = "Finish a race in the Forest",    goal = 1,  coins = 40, ev = "finish", biome = "FOREST" },
	{ key = "ocean",     text = "Finish a race at Sea",           goal = 1,  coins = 40, ev = "finish", biome = "OCEAN" },
	{ key = "sky",       text = "Finish a race in the Sky",       goal = 1,  coins = 40, ev = "finish", biome = "SKY" },
	{ key = "wild",      text = "Finish a race in wild weather",  goal = 1,  coins = 50, ev = "finish", wild = true },
}

local _byKey = {}
for _, c in ipairs(DC.POOL) do _byKey[c.key] = c end
function DC.get(key) return _byKey[key] end

--- Today's challenge keys for UTC day `day`: PER_DAY different ones, at
-- most one tied to a biome. Pure and the same on every server.
function DC.forDay(day)
	local seed = (day * 1103515245 + 12345) % 2147483648
	local function nextInt(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local out, used, biomeTaken = {}, {}, false
	local tries = 0
	while #out < DC.PER_DAY and tries < 200 do
		tries += 1
		local c = DC.POOL[nextInt(#DC.POOL)]
		if not used[c.key] and not (c.biome and biomeTaken) then
			used[c.key] = true
			if c.biome then biomeTaken = true end
			table.insert(out, c.key)
		end
	end
	return out
end

--- Turns a Telemetry event into challenge events: { { userId, ev } }.
-- Bots (ids ≤ 0, or bot = true) earn nothing.
function DC.eventsOf(kind, e)
	local out = {}
	local function add(uid, ev)
		if type(uid) == "number" and uid > 0 and not e.bot then table.insert(out, { userId = uid, ev = ev }) end
	end
	if kind == "finish" then
		add(e.userId, "finish")
		if e.place == 1 then add(e.userId, "win") end
		if e.place and e.place <= 3 then add(e.userId, "podium") end
	elseif kind == "drift_turbo" then add(e.userId, "turbo")
	elseif kind == "steal" then add(e.thief, "steal")
	elseif kind == "item_pickup" then add(e.userId, "pickup")
	elseif kind == "ability" and e.result == "ok" then add(e.userId, "ability")
	elseif kind == "boost" then add(e.userId, "boost")
	elseif kind == "punch" and e.result == "knockout" then add(e.attacker, "knockout")
	end
	return out
end

--- The record's challenge state for `day` (a new day starts it over).
function DC.state(rec, day)
	local s = rec.challenges
	if type(s) ~= "table" or s.day ~= day then
		s = { day = day, progress = {}, done = {}, bonus = false }
		rec.challenges = s
	end
	return s
end

--- Counts `ev` (with ctx { biome, weather } of the round) for today's
-- challenges; pays coins into rec for each one finished (and the bonus).
-- Returns { { key, text, coins } } of the ones finished now.
function DC.step(rec, day, ev, ctx)
	ctx = ctx or {}
	local s = DC.state(rec, day)
	local paid = {}
	for _, key in ipairs(DC.forDay(day)) do
		local c = _byKey[key]
		local fits = c.ev == ev and not s.done[key]
			and (not c.biome or c.biome == ctx.biome)
			and (not c.wild or (ctx.weather ~= nil and ctx.weather ~= "clear"))
		if fits then
			s.progress[key] = math.min(c.goal, (s.progress[key] or 0) + 1)
			if s.progress[key] >= c.goal then
				s.done[key] = true
				rec.coins += c.coins
				table.insert(paid, { key = key, text = c.text, coins = c.coins })
			end
		end
	end
	if #paid > 0 and not s.bonus then
		local all = true
		for _, key in ipairs(DC.forDay(day)) do
			if not s.done[key] then all = false end
		end
		if all then
			s.bonus = true
			rec.coins += DC.ALL_BONUS
			table.insert(paid, { key = "all", text = "All of today's challenges", coins = DC.ALL_BONUS })
		end
	end
	return paid
end

--- For the screen: { list = { { text, progress, goal, coins, done } }, bonus, allBonus }.
function DC.view(rec, day)
	local s = DC.state(rec, day)
	local list = {}
	for _, key in ipairs(DC.forDay(day)) do
		local c = _byKey[key]
		table.insert(list, { key = key, text = c.text, progress = s.progress[key] or 0, goal = c.goal,
			coins = c.coins, done = s.done[key] == true })
	end
	return { list = list, bonus = s.bonus, allBonus = DC.ALL_BONUS }
end

return DC
