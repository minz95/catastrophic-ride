-- StarterItems.lua
-- Junk waiting next to each player when FARMING starts (FarmingManager), so
-- the first item is a few steps away and a whole car (BODY, ENGINE,
-- SPECIAL) is in reach within seconds. A player's very first round always
-- starts with FIRST, a ride that looks silly at once (you sit in a shopping
-- cart and ram people). A player with a Roblox friend in the server gets
-- one more, a rarer one (FRIEND_BONUS). They are kept for their player for
-- Constants.STARTER.RESERVE s (bots and others leave them), and the client
-- points at them with an arrow (StarterArrow). Pure: no Instances.

local Constants = require(script.Parent.Constants)

local StarterItems = {}

StarterItems.FIRST = "Shopping Cart"
-- later rounds: one of these as the BODY (all look silly to ride)
StarterItems.BODIES = { "Shopping Cart", "Barrel", "Cardboard Box", "Skateboard", "Bamboo Raft", "Log" }
StarterItems.LOW = { Common = true, Uncommon = true }
StarterItems.FRIEND_BONUS = { Rare = true }

local function pickFrom(list, rand)
	if #list == 0 then return nil end
	return list[rand(#list)]
end

--- Names of `slotType` items whose rarity is in `rarities`, sorted.
function StarterItems.of(itemConfig, slotType, rarities)
	local list = {}
	for name, cfg in pairs(itemConfig) do
		if type(cfg) == "table" and cfg.slotType == slotType and rarities[cfg.rarity] then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

--- The starter items for one player: { { name, rarity, bonus = bool }, ... }.
-- `firstRound`: the player never finished a round (FIRST as the BODY).
-- `friend`: a Roblox friend is in the server (one rarer extra).
-- `rand(n)` → 1..n (math.random).
function StarterItems.pick(itemConfig, firstRound, friend, rand)
	rand = rand or math.random
	local out = {}
	local function add(name, bonus)
		local cfg = name and itemConfig[name]
		if cfg then table.insert(out, { name = name, rarity = cfg.rarity, bonus = bonus == true }) end
	end
	add(firstRound and StarterItems.FIRST or pickFrom(StarterItems.BODIES, rand))
	add(pickFrom(StarterItems.of(itemConfig, "ENGINE", StarterItems.LOW), rand))
	add(pickFrom(StarterItems.of(itemConfig, "SPECIAL", StarterItems.LOW), rand))
	if friend then
		local pool = {}
		for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
			for _, n in ipairs(StarterItems.of(itemConfig, slot, StarterItems.FRIEND_BONUS)) do table.insert(pool, n) end
		end
		add(pickFrom(pool, rand), true)
	end
	return out
end

--- Where `n` starter items go round a player standing at `origin` (Vector3)
-- facing `look` (Vector3): a fan in front, Constants.STARTER.DIST studs
-- out, SPREAD studs apart. `ok(x, z)` → false where an item may not stand
-- (FarmBounds.itemSpotOk); such a spot is pulled toward the player, then
-- dropped. Returns the spots (Vector3 with origin's Y), maybe fewer than n.
function StarterItems.spots(origin, look, n, ok)
	local S = Constants.STARTER
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local out = {}
	for i = 1, n do
		local side = (i - (n + 1) / 2) * S.SPREAD
		for _, dist in ipairs({ S.DIST, S.DIST * 0.6, S.DIST * 0.3 }) do
			local p = origin + fwd * dist + right * side
			if not ok or ok(p.X, p.Z) then
				table.insert(out, Vector3.new(p.X, origin.Y, p.Z))
				break
			end
		end
	end
	return out
end

--- True when the item `it` (FarmingManager's record) is kept for someone
-- other than `userId` at time `now`.
function StarterItems.heldFrom(it, userId, now)
	return it ~= nil and it.reservedFor ~= nil and it.reservedFor ~= userId and now < (it.reservedUntil or 0)
end

return StarterItems
