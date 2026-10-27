--!nocheck
-- SKY map built in the mock engine from the real SkyMap module, checked for
-- geometry problems a player would hit (see tests/lib/biomespecs.luau).
require("../lib/biomespecs").map("SKY", {
	isWall = function(name) return name:sub(1, 11) == "SkyBarrier_" end,
	wallOffset = 26,     -- CORRIDOR_W / 2 + 1
	doorway = 0,         -- continuous see-through barrier, no doorways
	isFloor = function(name) return name:sub(1, 10) == "TrackFloor" end,
	-- updraft 3 sits on the descent on purpose (a hazard zone), so not listed
	props = { "^Island", "^Balloon", "^EdgePuff_", "^CloudPuff" },   -- CloudSea lies far below the floor
})

-- Planes have no grip limit but a capped turn rate: at top speed a corner of
-- angle θ needs R (1 / cos(θ/2) − 1) studs off the centreline (R = speed /
-- turn rate). The canyon's ±80 zigzag needed 15-34 of the lane's 25 and every
-- plane met the outer fence side-on (Studio record-sky, playtest 2026-10-28).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local env = Loader.boot({ quiet = true })
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local VehicleController = env.requirePath("ReplicatedStorage.Shared.VehicleController")
local SkyTrack = env.requirePath("ReplicatedStorage.Shared.Tracks.SkyTrack")

R.describe("SKY corners a plane can make", function()
	R.it("every corner needs at most a third of the half lane at top speed and the slowest turn", function()
		local S = Constants.RACE_SPEED.SKY
		local speed = S.center * (1 + S.spread)
		local turn = VehicleController.turnRate(Constants.TURN_SPEED.SKY.min, true)
		local radius = speed / turn
		local limit = SkyTrack.width / 2 / 3
		local bad = {}
		local n = SkyTrack.nodes
		for i = 2, #n - 1 do
			local h1 = math.atan2(n[i][1] - n[i - 1][1], n[i][2] - n[i - 1][2])
			local h2 = math.atan2(n[i + 1][1] - n[i][1], n[i + 1][2] - n[i][2])
			local th = math.abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
			local off = radius * (1 / math.cos(th / 2) - 1)
			if off > limit then
				table.insert(bad, string.format("N%d: %.0f° corner needs %.1f studs (limit %.1f)", i, math.deg(th), off, limit))
			end
		end
		R.expect(bad).toBeEmpty("corners too sharp for a plane")
	end)
end)
