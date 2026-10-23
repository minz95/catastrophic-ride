-- ItemBlurbs.lua
-- One line per item for the crafting screen: what its E ability does in a
-- race. AbilityConfig (server only) holds the numbers; these stay
-- qualitative so a balance change does not make them wrong.
-- tests/specs/config.spec.luau checks every item has one.

local ItemBlurbs = {}

ItemBlurbs.SLOT_HINT = {
	BODY    = "Body: weight and grip",
	ENGINE  = "Engine: acceleration and speed",
	SPECIAL = "Special: boost",
}

ItemBlurbs.ABILITY = {
	-- BODY
	["Barrel"]         = "Rolls sideways and knocks nearby racers aside",
	["Cardboard Box"]  = "Hide inside: rivals' abilities and bumps can't touch you",
	["Bamboo Raft"]    = "Glide: faster, with slippery steering",
	["Skateboard"]     = "Slide: faster, but very twitchy steering",
	["Log"]            = "Drops a log on the track behind you",
	["Shopping Cart"]  = "Ram forward and shove racers you hit",
	["Life Preserver"] = "Float up and speed along",
	["Kite"]           = "Lift up and speed along",
	["Suitcase"]       = "Lock shut: absorbs the next hit, small boost",
	["Backpack"]       = "Refills your boost gauge and speeds you up",
	["Red Sofa"]       = "Nothing can hurt you; racers next to you bounce off",
	["Microwave"]      = "Freezes every racer near you",
	["Bathtub"]        = "Splashes and slows every racer near you",
	-- ENGINE
	["Fan"]              = "Gust that pushes back and slows racers near you",
	["Flower"]           = "Shakes off every slowdown and protects you briefly",
	["Alarm Clock"]      = "Rides the wind: a small boost, stronger at sea and in the sky",
	["Magnifying Glass"] = "Drops a slippery puddle behind you",
	["Hair Dryer"]       = "Strong blast that pushes back racers near you",
	["Compass"]          = "Spin burst: a big boost in a slightly random direction",
	["Propeller Hat"]    = "Hover up for a while",
	["Treadmill"]        = "Much faster, but no steering while it lasts",
	["Drill"]            = "Mud and off-track slowdowns don't affect you",
	["Rocket"]           = "Rocket burst forward",
	["Cup Noodle"]       = "Snares the nearest racer and slows them",
	["Kettle"]           = "Leaves a steam cloud behind you",
	-- SPECIAL
	["Gas Can"]       = "Drops a slick behind you",
	["Pizza"]         = "Drops a slippery puddle behind you",
	["Toilet Paper"]  = "Wraps the nearest racer: they can barely steer",
	["Cactus"]        = "Drops a cactus on the track behind you",
	["Magnet"]        = "Pulls the nearest racer back and slows them",
	["Racing Flag"]   = "Rally: a speed boost",
	["Lantern"]       = "Lifts you up with a small boost",
	["Camera"]        = "Flash: the nearest racer can't steer for a moment",
	["Magic Wand"]    = "Magic burst forward",
	["Umbrella"]      = "Shield: blocks the next hit, small boost",
	["Rubber Duck"]   = "Saves you: float, soft landing or a hop",
	["Trophy"]        = "Rally: a speed boost",
	["Balloon Bunch"] = "Rise up with a boost",
	["Soda Bottle"]   = "Fizz blast forward",
}

--- "Body: weight and grip · E: Rolls sideways …" for an item, or "" if unknown.
function ItemBlurbs.line(name, cfg)
	local parts = {}
	if cfg and ItemBlurbs.SLOT_HINT[cfg.slotType] then table.insert(parts, ItemBlurbs.SLOT_HINT[cfg.slotType]) end
	if ItemBlurbs.ABILITY[name] then table.insert(parts, "E: " .. ItemBlurbs.ABILITY[name]) end
	return table.concat(parts, "  ·  ")
end

return ItemBlurbs
