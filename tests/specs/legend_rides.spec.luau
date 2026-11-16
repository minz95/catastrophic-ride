--!nocheck
-- Legend Rides (2026-11-17: "the vote winner's own car in the shop, pricey;
-- others envy it, the winner got it for free"): Shared/LegendRides rules,
-- Modules/LegendStore (shared listings, sold counts, royalties),
-- Modules/LegendShop (buy with coins or Robux, wear round the waist).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

R.describe("Legend Rides rules", function()
	local env = Loader.boot()
	local LR = env.requirePath("ReplicatedStorage.Shared.LegendRides")
	local C = env.requirePath("ReplicatedStorage.Shared.Constants")
	local P = env.requirePath("ReplicatedStorage.Shared.Progression")
	local e = { userId = 7, name = "Ann", biome = "FOREST", slots = { BODY = "Toilet", ENGINE = "Rocket" }, votes = 3, look = {} }

	R.it("a listing: the owner's name and BODY, LIMIT copies for DAYS days", function()
		local l = LR.listing(e, 1000)
		R.expect(l.title).toBe("Ann's Toilet")
		R.expect(l.limit).toBe(C.LEGEND.LIMIT)
		R.expect(l.endsAt).toBe(1000 + C.LEGEND.DAYS * 86400)
	end)

	R.it("the owner cannot buy their own; nobody buys one sold out or ended; coins are checked", function()
		local l = LR.listing(e, 1000)
		local rec = P.newRecord()
		rec.coins = C.LEGEND.COINS
		R.expect(LR.canBuy(l, rec, 7, 1001, true)).toBe("denied: owned")
		R.expect(LR.canBuy(l, rec, 8, 1001, true)).toBe("ok")
		R.expect(LR.canBuy(l, rec, 8, l.endsAt, true)).toBe("denied: ended")
		rec.coins = C.LEGEND.COINS - 1
		R.expect(LR.canBuy(l, rec, 8, 1001, true)).toBe("denied: coins")
		R.expect(LR.canBuy(l, rec, 8, 1001, false)).toBe("ok")   -- Robux
		l.sold = l.limit
		R.expect(LR.canBuy(l, rec, 8, 1001, false)).toBe("denied: sold out")
	end)

	R.it("take counts a copy only while one is left", function()
		local list = LR.add({}, LR.listing(e, 1000))
		local id = list[1].id
		for _ = 1, C.LEGEND.LIMIT do
			local _, res = LR.take(list, id, 1001)
			R.expect(res).toBe("ok")
		end
		local _, res = LR.take(list, id, 1001)
		R.expect(res).toBe("denied: sold out")
		R.expect(#LR.active(list, 1001)).toBe(0)
	end)
end)

R.describe("Legend Rides in a server", function()
	local function boot(players)
		local srv = Server.boot({
			players = players,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.ShopManager",
				"ServerScriptService.LegendManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = players, lobbyDelay = 0,
				durations = { FARMING = 60, CRAFTING = 30 } },
		})
		srv.advance(0.5)
		return srv
	end

	R.it("the winner's ride goes on sale (picture built), the winner owns the original", function()
		local srv = boot(2)
		local e = srv.env
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local p1 = srv.players[1]
		local l = LegendShop.listWinner({ userId = p1.UserId, name = "Ann", biome = "FOREST",
			slots = { BODY = "Shopping Cart", ENGINE = "Rocket" }, votes = 2, look = {}, at = 5 })
		srv.advance(0.2)
		local rec = PlayerStore.get(p1)
		R.expect(rec.legend[l.id].original).toBe(true)
		local folder = e.game:GetService("ReplicatedStorage"):FindFirstChild("LegendRides")
		R.expect(folder and folder:FindFirstChild(l.id) ~= nil).toBe(true)
		-- every server reads it from the store
		R.expect(#srv.mock.dataStores[e.requirePath("ServerScriptService.Modules.LegendStore").NAME].listings).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("buying with coins: the coins go, the ride is yours and on, the owner gets the royalty", function()
		local srv = boot(2)
		local e = srv.env
		local C = e.requirePath("ReplicatedStorage.Shared.Constants")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local owner, buyer = srv.players[1], srv.players[2]
		local l = LegendShop.listWinner({ userId = owner.UserId, name = "Ann", biome = "FOREST",
			slots = { BODY = "Shopping Cart" }, votes = 2, look = {}, at = 5 })
		local oRec, bRec = PlayerStore.get(owner), PlayerStore.get(buyer)
		oRec.coins, bRec.coins = 0, C.LEGEND.COINS + 10
		local function act(player, ...) return (srv.mock.invoke(RE.ShopAction, player, ...)) end
		R.expect(act(owner, "legend_buy", l.id).result).toBe("denied: owned")
		local res = act(buyer, "legend_buy", l.id)
		R.expect(res.result).toBe("ok")
		R.expect(bRec.coins).toBe(10)
		R.expect(bRec.legend[l.id].original).toBe(false)
		-- numbered: the first copy sold is #1/50, the winner's is the original
		R.expect(bRec.legend[l.id].serial).toBe(1)
		local LR = e.requirePath("ReplicatedStorage.Shared.LegendRides")
		R.expect(LR.tag(bRec.legend[l.id])).toBe("#1/" .. C.LEGEND.LIMIT)
		R.expect(LR.tag(oRec.legend[l.id])).toBe("⭐ ORIGINAL")
		R.expect(bRec.legendOn).toBe(l.id)
		R.expect(oRec.coins).toBe(C.LEGEND.ROYALTY)
		R.expect(res.state.legend.listings[1].sold).toBe(1)
		R.expect(act(buyer, "legend_buy", l.id).result).toBe("denied: owned")
		srv.advance(0.2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("an owner who is away gets the royalty when they come back", function()
		local srv = boot(1)
		local e = srv.env
		local C = e.requirePath("ReplicatedStorage.Shared.Constants")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local p = srv.players[1]
		LegendStore.royalty(p.UserId, C.LEGEND.ROYALTY, "Ann's Toilet")
		LegendStore.royalty(p.UserId, C.LEGEND.ROYALTY, "Ann's Toilet")
		local rec = PlayerStore.get(p)
		local before = rec.coins
		LegendShop.claimFor(p)
		R.expect(rec.coins - before).toBe(2 * C.LEGEND.ROYALTY)
		LegendShop.claimFor(p)   -- once
		R.expect(rec.coins - before).toBe(2 * C.LEGEND.ROYALTY)
	end)

	R.it("Robux: the picked ride once a copy is left, else its price in coins; a receipt counts once", function()
		-- a live-like session (records from the DataStore), as the coin-pack spec does
		local e = Loader.boot()
		local C = e.requirePath("ReplicatedStorage.Shared.Constants")
		local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local Products = e.requirePath("ReplicatedStorage.Shared.Products")
		local Shop = e.requirePath("ServerScriptService.Modules.Shop")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		local D = require("@lune/roblox").Enum.ProductPurchaseDecision
		Products.LEGEND.id = 777
		local prompts = 0
		e.game:GetService("MarketplaceService").PromptProductPurchase = function() prompts += 1 end
		local owner, buyer = e.mock.addPlayer("Ann", 501), e.mock.addPlayer("Bo", 502)
		Store.load(owner)
		local bRec = Store.load(buyer)
		local l = LegendShop.listWinner({ userId = 501, name = "Ann", biome = "FOREST",
			slots = { BODY = "Shopping Cart" }, votes = 2, look = {}, at = 5 })
		R.expect(Shop.handle(buyer, "legend_robux", l.id).result).toBe("ok")
		R.expect(prompts).toBe(1)
		local function receipt(pid)
			local res
			e.mock.task.spawn(function() res = Shop.processReceipt({ PlayerId = 502, ProductId = 777, PurchaseId = pid }) end)
			e.mock.advance(1)
			return res
		end
		R.expect(receipt("p1")).toBe(D.PurchaseGranted)
		R.expect(bRec.legend[l.id] ~= nil).toBe(true)
		R.expect(receipt("p1")).toBe(D.PurchaseGranted)
		R.expect(LegendStore.find(l.id).sold).toBe(1)   -- once
		-- sold out between the prompt and the payment: its price in coins
		local l2 = LegendShop.listWinner({ userId = 501, name = "Ann", biome = "FOREST",
			slots = { BODY = "Rocket" }, votes = 2, look = {}, at = 6 })
		R.expect(Shop.handle(buyer, "legend_robux", l2.id).result).toBe("ok")
		local stored = e.mock.dataStores[LegendStore.NAME].listings
		for _, x in ipairs(stored) do if x.id == l2.id then x.sold = x.limit end end
		LegendStore.refresh()
		local coins = bRec.coins
		R.expect(receipt("p2")).toBe(D.PurchaseGranted)
		R.expect(bRec.coins - coins).toBe(C.LEGEND.COINS)
		R.expect(bRec.legend[l2.id]).toBe(nil)
		Products.LEGEND.id = 0
	end)

	R.it("worn round the waist outside races: massless, touching nothing, the seat disabled; off for the race", function()
		local srv = boot(1)
		local e = srv.env
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local p = srv.players[1]
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			root = e.mock.Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = p.Character
		end
		local l = LegendShop.listWinner({ userId = p.UserId, name = "Ann", biome = "FOREST",
			slots = { BODY = "Shopping Cart" }, votes = 2, look = {}, at = 5 })
		local rec = PlayerStore.get(p)
		rec.legendOn = l.id
		LegendShop.refresh(p)
		local worn = p.Character:FindFirstChild(LegendShop.WORN)
		R.expect(worn ~= nil).toBe(true)
		local bad = {}
		for _, d in ipairs(worn:GetDescendants()) do
			if d:IsA("BasePart") and (d.CanCollide or d.CanTouch or d.CanQuery or not d.Massless or d.Anchored) then
				table.insert(bad, d.Name)
			end
			if d:IsA("VehicleSeat") and not d.Disabled then table.insert(bad, "seat on") end
		end
		R.expect(bad).toBeEmpty("worn ride parts")
		local tag = worn:FindFirstChild("LegendTag", true)
		R.expect(tag ~= nil).toBe(true)
		R.expect(tag:FindFirstChildWhichIsA("TextLabel").Text).toBe("⭐ ORIGINAL")
		local GM = e.requirePath("ServerScriptService.GameManager")
		local real = GM.getPhase
		GM.getPhase = function() return "RACING" end
		LegendShop.refresh(p)
		GM.getPhase = real
		R.expect(p.Character:FindFirstChild(LegendShop.WORN)).toBe(nil)
	end)

	R.it("the shop screen has the Legend tab and the notices", function()
		local ui = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		for _, needle in ipairs({ 'legend = "🚗 Legend"', 'act("legend_buy", l.id)', 'act("legend_robux", l.id)',
			'act("legend_ride", l.id)', "RemoteEvents.LegendUpdate.OnClientEvent" }) do
			R.expect(ui:find(needle, 1, true) ~= nil).toBe(true, needle)
		end
	end)
end)

return R
