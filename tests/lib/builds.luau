--!nocheck
-- builds.luau
-- Enumerates every BODY × ENGINE × SPECIAL × MOBILITY combination for a biome
-- and derives the in-game seat values, using the real VehicleStats module.

local Builds = {}

local MOBILITY_CHOICES = 4 -- none, plus three sampled mobility items per combo

function Builds.enumerate(env, biome)
	local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local bySlot = { BODY = {}, ENGINE = {}, SPECIAL = {} }
	local all = {}
	for name, cfg in pairs(ItemConfig) do
		if type(cfg) == "table" and cfg.slotType and bySlot[cfg.slotType] then
			table.insert(bySlot[cfg.slotType], name)
			table.insert(all, name)
		end
	end
	for _, list in pairs(bySlot) do table.sort(list) end
	table.sort(all)

	-- Mobility candidates: none, best affinity item, a plain item.
	local affinity, plain = nil, nil
	for _, name in ipairs(all) do
		local cfg = ItemConfig[name]
		local aff = cfg.mobilityAffinity and cfg.mobilityAffinity[biome]
		if aff and (not affinity or Constants_rank(cfg.rarity) > Constants_rank(ItemConfig[affinity].rarity)) then
			affinity = name
		end
		if not aff and not plain then plain = name end
	end

	local out = {}
	for _, b in ipairs(bySlot.BODY) do
		for _, e in ipairs(bySlot.ENGINE) do
			for _, s in ipairs(bySlot.SPECIAL) do
				for _, m in ipairs({ false, affinity, plain }) do
					local stats = VehicleStats.calculate(ItemConfig[b], ItemConfig[e], ItemConfig[s], biome)
					stats = VehicleStats.applyMobility(stats, m and ItemConfig[m] or nil, biome)
					table.insert(out, {
						slots = { BODY = b, ENGINE = e, SPECIAL = s, MOBILITY = m or nil },
						stats = stats,
						maxSpeed = math.clamp(stats.speed * 2.5, 20, 120),
						turnSpeed = math.clamp(stats.stability * 0.3, 0.5, 3),
						torque = math.clamp(stats.acceleration * 4, 20, 200),
						boostDuration = stats.boostDuration,
					})
				end
			end
		end
	end
	return out
end

local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
function Constants_rank(r) return RANK[r] or 0 end

--- Picks representative builds by MaxSpeed percentile.
function Builds.representative(list)
	table.sort(list, function(a, b)
		if a.maxSpeed ~= b.maxSpeed then return a.maxSpeed < b.maxSpeed end
		return a.turnSpeed < b.turnSpeed
	end)
	local function at(p)
		return list[math.clamp(math.floor(#list * p) + 1, 1, #list)]
	end
	return {
		{ label = "slowest", build = list[1] },
		{ label = "p50", build = at(0.5) },
		{ label = "fastest", build = list[#list] },
	}
end

function Builds.describe(b)
	local s = b.slots
	return string.format("%s + %s + %s%s", s.BODY, s.ENGINE, s.SPECIAL, s.MOBILITY and (" + " .. s.MOBILITY) or "")
end

return Builds
