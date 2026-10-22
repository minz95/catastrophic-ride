--!nocheck
-- balance.luau
-- Crafting balance model: how much each item is worth in a race, and who
-- wins when six players craft from what they farmed.
--
-- Three layers, all on the real game modules:
--   1. Pace. Stats → seat values (VehicleStats, Constants.maxSpeedFor, …) →
--      lap time, from KineSim races of sampled builds (least-squares fit on
--      MaxSpeed, TurnSpeed, Torque and boost seconds).
--   2. Abilities. Each item's E ability, with the numbers AbilityManager
--      uses (AbilityConfig selfSpeed / victimSpeed / push / …), fired by a
--      sensible player during a KineSim race: self effects change the user's
--      time; harmful effects are applied to a victim car to measure what one
--      hit costs. Hit chances per use are assumptions (HIT_RATE below).
--   3. Matches. Monte Carlo: inventories drawn with the farming spawn odds,
--      each player crafts the build worth most to them, race time = pace −
--      own ability gains + hits taken from rivals + driver noise.
--
--   local B = Balance.measure(world, { seeds = 2 })      -- layers 1 + 2
--   local m = Balance.matches(B, { matches = 2000 })      -- layer 3
--   local ok = Balance.check(B, m, Constants.BALANCE_TARGETS)
--
-- Not modelled: HEAD / TAIL passives, car-to-car contact, the blinding
-- screen effects (Kettle steam, Bathtub splash) on a human driver.

local KineSim = require("./kinesim")
local Builds = require("./builds")

local Balance = {}

-- Chance that one use of a harmful ability lands on a rival. Nearest-target
-- abilities need a racer within 60 studs; radius abilities need one inside
-- the radius; drops need someone behind to drive into them.
Balance.HIT_RATE = {
	nearest = 0.75,
	radiusPerStud = 1 / 25,  -- all_in_radius: radius / 25, at most radiusMax
	radiusMax = 0.6,
	frontCone = 0.5,         -- Fan: only racers in front of you
	drop = 0.3,
}
Balance.DRIVER = "average"
Balance.NOISE = 2.0          -- s, spread of one driver's race time (seeds)
Balance.START = 4            -- s after the start before abilities are used
Balance.VICTIM_EVERY = 5     -- s between hits in a victim run (each seed shifts them)

-- Effects that protect or lift instead of changing speed.
local SHIELD = { umbrellaBlock = true, bloomCleanse = true, lockdown = true, sofaFortress = true, disguise = true, parachute = true }
local LIFT = {
	emergencyFloat = true, fullBuoyancy = true, softLanding = true, groundBounce = true,
	rise = true, hover = true, lifeFloat = true, kiteLift = true, kiteGlide = true, parachute = true,
}

local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
Balance.RANK = RANK
Balance.TIERS = { "Common", "Uncommon", "Rare", "Epic" }

local function mean(t)
	if #t == 0 then return 0 end
	local s = 0
	for _, v in ipairs(t) do s += v end
	return s / #t
end
Balance.mean = mean

-- Least squares: rows of features (first = 1), y. Returns coefficients.
local function fit(rows, y)
	local n = #rows[1]
	local A, b = {}, {}
	for i = 1, n do
		A[i] = table.create(n, 0)
		b[i] = 0
	end
	for k, r in ipairs(rows) do
		for i = 1, n do
			b[i] += r[i] * y[k]
			for j = 1, n do A[i][j] += r[i] * r[j] end
		end
	end
	for i = 1, n do A[i][i] += 1e-6 end   -- ridge: a feature that never varies
	for c = 1, n do
		local p = c
		for r = c + 1, n do if math.abs(A[r][c]) > math.abs(A[p][c]) then p = r end end
		A[c], A[p] = A[p], A[c]
		b[c], b[p] = b[p], b[c]
		for r = c + 1, n do
			local f = A[r][c] / A[c][c]
			for j = c, n do A[r][j] -= f * A[c][j] end
			b[r] -= f * b[c]
		end
	end
	local x = table.create(n, 0)
	for i = n, 1, -1 do
		local s = b[i]
		for j = i + 1, n do s -= A[i][j] * x[j] end
		x[i] = s / A[i][i]
	end
	return x
