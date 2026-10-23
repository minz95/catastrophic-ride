-- CatchUp.lua
-- Keeps the field together without deciding the race: cars far behind the
-- leader get a little more top speed, and the time the others get after the
-- winner grows with a slow winner. Used by RacingManager and the offline
-- match simulator (tests/lib/matchsim.luau). Numbers: Constants.CATCH_UP,
-- FINISH_GRACE*.

local Constants = require(script.Parent.Constants)

local CatchUp = {}

--- MaxSpeed multiplier for a car `gap` studs behind the leader (1 = none).
function CatchUp.mult(gap)
	local C = Constants.CATCH_UP
	if not gap or gap <= C.GAP_START then return 1 end
	local t = math.clamp((gap - C.GAP_START) / (C.GAP_FULL - C.GAP_START), 0, 1)
	return 1 + C.MAX * t
end

--- Seconds the others get once the winner finished in `winnerTime` s.
function CatchUp.graceFor(winnerTime)
	local g = (winnerTime or 0) * Constants.FINISH_GRACE_SHARE
	return math.clamp(g, Constants.FINISH_GRACE, Constants.FINISH_GRACE_MAX)
end

return CatchUp
