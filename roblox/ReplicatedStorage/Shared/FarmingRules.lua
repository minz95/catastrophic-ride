-- FarmingRules.lua
-- The FARMING phase's decisions as pure functions (no Roblox types), so they
-- can be checked over hundreds of cases offline (tests/specs/farming_rules).
-- FarmingManager does the I/O (characters, remotes, telemetry) and asks these
-- what to do.

local FarmingRules = {}

FarmingRules.RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }

local function rank(itemConfig, name)
	local cfg = itemConfig[name]
	return FarmingRules.RARITY_RANK[(cfg and cfg.rarity) or "Common"] or 1
end

--- Where a picked-up item goes.
-- Returns "add" (free slot), "swap", index (drop the weakest held item for a
-- strictly rarer one), or "full".
function FarmingRules.pickupSlot(inventory, newItem, itemConfig, size)
	if #inventory < size then
		return "add"
	end
	local newRank = rank(itemConfig, newItem)
	local weakestIdx, weakestRank = nil, math.huge
	for i, name in ipairs(inventory) do
		local r = rank(itemConfig, name)
		if r < weakestRank then
			weakestIdx, weakestRank = i, r
		end
	end
	if weakestIdx and newRank > weakestRank then
		return "swap", weakestIdx
	end
	return "full"
end

--- Contest winner from button-mash counts: 1 or 2. A tie goes to player 1,
-- the one who reached the item first.
function FarmingRules.contestWinner(presses1, presses2)
	return (presses1 or 0) >= (presses2 or 0) and 1 or 2
end

--- Whether a steal attempt may start. s = {
--   now, thiefCooldownEnd, farmingTimeLeft, disableBefore,
--   thiefItems, victimItems, inventorySize,
--   distance, range, victimInvincibleEnd,
--   self,               -- thief and victim are the same player
--   thiefBusy,          -- the thief's previous attempt is still in its defence window
--   victimUnderAttack } -- someone else is already stealing from the victim
-- Returns true, or false and the reason.
function FarmingRules.canSteal(s)
	if s.self then return false, "self" end
	if s.thiefBusy then return false, "already stealing" end
	if s.now < (s.thiefCooldownEnd or 0) then return false, "cooldown" end
	if s.victimUnderAttack then return false, "victim under attack" end
	if s.farmingTimeLeft < s.disableBefore then return false, "too late" end
	if s.victimItems == 0 then return false, "victim has nothing" end
	if s.thiefItems >= s.inventorySize then return false, "thief is full" end
	if s.distance > s.range then return false, "too far" end
	if s.now < (s.victimInvincibleEnd or 0) then return false, "victim protected" end
	return true
end

--- Result of a steal once its defence window closes: the victim keeps the
-- item only with at least `required` taps made inside the window.
function FarmingRules.stealOutcome(presses, required)
	return (presses or 0) >= required and "defended" or "stolen"
end

return FarmingRules
