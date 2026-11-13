--!nocheck
-- Playtest 2026-11-13: in SKY, climbing took a plane over the fence (and
-- wedged others under the lid), a car pinned against a wall stayed there,
-- and on a phone one stick had to give both gas and steering.
local R = require("../lib/runner")
local World = require("../lib/world")

local w = World.build("SKY", { visibility = "intended" })
local Constants = w.env.requirePath("ReplicatedStorage.Shared.Constants")
local RaceProgress = w.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local TouchDrive = w.env.requirePath("ReplicatedStorage.Shared.TouchDrive")

R.describe("SKY fence and lid", function()
	R.it("the fence reaches into the lid: no gap between them", function()
		R.expect(w.track.wallYHi >= w.track.ceilingY).toBe(true)
		local bad, n = {}, 0
		for _, sh in ipairs(w.allShapes) do
			if sh.name and string.sub(sh.name, 1, 11) == "SkyBarrier_" then
				n += 1
				local x = sh.cx or (sh.aabb[1] + sh.aabb[3]) / 2
				local z = sh.cz or (sh.aabb[2] + sh.aabb[4]) / 2
				local s = RaceProgress.progress("SKY", x, z, nil, sh.yMin + 6)   -- the road is 2 over its foot
				local lid = RaceProgress.roadY("SKY", s) + (w.track.ceilingY - w.track.trackTop)
				if sh.yMax < lid - 0.5 and #bad < 5 then
					table.insert(bad, string.format("%s top %.1f under lid %.1f", sh.name, sh.yMax, lid))
				end
			end
		end
		R.expect(n > 100).toBe(true)
		R.expect(bad).toBeEmpty("fence pieces whose top leaves a gap under the lid")
	end)

	R.it("the highest a plane gets (climb + strongest lift) stays under the lid", function()
		local U = Constants.UPDRAFT
		local lift = U.LIFT * U.MAX_SCALE
		for _, v in pairs(Constants.ABILITY_LIFT) do
			if v ~= Constants.ABILITY_LIFT.RATE then lift = math.max(lift, v) end
		end
		local cruise = 4   -- BiomeConfig.SKY.raceStartY over the road
		local top = cruise + Constants.SKY_CLIMB.MAX + lift + 2   -- + half a plane
		R.expect(top < w.track.ceilingY - w.track.trackTop).toBe(true)
	end)
end)

R.describe("over the lid", function()
	R.it("a plane above the lid counts as out (RacingManager respawns it); one under it does not", function()
		local s = 300
		local road = RaceProgress.roadY("SKY", s)
		local lid = w.track.ceilingY - w.track.trackTop
		R.expect(RaceProgress.overLid("SKY", s, road + 4)).toBe(false)
		R.expect(RaceProgress.overLid("SKY", s, road + lid - 1)).toBe(false)
		R.expect(RaceProgress.overLid("SKY", s, road + lid + 10)).toBe(true)
		R.expect(RaceProgress.overLid("FOREST", s, 9999)).toBe(false)   -- no lid there
	end)
end)

R.describe("stuck racers", function()
	R.it("a car that gains under MIN_GAIN in SECONDS is put back; a moving one never", function()
		local S = Constants.STUCK
		local st, fired = {}, 0
		for i = 1, 60 * 10 do
			if RaceProgress.stuckStep(st, 500 + (i % 3) * 0.5, 1 / 60) then fired += 1 end
		end
		R.expect(fired).toBe(math.floor(10 / S.SECONDS))
		local moving, any = {}, false
		for i = 1, 60 * 20 do
			if RaceProgress.stuckStep(moving, i * 0.5, 1 / 60) then any = true end   -- 30 studs/s
		end
		R.expect(any).toBe(false)
	end)
end)

R.describe("touch driving", function()
	local T = Constants.TOUCH_DRIVE
	R.it("gas is on with the stick untouched or pushed sideways", function()
		R.expect((TouchDrive.map(nil, nil))).toBe(1)
		local th, steer = TouchDrive.map(1, 0)
		R.expect(th).toBe(1)
		R.expect(steer).toBe(-1)   -- right
	end)
	R.it("steering grows with the push; a small wobble does nothing", function()
		local _, a = TouchDrive.map(T.DEADZONE * 0.5, 0)
		local _, b = TouchDrive.map(-0.4, 0)
		local _, c = TouchDrive.map(-T.FULL_AT, 0)
		R.expect(a).toBe(0)
		R.expect(b > 0 and b < 1).toBe(true)
		R.expect(c).toBeNear(1, 1e-9)
	end)
	R.it("pulling the stick back brakes", function()
		local th, _, back = TouchDrive.map(0, 0.9)
		R.expect(th).toBe(0)
		R.expect(back).toBe(true)
	end)
end)
