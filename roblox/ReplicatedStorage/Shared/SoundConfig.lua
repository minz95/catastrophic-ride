-- SoundConfig.lua
-- All audio AssetIds, volumes, and categories.
-- Uses Roblox free audio library IDs.
-- TODO: Verify all IDs in Roblox Studio (File → Manage Assets → Audio).
--       IDs marked with [PLACEHOLDER] need to be swapped for final release.
-- Resolves: Issue #73, #95

local SoundConfig = {}

-- ─── BGM ─────────────────────────────────────────────────────────────────────
-- Distinct IDs per phase/biome so each context has its own feel.
-- [PLACEHOLDER] — swap these for licensed/purchased music before release.

SoundConfig.BGM = {
	LOBBY = {
		id     = "",   -- [TODO] replace with valid audio asset id
		volume = 0.4,
		looped = true,
	},
	FARMING = {
		FOREST = { id = "", volume = 0.45, looped = true },  -- [TODO] peaceful nature
		OCEAN  = { id = "", volume = 0.45, looped = true },  -- [TODO] breezy coastal
		SKY    = { id = "", volume = 0.45, looped = true },  -- [TODO] airy ambient
	},
	CRAFTING = {
		id     = "",   -- [TODO] focused workshop feel
		volume = 0.35,
		looped = true,
	},
	RACING = {
		FOREST = { id = "", volume = 0.55, looped = true },  -- [TODO] fast forest chase
		OCEAN  = { id = "", volume = 0.55, looped = true },  -- [TODO] high-energy surf
		SKY    = { id = "", volume = 0.55, looped = true },  -- [TODO] epic sky battle
	},
	RESULTS_WIN  = { id = "", volume = 0.6, looped = false }, -- [TODO] victory fanfare
	RESULTS_LOSE = { id = "", volume = 0.5, looped = false }, -- [TODO] consolation jingle
}

-- ─── Biome Ambience ───────────────────────────────────────────────────────────

SoundConfig.AMBIENCE = {
	FOREST = {
		{ id = "",  volume = 0.3,  looped = true },  -- [TODO] birds chirping
		{ id = "",  volume = 0.2,  looped = true },  -- [TODO] wind through leaves
	},
	OCEAN = {
		{ id = "",  volume = 0.4,  looped = true },  -- [TODO] ocean waves loop
		{ id = "",  volume = 0.15, looped = true },  -- [TODO] distant seagulls
	},
	SKY = {
		{ id = "",  volume = 0.3,  looped = true },  -- [TODO] high-altitude wind
	},
}

-- ─── SFX ─────────────────────────────────────────────────────────────────────
-- IDs are grouped by acoustic character so similar actions share a sonic family.
-- [PLACEHOLDER] IDs need to be replaced with verified Roblox free audio IDs.
--
-- ID families used:
--   PICKUP   : 258057783  — bright collect chime
--   SPEED    : 3714463173 — laser/whoosh swoosh
--   COLLISION: 5800013125 — low thud / crash
--   OBSTACLE : 5801167317 — heavy drop
--   SHIELD   : 4947766283 — shield pop / bubble
--   UI_CHIME : 6026984224 — clean UI beep
--   WHOOSH   : 6895079555 — air movement

SoundConfig.SFX = {
	-- Farming
	ITEM_PICKUP         = { id = "rbxassetid://258057783",  volume = 0.7, pitch = 1.2  }, -- bright chime
	ITEM_PICKUP_RARE    = { id = "rbxassetid://258057783",  volume = 0.8, pitch = 1.5  }, -- higher pitch = rarer
	ITEM_PICKUP_EPIC    = { id = "rbxassetid://258057783",  volume = 1.0, pitch = 1.8  }, -- highest pitch = epic
	CONTEST_START       = { id = "rbxassetid://6026984224", volume = 0.8, pitch = 1.0  }, -- announcement chime
	CONTEST_WIN         = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.3  },
	CONTEST_LOSE        = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 0.7  },
	ITEM_STOLEN         = { id = "",                        volume = 0.8, pitch = 0.8  }, -- sharp hit
	ITEM_DEFENDED       = { id = "rbxassetid://4947766283", volume = 0.8, pitch = 1.4  }, -- shield pop

	-- Crafting
	SLOT_ASSIGN         = { id = "rbxassetid://258057783",  volume = 0.5, pitch = 1.1  }, -- soft click
	CRAFT_COMPLETE      = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.0  }, -- satisfying chime

	-- Racing
	BOOST_ACTIVATE      = { id = "", volume = 0.8, pitch = 1.0  }, -- speed whoosh
	BOOST_PAD           = { id = "", volume = 0.7, pitch = 1.3  },
	DRIFT_START         = { id = "rbxassetid://6895079555", volume = 0.6, pitch = 0.9  }, -- air scrub
	DRIFT_SLINGSHOT     = { id = "", volume = 0.8, pitch = 1.4  }, -- fast sling
	COLLISION           = { id = "",                        volume = 0.9, pitch = 0.8  }, -- heavy thud
	MUD_ENTER           = { id = "",                        volume = 0.6, pitch = 0.7  }, -- wet slap
	UPDRAFT_ENTER       = { id = "rbxassetid://6895079555", volume = 0.5, pitch = 1.2  }, -- rising air
	RESPAWN             = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 1.0  }, -- respawn chime
	BUBBLE_POP          = { id = "rbxassetid://4947766283", volume = 0.8, pitch = 1.5  }, -- pop
	FINISH_1ST          = { id = "rbxassetid://6026984224", volume = 1.0, pitch = 1.0  }, -- fanfare
	FINISH_OTHER        = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 0.9  },

	-- Countdown
	COUNTDOWN_BEEP      = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.0  },
	COUNTDOWN_GO        = { id = "", volume = 1.0, pitch = 1.3  }, -- GO! punch

	-- Abilities (category-based; SoundClient picks these by ABILITY_SFX key)
	ABILITY_SPEED       = { id = "", volume = 0.7, pitch = 1.2  }, -- fast laser
	ABILITY_SHIELD      = { id = "rbxassetid://4947766283", volume = 0.7, pitch = 0.9  }, -- shield bubble
	ABILITY_OBSTACLE    = { id = "",                        volume = 0.8, pitch = 0.8  }, -- drop/thud
	ABILITY_HACK        = { id = "rbxassetid://6026984224", volume = 0.8, pitch = 0.6  }, -- low tech beep
	ABILITY_FLOAT       = { id = "rbxassetid://6895079555", volume = 0.7, pitch = 1.1  }, -- airy whoosh
	ABILITY_GENERIC     = { id = "rbxassetid://258057783",  volume = 0.6, pitch = 1.0  }, -- neutral chime

	-- UI
	PLAYER_JOIN         = { id = "rbxassetid://258057783",  volume = 0.5, pitch = 1.0  },
	PHASE_TRANSITION    = { id = "rbxassetid://6026984224", volume = 0.6, pitch = 1.0  },
	TIMER_LOW           = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 1.5  },
}