end

local function features(car)
	return { 1, car.maxSpeed, car.turnSpeed, car.torque, car.boostDuration }
end

--- What an AbilityConfig entry does, for the model: a set of traits
--   self    changes the user's own speed / turning / shoves it (burst)
--   slow    slows the user (a brake that comes with a shield)
--   offense slows or shoves rivals (drop = left on the track)
--   shield  blocks hits for its duration;  lift: rides over ground drops
--   ground  mud / slow zones do not slow it;  refill: refills the boost gauge
function Balance.traits(cfg)
	local t = {}
	if not cfg then return t end
	local key = cfg.effectKey
	if (cfg.selfSpeed and cfg.selfSpeed > 1) or (cfg.selfTurn and cfg.selfTurn ~= 1) or cfg.push then t.self = true end
	if cfg.selfSpeed and cfg.selfSpeed < 1 then t.slow = true end
	if cfg.targetType == "track_drop" then
		t.offense, t.drop = true, true
	elseif cfg.victimSpeed or cfg.victimTurn or cfg.victimPush then
		t.offense = true
	end
	if SHIELD[key] then t.shield = true end
	if LIFT[key] then t.lift = true; t.ground = true end
	if key == "digMode" then t.ground = true end
	if key == "backpackBoost" then t.refill = true end
	return t
end

function Balance.label(t)
	local out = {}
	for _, k in ipairs({ "self", "slow", "offense", "drop", "shield", "lift", "ground", "refill" }) do
		if t[k] and not (k == "offense" and t.drop) and not (k == "ground" and t.lift) then table.insert(out, k) end
	end
	return #out > 0 and table.concat(out, "+") or "none"
end

local function hitRate(cfg)
	local H = Balance.HIT_RATE
	if cfg.targetType == "nearest" then return H.nearest end
	if cfg.targetType == "track_drop" then return H.drop end
	local r = cfg.radius or 8
	local p = math.min(H.radiusMax, r * H.radiusPerStud)
	if cfg.effectKey == "gustBlast" then p *= H.frontCone end
	return p
end

-- What one hit by `cfg` does to the car it lands on.
local function victimEffect(cfg, Constants)
	if cfg.targetType == "track_drop" then
		if cfg.effectKey == "cactusObstacle" or cfg.effectKey == "logObstacle" then
			return { speed = Constants.OBSTACLE_BOUNCE_SPEED_MULT, dur = Constants.OBSTACLE_BOUNCE_PENALTY_DURATION, push = -Constants.OBSTACLE_BOUNCE_PUSH }
		elseif cfg.hitSpeed then
			return { speed = cfg.hitSpeed, dur = cfg.hitFor or 1.5 }
		end
		return nil   -- steam: blinds a human, the car is not slowed
	end
	if not (cfg.victimSpeed or cfg.victimTurn or cfg.victimPush) then return nil end
	return {
		speed = cfg.victimSpeed, turn = cfg.victimTurn,
		dur = cfg.victimFor or cfg.duration or 1,
		side = cfg.victimPush,
		back = cfg.effectKey == "magnetPull",
	}
end

local function sig(v)
	if not v then return "nil" end
	return string.format("%s|%s|%s|%s|%s", tostring(v.speed), tostring(v.turn), tostring(v.dur), tostring(v.side or v.push), tostring(v.back))
end

