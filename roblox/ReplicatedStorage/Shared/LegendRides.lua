-- LegendRides.lua
-- Rules for Legend Rides (Constants.LEGEND): a ride show winner's ride on
-- sale in the shop, few copies for a short time; the winner owns the
-- original for free. Pure: Modules/LegendStore keeps the listings (shared by
-- every server), Modules/Shop sells them, ShopUI shows `view`.
--
-- A listing: { id, ownerId, ownerName, title, biome, slots, look, votes,
--   at, endsAt, limit, sold }
-- A player's record: rec.legend = { [id] = { title, ownerName, biome, slots,
--   look, original } }, rec.legendOn = the id worn (or nil).

local Constants = require(script.Parent.Constants)

local L = Constants.LEGEND
local LegendRides = {}

--- A new listing from a hall-of-fame entry (Modules/HallOfFame.entry).
function LegendRides.listing(e, now)
	now = now or e.at or 0
	local body = e.slots and e.slots.BODY
	local title = string.format("%s's %s", e.name, body or "Ride")
	return {
		id = string.format("%d_%d", e.userId, now), ownerId = e.userId, ownerName = e.name,
		title = title, biome = e.biome, slots = e.slots, look = e.look or {}, votes = e.votes or 0,
		at = now, endsAt = now + L.DAYS * 86400, limit = L.LIMIT, sold = 0,
	}
end

function LegendRides.isOpen(l, now)
	return now < l.endsAt and (l.sold or 0) < l.limit
end

--- "ok" or "denied: <reason>" for `userId` (record `rec`) buying listing
-- `l` at `now`; `withCoins`: also checks the coins.
function LegendRides.canBuy(l, rec, userId, now, withCoins)
	if not l then return "denied: unknown" end
	if l.ownerId == userId or (rec.legend and rec.legend[l.id]) then return "denied: owned" end
	if (l.sold or 0) >= l.limit then return "denied: sold out" end
	if now >= l.endsAt then return "denied: ended" end
	if withCoins and (rec.coins or 0) < L.COINS then return "denied: coins" end
	return "ok"
end

--- Puts listing `l` into the record (bought, or the winner's original).
-- `serial`: which copy it is (1 … limit), shown as "#7/50" wherever it rides.
function LegendRides.give(rec, l, original, serial)
	rec.legend = rec.legend or {}
	rec.legend[l.id] = { title = l.title, ownerName = l.ownerName, biome = l.biome, slots = l.slots,
		look = l.look, original = original == true, serial = serial, limit = l.limit }
end

--- The tag a ride carries: "⭐ ORIGINAL" or "#7/50" ("JUNK MOTORS" on a
-- new car, "TRYING ON" during a try-on).
function LegendRides.tag(owned)
	if owned.trying then return "TRYING ON" end
	if owned.new then return "JUNK MOTORS" end   -- a new car (Shared/NewCars)
	if owned.original then return "⭐ ORIGINAL" end
	if owned.serial then return string.format("#%d/%d", owned.serial, owned.limit or Constants.LEGEND.LIMIT) end
	return "LEGEND"
end

--- The listings still on sale, newest first, at most SHOWN.
function LegendRides.active(list, now)
	local out = {}
	for _, l in ipairs(list or {}) do
		if LegendRides.isOpen(l, now) then table.insert(out, l) end
	end
	table.sort(out, function(a, b) return a.at > b.at end)
	while #out > L.SHOWN do table.remove(out) end
	return out
end

--- Adds `l` to the stored list (newest kept, at most KEEP). Pure on the list.
function LegendRides.add(list, l)
	list = list or {}
	for _, o in ipairs(list) do
		if o.id == l.id then return list end
	end
	table.insert(list, l)
	table.sort(list, function(a, b) return a.at > b.at end)
	while #list > L.KEEP do table.remove(list) end
	return list
end

--- Takes one copy of listing `id` in the stored list if it is still open.
-- Returns the list and "ok" | "denied: …".
function LegendRides.take(list, id, now)
	for _, l in ipairs(list or {}) do
		if l.id == id then
			if (l.sold or 0) >= l.limit then return list, "denied: sold out" end
			if now >= l.endsAt then return list, "denied: ended" end
			l.sold = (l.sold or 0) + 1
			return list, "ok"
		end
	end
	return list, "denied: unknown"
end

--- What the shop shows a player: { listings = { … }, owned = { … }, on }.
function LegendRides.view(list, rec, userId, now)
	local listings = {}
	for _, l in ipairs(LegendRides.active(list, now)) do
		table.insert(listings, { id = l.id, title = l.title, ownerName = l.ownerName, votes = l.votes,
			sold = l.sold or 0, limit = l.limit, daysLeft = math.max(0, math.ceil((l.endsAt - now) / 86400)),
			owned = (rec.legend and rec.legend[l.id]) ~= nil or l.ownerId == userId })
	end
	local owned = {}
	for id, r in pairs(rec.legend or {}) do
		table.insert(owned, { id = id, title = r.title, ownerName = r.ownerName, original = r.original,
			tag = LegendRides.tag(r) })
	end
	table.sort(owned, function(a, b) return a.id > b.id end)
	return { listings = listings, owned = owned, on = rec.legendOn, coins = L.COINS }
end

return LegendRides
