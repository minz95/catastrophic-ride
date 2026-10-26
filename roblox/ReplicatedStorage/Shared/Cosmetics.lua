-- Cosmetics.lua
-- What the shop sells. Vehicle looks (special rides, paints, trails) have no
-- mass or collision, so handling never changes (the build must not decide
-- the race). Farming extras: a move changes how your punch looks only; a
-- gadget is one small trick per round (Constants.GADGETS). Bought with coins (Shared/Progression), kept in the
-- saved record (owned / equipped), applied by VehicleBuilder.build(…, look).
-- Each category's first entry is the free default.

local Cosmetics = {}

Cosmetics.CATEGORIES = { "ride", "paint", "trail", "move", "gadget" }
Cosmetics.TITLES = { ride = "Special Rides", paint = "Paint", trail = "Trail", move = "Moves", gadget = "Gadgets" }

local C3 = Color3.fromRGB

Cosmetics.ITEMS = {
	-- Special rides: the whole vehicle (car, boat or plane) turns into a show.
	-- They replace the paint and the trail while equipped. `material` goes on
	-- the body-coloured parts; `light` is a glow on the chassis; `fx` are
	-- particles that pour out while the vehicle drives forward (client:
	-- CosmeticFx, rate grows with speed); `hue` cycles the body colour.
	ride = {
		{ id = "ride_none", name = "My Build", price = 0 },
		{ id = "ride_flame",   name = "Flame Rider",  price = 1000, minLevel = 4,
			body = C3(25, 20, 20), accent = C3(255, 90, 20), material = "SmoothPlastic", light = C3(255, 120, 40),
			fx = "flame", trail = { colors = { C3(255, 220, 60), C3(255, 60, 20) }, light = 0.7 } },
		{ id = "ride_neon",    name = "Neon Phantom", price = 1300, minLevel = 5,
			body = C3(20, 255, 220), accent = C3(255, 40, 200), material = "Neon", light = C3(40, 255, 230),
			fx = "sparks", trail = { colors = { C3(40, 255, 230), C3(255, 40, 200) }, light = 1 } },
		{ id = "ride_rainbow", name = "Rainbow Comet", price = 1800, minLevel = 6,
			body = C3(255, 255, 255), accent = C3(255, 200, 40), material = "Glass", light = C3(255, 255, 255),
			fx = "rainbow", hue = true, trail = { rainbow = true, light = 0.8 } },
		{ id = "ride_gold",    name = "Golden Legend", price = 3000, minLevel = 10,
			body = C3(255, 200, 40), accent = C3(255, 245, 200), material = "Foil", light = C3(255, 210, 90),
			fx = "gold", trail = { colors = { C3(255, 230, 120), C3(255, 170, 20) }, light = 0.9 } },
	},
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
	-- Moves (FARMING): how your punch looks. Same reach, cooldown and hits
	-- (FarmingRules): a show, not an advantage.
	move = {
		{ id = "move_punch", name = "Punch", price = 0 },
		{ id = "move_kick",  name = "Flying Kick", price = 700, minLevel = 2, style = "kick" },
	},
	-- Gadgets (FARMING): one use per round (Constants.GADGETS).
	gadget = {
		{ id = "gadget_none",  name = "No Gadget", price = 0 },
		{ id = "gadget_smoke", name = "Smoke Bomb", price = 900, minLevel = 3, gadget = "smoke" },
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

--- What to put in front of a player who just earned coins (results
-- screen): the priciest look they can buy now ({ item, affordable = true }),
-- else the cheapest one their level allows ({ item, short = coins missing }),
-- nil when they own everything. `rec`: { coins, level, owned } with owned a
-- set or a list of ids (Modules/Shop.state sends a list).
function Cosmetics.suggest(rec)
	local owned = {}
	for k, v in pairs(rec.owned or {}) do
		if type(k) == "string" and v then owned[k] = true elseif type(v) == "string" then owned[v] = true end
	end
	local probe = { coins = rec.coins or 0, level = rec.level or 1, owned = owned }
	local best, cheapest
	for _, cat in ipairs(Cosmetics.CATEGORIES) do
		for _, it in ipairs(Cosmetics.ITEMS[cat]) do
			if not Cosmetics.owns(probe, it.id) and probe.level >= (it.minLevel or 1) then
				if probe.coins >= it.price then
					if not best or it.price > best.price then best = it end
				elseif not cheapest or it.price < cheapest.price then
					cheapest = it
				end
			end
		end
	end
	if best then return { item = best, affordable = true } end
	if cheapest then return { item = cheapest, short = cheapest.price - probe.coins } end
	return nil
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

--- The equipped, non-default item of a category (nil for defaults and
-- for ids no longer sold).
function Cosmetics.equipped(equipped, category)
	local id = equipped and equipped[category]
	local it = id and _byId[id]
	if it and it.category == category and not Cosmetics.isDefault(id) then return it end
	return nil
end

--- What VehicleBuilder needs: { paint = item?, trail = item?, ride = item? }.
-- A special ride brings its own paint and trail.
function Cosmetics.look(equipped)
	local look = {
		paint = Cosmetics.equipped(equipped, "paint"),
		trail = Cosmetics.equipped(equipped, "trail"),
	}
	local ride = Cosmetics.equipped(equipped, "ride")
	if ride then
		look.ride = ride
		look.paint = { body = ride.body, accent = ride.accent }
		look.trail = ride.trail
	end
	return look
end

return Cosmetics