--- Layers 1 and 2 for one biome. world: tests/lib/world.
-- opts: seeds (default 2), paceSamples (default 20).
function Balance.measure(world, opts)
	opts = opts or {}
	local env = world.env
	local biome = world.biome
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local AbilityConfig = env.requirePath("ServerScriptService.Modules.AbilityConfig")
	local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
	local profile = Autopilot.PROFILES[opts.driver or Balance.DRIVER]
	local seeds = opts.seeds or 2
	local runs = 0

	local function race(car, seed, onStep)
		runs += 1
		return KineSim.run(world, { car = car, profile = profile, profileName = opts.driver or Balance.DRIVER, seed = seed, respawn = "track", onStep = onStep })
	end
	local function time(r)
		-- an unfinished race counts as the timeout plus the distance left
		if r.finished then return r.time end
		return r.endT + (r.trackLength - r.maxProgress) / 30
	end

	-- ── 1. pace ─────────────────────────────────────────────────────────────
	local all = Builds.enumerate(env, biome)
	table.sort(all, function(a, b)
		if a.maxSpeed ~= b.maxSpeed then return a.maxSpeed < b.maxSpeed end
		return a.turnSpeed < b.turnSpeed
	end)
	local n = opts.paceSamples or 20
	local rows, ys, samples = {}, {}, {}
	local seen = {}
	for i = 1, n do
		-- spread over top speed, alternating low / high turn rate
		local k = math.clamp(math.floor((i - 0.5) / n * #all) + 1, 1, #all)
		local b = all[k]
		local alt = all[math.clamp(k + ((i % 2 == 0) and 37 or -37), 1, #all)]
		if i % 3 == 0 then b = alt end
		local car = KineSim.carFromStats(b.stats, Constants, biome)
		local key = string.format("%.2f|%.3f|%.1f|%.2f", car.maxSpeed, car.turnSpeed, car.torque, car.boostDuration)
		if not seen[key] then
			seen[key] = true
			local t = 0
			for seed = 1, math.min(seeds, 2) do t += time(race(car, seed)) / math.min(seeds, 2) end
			table.insert(rows, features(car))
			table.insert(ys, t)
			table.insert(samples, { build = Builds.describe(b), car = car, time = t })
		end
	end
	local coef = fit(rows, ys)
	local function pace(car)
		local f = features(car)
		local t = 0
		for i, c in ipairs(coef) do t += c * f[i] end
		return t
	end
	local ssRes, ssTot, my = 0, 0, mean(ys)
	for i, r in ipairs(rows) do
		local p = 0
		for j, c in ipairs(coef) do p += c * r[j] end
		ssRes += (ys[i] - p) ^ 2
		ssTot += (ys[i] - my) ^ 2
	end

	-- stats of a slot assignment → predicted time
	local function statsFor(slots)
		local st = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
			slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
		return VehicleStats.applyMobility(st, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	end
	local function paceOf(slots)
		return pace(KineSim.carFromStats(statsFor(slots), Constants, biome))
	end

	-- ── 2. abilities ────────────────────────────────────────────────────────
	local median = all[math.floor(#all / 2)]
	local baseCar = KineSim.carFromStats(median.stats, Constants, biome)
	local base = {}
	for seed = 1, seeds do base[seed] = time(race(baseCar, seed)) end
	local baseMean = mean(base)

	-- mud / slow zone positions along the track (lifts and Drill skip them)
	local groundS = {}
	for _, tr in ipairs(world.triggers) do
		if table.find(tr.tags, "MudZone") then
			table.insert(groundS, world.geo:project(tr.cx, tr.cz).s)
		end
	end
	table.sort(groundS)
	local function groundAhead(s, from, to)
		for _, g in ipairs(groundS) do
			if g >= s + from and g <= s + to then return true end
		end
		return false
	end

	-- a sensible player's E for an ability that helps its user: a burst on a
	-- straight long enough for it, a lift or Drill just before mud, a
	-- refill when the gauge is empty
	local function selfPolicy(cfg, tr, log)
		local ready = Balance.START
		return function(ctx)
			if ctx.t < ready then return end
			local dur = cfg.duration or 1
			local go = false
			if tr.ground and groundAhead(ctx.s, 5, math.max(ctx.speed, 20) * dur * 0.6) then go = true end
			if not go and tr.refill then go = ctx.gauge() < 0.5 end
			if not go and tr.self then
				local m = math.max(cfg.selfSpeed or 1, 1)
				-- a player fires a burst on any straight-ish stretch; a burst with
				-- the steering locked only where it is straight all the way
				local dist = math.min(ctx.maxSpeed * m * dur * 0.5, 150)
				if cfg.selfTurn and cfg.selfTurn < 1 then dist = math.min(ctx.maxSpeed * m * dur * 1.1, 400) end
				go = math.abs(ctx.err) < 0.15 and ctx.straight(dist)
			end
			if not go then return end
			ready = ctx.t + cfg.cooldown
			log.uses += 1
			if cfg.selfSpeed and cfg.selfSpeed > 1 then ctx.mods:set("ability", cfg.selfSpeed, ctx.t + (cfg.selfFor or dur)) end
			if cfg.selfTurn and cfg.selfTurn ~= 1 then ctx.turn:set("ability", cfg.selfTurn, ctx.t + dur) end
			if cfg.push then ctx.knock(cfg.push, 0) end
			if tr.ground then ctx.ground(ctx.t + dur) end
			if tr.refill then ctx.refillBoost() end
		end
	end

	-- one victim run per distinct effect
	local victimCost = {}
	local function costOf(v)
		local key = sig(v)
		if victimCost[key] then return victimCost[key] end
		local deltas, hits = {}, 0
		for seed = 1, seeds do
			local nextHit = Balance.START + Balance.VICTIM_EVERY * (seed - 0.5) / seeds
			local h = 0
			local r = race(baseCar, seed, function(ctx)
				if ctx.t < nextHit then return end
				nextHit = ctx.t + Balance.VICTIM_EVERY
				h += 1
				if v.speed then ctx.mods:set("hit", v.speed, ctx.t + v.dur) end
				if v.turn then ctx.turn:set("hit", v.turn, ctx.t + v.dur) end
				if v.side then ctx.knock(v.back and -v.side or 0, v.back and 0 or ((h % 2 == 0) and v.side or -v.side)) end
				if v.push then ctx.knock(v.push, 0) end
			end)
			table.insert(deltas, time(r) - base[seed])
			hits += h
		end
		local c = math.max(0, mean(deltas) * seeds / math.max(hits, 1))
		victimCost[key] = c
		return c
	end

	local items = {}
	for name, icfg in pairs(ItemConfig) do
		if type(icfg) == "table" and icfg.slotType then
			local cfg = AbilityConfig.get(name, biome)
			if cfg and icfg.rarity == Constants.RARITY.EPIC then cfg = AbilityConfig.applyEpicBonus(cfg) end
			local tr = Balance.traits(cfg)
			local it = {
				name = name, slot = icfg.slotType, rarity = icfg.rarity, kind = Balance.label(tr), drop = tr.drop,
				effect = cfg and cfg.effectKey, cooldown = cfg and cfg.cooldown, duration = cfg and cfg.duration,
				selfGain = 0, uses = 0, hitCost = 0, hits = 0, offense = 0, shieldUptime = 0, liftUptime = 0, block = 0,
			}
			local raceT = baseMean - Balance.START
			if cfg then it.uses = math.floor(raceT / cfg.cooldown) + 1 end
			if tr.self or tr.ground or tr.refill then
				local gains, uses = {}, 0
				for seed = 1, seeds do
					local log = { uses = 0 }
					local r = race(baseCar, seed, selfPolicy(cfg, tr, log))
					table.insert(gains, base[seed] - time(r))
					uses += log.uses / seeds
				end
				it.selfGain = mean(gains)
				it.uses = uses
			end
			if tr.slow then
				-- the brake that comes with a shield, used when a hit is coming
				it.selfGain -= costOf({ speed = cfg.selfSpeed, dur = cfg.selfFor or cfg.duration }) * 0.5 * it.uses
			end
			if tr.offense then
				local v = victimEffect(cfg, Constants)
				it.hitRate = hitRate(cfg)
				it.hits = it.uses * it.hitRate
				it.hitCost = v and costOf(v) or 0
			end
			if tr.shield then
				it.shieldUptime = math.min(1, it.uses * (cfg.duration or 1) / baseMean)
				-- a cleanse needs no foresight: fire it within 2 s of a hit
				if cfg.effectKey == "bloomCleanse" then it.shieldUptime = math.min(1, it.uses * ((cfg.duration or 1) + 2) / baseMean) end
			end
			if tr.lift then
				it.liftUptime = math.min(1, it.uses * (cfg.duration or 1) / baseMean)
			end
			items[name] = it
		end
	end

	-- stat value: pace with the item vs an empty slot, averaged over every
	-- build of the other slots
	local statDelta = {}
	for name, it in pairs(items) do statDelta[name] = {} end
	for _, b in ipairs(all) do
		if not b.slots.MOBILITY then
			local t = paceOf(b.slots)
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				local without = table.clone(b.slots)
				without[slot] = nil
				table.insert(statDelta[b.slots[slot]], paceOf(without) - t)
			end
		end
	end
	for name, it in pairs(items) do
		it.statGain = mean(statDelta[name])
	end

	local out = {
		biome = biome, driver = opts.driver or Balance.DRIVER, seeds = seeds, runs = runs,
		baseTime = baseMean, baseBuild = Builds.describe(median),
		pace = { coef = coef, r2 = ssTot > 0 and 1 - ssRes / ssTot or 1, samples = samples },
		items = items, victimCost = victimCost,
		paceOf = paceOf, statsFor = statsFor,
	}
	-- expected race value: own gain + damage to the nearest rival (+ shields
	-- and lifts are valued in matches, against the hits actually thrown)
	for _, it in pairs(items) do
		it.offense = it.hits * it.hitCost
		it.value = it.statGain + it.selfGain + it.offense
	end
	-- protection is worth the hits a racer takes: in a symmetric field each
	-- racer takes what one racer throws (3 ability items, average offense)
	local thrown, dropThrown, count = 0, 0, 0
	for _, it in pairs(items) do
		count += 1
		if it.drop then dropThrown += it.offense else thrown += it.offense end
	end
	out.incoming = (thrown + dropThrown) / count * 3
	out.incomingDrops = dropThrown / count * 3
	for _, it in pairs(items) do
		it.block = it.shieldUptime * out.incoming + (1 - it.shieldUptime) * it.liftUptime * out.incomingDrops
		it.value += it.block
	end
	return out
end

-- seeded rng
local function rngFor(seed)
	local state = (seed * 48271) % 2147483647
	if state == 0 then state = 1 end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local function normal(rng)
	local u1, u2 = math.max(rng(), 1e-9), rng()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

--- Layer 3: Monte Carlo matches. B = Balance.measure(...).
-- opts: matches (2000), players (6), inventory {min, max} items, seed,
-- crafter "value" (picks the item worth most per slot) | "stat" (top speed).
function Balance.matches(B, opts, Constants, ItemConfig)
	opts = opts or {}
	local rng = rngFor(opts.seed or 1)
	local nPlayers = opts.players or 6
	local invMin, invMax = (opts.inventory or {})[1] or 5, (opts.inventory or {})[2] or Constants.INVENTORY_SIZE

	-- spawn pool: each rarity's share split over its items
	local pool, total = {}, 0
	local byRarity = {}
	for name, it in pairs(B.items) do
		byRarity[it.rarity] = byRarity[it.rarity] or {}
		table.insert(byRarity[it.rarity], name)
	end
	for rarity, list in pairs(byRarity) do
		table.sort(list)
		for _, name in ipairs(list) do
			local w = (Constants.RARITY_SPAWN_DIST[rarity] or 0) / #list
			total += w
			table.insert(pool, { name = name, w = w })
		end
	end
	table.sort(pool, function(a, b) return a.name < b.name end)
	local function draw()
		local r = rng() * total
		for _, p in ipairs(pool) do
			r -= p.w
			if r <= 0 then return p.name end
		end
		return pool[#pool].name
	end

	local function craft(inv)
		-- core slots: the held item of that type worth most; mobility: the
		-- leftover that gives the best pace
		local slots, used = {}, {}
		for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
			local best, bestV, bestI
			for i, name in ipairs(inv) do
				local it = B.items[name]
				if not used[i] and it.slot == slot then
					local v = opts.crafter == "stat" and it.statGain or it.value
					if not bestV or v > bestV then best, bestV, bestI = name, v, i end
				end
			end
			if best then slots[slot] = best; used[bestI] = true end
		end
		local bestT = B.paceOf(slots)
		for i, name in ipairs(inv) do
			if not used[i] then
				local s2 = table.clone(slots)
				s2.MOBILITY = name
				local t = B.paceOf(s2)
				if t < bestT then bestT = t; slots.MOBILITY = name end
			end
		end
		return slots, bestT
	end

	local res = {
		matches = opts.matches or 2000, players = nPlayers,
		wins = {}, held = {}, equipped = {}, winsBySlot = { BODY = {}, ENGINE = {}, SPECIAL = {} },
		cores = {}, topRarityWins = 0, lowRarityWins = 0, lowRarityShare = 0,
		marginSum = 0, winnerRarity = {}, fieldRarity = {},
	}
	local function rarityScore(slots)
		local s = 0
		for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
			local it = slots[slot] and B.items[slots[slot]]
			s += it and RANK[it.rarity] or 0
		end
		return s
	end

	for _ = 1, res.matches do
		local field = {}
		for p = 1, nPlayers do
			local inv = {}
			for _ = 1, invMin + math.floor(rng() * (invMax - invMin + 1)) do table.insert(inv, draw()) end
			local slots, t = craft(inv)
			local f = { slots = slots, time = t + normal(rng) * Balance.NOISE, rarity = rarityScore(slots), shield = 0, lift = 0 }
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				local it = slots[slot] and B.items[slots[slot]]
				if it then
					f.time -= it.selfGain
					f.shield = 1 - (1 - f.shield) * (1 - it.shieldUptime)
					f.lift = 1 - (1 - f.lift) * (1 - it.liftUptime)
					res.equipped[it.name] = (res.equipped[it.name] or 0) + 1
				end
			end
			field[p] = f
		end
		-- harmful abilities land on the rival nearest in the running order
		local order = {}
		for p = 1, nPlayers do order[p] = p end
		table.sort(order, function(a, b) return field[a].time < field[b].time end)
		local place = {}
		for i, p in ipairs(order) do place[p] = i end
		local damage = table.create(nPlayers, 0)
		for p = 1, nPlayers do
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				local it = field[p].slots[slot] and B.items[field[p].slots[slot]]
				if it and it.offense > 0 then
					local i = place[p]
					local victim
					if it.drop then
						victim = order[i + 1]                                -- the car behind
					else
						local a, b = order[i - 1], order[i + 1]
						if a and b then
							victim = (math.abs(field[a].time - field[p].time) < math.abs(field[b].time - field[p].time)) and a or b
						else
							victim = a or b
						end
					end
					if victim then
						local f = field[victim]
						local blocked = it.drop and (1 - (1 - f.shield) * (1 - f.lift)) or f.shield
						damage[victim] += it.offense * (1 - blocked)
					end
				end
			end
		end
		local best, bestT, second = nil, math.huge, math.huge
		for p = 1, nPlayers do
			field[p].time += damage[p]
			if field[p].time < bestT then
				second = bestT
				best, bestT = p, field[p].time
			elseif field[p].time < second then
				second = field[p].time
			end
		end
		local w = field[best]
		res.marginSum += second - bestT
		local maxR, minR = -1, math.huge
		for p = 1, nPlayers do
			maxR = math.max(maxR, field[p].rarity)
			minR = math.min(minR, field[p].rarity)
			res.fieldRarity[field[p].rarity] = (res.fieldRarity[field[p].rarity] or 0) + 1
		end
		if w.rarity == maxR then res.topRarityWins += 1 end
		res.winnerRarity[w.rarity] = (res.winnerRarity[w.rarity] or 0) + 1
		local core = string.format("%s + %s + %s", w.slots.BODY or "-", w.slots.ENGINE or "-", w.slots.SPECIAL or "-")
		res.cores[core] = (res.cores[core] or 0) + 1
		for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
			local name = w.slots[slot] or "(empty)"
			res.winsBySlot[slot][name] = (res.winsBySlot[slot][name] or 0) + 1
			if w.slots[slot] then res.wins[name] = (res.wins[name] or 0) + 1 end
		end
	end

	-- summaries
	res.distinctCores = 0
	local topCore, topCoreN = nil, 0
	for core, k in pairs(res.cores) do
		res.distinctCores += 1
		if k > topCoreN then topCore, topCoreN = core, k end
	end
	res.topCore, res.topCoreShare = topCore, topCoreN / res.matches
	res.topItemShare = {}
	for slot, t in pairs(res.winsBySlot) do
		local name, k = nil, 0
		for n2, c in pairs(t) do if c > k then name, k = n2, c end end
		res.topItemShare[slot] = { item = name, share = k / res.matches }
	end
	res.upsetRate = 1 - res.topRarityWins / res.matches
	res.avgMargin = res.marginSum / res.matches
	-- win lift: share of wins / share of equips (1 = average)
	res.lift = {}
	local equips = 0
	for _, k in pairs(res.equipped) do equips += k end
	local winsTotal = 0
	for _, k in pairs(res.wins) do winsTotal += k end
	for name, k in pairs(res.equipped) do
		res.lift[name] = ((res.wins[name] or 0) / math.max(winsTotal, 1)) / (k / equips)
	end
	return res
end

--- Targets (Constants.BALANCE_TARGETS) → list of { name, ok, value, target, why }.
function Balance.check(B, m, T)
	local out = {}
	local function add(name, ok, value, target, why)
		table.insert(out, { name = name, ok = ok, value = value, target = target, why = why })
	end
	-- tiers per slot
	local tiers = {}
	for _, it in pairs(B.items) do
		tiers[it.slot] = tiers[it.slot] or {}
		tiers[it.slot][it.rarity] = tiers[it.slot][it.rarity] or {}
		table.insert(tiers[it.slot][it.rarity], it.value)
	end
	for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
		local means, prev, ordered = {}, -math.huge, true
		for _, r in ipairs(Balance.TIERS) do
			local v = mean(tiers[slot][r] or {})
			means[r] = v
			if tiers[slot][r] and v < prev + T.tierStep then ordered = false end
			if tiers[slot][r] then prev = v end
		end
		add(slot .. " tiers rise", ordered,
			string.format("%.1f / %.1f / %.1f / %.1f", means.Common, means.Uncommon, means.Rare, means.Epic),
			string.format("each ≥ %.1f s above the last", T.tierStep), "a rarer item is noticeably better on average")
		local edge = means.Epic - means.Common
		add(slot .. " Epic − Common", edge >= T.epicEdge.min and edge <= T.epicEdge.max, string.format("%.1f s", edge),
			string.format("%.1f .. %.1f s", T.epicEdge.min, T.epicEdge.max), "rare is better, not overwhelming")
	end
	-- no item far above its tier, none useless
	local outliers, dead = {}, {}
	for _, it in pairs(B.items) do
		local peers = tiers[it.slot][it.rarity]
		if #peers > 1 and it.value - mean(peers) > T.maxAboveTier then
			table.insert(outliers, string.format("%s %+.1f", it.name, it.value - mean(peers)))
		end
		if it.value < T.minItemValue then table.insert(dead, string.format("%s %.1f", it.name, it.value)) end
	end
	table.sort(outliers)
	table.sort(dead)
	add("no item far above its tier", #outliers == 0, #outliers == 0 and "none" or table.concat(outliers, ", "),
		string.format("≤ %.1f s above its tier's mean", T.maxAboveTier), "one item must not decide every build")
	add("every item helps", #dead == 0, #dead == 0 and "all" or table.concat(dead, ", "),
		string.format("≥ %.1f s per race", T.minItemValue), "no trap items")
	-- matches
	local worst, worstSlot = 0, nil
	for slot, t in pairs(m.topItemShare) do
		if t.share > worst then worst, worstSlot = t.share, slot .. ": " .. tostring(t.item) end
	end
	add("winning item variety", worst <= T.maxTopItemShare, string.format("%.0f%% (%s)", worst * 100, tostring(worstSlot)),
		string.format("≤ %.0f%% of wins", T.maxTopItemShare * 100), "many items show up in winning builds")
	local perK = m.distinctCores / m.matches * 1000
	add("distinct winning builds", perK >= T.minDistinctWinnersPer1000, string.format("%.0f per 1000", perK),
		string.format("≥ %d per 1000 matches", T.minDistinctWinnersPer1000), "different combinations win")
	add("upsets", m.upsetRate >= T.minUpsetRate, string.format("%.0f%%", m.upsetRate * 100),
		string.format("≥ %.0f%%", T.minUpsetRate * 100), "the rarest build does not always win")
	add("rarest build still favoured", m.upsetRate <= T.maxUpsetRate, string.format("%.0f%%", (1 - m.upsetRate) * 100),
		string.format("≥ %.0f%%", (1 - T.maxUpsetRate) * 100), "farming rare items pays off")
	return out
end

return Balance
