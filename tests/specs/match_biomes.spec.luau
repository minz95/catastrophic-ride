--!nocheck
-- A whole match on OCEAN and SKY: real FarmingManager / CraftingManager with
-- 6 bots on the biome's farm, then every crafted vehicle raced on the
-- kinematic simulator (tests/lib/matchsim.luau).
local R = require("../lib/runner")
local MatchSim = require("../lib/matchsim")

for _, biome in ipairs({ "OCEAN", "SKY" }) do
	R.describe(biome .. " match (6 bots)", function()
		local m = MatchSim.run({ players = 6, seed = 3, biome = biome })

		R.it("runs without server script errors", function()
			R.expect(m.serverErrors).toBeEmpty("errors raised inside server scripts")
		end)

		-- pickups, not the final inventory: a casual bot can lose everything to steals
		R.it("every bot picks up items on the " .. biome .. " farm and gets a vehicle", function()
			local bad = {}
			for _, p in ipairs(m.results) do
				if p.farm.pickups == 0 then table.insert(bad, p.name .. " picked up nothing") end
				if not p.maxSpeed then table.insert(bad, p.name .. " has no vehicle") end
			end
			R.expect(bad).toBeEmpty("bots without items or vehicles")
		end)

		R.it("every crafted vehicle finishes the race", function()
			local bad = {}
			for _, p in ipairs(m.results) do
				if not p.race.finished then
					table.insert(bad, string.format("%s (%s driver, MaxSpeed %d): stopped at s=%d after %d respawns",
						p.name, p.driver, p.maxSpeed, p.race.progress, p.race.respawns))
				end
			end
			R.expect(bad).toBeEmpty("vehicles that did not finish")
		end)
	end)
end
