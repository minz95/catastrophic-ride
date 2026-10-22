-- AbilityConfig.lua
-- Per-item active ability definitions for all 37 items.
-- Each entry drives AbilityManager (Issue #55) — no physics code here,
-- just data: cooldown, duration, target type, effect key, animation key.
-- Resolves: Issue #22, #55, #56, #57, #58

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local R = Constants.RARITY

-- ─── Target types ─────────────────────────────────────────────────────────────
-- "self"         – applies to the activating player's vehicle
-- "nearest"      – nearest other player's vehicle
-- "all_in_radius"– all vehicles within .radius studs
-- "track_drop"   – drops a Part on the track at current position
-- "random_enemy" – random player that isn't the activator

-- ─── Decoration effect pool (Issue #22) ──────────────────────────────────────
-- Server rolls one of these for each decoration slot at CRAFTING start.

local DECORATION_EFFECTS = {
	-- { id, weight, description, onActivate key }
	{ id = "boost",          weight = 30, label = "BOOST +50%",      vfxKey = "boostAura"    },
	{ id = "specialAbility", weight = 20, label = "SPECIAL ABILITY", vfxKey = "goldAura"     },
	{ id = "cosmetic",       weight = 35, label = "COSMETIC ONLY",   vfxKey = "sparkleAura"  },
	{ id = "fireworks",      weight = 15, label = "FIREWORKS TRAP",  vfxKey = "fireworksAura" },
}

-- Weighted random draw for decoration slots
local function _rollDecoration()
	local totalWeight = 0
	for _, e in ipairs(DECORATION_EFFECTS) do totalWeight = totalWeight + e.weight end
	local roll = math.random() * totalWeight
	local cum  = 0
	for _, e in ipairs(DECORATION_EFFECTS) do
		cum = cum + e.weight
		if roll <= cum then return e end
	end
	return DECORATION_EFFECTS[1]
end

-- Returns { [1]=effect, [2]=effect, [3]=effect } for a player's decor slots
function _rollDecorations()
	return { _rollDecoration(), _rollDecoration(), _rollDecoration() }
end

-- ─── Ability table ────────────────────────────────────────────────────────────
-- Fields:
--   cooldown   (s)   server-enforced
--   duration   (s)   effect lifetime; nil for instant
--   targetType       see above
--   radius     (s)   only for all_in_radius
--   phaseRestrict    nil = RACING only; "FARMING" = only in farming
--   effectKey        string key AbilityManager uses to dispatch physics effect
--   animKey          string key AbilityAnimator uses for VFX/sound
--   sfxKey           sound asset key
--   uiHint           short string shown in ability HUD
--   biomeEffect      optional table { FOREST=..., OCEAN=..., SKY=... } for biome variants
--
-- How strong an effect is (AbilityManager applies these; the balance model in
-- tests/lib/balance.luau reads the same numbers):
--   selfSpeed / selfTurn   MaxSpeed / TurnSpeed × this on the user (selfFor s, default duration)
--   push                   forward shove on the user (studs/s, a CarImpact knock)
--   victimSpeed / victimTurn  × this on the car(s) hit (victimFor s, default duration)
--   victimPush             shove on the car(s) hit (studs/s)
--   hitSpeed / hitFor      slick drops: × this for hitFor s on whoever drives in
--   allySpeed / allyRange  flag auras: the nearest racer within allyRange gets it too

local AbilityConfig = {}

-- ── SPECIAL tier ──────────────────────────────────────────────────────────────

AbilityConfig["Toilet Paper"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "steerDisable",
	victimTurn = 0.3, victimFor = 1.3,
	animKey     = "throwTP",
	sfxKey      = "tp_throw",
	uiHint      = "🧻 Wrap!",
	biomeEffect = { OCEAN = { victimTurn = 0.5 } },   -- turning decides OCEAN races
}

AbilityConfig["Pizza"] = {
	cooldown    = 15,
	duration    = 2,
	targetType  = "track_drop",
	effectKey   = "slipperyPuddle",
	hitSpeed = 0.7, hitFor = 1.5,
	animKey     = "throwPizza",
	sfxKey      = "pizza_splat",
	uiHint      = "🍕 Slip Zone!",
}

AbilityConfig["Rubber Duck"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "emergencyFloat",
	selfSpeed = 1.15,   -- glides while lifted
	animKey     = "duckPopup",
	sfxKey      = "duck_quack",
	uiHint      = "🐤 Float!",
	biomeEffect = {
		FOREST = { effectKey = "groundBounce",  duration = 2 },
		OCEAN  = { effectKey = "fullBuoyancy",  duration = 4 },
		SKY    = { effectKey = "softLanding",   duration = 5 },
	},
}

AbilityConfig["Balloon Bunch"] = {
	cooldown    = 18,
	duration    = 3,
	targetType  = "self",
	effectKey   = "rise",          -- float upward, bypass ground hazards
	selfSpeed = 1.2,   -- glides while lifted
	animKey     = "balloonRise",
	sfxKey      = "balloon_stretch",
	uiHint      = "🎈 Rise!",
}

AbilityConfig["Soda Bottle"] = {
	cooldown    = 18,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "reverseBoost",  -- propulsion backwards (net forward with momentum)
	selfSpeed = 1.3, push = 25,
	animKey     = "sodaExplosion",
	sfxKey      = "soda_fizz",
	uiHint      = "🥤 Blast!",
}

AbilityConfig["Racing Flag"] = {
	cooldown    = 20,
	duration    = 4,
	targetType  = "self",          -- also buffs nearest ally (handled in effectKey)
	effectKey   = "flagAura",      -- self +20% speed + nearest ally +20%
	selfSpeed = 1.12, allySpeed = 1.20, allyRange = 40,
	animKey     = "waveFlag",
	sfxKey      = "flag_wave",
	uiHint      = "🏁 Rally!",
}

AbilityConfig["Cactus"] = {
	cooldown    = 12,
	duration    = 1.5,
	targetType  = "track_drop",
	effectKey   = "cactusObstacle", -- contact → 50% slow for 1.5s
	animKey     = "throwCactus",
	sfxKey      = "cactus_thud",
	uiHint      = "🌵 Drop!",
}

-- Leaves removed in #88 (redundant trap)
-- Scarf  removed in #88 (shape doesn't communicate steerHinder)
-- Oil Can, Boombox, Bubble Wrap, Firework removed in SPECIAL overhaul
-- (see ItemConfig comment). Gas Can inherits the slippery-puddle role below.

AbilityConfig["Gas Can"] = {
	cooldown    = 12,
	duration    = 3,
	targetType  = "track_drop",
	effectKey   = "slipperyPuddle", -- reuses Pizza's slick effect; Gas Can is the new Common trap
	hitSpeed = 0.7, hitFor = 1.5,
	animKey     = "pourGasCan",
	sfxKey      = "gas_pour",
	uiHint      = "⛽ Slick!",
}

AbilityConfig["Lantern"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "rise",          -- brief lift, reuses Balloon Bunch rise logic
	selfSpeed = 1.1,   -- glides while lifted
	animKey     = "lanternGlow",
	sfxKey      = "lantern_chime",
	uiHint      = "🏮 Lift!",
}

AbilityConfig["Camera"] = {
	cooldown    = 14,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "steerDisable",  -- flash blinds nearest; reuses Toilet Paper effect
	victimTurn = 0.15, victimFor = 1.0,
	animKey     = "cameraFlash",
	sfxKey      = "camera_flash",
	uiHint      = "📸 Flash!",
	biomeEffect = { OCEAN = { victimTurn = 0.4 } },
}

AbilityConfig["Magic Wand"] = {
	cooldown    = 18,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "rocketBurst",   -- magic speed burst; reuses Rocket effect
	selfSpeed = 1.3, push = 20,
	animKey     = "wandCast",
	sfxKey      = "wand_sparkle",
	uiHint      = "🪄 Cast!",
}

AbilityConfig["Trophy"] = {
	cooldown    = 22,
	duration    = 5,
	targetType  = "self",          -- also buffs nearest ally (handled in flagAura)
	effectKey   = "flagAura",      -- champion's aura; reuses Racing Flag effect
	selfSpeed = 1.15, allySpeed = 1.20, allyRange = 40,
	animKey     = "trophyRaise",
	sfxKey      = "trophy_cheer",
	uiHint      = "🏆 Rally!",
}

AbilityConfig["Magnet"] = {
	cooldown    = 14,
	duration    = 2.5,
	targetType  = "nearest",
	effectKey   = "magnetPull",    -- pulls nearest vehicle toward activator
	victimSpeed = 0.8, victimPush = 35,
	animKey     = "magnetPulse",
	sfxKey      = "magnet_hum",
	uiHint      = "🧲 Pull!",
	-- hold input → repel variant (handled in effectKey server-side)
}

AbilityConfig["Umbrella"] = {
	cooldown    = 18,
	duration    = 3,
	targetType  = "self",
	effectKey   = "umbrellaBlock", -- per-biome variants below; FOREST behaviour is the default
	selfSpeed = 1.15,   -- the open canopy catches wind (every biome)
	animKey     = "umbrellaOpen",
	sfxKey      = "umbrella_pop",
	uiHint      = "☂️ Shield!",
	biomeEffect = {
		FOREST = { effectKey = "umbrellaBlock",  duration = 3 },   -- absorb 1 collision
		OCEAN  = { effectKey = "umbrellaSail",   duration = 4 },   -- side-wind speed bonus
		SKY    = { effectKey = "parachute",      duration = 4 },   -- canopy: lift + blocks the next hit
	},
}

-- ── ENGINE tier ───────────────────────────────────────────────────────────────

-- Shovel removed in #88 (mislabeled as spoon, power=5 minimum)

AbilityConfig["Fan"] = {
	cooldown    = 12,
	duration    = 1.5,
	targetType  = "all_in_radius",
	radius      = 18,
	effectKey   = "gustBlast",     -- forward wind push; affects vehicles in front
	victimSpeed = 0.7, victimPush = 45,
	animKey     = "fanSpin",
	sfxKey      = "fan_whirr",
	uiHint      = "🌬️ Gust!",
}

-- Flower used to be a FARMING-only "attract items" ability, but abilities can
-- only be triggered while racing (E key in RacingClient), so it never fired.
AbilityConfig["Flower"] = {
	cooldown    = 20,
	duration    = 2,
	targetType  = "self",
	effectKey   = "bloomCleanse",  -- removes every slowdown on you + 2s shield
	selfSpeed = 1.1,
	animKey     = "flowerBloom",
	sfxKey      = "flower_chime",
	uiHint      = "🌻 Bloom!",
}

AbilityConfig["Drill"] = {
	cooldown    = 14,
	duration    = 4,
	targetType  = "self",
	effectKey   = "digMode",       -- ignore mud and off-track slow zones, bore ahead
	selfSpeed = 1.15,
	animKey     = "drillSpin",
	sfxKey      = "drill_whirr",
	uiHint      = "🔧 Dig!",
}

-- Big Gear removed in #88 (power=8 underwhelming, single gear doesn't read as engine)
-- Wind Turbine removed: never modeled, item not in roster

AbilityConfig["Propeller Hat"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "hover",        -- BodyForce upward; ignore ground hazards
	selfSpeed = 1.15,   -- glides while lifted
	animKey     = "propHover",
	sfxKey      = "propeller_spin",
	uiHint      = "🎩 Hover!",
}

AbilityConfig["Treadmill"] = {
	cooldown    = 18,
	duration    = 2,
	targetType  = "self",
	effectKey   = "redline",      -- instant max speed; A/D disabled
	selfSpeed = 1.35, selfTurn = 0.5,
	animKey     = "v8Rev",
	sfxKey      = "v8_roar",
	uiHint      = "🏃 Redline!",
}

AbilityConfig["Kettle"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "track_drop",
	effectKey   = "steamCloud",   -- visibility block for entering vehicles
	hitSpeed = 0.8, hitFor = 1.5,
	animKey     = "kettleSteam",
	sfxKey      = "kettle_hiss",
	uiHint      = "🫖 Steam!",
}

AbilityConfig["Cup Noodle"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "noodleSnare",  -- 30% speed reduction via noodle trail
	victimSpeed = 0.85,
	animKey     = "noodleThrow",
	sfxKey      = "noodle_splat",
	uiHint      = "🍜 Snare!",
}

AbilityConfig["Rocket"] = {
	cooldown    = 18,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "rocketBurst",  -- speed ×3 for 1.5s
	selfSpeed = 1.25, push = 20,
	animKey     = "rocketIgnite",
	sfxKey      = "rocket_ignite",
	uiHint      = "🚀 IGNITE!",
}

AbilityConfig["Hair Dryer"] = {
	cooldown    = 18,
	duration    = 1,
	targetType  = "all_in_radius",
	radius      = 15,
	effectKey   = "windBlast",    -- pushes nearby vehicles laterally
	victimPush = 55, victimSpeed = 0.7, victimFor = 1.2,
	animKey     = "leafBlowerOn",
	sfxKey      = "leafblower_blast",
	uiHint      = "💇 Blast!",
}

AbilityConfig["Magnifying Glass"] = {
	cooldown    = 15,
	duration    = 2,
	targetType  = "track_drop",
	effectKey   = "waterPuddle",  -- OCEAN bonus: bigger + floatability drain
	hitSpeed = 0.6, hitFor = 2,
	animKey     = "waterPour",
	sfxKey      = "water_pour",
	uiHint      = "🔍 Flood!",
	biomeEffect = {
		OCEAN = { effectKey = "waterPuddleLarge", radius = 8, duration = 3 },
	},
}

AbilityConfig["Compass"] = {
	cooldown    = 16,
	duration    = 2,
	targetType  = "self",
	effectKey   = "spinBurst",    -- high speed burst with random directional wobble
	selfSpeed = 1.22, push = 20,
	animKey     = "topSpin",
	sfxKey      = "top_spin",
	uiHint      = "🧭 Spin!",
}

AbilityConfig["Alarm Clock"] = {
	cooldown    = 16,
	duration    = 3,
	targetType  = "self",
	effectKey   = "windRide",     -- strong biome bonus for SKY/OCEAN
	selfSpeed = 1.08,
	animKey     = "pinwheelSpin",
	sfxKey      = "pinwheel_spin",
	uiHint      = "⏰ Wind!",
	biomeEffect = {
		OCEAN = { selfSpeed = 1.1 },
		SKY   = { selfSpeed = 1.1 },
	},
}

-- ── BODY tier ─────────────────────────────────────────────────────────────────

AbilityConfig["Cardboard Box"] = {
	cooldown    = 15,
	duration    = 2,
	targetType  = "self",
	effectKey   = "disguise",     -- other vehicle collision detection disabled
	animKey     = "boxDisguise",
	sfxKey      = "cardboard_fold",
	uiHint      = "📦 Hide!",
}

AbilityConfig["Bamboo Raft"] = {
	cooldown    = 18,
	duration    = 3,
	targetType  = "self",
	effectKey   = "raftGlide",    -- friction = 0; glides over any surface
	selfSpeed = 1.1, selfTurn = 1.5,
	animKey     = "raftGlide",
	sfxKey      = "bamboo_creak",
	uiHint      = "🎍 Glide!",
}

AbilityConfig["Log"] = {
	cooldown    = 9,
	duration    = nil,
	targetType  = "track_drop",
	effectKey   = "logObstacle",  -- rolling log; contact → bounce + speed penalty
	animKey     = "logRoll",
	sfxKey      = "log_thud",
	uiHint      = "🪵 Drop!",
}

AbilityConfig["Red Sofa"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "sofaFortress", -- nothing can hurt you; cars next to you bounce off
	victimPush = 40, victimSpeed = 0.6, victimFor = 1.2, radius = 10,
	animKey     = "sofaSit",
	sfxKey      = "sofa_flump",
	uiHint      = "🛋️ Chill!",
}

AbilityConfig["Shopping Cart"] = {
	cooldown    = 10,
	duration    = 1,
	targetType  = "self",
	effectKey   = "cartRam",      -- speed burst + lateral push on contact
	selfSpeed = 1.2, push = 30, victimPush = 40, radius = 8,
	animKey     = "cartCharge",
	sfxKey      = "cart_clang",
	uiHint      = "🛒 RAM!",
}

AbilityConfig["Microwave"] = {
	cooldown    = 20,
	duration    = 1,
	targetType  = "all_in_radius",
	radius      = 12,
	effectKey   = "microFreeze",  -- complete stop for 1s
	victimSpeed = 0.3,
	animKey     = "microwavePulse",
	sfxKey      = "microwave_ding",
	uiHint      = "🧊 Freeze!",
	biomeEffect = { SKY = { radius = 16 } },   -- flyers spread out
}

AbilityConfig["Bathtub"] = {
	cooldown    = 15,
	duration    = 1.5,
	targetType  = "all_in_radius",
	radius      = 10,
	effectKey   = "bathSplash",   -- vision blur + mini-stun; OCEAN doubles radius
	victimSpeed = 0.5, victimFor = 1.5,
	animKey     = "bathSplash",
	sfxKey      = "bath_splash",
	uiHint      = "🛁 Splash!",
	biomeEffect = {
		OCEAN = { radius = 16 },
		SKY   = { radius = 15 },   -- flyers spread out
	},
}

AbilityConfig["Backpack"] = {
	cooldown    = 25,
	duration    = 30,
	targetType  = "self",
	effectKey   = "backpackBoost",  -- refills the boost gauge
	animKey     = "backpackOpen",
	sfxKey      = "backpack_zip",
	uiHint      = "🎒 Gear Up!",
	biomeEffect = { SKY = { selfSpeed = 1.15, duration = 3, cooldown = 18 } },   -- jetpack: a push as well
}

-- Laptop removed in #88 (body concept unclear; hack belongs to a SPECIAL item)
-- Stick  removed in #88 (stickTrap nearly invisible; weakest stats)

AbilityConfig["Barrel"] = {
	cooldown    = 11,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "barrelRoll",    -- lateral spin burst; pushes adjacent vehicles
	selfSpeed = 1.1, victimPush = 45, radius = 8,
	animKey     = "barrelSpin",
	sfxKey      = "barrel_roll",
	uiHint      = "🪣 Roll!",
}

AbilityConfig["Suitcase"] = {
	cooldown    = 14,
	duration    = 3,
	targetType  = "self",
	effectKey   = "lockdown",      -- locks shut: absorbs the next hit, rolls on its wheels
	selfSpeed = 1.15,
	
	animKey     = "suitcaseLock",
	sfxKey      = "suitcase_latch",
	uiHint      = "🧳 Lock!",
}

AbilityConfig["Skateboard"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "skateSlide",   -- friction near-zero; maximum turn rate
	selfSpeed = 1.15, selfTurn = 1.6,
	animKey     = "skateSlide",
	sfxKey      = "skate_grind",
	uiHint      = "🛹 Slide!",
}

AbilityConfig["Life Preserver"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "lifeFloat",    -- emergency max buoyancy; works on all biomes
	selfSpeed = 1.15,   -- glides while lifted
	animKey     = "lifeRingThrow",
	sfxKey      = "splash_ring",
	uiHint      = "🛟 Float!",
}

AbilityConfig["Kite"] = {
	cooldown    = 14,
	duration    = 3,
	targetType  = "self",
	effectKey   = "kiteLift",     -- strong upward force; SKY ×2 lift
	selfSpeed = 1.15,   -- glides while lifted
	animKey     = "kiteLaunch",
	sfxKey      = "kite_snap",
	uiHint      = "🪁 Lift!",
	biomeEffect = {
		SKY = { effectKey = "kiteGlide", duration = 4, selfSpeed = 1.12 },
	},
}

-- ─── Public helpers ───────────────────────────────────────────────────────────

--- Returns the resolved ability entry for an item in a given biome.
-- Merges biomeEffect overrides onto the base config.
function AbilityConfig.get(itemName, biome)
	local base = AbilityConfig[itemName]
	if not base then return nil end

	if biome and base.biomeEffect and base.biomeEffect[biome] then
		local merged = {}
		for k, v in pairs(base) do merged[k] = v end
		for k, v in pairs(base.biomeEffect[biome]) do merged[k] = v end
		return merged
	end
	return base
end

--- Applies EPIC rarity bonuses to an ability config.
function AbilityConfig.applyEpicBonus(cfg)
	local b = Constants.EPIC_ABILITY_BONUS
	local out = {}
	for k, v in pairs(cfg) do out[k] = v end
	if out.duration then out.duration  = out.duration  * b.duration  end
	for _, k in ipairs({ "selfFor", "victimFor", "hitFor" }) do
		if out[k] then out[k] = out[k] * b.duration end
	end
	if out.radius   then out.radius    = out.radius    * b.radius    end
	if out.cooldown then out.cooldown  = out.cooldown  * b.cooldown  end
	return out
end

AbilityConfig.rollDecorations = _rollDecorations

return AbilityConfig
