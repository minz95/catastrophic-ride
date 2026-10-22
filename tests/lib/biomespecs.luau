--!nocheck
-- biomespecs.luau
-- The map and race-sim checks every biome gets. A spec file is one call:
--
--   require("../lib/biomespecs").map("OCEAN", { isWall = ..., wallOffset = 31.5, doorway = 8 })
--   require("../lib/biomespecs").sim("OCEAN")
--
-- (FOREST keeps its own map_forest / sim_forest specs, which came first; they
-- check the same things.)

local R = require("./runner")
local World = require("./world")
local Loader = require("./loader")
local MapChecks = require("./mapchecks")
local KineSim = require("./kinesim")
local Builds = require("./builds")

local BiomeSpecs = {}

--- cfg:
--   isWall(name)   which collidable parts are the side walls
--   wallOffset     distance of the wall line from the centerline
--   doorway        widest intended opening in the wall (studs)
--   isFloor(name)  optional: parts that carry the lane surface (checked for holes)
--   props          optional: names (Lua patterns) of decoration that must stay off the lane
function BiomeSpecs.map(biome, cfg)
	local shipped = World.build(biome, { visibility = "shipped" })
	local intended = World.build(biome, { visibility = "intended" })
	local BiomeConfig = intended.env.requirePath("ServerScriptService.Modules.BiomeConfig")
	local bc = BiomeConfig[biome]

	R.describe(biome .. " map build", function()
		R.it("has the expected tagged parts", function()
			R.expect(MapChecks.tagCounts(intended, {
				Checkpoint1 = 1, Checkpoint2 = 1, FinishLine = 1,
				BoostPad = bc.boostPads, DriftCorner = bc.driftCorners, JumpZone = bc.jumpRamps,
			})).toBeEmpty("tag counts")
		end)

		R.it("start grid slots sit inside the corridor", function()
			R.expect(MapChecks.startGrid(intended)).toBeEmpty("grid slots outside the lane")
		end)
	end)

	R.describe(biome .. " map during RACING", function()
		R.it("trigger volumes stay non-collidable when the track is shown", function()
			R.expect(MapChecks.solidTriggers(shipped)).toBeEmpty("solid trigger volumes")
		end)

		R.it("nothing but the side walls blocks the lane", function()
			R.expect(MapChecks.laneObstacles(intended, cfg.isWall)).toBeEmpty("non-wall obstacles inside the lane")
		end)

		R.it("the track never crosses or touches itself (no forks, no open fence)", function()
			-- two stretches far apart along the track must not share lane:
			-- a crossing looks like a fork and leaves the fence open
			local geo, w = intended.geo, intended.track.width
			-- (a road may pass OVER itself, a spiral or an overpass: two layers
			-- at least 2 × LAYER_GAP apart in height never meet)
			local pts = {}
			for s = 0, geo.length, 10 do
				local x, z = geo:pointAt(s)
				table.insert(pts, { s, x, z, geo:heightAt(s) })
			end
			local gap = 2 * intended.env.requirePath("ReplicatedStorage.Shared.TrackGeometry").LAYER_GAP
			local bad = {}
			for i = 1, #pts do
				for j = i + 1, #pts do
					local a, b = pts[i], pts[j]
					if b[1] - a[1] > 4 * w and math.abs(a[4] - b[4]) < gap
						and math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2) < w + 4 then
						table.insert(bad, string.format("s=%d (%d,%d) meets s=%d", a[1], a[2], a[3], b[1]))
						break
					end
				end
				if #bad >= 5 then break end
			end
			R.expect(bad).toBeEmpty("places where the lane meets itself")
		end)

		R.it("walls never cut into the lane (inside of turns)", function()
			R.expect(MapChecks.wallIntrusions(intended, cfg.isWall, 6)).toBeEmpty("wall intrusions deeper than 6 studs from the lane edge")
		end)

		R.it("the road runs on past the finish line and ends at a wall", function()
			local finish
			for _, tr in ipairs(intended.triggers) do
				if table.find(tr.tags, "FinishLine") then finish = tr end
			end
			local runoff = intended.geo.length - intended.geo:project(finish.cx, finish.cz).s
			R.expect(runoff).toBeGreaterThan(120)
			local endWall = false
			for _, ob in ipairs(intended.obstacles) do
				if MapChecks.isEndWall(intended, ob) then endWall = true end
			end
			R.expect(endWall).toBe(true)
			-- a parked car (MaxSpeed 0 at the line, RacingManager) crossing at the
			-- fastest it can go (every buff stacked) stops before the wall
			local VC = intended.env.requirePath("ReplicatedStorage.Shared.VehicleController")
			local C = intended.env.requirePath("ReplicatedStorage.Shared.Constants")
			local top = C.RACE_SPEED[biome].center * (1 + C.RACE_SPEED[biome].spread) * C.SPEED_STACK_MAX
			local state = VC.newState()
			state.speed = top
			local dist, dt = 0, 1 / 60
			for _ = 1, 60 * 10 do
				local cmd = VC.command(VC.readKeys({ W = true }), { maxSpeed = 0, turnSpeed = 1, torque = 100, dt = dt,
					isSky = biome == "SKY", biome = biome, actualForward = state.speed }, state)
				dist += math.max(cmd.forwardSpeed, 0) * dt
				if cmd.forwardSpeed <= 0.1 then break end
			end
			R.expect(dist).toBeLessThan(runoff - 8)
		end)

		R.it("walls have no holes wider than a doorway, outside of turns included", function()
			R.expect(MapChecks.wallGaps(intended, cfg.isWall, cfg.wallOffset, cfg.doorway + 1))
				.toBeEmpty("holes in the wall wider than " .. cfg.doorway .. " studs")
		end)

		R.it("walls never continue past a corner as a detached spur", function()
			local t = intended.track
			local thick = t.wallThickness or 2
			R.expect(MapChecks.detachedWallRuns(intended, t.width / 2 + thick / 2, t.width / 2 + thick))
				.toBeEmpty("wall stretches cut off from their segment")
		end)

		R.it("off-track slow zones never cover the lane", function()
			R.expect(MapChecks.slowZonesInLane(intended)).toBeEmpty("slow zones inside the driving lane")
		end)

		R.it("checkpoints and the finish line cannot be driven past", function()
			local gaps = {}
			for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
				for _, g in ipairs(MapChecks.gateSpan(intended, tag)) do table.insert(gaps, g) end
			end
			R.expect(gaps).toBeEmpty("gates a car can miss")
		end)

		R.it("boost pads lie fully on the lane", function()
			R.expect(MapChecks.onLane(intended, "BoostPad")).toBeEmpty("pads off the lane")
		end)

		R.it("drift corners and jump zones are on the racing line", function()
			local bad = MapChecks.onCenterline(intended, "DriftCorner")
			for _, b in ipairs(MapChecks.onCenterline(intended, "JumpZone")) do table.insert(bad, b) end
			R.expect(bad).toBeEmpty("triggers the centerline never passes")
		end)

		if cfg.isFloor then
			R.it("the floor has no holes under the lane, outside of turns included", function()
				R.expect(MapChecks.floorCoverage(intended, cfg.isFloor)).toBeEmpty("lane without floor")
			end)
		end

		if cfg.props then
			R.it("decoration stays off the lane", function()
				local bad, half = {}, intended.track.width / 2
				for _, sh in ipairs(intended.allShapes) do
					for _, pat in ipairs(cfg.props) do
						if sh.name:match(pat) then
							local p = intended.geo:project(sh.cx, sh.cz)
							if p.dist - math.max(sh.hu, sh.hv) < half then
								table.insert(bad, string.format("%s at (%d,%d) reaches into the lane (s=%d)", sh.name, sh.cx, sh.cz, p.s))
							end
						end
					end
				end
				table.sort(bad)
				R.expect(bad).toBeEmpty("decoration in the lane")
			end)
		end

		R.it("racing visibility is right even when originals were never cached", function()
			local env = Loader.boot()
			local map = env.requirePath("ServerScriptService.Modules.Maps." .. World.BIOMES[biome].builder).build()
			R.expect(MapChecks.uncachedVisibility(env, map)).toBeEmpty("triggers that became solid or visible")
		end)
	end)
