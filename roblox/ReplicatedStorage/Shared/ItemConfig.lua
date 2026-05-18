-- ItemConfig.lua
-- Full stat definitions for all items.
-- Stats are BASE values before rarity multiplier is applied.
-- Resolves: Issue #6, #62, #67, #88, #89

-- Shared between server and client (lives in ReplicatedStorage/Shared).
local Constants = require(script.Parent.Constants)
local R = Constants.RARITY

local ItemConfig = {}

-- ─── BODY Items ───────────────────────────────────────────────────────────────
-- weight : 1–20  (higher = slower accel, better obstacle resistance)
-- grip   : 0.1–1.0 (higher = better cornering/stability)
-- biomeBonus: optional multiplier applied when in that biome
-- mobilityAffinity: items that work well in the MOBILITY slot for each biome

-- Stick removed in #88: too weak (weight=1, grip=0.20), boring trap ability

ItemConfig["Barrel"] = {
	slotType       = "BODY",
	rarity         = R.COMMON,
	weight         = 3,
	grip           = 0.35,
	icon           = "🛢️",
	shape          = "barrel",
	mobilityAffinity = {},
}

ItemConfig["Cardboard Box"] = {
	slotType       = "BODY",
	rarity         = R.COMMON,
	weight         = 2,
	grip           = 0.30,
	icon           = "📦",
	shape          = "cardboard",
	mobilityAffinity = {},
}

ItemConfig["Bamboo Raft"] = {
	slotType       = "BODY",
	rarity         = R.COMMON,
	weight         = 4,
	grip           = 0.40,
	icon           = "🎍",
	shape          = "bamboo",
	biomeBonus     = { OCEAN = 1.15 },
	mobilityAffinity = { OCEAN = true },
}

ItemConfig["Skateboard"] = {
	slotType       = "BODY",
	rarity         = R.UNCOMMON,
	weight         = 3,
	grip           = 0.25,
	icon           = "⛸️",
	shape          = "skateboard",
	mobilityAffinity = { FOREST = true },
}

ItemConfig["Log"] = {
	slotType       = "BODY",
	rarity         = R.UNCOMMON,
	weight         = 10,
	grip           = 0.70,
	icon           = "🌲",
	shape          = "log",
	biomeBonus     = { FOREST = 1.10 },
	mobilityAffinity = { FOREST = true },
}

ItemConfig["Shopping Cart"] = {
	slotType       = "BODY",
	rarity         = R.UNCOMMON,
	weight         = 5,
	grip           = 0.50,
	icon           = "🛒",
	shape          = "cart",
	mobilityAffinity = {},
}

ItemConfig["Life Preserver"] = {
	slotType       = "BODY",
	rarity         = R.RARE,
	weight         = 4,
	grip           = 0.45,
	floatabilityBonus = 2.0,   -- doubles floatability in OCEAN
	icon           = "⚓",
	shape          = "lifepreserver",
	biomeBonus     = { OCEAN = 1.20 },
	mobilityAffinity = { OCEAN = true },
}

ItemConfig["Kite"] = {
	slotType       = "BODY",
	rarity         = R.RARE,
	weight         = 2,
	grip           = 0.10,
	flyabilityBonus = 2.5,     -- 2.5× flyability in SKY
	icon           = "🎐",
	shape          = "kite",
	biomeBonus     = { SKY = 1.20 },
	mobilityAffinity = { SKY = true },
}

-- Laptop removed in #88: vehicle body concept unclear; weight=8+grip=0.10 awkward; hack ability doesn't fit BODY

ItemConfig["Suitcase"] = {
	slotType       = "BODY",
	rarity         = R.RARE,
	weight         = 9,
	grip           = 0.60,
	icon           = "💼",
	shape          = "suitcase",
	mobilityAffinity = {},
}

ItemConfig["Backpack"] = {
	slotType       = "BODY",
	rarity         = R.RARE,
	weight         = 20,
	grip           = 1.00,
	icon           = "🎒",
	shape          = "backpack",
	mobilityAffinity = {},
}

