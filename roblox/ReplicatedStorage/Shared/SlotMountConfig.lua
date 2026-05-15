-- SlotMountConfig.lua
-- Per-biome, per-slot mount transform table consumed by VehicleBuilder.
-- Declares where each crafted item should appear on the assembled vehicle.
-- Resolves: Issue #139

local V3 = Vector3.new
local CF = CFrame.new

local SlotMountConfig = {}

-- ─── Mount table ──────────────────────────────────────────────────────────────
-- Keys: slotName (BODY/ENGINE/SPECIAL/MOBILITY/HEAD/TAIL) → biome (FOREST/OCEAN/SKY).
--   scale   — target longest-axis size in studs after bbox-normalized rescale
--   offset  — local-space mount offset relative to the hidden physics anchor
--   rot     — Vector3 of Euler angles (degrees) applied to the mounted clone
--   pattern — "single" | "wheels4" | "sail" | "wings2" (consumed by _attachSlotItem)
--
-- Biome notes:
--   FOREST anchor sits at chassis center, +Z is forward (vehicle LookVector).
--   OCEAN  anchor sits at hull center, +Z forward.
--   SKY    anchor sits at fuselage center, -Z is forward (legacy buildFlyer convention).

SlotMountConfig.MOUNTS = {
	BODY = {
		FOREST = { scale = 7.0, offset = V3(0,  0.6, 0), rot = V3(0, 0, 0), pattern = "chassis" },
		OCEAN  = { scale = 8.0, offset = V3(0,  0.4, 0), rot = V3(0, 0, 0), pattern = "chassis" },
		SKY    = { scale = 7.5, offset = V3(0,  0.0, 0), rot = V3(0, 0, 0), pattern = "chassis" },
	},

	MOBILITY = {
		FOREST = { scale = 1.6, offset = V3(0, -0.6, 0), rot = V3(0, 0, 90), pattern = "wheels4" },
		OCEAN  = { scale = 3.5, offset = V3(0,  2.0, 0), rot = V3(0, 0, 0),  pattern = "sail" },
		SKY    = { scale = 3.0, offset = V3(0,  0.0, 0), rot = V3(0, 0, 0),  pattern = "wings2" },
	},

	ENGINE = {
		FOREST = { scale = 2.0, offset = V3(0,  0.8, -2.5), rot = V3(0, 0, 0), pattern = "single" },
		OCEAN  = { scale = 2.0, offset = V3(0,  1.0, -3.0), rot = V3(0, 0, 0), pattern = "single" },
		SKY    = { scale = 1.8, offset = V3(0,  0.0,  2.5), rot = V3(0, 0, 0), pattern = "single" },
	},

	SPECIAL = {
		FOREST = { scale = 2.0, offset = V3(0,  2.0,  0.5), rot = V3(0, 0, 0), pattern = "single" },
		OCEAN  = { scale = 2.0, offset = V3(0,  3.5,  0.5), rot = V3(0, 0, 0), pattern = "single" },
		SKY    = { scale = 1.8, offset = V3(0,  1.0,  0.0), rot = V3(0, 0, 0), pattern = "single" },
	},

	HEAD = {
		FOREST = { scale = 1.8, offset = V3(0,  1.2,  3.0), rot = V3(0, 0, 0), pattern = "single" },
		OCEAN  = { scale = 1.8, offset = V3(0,  1.2,  4.0), rot = V3(0, 0, 0), pattern = "single" },
		SKY    = { scale = 1.8, offset = V3(0,  0.4, -4.0), rot = V3(0, 0, 0), pattern = "single" },
	},

	TAIL = {
		FOREST = { scale = 1.8, offset = V3(0,  1.2, -3.0), rot = V3(0, 0, 0), pattern = "single" },
		OCEAN  = { scale = 1.8, offset = V3(0,  1.2, -4.0), rot = V3(0, 0, 0), pattern = "single" },
		SKY    = { scale = 1.8, offset = V3(0,  0.4,  3.0), rot = V3(0, 0, 0), pattern = "single" },
	},
}

-- ─── API ──────────────────────────────────────────────────────────────────────

function SlotMountConfig.get(slotName, biome)
	local s = SlotMountConfig.MOUNTS[slotName]
	if not s then return nil end
	return s[biome]
end

return SlotMountConfig