-- ─── Ability → SFX category mapping ─────────────────────────────────────────
-- Maps effectKey strings (from AbilityConfig) to SFX category keys above.
-- SoundClient plays SoundConfig.SFX[ABILITY_SFX[effectKey]] on ability use.

SoundConfig.ABILITY_SFX = {
	-- Speed / boost
	flagAura      = "ABILITY_SPEED",
	redline       = "ABILITY_SPEED",
	rocketBurst   = "ABILITY_SPEED",
	kettleBoost   = "ABILITY_SPEED",   -- kettle steam burst
	windBlast     = "ABILITY_SPEED",   -- Leaf Blower lateral push
	sodaBoost     = "ABILITY_SPEED",   -- reverseBoost alias
	reverseBoost  = "ABILITY_SPEED",
	gustBlast     = "ABILITY_SPEED",   -- Fan forward gust
	spinBurst     = "ABILITY_SPEED",   -- Spinning Top
	windRide      = "ABILITY_SPEED",   -- Pinwheel wind ride
	skateSlide    = "ABILITY_SPEED",   -- Skateboard slide
	barrelRoll    = "ABILITY_SPEED",   -- Barrel lateral spin

	-- Shield / absorb
	backpackBlock = "ABILITY_SHIELD",
	sofaFortress  = "ABILITY_SHIELD",
	lockdown      = "ABILITY_SHIELD",  -- Suitcase collision immunity

	-- Obstacle / trap
	cactusObstacle= "ABILITY_OBSTACLE",
	logObstacle   = "ABILITY_OBSTACLE",
	noodleSnare   = "ABILITY_OBSTACLE",
	steamCloud    = "ABILITY_OBSTACLE",
	waterPuddle   = "ABILITY_OBSTACLE",
	waterPuddleLarge = "ABILITY_OBSTACLE",
	slipperyPuddle= "ABILITY_OBSTACLE", -- Pizza slip zone

	-- Hack / control disruption
	microFreeze   = "ABILITY_HACK",
	disguise      = "ABILITY_HACK",
	steerDisable  = "ABILITY_HACK",    -- Toilet Paper wrap
	magnetPull    = "ABILITY_HACK",    -- Magnet pull/repel

	-- Float / aerial
	balloonLift   = "ABILITY_FLOAT",
	duckFloat     = "ABILITY_FLOAT",
	emergencyFloat= "ABILITY_FLOAT",
	hover         = "ABILITY_FLOAT",   -- Propeller
	raftGlide     = "ABILITY_FLOAT",
	lifeFloat     = "ABILITY_FLOAT",   -- Life Preserver
	kiteLift      = "ABILITY_FLOAT",   -- Kite
	kiteGlide     = "ABILITY_FLOAT",   -- Kite SKY variant
	rise          = "ABILITY_FLOAT",   -- Balloon Bunch
	umbrellaSky   = "ABILITY_FLOAT",
	parachute     = "ABILITY_FLOAT",
	umbrellaSail  = "ABILITY_FLOAT",

	-- Generic / misc
	cartRam       = "ABILITY_GENERIC",
	bathSplash    = "ABILITY_GENERIC",
	itemAttract   = "ABILITY_GENERIC", -- Flower
	umbrellaBlock = "ABILITY_GENERIC",
	groundBounce  = "ABILITY_GENERIC",
	fullBuoyancy  = "ABILITY_GENERIC",
	softLanding   = "ABILITY_GENERIC",
	backpackBoost = "ABILITY_GENERIC", -- Backpack gear up
}

return SoundConfig
