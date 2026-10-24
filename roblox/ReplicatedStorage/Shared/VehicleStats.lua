-- VehicleStats.lua
-- Pure functions: item combination + biome → vehicle stats table.
-- No Roblox API used — fully unit-testable outside Studio.
-- Resolves: Issue #7, #61

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local B = Constants.BALANCE
local R = Constants.RARITY

local VehicleStats = {}

-- ─── Rarity multiplier ────────────────────────────────────────────────────────

local function rarityMult(rarity)
	return Constants.RARITY_STAT_MULT[rarity] or 1.0
end

-- ─── Apply biome bonus to a single item ───────────────────────────────────────

local function biomeScale(itemCfg, biome)
	if itemCfg.biomeBonus and itemCfg.biomeBonus[biome] then
		return itemCfg.biomeBonus[biome]
	end
	return 1.0
end

-- ─── Normalise stats so their total ≤ STAT_BUDGET ────────────────────────────
-- Proportionally scales all stats down if they would exceed the cap.
-- This prevents any single combination from being dramatically overpowered.

local function normaliseToBudget(stats)
	local total = 0
	for _, v in pairs(stats) do
		total = total + v
	end
	if total <= B.STAT_BUDGET then
		return stats
	end
	local scale = B.STAT_BUDGET / total
	local out = {}
	for k, v in pairs(stats) do
		out[k] = v * scale
	end
	return out
end

-- ─── Main calculation ─────────────────────────────────────────────────────────
--
-- @param bodyCfg    ItemConfig entry for the BODY slot (or nil)
-- @param engineCfg  ItemConfig entry for the ENGINE slot (or nil)
-- @param specialCfg ItemConfig entry for the SPECIAL slot (or nil)
-- @param biome      string: "FOREST" | "OCEAN" | "SKY"
--
-- @returns stats table:
--   speed          – top speed
--   acceleration   – how quickly top speed is reached
--   stability      – resistance to spinning out / bouncing
--   floatability   – effectiveness on water (OCEAN)
--   flyability     – effectiveness in the air (SKY)
--   boostDuration  – seconds of boost (from SPECIAL boost stat)

function VehicleStats.calculate(bodyCfg, engineCfg, specialCfg, biome)
	-- Defaults for empty slots. A ridden non-BODY item (ItemConfig `ride`,
	-- CraftingRules.fits) counts with its ride weight and grip.
	if bodyCfg and bodyCfg.slotType ~= "BODY" and bodyCfg.ride then
		bodyCfg = { weight = bodyCfg.ride.weight, grip = bodyCfg.ride.grip, rarity = bodyCfg.rarity,
			biomeBonus = bodyCfg.ride.biomeBonus }
	end
	local body    = bodyCfg    or { weight = 8,  grip = 0.5,  rarity = R.COMMON }
	local engine  = engineCfg  or { power  = 10, rarity = R.COMMON }
	local special = specialCfg or { boost  = 10, rarity = R.COMMON }

	-- Rarity multipliers
	local bMult = rarityMult(body.rarity)
	local eMult = rarityMult(engine.rarity)
	local sMult = rarityMult(special.rarity)

	-- Biome bonuses
	local bBio  = biomeScale(body,    biome)
	local eBio  = biomeScale(engine,  biome)

	-- Effective values after rarity + biome (guard against wrong-slot items missing fields)
	local effectivePower  = (engine.power  or 10) * eMult * eBio
	-- Weight is a cost: rarity does not make it heavier. (Before 2026-10-22 it
	-- was × bMult, so an Epic body weighed twice its listed weight and every
	-- Rare / Epic body accelerated worst.)
	local effectiveWeight = (body.weight   or 8)
	local effectiveGrip   = (body.grip     or 0.5) * bMult * bBio
	local effectiveBoost  = (special.boost or 10) * sMult

	-- Core stat formulas
	local speed = B.BASE_SPEED
		+ effectivePower  * B.powerSpeedBonus

	local acceleration = B.BASE_ACCEL
		+ effectivePower  * B.powerAccelBonus
		- effectiveWeight * B.weightAccelPenalty

	local stability = B.BASE_STAB
		+ effectiveGrip   * B.gripTurnBonus
		+ effectiveWeight * B.weightStabBonus
		- effectivePower  * 0.10  -- powerful engines slightly reduce stability

	-- Biome-specific stats
	local floatability = effectiveGrip * B.gripFloatBonus * bBio
	if body.floatabilityBonus then
		floatability = floatability * body.floatabilityBonus
	end
	if biome == "OCEAN" then
		floatability = floatability + 20
	end

	-- light bodies fly better; grip (control surfaces, rarity included) helps
	-- too, so a heavy Rare / Epic body is not a dead weight in SKY
	local flyability = (1 / math.max(effectiveWeight, 1)) * 10 + effectiveGrip * B.gripFlyBonus
	if body.flyabilityBonus then
		flyability = flyability * body.flyabilityBonus
	end
	if biome == "SKY" then
		flyability = flyability + 15
	end

	-- Boost duration in seconds: a base plus the boost stat, capped. (Before
	-- 2026-10-22 it was boost × 0.08 up to 8 s: 0.8 s for a Common SPECIAL,
	-- 8 s for an Epic one, worth ~12 s per race on its own.)
	local boostDuration = math.min(B.BOOST_BASE + effectiveBoost * B.BOOST_PER_POINT, B.BOOST_MAX)

	-- Clamp negatives (e.g. very heavy body could make accel negative)
	speed        = math.max(speed, 5)
	acceleration = math.max(acceleration, 2)
	stability    = math.max(stability, 1)
	floatability = math.max(floatability, 0)
	flyability   = math.max(flyability, 0)

	local stats = {
		speed        = speed,
		acceleration = acceleration,
		stability    = stability,
		floatability = floatability,
		flyability   = flyability,
		boostDuration = boostDuration,
	}

	-- Normalise everything except boostDuration to the shared budget
	local forNorm = {
		speed        = stats.speed,
		acceleration = stats.acceleration,
		stability    = stats.stability,
		floatability = stats.floatability,
		flyability   = stats.flyability,
	}
	local normed = normaliseToBudget(forNorm)

	normed.boostDuration = stats.boostDuration
	return normed
