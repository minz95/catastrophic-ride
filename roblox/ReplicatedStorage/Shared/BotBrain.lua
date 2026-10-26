-- BotBrain.lua
-- Decision rules for harness bots during FARMING and CRAFTING. Pure: the
-- caller passes plain tables (positions as {x, z}) and acts on the answer.
--
-- Used by BotDriver (Studio multiplayer test) and tests/lib/farmsim (Lune).
-- The rules are a plausible player, not an optimal one; profiles vary the
-- greed, speed of button mashing and willingness to steal.

local ItemConfig   = require(script.Parent.ItemConfig)
local VehicleStats = require(script.Parent.VehicleStats)
local Constants    = require(script.Parent.Constants)

local BotBrain = {}

local RARITY_VALUE = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8 }
BotBrain.RARITY_VALUE = RARITY_VALUE

-- mashRate      contest presses per second
-- greed         how far (studs) a bot will walk for each extra rarity point
-- stealChance   probability per second of trying to steal when in range
-- defendChance  probability of tapping fast enough to block a steal
-- crafter       "optimal" (search best top speed) | "casual" (first fit)
--               | "slow" (places items like casual, never presses Submit)
--               | "none"
-- punchChance   probability per second of punching a player in reach
--               (>= 1: also walks up to players within huntRange to fight)
-- guardChance   probability of holding G after being punched
-- huntRange     studs a bot walks to reach a steal victim (0 = only steals
--               from players it happens to pass)
BotBrain.PROFILES = {
	sweaty  = { mashRate = 11, greed = 40, stealChance = 0.6, defendChance = 0.8, punchChance = 0.5, guardChance = 0.6, crafter = "optimal", huntRange = 40 },
	casual  = { mashRate = 7,  greed = 15, stealChance = 0.1, defendChance = 0.4, punchChance = 0.1, guardChance = 0.3, crafter = "casual",  huntRange = 0 },
	afk     = { mashRate = 0,  greed = 0,  stealChance = 0,   defendChance = 0,   punchChance = 0,   guardChance = 0,   crafter = "none",    huntRange = 0 },
	slow    = { mashRate = 7,  greed = 15, stealChance = 0,   defendChance = 0.4, punchChance = 0,   guardChance = 0.3, crafter = "slow",    huntRange = 0 },
	-- harness profiles: every encounter turns into a steal attempt / a fight
	thief   = { mashRate = 9,  greed = 10, stealChance = 5,   defendChance = 0.2, punchChance = 0,   guardChance = 0.2, crafter = "casual",  huntRange = 120 },
	guard   = { mashRate = 9,  greed = 20, stealChance = 0,   defendChance = 1,   punchChance = 0,   guardChance = 1,   crafter = "optimal", huntRange = 0 },
	brawler = { mashRate = 9,  greed = 10, stealChance = 0,   defendChance = 0.3, punchChance = 8,   guardChance = 0.2, crafter = "casual",  huntRange = 120 },
	-- trailer recording (record-* scenarios): a thief that leaves its draft on the
	-- crafting screen, so the phase runs its whole timer on camera
	filmer  = { mashRate = 9,  greed = 10, stealChance = 5,   defendChance = 0.2, punchChance = 0,   guardChance = 0.2, crafter = "slow",    huntRange = 120 },
}

local function rarityRank(name)
	local cfg = ItemConfig[name]
	return cfg and RARITY_VALUE[cfg.rarity] or 0
end

local function weakestIndex(inventory)
	local idx, rank = nil, math.huge
	for i, name in ipairs(inventory) do
		local r = rarityRank(name)
		if r < rank then idx, rank = i, r end
	end
	return idx, rank
end

--- Chooses an item to walk to.
-- items: { { id, name, x, z } }, me: { x, z }, inventory: { itemName }
-- returns the chosen item table or nil.
function BotBrain.pickItem(profile, me, items, inventory)
	local full = #inventory >= Constants.INVENTORY_SIZE
	local _, weakest = weakestIndex(inventory)
	local best, bestScore = nil, -math.huge
	for _, it in ipairs(items) do
		local value = rarityRank(it.name)
		-- Server only swaps into a full inventory if strictly better
		if not full or value > (weakest or 0) then
			local dx, dz = it.x - me.x, it.z - me.z
			local dist = math.sqrt(dx * dx + dz * dz)
			local score = value * (profile.greed or 0) - dist
			if score > bestScore then
				best, bestScore = it, score
			end
		end
	end
	return best
end

--- Whether to attempt a steal this tick.
function BotBrain.wantsSteal(profile, dt, rng)
	return (rng or math.random)() < (profile.stealChance or 0) * dt
end

-- Seconds a hunting bot chases one victim, then farms before the next hunt.
BotBrain.HUNT_TIME = 10
BotBrain.HUNT_REST = 4
-- Seconds a bot walks toward one item before giving up on it (unreachable
-- items used to hold a bot for the whole phase).
BotBrain.ITEM_GIVE_UP = 8

