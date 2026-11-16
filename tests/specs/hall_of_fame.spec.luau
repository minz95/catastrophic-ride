--!nocheck
-- The lobby's hall of fame (2026-11-16: "the winning ride with its driver
-- in the lobby"): RideShowManager hands the vote's winner to
-- Modules/HallOfFame, which builds the ride still with the winner seated
-- into ReplicatedStorage.HallOfFame; LobbyUI shows it beside the line-up.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

R.describe("hall of fame", function()
	R.it("entry: only string slots, the looks a ride shows, numbers sane", function()
		local env = Loader.boot()
		local H = env.requirePath("ServerScriptService.Modules.HallOfFame")
		local e = H.entry(5, "Ann", "SKY", { BODY = "Toilet", [3] = "x", ENGINE = 7 }, 3,
			{ hat = "hat_crown", pose = "pose_flex", paint = "paint_default", move = "move_kick" }, 100)
		R.expect(e.slots.BODY).toBe("Toilet")
		R.expect(e.slots.ENGINE).toBe(nil)
		R.expect(e.look.hat).toBe("hat_crown")
		R.expect(e.look.pose).toBe("pose_flex")
		R.expect(e.look.paint).toBe(nil)   -- the default
		R.expect(e.look.move).toBe(nil)    -- not a look a ride shows
		R.expect(H.entry(nil, "x", "SKY", {})).toBe(nil)
		R.expect(H.live).toBe(false)       -- tests never touch the DataStore
	end)

	R.it("the ride show's winner is built into ReplicatedStorage.HallOfFame with a rider and its votes", function()
		local harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = 3,
			botLoadouts = { { BODY = "Refrigerator", ENGINE = "Kettle" }, { BODY = "Washing Machine" } },
			rideShowBots = 2, durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } }
		local srv = Server.boot({
			players = 1,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.RideShowManager",
			},
			harness = harness,
		})
		local e = srv.env
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
		stats.slotAssignments = { BODY = "Rocking Horse" }
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(7, 2, 590), stats.slotAssignments)
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(srv.players[1], model, stats)
		local hb = e.game:GetService("RunService").Heartbeat
		srv.advance(0.5, 1 / 30, function() hb:Fire(1 / 30) end)
		srv.GameManager.raceComplete({})
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local RS = e.game:GetService("ReplicatedStorage")
		R.expect(RS:FindFirstChild("HallOfFame")).toBe(nil)   -- nobody won yet
		srv.advance(20)
		local folder = RS:FindFirstChild("HallOfFame")
		local winner = folder and folder:FindFirstChild("Winner")
		R.expect(winner ~= nil).toBe(true)
		R.expect(winner:GetAttribute("Votes") >= 1).toBe(true)
		R.expect(winner:FindFirstChild("Rider") ~= nil).toBe(true)
		local H = e.requirePath("ServerScriptService.Modules.HallOfFame")
		R.expect(H.latest().slots.BODY ~= nil).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the lobby shows it on the left and wears my pose on my own copy", function()
		local ui = fs.readFile("roblox/StarterGui/LobbyUI/init.client.lua")
		R.expect(ui:find('WaitForChild("HallOfFame"', 1, true) ~= nil).toBe(true)
		R.expect(ui:find("fameFrame.Size = listFrame.Size", 1, true) ~= nil).toBe(true)
		R.expect(ui:find('RidePoses.applyStill, rider, LocalPlayer:GetAttribute("RidePose")', 1, true) ~= nil).toBe(true)
	end)
end)

return R