ItemConfig["Red Sofa"] = {
	slotType       = "BODY",
	rarity         = R.RARE,
	weight         = 12,
	grip           = 0.80,
	icon           = "🛋️",
	shape          = "sofa",
	mobilityAffinity = {},
}

ItemConfig["Microwave"] = {
	slotType       = "BODY",
	rarity         = R.EPIC,
	weight         = 15,
	grip           = 0.90,
	icon           = "📺",
	shape          = "microwave",
	mobilityAffinity = {},
}

ItemConfig["Bathtub"] = {
	slotType       = "BODY",
	rarity         = R.EPIC,
	weight         = 14,
	grip           = 0.70,
	icon           = "🛁",
	shape          = "bathtub",
	biomeBonus     = { OCEAN = 1.15 },
	mobilityAffinity = { OCEAN = true },
}

-- ─── ENGINE Items ─────────────────────────────────────────────────────────────
-- power: 5–40 (drives speed + acceleration)

-- Shovel removed in #88: mislabeled (icon/shape=spoon), power=5 minimum, digMode too situational

ItemConfig["Fan"] = {
	slotType   = "ENGINE",
	rarity     = R.COMMON,
	power      = 8,
	icon       = "🌬️",
	shape      = "fan",
}

ItemConfig["Flower"] = {
	slotType   = "ENGINE",
	rarity     = R.COMMON,
	power      = 10,
	icon       = "🌻",
	shape      = "flower",
}

ItemConfig["Alarm Clock"] = {
	slotType   = "ENGINE",
	rarity     = R.COMMON,
	power      = 13,
	icon       = "⏰",
	shape      = "alarmclock",
	biomeBonus = { SKY = 1.40, OCEAN = 1.20 },
}

ItemConfig["Magnifying Glass"] = {
	slotType   = "ENGINE",
	rarity     = R.UNCOMMON,
	power      = 18,
	icon       = "🔍",
	shape      = "magnifyingglass",
	biomeBonus = { OCEAN = 1.35 },
}

-- Big Gear removed in #88: power=8 too low for Uncommon, single gear doesn't read as engine visually
-- Wind Turbine removed: never modeled, item not in roster

ItemConfig["Hair Dryer"] = {
	slotType   = "ENGINE",
	rarity     = R.UNCOMMON,
	power      = 20,
	icon       = "💇",
	shape      = "hairdryer",
	biomeBonus = { SKY = 1.30 },
}

ItemConfig["Compass"] = {
	slotType   = "ENGINE",
	rarity     = R.RARE,
	power      = 22,
	icon       = "➡️",
	shape      = "compass",
}

ItemConfig["Propeller Hat"] = {
	slotType   = "ENGINE",
	rarity     = R.RARE,
	power      = 15,
	icon       = "🎩",
	shape      = "propellerhat",
	biomeBonus = { SKY = 1.20 },
}

ItemConfig["Treadmill"] = {
	slotType   = "ENGINE",
	rarity     = R.RARE,
	power      = 25,
	icon       = "🏃",
	shape      = "treadmill",
}

ItemConfig["Drill"] = {
	slotType   = "ENGINE",
	rarity     = R.RARE,
	power      = 22,
	icon       = "🔧",
	shape      = "drill",
	biomeBonus = { FOREST = 1.25 },
}

ItemConfig["Rocket"] = {
	slotType   = "ENGINE",
	rarity     = R.EPIC,
	power      = 30,
	icon       = "🚀",
	shape      = "rocket",
}

ItemConfig["Cup Noodle"] = {
	slotType   = "ENGINE",
	rarity     = R.EPIC,
	power      = 35,
	icon       = "🍜",
	shape      = "noodle",
}

ItemConfig["Kettle"] = {
	slotType   = "ENGINE",
	rarity     = R.EPIC,
	power      = 40,
	icon       = "☕",
	shape      = "kettle",
}

-- ─── SPECIAL Items ────────────────────────────────────────────────────────────
-- boost: 10–100 (passive boost duration in ms when boost key used)

