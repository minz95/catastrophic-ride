-- Places.lua
-- The game's places (2026-11-17, phase 2 of the lobby: "a lobby place, a
-- group on a start pad goes to a new server together"). Roblox keeps the
-- universe's start place fixed, so the published place (HUB) becomes Junk
-- Town for everyone and the rounds run in a second place (RACE), the same
-- Rojo build published to both. RACE = 0: one place, rounds and lobby in
-- the same server, as before.
--
-- Modes (ReplicatedStorage attribute "PlaceMode"):
--   "single"  RACE is 0: the lobby counts down and rounds follow (as before)
--   "hub"     Junk Town only, no rounds; start pads send groups to RACE
--             (Modules/PlaceTeleport, DepartureManager)
--   "race"    rounds as before, between them a 🏠 button back to the hub
-- Studio and harness sessions play rounds ("single" or "race"): teleports
-- do not work there. The workspace attribute HubTest shows the hub in a
-- Studio playtest.

local Places = {}

Places.HUB = 74883519312765   -- the start place (Creator Dashboard)
Places.RACE = 0               -- the race place's id once it exists; 0 = one place

--- The mode of a server in place `placeId`.
-- `studio`: a Studio session; `hubTest`: workspace attribute HubTest;
-- `harness`: a test harness runs (always rounds).
function Places.mode(placeId, studio, hubTest, harness)
	if (Places.RACE or 0) == 0 then return "single" end
	if placeId == Places.RACE then return "race" end
	if harness then return "race" end
	if studio and not hubTest then return "race" end
	return "hub"
end

return Places
