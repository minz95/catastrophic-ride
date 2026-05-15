-- ItemTypes.lua
-- Canonical enum of all item names and their slot type.
-- Import this anywhere you need item identity without stats.
-- Resolves: Issue #6, #62, #88

local ItemTypes = {}

-- ─── Slot Types ───────────────────────────────────────────────────────────────
-- BODY/ENGINE/SPECIAL are item categories (each ItemTypes.ALL entry has one of these).
-- MOBILITY/HEAD/TAIL are vehicle slots — they accept items from any category and
-- only differ in where the item gets mounted on the assembled vehicle (see
-- SlotMountConfig.lua). Declared here so CraftingManager.slotAssignments and
-- VehicleBuilder._attachSlotItem share identifier strings.
ItemTypes.SlotType = {
	BODY     = "BODY",
	ENGINE   = "ENGINE",
	SPECIAL  = "SPECIAL",
	MOBILITY = "MOBILITY",
	HEAD     = "HEAD",
	TAIL     = "TAIL",
}

-- ─── Item Registry ─────────────────────────────────────────────────────────────
-- { name, slotType }
-- Keep alphabetical within each tier for diffing convenience.

-- Removed in #88: Stick (BODY), Laptop (BODY), Shovel (ENGINE), Big Gear (ENGINE),
--                 Leaves (SPECIAL), Scarf (SPECIAL), Rocket Boost (SPECIAL phantom)
-- Added   in #89: Barrel (BODY), Suitcase (BODY), Fan (ENGINE),
--                 Oil Can (SPECIAL), Magnet (SPECIAL), Firework (SPECIAL)
-- Wind Turbine was added in #89 then removed: never modeled, dropped from roster

ItemTypes.ALL = {
	-- ── BODY (13) ─────────────────────────────────────────────────────────────
	{ name = "Backpack",      slotType = "BODY" },
	{ name = "Bamboo Raft",   slotType = "BODY" },
	{ name = "Barrel",        slotType = "BODY" },
	{ name = "Bathtub",       slotType = "BODY" },
	{ name = "Cardboard Box", slotType = "BODY" },
	{ name = "Kite",          slotType = "BODY" },
	{ name = "Life Preserver",slotType = "BODY" },
	{ name = "Log",           slotType = "BODY" },
	{ name = "Microwave",     slotType = "BODY" },
	{ name = "Red Sofa",      slotType = "BODY" },
	{ name = "Shopping Cart", slotType = "BODY" },
	{ name = "Skateboard",    slotType = "BODY" },
	{ name = "Suitcase",      slotType = "BODY" },

	-- ── ENGINE (12) ───────────────────────────────────────────────────────────
	{ name = "Cup Noodle",    slotType = "ENGINE" },
	{ name = "Fan",           slotType = "ENGINE" },
	{ name = "Flower",        slotType = "ENGINE" },
	{ name = "Kettle",        slotType = "ENGINE" },
	{ name = "Hair Dryer",    slotType = "ENGINE" },
	{ name = "Alarm Clock",   slotType = "ENGINE" },
	{ name = "Propeller Hat", slotType = "ENGINE" },
	{ name = "Rocket",        slotType = "ENGINE" },
	{ name = "Compass",       slotType = "ENGINE" },
	{ name = "Treadmill",     slotType = "ENGINE" },
	{ name = "Magnifying Glass", slotType = "ENGINE" },
	{ name = "Drill",         slotType = "ENGINE" },

	-- ── SPECIAL (14) ──────────────────────────────────────────────────────────
	{ name = "Balloon Bunch", slotType = "SPECIAL" },
	{ name = "Camera",        slotType = "SPECIAL" },
	{ name = "Cactus",        slotType = "SPECIAL" },
	{ name = "Trophy",        slotType = "SPECIAL" },
	{ name = "Lantern",       slotType = "SPECIAL" },
	{ name = "Magic Wand",    slotType = "SPECIAL" },
	{ name = "Magnet",        slotType = "SPECIAL" },
	{ name = "Gas Can",       slotType = "SPECIAL" },
	{ name = "Pizza",         slotType = "SPECIAL" },
	{ name = "Racing Flag",   slotType = "SPECIAL" },
	{ name = "Rubber Duck",   slotType = "SPECIAL" },
	{ name = "Soda Bottle",   slotType = "SPECIAL" },
	{ name = "Toilet Paper",  slotType = "SPECIAL" },
	{ name = "Umbrella",      slotType = "SPECIAL" },
}

-- ─── Lookup helpers ───────────────────────────────────────────────────────────

-- Build name → entry map for O(1) lookup
ItemTypes.byName = {}
for _, item in ipairs(ItemTypes.ALL) do
	ItemTypes.byName[item.name] = item
end

-- Returns filtered list by slotType
function ItemTypes.getBySlot(slotType)
	local result = {}
	for _, item in ipairs(ItemTypes.ALL) do
		if item.slotType == slotType then
			table.insert(result, item)
		end
	end
	return result
end

return ItemTypes
