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

	R.it("the toilet ad: the sets, the statue of the filmer's ride, the friend buys a copy, the lights come back", function()
		local srv = Server.boot({ players = 1, harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 300 },
			scripts = { "ServerScriptService.GameManager", "ServerScriptService.LobbyManager", "ServerScriptService.ProgressionManager" } })
		srv.advance(1)
		local e = srv.env
		local LobbyFilm = e.requirePath("ServerScriptService.TestHarness.LobbyFilm")
		local ToiletAd = e.requirePath("ServerScriptService.TestHarness.ToiletAd")
		local Lighting = e.game:GetService("Lighting")
		Lighting.ClockTime = 14
		local doneWith
		e.mock.task.spawn(function()
			LobbyFilm.run({ lobbyFilm = { story = "toilet" } }, function(reason) doneWith = reason end)
		end)
		srv.advance(12 + 30)
		R.expect(Lighting.ClockTime).toBe(0)   -- the ad studio, lights down
		srv.advance(ToiletAd.LENGTH)
		R.expect(doneWith).toBe("toilet ad")
		R.expect(Lighting.ClockTime).toBe(14)
		local RS = e.game:GetService("ReplicatedStorage")
		R.expect(RS:GetAttribute("FilmStory")).toBe("toilet")
		local sets = e.workspace:FindFirstChild("FilmSets")
		R.expect(sets:FindFirstChild("Hangout") ~= nil and sets:FindFirstChild("AdStudio") ~= nil).toBe(true)
		local p = srv.players[1]
		R.expect(p.Character:FindFirstChild("LegendRide") ~= nil).toBe(true, "the filmer wears the original")
		local friend = sets:FindFirstChild(ToiletAd.FRIEND.name)
		R.expect(friend and friend:FindFirstChild("LegendRide") ~= nil).toBe(true, "the friend wears a copy")
		local winner = e.game:GetService("ReplicatedStorage"):FindFirstChild("HallOfFame"):FindFirstChild("Winner")
		R.expect(winner:GetAttribute("UserId")).toBe(p.UserId)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the used-car ad: the lot full, JUST IN by the entrance, Hank by it; the offers come to nothing, the new duck is bought for 1,200 and worn", function()
		local srv = Server.boot({ players = 1, harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 300 },
			scripts = { "ServerScriptService.GameManager", "ServerScriptService.ShopManager", "ServerScriptService.LegendManager",
				"ServerScriptService.LobbyManager", "ServerScriptService.ProgressionManager" } })
		srv.advance(1)
		local e = srv.env
		local LobbyFilm = e.requirePath("ServerScriptService.TestHarness.LobbyFilm")
		local UsedCarAd = e.requirePath("ServerScriptService.TestHarness.UsedCarAd")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local L = e.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		local doneWith
		e.mock.task.spawn(function()
			LobbyFilm.run({ lobbyFilm = { story = "usedcar" } }, function(reason) doneWith = reason end)
		end)
		srv.advance(12 + 20)
		R.expect(LegendStore.memoryOnly).toBe(true)
		local hub = e.workspace:FindFirstChild("LobbyHub")
		local live = hub:FindFirstChild("Live")
		local used = 0
		for _, c in ipairs(live:GetChildren()) do if c.Name:sub(1, 5) == "Used_" then used += 1 end end
		R.expect(used).toBe(#UsedCarAd.OTHERS + 1)
		local first = live:FindFirstChild("Used_1")
		local l = LegendStore.find(first:GetAttribute("Legend"))
		R.expect(l.ownerName).toBe(UsedCarAd.JUST_IN.name)
		local hank = hub:FindFirstChild("Npc_hank")
		local want = L.ORIGIN + UsedCarAd.HANK_AT
		local hp = hank:FindFirstChild("HumanoidRootPart").Position
		R.expect(math.abs(hp.X - want.X) + math.abs(hp.Z - want.Z) < 0.5).toBe(true, "Hank by the car")
		R.expect(e.game:GetService("ReplicatedStorage"):GetAttribute("FilmDuck") ~= nil).toBe(true)
		srv.advance(UsedCarAd.LENGTH)
		R.expect(doneWith).toBe("usedcar ad")
		local p = srv.players[1]
		local rec = PlayerStore.get(p)
		R.expect(rec.cars[UsedCarAd.DUCK]).toBe(true)
		R.expect(rec.coins).toBe(100)
		local worn = p.Character:FindFirstChild("LegendRide")
		R.expect(worn and worn:GetAttribute("LegendId")).toBe("car:" .. UsedCarAd.DUCK)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

return R
