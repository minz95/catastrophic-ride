-- BoostGauge.lua
-- The boost gauge (F), kept by the server for every racer, players and race
-- bots alike. It starts full, DriftCorner zones fill it
-- (Constants.DRIFT_CHARGE_PER_CORNER, each zone once per
-- DRIFT_CORNER_COOLDOWN s per car), the Backpack ability refills it, and a
-- boost needs it full and empties it.
-- History (2026-10-26): only the client kept the gauge; the server granted a
-- boost on cooldown alone. The harness bot client (and any exploiter) called
-- RequestBoost directly and boosted every 5 s, and server race bots never
-- boosted at all: in every Studio match the harness player won.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local BoostGauge = {}

local _level = {}    -- [userId] = 0..1
local _corners = {}  -- [userId] = { [part] = tick when it charges again }

--- A new race: every gauge goes; racers start full with `start`.
function BoostGauge.reset()
	_level, _corners = {}, {}
end

function BoostGauge.start(id)
	_level[id] = 1
	_corners[id] = {}
end

function BoostGauge.get(id)
	return _level[id] or 0
end

function BoostGauge.ready(id)
	return (_level[id] or 0) >= 1
end

function BoostGauge.fill(id)
	_level[id] = 1
end

--- A car went through a DriftCorner zone at `now`: charges the gauge
-- unless this car charged on this zone in the last cooldown. Returns the
-- amount charged, or nil.
function BoostGauge.corner(id, part, now)
	_corners[id] = _corners[id] or {}
	local cds = _corners[id]
	if cds[part] and now < cds[part] then return nil end
	cds[part] = now + Constants.DRIFT_CORNER_COOLDOWN
	local amount = Constants.DRIFT_CHARGE_PER_CORNER
	_level[id] = math.min(1, (_level[id] or 0) + amount)
	return amount
end

--- Empties a full gauge for a boost. False (and nothing changes) when it is
-- not full.
function BoostGauge.spend(id)
	if (_level[id] or 0) < 1 then return false end
	_level[id] = 0
	return true
end

return BoostGauge
