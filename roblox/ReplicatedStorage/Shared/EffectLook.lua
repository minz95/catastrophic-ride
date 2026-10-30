-- EffectLook.lua
-- How each effect looks when it lands on a car. Data only: the client script
-- StarterPlayerScripts/EffectFx draws it; tests check that every key the
-- server sends (Modules/EffectFx.play) and every ScreenEffect name has an
-- entry here.
--
-- CAR looks are drawn on the car for EVERY player (you see what happened to
-- the car in front of you). Fields:
--   style  boost | lift | shield | slow | stun | blind | hit | wave | ghost
--          | cleanse | aura | drop | badge   (what StarterPlayerScripts/EffectFx draws)
--   color  main colour (highlight, particles, label)
--   label  floating text over the car (nil = none)
--   beam   true: a short beam from the car that caused it (info.from)
--
-- SCREEN looks are drawn only on the screen of the player it hit
-- (RemoteEvents.ScreenEffect name → overlay): tint colour, alpha (0 = clear,
-- 1 = solid), text in the middle, shake (camera), seconds (default length).

local EffectLook = {}

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

local ORANGE, RED, YELLOW = C(255, 140, 40), C(255, 70, 60), C(255, 220, 70)
local SKY, BLUE, ICE      = C(130, 200, 255), C(70, 140, 255), C(170, 235, 255)
local GREEN, PURPLE, WHITE = C(80, 200, 90), C(180, 110, 255), C(245, 245, 245)
local PINK, BROWN, GREY   = C(255, 140, 200), C(150, 100, 60), C(170, 170, 170)

EffectLook.CAR = {
	-- ── abilities: what the activator's own car does ────────────────────────
	rocketBurst    = { style = "boost",   color = ORANGE, label = "🚀 IGNITE!" },
	reverseBoost   = { style = "boost",   color = C(80, 210, 255), label = "🥤 SODA BLAST!" },
	spinBurst      = { style = "boost",   color = YELLOW, label = "🧭 SPIN DASH!" },
	overclock      = { style = "boost",   color = ORANGE, label = "⚙️ OVERCLOCK!" },
	redline        = { style = "boost",   color = RED,    label = "🏃 REDLINE!" },
	windRide       = { style = "boost",   color = SKY,    label = "⏰ TAILWIND!" },
	umbrellaSail   = { style = "boost",   color = SKY,    label = "☂️ SAIL UP!" },
	raftGlide      = { style = "boost",   color = GREEN,  label = "🎍 GLIDE!" },
	skateSlide     = { style = "boost",   color = C(255, 120, 200), label = "🛹 SLIDE!" },
	cartRam        = { style = "boost",   color = GREY,   label = "🛒 RAM!" },
	barrelRoll     = { style = "boost",   color = BROWN,  label = "🛢️ ROLL!" },
	flagAura       = { style = "aura",    color = RED,    label = "🏁 RALLY!", beam = true },
	digMode        = { style = "aura",    color = BROWN,  label = "🔧 DIG MODE" },
	backpackBoost  = { style = "aura",    color = C(90, 200, 255), label = "🎒 BOOST REFILL!" },
	bloomCleanse   = { style = "cleanse", color = PINK,   label = "🌻 CLEANSE!" },
	rise           = { style = "lift",    color = PURPLE, label = "🎈 RISE!" },
	hover          = { style = "lift",    color = SKY,    label = "🎩 HOVER!" },
	emergencyFloat = { style = "lift",    color = YELLOW, label = "🐤 FLOAT!" },
	fullBuoyancy   = { style = "lift",    color = YELLOW, label = "🐤 FLOAT!" },
	softLanding    = { style = "lift",    color = YELLOW, label = "🐤 SOFT LANDING!" },
	groundBounce   = { style = "lift",    color = YELLOW, label = "🐤 BOING!" },
	lifeFloat      = { style = "lift",    color = ORANGE, label = "⭕ FLOAT!" },
	kiteLift       = { style = "lift",    color = C(255, 120, 120), label = "🪁 LIFT OFF!" },
	kiteGlide      = { style = "lift",    color = C(255, 120, 120), label = "🪁 GLIDE!" },
	parachute      = { style = "lift",    color = BLUE,   label = "☂️ CANOPY" },
	umbrellaBlock  = { style = "shield",  color = BLUE,   label = "☂️ SHIELD" },
	lockdown       = { style = "shield",  color = C(60, 80, 200), label = "🧳 LOCKED!" },
	sofaFortress   = { style = "shield",  color = RED,    label = "🛋️ FORTRESS" },
	disguise       = { style = "ghost",   color = C(200, 160, 110), label = "📦 HIDDEN" },
	windBlast      = { style = "wave",    color = SKY,    label = "💇 BLAST!" },
	gustBlast      = { style = "wave",    color = SKY,    label = "🌬️ GUST!" },
	microFreeze    = { style = "wave",    color = ICE,    label = "🧊 FREEZE!" },
	bathSplash     = { style = "wave",    color = BLUE,   label = "🛁 SPLASH!" },
	dropTrap       = { style = "drop",    color = YELLOW, label = "⚠️ TRAP SET" },
	stall          = { style = "stun",    color = GREY,   label = "💨 STALLED" },

	-- ── abilities: what happens to the car that got hit ────────────────────
	steerDisable   = { style = "slow",    color = WHITE,  label = "🧻 STEERING JAMMED!", beam = true },
	magnetPull     = { style = "slow",    color = PURPLE, label = "🧲 PULLED!",   beam = true },
	noodleSnare    = { style = "slow",    color = YELLOW, label = "🍜 NOODLED!", beam = true },
	slipped        = { style = "slow",    color = ORANGE, label = "💦 SLIPPED!" },
	splashed       = { style = "slow",    color = BLUE,   label = "💦 SOAKED!",   beam = true },
	steamed        = { style = "blind",   color = WHITE,  label = "♨️ CAN'T SEE!" },
	frozen         = { style = "stun",    color = ICE,    label = "🧊 FROZEN!", beam = true },
	blown          = { style = "hit",     color = SKY,    label = "💨 BLOWN AWAY!",   beam = true },
	rammed         = { style = "hit",     color = ORANGE, label = "💥 BANG!" },
	bombHit        = { style = "hit",     color = ORANGE, label = "💣 BOOM!",          beam = true },   -- shop trick
	blocked        = { style = "hit",     color = BLUE,   label = "🛡️ BLOCKED!" },

	-- ── HEAD / TAIL passives and boost ─────────────────────────────────────
	cartShove      = { style = "hit",     color = GREY,   label = "🛒 SHOVE!" },
	cactusSting    = { style = "slow",    color = GREEN,  label = "🌵 OUCH!" },
	bumperAbsorb   = { style = "shield",  color = PURPLE, label = "🎈 BUMPER!" },
	slipstream     = { style = "slow",    color = WHITE,  label = "🧻 TP TRAIL", beam = true },
	leadFlag       = { style = "badge",   color = RED,    label = "🏁 LEADER BONUS" },
	momentum       = { style = "badge",   color = PINK,   label = "🌻 MOMENTUM" },
	boost          = { style = "boost",   color = C(100, 200, 255) },
	boostRocket    = { style = "boost",   color = ORANGE, label = "🚀 ROCKET BOOST!" },

	-- ── driving: car-to-car hits and drift turbos ──────────────────────────
	bump           = { style = "hit",     color = YELLOW, label = "💥" },
	miniTurbo      = { style = "boost",   color = C(80, 190, 255), label = "🔵 MINI TURBO" },
	superTurbo     = { style = "boost",   color = ORANGE, label = "🔥 SUPER TURBO" },
}

