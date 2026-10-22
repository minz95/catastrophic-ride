--!nocheck
-- world.luau
-- Builds a biome map in the mock engine and prepares it for checks/sims.
--
--   local World = require("./world")
--   local w = World.build("OCEAN", { visibility = "shipped" | "intended" })
--   local w = World.forest(opts)   -- same as World.build("FOREST", opts)
--   w.env, w.map, w.track (data), w.geo (TrackGeometry), w.obstacles, w.triggers

local Loader = require("./loader")
local MapQuery = require("./mapquery")
local Mock = require("./mock")

local World = {}

--- visibility:
--   "shipped"  – MapVisibility.applyRacingState exactly as the live server runs it
--   "intended" – every part restored to its authored CanCollide/Transparency
--   "raw"      – as built, no visibility pass
World.BIOMES = {
	FOREST = { builder = "ForestMap", track = "ForestTrack" },
	OCEAN  = { builder = "OceanMap",  track = "OceanTrack" },
	SKY    = { builder = "SkyMap",    track = "SkyTrack" },
}

function World.build(biome, opts)
	opts = opts or {}
	local spec = assert(World.BIOMES[biome], "unknown biome " .. tostring(biome))
	local visibility = opts.visibility or "shipped"
	local env = Loader.boot()
	local Builder = env.requirePath("ServerScriptService.Modules.Maps." .. spec.builder)
	local map = Builder.build()
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

	local track = env.requirePath("ReplicatedStorage.Shared.Tracks." .. spec.track)
	local TrackGeometry = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
	local geo = TrackGeometry.new(track.nodes, track.width, track.trackTop)

	local w = {
		env = env,
		map = map,
		track = track,
		geo = geo,
		biome = biome,
		visibility = visibility,
	}
	local topHi = track.trackTop
	for _, nd in ipairs(track.nodes) do topHi = math.max(topHi, nd[3] or track.trackTop) end
	w.band = track.obstacleBand or { 0.6, 3.0 }
	w.obstacles = MapQuery.obstacles(map, track.trackTop, track.obstacleBand, topHi)
	w.obstacleGrid = MapQuery.grid(w.obstacles, 32)
	w.triggers = MapQuery.shapes(map, function(sh)
		return (MapQuery.isTrigger(sh))
	end)
	w.allShapes = MapQuery.shapes(map)
	return w
end

function World.forest(opts)
	return World.build("FOREST", opts)
end

function World.ocean(opts)
	return World.build("OCEAN", opts)
end

function World.sky(opts)
	return World.build("SKY", opts)
end

return World
