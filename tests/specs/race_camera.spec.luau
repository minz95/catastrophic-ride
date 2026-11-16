--!nocheck
-- Playtest 2026-11-16: in a bend the chase camera stood behind the outer
-- wall and the wall filled the screen. Shared/RaceCamera brings it in
-- front of whatever solid stands between the car and the camera.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local fs = require("@lune/fs")
local V3 = require("@lune/roblox").Vector3

-- a wall: the plane x = wallX, solid between y 0 and 20
local function wallAt(wallX, part)
	return function(origin, dir)
		if dir.X == 0 then return nil end
		local t = (wallX - origin.X) / dir.X
		if t <= 0 or t > 1 then return nil end
		local p = origin + dir * t
		if p.Y < 0 or p.Y > 20 then return nil end
		return { Position = p, Instance = part or { Name = "Wall" } }
	end
end

R.describe("race camera and walls", function()
	local env = Loader.boot()
	local C = env.requirePath("ReplicatedStorage.Shared.RaceCamera")
	local focus = V3.new(0, 1.5, 0)
	local want = V3.new(-14, 6, 0)   -- 14 studs behind, up

	R.it("nothing in the way: the camera stays where the chase rule puts it", function()
		R.expect(C.unblock(focus, want, function() return nil end)).toBe(want)
	end)

	R.it("a wall between car and camera: the camera comes in to just before it, still looking at the car", function()
		local at = C.unblock(focus, want, wallAt(-6))
		R.expect(at.X > -6).toBe(true, tostring(at))
		R.expect(at.X < -4).toBe(true, tostring(at))
		-- on the same line from the car (the view keeps its angle)
		local a, b = (want - focus).Unit, (at - focus).Unit
		R.expect((a - b).Magnitude < 1e-3).toBe(true)
	end)

	R.it("a wall right at the car: never closer than MIN_DIST", function()
		local at = C.unblock(focus, want, wallAt(-0.5))
		R.expect(math.abs((at - focus).Magnitude - C.MIN_DIST) < 1e-3).toBe(true)
	end)

	R.it("see-through or loose parts (glass fence, other cars) are looked through", function()
		local glass = { Name = "Glass" }
		local casts = 0
		local cast = function(origin, dir)
			casts += 1
			local glassHit = wallAt(-4, glass)(origin, dir)
			if glassHit then return glassHit end
			return wallAt(-10)(origin, dir)
		end
		local at = C.unblock(focus, want, cast, function(p) return p == glass end)
		R.expect(at.X < -8 and at.X > -10).toBe(true, tostring(at))
		R.expect(casts).toBe(2)
	end)

	R.it("RacingClient's chase camera goes through it, past the car, riders and other cars", function()
		local rc = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		for _, needle in ipairs({ "RaceCamera.unblock(focus, cf.Position", "_camParams.RespectCanCollide = true",
			'model.Name:sub(1, 8) == "Vehicle_"', "part.Transparency >= 0.5 or not part.Anchored" }) do
			R.expect(rc:find(needle, 1, true) ~= nil).toBe(true, needle)
		end
	end)
end)

return R
