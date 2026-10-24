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
-- Idle time (2026-10-22, from the Studio match reports): with 100 items for
-- 4 players every inventory was full 15–50 s into FARMING; ready crafters
-- waited for the slowest one up to 2 min; finished racers waited up to the
-- 240 s timeout for the last car.
Constants.FARM_SUPPLY = {
	BASE = 12, PER_PLAYER = 6,        -- items at the start: BASE + PER_PLAYER × players (≤ ITEM_SPAWN_COUNT)
	WAVES = {                         -- more items later, rarer ones (at = share of the phase)
		{ at = 0.35, perPlayer = 1.5, dist = { Common = 30, Uncommon = 35, Rare = 25, Epic = 10 } },
		{ at = 0.65, perPlayer = 1.5, dist = { Common = 15, Uncommon = 35, Rare = 35, Epic = 15 } },
	},
}
function Constants.farmSupply(players)
	local F = Constants.FARM_SUPPLY
	return math.min(Constants.ITEM_SPAWN_COUNT, F.BASE + F.PER_PLAYER * math.max(players or 1, 1))
end
-- Half the players submitted → the rest get 40 s. Estimated (keystroke model,
-- 2026-10-23): an experienced player crafts in 35–50 s, a first-timer in
-- 60–90 s; with 25 s a first-timer was cut off around 65 s.
Constants.CRAFT_HURRY  = { SHARE = 0.5, SECONDS = 40 }
-- s the others get after the winner crosses the line. 45 = FUN_TARGETS
-- finishSpread: a novice is ~1.35× the winner's time, 30-40 s on the
-- 2026-10-22 tracks (30 s cut the Studio SKY novice short)
Constants.FINISH_GRACE = 45
-- …at least; after a slow winner it grows to FINISH_GRACE_SHARE of the
-- winner's time (capped): a fast winner (92 s, Studio 2026-10-23) left the
-- novice 170 studs short with a flat 45 s. Shared/CatchUp.graceFor.
Constants.FINISH_GRACE_SHARE = 0.5
Constants.FINISH_GRACE_MAX   = 75
-- Catch-up: a car GAP_START studs or more behind the leader gets up to
-- +MAX top speed, full at GAP_FULL studs (Shared/CatchUp, RacingManager).
-- The leader never gets it, so a build or a driver still wins on merit.
Constants.CATCH_UP = { GAP_START = 60, GAP_FULL = 400, MAX = 0.12 }
Constants.RACE_COUNTDOWN = 4 -- s from RACING to GO (cars spawn and seat, then 3-2-1); Modules/RaceStart
Constants.RACING_TIMEOUT = 240 -- failsafe; the slowest build with a novice driver needs ~180 s on the 2026-10-20 tracks

-- ─── Player / Session ─────────────────────────────────────────────────────────
Constants.MAX_PLAYERS    = 10
Constants.SKIN_COUNT     = 10   -- must match ServerStorage/CharacterSkins count
Constants.MIN_TO_START   = 2    -- with this many players the lobby counts down LOBBY.FILL_SECONDS
Constants.SOLO_TEST_MODE = false -- true: start 5 s after the first player, print the balance audit (local testing only)
-- Live lobby: a lone player starts after MAX_WAIT s; once MIN_TO_START are
-- in, the countdown drops to FILL_SECONDS (time for friends to load in).
Constants.LOBBY = { MAX_WAIT = 25, FILL_SECONDS = 8 }

-- ─── Inventory ────────────────────────────────────────────────────────────────
Constants.INVENTORY_SIZE       = 8
Constants.STEAL_DISABLE_BEFORE = 5   -- seconds before CRAFTING that stealing locks

-- ─── Item World ───────────────────────────────────────────────────────────────
Constants.ITEM_SPAWN_COUNT = 100
Constants.PICKUP_RANGE     = 10  -- studs
Constants.DROP_TOSS        = 5   -- studs ahead of the dropper a dropped item lands (FarmFx animates the throw)
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
--   SKY    7000-stud path / 3500-stud Z-extent (two cloud bends,   path/Z ~2.0)
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
-- Speed buffs (boost, pads, turbos, abilities) multiply, but the product of
-- the ones above 1 is capped at this (SpeedModifiers): a Rocket on a boost
-- on a pad used to reach ×8 and pass through walls.
Constants.SPEED_STACK_MAX  = 2.0
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

