--!nocheck
-- RaceProgress (live ranking + respawn target) checked against the FOREST track.
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local TG = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
local Track = env.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
local geo = TG.new(Track.nodes, Track.width)

local function ranges(list, step)
	-- Collapse sorted s values into "a–b" ranges.
	local out, a, prev = {}, nil, nil
	for _, s in ipairs(list) do
		if not a then
			a, prev = s, s
		elseif s - prev > step * 1.5 then
			table.insert(out, string.format("s=%d–%d", a, prev))
			a, prev = s, s
		else
			prev = s
		end
	end
	if a then table.insert(out, string.format("s=%d–%d", a, prev)) end
	return out
end

R.describe("race progress (FOREST)", function()
	R.known("progress never decreases while driving forward along the track",
		"progress is zStart - z; the figure-3 layout runs sideways and backwards in Z, so live ranks flip mid-race",
		function()
			local back = {}
			local last = -math.huge
			for s = 0, geo.length, 10 do
				local _, z = geo:pointAt(s)
				local p = RaceProgress.progress("FOREST", z)
				if p < last - 0.5 then table.insert(back, s) end
				last = math.max(last, p)
			end
			R.expect(ranges(back, 10)).toBeEmpty("stretches where progress goes backwards")
		end)

	R.known("the respawn target is on the track everywhere",
		"respawn always teleports to X = 0; wherever the track is not at X = 0 the car lands on grass outside the walls",
		function()
			local off = {}
			for s = 0, geo.length, 10 do
				local x, z = geo:pointAt(s)
				local rx, _, rz = RaceProgress.respawnPoint("FOREST", z, BiomeConfig.FOREST.raceStartY)
				local p = geo:project(rx, rz)
				if p.dist > Track.width / 2 - 2 then table.insert(off, s) end
			end
			R.expect(ranges(off, 10)).toBeEmpty("track positions whose respawn lands off the track")
		end)

	R.it("progress is clamped to [0, track length]", function()
		R.expect(RaceProgress.progress("FOREST", 5000)).toBe(0)
		R.expect(RaceProgress.progress("FOREST", -9999)).toBe(2600)
	end)
end)
