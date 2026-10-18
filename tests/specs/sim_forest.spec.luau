--!nocheck
-- Kinematic race simulation on the FOREST map (see tests/lib/kinesim.luau for
-- what is and is not modelled).
local R = require("../lib/runner")
local World = require("../lib/world")
local KineSim = require("../lib/kinesim")
local Builds = require("../lib/builds")

local intended = World.forest({ visibility = "intended" })
local shipped = World.forest({ visibility = "shipped" })
local Autopilot = intended.env.requirePath("ReplicatedStorage.Shared.Autopilot")

local reps = Builds.representative(Builds.enumerate(intended.env, "FOREST"))
local p50 = KineSim.carFromStats(reps[2].build.stats, intended.env.requirePath("ReplicatedStorage.Shared.Constants"))

local function run(world, profile, seed, respawn, car)
	return KineSim.run(world, {
		car = car or p50, profile = Autopilot.PROFILES[profile], profileName = profile,
		seed = seed or 1, respawn = respawn or "track",
	})
end

R.describe("race sim (FOREST, median car)", function()
	R.it("is deterministic for a given seed", function()
		local a = run(intended, "average", 7)
		local b = run(intended, "average", 7)
		R.expect(a.endT).toBe(b.endT)
		R.expect(a.maxProgress).toBe(b.maxProgress)
		R.expect(#a.impacts).toBe(#b.impacts)
	end)

	R.it("an expert driver reaches both checkpoints on the authored map", function()
		local r = run(intended, "expert", 1)
		R.expect(#r.checkpoints).toBe(2)
	end)

	R.it("an average driver finishes inside the race timeout on the authored map",
		function()
			local unfinished = {}
			for seed = 1, 3 do
				local r = run(intended, "average", seed)
				if not r.finished then
					table.insert(unfinished, string.format("seed %d: stopped at s=%d/%d after %d respawns", seed, r.maxProgress, r.trackLength, #r.respawns))
				end
			end
			R.expect(unfinished).toBeEmpty("runs that did not finish in 180 s")
		end)

	R.it("every driver profile finishes on the map as the live server shows it", function()
		local unfinished = {}
		for _, profile in ipairs({ "expert", "average", "novice" }) do
			local r = run(shipped, profile, 1, "track")
			if not r.finished then
				table.insert(unfinished, string.format("%s: stopped at s=%d after %d respawns", profile, r.maxProgress, #r.respawns))
			end
		end
		R.expect(unfinished).toBeEmpty("runs that did not finish")
	end)

	R.it("a faster car beats a slower car with the same driver", function()
		local Constants = intended.env.requirePath("ReplicatedStorage.Shared.Constants")
		local slow = run(intended, "expert", 1, "track", KineSim.carFromStats(reps[1].build.stats, Constants))
		local fast = run(intended, "expert", 1, "track", KineSim.carFromStats(reps[3].build.stats, Constants))
		R.expect(slow.finished and fast.finished).toBe(true)
		R.expect(fast.time).toBeLessThan(slow.time)
	end)
end)
