--!nocheck
-- Roads with heights: a node may carry the road surface Y ({ x, z, y }).
-- FOREST climbs a trestle (S3) and winds down 1½ turns around the giant tree
-- (S4), passing 26 studs over itself. Everything that finds "where on the
-- track is this car" must tell the layers apart.
local R = require("../lib/runner")
local World = require("../lib/world")
local Loader = require("../lib/loader")
local KineSim = require("../lib/kinesim")
local Builds = require("../lib/builds")

local env = Loader.boot()
local TrackGeometry = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local Forest = env.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")

-- a square loop that passes over its own start 30 studs higher
local function loop()
	return TrackGeometry.new({
		{ 0, 0, 0 }, { 100, 0, 10 }, { 100, 100, 20 }, { 0, 100, 25 }, { 0, -20, 30 }, { 0, -100, 30 },
	}, 20, 0)
end

R.describe("TrackGeometry with heights", function()
	R.it("interpolates the road height along the track", function()
		local g = loop()
		R.expect(g.hasHeights).toBe(true)
		R.expect(g:heightAt(0)).toBe(0)
		R.expect(g:heightAt(50)).toBeNear(5, 1e-6)
		R.expect(g:heightAt(g.length)).toBe(30)
		local flat = TrackGeometry.new({ { 0, 0 }, { 0, 100 } }, 20, 1)
		R.expect(flat.hasHeights).toBe(false)
		R.expect(flat:heightAt(40)).toBe(1)
	end)

	R.it("a point where the road passes over itself belongs to the layer at the car's height", function()
		local g = loop()
		-- (0, -5): on the first segment near its start (Y 0) and under the
		-- last stretch (Y ~29)
		local low = g:project(0, -5, nil, nil, 1)
		local high = g:project(0, -5, nil, nil, 30)
		R.expect(low.seg).toBe(1)
		R.expect(high.seg).toBeGreaterThan(3)
		local sLow = g:progressAt(5, 0, nil, nil, 1)
		local sHigh = g:progressAt(0, 5, nil, nil, 29)
		R.expect(sLow).toBeLessThan(10)
		R.expect(sHigh).toBeGreaterThan(300)
	end)

	R.it("walls of one layer are not dropped for standing in the lane of another", function()
		local g = loop()
		-- last stretch runs over (0, 0): its walls at x = ±11 cross the first
		-- segment's lane 30 studs below, and must still stand
		local runs = g:boundaryRuns(5, 1, 11, 12)
		local total = 0
		for _, r in ipairs(runs) do total += r[2] - r[1] end
		R.expect(total).toBeGreaterThan(g.segments[5].len - 1)
	end)
end)

R.describe("FOREST raised road and giant tree spiral", function()
	local geo = RaceProgress.geometry("FOREST")

	R.it("climbs to the treetops and comes back down to the ground", function()
		local top = 0
		for _, n in ipairs(Forest.nodes) do top = math.max(top, n[3] or Forest.trackTop) end
		R.expect(top).toBeGreaterThan(35)
		R.expect(geo:heightAt(0)).toBe(Forest.trackTop)
		R.expect(geo:heightAt(geo.length)).toBe(Forest.trackTop)
	end)

	R.it("no grade steeper than 6% and no grade change sharper than 6% at a node", function()
		local bad = {}
		for i, seg in ipairs(geo.segments) do
			local gr = geo:grade(i)
			if math.abs(gr) > 0.06 then table.insert(bad, string.format("segment %d: %.1f%%", i, gr * 100)) end
			if i > 1 and math.abs(gr - geo:grade(i - 1)) > 0.06 then
				table.insert(bad, string.format("N%d: grade changes by %.1f%%", i, (gr - geo:grade(i - 1)) * 100))
			end
		end
		R.expect(bad).toBeEmpty("too steep")
	end)

	R.it("where the road passes over itself there is room for a car and the camera (24 studs)", function()
		local half = Forest.width / 2
		local worst = math.huge
		local passes = 0
		for s = 0, geo.length, 5 do
			local x, z = geo:pointAt(s)
			local y = geo:heightAt(s)
			for s2 = s + 4 * Forest.width, geo.length, 5 do
				local x2, z2 = geo:pointAt(s2)
				-- lanes overlapping by 6 studs or more (one passes over the other)
				if math.abs(x - x2) < half * 2 and math.abs(z - z2) < half * 2
					and math.sqrt((x - x2) ^ 2 + (z - z2) ^ 2) < half * 2 - 6 then
					passes += 1
					worst = math.min(worst, math.abs(geo:heightAt(s2) - y))
				end
			end
		end
		R.expect(passes).toBeGreaterThan(0)
		R.expect(worst).toBeGreaterThan(24)
	end)

	R.it("respawn on the trestle and in the spiral puts the car back on its own layer", function()
		local raceStartY = 2
		-- S3 trestle
		local _, y = RaceProgress.respawnPoint("FOREST", 460, -640, raceStartY, nil, 24)
		R.expect(y).toBeGreaterThan(20)
		-- (-195, -842): the spiral's top turn (Y ~38) above its last turn (Y ~12)
		local _, yTop = RaceProgress.respawnPoint("FOREST", -195, -842, raceStartY, nil, 39)
		local _, yLow = RaceProgress.respawnPoint("FOREST", -195, -842, raceStartY, nil, 13)
		R.expect(yTop - yLow).toBeGreaterThan(20)
	end)

	R.it("falling logs land on the road at its height, never under a higher turn of the spiral", function()
		local HazardPlan = env.requirePath("ReplicatedStorage.Shared.HazardPlan")
		local keep = HazardPlan.keepClear(geo, Forest)
		local st = 99
		local function rnd()
			st = (st * 1103515245 + 12345) % 2147483648
			return st / 2147483648
		end
		local bad, raised = {}, 0
		for k = 1, 400 do
			local lead = (k * 37) % math.floor(geo.length - 200)
			for _, sp in ipairs(HazardPlan.logSpots(geo, Forest.width, lead, 3, rnd, keep)) do
				if math.abs(sp.y - geo:heightAt(sp.s)) > 1e-6 then table.insert(bad, "wrong height at s=" .. math.floor(sp.s)) end
				if geo:coveredAt(sp.x, sp.z, sp.y, 0) then table.insert(bad, "under a deck at s=" .. math.floor(sp.s)) end
				if sp.y > Forest.trackTop + 3 then raised += 1 end
			end
		end
		R.expect(bad).toBeEmpty("bad log spots")
		R.expect(raised).toBeGreaterThan(0)   -- the raised road gets logs too
	end)

	R.it("a simulated driver goes down the spiral turn by turn (progress never jumps a layer)", function()
		local w = World.build("FOREST", { visibility = "shipped" })
		local Autopilot = w.env.requirePath("ReplicatedStorage.Shared.Autopilot")
		local Constants = w.env.requirePath("ReplicatedStorage.Shared.Constants")
		local reps = Builds.representative(Builds.enumerate(w.env, "FOREST"))
		local r = KineSim.run(w, {
			car = KineSim.carFromStats(reps[2].build.stats, Constants, "FOREST"),
			profile = Autopilot.PROFILES.average, profileName = "average", seed = 2, respawn = "track",
		})
		R.expect(r.finished).toBe(true)
		local jumps = {}
		for i = 2, #r.samples do
			local d = r.samples[i].s - r.samples[i - 1].s
			if d > 60 or d < -20 then table.insert(jumps, string.format("t=%.1f s %d → %d", r.samples[i].t, r.samples[i - 1].s, r.samples[i].s)) end
		end
		R.expect(jumps).toBeEmpty("progress jumps")
	end)
end)

