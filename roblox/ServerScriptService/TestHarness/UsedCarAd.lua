-- UsedCarAd.lua
-- Server side of the used-car reel (2026-11-18, the user's idea: "anyone
-- want a used car in Roblox? A skit: I walked into the map, there's a
-- used-car dealer, I tried to haggle, in the end I bought a Rubber Duck at
-- a price I liked and rode it around. Ends: 'buy a used car and race with
-- me!'"). The game has no haggling: the dealer turns every offer down
-- (the price on the card is the total, as the lot really works), the
-- filmer walks across the road and finds a brand new Rubber Duck at
-- Junk Motors for exactly their last offer, 1,200.
-- Harness arg `lobbyFilm = { story = "usedcar" }` (scenario record-usedcar).
-- Camera, walk and speech bubbles: StarterPlayerScripts/Modules/UsedCarAdClient.
-- Nothing is saved (LegendStore.memoryOnly, a memory record).
--
--   0  the plaza, out of the west gate      9  at the JUST IN car, Hank greets
--   14 the price card, the inspection card  19 the haggling (three offers)
--   30 across the road to Junk Motors       35 trying on the duck
--   39 bought                               41 riding it down the street
--   50 done

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UsedCarAd = {}

UsedCarAd.LENGTH = 50
UsedCarAd.DUCK = "Rubber Duck"
-- the lot: the car the filmer wants (newest, JUST IN) and others round it
UsedCarAd.JUST_IN = { name = "doyun0412", slots = { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" }, votes = 9 }
UsedCarAd.OTHERS = {
	{ "minty_k", { BODY = "Toilet", ENGINE = "Rocket" } }, { "Bo", { BODY = "Bathtub", ENGINE = "Fan" } },
	{ "Cy", { BODY = "Shopping Cart", SPECIAL = "Balloon Bunch" } }, { "jiho", { BODY = "Red Sofa", ENGINE = "Rocket" } },
	{ "Rae", { BODY = "Refrigerator" } }, { "sunny", { BODY = "Old TV", ENGINE = "Hair Dryer" } },
	{ "Taeo", { BODY = "Washing Machine" } }, { "Lu", { BODY = "Bicycle", ENGINE = "Rocket" } },
	{ "Mo", { BODY = "Office Chair" } }, { "Kai", { BODY = "Mattress", ENGINE = "Fan" } },
	{ "ari", { BODY = "Wheelbarrow" } }, { "Pip", { BODY = "Trash Can", ENGINE = "Rocket" } },
}
-- where Hank stands to sell (offset from ORIGIN): beside the JUST IN car's stand
UsedCarAd.HANK_AT = Vector3.new(-144, 0, 16.5)
UsedCarAd.START = Vector3.new(-52, 0, 0)   -- where the first shot starts (offset from ORIGIN)

local V = Vector3.new

local function hop(rig)
	local base = rig:GetPivot()
	for k = 1, 8 do
		local a = math.sin(k / 8 * math.pi)
		rig:PivotTo(base + V(0, a * 2.2, 0))
		task.wait(0.05)
	end
	rig:PivotTo(base)
end

--- Plays the timeline once the lobby film found its filmer.
function UsedCarAd.run(player, rec, done)
	local HallOfFame  = require(ServerScriptService.Modules.HallOfFame)
	local LegendStore = require(ServerScriptService.Modules.LegendStore)
	local CarDealer   = require(ServerScriptService.Modules.CarDealer)
	local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	local NewCars     = require(ReplicatedStorage.Shared.NewCars)
	local ItemConfig  = require(ReplicatedStorage.Shared.ItemConfig)
	local O = LobbyLayout.ORIGIN

	ReplicatedStorage:SetAttribute("FilmStory", "usedcar")
	-- the filmer: no ride on, enough coins for the duck and not for the Legend
	rec.coins = 1300
	rec.legendOn = nil
	rec.cars = {}
	require(ServerScriptService.Modules.LegendShop).refresh(player)

	-- the lot, older first: the JUST IN car last (newest)
	local nowT = os.time()
	for i, o in ipairs(UsedCarAd.OTHERS) do
		local l = LegendRides.listing(HallOfFame.entry(100 + i, o[1], "FOREST", o[2], 2 + i % 5, {}), nowT - 3600 * (20 - i))
		l.sold = (i * 7) % 43
		LegendStore.add(l)
	end
	local J = UsedCarAd.JUST_IN
	local just = LegendRides.listing(HallOfFame.entry(99, J.name, "FOREST", J.slots, J.votes, {}), nowT)
	just.sold = 3
	LegendStore.add(just)

	-- Hank comes over to the JUST IN car
	local hub = workspace:FindFirstChild("LobbyHub")
	local hank = hub and hub:FindFirstChild("Npc_hank")
	local hankAt = O + UsedCarAd.HANK_AT
	if hank then
		local root = hank:FindFirstChild("HumanoidRootPart")
		local lift = root and (root.Position.Y - O.Y) or 3
		hank:PivotTo(CFrame.lookAt(hankAt + V(0, lift, 0), O + V(-138, lift, 15.5)))
		for _, d in ipairs(hub:GetChildren()) do
			if d.Name == "NpcBlock" and d:GetAttribute("Npc") == "hank" then
				d.CFrame = CFrame.new(hankAt + V(0, d.Size.Y / 2, 0))
			end
		end
	end

	-- where the duck stands in the showroom (the client walks there)
	for i, c in ipairs(NewCars.catalog(ItemConfig)) do
		if c.item == UsedCarAd.DUCK then ReplicatedStorage:SetAttribute("FilmDuck", LobbyLayout.carSpot(i)) end
	end
	ReplicatedStorage:SetAttribute("FilmHank", hankAt)

	-- the filmer at the first shot's spot, by the server (a client's first
	-- move after the film starts is ignored: takes 1 and 2 stayed on the spawn)
	local function toStart()
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if not r then return end
		local y = (h and h.HipHeight or 2) + r.Size.Y / 2
		local feet = O + UsedCarAd.START
		c:PivotTo(CFrame.lookAt(feet + V(0, y, 0), O + V(-90, y, 0)))
	end
	toStart()
	task.wait(2)   -- the lot's cars built
	toStart()
	local T0 = workspace:GetServerTimeNow() + 2
	ReplicatedStorage:SetAttribute("FilmT0", T0)
	local function at(t, fn)
		task.delay(math.max(0, T0 + t - workspace:GetServerTimeNow()), function() pcall(fn) end)
	end
	at(28, function() if hank then hop(hank) end end)
	at(35, function() CarDealer.handle(player, rec, "try", UsedCarAd.DUCK) end)
	at(39, function() CarDealer.handle(player, rec, "buy", UsedCarAd.DUCK) end)
	at(UsedCarAd.LENGTH, function() done("usedcar ad") end)
end

return UsedCarAd
