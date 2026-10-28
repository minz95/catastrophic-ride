-- FarmKit.lua
-- What every farm shares: the invisible walls round it (Shared/FarmBounds).
-- They sit in the map's FarmArea model, so MapVisibility drops them with the
-- farm for RACING (Transparency 1 / CanCollide false) and puts them back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FarmBounds = require(ReplicatedStorage.Shared.FarmBounds)

local FarmKit = {}

--- Invisible, solid walls closing `biome`'s farm, parented to `root`.
function FarmKit.buildWalls(root, biome)
	local out = {}
	for _, w in ipairs(FarmBounds.walls(biome)) do
		local p = Instance.new("Part")
		p.Name = w.name
		p.Size = w.size
		p.Position = w.position
		p.Anchored = true
		p.CanCollide = true
		p.Transparency = 1
		p.CastShadow = false
		p.CanTouch = false
		p:SetAttribute("FarmWall", true)
		p.Parent = root
		table.insert(out, p)
	end
	return out
end

return FarmKit