-- Crafting balance (tests/lib/balance.luau, `lune run tools/balance.luau`).
-- An item's value = seconds it saves its owner per race (stats + its E
-- ability), averaged over every partner build; matches are Monte Carlo
-- fields of 6 players crafting from farmed inventories.
Constants.BALANCE_TARGETS = {
	tierStep        = 0.3,   -- s: each rarity tier beats the one below by this much on average
	epicEdge        = { min = 1.0, max = 4.5 },   -- s: Epic vs Common item mean, per slot (~4% of a race)
	maxAboveTier    = 2.0,   -- s: no item this far above its tier's mean
	minItemValue    = 0.2,   -- s: every item is worth equipping
	maxTopItemShare = 0.40,  -- the most common item in one slot of the winners
	minDistinctWinnersPer1000 = 60,  -- distinct BODY+ENGINE+SPECIAL among 1000 winners
	minUpsetRate    = 0.40,  -- the field's rarest build loses at least this often ...
	maxUpsetRate    = 0.80,  -- ... and wins at least 1 − this often
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

-- ─── Farming fights (FarmingManager, FarmingRules.punch) ─────────────────────
-- F punches the player in front of you; landed hits pile up on the victim
-- and HITS_TO_DROP of them (each within HIT_MEMORY s of the last) knock a
-- random item out onto the ground, for anyone to grab. Holding G guards:
-- punches on a guarding player are blocked. A knocked-out player cannot be
-- knocked out again for DROP_IMMUNE s.
Constants.FIGHT = {
	RANGE        = 6,     -- studs between root parts
	ARC          = 0.35,  -- attacker must face the victim: dot(look, toVictim) >= this
	COOLDOWN     = 0.45,  -- s between two punches of one player
	HITS_TO_DROP = 4,
	HIT_MEMORY   = 4,     -- s: hits older than this are forgotten
	DROP_IMMUNE  = 4,     -- s after a knock-out
	KNOCKBACK    = 26,    -- studs/s pushed away on a landed hit
	GUARD_MAX    = 3,     -- s a guard can be held before it drops
	GUARD_SLOW   = 0.5,   -- walk speed × this while guarding
}

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
-- Item stats × this (tools/balance.luau: Epic items save ~2–4 s per race
-- over Common ones; it was 1.3 / 1.6 / 2.0 and an Epic engine + special
-- alone were worth ~25 s).
Constants.RARITY_STAT_MULT = {
	Common   = 1.0,
	Uncommon = 1.15,
	Rare     = 1.3,
	Epic     = 1.5,
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
	powerAccelBonus  = 0.35,   -- engine power → acceleration (0.5 before 2026-10-22)
	weightAccelPenalty = 0.30, -- body weight → accel reduction (0.4 before 2026-10-22)
	weightStabBonus    = 0.80, -- body weight → stability bonus
	gripTurnBonus      = 20,   -- body grip → turn rate
	gripFlyBonus       = 8,    -- body grip → flyability (SKY)
	gripFloatBonus     = 4,    -- body grip → floatability (OCEAN; 0.5 before 2026-10-22)

	STAT_BUDGET      = 100,    -- total stat normalisation cap (Issue #61)
	biomeStatMult    = 1.30,   -- bonus for biome-matched items

	-- SPECIAL boost stat → boost seconds (VehicleStats)
	BOOST_BASE       = 1.6,
	BOOST_PER_POINT  = 0.010,
	BOOST_MAX        = 3.6,
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
	-- Grip: at speed a car cannot turn at its full TurnSpeed; the turn rate
	-- is capped at GRIP_LAT / speed (lateral acceleration, studs/s²). Sharp
	-- corners need a brake, or a drift.
	GRIP_LAT         = { FOREST = 120, OCEAN = 110 },
	-- Drift (Shift + steer above DRIFT_SPEED_RATIO of MaxSpeed): the car
	-- turns faster and is allowed more lateral acceleration, but its travel
	-- direction lags behind where it points (it slides) and it loses a
	-- little speed while sliding. Releasing a long drift gives a mini-turbo.
	-- (Before 2026-10-22 drifting only turned SLOWER, × 0.35: it never helped.)
	DRIFT_TURN_MULT  = 1.35,
	DRIFT_LAT        = { FOREST = 175, OCEAN = 150 },
	TRAVEL_FOLLOW    = 14,     -- 1/s: travel direction follows the nose (grip)
	DRIFT_FOLLOW     = 4.0,    -- 1/s: while drifting (slide angle ≈ turn rate / this)
	DRIFT_DRAG       = 10,     -- studs/s² × sin(slide angle) while drifting
	DRIFT_EXIT_RATIO = 0.35,   -- drift ends below this share of MaxSpeed
	DRIFT_TURBO = {            -- released drift → speed × mult for duration (server)
		MIN_SLIDE = 0.15,      -- rad: sliding at least this much counts as drifting
		{ time = 0.6, mult = 1.25, duration = 1.0, label = "MINI TURBO" },
		{ time = 1.4, mult = 1.38, duration = 1.4, label = "SUPER TURBO" },
	},
}

-- ─── Top speed: stat → VehicleSeat.MaxSpeed ──────────────────────────────────
-- The build may not decide the race: every car's top speed sits within
-- ±`spread` of the biome's `center`. The speed stat (p10 `lo` .. p90 `hi` of
-- all item combinations) only picks the place inside that band, so a better
-- build is a little faster and driving, boosts and items decide the rest.
-- Centers put the best build with a good driver at about 85 s per race.
-- (Before 2026-10-21 MaxSpeed was speed × 2.5 / 2.0 / 3.0: the fastest
-- build was 1.8× the slowest and the field finished 50–60 s apart.)
-- (2026-10-22: spread 0.06 → 0.015. tools/balance.luau measured ~1.7 s per
-- stud/s in FOREST, so ±6% made the engine alone worth ~9 s per race.)
Constants.RACE_SPEED = {
	FOREST = { center = 69, spread = 0.015, lo = 22, hi = 33 },
	OCEAN  = { center = 63, spread = 0.015, lo = 20, hi = 40 },
	SKY    = { center = 87, spread = 0.015, lo = 21, hi = 30 },
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
-- OCEAN / SKY races are decided by turning (tools/balance.luau: 13 / 22 s per
-- rad/s), so their ranges are narrow (2026-10-22: were 1.2–2.0 and 1.0–1.5).
-- SKY tops out at VehicleController.SKY_TURN_CAP (1.5): the old map
-- (flyability × 0.4, clamped 0.5–4.0) put every build at or above the cap, so
-- flyability did nothing for handling.
Constants.TURN_SPEED = {
	FOREST = { stat = "stability",    lo = 20, hi = 100, min = 2.0, max = 3.2 },
	OCEAN  = { stat = "floatability", lo = 10, hi = 45,  min = 1.5, max = 1.85 },
	SKY    = { stat = "flyability",   lo = 8,  hi = 36,  min = 1.3, max = 1.5 },
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

-- ─── Car-to-car hits (Shared/CarImpact, RacingManager, VehicleController) ─────
-- Every contact between two race cars is resolved on the server as an
-- inelastic collision and each driver gets a velocity change ("knock") and
-- a spin that fade out (the drive model overwrites Roblox's own response).
Constants.IMPACT = {
	RESTITUTION  = 0.4,    -- 0 = cars stick, 1 = full bounce
	PUSH         = 1.0,    -- × the physical impulse (arcade feel)
	MIN_CLOSING  = 4,      -- studs/s: slower touches do nothing
	MAX_DV       = 45,     -- studs/s cap per car per hit
	SPIN_PER_DV  = 0.09,   -- rad/s of spin per stud/s of sideways push at the nose/tail
	MAX_SPIN     = 2.5,    -- rad/s
	KNOCK_DECAY  = 2.5,    -- 1/s: sideways slide fades as exp(-KNOCK_DECAY × t)
	SPIN_DECAY   = 3.0,    -- 1/s
	PAIR_COOLDOWN = 0.35,  -- s before the same two cars can hit again
	BIG_HIT      = 18,     -- closing speed that shows a "BANG!" label on both cars
	SHAKE_PER_HIT = 0.02,  -- camera shake per stud/s of closing speed (driver's own car)
}

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
	LOG_MIN_GAP       = 12,     -- studs of open lane always left beside a log (HazardPlan)
	LOG_WALL_MARGIN   = 1,
	LOG_SPACING       = 30,     -- studs along the track between logs of one drop
	LOG_FINISH_CLEAR  = 60,     -- no logs this close to the finish
	LOG_KEEP_CLEAR    = 25,     -- ... or to a jump ramp, mud patch or boost pad (HazardPlan.keepClear)
	LOG_YAW_JITTER    = 0.3,    -- rad
	LOG_WARN          = 1.2,    -- s the landing marker shows before the log drops
	GUST_DURATION     = 2,
	GUST_PULSE        = 0.25,   -- s between sideways shoves while a gust blows
	GUST_PUSH_PER_FORCE = 0.12, -- shove speed (studs/s) per unit of BiomeConfig force
	FLOOD_STEPS       = 10,     -- water rises/falls in this many steps over 1 s
}

-- ─── Collision / Physics ──────────────────────────────────────────────────────
Constants.OBSTACLE_BOUNCE_PENALTY_DURATION = 1.0  -- seconds
Constants.OBSTACLE_BOUNCE_SPEED_MULT       = 0.5
Constants.OBSTACLE_BOUNCE_PUSH             = 30   -- studs/s knock away from the obstacle
Constants.MUD_SPEED_MULT                   = 0.5
Constants.SLOW_ZONE_MULT                   = 0.6  -- off-corridor soft penalty
Constants.RACE_BOOST_PAD_ACTIVE_RATIO      = 0.6  -- fraction of placed BoostPads active per race
Constants.SKY_GRAVITY_MULT                 = 1.2  -- outside updraft zones
Constants.UPDRAFT_BASE_FORCE               = 200  -- studs/s² upward (scaled by flyability)

-- ─── Progression (saved: Modules/PlayerStore, rules: Shared/Progression) ──────
-- A 5-player round: the winner gets ~110 XP / 40 coins, a finisher ~55 / 15,
-- a DNF 25 / 5. Level L needs XP_BASE + XP_STEP × (L − 1) XP, so level 2
-- takes about two rounds and level 10 (2700 XP) about 35 rounds in total.
Constants.PROGRESSION = {
	XP_BASE = 100, XP_STEP = 50,
	PLAY_XP = 25,  FINISH_XP = 30, PLACE_XP = { 55, 35, 20 },   -- 1st, 2nd, 3rd
	PLAY_COINS = 5, FINISH_COINS = 10, PLACE_COINS = { 25, 15, 8 },
	-- first round of a UTC day: DAILY_COINS + DAILY_STREAK_COINS per extra
	-- day in a row, the streak counting up to DAILY_STREAK_MAX days
	DAILY_COINS = 40, DAILY_STREAK_COINS = 10, DAILY_STREAK_MAX = 7,
	AUTOSAVE_SECONDS = 120,
}

-- ─── Race bots (Modules/RaceBots): live servers fill the grid to FILL_TO ─────
Constants.BOTS = {
	FILL_TO = 4,
	NAMES = { "Rusty", "Duckie", "Turbo Tom", "Bubbles", "Sparky", "Noodle", "Zippy", "Biscuit" },
	-- mostly average drivers so a new player can beat them; one expert to chase
	PROFILES = { "average", "novice", "expert", "average", "novice", "average", "average", "novice" },
	-- FARMING (Modules/FarmBots): the same bots walk the farm first. Slower than
	-- a player (16), they mash slower in contests, tap to defend a steal now and
	-- then, throw the odd punch at a player in reach, guard and rob now and then. Their items become
	-- their race car (CraftingRules.autoSlots).
	FARM = {
		WALK = 13,          -- studs/s
		THINK = 0.25,       -- s between decisions
		MASH = 5,           -- contest presses per second
		DEFEND = 0.45,      -- chance per think to tap DefendSteal while grabbed
		PUNCH_EVERY = 7,    -- s, average, at a player in reach
		PUNCH_CHANCE = 0.5, -- of taking a swing when one is due
		WANDER = 18,        -- studs: how far a bot with a full bag strolls
		-- steals: now and then a bot walks up to someone with items near it
		-- and grabs (the victim defends as usual)
		STEAL_EVERY = 8,    -- s, average, between two thoughts of stealing
		STEAL_CHANCE = 0.6, -- of going for it when one is due
		STEAL_CHASE = 28,   -- studs: only someone this close (a player walks 16/s, a bot 13)
		CHASE_FOR = 5,      -- s: gives up the chase after this
		KEEP_FREE = 1,      -- bag slots left free for a steal (a car takes 6 of 8)
		PROWL = 0.5,        -- with that bag: chance a stroll heads for someone with items
		PROWL_RANGE = 70,   -- studs
		-- guard (G): raised when just hit (chance per hit) or when a player in
		-- reach faces the bot (chance per second); held GUARD_HOLD s, still
		GUARD_HIT = 0.3,    -- (0.5 blocked 9 of 16 punches in Studio: no knock-out)
		GUARD_NEAR = 0.25,
		GUARD_HOLD = 1.2,
		GUARD_REST = 3,     -- s before the next guard
	},
	-- RACING (Modules/RaceBots): bots fire their crafted abilities like a
	-- player's E, a little less eagerly
	RACE = {
		ABILITY_FIRST = 6,  -- s after GO, about, before the first try
		ABILITY_EVERY = 3,  -- s, average, between two tries
		ABILITY_CHANCE = 0.6,
		TARGET_RANGE = 45,  -- studs: aimed abilities wait for a car this close
	},
}

-- ─── Gadgets (shop, FARMING; Shared/Cosmetics "gadget") ───────────────────────
-- Smoke Bomb: USES per round; you vanish in smoke for HIDE s (no punches or
-- steals reach you, and a grab on you ends with nothing taken); the cloud
-- itself lasts CLOUD s. A trick to escape once, not a weapon.
Constants.GADGETS = {
	smoke = { USES = 1, HIDE = 3.5, CLOUD = 6 },
}

-- ─── Emotes ───────────────────────────────────────────────────────────────────
Constants.EMOTE_IDS = { "Wave", "Dance", "Laugh" }

return Constants
