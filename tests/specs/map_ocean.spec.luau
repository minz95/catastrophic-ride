--!nocheck
-- OCEAN map built in the mock engine from the real OceanMap module, checked
-- for geometry problems a player would hit (see tests/lib/biomespecs.luau).
require("../lib/biomespecs").map("OCEAN", {
	isWall = function(name) return name == "ReefWall" end,
	wallOffset = 31.5,   -- LANE_W / 2 + WALL_T / 2
	doorway = 8,         -- WALL_GAP_HALF_WIDTH * 2: intended sail-out openings
	-- buoys are lane-edge markers by design (CanCollide false), so not listed
	props = { "^PalmTrunk$", "^ReefSpire_%d+$" },
})