end

--- Kinematic race sims on the biome's map (see tests/lib/kinesim.luau for
-- what is and is not modelled).
function BiomeSpecs.sim(biome)
	local intended = World.build(biome, { visibility = "intended" })
	local shipped = World.build(biome, { visibility = "shipped" })
	local env = intended.env
	local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local reps = Builds.representative(Builds.enumerate(env, biome))
	local function car(i) return KineSim.carFromStats(reps[i].build.stats, Constants, biome) end

	local function run(world, profile, seed, c)
		return KineSim.run(world, {
			car = c or car(2), profile = Autopilot.PROFILES[profile], profileName = profile,
			seed = seed or 1, respawn = "track",
		})
	end

	R.describe("race sim (" .. biome .. ", median car)", function()
		R.it("is deterministic for a given seed", function()
			local a = run(intended, "average", 7)
			local b = run(intended, "average", 7)
			R.expect(a.endT).toBe(b.endT)
			R.expect(a.maxProgress).toBe(b.maxProgress)
			R.expect(#a.impacts).toBe(#b.impacts)
		end)

		R.it("an expert reaches both checkpoints in order", function()
			local r = run(intended, "expert", 1)
			R.expect(#r.checkpoints).toBe(2)
			R.expect(r.checkpoints[1].index).toBe(1)
		end)

		R.it("an average driver finishes on the authored map (3 seeds)", function()
			local unfinished = {}
			for seed = 1, 3 do
				local r = run(intended, "average", seed)
				if not r.finished then
					table.insert(unfinished, string.format("seed %d: stopped at s=%d/%d after %d respawns", seed, r.maxProgress, r.trackLength, #r.respawns))
				end
			end
			R.expect(unfinished).toBeEmpty("runs that did not finish in " .. Constants.RACING_TIMEOUT .. " s")
		end)

		R.it("a faster build beats a slower one with the same driver", function()
			local slow = run(intended, "expert", 1, car(1))
			local fast = run(intended, "expert", 1, car(3))
			R.expect(slow.finished and fast.finished).toBe(true)
			R.expect(fast.time).toBeLessThan(slow.time)
		end)
	end)

	R.describe("race sim (" .. biome .. ", map as the live server shows it)", function()
		R.it("slowest / median / fastest build × every driver finishes without respawning", function()
			local bad = {}
			for i, rep in ipairs(reps) do
				for _, profile in ipairs({ "expert", "average", "novice" }) do
					local r = run(shipped, profile, 1, car(i))
					if not r.finished or #r.respawns > 0 then
						table.insert(bad, string.format("%s / %s: finished=%s at s=%d/%d, %d respawns",
							rep.label, profile, tostring(r.finished), r.maxProgress, r.trackLength, #r.respawns))
					end
				end
			end
			R.expect(bad).toBeEmpty("runs that got stuck or timed out")
		end)
	end)
end

return BiomeSpecs
