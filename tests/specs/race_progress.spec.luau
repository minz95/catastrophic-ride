--!nocheck
-- RaceProgress (live ranking + respawn target) checked against every track.
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")

local function ranges(list, step)
	local out, a, prev = {}, nil, nil
	for _, s in ipairs(list) do
		if not a then
			a, prev = s, s
		elseif s - prev > step * 1.5 then
			table.insert(out, string.format("s=%d–%d", a, prev))
			a, prev = s, s
		else
			prev = s
		end
	end
	if a then table.insert(out, string.format("s=%d–%d", a, prev)) end
	return out
end

-- A continuous path offset from the centerline (like a real car's line);
-- geo:offsetPoint jumps at every kink, so it is not used here.
local function smoothOffset(geo, s, lat)
	local ax, az = geo:pointAt(s - 5)
	local bx, bz = geo:pointAt(s + 5)
	local dx, dz = bx - ax, bz - az
	local m = math.sqrt(dx * dx + dz * dz)
	local cx, cz = geo:pointAt(s)
	return cx - dz / m * lat, cz + dx / m * lat
end

for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	local geo = RaceProgress.geometry(biome)
	R.describe("race progress (" .. biome .. ")", function()
		R.it("has track data", function()
			R.expect(geo ~= nil).toBe(true)
		end)

		-- progressAt is continuous across kinks; a few studs of wobble remain
		-- where non-adjacent segments' regions overlap on zigzags.
		R.it("progress never drops more than 5 studs while driving forward", function()
			local back, last, seg = {}, -math.huge, nil
			for s = 0, geo.length, 2 do
				local ox, oz = smoothOffset(geo, s, 6)
				local p
				p, seg = RaceProgress.progress(biome, ox, oz, seg)
				if p < last - 5 then table.insert(back, s) end
				last = math.max(last, p)
			end
			R.expect(ranges(back, 2)).toBeEmpty("stretches where progress goes backwards")
		end)

		R.it("the respawn target is on the track and faces along it", function()
			local off, seg = {}, nil
			local width = geo.width
			for s = 0, geo.length, 10 do
				local x, z = smoothOffset(geo, s, 8)
				local _
				_, seg = RaceProgress.progress(biome, x, z, seg)
				local rx, _, rz, yaw = RaceProgress.respawnPoint(biome, x, z, BiomeConfig[biome].raceStartY, seg)
				local p = geo:project(rx, rz)
				local _, _, dx, dz = geo:pointAt(p.s)
				local facing = -math.sin(yaw) * dx + -math.cos(yaw) * dz
				if p.dist > 1 or facing < 0.9 or p.s > s then table.insert(off, s) end
			end
			R.expect(ranges(off, 10)).toBeEmpty("positions whose respawn is off the track, misaligned or ahead")
		end)
	end)
end

R.describe("race progress", function()
	R.it("is clamped to [0, track length]", function()
		local geo = RaceProgress.geometry("FOREST")
		R.expect(RaceProgress.progress("FOREST", 0, 5000)).toBe(0)
		R.expect(RaceProgress.progress("FOREST", 0, -9999)).toBeNear(geo.length, 1e-6)
	end)
end)
