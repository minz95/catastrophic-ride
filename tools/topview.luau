--!nocheck
-- topview.luau
-- Dumps a biome's lane, walls and simulated driver paths as JSON for
-- tools/topview.py (top-down PNG with respawns marked).
--
--   lune run tools/topview.luau <BIOME> [seeds] [out.json]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local World = require("../tests/lib/world")
local KineSim = require("../tests/lib/kinesim")
local Builds = require("../tests/lib/builds")

local biome = (process.args[1] or "SKY"):upper()
local seeds = tonumber(process.args[2] or "4")
local out = process.args[3] or ("reports/" .. biome:lower() .. "/topview.json")

local w = World.build(biome, { visibility = "shipped" })
local env = w.env
local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local reps = Builds.representative(Builds.enumerate(env, biome))

local data = { biome = biome, width = w.track.width, nodes = w.track.nodes, walls = {}, runs = {} }
for _, ob in ipairs(w.obstacles) do
	table.insert(data.walls, { cx = ob.cx, cz = ob.cz, ux = ob.ux, uz = ob.uz, hu = ob.hu, vx = ob.vx, vz = ob.vz, hv = ob.hv, name = ob.name })
end
for i, rep in ipairs(reps) do
	for _, profile in ipairs({ "expert", "average", "novice" }) do
		for seed = 1, seeds do
			local r = KineSim.run(w, {
				car = KineSim.carFromStats(rep.build.stats, Constants, biome),
				profile = Autopilot.PROFILES[profile], profileName = profile, seed = seed, respawn = "track",
			})
			local pts = {}
			for _, s in ipairs(r.samples) do table.insert(pts, { s.x, s.z, s.y }) end
			local rs = {}
			for _, e in ipairs(r.respawns) do table.insert(rs, { x = e.from.x, z = e.from.z, s = e.s, t = e.t, reason = e.reason }) end
			table.insert(data.runs, { car = rep.label, profile = profile, seed = seed, finished = r.finished, time = r.time, pts = pts, respawns = rs })
			if #rs > 0 then
				for _, e in ipairs(r.respawns) do
					print(string.format("%s/%s seed %d: respawn %s at (%d,%d) s=%d t=%.1f", rep.label, profile, seed, tostring(e.reason), math.floor(e.from.x), math.floor(e.from.z), e.s or -1, e.t))
				end
			end
		end
	end
end
fs.writeFile(out, serde.encode("json", data))
print("wrote " .. out)
