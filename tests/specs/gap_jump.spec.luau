--!nocheck
-- Gap jumps (ForestTrack.gapJumps): the road is cut, a spring pad sits
-- before the lip, and a respawn near it goes back before the pad.
local R = require("../lib/runner")
local World = require("../lib/world")
local MapQuery = require("../lib/mapquery")

local w = World.build("FOREST", { visibility = "intended" })
local RaceProgress = w.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local gaps = w.geo:gapIntervals(w.track.gapJumps)

-- collidable parts under (x, z) whose top is within 1.5 studs of the road there
local function floorAt(s)
	local x, z = w.geo:pointAt(s)
	local y = w.geo:heightAt(s)
	local out = {}
	for _, sh in ipairs(w.allShapes) do
		if sh.canCollide and MapQuery.contains(sh, x, z) and sh.yMax > y - 1.5 and sh.yMin < y + 1.5 then
			table.insert(out, sh)
		end
	end
	return out
end

R.describe("FOREST gap jump", function()
	R.it("has at least one gap, on a raised stretch (falling in means a respawn)", function()
		R.expect(#gaps >= 1).toBe(true)
		for _, g in ipairs(gaps) do
			local y = w.geo:heightAt((g.s0 + g.s1) / 2)
			R.expect(y - w.track.trackTop > RaceProgress.FALL_BELOW + 4).toBe(true)
		end
	end)

	R.it("the road is cut across the whole gap and whole on both sides", function()
		for _, g in ipairs(gaps) do
			for s = g.s0 + 1, g.s1 - 1, 2 do
				R.expect(#floorAt(s)).toBe(0)
			end
			R.expect(#floorAt(g.s0 - 3) > 0).toBe(true)
			R.expect(#floorAt(g.s1 + 3) > 0).toBe(true)
		end
	end)

	R.it("a spring pad covers the run-up to the lip, with its launch numbers", function()
		for i, g in ipairs(gaps) do
			local pad = w.map:FindFirstChild("SpringPad_" .. i, true)
			R.expect(pad ~= nil).toBe(true)
			R.expect(pad.CanCollide).toBe(true)
			R.expect(pad:GetAttribute("VY")).toBe(g.gap.vy)
			R.expect(pad:GetAttribute("MinSpeed")).toBe(g.gap.minSpeed)
			-- on the road right before the lip, its top just above the road
			local found = false
			for _, sh in ipairs(floorAt(g.s0 - 2)) do
				if sh.name == pad.Name then
					found = true
					R.expect(sh.yMax - w.geo:heightAt(g.s0 - 2)).toBeNear(0.05, 0.1)
				end
			end
			R.expect(found).toBe(true)
		end
	end)

	R.it("the pad's arc at its MinSpeed clears the gap", function()
		local J = w.env.requirePath("ReplicatedStorage.Shared.Constants").DRIVE.JUMP
		for _, g in ipairs(gaps) do
			-- back down to the take-off height (the far side is a little higher on a climb)
			local rise = w.geo:heightAt(g.s1 + 2) - w.geo:heightAt(g.s0 - 2)
			local vy, gr = g.gap.vy, J.GRAVITY
			local t = (vy + math.sqrt(vy * vy - 2 * gr * rise)) / gr
			R.expect(g.gap.minSpeed * t > (g.s1 - g.s0) * 1.4).toBe(true)   -- 40 % to spare
		end
	end)

	R.it("a respawn near the gap goes back before the spring pad", function()
		local geo = RaceProgress.geometry("FOREST")
		for _, g in ipairs(geo.gaps) do
			for _, s in ipairs({ g.pad0 - 10, g.s0 + 4, (g.s0 + g.s1) / 2, g.s1 + 2 }) do
				local x, z = geo:pointAt(s)
				local rx, _, rz = RaceProgress.respawnPoint("FOREST", x, z, 2, nil, geo:heightAt(s) + 2)
				local rs = geo:progressAt(rx, rz, nil, nil, geo:heightAt(g.pad0))
				R.expect(rs < g.pad0 - RaceProgress.GAP_RUNUP + 1).toBe(true)
			end
			-- far past it: the usual step back
			local s = g.s1 + 60
			local x, z = geo:pointAt(s)
			local rx, _, rz = RaceProgress.respawnPoint("FOREST", x, z, 2, nil, geo:heightAt(s) + 2)
			R.expect(math.abs(geo:progressAt(rx, rz, nil, nil, geo:heightAt(s)) - (s - RaceProgress.RESPAWN_STEP_BACK)) < 1).toBe(true)
		end
	end)
end)
