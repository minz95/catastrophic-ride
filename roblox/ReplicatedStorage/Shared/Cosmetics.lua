-- Cosmetics.lua
-- What the shop sells: looks only. A paint recolours the vehicle's body /
-- accent roles (VehicleDesign palette); a trail streams behind the chassis.
-- Neither has mass or collision, so handling never changes (the build must
-- not decide the race). Bought with coins (Shared/Progression), kept in the
-- saved record (owned / equipped), applied by VehicleBuilder.build(…, look).
-- Each category's first entry is the free default.

local Cosmetics = {}

Cosmetics.CATEGORIES = { "paint", "trail" }
Cosmetics.TITLES = { paint = "Paint", trail = "Trail" }

local C3 = Color3.fromRGB

Cosmetics.ITEMS = {
	paint = {
		{ id = "paint_default", name = "Biome Colors", price = 0 },
		{ id = "paint_midnight", name = "Midnight", price = 150, body = C3(30, 40, 90),   accent = C3(190, 200, 215) },
		{ id = "paint_lime",     name = "Lime Rush", price = 150, body = C3(120, 210, 40), accent = C3(30, 30, 35) },
		{ id = "paint_bubblegum", name = "Bubblegum", price = 200, body = C3(255, 130, 190), accent = C3(255, 255, 255) },
		{ id = "paint_sunset",   name = "Sunset",    price = 250, body = C3(250, 120, 40),  accent = C3(150, 40, 120) },
		{ id = "paint_arctic",   name = "Arctic",    price = 300, body = C3(225, 240, 250), accent = C3(70, 170, 230), minLevel = 3 },
		{ id = "paint_galaxy",   name = "Galaxy",    price = 450, body = C3(45, 20, 75),    accent = C3(0, 220, 230),  minLevel = 5 },
		{ id = "paint_gold",     name = "Gold Rush", price = 800, body = C3(240, 190, 50),  accent = C3(40, 30, 20),   minLevel = 8 },
	},
	trail = {
		{ id = "trail_none", name = "No Trail", price = 0 },
		{ id = "trail_cloud",   name = "Cloud Puff", price = 200, colors = { C3(255, 255, 255), C3(200, 210, 225) } },
		{ id = "trail_bubbles", name = "Bubbles",    price = 300, colors = { C3(120, 210, 255), C3(220, 245, 255) } },
		{ id = "trail_fire",    name = "Fire",       price = 450, colors = { C3(255, 220, 60), C3(255, 70, 20) }, light = 0.6, minLevel = 4 },
		{ id = "trail_rainbow", name = "Rainbow",    price = 900, rainbow = true, light = 0.4, minLevel = 7 },
	},
}

local _byId = {}
for cat, list in pairs(Cosmetics.ITEMS) do
	for _, it in ipairs(list) do
		it.category = cat
		_byId[it.id] = it
	end
end

function Cosmetics.get(id)
	return _byId[id]
end

function Cosmetics.default(category)
	return Cosmetics.ITEMS[category][1]
end

function Cosmetics.isDefault(id)
	local it = _byId[id]
	return it ~= nil and Cosmetics.ITEMS[it.category][1] == it
end

--- Owns `id` (defaults are always owned).
function Cosmetics.owns(rec, id)
	return Cosmetics.isDefault(id) or (rec.owned and rec.owned[id] == true)
end

--- "ok" or "denied: <reason>" for buying `id` with this record.
function Cosmetics.canBuy(rec, id)
	local it = _byId[id]
	if not it then return "denied: unknown item" end
	if Cosmetics.owns(rec, id) then return "denied: owned" end
	if (rec.level or 1) < (it.minLevel or 1) then return "denied: level " .. it.minLevel end
	if (rec.coins or 0) < it.price then return "denied: coins" end
	return "ok"
end

--- Buys and equips. Returns "ok" or "denied: <reason>" (record unchanged).
function Cosmetics.buy(rec, id)
	local res = Cosmetics.canBuy(rec, id)
	if res ~= "ok" then return res end
	local it = _byId[id]
	rec.coins -= it.price
	rec.owned = rec.owned or {}
	rec.owned[id] = true
	rec.equipped = rec.equipped or {}
	rec.equipped[it.category] = id
	return "ok"
end

--- Equips an owned item. Returns "ok" or "denied: <reason>".
function Cosmetics.equip(rec, id)
	local it = _byId[id]
	if not it then return "denied: unknown item" end
	if not Cosmetics.owns(rec, id) then return "denied: not owned" end
	rec.equipped = rec.equipped or {}
	rec.equipped[it.category] = id
	return "ok"
end

--- What VehicleBuilder needs from the equipped items: { paint = item?, trail = item? }
-- (nil for defaults and for ids no longer sold).
function Cosmetics.look(equipped)
	local look = {}
	for _, cat in ipairs(Cosmetics.CATEGORIES) do
		local id = equipped and equipped[cat]
		local it = id and _byId[id]
		if it and not Cosmetics.isDefault(id) then look[cat] = it end
	end
	return look
end

return Cosmetics
