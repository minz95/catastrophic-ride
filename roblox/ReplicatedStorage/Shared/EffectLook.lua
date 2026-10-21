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
	rocketBurst    = { style = "boost",   color = ORANGE, label = "🚀 점화!" },
	reverseBoost   = { style = "boost",   color = C(80, 210, 255), label = "🥤 소다 분사!" },
	spinBurst      = { style = "boost",   color = YELLOW, label = "🧭 회전 돌진!" },
	overclock      = { style = "boost",   color = ORANGE, label = "⚙️ 과열 가속!" },
	redline        = { style = "boost",   color = RED,    label = "🏃 레드라인!" },
	windRide       = { style = "boost",   color = SKY,    label = "⏰ 순풍!" },
	umbrellaSail   = { style = "boost",   color = SKY,    label = "☂️ 돛 펼침!" },
	raftGlide      = { style = "boost",   color = GREEN,  label = "🎍 활주!" },
	skateSlide     = { style = "boost",   color = C(255, 120, 200), label = "🛹 슬라이드!" },
	cartRam        = { style = "boost",   color = GREY,   label = "🛒 돌진!" },
	barrelRoll     = { style = "boost",   color = BROWN,  label = "🛢️ 구르기!" },
	flagAura       = { style = "aura",    color = RED,    label = "🏁 응원!", beam = true },
	digMode        = { style = "aura",    color = BROWN,  label = "🔧 진흙 무시" },
	backpackBoost  = { style = "aura",    color = C(90, 200, 255), label = "🎒 부스트 충전!" },
	bloomCleanse   = { style = "cleanse", color = PINK,   label = "🌻 정화!" },
	rise           = { style = "lift",    color = PURPLE, label = "🎈 떠오름!" },
	hover          = { style = "lift",    color = SKY,    label = "🎩 호버!" },
	emergencyFloat = { style = "lift",    color = YELLOW, label = "🐤 둥실!" },
	fullBuoyancy   = { style = "lift",    color = YELLOW, label = "🐤 둥실!" },
	softLanding    = { style = "lift",    color = YELLOW, label = "🐤 사뿐!" },
	groundBounce   = { style = "lift",    color = YELLOW, label = "🐤 통통!" },
	lifeFloat      = { style = "lift",    color = ORANGE, label = "🛟 둥실!" },
	kiteLift       = { style = "lift",    color = C(255, 120, 120), label = "🪁 비상!" },
	kiteGlide      = { style = "lift",    color = C(255, 120, 120), label = "🪁 활공!" },
	parachute      = { style = "lift",    color = BLUE,   label = "☂️ 낙하산" },
	umbrellaBlock  = { style = "shield",  color = BLUE,   label = "☂️ 방어막" },
	lockdown       = { style = "shield",  color = C(60, 80, 200), label = "🧳 잠금!" },
	sofaFortress   = { style = "shield",  color = RED,    label = "🛋️ 무적 휴식" },
	disguise       = { style = "ghost",   color = C(200, 160, 110), label = "📦 숨기" },
	windBlast      = { style = "wave",    color = SKY,    label = "💇 돌풍!" },
	gustBlast      = { style = "wave",    color = SKY,    label = "🌬️ 바람!" },
	microFreeze    = { style = "wave",    color = ICE,    label = "🧊 얼려라!" },
	bathSplash     = { style = "wave",    color = BLUE,   label = "🛁 첨벙!" },
	dropTrap       = { style = "drop",    color = YELLOW, label = "🪤 함정 설치" },
	stall          = { style = "stun",    color = GREY,   label = "💨 엔진 멈춤" },

	-- ── abilities: what happens to the car that got hit ────────────────────
	steerDisable   = { style = "slow",    color = WHITE,  label = "🧻 핸들 잠김!", beam = true },
	magnetPull     = { style = "slow",    color = PURPLE, label = "🧲 끌려감!",   beam = true },
	noodleSnare    = { style = "slow",    color = YELLOW, label = "🍜 면발에 걸림!", beam = true },
	slipped        = { style = "slow",    color = ORANGE, label = "💦 미끄덩!" },
	splashed       = { style = "slow",    color = BLUE,   label = "💦 물벼락!",   beam = true },
	steamed        = { style = "blind",   color = WHITE,  label = "♨️ 앞이 안 보여!" },
	frozen         = { style = "stun",    color = ICE,    label = "🧊 얼어붙음!", beam = true },
	blown          = { style = "hit",     color = SKY,    label = "💨 밀려남!",   beam = true },
	rammed         = { style = "hit",     color = ORANGE, label = "💥 쾅!" },
	blocked        = { style = "hit",     color = BLUE,   label = "🛡️ 막음!" },

	-- ── HEAD / TAIL passives and boost ─────────────────────────────────────
	cartShove      = { style = "hit",     color = GREY,   label = "🛒 밀치기!" },
	cactusSting    = { style = "slow",    color = GREEN,  label = "🌵 따끔!" },
	bumperAbsorb   = { style = "shield",  color = PURPLE, label = "🎈 범퍼!" },
	slipstream     = { style = "slow",    color = WHITE,  label = "🧻 휴지 바람", beam = true },
	leadFlag       = { style = "badge",   color = RED,    label = "🏁 선두 보너스" },
	momentum       = { style = "badge",   color = PINK,   label = "🌻 가속" },
	boost          = { style = "boost",   color = C(100, 200, 255) },
	boostRocket    = { style = "boost",   color = ORANGE, label = "🚀 로켓 부스트!" },

	-- ── driving: car-to-car hits and drift turbos ──────────────────────────
	bump           = { style = "hit",     color = YELLOW, label = "💥" },
	miniTurbo      = { style = "boost",   color = C(80, 190, 255), label = "🔵 미니 터보" },
	superTurbo     = { style = "boost",   color = ORANGE, label = "🔥 슈퍼 터보" },
}

EffectLook.SCREEN = {
	steerDisable  = { color = WHITE,  alpha = 0.35, text = "핸들 잠김!" },
	slippery      = { color = ORANGE, alpha = 0.25, text = "미끄덩!", shake = 0.03, seconds = 0.8 },
	flagBuff      = { color = RED,    alpha = 0.15, text = "응원 받음! 속도 UP" },
	magnetPull    = { color = PURPLE, alpha = 0.3,  text = "자석에 끌려가요!", shake = 0.02 },
	redlineActive = { color = RED,    alpha = 0.2,  text = "레드라인! 핸들 고정" },
	steamBlind    = { color = WHITE,  alpha = 0.8,  text = "앞이 안 보여!" },
	noodleSnare   = { color = YELLOW, alpha = 0.3,  text = "면발에 걸렸어요!" },
	windBlast     = { color = SKY,    alpha = 0.25, text = "밀려나요!", shake = 0.05, seconds = 0.6 },
	microFreeze   = { color = ICE,    alpha = 0.5,  text = "얼어붙었어요!", shake = 0.01 },
	bathSplash    = { color = BLUE,   alpha = 0.55, text = "물벼락!" },
}

EffectLook.FALLBACK = { style = "hit", color = YELLOW, label = "!" }

function EffectLook.car(key)
	return EffectLook.CAR[key] or EffectLook.FALLBACK
end

return EffectLook
