-- RideRating.lua
-- How strong a crafted ride is, for the crafting screen (playtest 2026-11-14:
-- "I can't tell how strong the car I'm making is"). Pure: slots + biome in,
-- numbers out, from the same functions the race uses (VehicleStats,
-- Constants.maxSpeedFor / torqueFor / turnSpeedFor).
--
--   local r = RideRating.rate({ BODY = "Piano", ENGINE = "Rocket" }, "FOREST")
--   r.bars.speed (0..1), r.score (0..1), r.grade ("S" | "A" | "B" | "C")
--
-- Each bar is placed between the weakest and the strongest value any
-- BODY × ENGINE × SPECIAL combination reaches in that biome (empty slots
-- included). The grade is the score's place among all those combinations.

local Constants    = require(script.Parent.Constants)
local ItemConfig   = require(script.Parent.ItemConfig)
local VehicleStats = require(script.Parent.VehicleStats)

local RideRating = {}

-- The bars, in the order the screen shows them.
RideRating.BARS = {
	{ key = "speed",    label = "Top speed" },
	{ key = "accel",    label = "Acceleration" },
	{ key = "handling", label = "Handling" },
	{ key = "boost",    label = "Boost" },
}

-- Share of all combinations a grade beats (S: the best 10 %).
RideRating.GRADES = {
	{ grade = "S", above = 0.90 },
	{ grade = "A", above = 0.65 },
	{ grade = "B", above = 0.30 },
	{ grade = "C", above = -1 },
}

local function cfgOf(name)
	return name and ItemConfig[name] or nil
end

--- The race numbers of a build: top speed, seat torque, turn speed, boost s.
function RideRating.metrics(slots, biome)
	slots = slots or {}
	local stats = VehicleStats.calculate(cfgOf(slots.BODY), cfgOf(slots.ENGINE), cfgOf(slots.SPECIAL), biome)
	stats = VehicleStats.applyMobility(stats, cfgOf(slots.MOBILITY), biome)
	return {
		speed    = Constants.maxSpeedFor(biome, stats),
		accel    = Constants.torqueFor(biome, stats),
		handling = Constants.turnSpeedFor(biome, stats),
		boost    = stats.boostDuration or 0,
	}
end

local _ranges = {}

-- Every BODY (and rideable item) × ENGINE × SPECIAL, empties included, with
-- no MOBILITY: min / max of each metric and the sorted plain scores.
local function range(biome)
	if _ranges[biome] then return _ranges[biome] end
	local pools = { BODY = { false }, ENGINE = { false }, SPECIAL = { false } }
	for name, cfg in pairs(ItemConfig) do
		if type(cfg) == "table" and cfg.slotType then
			if pools[cfg.slotType] then table.insert(pools[cfg.slotType], name) end
			if cfg.ride and cfg.slotType ~= "BODY" then table.insert(pools.BODY, name) end
		end
	end
	local all = {}
	local lo, hi = {}, {}
	for _, b in ipairs(pools.BODY) do
		for _, e in ipairs(pools.ENGINE) do
			for _, s in ipairs(pools.SPECIAL) do
				local m = RideRating.metrics({ BODY = b or nil, ENGINE = e or nil, SPECIAL = s or nil }, biome)
				table.insert(all, m)
				for _, bar in ipairs(RideRating.BARS) do
					local v = m[bar.key]
					lo[bar.key] = math.min(lo[bar.key] or v, v)
					hi[bar.key] = math.max(hi[bar.key] or v, v)
				end
			end
		end
	end
	local r = { lo = lo, hi = hi, scores = {} }
	_ranges[biome] = r
	for _, m in ipairs(all) do
		table.insert(r.scores, RideRating._score(m, r))
	end
	table.sort(r.scores)
	return r
end

function RideRating._score(m, r)
	local sum = 0
	for _, bar in ipairs(RideRating.BARS) do
		local span = r.hi[bar.key] - r.lo[bar.key]
		sum += span > 1e-9 and math.clamp((m[bar.key] - r.lo[bar.key]) / span, 0, 1) or 0.5
	end
	return sum / #RideRating.BARS
end

--- Bars (0..1 each), score (their mean) and grade of a build.
function RideRating.rate(slots, biome)
	local r = range(biome)
	local m = RideRating.metrics(slots, biome)
	local bars = {}
	for _, bar in ipairs(RideRating.BARS) do
		local span = r.hi[bar.key] - r.lo[bar.key]
		bars[bar.key] = span > 1e-9 and math.clamp((m[bar.key] - r.lo[bar.key]) / span, 0, 1) or 0.5
	end
	local score = RideRating._score(m, r)
	-- share of combinations this score beats
	local lo, hi = 1, #r.scores + 1   -- first index with scores[i] >= score
	while lo < hi do
		local mid = (lo + hi) // 2
		if r.scores[mid] < score - 1e-9 then lo = mid + 1 else hi = mid end
	end
	local below = lo - 1
	local share = #r.scores > 0 and below / #r.scores or 0.5
	local grade = "C"
	for _, g in ipairs(RideRating.GRADES) do
		if share > g.above then grade = g.grade break end
	end
	return { bars = bars, score = score, share = share, grade = grade, metrics = m }
end

--- The core slot `item` would go into (its own type), or nil.
function RideRating.slotFor(item)
	local cfg = cfgOf(item)
	local own = cfg and cfg.slotType
	if own == "BODY" or own == "ENGINE" or own == "SPECIAL" then return own end
	return nil
end

--- The build with `item` put in `slot` (moved out of any other slot).
function RideRating.with(slots, item, slot)
	local out = {}
	for k, v in pairs(slots or {}) do
		if v ~= item then out[k] = v end
	end
	out[slot] = item
	return out
end

return RideRating
