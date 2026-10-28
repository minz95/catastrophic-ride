--!nocheck
-- Playtest 2026-10-29: a boat or a bot that left the lane floated on the
-- open sea and never came back (no fall rule saw it).
local R = require("../lib/runner")
local fs = require("@lune/fs")
local Loader = require("../lib/loader")

local env = Loader.boot({ quiet = true })
local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

R.describe("off the lane", function()
	R.it("is 0 on the lane and grows beyond its edge, in every biome", function()
		for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
			local geo = RaceProgress.geometry(biome)
			for _, s in ipairs({ geo.length * 0.2, geo.length * 0.5, geo.length * 0.8 }) do
				local x, z, dx, dz = geo:pointAt(s)
				local y = geo:heightAt(s)
				local on = RaceProgress.offLane(biome, x, z, nil, y)
				R.expect(on).toBe(0)
				-- 40 studs past the lane edge, to the right
				local d = geo.halfWidth + 40
				local out = RaceProgress.offLane(biome, x - dz * d, z + dx * d, nil, y)
				R.expect(out).toBeGreaterThan(Constants.OFF_LANE.MARGIN)
			end
		end
	end)

	R.it("respawns only after SECONDS out, and a car back on the lane starts over", function()
		local st, O = {}, Constants.OFF_LANE
		local fired = false
		for _ = 1, math.floor(O.SECONDS * 60) - 2 do
			fired = RaceProgress.offLaneStep(st, O.MARGIN + 5, 1 / 60) or fired
		end
		R.expect(fired).toBe(false)
		RaceProgress.offLaneStep(st, 0, 1 / 60)
		R.expect(st.offFor).toBe(0)
		for _ = 1, math.ceil(O.SECONDS * 60) + 1 do
			fired = RaceProgress.offLaneStep(st, O.MARGIN + 5, 1 / 60) or fired
		end
		R.expect(fired).toBe(true)
	end)

	R.it("players and race bots both use it", function()
		local rm = fs.readFile("roblox/ServerScriptService/RacingManager.server.lua")
		local rb = fs.readFile("roblox/ServerScriptService/Modules/RaceBots.lua")
		R.expect(rm:find('"off_lane"', 1, true) ~= nil).toBe(true)
		R.expect(rb:find("RaceProgress.offLaneStep", 1, true) ~= nil).toBe(true)
	end)
end)