end

-- ─── MOBILITY slot modifier ───────────────────────────────────────────────────
-- Call after calculate() to apply the MOBILITY slot bonus/penalty.
--
-- @param stats       result of calculate()
-- @param mobCfg      ItemConfig entry for the MOBILITY slot (or nil)
-- @param biome       string
-- @param biomeSlotName  "WHEELS" | "SAIL" | "WINGS"
-- @returns modified stats table

function VehicleStats.applyMobility(stats, mobCfg, biome)
	local out = {}
	for k, v in pairs(stats) do out[k] = v end

	if not mobCfg then
		-- Penalty for empty mobility slot
		local penalty = 1 - Constants.MOBILITY_EMPTY_PENALTY
		if biome == "OCEAN" then
			out.floatability = out.floatability * penalty
		elseif biome == "SKY" then
			out.flyability   = out.flyability   * penalty
		else  -- FOREST
			out.stability    = out.stability    * penalty
		end
		return out
	end

	-- Check biome affinity of the mobility item
	local isAffinityMatch = mobCfg.mobilityAffinity and mobCfg.mobilityAffinity[biome]
	local mobBio = isAffinityMatch and B.biomeStatMult or 1.0
	local mobMult = rarityMult(mobCfg.rarity) * mobBio

	if biome == "OCEAN" then
		out.floatability = out.floatability * mobMult
		out.speed        = out.speed * (1 + (mobMult - 1) * 0.5)
	elseif biome == "SKY" then
		out.flyability   = out.flyability   * mobMult
		out.stability    = out.stability    * (1 + (mobMult - 1) * 0.4)
	else  -- FOREST
		out.stability    = out.stability    * mobMult
		out.acceleration = out.acceleration * (1 + (mobMult - 1) * 0.3)
	end

	return out
end

-- ─── HEAD / TAIL passive bonuses ─────────────────────────────────────────────
-- These are small additive tweaks; major active effects live in AbilityConfig.
-- Kept here so the crafting UI can reflect them in the preview.

-- Applied by RacingManager through Shared/Passives.lua.
VehicleStats.HEAD_PASSIVES = {
	["Shopping Cart"]  = { collisionPower = 1.50 },     -- rear-end shove ×1.5
	["Cactus"]         = { headCollisionSlow = 1.0 },   -- slows the car you rear-end (seconds)
	["Rubber Duck"]    = { absorbOneHit = true },       -- first hit of the race is ignored
	["Racing Flag"]    = { leadSpeedBonus = 0.05 },     -- +5% when in 1st place
	["Flower"]         = { momentumBonus = 0.03 },      -- small per-5s accel bonus
}

VehicleStats.TAIL_PASSIVES = {
	["Rocket"]         = { boostDurationAdd = 1.0 },    -- +1s to boost
	["Soda Bottle"]    = { boostBlindTrail = true },     -- boosting blinds the car behind
	["Toilet Paper"]   = { slipstreamSlow = 0.10 },      -- -10% to car directly behind
	["Balloon Bunch"]  = { rearImpactAbsorb = true },   -- bumper absorbs rear hit
	["Cactus"]         = { rearContactSlow = 1.5 },      -- slows anyone who rear-ends you
}

return VehicleStats
