--!nocheck
-- drift_sim.luau
-- Offline check of drifting: the same car and driver around a track with and
-- without drifting (tests/lib/kinesim, the real VehicleController and
-- Autopilot), per section. Shows where drifting wins time.
--
--   lune run tools/drift_sim.luau [FOREST|OCEAN] [profile]
--
-- "drifts at s": each drift as start-end progress (studs), T1 / T2 = the
-- mini / super turbo it paid on release.

local process = require("@lune/process")
local World = require("../tests/lib/world")
local KineSim = require("../tests/lib/kinesim")
local Builds = require("../tests/lib/builds")

local biome = (process.args[1] or "FOREST"):upper()
local profiles = process.args[2] and { process.args[2] } or { "expert", "average" }

local world = World.build(biome, { visibility = "intended" })
local env = world.env
local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local reps = Builds.representative(Builds.enumerate(env, biome))

local function fmt(n) return n and string.format("%.1f", n) or "DNF" end

for _, rep in ipairs(reps) do
	if rep.label == "slowest" or rep.label == "p50" or rep.label == "fastest" then
		local car = KineSim.carFromStats(rep.build.stats, Constants, biome)
		for _, prof in ipairs(profiles) do
			local runs = {}
			for _, nd in ipairs({ true, false }) do
				runs[nd and "grip" or "drift"] = KineSim.run(world, {
					car = car, profile = Autopilot.PROFILES[prof], profileName = prof,
					seed = 1, respawn = "track", noDrift = nd,
				})
			end
			local g, d = runs.grip, runs.drift
			print(string.format("%s %-4s %-7s grip %6s s  drift %6s s  (%d drifts, %d turbos, %.0f s sliding, respawns %d/%d, walls %d/%d)",
				biome, rep.label, prof, fmt(g.time), fmt(d.time), d.drifts, d.turbos, d.driftSeconds,
				#g.respawns, #d.respawns, #g.impacts, #d.impacts))
			-- where the drifts were (s along the track) and which paid a turbo
			local marks = {}
			for _, e in ipairs(d.driftLog or {}) do
				table.insert(marks, string.format("%d-%d%s", e.s0, e.s1 or -1, e.level and ("T" .. e.level) or ""))
			end
			print("    drifts at s: " .. table.concat(marks, " "))
			for i, sec in ipairs(d.sections) do
				local gs = g.sections[i]
				if gs and gs.exit and sec.exit then
					local gt, dtm = gs.exit - gs.enter, sec.exit - sec.enter
					print(string.format("    %-28s grip %5.1f  drift %5.1f  %+5.1f", sec.name, gt, dtm, dtm - gt))
				end
			end
		end
	end
end
