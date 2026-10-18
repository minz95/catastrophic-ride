-- RaceMetrics.lua
-- "Is this race fun?" turned into numbers. Pure (no Roblox types): the same
-- code scores a real playtest (server Telemetry, see Modules/PlaytestReport)
-- and the offline simulations (tests/lib/matchsim, tools/report.luau).
--
--   local race = {
--     length = 4421, timeout = 180,
--     sections = RaceMetrics.sections(track, geo),   -- { name, s0, s1 }
--     racers = { { id = 1, progress = { {t, s}, ... }, finish = 74.2 | nil,
--                  respawns = { s, ... }, hits = { s, ... } }, ... },
--     markers = { { s = 1200, note = "bad" | "fun", id = 1 }, ... },
--   }
--   local m = RaceMetrics.compute(race)
--   local verdicts = RaceMetrics.verdicts(RaceMetrics.aggregate({ m, ... }), Constants.FUN_TARGETS)
--
-- What the numbers mean (targets live in Constants.FUN_TARGETS):
--   winnerTime      how long a race takes for the winner
--   finishRate      share of racers who finish before the timeout
--   finishSpread    seconds between first and last finisher (a long tail = waiting)
--   leadChanges     how often the leader changes (held >= HOLD_STEPS seconds)
--   overtakes       position swaps between any two racers
--   closeShare      share of race time the top two are within CLOSE_GAP studs
--   sections        per section: mean time, spread (max - min) between racers,
--                   respawns, wall hits, playtest markers. The section with the
--                   largest spread is where races are won or lost.

local RaceMetrics = {}

RaceMetrics.STEP       = 1     -- seconds between timeline samples
RaceMetrics.HOLD_STEPS = 2     -- a new order must hold this many steps to count
RaceMetrics.CLOSE_GAP  = 40    -- studs: "the top two are racing each other"
RaceMetrics.DEADBAND   = 5     -- studs: closer than this is not an order

--- Sections with arc-length bounds from a track's node-index sections.
function RaceMetrics.sections(track, geo)
	local out = {}
	for _, sec in ipairs(track.sections or {}) do
		local s0 = geo.segments[sec.from] and geo.segments[sec.from].s0 or 0
		local s1 = geo.segments[sec.to] and geo.segments[sec.to].s0 or geo.length
		table.insert(out, { name = sec.name, s0 = s0, s1 = s1 })
	end
	return out
end

local function sectionOf(sections, s)
	for i, sec in ipairs(sections) do
		if s >= sec.s0 and s < sec.s1 then return i end
	end
	return #sections
end
RaceMetrics.sectionOf = sectionOf

