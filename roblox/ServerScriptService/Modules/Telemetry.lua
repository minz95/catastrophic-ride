-- Telemetry.lua
-- Structured, bounded event log for the server. Game systems call
-- Telemetry.record(kind, fields); the test harness reads snapshot() and
-- ships it back as JSON so an AI (or a person) can analyse a match.
--
-- Cheap by design: one table insert per event, a fixed-size ring buffer, and
-- high-frequency samples (vehicle positions) only when `detailed` is on.
--
-- Event kinds currently emitted
--   phase            GameManager            { phase, biome, round }
--   item_pickup      FarmingManager         { userId, item, rarity, result }
--   contest_result   FarmingManager         { itemId, winner, loser, presses }
--   steal            FarmingManager         { thief, victim, item }
--   craft            CraftingManager        { userId, slots, stats, auto }
--   race_start       RacingManager          { racers = { userId, maxSpeed, turnSpeed, mass } }
--   race_sample      RacingManager          { userId, x, y, z, speed, maxSpeed, progress }  (detailed only)
--   speed_effect     RacingManager          { userId, effect, phase = "enter"|"exit"|"restore", before, after }
--   respawn          RacingManager          { userId, reason, from = {x,y,z}, to = {x,y,z} }
--   checkpoint       CheckpointService      { userId, index }
--   finish           RacingManager          { userId, time, place }
--   ability          AbilityManager         { userId, item, result }

local Telemetry = {}

Telemetry.CAPACITY = 20000

local _events   = table.create and table.create(64) or {}
local _head     = 0      -- index of the most recent event
local _count    = 0
local _dropped  = 0
local _t0       = os.clock()
local _meta     = {}

Telemetry.detailed = false

local function now()
	return os.clock() - _t0
end

--- Clears the log and starts a new session clock.
function Telemetry.reset(meta)
	_events  = {}
	_head    = 0
	_count   = 0
	_dropped = 0
	_t0      = os.clock()
	_meta    = meta or {}
end

function Telemetry.setDetailed(on)
	Telemetry.detailed = on and true or false
end

function Telemetry.record(kind, fields)
	local e = fields or {}
	e.kind = kind
	e.t    = math.floor(now() * 1000) / 1000
	_head = (_head % Telemetry.CAPACITY) + 1
	if _count == Telemetry.CAPACITY then
		_dropped += 1
	else
		_count += 1
	end
	_events[_head] = e
	return e
end

--- Records only when detailed sampling is on (positions, per-tick values).
function Telemetry.sample(kind, fields)
	if Telemetry.detailed then
		return Telemetry.record(kind, fields)
	end
	return nil
end

--- Events in chronological order, optionally filtered by kind.
function Telemetry.events(kind)
	local out = {}
	local start = (_count < Telemetry.CAPACITY) and 1 or (_head % Telemetry.CAPACITY) + 1
	for i = 0, _count - 1 do
		local idx = ((start - 1 + i) % Telemetry.CAPACITY) + 1
		local e = _events[idx]
		if e and (kind == nil or e.kind == kind) then
			table.insert(out, e)
		end
	end
	return out
end

function Telemetry.snapshot()
	return {
		meta    = _meta,
		events  = Telemetry.events(),
		dropped = _dropped,
		count   = _count,
	}
end

--- Rounds a Vector3 into a small JSON-friendly table.
function Telemetry.vec(v)
	if not v then return nil end
	return {
		x = math.floor(v.X * 10 + 0.5) / 10,
		y = math.floor(v.Y * 10 + 0.5) / 10,
		z = math.floor(v.Z * 10 + 0.5) / 10,
	}
end

return Telemetry
