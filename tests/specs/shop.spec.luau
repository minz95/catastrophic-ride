--!nocheck
-- The cosmetics shop: rules (Shared/Cosmetics), looks on the real vehicle
-- (VehicleBuilder: paint and trail, handling unchanged), the server handler
-- (Modules/Shop) and Robux coin packs (ProcessReceipt: once per purchase,
-- only after the grant is saved).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local env = Loader.boot()
local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")
local Progression = env.requirePath("ReplicatedStorage.Shared.Progression")
local C = env.requirePath("ReplicatedStorage.Shared.Constants")

local function rich(coins, level)
	local rec = Progression.newRecord()
	rec.coins, rec.level = coins, level or 1
	return rec
end

R.describe("Cosmetics rules", function()
	R.it("the catalogue: unique ids, a free default first in each category, every other item has a look and a price", function()
		local seen, bad = {}, {}
		for _, cat in ipairs(Cosmetics.CATEGORIES) do
			local list = Cosmetics.ITEMS[cat]
			if list[1].price ~= 0 then table.insert(bad, cat .. ": default not free") end
			for i, it in ipairs(list) do
				if cat == "taunt" and not (it.emoji and it.text) then table.insert(bad, it.id .. ": no bubble") end
				if seen[it.id] then table.insert(bad, "duplicate " .. it.id) end
				seen[it.id] = true
				if i > 1 then
					if it.price <= 0 then table.insert(bad, it.id .. ": no price") end
					if cat == "paint" and not (it.body and it.accent) then table.insert(bad, it.id .. ": no colours") end
					if cat == "trail" and not (it.colors or it.rainbow) then table.insert(bad, it.id .. ": no colours") end
					if cat == "ride" and not (it.body and it.accent and it.fx and it.trail) then table.insert(bad, it.id .. ": incomplete ride") end
					if cat == "move" and not it.style then table.insert(bad, it.id .. ": no style") end
					if cat == "gadget" and not (it.gadget and C.GADGETS[it.gadget]) then table.insert(bad, it.id .. ": unknown gadget") end
					if cat == "trick" and not (it.trick and C.RACE_TRICKS[it.trick]) then table.insert(bad, it.id .. ": unknown trick") end
				end
			end
		end
		R.expect(bad).toBeEmpty("catalogue problems")
	end)

	R.it("buying takes the coins, owns and equips; refused for too few coins, too low a level, owned or unknown", function()
		local rec = rich(1000, 10)
		R.expect(Cosmetics.buy(rec, "paint_midnight")).toBe("ok")
		R.expect(rec.coins).toBe(1000 - Cosmetics.get("paint_midnight").price)
		R.expect(rec.equipped.paint).toBe("paint_midnight")
		R.expect(Cosmetics.buy(rec, "paint_midnight")).toBe("denied: owned")
		R.expect(Cosmetics.buy(rec, "nope")).toBe("denied: unknown item")
		local poor = rich(10, 10)
		R.expect(Cosmetics.buy(poor, "paint_lime")).toBe("denied: coins")
		R.expect(poor.coins).toBe(10)
		local low = rich(5000, 1)
		R.expect(Cosmetics.buy(low, "paint_gold")).toBe("denied: level 8")
		R.expect(low.owned.paint_gold).toBe(nil)
	end)

	R.it("equip needs the item (defaults are always owned); defaults add no look", function()
		local rec = rich(0)
		R.expect(Cosmetics.equip(rec, "trail_fire")).toBe("denied: not owned")
		R.expect(Cosmetics.equip(rec, "trail_none")).toBe("ok")
		R.expect(next(Cosmetics.look(rec.equipped))).toBe(nil)
		rec.owned.trail_fire = true
		R.expect(Cosmetics.equip(rec, "trail_fire")).toBe("ok")
		R.expect(Cosmetics.look(rec.equipped).trail.id).toBe("trail_fire")
		R.expect(Cosmetics.look({ paint = "retired_item" }).paint).toBe(nil)
	end)
end)