-- Leaves removed in #88: third track_drop trap alongside Pizza and Cactus — pure redundancy
-- Scarf  removed in #88: boring Blender shape; steerHinder not communicated visually by a scarf
-- Oil Can, Boombox, Bubble Wrap, Firework removed in SPECIAL overhaul:
--   Oil Can → replaced by Gas Can (same slick mechanic, clearer silhouette)
--   Boombox → removed (soundBlast effect redundant with microFreeze)
--   Bubble Wrap → removed (bubbleShield never wired to physState in RacingManager)
--   Firework → removed (speed-burst role covered by Soda Bottle + new Magic Wand)

ItemConfig["Gas Can"] = {
	slotType   = "SPECIAL",
	rarity     = R.COMMON,
	boost      = 12,
	icon       = "⛽",
	shape      = "gascan",
}

ItemConfig["Pizza"] = {
	slotType   = "SPECIAL",
	rarity     = R.COMMON,
	boost      = 10,
	icon       = "🍕",
	shape      = "pizza",
}

ItemConfig["Toilet Paper"] = {
	slotType   = "SPECIAL",
	rarity     = R.COMMON,
	boost      = 20,
	icon       = "📜",
	shape      = "roll",
}

ItemConfig["Cactus"] = {
	slotType   = "SPECIAL",
	rarity     = R.UNCOMMON,
	boost      = 25,
	icon       = "🌵",
	shape      = "cactus",
}

ItemConfig["Magnet"] = {
	slotType   = "SPECIAL",
	rarity     = R.UNCOMMON,
	boost      = 30,
	icon       = "📎",
	shape      = "magnet",
}

ItemConfig["Racing Flag"] = {
	slotType   = "SPECIAL",
	rarity     = R.UNCOMMON,
	boost      = 30,
	icon       = "🏁",
	shape      = "flag",
}

ItemConfig["Lantern"] = {
	slotType   = "SPECIAL",
	rarity     = R.COMMON,
	boost      = 15,
	icon       = "💡",
	shape      = "lantern",
}

ItemConfig["Camera"] = {
	slotType   = "SPECIAL",
	rarity     = R.UNCOMMON,
	boost      = 25,
	icon       = "📸",
	shape      = "camera",
}

ItemConfig["Magic Wand"] = {
	slotType   = "SPECIAL",
	rarity     = R.RARE,
	boost      = 45,
	icon       = "✨",
	shape      = "wand",
}

ItemConfig["Umbrella"] = {
	slotType   = "SPECIAL",
	rarity     = R.RARE,
	boost      = 45,
	icon       = "☂️",
	shape      = "umbrella",
	-- different effects per biome handled in AbilityConfig
}

ItemConfig["Rubber Duck"] = {
	slotType   = "SPECIAL",
	rarity     = R.RARE,
	boost      = 50,
	icon       = "🐤",
	shape      = "duck",
}

ItemConfig["Trophy"] = {
	slotType   = "SPECIAL",
	rarity     = R.EPIC,
	boost      = 70,
	icon       = "🏆",
	shape      = "trophy",
}

ItemConfig["Balloon Bunch"] = {
	slotType   = "SPECIAL",
	rarity     = R.EPIC,
	boost      = 60,
	icon       = "🎈",
	shape      = "balloons",
	biomeBonus = { SKY = 1.20 },
}

ItemConfig["Soda Bottle"] = {
	slotType   = "SPECIAL",
	rarity     = R.EPIC,
	boost      = 100,
	icon       = "🥤",
	shape      = "bottle",
}

-- ─── Rarity spawn pool ────────────────────────────────────────────────────────
-- Precomputed list used by FarmingManager to build weighted spawn table.
ItemConfig._byRarity = { Common = {}, Uncommon = {}, Rare = {}, Epic = {} }
for name, cfg in pairs(ItemConfig) do
	if type(cfg) == "table" and cfg.rarity then
		table.insert(ItemConfig._byRarity[cfg.rarity], name)
	end
end

return ItemConfig
