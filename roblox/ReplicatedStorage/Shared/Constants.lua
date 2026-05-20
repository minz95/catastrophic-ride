-- Constants.lua
-- Single source of truth for all game-wide values.
-- Every other module must read from here — no magic numbers in logic files.
-- Resolves: Issue #2, #63

local Constants = {}

-- ─── Phase Names ──────────────────────────────────────────────────────────────
Constants.PHASES = {
	LOBBY    = "LOBBY",
	FARMING  = "FARMING",
	CRAFTING = "CRAFTING",
	RACING   = "RACING",
	RESULTS  = "RESULTS",
}

-- ─── Phase Durations (seconds) ────────────────────────────────────────────────
-- FARMING: 90s gives 30s competition window after initial collection
-- CRAFTING: 120s for 6-slot assignment + strategy time (Issue #63)
Constants.PHASE_DURATION = {
	FARMING  = 90,
	CRAFTING = 120,
	RACING   = nil, -- ends on finish, timeout below
}
Constants.RACING_TIMEOUT = 180 -- 3-minute failsafe

-- ─── Player / Session ─────────────────────────────────────────────────────────
Constants.MAX_PLAYERS    = 10
Constants.SKIN_COUNT     = 10   -- must match ServerStorage/CharacterSkins count
Constants.MIN_TO_START   = 1    -- minimum players before LOBBY ends (1 = solo test OK)
Constants.SOLO_TEST_MODE = true  -- set false in production; skips lobby wait

-- ─── Inventory ────────────────────────────────────────────────────────────────
Constants.INVENTORY_SIZE       = 8
Constants.STEAL_DISABLE_BEFORE = 5   -- seconds before CRAFTING that stealing locks

-- ─── Item World ───────────────────────────────────────────────────────────────
Constants.ITEM_SPAWN_COUNT = 100
Constants.PICKUP_RANGE     = 10  -- studs
Constants.STEAL_RANGE      = 5   -- studs

-- ─── Crafting Slots ───────────────────────────────────────────────────────────
Constants.CRAFT_SLOTS = {
	BODY     = "BODY",
	ENGINE   = "ENGINE",
	SPECIAL  = "SPECIAL",
	MOBILITY = "MOBILITY", -- biome-specific: WHEELS / SAIL / WINGS
	HEAD     = "HEAD",
	TAIL     = "TAIL",
}
Constants.MOBILITY_SLOT_NAMES = {
	FOREST = "WHEELS",
	OCEAN  = "SAIL",
	SKY    = "WINGS",
}
Constants.MOBILITY_EMPTY_PENALTY = 0.30  -- 30% reduction to biome core stat

-- ─── Vehicle / Track ──────────────────────────────────────────────────────────
-- Per-biome track dimensions. Races run along -Z from zStart to zFinish.
-- Lengths derived from the per-biome racetrack spec (90s playtime × avg speed):
--   FOREST 4700-stud path / 2600-stud Z-extent (figure-3 + U-bend, path/Z ~1.8)
--   OCEAN  3400-stud path / 2100-stud Z-extent (arc-S + U-bend,    path/Z ~1.6)
--   SKY    7800-stud path / 3500-stud Z-extent (planar figure-8,   path/Z ~2.2)
Constants.TRACK = {
	FOREST = { zStart = 600,  zFinish = -2000, width = 40 },
	OCEAN  = { zStart = 600,  zFinish = -1500, width = 60 },
	SKY    = { zStart = 1500, zFinish = -2000, width = 50 },
}

function Constants.getTrackLength(biome)
	local t = Constants.TRACK[biome]
	assert(t, "Constants.getTrackLength: unknown biome " .. tostring(biome))
	return t.zStart - t.zFinish
end

-- ─── Racing ───────────────────────────────────────────────────────────────────
Constants.BOOST_DURATION   = 2    -- seconds
Constants.BOOST_MULTIPLIER = 1.5
Constants.BOOST_COOLDOWN   = 5
Constants.POSITION_SYNC_RATE = 0.5  -- seconds between PlayerPositionSync broadcasts

-- ─── Drift / DriftCorner ──────────────────────────────────────────────────────
-- Driving through a tagged DriftCorner zone fills the boost gauge by this amount.
-- Key bindings: Shift = drift slide; F = activate boost when gauge is full.
Constants.DRIFT_CHARGE_PER_CORNER = 0.5   -- 2 corners = full gauge
Constants.DRIFT_CORNER_COOLDOWN   = 8     -- seconds before same zone charges again

-- ─── Farming Contest (button-mash) ────────────────────────────────────────────
Constants.CONTEST_DURATION   = 2.5  -- seconds
Constants.STEAL_COOLDOWN     = 8    -- seconds between steal attempts
Constants.STEAL_INVINCIBLE   = 3    -- seconds of steal immunity after being robbed
Constants.STEAL_DEFEND_WINDOW = 1   -- seconds victim has to defend
Constants.STEAL_DEFEND_PRESSES = 3  -- taps needed to block

-- ─── Rarity ───────────────────────────────────────────────────────────────────
Constants.RARITY = {
	COMMON   = "Common",
	UNCOMMON = "Uncommon",
	RARE     = "Rare",
	EPIC     = "Epic",
}
Constants.RARITY_SPAWN_DIST = {  -- out of ITEM_SPAWN_COUNT = 100
	Common   = 60,
	Uncommon = 25,
	Rare     = 12,
	Epic     = 3,
}
Constants.RARITY_STAT_MULT = {
	Common   = 1.0,
	Uncommon = 1.3,
	Rare     = 1.6,
	Epic     = 2.0,
}
Constants.EPIC_ABILITY_BONUS = {
	duration  = 1.30,  -- ×1.3 effect duration
	radius    = 1.20,  -- ×1.2 radius
	cooldown  = 0.80,  -- ×0.8 cooldown (shorter)
}

-- ─── Balance Tuning ───────────────────────────────────────────────────────────
-- Centralised here so plytests can adjust without touching formulas (Issue #61)
Constants.BALANCE = {
	BASE_SPEED       = 20,
	BASE_ACCEL       = 10,
	BASE_STAB        = 30,

	powerSpeedBonus  = 0.30,   -- engine power → speed
	powerAccelBonus  = 0.50,   -- engine power → acceleration
	weightAccelPenalty = 0.40, -- body weight → accel reduction
	weightStabBonus    = 0.80, -- body weight → stability bonus
	gripTurnBonus      = 20,   -- body grip → turn rate

	STAT_BUDGET      = 100,    -- total stat normalisation cap (Issue #61)
	biomeStatMult    = 1.30,   -- bonus for biome-matched items
}

-- ─── Biomes ───────────────────────────────────────────────────────────────────
Constants.BIOMES = { "FOREST", "OCEAN", "SKY" }
Constants.VEHICLE_TYPE = {
	FOREST = "Car",
	OCEAN  = "Boat",
	SKY    = "FlyingVehicle",
}

-- ─── Collision / Physics ──────────────────────────────────────────────────────
Constants.OBSTACLE_BOUNCE_PENALTY_DURATION = 1.0  -- seconds
Constants.OBSTACLE_BOUNCE_SPEED_MULT       = 0.5
Constants.MUD_SPEED_MULT                   = 0.5
Constants.SLOW_ZONE_MULT                   = 0.6  -- off-corridor soft penalty
Constants.RACE_BOOST_PAD_ACTIVE_RATIO      = 0.6  -- fraction of placed BoostPads active per race
Constants.SKY_GRAVITY_MULT                 = 1.2  -- outside updraft zones
Constants.UPDRAFT_BASE_FORCE               = 200  -- studs/s² upward (scaled by flyability)

-- ─── Emotes ───────────────────────────────────────────────────────────────────
Constants.EMOTE_IDS = { "Wave", "Dance", "Laugh" }

return Constants