-- Progress of a racer at time t (linear between samples; the finish counts
-- as reaching the end of the track).
local function progressAt(r, t, length)
	if r.finish and t >= r.finish then return length end
	local p = r.progress
	if #p == 0 or t <= p[1][1] then return p[1] and p[1][2] or 0 end
	for i = 2, #p do
		if p[i][1] >= t then
			local a, b = p[i - 1], p[i]
			local f = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			return a[2] + (b[2] - a[2]) * f
		end
	end
	return p[#p][2]
end

-- First time the racer reaches arc length s (nil if never).
local function timeAt(r, s, length)
	local p = r.progress
	if s <= 0 then return 0 end
	local best = 0
	for i = 1, #p do
		if p[i][2] > best then
			if p[i][2] >= s then
				local prev = i > 1 and p[i - 1] or { 0, 0 }
				local f = (s - prev[2]) / math.max(p[i][2] - prev[2], 1e-6)
				return prev[1] + (p[i][1] - prev[1]) * math.clamp(f, 0, 1)
			end
			best = p[i][2]
		end
	end
	if r.finish and s >= length - 1 then return r.finish end
	return nil
end

function RaceMetrics.compute(race)
	local length = race.length
	local racers = race.racers
	local sections = race.sections or {}
	local m = { racers = #racers, finished = 0 }

	-- Finish
	local times = {}
	for _, r in ipairs(racers) do
		if r.finish then table.insert(times, r.finish) end
	end
	table.sort(times)
	m.finished = #times
	m.finishRate = #racers > 0 and #times / #racers or 0
	m.winnerTime = times[1]
	m.lastTime = times[#times]
	m.finishSpread = #times >= 2 and (times[#times] - times[1]) or nil
	m.gap12 = #times >= 2 and (times[2] - times[1]) or nil

	-- Timeline: leader changes, overtakes, close racing
	local tEnd = 0
	for _, r in ipairs(racers) do
		local last = r.progress[#r.progress]
		tEnd = math.max(tEnd, r.finish or (last and last[1]) or 0)
	end
	local leader, pendingLeader, pendingFor = nil, nil, 0
	local leadChanges = 0
	local pairSign, pairPending = {}, {}
	local overtakes = 0
	local closeSteps, raceSteps = 0, 0
	for t = RaceMetrics.STEP, tEnd, RaceMetrics.STEP do
		local s = {}
		for i, r in ipairs(racers) do s[i] = progressAt(r, t, length) end
		-- leader
		local best, bestS, second = nil, -math.huge, -math.huge
		for i = 1, #racers do
			if s[i] > bestS then second = bestS; best, bestS = i, s[i]
			elseif s[i] > second then second = s[i] end
		end
		if leader == nil then
			leader = best
		elseif best ~= leader and bestS - s[leader] > RaceMetrics.DEADBAND then
			if pendingLeader == best then pendingFor += 1 else pendingLeader, pendingFor = best, 1 end
			if pendingFor >= RaceMetrics.HOLD_STEPS then
				leader, pendingLeader, pendingFor = best, nil, 0
				leadChanges += 1
			end
		else
			pendingLeader, pendingFor = nil, 0
		end
		-- close racing while the leader is still on track
		if #racers >= 2 and bestS < length then
			raceSteps += 1
			if bestS - second < RaceMetrics.CLOSE_GAP then closeSteps += 1 end
		end
		-- pairwise order swaps
		for i = 1, #racers do
			for j = i + 1, #racers do
				local key = i .. ":" .. j
				local d = s[i] - s[j]
				local sign = d > RaceMetrics.DEADBAND and 1 or (d < -RaceMetrics.DEADBAND and -1 or 0)
				if sign ~= 0 then
					if pairSign[key] == nil then
						pairSign[key] = sign
					elseif sign ~= pairSign[key] then
						pairPending[key] = (pairPending[key] or 0) + 1
						if pairPending[key] >= RaceMetrics.HOLD_STEPS then
							pairSign[key] = sign
							pairPending[key] = 0
							overtakes += 1
						end
					else
						pairPending[key] = 0
					end
				end
			end
		end
	end
	m.leadChanges = leadChanges
	m.overtakes = overtakes
	m.closeShare = raceSteps > 0 and closeSteps / raceSteps or 0

	-- Sections
	m.sections = {}
	for k, sec in ipairs(sections) do
		local entry = { name = sec.name, times = {}, respawns = 0, hits = 0, markers = { bad = 0, fun = 0 } }
		for _, r in ipairs(racers) do
			local a, b = timeAt(r, sec.s0, length), timeAt(r, math.min(sec.s1, length - 0.5), length)
			if a and b and b >= a then table.insert(entry.times, b - a) end
			for _, s in ipairs(r.respawns or {}) do
				if sectionOf(sections, s) == k then entry.respawns += 1 end
			end
			for _, s in ipairs(r.hits or {}) do
				if sectionOf(sections, s) == k then entry.hits += 1 end
			end
		end
		for _, mk in ipairs(race.markers or {}) do
			if mk.s and sectionOf(sections, mk.s) == k then
				entry.markers[mk.note == "fun" and "fun" or "bad"] += 1
			end
		end
		local sum, lo, hi = 0, math.huge, -math.huge
		for _, v in ipairs(entry.times) do sum += v; lo = math.min(lo, v); hi = math.max(hi, v) end
		entry.meanTime = #entry.times > 0 and sum / #entry.times or nil
		entry.spread = #entry.times >= 2 and (hi - lo) or 0
		entry.times = nil
		table.insert(m.sections, entry)
	end
	local decide, decideSpread = nil, -1
	for _, sec in ipairs(m.sections) do
		if sec.spread > decideSpread then decide, decideSpread = sec.name, sec.spread end
	end
	m.decidingSection = decide
	return m
end

--- Share of a round spent racing: race / (farming + crafting + race + results).
-- `durations` is Constants.PHASE_DURATION (harness overrides not applied).
function RaceMetrics.racingShare(raceSeconds, durations)
	if not raceSeconds then return nil end
	local other = (durations.FARMING or 0) + (durations.CRAFTING or 0) + (durations.RESULTS or 0)
	return raceSeconds / (raceSeconds + other)
end

--- Averages over many races (sections summed by name).
function RaceMetrics.aggregate(list)
	local agg = { races = #list }
	local function mean(key)
		local sum, n = 0, 0
		for _, m in ipairs(list) do
			if m[key] ~= nil then sum += m[key]; n += 1 end
		end
		return n > 0 and sum / n or nil
	end
	for _, key in ipairs({ "finishRate", "winnerTime", "lastTime", "finishSpread", "gap12", "leadChanges", "overtakes", "closeShare" }) do
		agg[key] = mean(key)
	end
	local byName, order = {}, {}
	for _, m in ipairs(list) do
		for _, sec in ipairs(m.sections or {}) do
			local e = byName[sec.name]
			if not e then
				e = { name = sec.name, spread = 0, meanTime = 0, n = 0, respawns = 0, hits = 0, markers = { bad = 0, fun = 0 }, deciding = 0 }
				byName[sec.name] = e
				table.insert(order, e)
			end
			if sec.meanTime then e.meanTime += sec.meanTime; e.spread += sec.spread; e.n += 1 end
			e.respawns += sec.respawns
			e.hits += sec.hits
			e.markers.bad += sec.markers.bad
			e.markers.fun += sec.markers.fun
		end
		if m.decidingSection and byName[m.decidingSection] then
			byName[m.decidingSection].deciding += 1
		end
	end
	for _, e in ipairs(order) do
		if e.n > 0 then e.meanTime /= e.n; e.spread /= e.n end
		e.n = nil
	end
	agg.sections = order
	return agg
end

--- Compares aggregated numbers with targets: { min, max } per key.
-- Returns { { key, value, min, max, ok } } in a stable order.
function RaceMetrics.verdicts(values, targets)
	local out = {}
	local keys = {}
	for k in pairs(targets) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local t, v = targets[k], values[k]
		local ok = nil   -- nil = not measured
		if v ~= nil then ok = (t.min == nil or v >= t.min) and (t.max == nil or v <= t.max) end
		table.insert(out, { key = k, value = v, min = t.min, max = t.max, ok = ok, why = t.why })
	end
	return out
end

--- Race input from server Telemetry events (oldest first). Uses the LAST
-- race_start in the log; times are relative to it.
function RaceMetrics.fromTelemetry(events, sections, length)
	local startIdx
	for i = #events, 1, -1 do
		if events[i].kind == "race_start" then startIdx = i break end
	end
	if not startIdx then return nil end
	local t0 = events[startIdx].t
	local byId, racers = {}, {}
	local function racer(id)
		if not byId[id] then
			byId[id] = { id = id, progress = {}, respawns = {}, hits = {} }
			table.insert(racers, byId[id])
		end
		return byId[id]
	end
	for _, id in ipairs(events[startIdx].racers or {}) do racer(id) end
	local markers = {}
	for i = startIdx + 1, #events do
		local e = events[i]
		if e.kind == "race_start" or (e.kind == "phase" and e.phase ~= "RACING") then break end
		if e.kind == "race_progress" then
			table.insert(racer(e.userId).progress, { e.t - t0, e.s })
		elseif e.kind == "finish" then
			racer(e.userId).finish = e.time
		elseif e.kind == "respawn" and e.s then
			table.insert(racer(e.userId).respawns, e.s)
		elseif e.kind == "hit" and e.s then
			table.insert(racer(e.userId).hits, e.s)
		elseif e.kind == "feedback" and e.s then
			table.insert(markers, { s = e.s, note = e.note, id = e.userId })
		end
	end
	return {
		length = length, sections = sections, racers = racers, markers = markers,
		timeout = events[startIdx].timeout,
	}
end

return RaceMetrics
