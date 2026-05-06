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

local AbilityConfig = {}

-- ── SPECIAL tier ──────────────────────────────────────────────────────────────

AbilityConfig["Toilet Paper"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "steerDisable",
	animKey     = "throwTP",
	sfxKey      = "tp_throw",
	uiHint      = "🧻 Wrap!",
}

AbilityConfig["Pizza"] = {
	cooldown    = 15,
	duration    = 2,
	targetType  = "track_drop",
	effectKey   = "slipperyPuddle",
	animKey     = "throwPizza",
	sfxKey      = "pizza_splat",
	uiHint      = "🍕 Slip Zone!",
}

AbilityConfig["Rubber Duck"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "emergencyFloat",
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
	animKey     = "balloonRise",
	sfxKey      = "balloon_stretch",
	uiHint      = "🎈 Rise!",
}

AbilityConfig["Soda Bottle"] = {
	cooldown    = 10,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "reverseBoost",  -- propulsion backwards (net forward with momentum)
	animKey     = "sodaExplosion",
	sfxKey      = "soda_fizz",
	uiHint      = "🥤 Blast!",
}

AbilityConfig["Racing Flag"] = {
	cooldown    = 20,
	duration    = 4,
	targetType  = "self",          -- also buffs nearest ally (handled in effectKey)
	effectKey   = "flagAura",      -- self +20% speed + nearest ally +20%
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
	animKey     = "pourGasCan",
	sfxKey      = "gas_pour",
	uiHint      = "⛽ Slick!",
}

AbilityConfig["Lantern"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "rise",          -- brief lift, reuses Balloon Bunch rise logic
	animKey     = "lanternGlow",
	sfxKey      = "lantern_chime",
	uiHint      = "🏮 Lift!",
}

AbilityConfig["Camera"] = {
	cooldown    = 14,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "steerDisable",  -- flash blinds nearest; reuses Toilet Paper effect
	animKey     = "cameraFlash",
	sfxKey      = "camera_flash",
	uiHint      = "📸 Flash!",
}

AbilityConfig["Magic Wand"] = {
	cooldown    = 15,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "rocketBurst",   -- magic speed burst; reuses Rocket effect
	animKey     = "wandCast",
	sfxKey      = "wand_sparkle",
	uiHint      = "🪄 Cast!",
}

AbilityConfig["Trophy"] = {
	cooldown    = 22,
	duration    = 5,
	targetType  = "self",          -- also buffs nearest ally (handled in flagAura)
	effectKey   = "flagAura",      -- champion's aura; reuses Racing Flag effect
	animKey     = "trophyRaise",
	sfxKey      = "trophy_cheer",
	uiHint      = "🏆 Rally!",
}

AbilityConfig["Magnet"] = {
	cooldown    = 14,
	duration    = 2.5,
	targetType  = "nearest",
	effectKey   = "magnetPull",    -- pulls nearest vehicle toward activator
	animKey     = "magnetPulse",
	sfxKey      = "magnet_hum",
	uiHint      = "🧲 Pull!",
	-- hold input → repel variant (handled in effectKey server-side)
}

AbilityConfig["Umbrella"] = {
	cooldown    = 18,
	duration    = 3,
	targetType  = "self",
	effectKey   = "umbrellaSky",   -- per-biome variant
	animKey     = "umbrellaOpen",
	sfxKey      = "umbrella_pop",
	uiHint      = "☂️ Shield!",
	biomeEffect = {
		FOREST = { effectKey = "umbrellaBlock",  duration = 3 },   -- absorb 1 collision
		OCEAN  = { effectKey = "umbrellaSail",   duration = 4 },   -- side-wind speed bonus
		SKY    = { effectKey = "parachute",      duration = 6 },   -- fall at 20% speed
	},
}

-- ── ENGINE tier ───────────────────────────────────────────────────────────────

-- Shovel removed in #88 (mislabeled as spoon, power=5 minimum)

