-- ItemModelPreloader.server.lua
-- Pre-builds all item 3D models into ServerStorage.ItemModels at game start.
-- Where each model comes from, first found wins:
--   1. the place's own import: ServerStorage.ItemMeshes.<Item> (or a Model
--      named after the item directly in ServerStorage), FBX from assets/items
--      imported in Studio (File → Import 3D, "Merge Meshes" off);
--   2. Modules/ItemMeshData: the same models as data (mesh / texture ids),
--      built with AssetService:CreateMeshPartAsync, so a Rojo-built place or
--      a fresh one shows the real models too (refresh the data with
--      `python3 tools/studio/item_meshes.py` after re-importing in Studio);
--   3. ItemModelBuilder: procedural parts (offline tests, or a mesh that
--      failed to load).
-- Every model is scaled so its longest side is TARGET_MAX studs, welded to its
-- PrimaryPart and streams as one piece (ModelStreamingMode Atomic: with
-- streaming on, a multi-part model otherwise arrives part by part and looks
-- broken).
-- Resolves: Issue #93

local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Recreate ItemModels folder first — even if requires below fail,
-- the folder existence tells FarmingManager the preloader ran.
local folder = ServerStorage:FindFirstChild("ItemModels")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name   = "ItemModels"
folder.Parent = ServerStorage

local ItemTypes        = require(game.ReplicatedStorage.Shared.ItemTypes)
local ItemModelBuilder = require(ServerScriptService.Modules.ItemModelBuilder)
local ItemMeshData     = require(ServerScriptService.Modules.ItemMeshData)

local TARGET_MAX = 4

if workspace.StreamingEnabled then
	warn("[ItemModelPreloader] Workspace.StreamingEnabled is on: turn it off in Studio (Workspace → "
		.. "StreamingEnabled). With it on, multi-part models and far teleports stall on clients.")
end

local meshesFolder = ServerStorage:FindFirstChild("ItemMeshes") or ServerStorage

local function imported(name)
	local m = meshesFolder:FindFirstChild(name) or meshesFolder:FindFirstChild((name:lower():gsub(" ", "_")))
	if m and m:IsA("Model") and m:FindFirstChildWhichIsA("BasePart", true) then return m:Clone() end
	return nil
end

-- A Model from ItemMeshData (nil when a mesh cannot be loaded here).
local function fromData(name)
	local list = ItemMeshData[name]
	if not list then return nil end
	local okSvc, AssetService = pcall(game.GetService, game, "AssetService")
	if not okSvc or not AssetService or not AssetService.CreateMeshPartAsync then return nil end
	local model = Instance.new("Model")
	model.Name = name
	local parts, failed, pending = {}, false, #list
	local done = Instance.new("BindableEvent")
	for i, d in ipairs(list) do
		task.spawn(function()
			local ok, part = pcall(function() return AssetService:CreateMeshPartAsync(d.mesh) end)
			if ok and part then
				part.Name = d.n
				pcall(function() part.TextureID = d.tex end)
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

-- Scale to TARGET_MAX around the bounding-box centre, set a PrimaryPart
-- (largest part), weld, stream as one piece.
local function finish(model, name)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	local bestVol, bestPart = -1, nil
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local h, p = part.Size * 0.5, part.Position
			minV = Vector3.new(math.min(minV.X, p.X - h.X), math.min(minV.Y, p.Y - h.Y), math.min(minV.Z, p.Z - h.Z))
			maxV = Vector3.new(math.max(maxV.X, p.X + h.X), math.max(maxV.Y, p.Y + h.Y), math.max(maxV.Z, p.Z + h.Z))
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > bestVol then bestVol, bestPart = vol, part end
		end
	end
	if not bestPart then return nil end
	local extent = maxV - minV
	local maxDim = math.max(extent.X, extent.Y, extent.Z)
	if maxDim > 0 then
		local factor = TARGET_MAX / maxDim
		local center = (minV + maxV) * 0.5
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Size = part.Size * factor
				local rot = part.CFrame - part.CFrame.Position
				part.CFrame = rot + center + (part.Position - center) * factor
			end
		end
	end
	model.Name = name
	model.PrimaryPart = model.PrimaryPart or bestPart
	local primary = model.PrimaryPart
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= primary and not part:FindFirstChildWhichIsA("WeldConstraint") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = part
			weld.Parent = primary
		end
	end
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
	return model
end

local counts = { imported = 0, data = 0, procedural = 0 }

local function build(item)
	local name = item.name
	local model, source = imported(name), "imported"
	if not model then model, source = fromData(name), "data" end
	model = model and finish(model, name)
	if model then
		model.Parent = folder
		counts[source] += 1
		return
	end
	local ok, err = pcall(function()
		local m = ItemModelBuilder.build(name, folder)
		if m then pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end) end
	end)
	if ok then
		counts.procedural += 1
	else
		warn("[ItemModelPreloader] Failed to build " .. name .. ": " .. tostring(err))
	end
end

-- Mesh loads are network calls: build the items side by side.
local left = #ItemTypes.ALL
local allDone = Instance.new("BindableEvent")
for _, item in ipairs(ItemTypes.ALL) do
	task.spawn(function()
		build(item)
		left -= 1
		if left == 0 then allDone:Fire() end
	end)
end
if left > 0 then allDone.Event:Wait() end
folder:SetAttribute("Ready", true)

print(string.format("[ItemModelPreloader] Ready: %d imported, %d from ItemMeshData, %d procedural",
	counts.imported, counts.data, counts.procedural))
