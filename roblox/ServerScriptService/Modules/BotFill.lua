-- BotFill.lua
-- How many take part in a round on a live server: a number drawn each
-- round between Constants.BOTS.FILL.MIN and MAX (players + bots); bots
-- make up whatever the players do not. FarmingManager draws it when
-- FARMING starts; FarmBots and RaceBots both read the same draw, so the
-- bots that farmed are the ones that race.
-- History (2026-10-30, "why the same count every time?"): a fixed FILL_TO
-- of 4 gave a lone player exactly three bots every round.
-- Harness sessions keep `fillBots` (exact; none without it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local BotFill = {}

BotFill.current = nil   -- this round's draw (players + bots)
local _rng = Random.new()

--- Draws this round's number of participants. `rng` for specs.
function BotFill.roll(rng)
	local F = Constants.BOTS.FILL
	BotFill.current = (rng or _rng):NextInteger(F.MIN, F.MAX)
	return BotFill.current
end

--- This round's number (drawn now if no round drew one yet).
function BotFill.target()
	return BotFill.current or BotFill.roll()
end

--- Bots to add for `humans` players. harness: args (fillBots) or nil.
function BotFill.wanted(humans, harness)
	local fillTo
	if harness then
		fillTo = harness.fillBots
		if type(fillTo) ~= "number" then return 0 end
	else
		fillTo = BotFill.target()
	end
	return math.max(0, math.min(fillTo, Constants.MAX_PLAYERS) - humans)
end

return BotFill
