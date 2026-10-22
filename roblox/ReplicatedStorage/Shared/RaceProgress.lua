-- RaceProgress.lua
-- Race progress (live ranking) and respawn targets, measured ALONG the track
-- centerline from Shared/Tracks/<Biome>Track. Pure: plain numbers in and out.
--
--   local s, seg = RaceProgress.progress("FOREST", x, z, lastSeg)
--   local x, y, z, yaw = RaceProgress.respawnPoint("FOREST", x, z, raceStartY, lastSeg, carY)
--
-- Pass the segment index returned last time (`lastSeg`) for each car: the
-- search then stays near it, so a car is never "teleported" to another part
-- of the track that happens to pass close by (two stretches of a track can run close by).
--
-- Biomes without track data fall back to distance along -Z.

local Constants     = require(script.Parent.Constants)
local TrackGeometry = require(script.Parent.TrackGeometry)

local RaceProgress = {}

RaceProgress.RESPAWN_STEP_BACK = 30   -- studs behind current progress
RaceProgress.RESPAWN_LIFT      = 3    -- studs above raceStartY (plus the road's rise there)
RaceProgress.SEARCH_WINDOW     = 3    -- segments either side of the hint
-- A car this far below the road under it fell off a raised stretch.
RaceProgress.FALL_BELOW        = 12

--- Road surface Y at progress s (trackTop on flat tracks).
function RaceProgress.roadY(biome, s)
	local geo = RaceProgress.geometry(biome)
	return geo and geo:heightAt(s) or nil
end

local TRACK_MODULES = {
	FOREST = "ForestTrack",
	OCEAN  = "OceanTrack",
	SKY    = "SkyTrack",
}

local _geo = {}

--- TrackGeometry for a biome, or nil when there is no track data.
function RaceProgress.geometry(biome)
	if _geo[biome] ~= nil then
		return _geo[biome] or nil
	end
	local name = TRACK_MODULES[biome]
	local folder = script.Parent:FindFirstChild("Tracks")
	local mod = name and folder and folder:FindFirstChild(name)
	if not mod then
		_geo[biome] = false
		return nil
	end
	local data = require(mod)
	_geo[biome] = TrackGeometry.new(data.nodes, data.width, data.trackTop)
	_geo[biome].trackTop = data.trackTop
	return _geo[biome]
end

--- Length used to normalise progress.
function RaceProgress.trackLength(biome)
	local geo = RaceProgress.geometry(biome)
	if geo then return geo.length end
	local track = Constants.TRACK[biome]
	return track and (track.zStart - track.zFinish) or 0
end

--- Distance travelled along the track, plus the segment for the next hint.
-- y (optional): the car's Y, so a road passing over itself is told apart.
function RaceProgress.progress(biome, x, z, hintSeg, y)
	local geo = RaceProgress.geometry(biome)
	if geo then
		return geo:progressAt(x, z, hintSeg, hintSeg and RaceProgress.SEARCH_WINDOW or nil, y)
	end
	local track = Constants.TRACK[biome]
	if not track then return 0, nil end
	return math.clamp(track.zStart - z, 0, track.zStart - track.zFinish), nil
end

--- Where a respawning vehicle goes: on the centerline RESPAWN_STEP_BACK studs
-- behind its progress, facing along the track.
-- @returns x, y, z, yaw (radians; CFrame.Angles(0, yaw, 0) faces the track)
function RaceProgress.respawnPoint(biome, x, z, raceStartY, hintSeg, carY)
	local y = (raceStartY or 2) + RaceProgress.RESPAWN_LIFT
	local geo = RaceProgress.geometry(biome)
	if geo then
		local s = RaceProgress.progress(biome, x, z, hintSeg, carY)
		local ts = math.max(s - RaceProgress.RESPAWN_STEP_BACK, 0)
		local px, pz = geo:pointAt(ts)
		-- raised road: the same height above the road as at the start
		y += geo:heightAt(ts) - (geo.trackTop or geo.baseY)
		return px, y, pz, geo:yawAt(ts)
	end
	-- Fallback (no track data): straight back along -Z at X = 0
	local track = Constants.TRACK[biome]
	local zStart = track and track.zStart or 600
	local progress = RaceProgress.progress(biome, x, z)
	local safeZ = zStart - math.max(progress - RaceProgress.RESPAWN_STEP_BACK, 0)
	return 0, y, safeZ, 0
end

return RaceProgress
