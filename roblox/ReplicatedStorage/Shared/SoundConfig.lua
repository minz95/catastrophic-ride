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

-- ─── Mix ─────────────────────────────────────────────────────────────────────
-- Every sound plays through one of these SoundGroups (Shared/SoundFx.group).
-- Playtest 2026-10-28: the music was so loud the game was hard to play; it
-- now sits well under the effects. The 🎵 button (SoundClient) mutes Music.

SoundConfig.GROUPS = {
	Music    = 0.45,
	Ambience = 0.6,
	Effects  = 1.0,
}

-- ─── BGM ─────────────────────────────────────────────────────────────────────

SoundConfig.BGM = {
	-- Playtest 2026-10-28 (twice): rock / tropical house did not fit, nor did
	-- the next random "chase" picks. Now mostly APM production music written
	-- as game music (titles "Happy Game", "Fun Arcade", "The Racing Game"),
	-- chiptune for SKY. Still picked by title: in a Studio playtest [ / ]
	-- plays the other candidates in SoundConfig.TRY (SoundClient).
	LOBBY = { id = "rbxassetid://1839406050", volume = 0.5, looped = true },        -- Happy Game (APM, Yannick Kalfayan)
	FARMING = {
		FOREST = { id = "rbxassetid://1843599021", volume = 0.5, looped = true },   -- Fun Arcade (APM)
		OCEAN  = { id = "rbxassetid://1838029319", volume = 0.5, looped = true },   -- Food Tray Fight (a) (APM)
		SKY    = { id = "rbxassetid://111298808852201", volume = 0.5, looped = true }, -- Game Level Twenty (chiptune)
	},
	CRAFTING = { id = "rbxassetid://1839396884", volume = 0.45, looped = true },    -- Cook With Me Cartoon (APM)
	RACING = {
		FOREST = { id = "rbxassetid://1847415881", volume = 0.55, looped = true },  -- Racing Games A (APM)
		OCEAN  = { id = "rbxassetid://1845092006", volume = 0.55, looped = true },  -- The Racing Game (APM)
		SKY    = { id = "rbxassetid://140250810677459", volume = 0.55, looped = true }, -- Racing Through Time (Video Game Soundtrack)
	},
	RESULTS_WIN  = { id = "rbxassetid://1836473422", volume = 0.6, looped = false }, -- Victory Fanfare Sting (APM)
	RESULTS_LOSE = { id = "rbxassetid://1841391669", volume = 0.5, looped = false }, -- Wipsy La La Sting 3 (APM)
}

-- Candidates per phase for the Studio music tryout ([ / ], SoundClient).
-- All licensed catalogue ids that loaded in `sim.py run sounds`.
local function T(id, title) return { id = id, title = title } end
SoundConfig.TRY = {
	LOBBY = {
		T("1839406050", "Happy Game (APM)"), T("1839404385", "Happy Game alt (APM)"),
		T("133710918293530", "Rainbow Slide"), T("105774799756277", "Bubblegum Supercluster"),
		T("9045344810", "Bouncy Vision (APM)"), T("1838029718", "Kids At Gigs (APM)"),
	},
	FARMING = {
		T("1843599021", "Fun Arcade (APM)"), T("1838029319", "Food Tray Fight (APM)"),
		T("111298808852201", "Game Level Twenty"), T("122180244370179", "Funny Cartoon Chase"),
		T("118070543189702", "Funny Chase"), T("1845463755", "Scary Comedy Chase (APM)"),
		T("9040145864", "Silly Outtakes (APM)"), T("1838708049", "Silly (APM)"),
		T("136833165577660", "Campground Silly Parade"), T("123897301584254", "Bubblegum"),
	},
	CRAFTING = {
		T("1839396884", "Cook With Me Cartoon (APM)"), T("1839403410", "Happy Game alt 2 (APM)"),
		T("1841146648", "Castles and Crayons (APM)"), T("1839398358", "Feel The Love Cartoon (APM)"),
		T("87614776980545", "Chiptune Chillout"), T("1847540538", "Main Street Strut (APM)"),
	},
	RACING = {
		T("1847415881", "Racing Games A (APM)"), T("1845092006", "The Racing Game (APM)"),
		T("140250810677459", "Racing Through Time"), T("79346445214749", "Game Level Ninety"),
		T("94185225253376", "Chiptune Odyssey"), T("117780627999526", "Go Bunny Boom Zone 1"),
		T("99939135861375", "Arcade Pizza"), T("88951633857057", "16-Bit Revolution"),
		T("116155493709494", "Hurry Up"), T("1837769109", "Battle Hero (APM)"),
		T("139584088721641", "8-Bit Tidepool"), T("123046034394607", "Adrenaline (Pulse Pixel)"),
	},
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

SoundConfig.COLLISION_GAP = 0.6   -- s between two COLLISION sounds

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
	PUNCH_SWING         = { id = "rbxassetid://9116399935", volume = 0.6, pitch = 1.7 }, -- Airy Whips Swooshes, quick (every F)
	PUNCH_HIT           = { id = "rbxassetid://9118616398", volume = 1.0, pitch = 1.1 }, -- muted thud
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
	-- a cartoon pop, not a crash: "Big Thuds Wall Impact" at 0.8 was a loud
	-- BANG on every bump and ability hit (playtest 2026-10-28). SoundClient
	-- plays it at most once per COLLISION_GAP s.
	COLLISION           = { id = "rbxassetid://9112872239", volume = 0.45, pitch = 0.75 }, -- Small Bubbles Pop, low
	MUD_ENTER           = { id = "rbxassetid://9120352855", volume = 0.6, pitch = 0.8 }, -- Underwater Splash
	UPDRAFT_ENTER       = { id = "rbxassetid://9125806782", volume = 0.5, pitch = 1.0 }, -- Rising Whoosh
	RESPAWN             = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 1.0 },
	BUBBLE_POP          = { id = "rbxassetid://9112872239", volume = 0.8, pitch = 1.0 }, -- Small Bubbles Pop
	FINISH_1ST          = { id = "rbxassetid://6026984224", volume = 1.0, pitch = 1.0 },
	FINISH_OTHER        = { id = "rbxassetid://6026984224", volume = 0.7, pitch = 0.9 },

	-- Countdown
	COUNTDOWN_BEEP      = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.0 },
	-- GO is the countdown beep, higher (kart-racer style); the air horn that
	-- was here sounded like a BANG at every start
	COUNTDOWN_GO        = { id = "rbxassetid://6026984224", volume = 0.9, pitch = 1.6 },

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