AbilityConfig["Fan"] = {
	cooldown    = 12,
	duration    = 1.5,
	targetType  = "all_in_radius",
	radius      = 10,
	effectKey   = "gustBlast",     -- forward wind push; affects vehicles in front
	animKey     = "fanSpin",
	sfxKey      = "fan_whirr",
	uiHint      = "🌬️ Gust!",
}

AbilityConfig["Flower"] = {
	cooldown    = 30,
	duration    = 5,
	targetType  = "self",
	effectKey   = "itemAttract",   -- pulls nearby unclaimed items toward player
	animKey     = "flowerBloom",
	sfxKey      = "flower_chime",
	uiHint      = "🌻 Attract!",
	phaseRestrict = "FARMING",     -- only usable during farming
}

-- Big Gear removed in #88 (power=8 underwhelming, single gear doesn't read as engine)
-- Wind Turbine removed: never modeled, item not in roster

AbilityConfig["Propeller"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "hover",        -- BodyForce upward; ignore ground hazards
	animKey     = "propHover",
	sfxKey      = "propeller_spin",
	uiHint      = "🚁 Hover!",
}

AbilityConfig["V8 Engine"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "redline",      -- instant max speed; A/D disabled
	animKey     = "v8Rev",
	sfxKey      = "v8_roar",
	uiHint      = "🏎️ Redline!",
}

AbilityConfig["Kettle"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "track_drop",
	effectKey   = "steamCloud",   -- visibility block for entering vehicles
	animKey     = "kettleSteam",
	sfxKey      = "kettle_hiss",
	uiHint      = "🫖 Steam!",
}

AbilityConfig["Cup Noodle"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "nearest",
	effectKey   = "noodleSnare",  -- 30% speed reduction via noodle trail
	animKey     = "noodleThrow",
	sfxKey      = "noodle_splat",
	uiHint      = "🍜 Snare!",
}

AbilityConfig["Rocket"] = {
	cooldown    = 10,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "rocketBurst",  -- speed ×3 for 1.5s
	animKey     = "rocketIgnite",
	sfxKey      = "rocket_ignite",
	uiHint      = "🚀 IGNITE!",
}

AbilityConfig["Leaf Blower"] = {
	cooldown    = 18,
	duration    = 1,
	targetType  = "all_in_radius",
	radius      = 12,
	effectKey   = "windBlast",    -- pushes nearby vehicles laterally
	animKey     = "leafBlowerOn",
	sfxKey      = "leafblower_blast",
	uiHint      = "💨 Blast!",
}

AbilityConfig["Watering Can"] = {
	cooldown    = 15,
	duration    = 2,
	targetType  = "track_drop",
	effectKey   = "waterPuddle",  -- OCEAN bonus: bigger + floatability drain
	animKey     = "waterPour",
	sfxKey      = "water_pour",
	uiHint      = "🚿 Flood!",
	biomeEffect = {
		OCEAN = { effectKey = "waterPuddleLarge", radius = 8, duration = 3 },
	},
}

AbilityConfig["Spinning Top"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "spinBurst",    -- high speed burst with random directional wobble
	animKey     = "topSpin",
	sfxKey      = "top_spin",
	uiHint      = "🪀 Spin!",
}

AbilityConfig["Pinwheel"] = {
	cooldown    = 14,
	duration    = 3,
	targetType  = "self",
	effectKey   = "windRide",     -- strong biome bonus for SKY/OCEAN
	animKey     = "pinwheelSpin",
	sfxKey      = "pinwheel_spin",
	uiHint      = "🌀 Wind!",
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
	animKey     = "raftGlide",
	sfxKey      = "bamboo_creak",
	uiHint      = "🎍 Glide!",
}

AbilityConfig["Log"] = {
	cooldown    = 12,
	duration    = nil,
	targetType  = "track_drop",
	effectKey   = "logObstacle",  -- rolling log; contact → bounce + speed penalty
	animKey     = "logRoll",
	sfxKey      = "log_thud",
	uiHint      = "🪵 Drop!",
}

