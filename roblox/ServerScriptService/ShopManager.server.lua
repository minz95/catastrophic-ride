-- ShopManager.server.lua
-- Wires Modules/Shop: the shop screen's RemoteEvents.ShopAction and Robux
-- coin packs (MarketplaceService.ProcessReceipt).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Shop = require(ServerScriptService.Modules.Shop)

RemoteEvents.ShopAction.OnServerInvoke = function(player, action, id)
	local ok, res = pcall(Shop.handle, player, action, id)
	if not ok then
		warn("[ShopManager] " .. tostring(res))
		return { result = "denied: error" }
	end
	return res
end

MarketplaceService.ProcessReceipt = function(info)
	local ok, res = pcall(Shop.processReceipt, info)
	if not ok then
		warn("[ShopManager] ProcessReceipt: " .. tostring(res))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return res
end

-- The shop's pictures (Modules/ShopPreview): every look on each biome's
-- vehicle, built once, a little at a time, after the server is up.
task.delay(3, function()
	local ok, err = pcall(function()
		require(game:GetService("ServerScriptService").Modules.ShopPreview).buildAll()
	end)
	if not ok then warn("[ShopManager] previews: " .. tostring(err)) end
end)

-- Shop hats on every avatar (Modules/ShopHat).
require(game:GetService("ServerScriptService").Modules.ShopHat).start()
