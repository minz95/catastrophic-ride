--!nocheck
-- Two places (2026-11-17, lobby phase 2: "a lobby place; a group on a start
-- pad goes to a new server together"). The start place is Junk Town (hub),
-- rounds run in the race place; Places.RACE = 0 keeps one place as before.
-- Teleports cannot run in Studio, so the hub, its pads and both ways of
-- travelling are played here with TeleportAsync recorded.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local RACE_ID = 555

local SCRIPTS = {
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.CharacterManager",
	"ServerScriptService.LobbyManager",
	"ServerScriptService.DepartureManager",
}

R.describe("place modes (Shared/Places)", function()
	local env = Loader.boot()
	local Places = env.requirePath("ReplicatedStorage.Shared.Places")

	R.it("one place while RACE is 0; with it, the start place is the hub and the race place plays rounds", function()
		local saved = Places.RACE
		Places.RACE = 0
		R.expect(Places.mode(Places.HUB, false, false, false)).toBe("single")
		Places.RACE = RACE_ID
		R.expect(Places.mode(Places.HUB, false, false, false)).toBe("hub")
		R.expect(Places.mode(RACE_ID, false, false, false)).toBe("race")
		-- Studio cannot teleport: rounds there, the hub only on request (HubTest)
		R.expect(Places.mode(Places.HUB, true, false, false)).toBe("race")
		R.expect(Places.mode(Places.HUB, true, true, false)).toBe("hub")
		-- a test harness always plays rounds
		R.expect(Places.mode(Places.HUB, false, false, true)).toBe("race")
		Places.RACE = saved
		R.expect(Places.RACE).toBe(0)   -- shipped off until the race place exists
	end)
end)

R.describe("start pads (Shared/Departure)", function()
	local env = Loader.boot()
	local D = env.requirePath("ReplicatedStorage.Shared.Departure")

	R.it("the clock starts with the first on the pad, stops when it empties, and the whole pad leaves together", function()
		local s = D.new()
		local left, view = D.step(s, { race = { 1 } }, 100, 8, 10)
		R.expect(#left).toBe(0)
		R.expect(view.race.leavesAt).toBe(108)
		left, view = D.step(s, { race = { 1, 2 } }, 104, 8, 10)
		R.expect(view.race.leavesAt).toBe(108)   -- a second one does not restart it
		R.expect(view.race.count).toBe(2)
		left, view = D.step(s, { race = {} }, 105, 8, 10)
		R.expect(view.race.leavesAt).toBe(nil)
		D.step(s, { race = { 2 } }, 106, 8, 10)
		left = D.step(s, { race = { 2, 3 } }, 113.9, 8, 10)
		R.expect(#left).toBe(0)
		left, view = D.step(s, { race = { 2, 3 } }, 114, 8, 10)
		R.expect(#left).toBe(1)
		R.expect(left[1].kind).toBe("public")
		R.expect(table.concat(left[1].ids, ",")).toBe("2,3")
		R.expect(view.race.count).toBe(0)
	end)

	R.it("a pad holds a server's worth; those left over start a new clock", function()
		local s = D.new()
		local ids = {}
		for i = 1, 12 do ids[i] = i end
		D.step(s, { party1 = ids }, 0, 8, 10)
		local left, view = D.step(s, { party1 = ids }, 8, 8, 10)
		R.expect(#left[1].ids).toBe(10)
		R.expect(left[1].kind).toBe("private")
		R.expect(view.party1.count).toBe(2)
		R.expect(view.party1.leavesAt).toBe(16)
	end)
end)

R.describe("the hub place", function()
	local function boot(opts)
		local calls = {}
		local srv = Server.boot({ live = true, players = opts.players or 3, scripts = SCRIPTS, swallowErrors = true,
			setup = function(env, Mock)
				env.requirePath("ReplicatedStorage.Shared.Places").RACE = RACE_ID
				Mock.props(env.game).PlaceId = opts.placeId
				local ts = env.game:GetService("TeleportService")
				rawset(ts, "TeleportAsync", function(_, placeId, players, options)
					table.insert(calls, { placeId = placeId, players = players, options = options })
					if opts.fail then error("teleport failed") end
					return {}
				end)
			end })
		srv.advance(1)
		local hub = srv.env.workspace:FindFirstChild("LobbyHub")
		return srv, hub, calls
	end
	local function standOn(p, pad, dx)
		local root = p.Character:FindFirstChild("HumanoidRootPart")
		root.CFrame = CFrame.new(pad.Position + Vector3.new(dx or 0, 3, 0))
	end
	local function off(p)
		p.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(2600, 203, 30)
	end

	R.it("plays no rounds: Junk Town with three start pads where the junk rides stood, the TV points at them", function()
		local srv, hub = boot({ placeId = 74883519312765 })
		local RS = srv.env.game:GetService("ReplicatedStorage")
		R.expect(RS:GetAttribute("PlaceMode")).toBe("hub")
		srv.advance(120)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		R.expect(RS:GetAttribute("PhaseEndsAt")).toBe(nil)
		local L = srv.env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		local D = srv.env.requirePath("ReplicatedStorage.Shared.Departure")
		for i, d in ipairs(D.PADS) do
			local pad = hub:FindFirstChild("Depart_" .. d.id)
			R.expect(pad ~= nil).toBe(true, d.id)
			R.expect((pad.Position - L.SHOWCASE[i]).Magnitude < 1).toBe(true, d.id)
			R.expect(pad.CanCollide).toBe(true)
		end
		local live = hub:FindFirstChild("Live")
		for _, c in ipairs(live:GetChildren()) do
			R.expect(c.Name:sub(1, 9) ~= "Showcase_").toBe(true, c.Name)
		end
		local track = hub:FindFirstChild("Screen"):FindFirstChild("Track", true)
		R.expect(track.Text).toBe("🏁 RACE PADS")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a group on a private pad leaves together for a new server; one on the race pad joins a race; nobody is sent twice", function()
		local srv, hub, calls = boot({ placeId = 74883519312765 })
		local p1, p2, p3 = srv.players[1], srv.players[2], srv.players[3]
		local party = hub:FindFirstChild("Depart_party1")
		standOn(p1, party, -1.5)
		srv.advance(3)
		standOn(p2, party, 1.5)
		standOn(p3, hub:FindFirstChild("Depart_race"))
		srv.advance(1)
		R.expect(p1:GetAttribute("DepartPad")).toBe("party1")
		R.expect(type(p2:GetAttribute("DepartAt"))).toBe("number")
		local status = party:FindFirstChild("Status", true)
		R.expect(status.Text:find("2 on pad", 1, true) ~= nil).toBe(true, status.Text)
		R.expect(#calls).toBe(0)
		srv.advance(5)
		-- the party: one call, both players, a reserved server, the party named
		local partyCall, raceCall
		for _, c in ipairs(calls) do
			if #c.players == 2 then partyCall = c else raceCall = c end
		end
		R.expect(partyCall ~= nil).toBe(true, "party sent")
		R.expect(partyCall.placeId).toBe(RACE_ID)
		R.expect(partyCall.options.ShouldReserveServer).toBe(true)
		R.expect(#partyCall.options:GetTeleportData().party).toBe(2)
		R.expect(raceCall).toBe(nil)   -- p3 stepped on later: still counting
		srv.advance(4)
		R.expect(#calls).toBe(2)
		local race = calls[2]
		R.expect(race.players[1]).toBe(p3)
		R.expect(race.options.ShouldReserveServer ~= true).toBe(true)
		-- still standing there while the teleport loads: not sent again
		srv.advance(10)
		R.expect(#calls).toBe(2)
		R.expect(p1:GetAttribute("DepartPad")).toBe(nil)
		R.expect(#srv.Telemetry.events("depart")).toBe(2)
	end)

	R.it("stepping off stops the clock; ▶ PLAY puts you on the race pad", function()
		local srv, hub, calls = boot({ placeId = 74883519312765 })
		local p1 = srv.players[1]
		local pad = hub:FindFirstChild("Depart_race")
		standOn(p1, pad)
		srv.advance(5)
		off(p1)
		srv.advance(10)
		R.expect(#calls).toBe(0)
		R.expect(p1:GetAttribute("DepartPad")).toBe(nil)
		R.expect(pad:FindFirstChild("Status", true).Text).toBe("step on!")
		local res = srv.mock.invoke(srv.remote("PlaceAction"), p1, "play")
		R.expect(res).toBe("ok")
		local root = p1.Character:FindFirstChild("HumanoidRootPart")
		local d = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z).Magnitude
		R.expect(d <= 5).toBe(true, tostring(d))
		srv.advance(9)
		R.expect(#calls).toBe(1)
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), srv.players[2], "hub")).toBe("denied: not here")
	end)

	R.it("a failed teleport is told to the player, who can step on again", function()
		local srv, hub, calls = boot({ placeId = 74883519312765, players = 1, fail = true })
		local p1 = srv.players[1]
		standOn(p1, hub:FindFirstChild("Depart_party2"))
		srv.advance(9)
		R.expect(#calls).toBe(1)
		local told = nil
		for _, c in ipairs(rawget(srv.remote("TravelUpdate"), "_calls") or {}) do
			if c.method == "FireClient" and c.args[1] == p1 and c.args[2].kind == "failed" then told = c.args[2] end
		end
		R.expect(told ~= nil).toBe(true, "failure told")
		srv.advance(9)
		R.expect(#calls).toBe(2)   -- still on the pad: tried again
	end)
end)

R.describe("the race place", function()
	R.it("plays rounds; ← JUNK TOWN sends you back to the hub", function()
		local calls = {}
		local srv = Server.boot({ live = true, players = 1, swallowErrors = true,
			scripts = { "ServerScriptService.GameBootstrap", "ServerScriptService.DepartureManager" },
			setup = function(env, Mock)
				env.requirePath("ReplicatedStorage.Shared.Places").RACE = RACE_ID
				Mock.props(env.game).PlaceId = RACE_ID
				rawset(env.game:GetService("TeleportService"), "TeleportAsync", function(_, placeId, players, options)
					table.insert(calls, { placeId = placeId, players = players, options = options })
				end)
			end })
		srv.advance(30)
		local RS = srv.env.game:GetService("ReplicatedStorage")
		R.expect(RS:GetAttribute("PlaceMode")).toBe("race")
		R.expect(srv.GameManager.getPhase() ~= "LOBBY").toBe(true, "a round started")
		local p1 = srv.players[1]
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p1, "play")).toBe("denied: not here")
		srv.advance(2)
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p1, "hub")).toBe("ok")
		R.expect(#calls).toBe(1)
		R.expect(calls[1].placeId).toBe(74883519312765)
		R.expect(calls[1].players[1]).toBe(p1)
	end)

	R.it("with one place (RACE 0) nothing changes: no pads, rounds count down, no travel", function()
		local srv = Server.boot({ live = true, players = 1, swallowErrors = true,
			scripts = { "ServerScriptService.GameBootstrap", "ServerScriptService.LobbyManager", "ServerScriptService.DepartureManager" } })
		srv.advance(1)
		R.expect(srv.env.game:GetService("ReplicatedStorage"):GetAttribute("PlaceMode")).toBe("single")
		R.expect(srv.env.workspace:FindFirstChild("LobbyHub"):FindFirstChild("Depart_race")).toBe(nil)
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), srv.players[1], "hub")).toBe("denied: not here")
		srv.advance(15)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
	end)
end)

return R
