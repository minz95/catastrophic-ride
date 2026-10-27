-- CraftingRules.lua
-- Checks a client's craft submission against the player's inventory. Pure
-- (no Roblox types): CraftingManager calls it, tests/specs check it.

local CraftingRules = {}

-- Core slots take only items of their own slotType; the others take anything.
-- BODY also takes an item you can ride (ItemConfig `ride`, e.g. Pizza): it
-- becomes the vehicle (VehicleDesign `ride`) with the `ride` weight and grip.
CraftingRules.CORE_SLOTS = { BODY = true, ENGINE = true, SPECIAL = true }
CraftingRules.FREE_SLOTS = { MOBILITY = true, HEAD = true, TAIL = true }
CraftingRules.ORDER = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }

--- Can `cfg` (an ItemConfig entry) go into `slot`?
function CraftingRules.fits(slot, cfg)
	if not cfg then return false end
	if not CraftingRules.CORE_SLOTS[slot] then return CraftingRules.FREE_SLOTS[slot] == true end
	return cfg.slotType == slot or (slot == "BODY" and cfg.ride ~= nil)
end

local SLOT_NAMES = { BODY = "Body", ENGINE = "Engine", SPECIAL = "Special" }

--- Why `item` (config `cfg`) cannot go into `slot`, for the crafting screen
-- (English, player-facing).
function CraftingRules.whyNot(slot, item, cfg)
	local name = SLOT_NAMES[slot] or slot
	if not cfg then return item .. " is not an item." end
	if slot == "BODY" then
		return string.format("%s can't be your ride. Body takes BODY items or ones marked RIDE.", item)
	end
	return string.format("%s is a %s item: %s takes only %s items.", item, cfg.slotType, name, slot)
end

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
			elseif not CraftingRules.fits(slot, cfg) then
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

--- Fills the empty slots of `keep` (already valid slots, e.g. a player's
-- arrangement when the timer ran out) from the unused inventory: the first
-- item of each type goes to BODY / ENGINE / SPECIAL (no BODY item: a
-- rideable leftover is ridden), leftovers to MOBILITY, HEAD, TAIL. Used by the Auto fill button and the timeout auto craft, so
-- both put items where they count.
function CraftingRules.autoSlots(inventory, itemConfig, keep)
	local slots, used = {}, {}
	for slot, item in pairs(keep or {}) do
		for i, held in ipairs(inventory) do
			if held == item and not used[i] then
				used[i] = true
				slots[slot] = item
				break
			end
		end
	end
	for _, slot in ipairs(CraftingRules.ORDER) do
		if slots[slot] == nil and CraftingRules.CORE_SLOTS[slot] then
			for i, name in ipairs(inventory) do
				local cfg = itemConfig[name]
				if not used[i] and cfg and cfg.slotType == slot then
					slots[slot], used[i] = name, true
					break
				end
			end
		end
	end
	if slots.BODY == nil then
		for i, name in ipairs(inventory) do
			local cfg = itemConfig[name]
			if not used[i] and cfg and cfg.ride then
				slots.BODY, used[i] = name, true
				break
			end
		end
	end
	for _, slot in ipairs(CraftingRules.ORDER) do
		if slots[slot] == nil and CraftingRules.FREE_SLOTS[slot] then
			for i, name in ipairs(inventory) do
				if not used[i] then
					slots[slot], used[i] = name, true
					break
				end
			end
		end
	end
	return slots
end

return CraftingRules
