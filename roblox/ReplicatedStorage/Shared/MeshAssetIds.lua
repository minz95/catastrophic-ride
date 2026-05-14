-- MeshAssetIds.lua
-- Maps item names → Roblox mesh asset IDs (rbxassetid://XXXXXXXXXX).
-- After importing each FBX from assets/items/ in Roblox Studio:
--   File → Import 3D → select .fbx → copy the generated asset ID here.
-- ItemModelBuilder checks this table first; falls back to procedural Part model if empty.
-- Resolves: Issue #93

local MeshAssetIds = {
	-- ── BODY ──────────────────────────────────────────────────────────────────
	["Backpack"]       = "",   -- assets/items/backpack.fbx
	["Bamboo Raft"]    = "",   -- assets/items/bamboo_raft.fbx
	["Barrel"]         = "",   -- assets/items/barrel.fbx
	["Bathtub"]        = "",   -- assets/items/bathtub.fbx
	["Cardboard Box"]  = "",   -- assets/items/cardboard_box.fbx
	["Kite"]           = "",   -- assets/items/kite.fbx
	["Life Preserver"] = "",   -- assets/items/life_preserver.fbx
	["Log"]            = "",   -- assets/items/log.fbx
	["Microwave"]      = "",   -- assets/items/microwave.fbx
	["Red Sofa"]       = "",   -- assets/items/red_sofa.fbx
	["Shopping Cart"]  = "",   -- assets/items/shopping_cart.fbx
	["Skateboard"]     = "",   -- assets/items/skateboard.fbx
	["Suitcase"]       = "",   -- assets/items/suitcase.fbx

	-- ── ENGINE ────────────────────────────────────────────────────────────────
	["Cup Noodle"]     = "",   -- assets/items/cup_noodle.fbx
	["Fan"]            = "",   -- assets/items/fan.fbx
	["Flower"]         = "",   -- assets/items/flower.fbx
	["Kettle"]         = "",   -- assets/items/kettle.fbx
	["Leaf Blower"]    = "",   -- assets/items/leaf_blower.fbx
	["Pinwheel"]       = "",   -- assets/items/pinwheel.fbx
	["Propeller"]      = "",   -- assets/items/propeller.fbx
	["Rocket"]         = "",   -- assets/items/rocket.fbx
	["Spinning Top"]   = "",   -- assets/items/spinning_top.fbx
	["V8 Engine"]      = "",   -- assets/items/v8_engine.fbx
	["Watering Can"]   = "",   -- assets/items/watering_can.fbx

	-- ── SPECIAL ───────────────────────────────────────────────────────────────
	["Balloon Bunch"]  = "",   -- assets/items/Balloon Bunch.fbx
	["Cactus"]         = "",   -- assets/items/Cactus.fbx
	["Camera"]         = "",   -- assets/items/Camera.fbx
	["Gas Can"]        = "",   -- assets/items/Gas Can.fbx
	["Lantern"]        = "",   -- assets/items/Lantern.fbx
	["Magic Wand"]     = "",   -- assets/items/Magic Wand.fbx
	["Magnet"]         = "",   -- assets/items/Magnet.fbx
	["Pizza"]          = "",   -- assets/items/Pizza.fbx
	["Racing Flag"]    = "",   -- assets/items/Racing Flag.fbx
	["Rubber Duck"]    = "",   -- assets/items/Rubber Duck.fbx
	["Soda Bottle"]    = "",   -- assets/items/Soda Bottle.fbx
	["Toilet Paper"]   = "",   -- assets/items/Toilet Paper.fbx
	["Trophy"]         = "",   -- assets/items/Trophy.fbx
	["Umbrella"]       = "",   -- assets/items/Umbrella.fbx
}

return MeshAssetIds