R.describe("cosmetics on the vehicle (VehicleBuilder)", function()
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")

	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": paint recolours the body, the trail is attached, and the chassis (mass, size, collision) is unchanged", function()
			local stats = VehicleStats.calculate(nil, nil, nil, biome)
			local plain = VehicleBuilder.build(stats, biome, CFrame.new(), {})
			local look = { paint = Cosmetics.get("paint_lime"), trail = Cosmetics.get("trail_rainbow") }
			local fancy = VehicleBuilder.build(stats, biome, CFrame.new(), {}, look)
			R.expect(fancy.PrimaryPart.Size).toBe(plain.PrimaryPart.Size)
			R.expect(fancy.PrimaryPart.CanCollide).toBe(plain.PrimaryPart.CanCollide)
			local lime = 0
			for _, d in ipairs(fancy:GetDescendants()) do
				if d:IsA("BasePart") and d.Color == look.paint.body then lime += 1 end
				if d:IsA("BasePart") and d ~= fancy.PrimaryPart then
					R.expect(d.Massless or not d.CanCollide).toBe(true)
				end
			end
			R.expect(lime).toBeGreaterThan(0)
			local trail = fancy.PrimaryPart:FindFirstChild("CosmeticTrail")
			R.expect(trail ~= nil).toBe(true)
			R.expect(trail.Attachment0.Parent).toBe(fancy.PrimaryPart)
			R.expect(plain.PrimaryPart:FindFirstChild("CosmeticTrail")).toBe(nil)
			local seatA = plain:FindFirstChildWhichIsA("VehicleSeat", true)
			local seatB = fancy:FindFirstChildWhichIsA("VehicleSeat", true)
			R.expect(seatB.MaxSpeed).toBe(seatA.MaxSpeed)
			R.expect(seatB.TurnSpeed).toBe(seatA.TurnSpeed)
		end)
	end
end)

