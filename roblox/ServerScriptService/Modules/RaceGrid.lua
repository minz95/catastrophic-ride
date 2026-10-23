-- RaceGrid.lua
-- The race start grid: MAX_PLAYERS slots, 2 rows of 5, pointing down -Z.
-- Players take the first slots (CraftingManager), bots the next ones
-- (Modules/RaceBots).

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
	local grid = {}
	for i = 1, Constants.MAX_PLAYERS do
		local row = math.ceil(i / 5)
		local col = ((i - 1) % 5) + 1
		local x   = (col - 3) * 7
		local z   = startZ + (row - 1) * 8  -- row 1 at startZ, row 2 slightly behind
		table.insert(grid, CFrame.new(x, startY, z))
	end
	return grid
end

return RaceGrid
