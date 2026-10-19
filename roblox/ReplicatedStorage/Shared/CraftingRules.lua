-- CraftingRules.lua
-- Checks a client's craft submission against the player's inventory. Pure
-- (no Roblox types): CraftingManager calls it, tests/specs check it.

local CraftingRules = {}

-- Core slots take only items of their own slotType; the others take anything.
CraftingRules.CORE_SLOTS = { BODY = true, ENGINE = true, SPECIAL = true }
CraftingRules.FREE_SLOTS = { MOBILITY = true, HEAD = true, TAIL = true }
CraftingRules.ORDER = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }

--- Returns clean slots (every item from the inventory, each inventory entry
-- used once) and the rejected entries { slot, item, reason }.
-- Returns nil, "bad slots" when `slots` is not a table.
function CraftingRules.validate(slots, inventory, itemConfig)
	if type(slots) ~= "table" then
		return nil, "bad slots"
	end
	local clean, rejected, used = {}, {}, {}
	for slot, item in pairs(slots) do
		if not (CraftingRules.CORE_SLOTS[slot] or CraftingRules.FREE_SLOTS[slot]) then
			table.insert(rejected, { slot = tostring(slot), item = tostring(item), reason = "unknown slot" })
		end
	end
	for _, slot in ipairs(CraftingRules.ORDER) do
		local item = slots[slot]
		if item ~= nil and item ~= "" then
			local cfg = type(item) == "string" and itemConfig[item]
			local reason
			if not cfg then
				reason = "unknown item"
			elseif CraftingRules.CORE_SLOTS[slot] and cfg.slotType ~= slot then
				reason = "wrong type (" .. tostring(cfg.slotType) .. ")"
			else
				reason = "not in inventory"
				for i, held in ipairs(inventory) do
					if held == item and not used[i] then
						used[i] = true
						reason = nil
						break
					end
				end
			end
			if reason then
				table.insert(rejected, { slot = slot, item = tostring(item), reason = reason })
			else
				clean[slot] = item
			end
		end
	end
	return clean, rejected
end

return CraftingRules
