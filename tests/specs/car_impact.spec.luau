--!nocheck
-- Car-to-car hits (Shared/CarImpact) and how RacingManager sends them.
--
-- History (2026-10-22): the drive model sets each car's velocity every
-- frame, so Roblox's own collision response was overwritten and a hit felt
-- like touching a wall; only a rear-end got a fixed 30 studs/s shove through
-- a second BodyVelocity that fought the drive mover.
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local CarImpact = env.requirePath("ReplicatedStorage.Shared.CarImpact")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local I = Constants.IMPACT

local function car(x, z, vx, vz, mass, lx, lz)
	return { x = x, z = z, vx = vx, vz = vz, mass = mass or 10, lx = lx or 0, lz = lz or -1 }
end

local function len(s) return math.sqrt(s.dvx ^ 2 + s.dvz ^ 2) end

R.describe("CarImpact.resolve", function()
	R.it("a rear-end pushes the car in front forward and slows the one behind", function()
		-- both face -Z; B is 5 studs ahead, A is 20 studs/s faster
		local hit = CarImpact.resolve(car(0, 0, 0, -60), car(0, -5, 0, -40))
		R.expect(hit).toBeTruthy()
		R.expect(hit.b.dvz).toBeLessThan(-5)    -- B shoved forward (-Z)
		R.expect(hit.a.dvz).toBeGreaterThan(5)  -- A loses speed
		R.expect(math.abs(hit.a.spin)).toBeLessThan(1e-6)   -- square hit: no spin
	end)

	R.it("cars moving apart, or touching gently, do nothing", function()
		R.expect(CarImpact.resolve(car(0, 0, 0, -40), car(0, -5, 0, -60))).toBe(nil)
		R.expect(CarImpact.resolve(car(0, 0, 0, -41), car(0, -5, 0, -40))).toBe(nil)
	end)

	R.it("the heavier car is pushed less", function()
		local hit = CarImpact.resolve(car(0, 0, 0, -60, 30), car(0, -5, 0, -40, 10))
		R.expect(len(hit.b)).toBeGreaterThan(len(hit.a) * 2)
	end)

	R.it("a hit on the nose from the side spins the car away from the hitter", function()
		-- A faces -Z; B comes in from A's right (+X), a little ahead of A's centre
		local hit = CarImpact.resolve(car(0, 0, 0, -40), car(4, -2, -30, -40))
		R.expect(hit.a.dvx).toBeLessThan(0)       -- A pushed to its left (-X)
		R.expect(hit.a.spin).toBeGreaterThan(0)   -- nose turns left (+yaw), away from B
	end)

	R.it("a hit on the tail from the side turns the nose towards the hitter", function()
		local hit = CarImpact.resolve(car(0, 0, 0, -40), car(4, 2, -30, -40))
		R.expect(hit.a.spin).toBeLessThan(0)
	end)

	R.it("pushes and spins are capped", function()
		local hit = CarImpact.resolve(car(0, 0, 0, -400, 1), car(0, -5, 0, 400, 1000))
		R.expect(len(hit.a)).toBeAtMost(I.MAX_DV + 1e-6)
		local side = CarImpact.resolve(car(0, 0, 0, 0, 1), car(4, -3, -400, 0, 1000))
		R.expect(math.abs(side.a.spin)).toBeAtMost(I.MAX_SPIN + 1e-6)
	end)

	R.it("addPush adds an extra shove (Shopping Cart HEAD)", function()
		local side = { dvx = 0, dvz = -10, spin = 0 }
		CarImpact.addPush(side, 0, -2, 15)
		R.expect(side.dvz).toBeNear(-25, 1e-9)
	end)
end)

R.describe("RacingManager sends hits to both drivers", function()
	local src = require("@lune/fs").readFile("roblox/ServerScriptService/RacingManager.server.lua")
	R.it("every contact goes through CarImpact and RemoteEvents.CarImpact", function()
		R.expect(src:find("CarImpact.resolve", 1, true) ~= nil).toBe(true)
		R.expect(select(2, src:gsub("RemoteEvents.CarImpact:FireClient", ""))).toBe(2)
	end)
	R.it("no second BodyVelocity fights the drive mover on a rear-end", function()
		local contact = src:sub(src:find("local function _rearEndPassives", 1, true), src:find("-- Per-race passive setup", 1, true))
		R.expect(contact:find("BodyVelocity", 1, true)).toBe(nil)
	end)
end)
