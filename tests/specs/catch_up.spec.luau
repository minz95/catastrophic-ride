--!nocheck
-- Catch-up and the finish grace (Shared/CatchUp, RacingManager).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local CFrame = require("@lune/roblox").CFrame

local env = Loader.boot()
local CatchUp = env.requirePath("ReplicatedStorage.Shared.CatchUp")
local C = env.requirePath("ReplicatedStorage.Shared.Constants")

R.describe("CatchUp rules", function()
	R.it("no bonus near the leader, more the further behind, capped at MAX", function()
		R.expect(CatchUp.mult(0)).toBe(1)
		R.expect(CatchUp.mult(C.CATCH_UP.GAP_START)).toBe(1)
		R.expect(CatchUp.mult(200) > 1 and CatchUp.mult(200) < CatchUp.mult(350)).toBe(true)
		R.expect(CatchUp.mult(C.CATCH_UP.GAP_FULL)).toBeNear(1 + C.CATCH_UP.MAX, 1e-9)
		R.expect(CatchUp.mult(5000)).toBeNear(1 + C.CATCH_UP.MAX, 1e-9)
		R.expect(CatchUp.mult(-100)).toBe(1)
	end)

	R.it("the finish grace is FINISH_GRACE at least, a share of a slow winner's time, capped", function()
		R.expect(CatchUp.graceFor(60)).toBe(C.FINISH_GRACE)
		R.expect(CatchUp.graceFor(120)).toBe(120 * C.FINISH_GRACE_SHARE)
		R.expect(CatchUp.graceFor(1000)).toBe(C.FINISH_GRACE_MAX)
	end)
end)

R.describe("RacingManager applies catch-up", function()
	R.it("a car far behind the leader races with the catchUp multiplier; the leader never", function()
		local srv = Server.boot({
			players = 2,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1 } },
		})
		local e = srv.env
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
		local cars = {}
		for i, p in ipairs(srv.players) do
			local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
			model.Parent = e.workspace
			srv.SessionManager.setVehicle(p, model, stats)
			cars[i] = model
		end
		srv.advance(0.5)
		srv.advance(C.RACE_COUNTDOWN + 0.5)
		local base = cars[2]:FindFirstChildWhichIsA("VehicleSeat", true).MaxSpeed
		-- car 1 far ahead on the track (700 studs along it)
		local TrackGeometry = e.requirePath("ReplicatedStorage.Shared.TrackGeometry")
		local track = e.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
		local g = TrackGeometry.new(track.nodes, track.width, track.trackTop)
		local x, z = g:pointAt(700)
		cars[1]:PivotTo(CFrame.new(x, g:heightAt(700) + 2, z))
		srv.advance(2)
		local behind = cars[2]:FindFirstChildWhichIsA("VehicleSeat", true).MaxSpeed
		local ahead = cars[1]:FindFirstChildWhichIsA("VehicleSeat", true).MaxSpeed
		R.expect(behind > base * 1.05).toBe(true)
		R.expect(ahead <= base + 1e-6).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
