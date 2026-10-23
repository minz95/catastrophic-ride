--!nocheck
-- The live lobby (no harness, not Studio): a lone player starts after
-- LOBBY.MAX_WAIT s, MIN_TO_START players after LOBBY.FILL_SECONDS, an empty
-- server waits; the countdown is PhaseEndsAt. RESULTS shows its end time too.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local function live(n)
	local srv = Server.boot({
		live = true, players = n,
		scripts = { "ServerScriptService.MapBuilders.ForestMapBuilder", "ServerScriptService.GameBootstrap" },
	})
	srv.advance(3)   -- HarnessConfig polls ~2 s, finds nothing: live
	local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
	local RS = srv.env.game:GetService("ReplicatedStorage")
	local function left() return (RS:GetAttribute("PhaseEndsAt") or 0) - srv.env.workspace:GetServerTimeNow() end
	return srv, C, left
end

R.describe("live lobby", function()
	R.it("testing switches are off for release", function()
		local srv, C = live(0)
		R.expect(C.SOLO_TEST_MODE).toBe(false)
		R.expect(C.MIN_TO_START >= 2).toBe(true)
		R.expect(srv.GameManager.getHarness()).toBe(nil)
	end)

	R.it("a lone player waits LOBBY.MAX_WAIT s with a visible countdown, then plays solo", function()
		local srv, C, left = live(1)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		R.expect(left()).toBeNear(C.LOBBY.MAX_WAIT - 3, 2)   -- 3 s of boot already passed
		srv.advance(C.LOBBY.MAX_WAIT)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
	end)

	R.it("once a second player arrives, the countdown drops to LOBBY.FILL_SECONDS", function()
		local srv, C, left = live(1)
		srv.advance(5)
		srv.mock.addPlayer("Friend", 2002, Vector3.new(0, 3, 0))
		srv.advance(1)
		R.expect(left() <= C.LOBBY.FILL_SECONDS).toBe(true)
		srv.advance(C.LOBBY.FILL_SECONDS)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
	end)

	R.it("an empty server does not start a round", function()
		local srv, C = live(0)
		srv.advance(C.LOBBY.MAX_WAIT * 3)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		srv.mock.addPlayer("First", 3003, Vector3.new(0, 3, 0))
		srv.advance(C.LOBBY.MAX_WAIT + 2)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
	end)
end)
