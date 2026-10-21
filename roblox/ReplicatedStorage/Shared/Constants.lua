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
	RESULTS  = 30,
}
Constants.RACE_COUNTDOWN = 4 -- s from RACING to GO (cars spawn and seat, then 3-2-1); Modules/RaceStart
Constants.RACING_TIMEOUT = 240 -- failsafe; the slowest build with a novice driver needs ~180 s on the 2026-10-20 tracks

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
	FOREST = { zStart = 600,  zFinish = -3050, width = 40 },
	OCEAN  = { zStart = 600,  zFinish = -2800, width = 60 },
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

-- ─── Fun as numbers (Shared/RaceMetrics, tools/report.luau, PlaytestReport) ──
-- Starting targets, not truths: playtests decide. A report marks each value
-- inside / outside its range so a change can be judged against them.
Constants.FUN = {
	PROGRESS_EVERY = 1,   -- s between race_progress telemetry samples
	MARK_COOLDOWN  = 1,   -- s between playtest markers from one player
}
Constants.FUN_TARGETS = {
	winnerTime   = { min = 60,  max = 120, why = "a race should take about 90 s" },
	finishRate   = { min = 0.9,            why = "almost everyone finishes" },
	finishSpread = {            max = 45,  why = "nobody waits long for the last car" },
	leadChanges  = { min = 1,              why = "the lead changes at least once" },
	closeShare   = { min = 0.25,           why = "the top two race each other a quarter of the time" },
	racingShare  = { min = 0.35,           why = "share of a round spent racing (vs farming / crafting / results)" },
	fastestWinRate = {          max = 0.7, why = "the fastest build should not always win" },
	speedPlaceCorr = { min = -0.6, max = 0.1, why = "the build helps a little; it must not decide the race" },
}

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
Constants.STEAL_DEFENDED_COOLDOWN = 0.5 -- thief may try again this soon after a defended attempt

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

-- Lift abilities raise the car's ride height (studs) for their duration:
-- Modules/VehicleLift sets the chassis "LiftOffset" attribute and
-- VehicleController adds it to the hover target. (An upward BodyForce, as
-- before, could not beat the ride-height BodyPosition: cars rose < 0.3 studs.)
-- FOREST walls are 8 studs high: keep every lift below that.
Constants.ABILITY_LIFT = {
	rise           = 4,     -- Balloon Bunch, Lantern
	hover          = 3.5,   -- Propeller Hat
	emergencyFloat = 3,     -- Rubber Duck
	fullBuoyancy   = 3,     -- Rubber Duck (OCEAN)
	softLanding    = 3,     -- Rubber Duck (SKY)
	groundBounce   = 3,     -- Rubber Duck (FOREST), short hop
	lifeFloat      = 3.5,   -- Life Preserver
	kiteLift       = 4,     -- Kite
	kiteGlide      = 4,     -- Kite (SKY)
	parachute      = 2,     -- Umbrella (SKY)
	RATE           = 12,    -- studs per second the offset moves (up and down)
}

-- Studio harness: how each effect's car is measured (Modules/EffectFx).
Constants.EFFECT_PROBE = {
	STEP     = 0.1,   -- s between samples
	FRACTION = 0.6,   -- of the effect duration
	MIN      = 0.5,   -- s, shortest window (bursts)
	MAX      = 1.5,   -- s, longest window
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

-- ─── Driving model (VehicleController) ────────────────────────────────────────
-- The commanded forward speed ramps instead of jumping to MaxSpeed:
--   acceleration (studs/s²) = ACCEL_BASE + VehicleSeat.Torque * ACCEL_PER_TORQUE
-- so the acceleration stat (Torque = acceleration × 4) matters.
Constants.DRIVE = {
	ACCEL_BASE       = 20,
	ACCEL_PER_TORQUE = 0.3,
	COAST_DECEL      = 30,   -- W released: roll to a stop
	BRAKE_DECEL      = 90,   -- S held, or MaxSpeed dropped below the current speed
	BLOCKED_SLACK    = 10,   -- command may not run more than this ahead of the real speed
	DRIFT_TURN_MULT  = 0.35, -- drifting turns slower but keeps speed
	DRIFT_TURN_MIN   = 0.3,
}

-- ─── Top speed: stat → VehicleSeat.MaxSpeed ──────────────────────────────────
-- The build may not decide the race: every car's top speed sits within
-- ±`spread` of the biome's `center`. The speed stat (p10 `lo` .. p90 `hi` of
-- all item combinations) only picks the place inside that band, so a better
-- build is a little faster and driving, boosts and items decide the rest.
-- Centers put the best build with a good driver at about 85 s per race.
-- (Before 2026-10-21 MaxSpeed was speed × 2.5 / 2.0 / 3.0: the fastest
-- build was 1.8× the slowest and the field finished 50–60 s apart.)
Constants.RACE_SPEED = {
	FOREST = { center = 69, spread = 0.06, lo = 22, hi = 33 },
	OCEAN  = { center = 63, spread = 0.06, lo = 20, hi = 40 },
	SKY    = { center = 87, spread = 0.06, lo = 21, hi = 30 },
}

