--!nocheck
-- FOREST map built in the mock engine from the real ForestMap module, checked
-- for geometry problems a player would hit (shared checks: tests/lib/biomespecs.luau).
local R = require("../lib/runner")
local World = require("../lib/world")
local MapChecks = require("../lib/mapchecks")

require("../lib/biomespecs").map("FOREST", {
	isWall = function(name) return name == "TrackWall" end,
	wallOffset = 21,     -- width / 2 + wallThickness / 2
	doorway = 0,         -- continuous walls (ForestTrack.wallGapHalfWidth = 0)
	isFloor = function(name) return name:sub(1, 8) == "TrackSeg" end,
	props = { "Trunk$", "^RockBase_%d+$" },
})

local intended = World.forest({ visibility = "intended" })
local geo, track = intended.geo, intended.track

R.describe("FOREST map: forest-only props", function()
	R.it("has one mud zone per data entry", function()
		R.expect(#MapChecks.tagged(intended, "MudZone")).toBe(#track.mudZones)
	end)

	R.it("jump ramps sit inside the corridor and face the direction of travel", function()
		local bad = {}
		for i, r in ipairs(track.jumpRamps) do
			local p = geo:project(r[1], r[2])
			local trackYaw = geo:yawAt(p.s)
			-- WedgePart is built with CFrame.Angles(0, yaw + pi, 0); its slope faces
			-- the vehicle when that yaw matches the travel direction ± 180°.
			local diff = math.abs(math.deg(((r[3] + math.pi - trackYaw + math.pi) % (2 * math.pi)) - math.pi))
			diff = math.min(diff, math.abs(180 - diff))
			if math.abs(p.lateral) > 4 then
				table.insert(bad, string.format("JumpRamp_%d is %.0f studs off centre (ramp half-width %d)", i, math.abs(p.lateral), track.jumpRampSize[1] / 2))
			end
			if diff > 15 then
				table.insert(bad, string.format("JumpRamp_%d is rotated %.0f° from the track direction", i, diff))
			end
		end
		R.expect(bad).toBeEmpty("misplaced ramps")
	end)
end)
