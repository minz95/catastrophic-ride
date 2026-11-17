--!nocheck
-- The lobby reel's server timeline (TestHarness/LobbyFilm, Studio scenario
-- record-lobby) played offline: the filmer wins the vote (Junk Crown, the
-- statue, the original round the waist), the crowd buys numbered copies and
-- every sale tells the filmer who bought it; nothing goes to a DataStore.
local R = require("../lib/runner")
local Server = require("../lib/server")

R.describe("Lobby film (Studio reel)", function()
	R.it("the filmer wins, the crowd buys six numbered copies, the filmer hears of each", function()
		local srv = Server.boot({ players = 1, harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 300 },
			scripts = { "ServerScriptService.GameManager", "ServerScriptService.LobbyManager", "ServerScriptService.ProgressionManager" } })
		srv.advance(1)
		local e = srv.env
		local LobbyFilm = e.requirePath("ServerScriptService.TestHarness.LobbyFilm")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local doneWith
		e.mock.task.spawn(function()
			LobbyFilm.run({ lobbyFilm = {} }, function(reason) doneWith = reason end)
		end)
		srv.advance(LobbyFilm.LENGTH + 12)
		R.expect(doneWith).toBe("lobby film")
		R.expect(LegendStore.memoryOnly).toBe(true)
		local p = srv.players[1]
		local rec = PlayerStore.get(p)
		R.expect(rec.equipped.hat).toBe("hat_junkcrown")
		local mine
		for _, l in ipairs(LegendStore.list()) do
			if l.ownerId == p.UserId then mine = l end
		end
		R.expect(mine ~= nil).toBe(true, "the filmer's listing")
		R.expect(mine.sold).toBe(#LobbyFilm.SALES)
		R.expect(rec.legend[mine.id].original).toBe(true)
		local crowd = e.workspace:FindFirstChild("FilmCrowd")
		local wearing = 0
		for _, m in ipairs(crowd:GetChildren()) do
			if m:FindFirstChild("LegendRide") then wearing += 1 end
		end
		R.expect(wearing).toBe(#LobbyFilm.SALES)
		local royalties = 0
		for _, c in ipairs(rawget(RE.LegendUpdate, "_calls") or {}) do
			if c.method == "FireClient" and c.args[2].kind == "royalty" then
				royalties += 1
				R.expect(type(c.args[2].buyer)).toBe("string")
			end
		end
		R.expect(royalties).toBe(#LobbyFilm.SALES)
		R.expect(rec.coins >= #LobbyFilm.SALES * 250).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

return R
