-- SoundConfig.lua
-- All audio AssetIds, volumes, and categories.
-- Resolves: Issue #73, #95

local SoundConfig = {}

-- Every id comes from a catalogue Roblox licenses for all experiences
-- (APMOfficial, ProSoundEffects, DistrokidOfficial on the Creator Store),
-- found and load-checked with `python3 tools/studio/sim.py run sounds`
-- (TestHarness/SoundCheck). Picked by title, not by ear: listen in a
-- playtest and swap any that do not fit. Never use uploads of game or film
-- audio (copyright).

-- ─── BGM ─────────────────────────────────────────────────────────────────────

SoundConfig.BGM = {
	LOBBY = { id = "rbxassetid://71612604315412", volume = 0.4, looped = true },    -- Blissful Leap Fiesta (DistroKid)
	FARMING = {
		FOREST = { id = "rbxassetid://106729070236769", volume = 0.45, looped = true }, -- The forest adventure
		OCEAN  = { id = "rbxassetid://90091763838597",  volume = 0.45, looped = true }, -- Tropical House
		SKY    = { id = "rbxassetid://132915893124028", volume = 0.45, looped = true }, -- Floating On A Cloud
	},
	CRAFTING = { id = "rbxassetid://85643586571329", volume = 0.35, looped = true }, -- Warm Breeze
	RACING = {
		FOREST = { id = "rbxassetid://140563561636307", volume = 0.55, looped = true }, -- Energetic and Upbeat Rock
		OCEAN  = { id = "rbxassetid://127764396558082", volume = 0.55, looped = true }, -- Blue Lagoon Ride
		SKY    = { id = "rbxassetid://1837808539",      volume = 0.55, looped = true }, -- OMG Run (a) (APM)
	},
	RESULTS_WIN  = { id = "rbxassetid://1836473422", volume = 0.6, looped = false }, -- Victory Fanfare Sting (APM)
	RESULTS_LOSE = { id = "rbxassetid://1841391669", volume = 0.5, looped = false }, -- Wipsy La La Sting 3 (APM)
}

-- ─── Biome ambience (FARMING and RACING) ──────────────────────────────────────

SoundConfig.AMBIENCE = {
	FOREST = {
		{ id = "rbxassetid://139767023947424", volume = 0.25, looped = true }, -- Young Birds in Morning Mist
	},
	OCEAN = {
		{ id = "rbxassetid://137826155053556", volume = 0.35, looped = true }, -- Ocean waves on the beach
		{ id = "rbxassetid://9118858279",      volume = 0.08, looped = true }, -- Seagull Squawks 1 (PSE)
	},
	SKY = {
		{ id = "rbxassetid://9125515918", volume = 0.25, looped = true },      -- Eastern Wind ambience (PSE)
	},
}

-- ─── SFX ─────────────────────────────────────────────────────────────────────
-- 258057783 and 6026984224 are older ids that load (pickup chime, UI beep).