R.describe("OCEAN lighthouse spiral and water slide", function()
	local geo = RaceProgress.geometry("OCEAN")
	local Ocean = env.requirePath("ReplicatedStorage.Shared.Tracks.OceanTrack")

	-- (boats hold a height above the water instead of climbing a slope, so a
	-- slide may be steeper than a road: 8%)
	R.it("climbs from the sea and slides back down to it, no grade over 8%", function()
		local top, bad = 0, {}
		for _, n in ipairs(Ocean.nodes) do top = math.max(top, n[3] or Ocean.trackTop) end
		R.expect(top).toBeGreaterThan(30)
		R.expect(geo:heightAt(0)).toBe(Ocean.trackTop)
		R.expect(geo:heightAt(geo.length)).toBe(Ocean.trackTop)
		for i = 1, #geo.segments do
			if math.abs(geo:grade(i)) > 0.08 then table.insert(bad, string.format("segment %d: %.1f%%", i, geo:grade(i) * 100)) end
		end
		R.expect(bad).toBeEmpty("too steep")
	end)

	R.it("where the flume passes over itself there are 24+ studs", function()
		local half, worst, passes = Ocean.width / 2, math.huge, 0
		for s = 0, geo.length, 5 do
			local x, z = geo:pointAt(s)
			for s2 = s + 4 * Ocean.width, geo.length, 5 do
				local x2, z2 = geo:pointAt(s2)
				if math.abs(x - x2) < half * 2 and math.abs(z - z2) < half * 2
					and math.sqrt((x - x2) ^ 2 + (z - z2) ^ 2) < half * 2 - 6 then
					passes += 1
					worst = math.min(worst, math.abs(geo:heightAt(s2) - geo:heightAt(s)))
				end
			end
		end
		R.expect(passes).toBeGreaterThan(0)
		R.expect(worst).toBeGreaterThan(24)
	end)

	R.it("a simulated boat goes up the spiral and down the slide without jumping a layer", function()
		local w = World.build("OCEAN", { visibility = "shipped" })
		local Autopilot = w.env.requirePath("ReplicatedStorage.Shared.Autopilot")
		local Constants = w.env.requirePath("ReplicatedStorage.Shared.Constants")
		local reps = Builds.representative(Builds.enumerate(w.env, "OCEAN"))
		local r = KineSim.run(w, {
			car = KineSim.carFromStats(reps[2].build.stats, Constants, "OCEAN"),
			profile = Autopilot.PROFILES.average, profileName = "average", seed = 2, respawn = "track",
		})
		R.expect(r.finished).toBe(true)
		R.expect(#r.respawns).toBe(0)
		local jumps = {}
		for i = 2, #r.samples do
			local d = r.samples[i].s - r.samples[i - 1].s
			if d > 60 or d < -20 then table.insert(jumps, string.format("t=%.1f", r.samples[i].t)) end
		end
		R.expect(jumps).toBeEmpty("progress jumps")
	end)
end)