R.describe("Modules/Shop (server)", function()
	local function boot()
		local e = Loader.boot()
		local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local Shop = e.requirePath("ServerScriptService.Modules.Shop")
		local Products = e.requirePath("ReplicatedStorage.Shared.Products")
		Products.COIN_PACKS[1].id = 111   -- as if created on the Creator Dashboard
		local p = e.mock.addPlayer("Buyer", 4242)
		local rec = Store.load(p)
		return e, Store, Shop, p, rec, Products
	end

	R.it("buy and equip through the handler; the reply carries the new state", function()
		local e, Store, Shop, p, rec = boot()
		rec.coins = 500
		local res = Shop.handle(p, "buy", "paint_sunset")
		R.expect(res.result).toBe("ok")
		R.expect(res.state.coins).toBe(500 - Cosmetics.get("paint_sunset").price)
		R.expect(res.state.equipped.paint).toBe("paint_sunset")
		R.expect(Shop.handle(p, "equip", "paint_default").result).toBe("ok")
		R.expect(Shop.handle(p, "equip", "trail_fire").result).toBe("denied: not owned")
		R.expect(Shop.handle(p, "hack", "x").result).toBe("denied: bad action")
		R.expect(Shop.handle(p, "buy", 5).result).toBe("denied: bad id")
		e.mock.advance(Store.SAVE_SOON + 1)
		R.expect(e.mock.dataStores[Store.STORE_NAME].u4242.owned.paint_sunset).toBe(true)
	end)

	R.it("a coin pack is granted once per PurchaseId, after it is saved", function()
		local e, Store, Shop, p, rec, Products = boot()
		local D = roblox.Enum.ProductPurchaseDecision
		local info = { PlayerId = 4242, ProductId = 111, PurchaseId = "abc" }
		local res
		e.mock.task.spawn(function() res = Shop.processReceipt(info) end)
		e.mock.advance(1)
		R.expect(res).toBe(D.PurchaseGranted)
		R.expect(rec.coins).toBe(Products.COIN_PACKS[1].coins)
		R.expect(e.mock.dataStores[Store.STORE_NAME].u4242.coins).toBe(Products.COIN_PACKS[1].coins)
		e.mock.task.spawn(function() res = Shop.processReceipt(info) end)
		e.mock.advance(1)
		R.expect(res).toBe(D.PurchaseGranted)
		R.expect(rec.coins).toBe(Products.COIN_PACKS[1].coins)   -- not twice
	end)

	R.it("a failed save undoes the grant and asks Roblox to retry; unknown products and absent players wait", function()
		local e, Store, Shop, p, rec = boot()
		local D = roblox.Enum.ProductPurchaseDecision
		e.mock.dataStoreFail = "set"
		local res
		e.mock.task.spawn(function() res = Shop.processReceipt({ PlayerId = 4242, ProductId = 111, PurchaseId = "x1" }) end)
		e.mock.advance(10)
		R.expect(res).toBe(D.NotProcessedYet)
		R.expect(rec.coins).toBe(0)
		R.expect(#rec.receipts).toBe(0)
		e.mock.dataStoreFail = nil
		R.expect(Shop.processReceipt({ PlayerId = 4242, ProductId = 999, PurchaseId = "x2" })).toBe(D.NotProcessedYet)
		R.expect(Shop.processReceipt({ PlayerId = 1, ProductId = 111, PurchaseId = "x3" })).toBe(D.NotProcessedYet)
	end)

	R.it("one receipt at a time: Roblox asking twice mid-save grants once; no spending the coins before they are saved", function()
		local e, Store, Shop, p, rec, Products = boot()
		local D = roblox.Enum.ProductPurchaseDecision
		e.mock.dataStoreFail = "set"   -- the first save keeps failing for a while
		local a, b
		e.mock.task.spawn(function() a = Shop.processReceipt({ PlayerId = 4242, ProductId = 111, PurchaseId = "same" }) end)
		e.mock.advance(0.5)
		R.expect(Shop.handle(p, "buy", "paint_sunset").result).toBe("denied: busy")
		e.mock.task.spawn(function() b = Shop.processReceipt({ PlayerId = 4242, ProductId = 111, PurchaseId = "same" }) end)
		e.mock.advance(0.5)
		R.expect(b).toBe(nil)                          -- waits for the first, not "granted" off an unsaved id
		e.mock.dataStoreFail = nil
		e.mock.advance(20)
		R.expect(a).toBe(D.PurchaseGranted)            -- its retry got through
		R.expect(b).toBe(D.PurchaseGranted)
		R.expect(rec.coins).toBe(Products.COIN_PACKS[1].coins)
		R.expect(e.mock.dataStores[Store.STORE_NAME].u4242.coins).toBe(Products.COIN_PACKS[1].coins)
	end)

	R.it("a record that failed to load gets no Robux grant (it could not be saved)", function()
		local e = Loader.boot()
		local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local Shop = e.requirePath("ServerScriptService.Modules.Shop")
		e.requirePath("ReplicatedStorage.Shared.Products").COIN_PACKS[1].id = 111
		e.mock.dataStoreFail = "get"
		local p = e.mock.addPlayer("Unlucky", 5151)
		e.mock.task.spawn(function() Store.load(p) end)
		e.mock.advance(10)
		e.mock.dataStoreFail = nil
		local D = roblox.Enum.ProductPurchaseDecision
		R.expect(Shop.processReceipt({ PlayerId = 5151, ProductId = 111, PurchaseId = "y" })).toBe(D.NotProcessedYet)
		R.expect(Store.get(p).coins).toBe(0)
	end)
end)

R.describe("the next car wears what is equipped (CraftingManager)", function()
	R.it("equipped paint and trail show on the car built at the end of CRAFTING", function()
		local srv = Server.boot({
			players = 1,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.CraftingManager",
				"ServerScriptService.ProgressionManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0,
				durations = { FARMING = 0.5, CRAFTING = 0.5, RACING = 600 } },
		})
		local Store = srv.env.requirePath("ServerScriptService.Modules.PlayerStore")
		local rec = Store.get(srv.players[1])
		rec.owned.paint_galaxy, rec.owned.trail_bubbles = true, true
		rec.equipped = { paint = "paint_galaxy", trail = "trail_bubbles" }
		srv.advance(3)
		local data = srv.SessionManager.getData(srv.players[1])
		local car = data and data.vehicleModel
		R.expect(car ~= nil).toBe(true)
		R.expect(car.PrimaryPart:FindFirstChild("CosmeticTrail") ~= nil).toBe(true)
		local galaxy = 0
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") and d.Color == Cosmetics.get("paint_galaxy").body then galaxy += 1 end
		end
		R.expect(galaxy).toBeGreaterThan(0)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

-- Playtest 2026-10-25: the shop opened only in LOBBY and RESULTS, and the
-- lobby counts down 8 s once two players are in: no time to shop. It is open
-- in every phase but RACING now, and a look bought on the crafting screen
-- shows in its showroom at once.
R.describe("Shopping time", function()
	R.it("buying a paint on the crafting screen rebuilds the showroom in it", function()
		local e = Loader.boot()
		local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local Shop = e.requirePath("ServerScriptService.Modules.Shop")
		local CraftPreview = e.requirePath("ServerScriptService.Modules.CraftPreview")
		local p = e.mock.addPlayer("Crafter", 5151)
		local gui = e.mock.Instance.new("Folder")
		gui.Name = "PlayerGui"
		gui.Parent = p
		local rec = Store.load(p)
		rec.coins = 500
		local function painted()
			local folder = gui:FindFirstChild(CraftPreview.FOLDER)
			local model = folder and folder:GetChildren()[1]
			if not model then return nil end
			local want = Cosmetics.get("paint_sunset").body
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and math.abs(d.Color.R - want.R) < 0.01 and math.abs(d.Color.G - want.G) < 0.01
					and math.abs(d.Color.B - want.B) < 0.01 then return true end
			end
			return false
		end
		CraftPreview.show(p, {}, "FOREST")
		e.mock.advance(0.5)
		R.expect(painted()).toBe(false)
		R.expect(Shop.handle(p, "buy", "paint_sunset").result).toBe("ok")
		e.mock.advance(0.5)
		R.expect(painted()).toBe(true)
		-- crafting over: no showroom to refresh, an equip builds nothing
		CraftPreview.clear(p)
		R.expect(Shop.handle(p, "equip", "paint_default").result).toBe("ok")
		e.mock.advance(0.5)
		R.expect(#gui:FindFirstChild(CraftPreview.FOLDER):GetChildren()).toBe(0)
		R.expect(e.mock.errors).toBeEmpty("errors")
	end)

	R.it("the shop screen opens in every phase but RACING, also with B; the guides list it", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		R.expect(src:find("phase ~= Constants.PHASES.RACING", 1, true) ~= nil).toBe(true)
		R.expect(src:find("PHASES.LOBBY or phase", 1, true)).toBe(nil)
		R.expect(src:find("KeyCode.B", 1, true) ~= nil).toBe(true)
		R.expect(src:find("KeyInput.began", 1, true) ~= nil).toBe(true)
		local tutorial = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
		local _, n = tutorial:gsub('key = "B",%s+act = "shop",%s+short = "Shop"', "")
		R.expect(n).toBe(2)   -- FARMING and CRAFTING
	end)
end)

-- 2026-10-26: the shop stayed open over the crafting screen while its clock
-- ran out, and a lobby shopper found the round started under the panel.
R.describe("shop timing (Shared/ShopTiming)", function()
	local ShopTiming = env.requirePath("ReplicatedStorage.Shared.ShopTiming")
	local S = C.SHOP

	R.it("the panel shows what the game around it is doing, red in the last seconds", function()
		local t, warn = ShopTiming.line("LOBBY", 14.2)
		R.expect(t).toBe("Round starts in 0:14")
		R.expect(warn).toBe(false)
		R.expect(ShopTiming.line("LOBBY", nil)).toBe("Waiting for players")
		local c, w = ShopTiming.line("CRAFTING", S.WARN_AT - 1)
		R.expect(c:find("slots are kept", 1, true) ~= nil).toBe(true)
		R.expect(w).toBe(true)
		R.expect(ShopTiming.line("RESULTS", 25):find("Next round", 1, true) ~= nil).toBe(true)
		R.expect(ShopTiming.line("FARMING", 60):find("grab items", 1, true) ~= nil).toBe(true)
	end)

	R.it("an open shop closes when a round starts, for the race and once near the end of crafting", function()
		R.expect(ShopTiming.closeFor("FARMING", "LOBBY", 90, {})).toBe(true)
		R.expect(ShopTiming.closeFor("FARMING", nil, 60, {})).toBe(false)       -- opened during farming: stays
		R.expect(ShopTiming.closeFor("LOBBY", "RESULTS", 15, {})).toBe(false)   -- results → lobby: keep shopping
		R.expect(ShopTiming.closeFor("RACING", "CRAFTING", nil, {})).toBe(true)
		R.expect(ShopTiming.closeFor("CRAFTING", nil, S.CRAFT_CLOSE_AT + 5, {})).toBe(false)
		local close, why = ShopTiming.closeFor("CRAFTING", nil, S.CRAFT_CLOSE_AT - 0.5, {})
		R.expect(close).toBe(true)
		R.expect(why:find("Finish your car", 1, true) ~= nil).toBe(true)
		-- reopened after that: the player's choice
		R.expect(ShopTiming.closeFor("CRAFTING", nil, 5, { craftClosed = true })).toBe(false)
		R.expect(S.CRAFT_CLOSE_AT < C.CRAFT_HURRY.SECONDS).toBe(true)   -- the hurry clock still leaves shopping time
	end)

	R.it("the shop screen uses those rules on every frame and keeps the draft promise visible", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		R.expect(src:find("ShopTiming.closeFor(", 1, true) ~= nil).toBe(true)
		R.expect(src:find("ShopTiming.line(", 1, true) ~= nil).toBe(true)
		R.expect(src:find("Heartbeat:Connect", 1, true) ~= nil).toBe(true)
	end)
end)
