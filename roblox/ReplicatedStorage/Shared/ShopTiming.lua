-- ShopTiming.lua
-- What the shop screen tells a shopper about the game going on around it,
-- and when it gets out of the way. Pure rules (ShopUI draws them).
--
-- History (2026-10-26): the shop stayed open over the crafting screen while
-- the crafting clock ran out, and a lobby shopper found the round already
-- started under the panel. Now the panel shows the phase clock, closes
-- itself CRAFT_CLOSE_AT s before the car is built (once: reopening is the
-- player's choice) and when a round starts or the race begins.

local Constants = require(script.Parent.Constants)

local ShopTiming = {}

local P = Constants.PHASES

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

--- The status line for `phase` with `left` s to go (nil: no clock).
-- Returns text, warn (true: show it in red).
function ShopTiming.line(phase, left)
	local warn = left ~= nil and left <= Constants.SHOP.WARN_AT
	if phase == P.LOBBY then
		if not left then return "Waiting for players", false end
		return "Round starts in " .. clock(left), warn
	elseif phase == P.FARMING then
		return "Farming: " .. clock(left) .. " left to grab items", warn
	elseif phase == P.CRAFTING then
		return "Car is built in " .. clock(left) .. ": your slots are kept, empty ones auto-filled", warn
	elseif phase == P.RESULTS then
		return "Next round in " .. clock(left), warn
	end
	return "", false
end

--- Whether an open shop should close now, and the notice to show then.
-- `from`: the phase before (nil when the phase did not just change);
-- `state.craftClosed`: it already closed itself in this CRAFTING phase.
function ShopTiming.closeFor(phase, from, left, state)
	if phase == P.RACING then
		return true, nil
	end
	if from and from ~= P.FARMING and phase == P.FARMING then
		return true, "The round started: grab items!  (B: shop)"
	end
	if phase == P.CRAFTING and not (state and state.craftClosed)
		and left ~= nil and left <= Constants.SHOP.CRAFT_CLOSE_AT then
		return true, "Finish your car: " .. math.ceil(left) .. " s left!"
	end
	return false, nil
end

return ShopTiming
