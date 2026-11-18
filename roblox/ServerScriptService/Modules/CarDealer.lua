-- CarDealer.lua
-- Junk Motors (Shared/NewCars): the new car showroom on Auto Street. Each
-- car stands on a plinth with two prompts (LobbyHub, attribute CarAction):
--   "try"  wear it round the waist for Constants.NEW_CARS.TRY_SECONDS
--   "buy"  pay its price in coins; it is yours and on at once
-- Owned cars are worn and changed like Legend Rides (Modules/LegendShop,
-- the shop's 🚗 tab, action "legend_ride" with "car:<item>").
-- The showroom's cars are built once at boot into ReplicatedStorage.NewCars
-- (one still per item, also the shop cards' pictures).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local NewCars = require(ReplicatedStorage.Shared.NewCars)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local CarDealer = {}
CarDealer.FOLDER = "NewCars"

local _trying = {}   -- userId → { item, token }

local function itemConfig()
	return require(ServerScriptService.Modules.ItemConfig)
end

local function tell(player, msg)
	pcall(function() RemoteEvents.LegendUpdate:FireClient(player, msg) end)
end

local function coinsStat(player, rec)
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	if c then c.Value = rec.coins end
end

--- The item `player` is trying on now, or nil.
function CarDealer.trying(player)
	local t = _trying[player.UserId]
	return t and t.item or nil
end

local function stopTrying(player)
	if _trying[player.UserId] then
		_trying[player.UserId] = nil
		require(ServerScriptService.Modules.LegendShop).refresh(player)
	end
end

--- Showroom actions: "try" | "buy" with an item. Returns "ok" or "denied: …".
function CarDealer.handle(player, rec, action, item)
	if type(item) ~= "string" or #item > 64 then return "denied: bad item" end
	local cfg = itemConfig()
	local price = NewCars.priceOf(cfg, item)
	if not price then return "denied: unknown" end
	local LegendShop = require(ServerScriptService.Modules.LegendShop)
	if action == "try" then
		local token = {}
		_trying[player.UserId] = { item = item, token = token }
		LegendShop.refresh(player)
		tell(player, { kind = "car_try", title = item, price = price, seconds = Constants.NEW_CARS.TRY_SECONDS,
			owned = NewCars.owns(rec, item) })
		Telemetry.record("car_try", { userId = player.UserId, item = item })
		task.delay(Constants.NEW_CARS.TRY_SECONDS, function()
			local t = _trying[player.UserId]
			if t and t.token == token then stopTrying(player) end
		end)
		return "ok"
	elseif action == "buy" then
		local res = NewCars.buy(cfg, rec, item)
		Telemetry.record("car_buy", { userId = player.UserId, item = item, price = price, result = res, coins = rec.coins })
		if res ~= "ok" then
			tell(player, { kind = "car_denied", title = item, reason = res, price = price, coins = rec.coins })
			return res
		end
		pcall(function()
			require(ServerScriptService.Modules.Analytics).spend(player, "Coins", price, rec.coins, "car_" .. item)
		end)
		coinsStat(player, rec)
		PlayerStore.saveSoon(player)
		_trying[player.UserId] = nil
		LegendShop.refresh(player)
		tell(player, { kind = "car_bought", title = item, price = price })
		return "ok"
	end
	return "denied: bad action"
end

--- A showroom prompt was used (LobbyManager wires them).
function CarDealer.prompt(player, action, item)
	local rec = PlayerStore.get(player)
	if not rec then return "denied: loading" end
	local res = CarDealer.handle(player, rec, action, item)
	local Shop = require(ServerScriptService.Modules.Shop)
	pcall(function() RemoteEvents.ShopUpdated:FireClient(player, Shop.state(rec)) end)
	return res
end

Players.PlayerRemoving:Connect(function(player)
	_trying[player.UserId] = nil
end)

--- Builds every new car into ReplicatedStorage.NewCars (a still each, named
-- after the item), once the item models are ready. Returns the folder.
function CarDealer.buildStills(waitFor)
	local ServerStorage = game:GetService("ServerStorage")
	local t0 = os.clock()
	while os.clock() - t0 < (waitFor or 20) do
		local f = ServerStorage:FindFirstChild("ItemModels")
		if f and f:GetAttribute("Ready") then break end
		task.wait(0.25)
	end
	local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
	local folder = Instance.new("Folder")
	folder.Name = CarDealer.FOLDER .. "_building"
	for _, c in ipairs(NewCars.catalog(itemConfig())) do
		local model = HallOfFame.buildStill(NewCars.ride(c.item))
		if model then
			for _, ch in ipairs(model:GetChildren()) do
				if ch:IsA("Model") and ch:GetAttribute("Hat") then ch:Destroy() end
			end
			model.Name = c.item
			model.Parent = folder
		end
		task.wait()
	end
	local old = ReplicatedStorage:FindFirstChild(CarDealer.FOLDER)
	if old then old:Destroy() end
	folder.Name = CarDealer.FOLDER
	folder.Parent = ReplicatedStorage
	return folder
end

return CarDealer
