-- RaceGrid.lua
-- The race start grid: MAX_PLAYERS slots, 2 rows of 5, pointing down -Z.
-- Players take the first entries (CraftingManager), bots the next ones
-- (Modules/RaceBots). The entries are the slots in a new order every round
-- (the same for both callers within a round): players always took the
-- front-left slots and bots the rest, the second row 8 studs back from six
-- racers on, and the player won nearly every bot race (Studio bots-*,
-- 2026-10-30).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local BiomeConfig = require(ServerScriptService.Modules.BiomeConfig)

local RaceGrid = {}

function RaceGrid.cframes(biome)
	local cfg  = biome and BiomeConfig[biome]
	local startZ = (cfg and cfg.raceStartZ) or 195
	local startY = (cfg and cfg.raceStartY) or 2

	-- 2 rows of 5, staggered 8 studs apart, pointing down-Z (race direction)
	local slots = {}
	for i = 1, Constants.MAX_PLAYERS do
		local row = math.ceil(i / 5)
		local col = ((i - 1) % 5) + 1
		local x   = (col - 3) * 7
		local z   = startZ + (row - 1) * 8  -- row 1 at startZ, row 2 slightly behind
		table.insert(slots, CFrame.new(x, startY, z))
	end
	local grid = {}
	for k, i in ipairs(RaceGrid.order(RaceGrid.round())) do grid[k] = slots[i] end
	return grid
end

-- This server's draws: one shuffle per round.
local _seed = Random.new():NextInteger(1, 2 ^ 30)
local _orders = {}

--- The round number (GameManager), 0 before the first.
function RaceGrid.round()
	local ok, GameManager = pcall(function() return require(ServerScriptService.GameManager) end)
	local r = ok and GameManager and GameManager.getRound and GameManager.getRound()
	return type(r) == "number" and r or 0
end

--- Slot numbers 1..MAX_PLAYERS in round `round`'s order.
function RaceGrid.order(round)
	local o = _orders[round]
	if not o then
		o = {}
		for i = 1, Constants.MAX_PLAYERS do o[i] = i end
		local rng = Random.new(_seed + round * 7919)
		for i = #o, 2, -1 do
			local j = rng:NextInteger(1, i)
			o[i], o[j] = o[j], o[i]
		end
		_orders = { [round] = o }   -- only the current round is kept
	end
	return o
end

return RaceGrid