--- Who to steal from: the nearest other player with items within reach
-- (STEAL_RANGE, or huntRange when hunting), or nil.
-- others: { { userId, x, z, items } }, me: { x, z, items }
function BotBrain.pickVictim(profile, me, others)
	if (profile.stealChance or 0) <= 0 or (me.items or 0) >= Constants.INVENTORY_SIZE then
		return nil
	end
	local reach = math.max(Constants.STEAL_RANGE, profile.huntRange or 0)
	local best, bestD = nil, math.huge
	for _, o in ipairs(others) do
		if (o.items or 0) > 0 then
			local dx, dz = o.x - me.x, o.z - me.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= reach and d < bestD then best, bestD = o, d end
		end
	end
	return best, bestD
end

--- Fights (Constants.FIGHT): whether to throw a punch this tick at a player
-- in reach, whom to go after (nearest other player within FIGHT.RANGE, or
-- huntRange for a profile with punchChance >= 1), and whether a punched bot
-- raises its guard.
function BotBrain.wantsPunch(profile, dt, rng)
	return (rng or math.random)() < (profile.punchChance or 0) * dt
end

function BotBrain.pickFoe(profile, me, others)
	if (profile.punchChance or 0) <= 0 then return nil end
	local reach = (profile.punchChance >= 1) and math.max(Constants.FIGHT.RANGE, profile.huntRange or 0)
		or Constants.FIGHT.RANGE
	local best, bestD = nil, math.huge
	for _, o in ipairs(others) do
		local dx, dz = o.x - me.x, o.z - me.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= reach and d < bestD then best, bestD = o, d end
	end
	return best, bestD
end

function BotBrain.guards(profile, rng)
	return (rng or math.random)() < (profile.guardChance or 0)
end

--- Whether a steal attempt against this bot gets defended.
function BotBrain.defends(profile, rng)
	return (rng or math.random)() < (profile.defendChance or 0)
end

local CORE = { "BODY", "ENGINE", "SPECIAL" }

local function statsFor(slots, biome)
	local stats = VehicleStats.calculate(
		slots.BODY and ItemConfig[slots.BODY],
		slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL],
		biome)
	return VehicleStats.applyMobility(stats, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
end
BotBrain.statsFor = statsFor

--- Seat MaxSpeed for a slot assignment, as VehicleBuilder derives it.
function BotBrain.topSpeed(slots, biome)
	local s = statsFor(slots, biome)
	return Constants.maxSpeedFor(biome or "FOREST", s), s
end

--- Picks slots from an inventory.
-- "optimal": exhaustive search over BODY/ENGINE/SPECIAL/MOBILITY for the
--            highest top speed (inventory ≤ 8, so this is cheap).
-- "casual" : first item of each matching type, mobility = first leftover.
function BotBrain.chooseSlots(profile, inventory, biome)
	local mode = profile.crafter or "casual"
	if mode == "none" then
		return {}
	end
	local byType = { BODY = {}, ENGINE = {}, SPECIAL = {} }
	for i, name in ipairs(inventory) do
		local cfg = ItemConfig[name]
		if cfg and byType[cfg.slotType] then
			table.insert(byType[cfg.slotType], i)
		end
	end

	if mode == "slow" then
		-- the LAST item of each type (the auto craft takes the first), so a
		-- kept draft is told apart from a fresh auto craft
		local slots = {}
		for _, slot in ipairs(CORE) do
			local list = byType[slot]
			if #list > 0 then slots[slot] = inventory[list[#list]] end
		end
		return slots
	end

	if mode == "casual" then
		local used, slots = {}, {}
		for _, slot in ipairs(CORE) do
			local i = byType[slot][1]
			if i then slots[slot] = inventory[i]; used[i] = true end
		end
		for i, name in ipairs(inventory) do
			if not used[i] then slots.MOBILITY = name; used[i] = true; break end
		end
		return slots
	end

	local best, bestUsed, bestSpeed = {}, {}, -1
	local function options(list)
		local o = { false }
		for _, i in ipairs(list) do table.insert(o, i) end
		return o
	end
	for _, b in ipairs(options(byType.BODY)) do
		for _, e in ipairs(options(byType.ENGINE)) do
			for _, s in ipairs(options(byType.SPECIAL)) do
				local used = {}
				if b then used[b] = true end
				if e then used[e] = true end
				if s then used[s] = true end
				local mobOptions = { false }
				for i = 1, #inventory do
					if not used[i] then table.insert(mobOptions, i) end
				end
				for _, m in ipairs(mobOptions) do
					local slots = {
						BODY = b and inventory[b] or nil,
						ENGINE = e and inventory[e] or nil,
						SPECIAL = s and inventory[s] or nil,
						MOBILITY = m and inventory[m] or nil,
					}
					local _, st = BotBrain.topSpeed(slots, biome)
					-- Speed stat first (MaxSpeed saturates at the top of the
					-- Constants.RACE_SPEED band, the stat keeps ordering builds);
					-- boost duration breaks ties (SPECIAL items never change speed).
					local score = st.speed * 1000 + (st.boostDuration or 0)
					if score > bestSpeed then
						local u = table.clone(used)
						if m then u[m] = true end
						best, bestUsed, bestSpeed = slots, u, score
					end
				end
			end
		end
	end
	-- Fill HEAD / TAIL with leftover items (their passives are not wired yet).
	local leftovers = {}
	for i = 1, #inventory do
		if not bestUsed[i] then table.insert(leftovers, inventory[i]) end
	end
	best.HEAD = leftovers[1]
	best.TAIL = leftovers[2]
	return best
end

return BotBrain
