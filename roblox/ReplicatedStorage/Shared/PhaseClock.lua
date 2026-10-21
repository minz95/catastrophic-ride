-- PhaseClock.lua
-- Remaining time of the current phase as the server sees it, for client
-- timers. GameManager sets the ReplicatedStorage attribute PhaseEndsAt
-- (server time, workspace:GetServerTimeNow()) on every timed phase.
--
-- History: each UI counted its own Constants.PHASE_DURATION from the moment
-- its PhaseChanged handler ran, so a UI script that started late (character
-- respawn, slow client) never ran its timer and harness phase lengths showed
-- the wrong time (a 20 s crafting phase displayed 2:00).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseClock = {}

--- Seconds left in the phase, or `fallback` when the server sent no end time.
function PhaseClock.remaining(fallback)
	local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
	if type(endsAt) ~= "number" then return fallback end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

--- "m:ss" for `seconds`.
function PhaseClock.format(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return PhaseClock