AbilityConfig["Red Sofa"] = {
	cooldown    = 20,
	duration    = 2,
	targetType  = "self",
	effectKey   = "sofaFortress", -- full stop + damage immunity
	animKey     = "sofaSit",
	sfxKey      = "sofa_flump",
	uiHint      = "🛋️ Chill!",
}

AbilityConfig["Shopping Cart"] = {
	cooldown    = 10,
	duration    = 1,
	targetType  = "self",
	effectKey   = "cartRam",      -- speed burst + lateral push on contact
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
	animKey     = "microwavePulse",
	sfxKey      = "microwave_ding",
	uiHint      = "🧊 Freeze!",
}

AbilityConfig["Bathtub"] = {
	cooldown    = 15,
	duration    = 1.5,
	targetType  = "all_in_radius",
	radius      = 8,
	effectKey   = "bathSplash",   -- vision blur + mini-stun; OCEAN doubles radius
	animKey     = "bathSplash",
	sfxKey      = "bath_splash",
	uiHint      = "🛁 Splash!",
	biomeEffect = {
		OCEAN = { radius = 16 },
		SKY   = { radius = 5  },
	},
}

AbilityConfig["Backpack"] = {
	cooldown    = 60,
	duration    = 30,
	targetType  = "self",
	effectKey   = "backpackBoost",  -- FARMING: +2 inventory slots; RACING: free boost charge
	animKey     = "backpackOpen",
	sfxKey      = "backpack_zip",
	uiHint      = "🎒 Gear Up!",
	biomeEffect = {},              -- see effectKey — server checks current phase
}

-- Laptop removed in #88 (body concept unclear; hack belongs to a SPECIAL item)
-- Stick  removed in #88 (stickTrap nearly invisible; weakest stats)

AbilityConfig["Barrel"] = {
	cooldown    = 11,
	duration    = 1.5,
	targetType  = "self",
	effectKey   = "barrelRoll",    -- lateral spin burst; pushes adjacent vehicles
	animKey     = "barrelSpin",
	sfxKey      = "barrel_roll",
	uiHint      = "🪣 Roll!",
}

AbilityConfig["Suitcase"] = {
	cooldown    = 18,
	duration    = 2,
	targetType  = "self",
	effectKey   = "lockdown",      -- brief stop + collision immunity; absorbs 1 hit
	animKey     = "suitcaseLock",
	sfxKey      = "suitcase_latch",
	uiHint      = "🧳 Lock!",
}

AbilityConfig["Skateboard"] = {
	cooldown    = 12,
	duration    = 2,
	targetType  = "self",
	effectKey   = "skateSlide",   -- friction near-zero; maximum turn rate
	animKey     = "skateSlide",
	sfxKey      = "skate_grind",
	uiHint      = "🛹 Slide!",
}

AbilityConfig["Life Preserver"] = {
	cooldown    = 15,
	duration    = 3,
	targetType  = "self",
	effectKey   = "lifeFloat",    -- emergency max buoyancy; works on all biomes
	animKey     = "lifeRingThrow",
	sfxKey      = "splash_ring",
	uiHint      = "🛟 Float!",
}

AbilityConfig["Kite"] = {
	cooldown    = 14,
	duration    = 3,
	targetType  = "self",
	effectKey   = "kiteLift",     -- strong upward force; SKY ×2 lift
	animKey     = "kiteLaunch",
	sfxKey      = "kite_snap",
	uiHint      = "🪁 Lift!",
	biomeEffect = {
		SKY = { effectKey = "kiteGlide", duration = 5 },
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
	if out.radius   then out.radius    = out.radius    * b.radius    end
	if out.cooldown then out.cooldown  = out.cooldown  * b.cooldown  end
	return out
end

AbilityConfig.rollDecorations = _rollDecorations

return AbilityConfig