-- Size of the floating effect words ("STOLEN!", "RAM!") in pixels, over a
-- car (EffectFx) or a farming avatar (FarmFx); BIG = your own car. SCREEN
-- text is that share of the screen, capped at SCREEN_MAX_PX.
-- History (2026-10-26): at 160 x 36 (220 x 46 for your car) and 9 % of the
-- screen the words of two cars or two players side by side ran into each
-- other; a car hit twice stacked two labels on one spot.
EffectLook.TEXT = {
	W = 120, H = 26, BIG_W = 160, BIG_H = 34,
	SCREEN_W = 0.44, SCREEN_H = 0.06, SCREEN_MAX_PX = 40,
}

EffectLook.SCREEN = {
	steerDisable  = { color = WHITE,  alpha = 0.35, text = "STEERING JAMMED!" },
	slippery      = { color = ORANGE, alpha = 0.25, text = "SLIPPED!", shake = 0.03, seconds = 0.8 },
	flagBuff      = { color = RED,    alpha = 0.15, text = "RALLIED! SPEED UP" },
	magnetPull    = { color = PURPLE, alpha = 0.3,  text = "MAGNET PULL!", shake = 0.02 },
	redlineActive = { color = RED,    alpha = 0.2,  text = "REDLINE! STEERING LOCKED" },
	steamBlind    = { color = WHITE,  alpha = 0.8,  text = "CAN'T SEE!" },
	noodleSnare   = { color = YELLOW, alpha = 0.3,  text = "NOODLE SNARE!" },
	windBlast     = { color = SKY,    alpha = 0.25, text = "BLOWN AWAY!", shake = 0.05, seconds = 0.6 },
	bombed        = { color = ORANGE, alpha = 0.3,  text = "💣 BOMBED!", shake = 0.06, seconds = 1 },
	microFreeze   = { color = ICE,    alpha = 0.5,  text = "FROZEN!", shake = 0.01 },
	bathSplash    = { color = BLUE,   alpha = 0.55, text = "SOAKED!" },
	itemWave      = { color = YELLOW, alpha = 0.12, text = "✨ NEW ITEMS DROPPED! Rare items more likely", seconds = 2.5 },
	finishGrace   = { color = YELLOW, alpha = 0.1,  text = "🏁 WINNER IN! Reach the finish before time runs out!", seconds = 3 },
	craftHurry    = { color = YELLOW, alpha = 0.1,  text = "⏳ Others are ready! Race starts soon", seconds = 2.5 },
}

EffectLook.FALLBACK = { style = "hit", color = YELLOW, label = "!" }

function EffectLook.car(key)
	return EffectLook.CAR[key] or EffectLook.FALLBACK
end

return EffectLook
