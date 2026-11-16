--!nocheck
-- Filming the ride show (2026-11-16, Korean reel): Studio records one bot
-- client, and a lone player never gets a ride show. Harness `botLoadouts`
-- fixes the race bots' builds and `rideShowBots` puts their rides in the
-- show, where they vote. Both are nil on live servers.
local R = require("../lib/runner")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

local LOADOUTS = {
	{ BODY = "Refrigerator", ENGINE = "Kettle", SPECIAL = "Pizza" },
	{ BODY = "Washing Machine", ENGINE = "Fire Extinguisher", SPECIAL = "Watermelon" },
}

local function results(extra)
	local harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = 3,
		durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } }
	for k, v in pairs(extra) do harness[k] = v end
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
	assert(srv.GameManager.getPhase() == "RACING", "not racing")
	srv.GameManager.raceComplete({})
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RESULTS", "no results")
	local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
	local function sent(kind)
		local out = {}
		for _, c in ipairs(rawget(RE.RideShow, "_calls") or {}) do
			if c.args[1] == kind then table.insert(out, c.args[2]) end
		end
		return out
	end
	return srv, sent
end

R.describe("filming the ride show (harness only)", function()
	R.it("botLoadouts builds the race bots as given; rideShowBots shows their rides and they vote", function()
		local srv, sent = results({ botLoadouts = LOADOUTS, rideShowBots = 2 })
		local open = sent("open")
		R.expect(#open).toBe(1)
		R.expect(#open[1].entries).toBe(3)
		local bodies = {}
		for _, entry in ipairs(open[1].entries) do bodies[entry.slots.BODY] = true end
		R.expect(bodies["Rocking Horse"] and bodies["Refrigerator"] and bodies["Washing Machine"]).toBe(true)
		srv.advance(6)
		local votes = sent("votes")
		R.expect(#votes).toBeGreaterThan(1)
		local total = 0
		for _, c in ipairs(votes[#votes].counts) do total += c.votes end
		R.expect(total).toBe(2)   -- each bot once, never for its own ride
		srv.advance(10)
		R.expect(#sent("closed")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("without rideShowBots a lone player with bots gets no show (live servers never set it)", function()
		local _, sent = results({ botLoadouts = LOADOUTS })
		R.expect(#sent("open")).toBe(0)
	end)

	R.it("the bot client votes through the screen, so a recording shows the button pressed", function()
		local driver = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/BotDriver.client.lua")
		local ui = fs.readFile("roblox/StarterGui/RideShowUI/init.client.lua")
		R.expect(driver:find('SetAttribute("RideVoteFor"', 1, true) ~= nil).toBe(true)
		R.expect(ui:find('GetAttributeChangedSignal("RideVoteFor")', 1, true) ~= nil).toBe(true)
		local runner = fs.readFile("roblox/ServerScriptService/TestHarness/Runner.lua")
		R.expect(runner:find("rideShowBots = opts.rideShowBots", 1, true) ~= nil).toBe(true)
		R.expect(runner:find("botLoadouts = opts.botLoadouts", 1, true) ~= nil).toBe(true)
		R.expect(runner:find("resultsHold = opts.resultsHold", 1, true) ~= nil).toBe(true)
		local match = fs.readFile("roblox/ServerScriptService/TestHarness/MatchHarness.lua")
		R.expect(match:find("args.resultsHold", 1, true) ~= nil).toBe(true)   -- the take reaches the show
	end)
end)

return R