SoundConfig.SFX = {
	-- Farming
	ITEM_PICKUP         = { id = "rbxassetid://258057783",  volume = 0.7, pitch = 1.2 },
	ITEM_PICKUP_RARE    = { id = "rbxassetid://258057783",  volume = 0.8, pitch = 1.4 },
	ITEM_PICKUP_EPIC    = { id = "rbxassetid://258057783",  volume = 1.0, pitch = 1.6 },
	CONTEST_START       = { id = "rbxassetid://6026984224", volume = 0.8, pitch = 1.0 },
	CONTEST_WIN         = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.3 },
	CONTEST_LOSE        = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 0.7 },
	GRAB_WARN           = { id = "rbxassetid://9113251685", volume = 0.9, pitch = 1.0 }, -- Bag Grab Quick (someone grabs you)
	ITEM_STOLEN         = { id = "rbxassetid://9113722807", volume = 0.9, pitch = 0.9 }, -- Card Swipe
	ITEM_DEFENDED       = { id = "rbxassetid://9114343910", volume = 0.8, pitch = 1.2 }, -- Energy Presence
	PUNCH_HIT           = { id = "rbxassetid://9118616398", volume = 0.9, pitch = 1.1 }, -- muted thud
	PUNCH_BLOCKED       = { id = "rbxassetid://9119075972", volume = 0.7, pitch = 1.2 }, -- Shield Impacts
	KNOCKOUT            = { id = "rbxassetid://9113470178", volume = 1.0, pitch = 1.0 }, -- Body Fall Heavy

	-- Crafting
	SLOT_ASSIGN         = { id = "rbxassetid://258057783",  volume = 0.4, pitch = 1.1 },
	CRAFT_COMPLETE      = { id = "rbxassetid://1841209857", volume = 0.8, pitch = 1.0 }, -- Simple Chimes (APM)

	-- Racing
	BOOST_ACTIVATE      = { id = "rbxassetid://9114329395", volume = 0.8, pitch = 1.0 }, -- Energy Cloud Whooshing By Very Fast
	BOOST_PAD           = { id = "rbxassetid://9116411685", volume = 0.7, pitch = 1.1 }, -- Magic Swoosh Fast Zooming
	DRIFT_START         = { id = "rbxassetid://9116399935", volume = 0.5, pitch = 0.9 }, -- Airy Whips Swooshes
	DRIFT_SLINGSHOT     = { id = "rbxassetid://9121000116", volume = 0.8, pitch = 1.1 }, -- Zip Bys Airy Rips
	COLLISION           = { id = "rbxassetid://9113437833", volume = 0.8, pitch = 1.0 }, -- Big Thuds Wall Impact
	MUD_ENTER           = { id = "rbxassetid://9120352855", volume = 0.6, pitch = 0.8 }, -- Underwater Splash
	UPDRAFT_ENTER       = { id = "rbxassetid://9125806782", volume = 0.5, pitch = 1.0 }, -- Rising Whoosh
	RESPAWN             = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 1.0 },
	BUBBLE_POP          = { id = "rbxassetid://9112872239", volume = 0.8, pitch = 1.0 }, -- Small Bubbles Pop
	FINISH_1ST          = { id = "rbxassetid://6026984224", volume = 1.0, pitch = 1.0 },
	FINISH_OTHER        = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 0.9 },

	-- Countdown
	COUNTDOWN_BEEP      = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.0 },
	COUNTDOWN_GO        = { id = "rbxassetid://9113071178", volume = 0.8, pitch = 1.0 }, -- Air Horn Bursts

	-- Abilities (category-based; SoundClient picks these by ABILITY_SFX key)
	ABILITY_SPEED       = { id = "rbxassetid://9114328260", volume = 0.7, pitch = 1.1 }, -- Energy Cloud Whooshing By 2
	ABILITY_SHIELD      = { id = "rbxassetid://9114343910", volume = 0.7, pitch = 0.9 }, -- Energy Presence
	ABILITY_OBSTACLE    = { id = "rbxassetid://9120873997", volume = 0.7, pitch = 1.0 }, -- Wooden Gate Crash
	ABILITY_HACK        = { id = "rbxassetid://6026984224", volume = 0.8, pitch = 0.6 },
	ABILITY_FLOAT       = { id = "rbxassetid://9114320437", volume = 0.7, pitch = 1.1 }, -- Energy Cloud Whooshing Medium
	ABILITY_GENERIC     = { id = "rbxassetid://258057783",  volume = 0.6, pitch = 1.0 },

	-- UI
	PLAYER_JOIN         = { id = "rbxassetid://258057783",  volume = 0.5, pitch = 1.0 },
	PHASE_TRANSITION    = { id = "rbxassetid://6026984224", volume = 0.6, pitch = 1.0 },
	TIMER_LOW           = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 1.5 },
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
