-- AbilitySlots.lua
-- Which crafted items a car can fire with E, shared by the server
-- (AbilityManager checks ownership) and the clients (RacingClient picks the
-- item, the HUD shows it). Pure apart from reading / writing attributes.
--
-- The server writes the car's slots as attributes on the vehicle model
-- (VehicleBuilder), so every client can read them from the model it drives.
-- History: RacingClient used to read a "CraftSlots" folder in PlayerGui that
-- nothing ever created, so E never fired an ability in a real game.

local AbilitySlots = {}

-- E cycles through these slots in this order (core slots: one item type each).
AbilitySlots.ORDER = { "SPECIAL", "ENGINE", "BODY" }
AbilitySlots.ATTR_PREFIX = "Ability_"

--- The slot that holds `item` among the ability slots, or nil.
function AbilitySlots.slotOf(slots, item)
	if type(slots) ~= "table" or type(item) ~= "string" then return nil end
	for _, slot in ipairs(AbilitySlots.ORDER) do
		if slots[slot] == item then return slot end
	end
	return nil
end

--- Equipped ability items in E order: { { slot = "SPECIAL", item = "Pizza" }, ... }.
function AbilitySlots.list(slots)
	local out = {}
	for _, slot in ipairs(AbilitySlots.ORDER) do
		local item = type(slots) == "table" and slots[slot]
		if type(item) == "string" and item ~= "" then
			table.insert(out, { slot = slot, item = item })
		end
	end
	return out
end

--- Writes the ability slots onto a vehicle model as attributes.
function AbilitySlots.write(model, slots)
	for _, slot in ipairs(AbilitySlots.ORDER) do
		local item = type(slots) == "table" and slots[slot] or nil
		model:SetAttribute(AbilitySlots.ATTR_PREFIX .. slot, (type(item) == "string" and item ~= "") and item or nil)
	end
end

--- Reads them back: { SPECIAL = "Pizza", ENGINE = nil, BODY = "Log" }.
function AbilitySlots.read(model)
	local out = {}
	if not model then return out end
	for _, slot in ipairs(AbilitySlots.ORDER) do
		local v = model:GetAttribute(AbilitySlots.ATTR_PREFIX .. slot)
		if type(v) == "string" and v ~= "" then out[slot] = v end
	end
	return out
end

--- The item E fires now: the first equipped item from position `start`
-- (1-based, wraps) whose cooldown has ended. readyAt[item] = time it is ready.
-- Returns item, position or nil, plus the item that is ready soonest and its
-- time (for the HUD) when nothing is ready.
function AbilitySlots.pick(slots, readyAt, now, start)
	local items = AbilitySlots.list(slots)
	local n = #items
	if n == 0 then return nil end
	start = ((math.max(start or 1, 1) - 1) % n) + 1
	local soonest, soonestAt
	for k = 0, n - 1 do
		local i = ((start - 1 + k) % n) + 1
		local item = items[i].item
		local at = (readyAt and readyAt[item]) or 0
		if at <= now then
			return item, i
		end
		if not soonestAt or at < soonestAt then soonest, soonestAt = item, at end
	end
	return nil, nil, soonest, soonestAt
end

return AbilitySlots
