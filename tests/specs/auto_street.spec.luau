--!nocheck
-- Auto Street and Junk Motors (2026-11-18, "a dealership where you buy the
-- car you want at a fixed price, not gacha; bought cars are worn round the
-- waist"): the way out of the plaza's west gate, the showroom with every
-- rideable item as a new car, trying one on, buying one with coins, wearing
-- it, and players walking there without being sent back to the spawn.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local SCRIPTS = {
	"ServerScriptService.MapBuilders.ForestMapBuilder",
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.CharacterManager",
	"ServerScriptService.FarmingManager",
	"ServerScriptService.CraftingManager",
	"ServerScriptService.RacingManager",
	"ServerScriptService.ProgressionManager",
	"ServerScriptService.ShopManager",
	"ServerScriptService.LegendManager",
	"ServerScriptService.LobbyManager",
}

R.describe("Auto Street: the cars and where they stand", function()
	local env = Loader.boot()
	local L = env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
	local NewCars = env.requirePath("ReplicatedStorage.Shared.NewCars")
	local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local Npcs = env.requirePath("ReplicatedStorage.Shared.LobbyNpcs")
	local O = L.ORIGIN

	R.it("every rideable item is a new car once, priced by its rarity, cheapest first; they all fit the showroom", function()
		local cat = NewCars.catalog(ItemConfig)
		local want = 0
		for name, cfg in pairs(ItemConfig) do
			if type(name) == "string" and type(cfg) == "table" and cfg.rarity
				and (cfg.slotType == "BODY" or cfg.ride ~= nil) then want += 1 end
		end
		R.expect(#cat).toBe(want)
		R.expect(#cat >= 30).toBe(true, tostring(#cat))
		R.expect(#cat <= L.CAR_SLOTS).toBe(true, "showroom slots " .. L.CAR_SLOTS)
		local seen, last = {}, 0
		for _, c in ipairs(cat) do
			R.expect(seen[c.item]).toBe(nil)
			seen[c.item] = true
			R.expect(c.price).toBe(Constants.NEW_CARS.PRICE[c.rarity])
			R.expect(c.price >= last).toBe(true, c.item)
			last = c.price
		end
		R.expect(seen.Toilet and seen.Rocket and seen["Rubber Duck"]).toBe(true)
		R.expect(seen.Toaster).toBe(nil)   -- an engine nobody can ride
	end)

	R.it("plinths stand inside the showroom with walkways between the rows; the street is walled in", function()
		local S = L.SHOWROOM
		local b = S.box
		local bad = {}
		for i = 1, L.CAR_SLOTS do
			local p = L.carSpot(i) - O
			local hx, hz = S.plinth.X / 2, S.plinth.Z / 2
			if p.X - hx < b[1] + 4 or p.X + hx > b[2] - 4 or p.Z - hz < b[3] + 4 or p.Z + hz > b[4] - 4 then
				table.insert(bad, "plinth " .. i .. " against a wall")
			end
			for j = i + 1, L.CAR_SLOTS do
				local q = L.carSpot(j) - O
				local gx = math.abs(p.X - q.X) - S.plinth.X
				local gz = math.abs(p.Z - q.Z) - S.plinth.Z
				if gx < 2 and gz < 5 then table.insert(bad, string.format("plinths %d / %d", i, j)) end
			end
		end
		R.expect(bad).toBeEmpty("crowded showroom")
		-- the showroom and the road are on the lot; the doors open onto the road side
		local T = L.STREET.lot
		R.expect(b[1] >= T[1] and b[2] <= T[2] and b[3] >= T[3] and b[4] <= T[4]).toBe(true)
		R.expect(b[4] < L.STREET.road[3]).toBe(true, "showroom off the road")
		-- where you may walk
		R.expect(L.inTown(O + Vector3.new(-90, 2, 0))).toBe(true)          -- the lane
		R.expect(L.inTown(O + Vector3.new(-200, 2, 0))).toBe(true)         -- the road
		R.expect(L.inTown(O + Vector3.new(-200, 2, -40))).toBe(true)       -- in the showroom
		R.expect(L.inTown(O + Vector3.new(-200, 2, 90))).toBe(false)       -- past the south wall
		R.expect(L.inTown(O + Vector3.new(-90, 2, 40))).toBe(false)        -- the island's houses
		R.expect(L.inTown(O + Vector3.new(-200, -30, 0))).toBe(false)      -- fell off
		-- the salesman stands in the showroom off the plinths, the dealers on the lot clear of the cars
		local U = L.USED_LOT
		for _, n in ipairs(Npcs.LIST) do
			if n.street then
				local p = n.at
				R.expect(L.inRect(b, p.X, p.Z) or L.inRect(U.box, p.X, p.Z)).toBe(true, n.id)
				for i = 1, L.CAR_SLOTS do
					local q = L.carSpot(i) - O
					R.expect(math.abs(p.X - q.X) > S.plinth.X / 2 + 1 or math.abs(p.Z - q.Z) > S.plinth.Z / 2 + 1).toBe(true, n.id)
				end
				for i = 1, L.USED_SLOTS do
					local q = L.usedSpot(i) - O
					R.expect(math.abs(p.X - q.X) > 3.5 or math.abs(p.Z - q.Z) > 6).toBe(true, n.id)
				end
			end
		end
	end)

	R.it("the used-car lot: bays in back-to-back rows on the gravel, more on the tower deck up the ramp; one bay per kept listing", function()
		local U = L.USED_LOT
		local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
		R.expect(L.USED_SLOTS).toBe(Constants.LEGEND.KEEP)
		local T = U.tower
		for i = 1, L.USED_SLOTS do
			local p, north = L.usedSpot(i)
			local d = p - O
			if d.Y > 1 then
				R.expect(math.abs(d.Y - T.deck) < 0.01).toBe(true)
				R.expect(L.inRect(T.box, d.X, d.Z + (north and -3.5 or 3.5))).toBe(true, "deck bay " .. i)
			else
				R.expect(L.inRect(U.box, d.X, d.Z - 3.5) and L.inRect(U.box, d.X, d.Z + 3.5)).toBe(true, "bay " .. i)
				R.expect(L.inRect(T.box, d.X, d.Z)).toBe(false, "bay " .. i .. " under the tower")
			end
			R.expect(L.onStreet(p + Vector3.new(0, 3, 0))).toBe(true, "bay " .. i)
		end
		local first, firstNorth = L.usedSpot(1)
		R.expect(firstNorth).toBe(true)   -- the newest faces the road, by the entrance
		R.expect(math.abs(first.X - O.X - U.entranceX) < 16).toBe(true)
		-- the ramp climbs from the lot to the deck's edge
		R.expect(T.ramp.x0).toBe(T.box[2])
		R.expect(L.inRect(U.box, T.ramp.x1, T.ramp.z0)).toBe(true)
		-- offices stand behind the rows
		for _, x in ipairs(U.offices) do
			R.expect(U.officeZ - 3 > U.rows[2] + 6).toBe(true)
			R.expect(L.inRect(U.box, x, U.officeZ + 3)).toBe(true)
		end
	end)
end)

R.describe("Junk Motors in a server", function()
	local function boot(opts)
		opts = opts or {}
		local srv = Server.boot({
			players = opts.players or 1, scripts = SCRIPTS,
			harness = { harness = "lune", biome = "FOREST", players = opts.players or 1, lobbyDelay = opts.lobbyDelay or 300 },
		})
		srv.advance(2)
		local e = srv.env
		return srv, {
			L = e.requirePath("ReplicatedStorage.Shared.LobbyLayout"),
			NewCars = e.requirePath("ReplicatedStorage.Shared.NewCars"),
			Constants = e.requirePath("ReplicatedStorage.Shared.Constants"),
			PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore"),
			Shop = e.requirePath("ServerScriptService.Modules.Shop"),
			RE = e.requirePath("ReplicatedStorage.RemoteEvents"),
			hub = e.workspace:FindFirstChild("LobbyHub"),
		}
	end
	local function rootOf(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
	local function prompts(hub, item)
		local out = {}
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d:GetAttribute("Car") == item then out[d:GetAttribute("CarAction")] = d end
		end
		return out
	end
	local function worn(p)
		local m = p.Character and p.Character:FindFirstChild("LegendRide")
		return m and m:GetAttribute("LegendId") or nil
	end
	local function notices(m, kind)
		local n = 0
		for _, c in ipairs(rawget(m.RE.LegendUpdate, "_calls") or {}) do
			if c.method == "FireClient" and c.args[2].kind == kind then n += 1 end
		end
		return n
	end

	R.it("is built: the gate open in the fence, the walls, a plinth with Try on and Buy for every car, each car on its plinth", function()
		local srv, m = boot()
		local hub, L = m.hub, m.L
		local O = L.ORIGIN
		local cat = m.NewCars.catalog(srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig"))
		-- nothing of the plaza's invisible wall stands in the gate
		for _, d in ipairs(hub:GetChildren()) do
			if d.Name == "Wall" then
				local rel = d.Position - O
				R.expect(math.abs(rel.Z) > L.GATE_HALF or rel.X > -60).toBe(true, "a wall piece in the gate")
			end
		end
		local walls = 0
		for _, d in ipairs(hub:GetChildren()) do if d.Name == "StreetWall" then walls += 1 end end
		R.expect(walls).toBe(7)
		for _, c in ipairs(cat) do
			local pp = prompts(hub, c.item)
			R.expect(pp.try ~= nil and pp.buy ~= nil).toBe(true, c.item)
			R.expect(pp.buy.HoldDuration > 0).toBe(true)
			R.expect(tostring(pp.buy.KeyboardKeyCode)).toBe("Enum.KeyCode.F")
			R.expect(pp.buy.ActionText:find(tostring(c.price), 1, true) ~= nil).toBe(true, c.item)
		end
		srv.advance(25)   -- the stills are built once the item models are in (no preloader here: it waits 20 s)
		local live = hub:FindFirstChild("Live")
		local cars = 0
		for _, c in ipairs(live:GetChildren()) do
			if c.Name:sub(1, 7) == "NewCar_" then
				cars += 1
				local cf, size = c:GetBoundingBox()
				R.expect(math.abs(math.max(size.X, size.Z) - m.Constants.NEW_CARS.SHOW_LENGTH) < 0.05).toBe(true, c.Name)
				R.expect(L.inRect(L.SHOWROOM.box, cf.Position.X - O.X, cf.Position.Z - O.Z)).toBe(true, c.Name)
			end
		end
		R.expect(cars).toBe(#cat)
		local parts = 0
		for _, d in ipairs(hub:GetDescendants()) do if d:IsA("BasePart") then parts += 1 end end
		R.expect(parts < 4500).toBe(true, "parts " .. parts)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("buying: coins pay for it, it is yours and on at once; short of coins or already yours changes nothing", function()
		local srv, m = boot()
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		rec.coins = 600
		prompts(m.hub, "Cardboard Box").buy.Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(rec.coins).toBe(100)
		R.expect(rec.cars["Cardboard Box"]).toBe(true)
		R.expect(rec.legendOn).toBe("car:Cardboard Box")
		R.expect(worn(p)).toBe("car:Cardboard Box")
		R.expect(notices(m, "car_bought")).toBe(1)
		-- not enough coins for the piano
		prompts(m.hub, "Piano").buy.Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(rec.coins).toBe(100)
		R.expect(rec.cars.Piano).toBe(nil)
		R.expect(worn(p)).toBe("car:Cardboard Box")
		-- the box again: already yours
		rec.coins = 5000
		prompts(m.hub, "Cardboard Box").buy.Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(rec.coins).toBe(5000)
		R.expect(notices(m, "car_denied")).toBe(2)
		-- the garage: in the shop's 🚗 tab, worn on and off from there
		local state = m.Shop.state(rec)
		local inGarage = false
		for _, o in ipairs(state.legend.owned) do
			if o.id == "car:Cardboard Box" then inGarage = o.new == true end
		end
		R.expect(inGarage).toBe(true)
		R.expect(m.Shop.handle(p, "legend_ride", "").result).toBe("ok")
		R.expect(worn(p)).toBe(nil)
		R.expect(m.Shop.handle(p, "legend_ride", "car:Piano").result).toBe("denied: not owned")
		R.expect(m.Shop.handle(p, "legend_ride", "car:Cardboard Box").result).toBe("ok")
		R.expect(worn(p)).toBe("car:Cardboard Box")
		-- a new character (a respawn) puts it back on
		p:LoadCharacter()
		srv.advance(1)
		R.expect(worn(p)).toBe("car:Cardboard Box")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("trying on: the car goes round the waist for TRY_SECONDS, then your own ride comes back; nothing is bought", function()
		local srv, m = boot()
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		rec.coins = 600
		prompts(m.hub, "Cardboard Box").buy.Triggered:Fire(p)
		srv.advance(0.5)
		prompts(m.hub, "Piano").try.Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(worn(p)).toBe("try:Piano")
		R.expect(rec.cars.Piano).toBe(nil)
		R.expect(rec.coins).toBe(100)
		R.expect(notices(m, "car_try")).toBe(1)
		-- another try-on restarts the clock
		srv.advance(m.Constants.NEW_CARS.TRY_SECONDS - 3)
		prompts(m.hub, "Toilet").try.Triggered:Fire(p)
		srv.advance(5)
		R.expect(worn(p)).toBe("try:Toilet")
		srv.advance(m.Constants.NEW_CARS.TRY_SECONDS)
		R.expect(worn(p)).toBe("car:Cardboard Box")
		-- buying what you try on keeps it on
		rec.coins = 5000
		prompts(m.hub, "Toilet").try.Triggered:Fire(p)
		srv.advance(1)
		prompts(m.hub, "Toilet").buy.Triggered:Fire(p)
		srv.advance(1)
		R.expect(worn(p)).toBe("car:Toilet")
		srv.advance(m.Constants.NEW_CARS.TRY_SECONDS + 1)
		R.expect(worn(p)).toBe("car:Toilet")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	-- puts `n` vote winners' rides on sale (newest last), owners not on this server
	local function listWinners(srv, n)
		local e = srv.env
		local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		LegendStore.memoryOnly = true
		local bodies = { "Toilet", "Bathtub", "Piano", "Red Sofa", "Shopping Cart", "Rubber Duck", "Refrigerator", "Old TV" }
		local out = {}
		for k = 1, n do
			local ent = HallOfFame.entry(9000 + k, "Winner" .. k, "FOREST", { BODY = bodies[(k - 1) % #bodies + 1], ENGINE = "Rocket" }, k, {})
			table.insert(out, LegendShop.listWinner(ent))
			srv.advance(1.1)   -- a listing's time is whole seconds: one a second keeps the order
		end
		srv.advance(2)
		return out
	end
	local function usedCar(hub, i)
		return hub:FindFirstChild("Live"):FindFirstChild("Used_" .. i)
	end
	local function usedPrompt(hub, id, action)
		for _, c in ipairs(hub:FindFirstChild("Live"):GetChildren()) do
			if c:GetAttribute("Legend") == id then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("ProximityPrompt") and d:GetAttribute("CarAction") == action then return d end
				end
			end
		end
		return nil
	end

	R.it("the used-car lot fills with the vote winners' rides, newest JUST IN by the entrance; the plaza pads keep the newest six", function()
		local srv, m = boot()
		local hub = m.hub
		R.expect(hub:FindFirstChild("LotEmptySign").Transparency).toBe(0)
		local listed = listWinners(srv, 8)
		R.expect(hub:FindFirstChild("LotEmptySign").Transparency).toBe(1)
		for i = 1, 8 do R.expect(usedCar(hub, i) ~= nil).toBe(true, "bay " .. i) end
		R.expect(usedCar(hub, 9)).toBe(nil)
		-- the newest first, its card says JUST IN
		R.expect(usedCar(hub, 1):GetAttribute("Legend")).toBe(listed[8].id)
		local tagText = {}
		for _, d in ipairs(usedCar(hub, 1):GetDescendants()) do
			if d:IsA("TextLabel") then table.insert(tagText, d.Text) end
		end
		R.expect(table.concat(tagText, "|"):find("JUST IN!", 1, true) ~= nil).toBe(true)
		R.expect(table.concat(tagText, "|"):find("Built by Winner8", 1, true) ~= nil).toBe(true)
		R.expect(table.concat(tagText, "|"):find("2,500", 1, true) ~= nil).toBe(true)
		local pads = 0
		for _, c in ipairs(hub:FindFirstChild("Live"):GetChildren()) do
			if c.Name:sub(1, 7) == "Legend_" then pads += 1 end
		end
		R.expect(pads).toBe(6)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("buying on the lot: coins, the numbered copy round your waist, the builder's royalty kept for them; trying on first is free", function()
		local srv, m = boot()
		local hub = m.hub
		local p = srv.players[1]
		local rec = m.PlayerStore.get(p)
		local listed = listWinners(srv, 3)
		local id = listed[2].id
		rec.coins = 3000
		usedPrompt(hub, id, "try").Triggered:Fire(p)
		srv.advance(0.5)
		R.expect(worn(p)).toBe("try:" .. id)
		R.expect(rec.coins).toBe(3000)
		usedPrompt(hub, id, "buy").Triggered:Fire(p)
		srv.advance(1)
		R.expect(rec.coins).toBe(3000 - m.Constants.LEGEND.COINS)
		R.expect(rec.legend[id] ~= nil and rec.legend[id].serial).toBe(1)
		R.expect(worn(p)).toBe(id)
		R.expect(notices(m, "car_bought")).toBe(1)
		-- the lot shows the sale on the card
		srv.advance(2)
		local text = {}
		for _, d in ipairs(hub:FindFirstChild("Live"):GetDescendants()) do
			if d:IsA("TextLabel") then table.insert(text, d.Text) end
		end
		R.expect(table.concat(text, "|"):find("Sold 1/50", 1, true) ~= nil).toBe(true)
		-- again: already yours; short of coins for another
		rec.coins = 3000
		usedPrompt(hub, id, "buy").Triggered:Fire(p)
		srv.advance(1)
		R.expect(rec.coins).toBe(3000)
		rec.coins = 100
		usedPrompt(hub, listed[1].id, "buy").Triggered:Fire(p)
		srv.advance(1)
		R.expect(rec.coins).toBe(100)
		R.expect(rec.legend[listed[1].id]).toBe(nil)
		R.expect(notices(m, "car_denied")).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("walking down Auto Street and into the showroom keeps you there; past its walls or off the lot you go back to the spawn", function()
		local srv, m = boot()
		local L, O = m.L, m.L.ORIGIN
		local p = srv.players[1]
		rootOf(p).CFrame = CFrame.new(O + Vector3.new(-200, 3, -40))
		srv.advance(2)
		R.expect(L.onStreet(rootOf(p).Position)).toBe(true)
		R.expect((rootOf(p).Position - (O + Vector3.new(-200, 3, -40))).Magnitude < 1).toBe(true)
		rootOf(p).CFrame = CFrame.new(O + Vector3.new(-280, 3, 6))
		srv.advance(2)
		R.expect(L.onStreet(rootOf(p).Position)).toBe(true)
		-- up on the parking tower's deck
		rootOf(p).CFrame = CFrame.new(O + Vector3.new(-280, L.USED_LOT.tower.deck + 3, 38))
		srv.advance(2)
		R.expect(rootOf(p).Position.Y > O.Y + L.USED_LOT.tower.deck).toBe(true)
		-- over the south wall: back to the plaza
		rootOf(p).CFrame = CFrame.new(O + Vector3.new(-200, 3, 90))
		srv.advance(2)
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(true)
		-- fell off the lot: back to the plaza
		rootOf(p).CFrame = CFrame.new(O + Vector3.new(-200, -40, 0))
		srv.advance(2)
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

return R
