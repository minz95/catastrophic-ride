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
local _receiptBusy = {}   -- userId → a coin pack is being granted

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
	if (action == "buy" or action == "equip") and (type(id) ~= "string" or #id > 64) then
		return { result = "denied: bad id" }
	end
	if action == "buy" then
		-- a coin pack still being saved: its coins may yet be taken back
		if _receiptBusy[player.UserId] then return { result = "denied: busy", state = Shop.state(rec) } end
		result = Cosmetics.buy(rec, id)
		if result == "ok" then
			local it = Cosmetics.get(id)
			Analytics.spend(player, "Coins", it.price, rec.coins, id)
			coinsStat(player, rec)
			PlayerStore.saveSoon(player)
		end
		Telemetry.record("shop", { userId = player.UserId, action = "buy", id = id, result = result, coins = rec.coins })
	elseif action == "equip" then
		local it = Cosmetics.get(id)
		if it and rec.equipped and rec.equipped[it.category] == id then
			return { result = "ok", state = Shop.state(rec) }   -- already on: nothing to rebuild or save
		end
		result = Cosmetics.equip(rec, id)
		if result == "ok" then PlayerStore.saveSoon(player) end
		Telemetry.record("shop", { userId = player.UserId, action = "equip", id = id, result = result })
	elseif action ~= "state" then
		result = "denied: bad action"
	end
	-- buying equips too; on the crafting screen the showroom shows it now
	if result == "ok" and action ~= "state" then
		require(ServerScriptService.Modules.CraftPreview).refresh(player)
		local it = Cosmetics.get(id)
		if it and (it.category == "hat" or it.category == "move") then
			require(ServerScriptService.Modules.ShopHat).refresh(player)
		end
	end
	return { result = result, state = Shop.state(rec) }
end

--- Robux coin packs. Grants once per PurchaseId and only after the record
-- holding the grant is saved (else Roblox retries later). Studio test
-- purchases (memory-only records) are granted without saving.
function Shop.processReceipt(info)
	-- one receipt at a time per player: a second one (or Roblox asking again
	-- for the same purchase) waits for the first to be saved or undone
	local uid = info.PlayerId
	local t0 = os.clock()
	while _receiptBusy[uid] and os.clock() - t0 < 30 do task.wait(0.1) end
	if _receiptBusy[uid] then return Enum.ProductPurchaseDecision.NotProcessedYet end
	_receiptBusy[uid] = true
	local ok, res = pcall(Shop._grant, info)
	_receiptBusy[uid] = nil
	if not ok then error(res, 0) end
	return res
end

function Shop._grant(info)
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
		local at = table.find(rec.receipts, info.PurchaseId)
		if at then table.remove(rec.receipts, at) end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	coinsStat(player, rec)
	Analytics.earn(player, "Coins", pack.coins, rec.coins, "IAP")
	Telemetry.record("purchase", { userId = player.UserId, product = info.ProductId, coins = pack.coins, purchaseId = info.PurchaseId })
	RemoteEvents.ShopUpdated:FireClient(player, Shop.state(rec))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return Shop
