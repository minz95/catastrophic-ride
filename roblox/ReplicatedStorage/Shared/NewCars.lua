-- NewCars.lua
-- Junk Motors, the new car showroom on Auto Street (2026-11-18: "a
-- dealership where you pick the car you want at a fixed price, not gacha").
-- Every item you can ride (a BODY item, or one with `ride`) is a new car:
-- bought once with coins at Constants.NEW_CARS.PRICE[rarity], then worn
-- round the waist like a Legend Ride (Modules/LegendShop wears both).
-- Pure: Modules/CarDealer sells them, LobbyHub shows them.
--
-- A player's record: rec.cars = { [item] = true }; worn when rec.legendOn
-- is NewCars.idOf(item) ("car:<item>").

local Constants = require(script.Parent.Constants)

local NewCars = {}

NewCars.PREFIX = "car:"
NewCars.BIOME = "FOREST"   -- built as a car (wheels), not a boat or a plane
NewCars.ORDER = { "Common", "Uncommon", "Rare", "Epic" }

local function rank(rarity)
	return table.find(NewCars.ORDER, rarity) or #NewCars.ORDER + 1
end

--- True when `cfg` (an ItemConfig entry) can be ridden.
function NewCars.rideable(cfg)
	return type(cfg) == "table" and cfg.rarity ~= nil and (cfg.slotType == "BODY" or cfg.ride ~= nil)
end

--- Every new car: { { item, rarity, price } }, cheapest first, then by name.
function NewCars.catalog(itemConfig)
	local out = {}
	for name, cfg in pairs(itemConfig) do
		if type(name) == "string" and name:sub(1, 1) ~= "_" and NewCars.rideable(cfg) then
			table.insert(out, { item = name, rarity = cfg.rarity, price = Constants.NEW_CARS.PRICE[cfg.rarity] })
		end
	end
	table.sort(out, function(a, b)
		if rank(a.rarity) ~= rank(b.rarity) then return rank(a.rarity) < rank(b.rarity) end
		return a.item < b.item
	end)
	return out
end

--- The price of `item` in coins, or nil when it is not a new car.
function NewCars.priceOf(itemConfig, item)
	local cfg = type(item) == "string" and itemConfig[item]
	if not NewCars.rideable(cfg) then return nil end
	return Constants.NEW_CARS.PRICE[cfg.rarity]
end

function NewCars.idOf(item) return NewCars.PREFIX .. item end

--- The item of a worn id "car:<item>", or nil for anything else.
function NewCars.itemOf(id)
	if type(id) ~= "string" or id:sub(1, #NewCars.PREFIX) ~= NewCars.PREFIX then return nil end
	return id:sub(#NewCars.PREFIX + 1)
end

function NewCars.owns(rec, item)
	return rec.cars ~= nil and rec.cars[item] == true
end

--- "ok" or "denied: unknown" | "denied: owned" | "denied: coins".
function NewCars.canBuy(itemConfig, rec, item)
	local price = NewCars.priceOf(itemConfig, item)
	if not price then return "denied: unknown" end
	if NewCars.owns(rec, item) then return "denied: owned" end
	if (rec.coins or 0) < price then return "denied: coins" end
	return "ok"
end

--- Buys `item` with coins and puts it on. Returns "ok" or the reason.
function NewCars.buy(itemConfig, rec, item)
	local res = NewCars.canBuy(itemConfig, rec, item)
	if res ~= "ok" then return res end
	rec.coins -= NewCars.priceOf(itemConfig, item)
	rec.cars = rec.cars or {}
	rec.cars[item] = true
	rec.legendOn = NewCars.idOf(item)   -- on at once: the point of buying it
	return "ok"
end

--- What LegendShop.wear builds for new car `item` (a Legend Ride's shape).
function NewCars.ride(item, trying)
	return { title = item, ownerName = "Junk Motors", biome = NewCars.BIOME, slots = { BODY = item }, look = {},
		new = true, trying = trying == true }
end

--- The cars a player owns, for the shop's garage: { { id, item, title, new, tag } }.
function NewCars.owned(rec)
	local out = {}
	for item in pairs(rec.cars or {}) do
		table.insert(out, { id = NewCars.idOf(item), item = item, title = item, new = true, tag = "JUNK MOTORS" })
	end
	table.sort(out, function(a, b) return a.title < b.title end)
	return out
end

return NewCars
