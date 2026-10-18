--!nocheck
-- world.luau
-- Builds a biome map in the mock engine and prepares it for checks/sims.
--
--   local World = require("./world")
--   local w = World.forest({ visibility = "shipped" | "intended" })
--   w.env, w.map, w.track (data), w.geo (TrackGeometry), w.obstacles, w.triggers

local Loader = require("./loader")
local MapQuery = require("./mapquery")
local Mock = require("./mock")

local World = {}

--- visibility:
--   "shipped"  – MapVisibility.applyRacingState exactly as the live server runs it
--   "intended" – every part restored to its authored CanCollide/Transparency
--   "raw"      – as built, no visibility pass
function World.forest(opts)
	opts = opts or {}
	local visibility = opts.visibility or "shipped"
	local env = Loader.boot()
	local ForestMap = env.requirePath("ServerScriptService.Modules.Maps.ForestMap")
	local map = ForestMap.build()
	local mapsFolder = env.workspace.Maps

	local MapVisibility = env.requirePath("ServerScriptService.Modules.MapVisibility")
	MapVisibility.cacheOriginals(mapsFolder)
	if visibility == "shipped" then
		MapVisibility.applyRacingState(mapsFolder, map)
	elseif visibility == "intended" then
		MapVisibility.applyRacingState(mapsFolder, map)
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") then
				local cc = d:GetAttribute("OriginalCanCollide")
				local tr = d:GetAttribute("OriginalTransparency")
				if cc ~= nil then d.CanCollide = cc end
				if tr ~= nil then d.Transparency = tr end
			end
		end
		-- FarmArea stays hidden during RACING
		MapVisibility.setSubVisible(map, "FarmArea", false)
	end

	local track = env.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
	local TrackGeometry = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
	local geo = TrackGeometry.new(track.nodes, track.width)

	local w = {
		env = env,
		map = map,
		track = track,
		geo = geo,
		biome = "FOREST",
		visibility = visibility,
	}
	w.obstacles = MapQuery.obstacles(map, track.trackTop)
	w.obstacleGrid = MapQuery.grid(w.obstacles, 32)
	w.triggers = MapQuery.shapes(map, function(sh)
		return (MapQuery.isTrigger(sh))
	end)
	w.allShapes = MapQuery.shapes(map)
	return w
end

return World
