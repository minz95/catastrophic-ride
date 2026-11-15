-- ItemDataModel.lua
-- Builds an item Model from its data list (Modules/ItemMeshData or
-- Modules/StoreModelData: per part a mesh id or a plain shape, size,
-- position, rotation, colour, material) with AssetService:CreateMeshPartAsync.
-- Returns nil when any mesh cannot be loaded here: in live servers Roblox
-- loads only meshes the game's owner owns that way, so the Creator Store
-- items are baked into the place instead (Modules/StoreModelBake).

local ItemDataModel = {}

function ItemDataModel.build(name, list)
	if not list then return nil end
	local okSvc, AssetService = pcall(game.GetService, game, "AssetService")
	if not okSvc or not AssetService or not AssetService.CreateMeshPartAsync then return nil end
	local model = Instance.new("Model")
	model.Name = name
	local parts, failed, pending = {}, false, #list
	local done = Instance.new("BindableEvent")
	for i, d in ipairs(list) do
		task.spawn(function()
			local ok, part
			if d.mesh then
				ok, part = pcall(function() return AssetService:CreateMeshPartAsync(d.mesh) end)
			else
				ok, part = pcall(function()
					local p = Instance.new("Part")
					p.Shape = Enum.PartType[d.shape] or Enum.PartType.Block
					return p
				end)
			end
			if ok and part then
				part.Name = d.n
				if d.tex then pcall(function() part.TextureID = d.tex end) end
				if d.col then part.Color = Color3.fromRGB(d.col[1], d.col[2], d.col[3]) end
				if d.mat then pcall(function() part.Material = Enum.Material[d.mat] end) end
				if d.tr then part.Transparency = d.tr end
				part.Size = Vector3.new(d.s[1], d.s[2], d.s[3])
				local pos = Vector3.new(d.p[1], d.p[2], d.p[3])
				local r = d.rot
				part.CFrame = r and CFrame.new(pos.X, pos.Y, pos.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
					or CFrame.new(pos)
				parts[i] = part
			else
				failed = true
			end
			pending -= 1
			if pending == 0 then done:Fire() end
		end)
	end
	if pending > 0 then done.Event:Wait() end
	done:Destroy()
	if failed then
		for _, p in pairs(parts) do p:Destroy() end
		model:Destroy()
		return nil
	end
	for _, p in ipairs(parts) do p.Parent = model end
	return model
end

return ItemDataModel
