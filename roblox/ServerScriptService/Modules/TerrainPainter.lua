-- TerrainPainter.lua
-- Paints the decorative terrain of ONE biome (Modules/TerrainPlan) into
-- workspace.Terrain. All three maps share world coordinates, so only the
-- biome being played may have terrain: MapManager calls paint() when a round
-- picks its biome, RaceSim when it prepares a map.
--
-- History: the old MapBuilders/TerrainPainter script repainted on every map
-- model it saw. All three maps are built at server start, so whichever was
-- built last won (a FOREST race ran on OCEAN terrain), and its hills, laid
-- out for the old straight tracks, stood in the new lanes.

local ServerScriptService = game:GetService("ServerScriptService")
local TerrainPlan = require(ServerScriptService.Modules.TerrainPlan)

local TerrainPainter = {}

local _painted = nil

local function terrain()
	return workspace:FindFirstChildOfClass("Terrain")
end

--- Biome whose terrain is currently painted (nil = none).
function TerrainPainter.current()
	return _painted
end

--- Clears the terrain and paints `biome`. No-op when it is already painted,
-- unless `force`. Returns the number of fill operations.
function TerrainPainter.paint(biome, force)
	if _painted == biome and not force then return 0 end
	local t = terrain()
	if not t or not t.FillBall then
		_painted = biome
		return 0
	end
	local ops = TerrainPlan.build(biome)
	t:Clear()
	for _, op in ipairs(ops) do
		local mat = Enum.Material[op.material]
		if op.kind == "ball" then
			t:FillBall(Vector3.new(op.cx, op.cy, op.cz), op.r, mat)
		else
			t:FillBlock(CFrame.new(op.cx, op.cy, op.cz), Vector3.new(op.sx, op.sy, op.sz), mat)
		end
	end
	_painted = biome
	print(string.format("[TerrainPainter] %s terrain painted (%d fills)", biome, #ops))
	return #ops
end

return TerrainPainter
