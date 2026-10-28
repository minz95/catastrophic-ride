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
	-- lobby: casual, laid back (playtest 2026-10-28: "Happy Game" was too busy)
	LOBBY = { id = "rbxassetid://122548743506590", volume = 0.45, looped = true },  -- Playful Whistling Swing (APM)
	FARMING = {
		FOREST = { id = "rbxassetid://1843599021", volume = 0.5, looped = true },   -- Fun Arcade (APM)
		OCEAN  = { id = "rbxassetid://1838029319", volume = 0.5, looped = true },   -- Food Tray Fight (a) (APM)
		SKY    = { id = "rbxassetid://111298808852201", volume = 0.5, looped = true }, -- Game Level Twenty (chiptune)
	},
	-- crafting: quiet thinking music (playtest 2026-10-29: "Cook With Me
	-- Cartoon" was too loud and did not fit)
	CRAFTING = { id = "rbxassetid://83000834000142", volume = 0.3, looped = true }, -- Crafting Menu Loops While Thinking
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
		T("122548743506590", "Playful Whistling Swing (APM)"), T("133462395737742", "Cheerful Whistling Swing (APM)"),
		T("117904207848395", "Hyper Casual Sports Game Theme"), T("70502914416994", "Casual Gamer"),
		T("9047158085", "Little Rascals A (APM)"), T("1839627176", "Cute Moments (APM)"),
		T("9046270989", "Playful Penguins C (APM)"), T("9038818729", "Lucky And Carefree C (APM)"),
		T("1837480547", "Easy Going (APM)"), T("1839406050", "Happy Game (APM)"),
	},
	FARMING = {
		T("1843599021", "Fun Arcade (APM)"), T("1838029319", "Food Tray Fight (APM)"),
		T("111298808852201", "Game Level Twenty"), T("122180244370179", "Funny Cartoon Chase"),
		T("118070543189702", "Funny Chase"), T("1845463755", "Scary Comedy Chase (APM)"),
		T("9040145864", "Silly Outtakes (APM)"), T("1838708049", "Silly (APM)"),
		T("136833165577660", "Campground Silly Parade"), T("123897301584254", "Bubblegum"),
	},
	CRAFTING = {
		T("83000834000142", "Crafting Menu Loops While Thinking"), T("9048058841", "Building Blocks (a) (APM)"),
		T("1836663996", "Tinker (APM)"), T("94937056784916", "Puzzle Game Theme"),
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
-- Playtest 2026-10-29: two old ids were the "bangs" heard everywhere:
-- 258057783 is a user upload named "Explosion" (BOOM!) and played on every
-- pickup, slot, item use (ABILITY_GENERIC) and join; 6026984224 a user upload
-- of a chat-app notification (countdown, GO, respawn, contests, finish). Both
-- are gone: every id below is a ProSoundEffects / APM catalogue sound, soft
-- by design (blips, chimes, pops; no crashes or explosions). Find more without
-- Studio: `python3 tools/sound_search.py "<words>"`. The spec
-- playtest_polish checks no SFX is a banned id or a crash / explosion title.

SoundConfig.COLLISION_GAP = 0.6   -- s between two COLLISION sounds

-- ids (title from the Creator Store)
local BLIP   = "rbxassetid://9125397583"  -- Blip Tone Single High Pitch Synth Blip (PSE, "Notify, UI")
local CHIME  = "rbxassetid://9116394545"  -- Magic Glows Soft Clusters Of Chiming Hits 1 (PSE)
local CHIME2 = "rbxassetid://9116394876"  -- Magic Glows Soft Clusters Of Chiming Hits 2 (PSE)
local CLICK  = "rbxassetid://9119717529"  -- Switch Click On Or Off Toggle Button 1 (PSE)
local BOINK  = "rbxassetid://9113537815"  -- Boink Wet Suction Pop Blip Hollow 3 (PSE)
local POP    = "rbxassetid://9112872239"  -- Small Bubbles Water Surface Float Up Pop 5 (PSE)
local TINKLE = "rbxassetid://9125537079"  -- Electronic Tinkles Sharp Relay Falling Beeps (PSE)

SoundConfig.SFX = {
	-- Farming
	ITEM_PICKUP         = { id = CHIME,  volume = 0.45, pitch = 1.2 },
	ITEM_PICKUP_RARE    = { id = CHIME,  volume = 0.5,  pitch = 1.4 },
	ITEM_PICKUP_EPIC    = { id = CHIME2, volume = 0.55, pitch = 1.5 },
	CONTEST_START       = { id = BLIP,   volume = 0.4,  pitch = 1.0 },
	CONTEST_WIN         = { id = CHIME2, volume = 0.5,  pitch = 1.3 },
	CONTEST_LOSE        = { id = BLIP,   volume = 0.35, pitch = 0.7 },
	GRAB_WARN           = { id = "rbxassetid://9113251685", volume = 0.6, pitch = 1.0 }, -- Bag Grab Quick (someone grabs you)
	ITEM_STOLEN         = { id = "rbxassetid://9113722807", volume = 0.6, pitch = 0.9 }, -- Card Swipe
	ITEM_DEFENDED       = { id = "rbxassetid://9114343910", volume = 0.5, pitch = 1.2 }, -- Energy Presence
	-- the punch: an arm-swing whoosh on every F, a slappy cloth hit when it
	-- lands (the old muted rock thud gave no punch), a cartoon smack on a KO
	PUNCH_SWING         = { id = "rbxassetid://9120729007", volume = 0.6, pitch = 1.15 }, -- Whoosh Heavy Punches 3 (arm swings)
	PUNCH_HIT           = { id = "rbxassetid://9113534108", volume = 0.8, pitch = 1.05 }, -- Body Pats Cloth Hits 24 (slaps, hits)
	PUNCH_BLOCKED       = { id = "rbxassetid://9119075972", volume = 0.45, pitch = 1.3 }, -- Shield Impacts
	KNOCKOUT            = { id = "rbxassetid://9113263968", volume = 0.6, pitch = 1.0 }, -- Balloon Pops Slap Clap Smack 3

	-- Crafting
	SLOT_ASSIGN         = { id = CLICK,  volume = 0.4,  pitch = 1.1 },
	CRAFT_COMPLETE      = { id = "rbxassetid://1841209857", volume = 0.5, pitch = 1.0 }, -- Simple Chimes (APM)

	-- Racing
	BOOST_ACTIVATE      = { id = "rbxassetid://9114329395", volume = 0.5, pitch = 1.0 }, -- Energy Cloud Whooshing By Very Fast
	BOOST_PAD           = { id = "rbxassetid://9116411685", volume = 0.45, pitch = 1.1 }, -- Magic Swoosh Fast Zooming
	DRIFT_START         = { id = "rbxassetid://9116399935", volume = 0.35, pitch = 0.9 }, -- Airy Whips Swooshes
	DRIFT_SLINGSHOT     = { id = "rbxassetid://9121000116", volume = 0.5, pitch = 1.1 }, -- Zip Bys Airy Rips
	-- a cartoon pop, not a crash; at most once per COLLISION_GAP s
	COLLISION           = { id = POP,    volume = 0.35, pitch = 0.75 },
	MUD_ENTER           = { id = "rbxassetid://9120352855", volume = 0.4, pitch = 0.8 }, -- Underwater Splash
	UPDRAFT_ENTER       = { id = "rbxassetid://9125806782", volume = 0.35, pitch = 1.0 }, -- Rising Whoosh
	RESPAWN             = { id = BOINK,  volume = 0.45, pitch = 1.0 },
	BUBBLE_POP          = { id = POP,    volume = 0.5,  pitch = 1.0 },
	FINISH_1ST          = { id = CHIME2, volume = 0.6,  pitch = 1.2 },
	FINISH_OTHER        = { id = CHIME,  volume = 0.45, pitch = 1.0 },

	-- Countdown: a short synth blip, GO the same blip higher (kart style)
	COUNTDOWN_BEEP      = { id = BLIP,   volume = 0.5,  pitch = 1.0 },
	COUNTDOWN_GO        = { id = BLIP,   volume = 0.6,  pitch = 1.5 },

	-- Abilities (category-based; SoundClient picks these by ABILITY_SFX key).
	-- Soft cues only: the effect itself is drawn on the car (EffectFx).
	ABILITY_SPEED       = { id = "rbxassetid://9114328260", volume = 0.35, pitch = 1.1 }, -- Energy Cloud Whooshing By 2
	ABILITY_SHIELD      = { id = "rbxassetid://9114343910", volume = 0.35, pitch = 0.9 }, -- Energy Presence
	ABILITY_OBSTACLE    = { id = BOINK,  volume = 0.4,  pitch = 0.8 },  -- was a wooden-gate crash on every use
	ABILITY_HACK        = { id = TINKLE, volume = 0.35, pitch = 1.0 },
	ABILITY_FLOAT       = { id = "rbxassetid://9114320437", volume = 0.35, pitch = 1.1 }, -- Energy Cloud Whooshing Medium
	ABILITY_GENERIC     = { id = CHIME,  volume = 0.35, pitch = 1.0 },

	-- UI
	PLAYER_JOIN         = { id = CLICK,  volume = 0.3,  pitch = 1.0 },
	PHASE_TRANSITION    = { id = CHIME,  volume = 0.35, pitch = 1.0 },
	TIMER_LOW           = { id = BLIP,   volume = 0.35, pitch = 1.3 },
}

-- Ids that must never come back (spec playtest_polish).
SoundConfig.BANNED = { "258057783", "6026984224", "9120873997" }

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
