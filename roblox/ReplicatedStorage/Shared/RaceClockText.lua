-- RaceClockText.lua
-- The race clock's line (HUD, under the top bar once the winner is in).
-- Playtest 2026-11-15: a player who had finished saw only "TIME LEFT" and
-- could not tell why the race went on. Finished, it says so and how many
-- racers (players and bots) are still driving.
local PhaseClock = require(script.Parent.PhaseClock)

local RaceClockText = {}

--- `place`: the local player's finish place, nil while driving; `left`:
-- racers still driving (ReplicatedStorage "RacersLeft"); `seconds` left.
function RaceClockText.text(place, left, seconds)
	local clock = PhaseClock.format(seconds)
	if not place then return "🏁 TIME LEFT " .. clock end
	if left and left > 0 then
		return string.format("🏁 FINISHED #%d · %d still racing · %s", place, left, clock)
	end
	return string.format("🏁 FINISHED #%d · results in %s", place, clock)
end

return RaceClockText
