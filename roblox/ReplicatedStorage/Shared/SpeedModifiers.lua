-- SpeedModifiers.lua
-- A multiplicative stack of speed effects (mud, slow zone, boost pad, ...).
-- Each effect has an id; adding the same id twice replaces it, and removing
-- an effect can never leave the base speed changed. Pure, no Roblox types.
--
-- Used by the race simulators today. RacingManager still mutates
-- VehicleSeat.MaxSpeed directly with save/restore pairs, which drifts when
-- effects overlap — tests/specs/racing_manager.spec.luau documents that.

local SpeedModifiers = {}
SpeedModifiers.__index = SpeedModifiers

--- `maxBoost` (optional): the product of the multipliers above 1 is capped
-- at this (Constants.SPEED_STACK_MAX for MaxSpeed); slowdowns still apply.
function SpeedModifiers.new(baseSpeed, maxBoost)
	return setmetatable({ base = baseSpeed, effects = {}, maxBoost = maxBoost }, SpeedModifiers)
end

--- Adds or replaces an effect. `expiresAt` (seconds, same clock as `now`
-- passed to value()) is optional; without it the effect lasts until removed.
function SpeedModifiers:set(id, mult, expiresAt)
	self.effects[id] = { mult = mult, expiresAt = expiresAt }
end

function SpeedModifiers:remove(id)
	self.effects[id] = nil
end

function SpeedModifiers:has(id, now)
	local e = self.effects[id]
	if not e then return false end
	if e.expiresAt and now and now >= e.expiresAt then
		self.effects[id] = nil
		return false
	end
	return true
end

--- Effective speed at time `now`; expired effects are dropped.
function SpeedModifiers:value(now)
	local up, down = 1, 1
	for id, e in pairs(self.effects) do
		if e.expiresAt and now and now >= e.expiresAt then
			self.effects[id] = nil
		elseif e.mult > 1 then
			up *= e.mult
		else
			down *= e.mult
		end
	end
	if self.maxBoost then up = math.min(up, self.maxBoost) end
	return self.base * up * down
end

return SpeedModifiers
