--!nocheck
-- tools/gust_sim.luau — what each weather's gusts (Shared/Weather →
-- HazardManager._gust) do to a race: the same cars and drivers round the
-- track (tests/lib/kinesim) with no gusts, the clear weather's and the
-- storm's, sideways pulses exactly as the server sends them (every
-- GUST_PULSE for GUST_DURATION, push = force × GUST_KNOCK_PER_FORCE, one side
-- per gust). Shows finish rate, time lost, respawns and wall hits.
--   lune run tools/gust_sim.luau [OCEAN|SKY] [seeds=6]
local process = require("@lune/process")
local World = require("../tests/lib/world")
local KineSim = require("../tests/lib/kinesim")
local Builds = require("../tests/lib/builds")

local biome = (process.args[1] or "OCEAN"):upper()
local SEEDS = tonumber(process.args[2]) or 6
local world = World.build(biome, { visibility = "intended" })
local env = world.env
local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local W = env.requirePath("ReplicatedStorage.Shared.Weather")
local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
local H = Constants.HAZARDS
local reps = Builds.representative(Builds.enumerate(env, biome))

local function gustOf(weather)
	for _, hz in ipairs(W.hazards(BiomeConfig[biome].hazards, biome, weather)) do
		if hz.type == "gustZone" then return hz end
	end
	return nil
end

local cases = { { name = "none", gust = nil } }
for _, w in ipairs({ "clear", "storm" }) do
	local g = gustOf(w)
	if g then table.insert(cases, { name = w, gust = g }) end
end

local function run(car, prof, seed, gust)
	local st = seed * 7919 + 1
	local function rnd() st = (st * 1103515245 + 12345) % 2147483648; return st / 2147483648 end
	local nextGust = gust and gust.interval or math.huge
	local gustEnd, side, lastPulse = -1, 1, -1
	return KineSim.run(world, {
		car = car, profile = Autopilot.PROFILES[prof], profileName = prof, seed = seed, respawn = "track",
		onStep = function(ctx)
			if not gust then return end
			if ctx.t >= nextGust then
				nextGust += gust.interval
				gustEnd = ctx.t + H.GUST_DURATION
				side = rnd() < 0.5 and -1 or 1
				lastPulse = -1
			end
			if ctx.t < gustEnd and ctx.t - lastPulse >= H.GUST_PULSE then
				lastPulse = ctx.t
				ctx.knock(0, side * gust.force * H.GUST_KNOCK_PER_FORCE)
			end
		end,
	})
end

print(("%s gusts: %s"):format(biome, (function()
	local t = {}
	for _, c in ipairs(cases) do
		table.insert(t, c.name .. (c.gust and (" every %ds force %d"):format(c.gust.interval, c.gust.force) or ""))
	end
	return table.concat(t, " | ")
end)()))
for _, rep in ipairs(reps) do
	if rep.label == "slowest" or rep.label == "p50" or rep.label == "fastest" then
		local car = KineSim.carFromStats(rep.build.stats, Constants, biome)
		for _, prof in ipairs({ "novice", "average", "expert" }) do
			local line = ("%-8s %-8s"):format(rep.label, prof)
			for _, c in ipairs(cases) do
				local fin, time, resp, walls = 0, 0, 0, 0
				for seed = 1, SEEDS do
					local r = run(car, prof, seed, c.gust)
					if r.finished then fin += 1; time += r.time end
					resp += #r.respawns
					walls += #r.impacts
				end
				line ..= ("  %s: %d/%d fin %5.1fs resp %.1f walls %.1f"):format(c.name, fin, SEEDS,
					fin > 0 and time / fin or 0, resp / SEEDS, walls / SEEDS)
			end
			print(line)
		end
	end
end
