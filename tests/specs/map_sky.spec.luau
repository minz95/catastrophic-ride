--!nocheck
-- SKY map built in the mock engine from the real SkyMap module, checked for
-- geometry problems a player would hit (see tests/lib/biomespecs.luau).
require("../lib/biomespecs").map("SKY", {
	isWall = function(name) return name:sub(1, 11) == "EdgePillar_" end,
	wallOffset = 26,     -- CORRIDOR_W / 2 + 1
	doorway = 1,         -- continuous fence: pillars touch, no doorways
	isFloor = function(name) return name:sub(1, 10) == "TrackFloor" end,
	-- updraft 3 sits on the descent on purpose (a hazard zone), so not listed
	props = { "^CrystalSpire_", "^CrystalTip_" },
})
