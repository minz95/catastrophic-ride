--!nocheck
-- tools/catchup_compare.luau — fun metrics with and without catch-up
-- (Shared/CatchUp) on simulated 6-bot matches, every biome. Both use the
-- live finish grace (CatchUp.graceFor).
--   lune run tools/catchup_compare.luau [matches=6]
local process = require("@lune/process")
local MatchSim = require("../tests/lib/matchsim")
local World = require("../tests/lib/world")
local N = tonumber(process.args[1]) or 6

for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	local world = World.build(biome, { visibility = "intended" })
	local RaceMetrics = world.env.requirePath("ReplicatedStorage.Shared.RaceMetrics")
	for _, on in ipairs({ false, true }) do
		local list = {}
		local cut = 0
		for seed = 1, N do
			local m = MatchSim.run({ players = 6, seed = seed, world = world, biome = biome, catchUp = on })
			table.insert(list, m.fun)
		end
		local a = RaceMetrics.aggregate(list)
		local function v(k) local x = a[k]; return type(x) == "table" and (x.mean or x.avg or x.value) or x end
		print(string.format("%-6s catch-up %-3s  finish %.0f%%  winner %.0fs  spread %.0fs  lead changes %.1f  top-two close %.0f%%",
			biome, on and "on" or "off", (v("finishRate") or 0) * 100, v("winnerTime") or 0, v("finishSpread") or 0,
			v("leadChanges") or 0, (v("closeShare") or 0) * 100))
	end
end
