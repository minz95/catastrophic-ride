-- Shop.lua
-- The cosmetics shop (Shared/Cosmetics) and Robux coin packs
-- (Shared/Products) over the saved record (Modules/PlayerStore).
-- ShopManager wires it: RemoteEvents.ShopAction ("state" | "buy" | "equip",
-- id) → { result, state }, and MarketplaceService.ProcessReceipt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Products = require(ReplicatedStorage.Shared.Products)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Analytics = require(ServerScriptService.Modules.Analytics)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local RECEIPTS_KEPT = 50

local Shop = {}

local function coinsStat(player, rec)
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	if c then c.Value = rec.coins end
end

--- What the shop screen shows.
function Shop.state(rec)
	local owned = {}
	for id in pairs(rec.owned or {}) do table.insert(owned, id) end
	local packs = {}
	for _, p in ipairs(Products.available()) do
		table.insert(packs, { id = p.id, name = p.name, coins = p.coins, robux = p.robux })
	end
	return { coins = rec.coins, level = rec.level, owned = owned, equipped = rec.equipped or {}, packs = packs }
end

function Shop.handle(player, action, id)
	local rec = PlayerStore.get(player)
	if not rec then return { result = "denied: loading" } end
	local result = "ok"
	if action == "buy" then
		if type(id) ~= "string" then return { result = "denied: bad id" } end
		result = Cosmetics.buy(rec, id)
		if result == "ok" then
			local it = Cosmetics.get(id)
			Analytics.spend(player, "Coins", it.price, rec.coins, id)
			coinsStat(player, rec)
			task.spawn(PlayerStore.save, player)
		end
		Telemetry.record("shop", { userId = player.UserId, action = "buy", id = id, result = result, coins = rec.coins })
	elseif action == "equip" then
		if type(id) ~= "string" then return { result = "denied: bad id" } end
		result = Cosmetics.equip(rec, id)
		if result == "ok" then task.spawn(PlayerStore.save, player) end
		Telemetry.record("shop", { userId = player.UserId, action = "equip", id = id, result = result })
	elseif action ~= "state" then
		result = "denied: bad action"
	end
	return { result = result, state = Shop.state(rec) }
end

--- Robux coin packs. Grants once per PurchaseId and only after the record
-- holding the grant is saved (else Roblox retries later). Studio test
-- purchases (memory-only records) are granted without saving.
function Shop.processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local pack = Products.packFor(info.ProductId)
	local rec = player and PlayerStore.get(player)
	if not player or not pack or not rec then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	rec.receipts = rec.receipts or {}
	for _, r in ipairs(rec.receipts) do
		if r == info.PurchaseId then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end
	local saved = PlayerStore.isSaved(player)
	if not saved and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	rec.coins += pack.coins
	table.insert(rec.receipts, info.PurchaseId)
	while #rec.receipts > RECEIPTS_KEPT do table.remove(rec.receipts, 1) end
	if saved and not PlayerStore.save(player) then
		-- not stored: undo, Roblox calls again later
		rec.coins -= pack.coins
		table.remove(rec.receipts)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	coinsStat(player, rec)
	Analytics.earn(player, "Coins", pack.coins, rec.coins, "IAP")
	Telemetry.record("purchase", { userId = player.UserId, product = info.ProductId, coins = pack.coins, purchaseId = info.PurchaseId })
	RemoteEvents.ShopUpdated:FireClient(player, Shop.state(rec))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return Shop
