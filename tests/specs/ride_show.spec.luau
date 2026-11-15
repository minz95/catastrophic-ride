--!nocheck
-- Playtest 2026-11-15: friends want to show their rides off, compare them and
-- vote for the funniest. RESULTS opens with a ride show when two or more
-- players raced (RideShowManager, Shared/RideVote, StarterGui/RideShowUI).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

R.describe("ride vote rules", function()
	local env = Loader.boot()
	local V = env.requirePath("ReplicatedStorage.Shared.RideVote")
	R.it("no vote for your own ride or a ride not on show; the most votes win, ties all win", function()
		local votes, on = {}, { [1] = true, [2] = true, [3] = true }
		R.expect(V.cast(votes, on, 1, 1)).toBe("own ride")
		R.expect(V.cast(votes, on, 1, 9)).toBe("no such ride")
		R.expect(V.cast(votes, on, 1, "2")).toBe("no such ride")
		R.expect(V.cast(votes, on, 1, 2)).toBe("ok")
		R.expect(V.cast(votes, on, 1, 2)).toBe("same")
		R.expect(V.cast(votes, on, 3, 2)).toBe("ok")
		R.expect(V.cast(votes, on, 2, 3)).toBe("ok")
		local w, n = V.winners(votes)
		R.expect(#w).toBe(1); R.expect(w[1]).toBe(2); R.expect(n).toBe(2)
		R.expect(V.cast(votes, on, 1, 3)).toBe("ok")   -- a changed mind: one vote each now
		w = V.winners(votes)
		R.expect(#w).toBe(1); R.expect(w[1]).toBe(3)
		R.expect(#V.winners({})).toBe(0)
	end)
end)

local function results(players)
	local srv = Server.boot({
		players = players,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.ProgressionManager",
			"ServerScriptService.RideShowManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = players, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	for i, p in ipairs(srv.players) do
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		stats.slotAssignments = { BODY = i == 1 and "Log" or "Pizza" }
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), stats.slotAssignments)
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
	end
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RACING", "not racing")
	return srv, e.requirePath("ReplicatedStorage.RemoteEvents"), e.requirePath("ReplicatedStorage.Shared.Constants")
end

local function sent(RE, kind)
	local out = {}
	for _, c in ipairs(rawget(RE.RideShow, "_calls") or {}) do
		if c.args[1] == kind then table.insert(out, c.args[2]) end
	end
	return out
end

R.describe("ride show at RESULTS", function()
	R.it("two players: their rides go on show, votes count, the winner gets the coins", function()
		local srv, RE, C = results(2)
		srv.GameManager.raceComplete({})
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local open = sent(RE, "open")
		R.expect(#open).toBe(1)
		R.expect(#open[1].entries).toBe(2)
		local a, b = srv.players[1], srv.players[2]
		for _, entry in ipairs(open[1].entries) do
			R.expect(entry.model ~= nil and entry.model.Parent ~= nil).toBe(true)
			R.expect(type(entry.slots.BODY)).toBe("string")
		end
		local PlayerStore = srv.env.requirePath("ServerScriptService.Modules.PlayerStore")
		local before = PlayerStore.get(b).coins
		RE.VoteRide.OnServerEvent:Fire(b, b.UserId)   -- own ride: nothing
		RE.VoteRide.OnServerEvent:Fire(a, b.UserId)
		R.expect(#sent(RE, "votes")).toBe(1)
		srv.advance(C.RIDE_SHOW.SECONDS + 0.5)
		local closed = sent(RE, "closed")
		R.expect(#closed).toBe(1)
		R.expect(closed[1].winners[1]).toBe(b.UserId)
		R.expect(PlayerStore.get(b).coins - before).toBe(C.RIDE_SHOW.COINS)
		R.expect(#srv.Telemetry.events("ride_vote")).toBe(1)
		-- votes after the show closed count for nothing
		RE.VoteRide.OnServerEvent:Fire(b, a.UserId)
		R.expect(#srv.Telemetry.events("ride_vote")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a lone player gets no show (nobody to vote)", function()
		local srv, RE = results(1)
		srv.GameManager.raceComplete({})
		srv.advance(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		R.expect(#sent(RE, "open")).toBe(0)
	end)
end)

R.describe("ride show and snapshot on screen", function()
	R.it("the show draws each ride with its grade and bars, votes, and has 📸; the showroom has 📸 too", function()
		local ui = fs.readFile("roblox/StarterGui/RideShowUI/init.client.lua")
		for _, needle in ipairs({ "RideCard.view(viewSlot", "RideRating.rate(", "RemoteEvents.VoteRide:FireServer",
			"if mine then", "Snapshot.card(rides", "🏆 FUNNIEST RIDE" }) do
			R.expect(ui:find(needle, 1, true) ~= nil).toBe(true, needle)
		end
		local craft = fs.readFile("roblox/StarterGui/CraftingUI/init.client.lua")
		R.expect(craft:find('Snapshot.card({ {', 1, true) ~= nil).toBe(true)
		local snap = fs.readFile("roblox/ReplicatedStorage/Shared/Snapshot.lua")
		R.expect(snap:find("CaptureScreenshot(", 1, true) ~= nil).toBe(true)
		R.expect(snap:find("PromptShareCapture(", 1, true) ~= nil).toBe(true)
		R.expect(snap:find("PromptSaveCapturesToGallery(", 1, true) ~= nil).toBe(true)
	end)

	R.it("RideCard lists the items BODY first", function()
		local env = Loader.boot()
		local RideCard = env.requirePath("ReplicatedStorage.Shared.RideCard")
		R.expect(RideCard.items({ SPECIAL = "Pizza", BODY = "Piano", ENGINE = "Rocket" })).toBe("Piano + Rocket + Pizza")
		R.expect(RideCard.items({})).toBe("Plain junk")
	end)
end)

return R
