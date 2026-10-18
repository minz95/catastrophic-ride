-- VehicleTuning.lua
-- The ONLY place that writes VehicleSeat.MaxSpeed / TurnSpeed during a race.
--
-- Every effect (mud, slow zone, obstacle bump, boost pad, boost, abilities,
-- passives) is a named multiplier in a SpeedModifiers stack per seat:
--
--   VehicleTuning.set(seat, "MaxSpeed", "mud", 0.5)          -- until removed
--   VehicleTuning.set(seat, "MaxSpeed", "obstacle", 0.5, 1)  -- for 1 second
--   VehicleTuning.remove(seat, "MaxSpeed", "mud")
--
-- The seat value is always base × product(active multipliers), so overlapping
-- effects can never leave a car permanently faster or slower (the old
-- save-and-restore pattern did; see tests/specs/racing_manager.spec.luau).
-- The base is captured the first time a seat is touched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpeedModifiers = require(ReplicatedStorage.Shared.SpeedModifiers)

local VehicleTuning = {}

local PROPS = { MaxSpeed = true, TurnSpeed = true }

local _state = setmetatable({}, { __mode = "k" })   -- [seat] = { [prop] = SpeedModifiers }

local function now()
	return os.clock()
end

local function stackFor(seat, prop)
	assert(PROPS[prop], "VehicleTuning: unsupported property " .. tostring(prop))
	local st = _state[seat]
	if not st then
		st = {}
		_state[seat] = st
	end
	if not st[prop] then
		st[prop] = SpeedModifiers.new(seat[prop])
	end
	return st[prop]
end

local function apply(seat, prop)
	local st = _state[seat]
	if not st or not st[prop] or not seat.Parent then return end
	seat[prop] = st[prop]:value(now())
end

--- Adds or replaces effect `id`. With `duration`, it expires on its own.
function VehicleTuning.set(seat, prop, id, mult, duration)
	if not seat then return end
	local stack = stackFor(seat, prop)
	local expiresAt = duration and (now() + duration) or nil
	stack:set(id, mult, expiresAt)
	apply(seat, prop)
	if duration then
		task.delay(duration, function()
			apply(seat, prop)
		end)
	end
end

function VehicleTuning.remove(seat, prop, id)
	if not seat then return end
	local st = _state[seat]
	if st and st[prop] then
		st[prop]:remove(id)
		apply(seat, prop)
	end
end

function VehicleTuning.has(seat, prop, id)
	local st = seat and _state[seat]
	return st ~= nil and st[prop] ~= nil and st[prop]:has(id, now())
end

--- Removes every active multiplier below 1 (debuffs). Returns how many.
function VehicleTuning.cleanse(seat)
	local st = seat and _state[seat]
	if not st then return 0 end
	local n = 0
	for prop, stack in pairs(st) do
		for id, e in pairs(stack.effects) do
			if e.mult < 1 then
				stack:remove(id)
				n += 1
			end
		end
		apply(seat, prop)
	end
	return n
end

--- Base value (without effects).
function VehicleTuning.base(seat, prop)
	return stackFor(seat, prop).base
end

--- Changes the base (e.g. a seat rebuilt with new stats).
function VehicleTuning.setBase(seat, prop, value)
	stackFor(seat, prop).base = value
	apply(seat, prop)
end

function VehicleTuning.clear(seat)
	local st = seat and _state[seat]
	if not st then return end
	for prop, stack in pairs(st) do
		stack.effects = {}
		apply(seat, prop)
	end
	_state[seat] = nil
end

return VehicleTuning
