-- Products.lua
-- Robux developer products (coin packs). Create each product on the Creator
-- Dashboard (your experience → Monetization → Developer Products), then put
-- its id here. Packs with id 0 are not shown and cannot be bought.
-- Granted by ShopManager's ProcessReceipt (once per purchase, saved first).

local Products = {}

Products.COIN_PACKS = {
	{ key = "coins_small",  name = "Pouch of Coins", coins = 300,  robux = 49,  id = 0 },
	{ key = "coins_medium", name = "Bag of Coins",   coins = 1000, robux = 129, id = 0 },
	{ key = "coins_large",  name = "Chest of Coins", coins = 2500, robux = 279, id = 0 },
}

--- The pack sold under this developer product id, or nil.
function Products.packFor(productId)
	if not productId or productId == 0 then return nil end
	for _, p in ipairs(Products.COIN_PACKS) do
		if p.id == productId then return p end
	end
	return nil
end

--- Packs that can be bought (id set).
function Products.available()
	local out = {}
	for _, p in ipairs(Products.COIN_PACKS) do
		if p.id ~= 0 then table.insert(out, p) end
	end
	return out
end

return Products
