-- ItemScan.lua
-- Which farm item a part belongs to. FarmingManager puts a StringValue
-- "ItemName" on the item model's PrimaryPart; FBX imports nest models, so
-- climb past inner models until one's PrimaryPart carries it.

local ItemScan = {}

--- The item's PrimaryPart for any part of a farm item, or nil.
function ItemScan.itemPrimary(part)
	local node = part and part:FindFirstAncestorWhichIsA("Model")
	while node do
		local primary = node.PrimaryPart
		if primary and primary:FindFirstChild("ItemName") then
			return primary
		end
		node = node:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

return ItemScan