function Constants.maxSpeedFor(biome, stats)
	local t = Constants.RACE_SPEED[biome] or Constants.RACE_SPEED.FOREST
	local f = math.clamp(((stats.speed or 0) - t.lo) / (t.hi - t.lo), 0, 1)
	return t.center * (1 + t.spread * (2 * f - 1))
end

-- Acceleration: VehicleSeat.Torque = acceleration × scale, clamped.
Constants.SEAT_TORQUE = {
	FOREST = { scale = 4, min = 20, max = 200 },
	OCEAN  = { scale = 3, min = 15, max = 120 },
	SKY    = { scale = 5, min = 30, max = 250 },
}

function Constants.torqueFor(biome, stats)
	local t = Constants.SEAT_TORQUE[biome] or Constants.SEAT_TORQUE.FOREST
	return math.clamp((stats.acceleration or 0) * t.scale, t.min, t.max)
end

-- ─── Handling: stat → VehicleSeat.TurnSpeed ───────────────────────────────────
-- Linear map of a biome's handling stat onto [min, max], clamped. The ranges
-- cover roughly the 10th–90th percentile of all item combinations, so BODY and
-- MOBILITY choices change how the vehicle turns.
-- SKY tops out at VehicleController.SKY_TURN_CAP (1.5): the old map
-- (flyability × 0.4, clamped 0.5–4.0) put every build at or above the cap, so
-- flyability did nothing for handling.
Constants.TURN_SPEED = {
	FOREST = { stat = "stability",    lo = 20, hi = 100, min = 2.0, max = 3.2 },
	OCEAN  = { stat = "floatability", lo = 10, hi = 45,  min = 1.2, max = 2.0 },
	SKY    = { stat = "flyability",   lo = 8,  hi = 36,  min = 1.0, max = 1.5 },
}

function Constants.turnSpeedFor(biome, stats)
	local t = Constants.TURN_SPEED[biome]
	if not t then return 1 end
	local v = stats[t.stat] or 0
	if t.scale then
		return math.clamp(v * t.scale, t.min, t.max)
	end
	local f = math.clamp((v - t.lo) / (t.hi - t.lo), 0, 1)
	return t.min + f * (t.max - t.min)
end

-- ─── HEAD / TAIL passives (RacingManager) ─────────────────────────────────────
Constants.PASSIVES = {
	CONTACT_COOLDOWN   = 1.0,   -- s between effects for the same pair of cars
	REAR_END_DOT       = 0.5,   -- attacker must face the victim this squarely
	HEAD_SLOW_MULT     = 0.5,   -- Cactus head: victim speed
	HEAD_SLOW_TIME     = 1.0,
	REAR_SLOW_MULT     = 0.5,   -- Cactus tail: attacker speed
	RAM_PUSH           = 30,    -- base shove (studs/s) when rear-ending
	SLIPSTREAM_RANGE   = 25,    -- Toilet Paper tail: car directly behind
	SLIPSTREAM_CONE    = 0.85,  -- dot(leaderLook, toFollower) <= -this
	LEAD_PERIOD        = 0.5,   -- s between lead / momentum / slipstream checks
	MOMENTUM_STEP      = 5,     -- s of clean driving per Flower bonus step
	MOMENTUM_MAX       = 0.15,
	BLIND_TIME         = 1.5,   -- Soda Bottle tail: follower blinded on boost
}

-- ─── Track hazards (HazardManager, see BiomeConfig.hazards) ───────────────────
Constants.HAZARDS = {
	LOG_SIZE          = { 7, 2.2, 2.2 },
	LOG_DROP_HEIGHT   = 22,
	LOG_LIFETIME      = 6,
	LOG_AHEAD_MIN     = 80,     -- studs of track ahead of the leading car
	LOG_AHEAD_MAX     = 260,
	LOG_LATERAL       = 12,     -- max offset from the centerline
	GUST_DURATION     = 2,
	GUST_PULSE        = 0.25,   -- s between sideways shoves while a gust blows
	GUST_PUSH_PER_FORCE = 0.12, -- shove speed (studs/s) per unit of BiomeConfig force
	FLOOD_STEPS       = 10,     -- water rises/falls in this many steps over 1 s
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
