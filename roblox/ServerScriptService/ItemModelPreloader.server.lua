-- ItemModelPreloader.server.lua
-- Pre-builds all item 3D models into ServerStorage at game start.
-- Priority: ServerStorage.ItemMeshes (Blender FBX imported in Studio) → procedural Part build.
--
-- To activate a Blender FBX model for an item:
--   1. In Roblox Studio: File → Import 3D → select assets/items/<item>.fbx
--   2. Rename the imported Model to the exact item name (e.g. "Barrel")
--   3. Drag it into ServerStorage.ItemMeshes
--   The preloader will automatically use it on next server start.
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

-- Debug: list ServerStorage children at runtime
do
	local children = ServerStorage:GetChildren()
	print("[ItemModelPreloader] ServerStorage has", #children, "children:")
	for _, c in ipairs(children) do
		print("  -", c.Name, "(", c.ClassName, ")")
	end
end

-- ItemMeshes: optional folder populated with Blender-imported Models.
-- Falls back to searching ServerStorage directly if the subfolder doesn't exist.
local meshesFolder = ServerStorage:FindFirstChild("ItemMeshes") or ServerStorage
print("[ItemModelPreloader] meshesFolder =", meshesFolder.Name, "(", meshesFolder.ClassName, ")")

local blenderCount    = 0
local proceduralCount = 0

for _, item in ipairs(ItemTypes.ALL) do
	local name = item.name

	-- 1. Try Blender-imported mesh from ItemMeshes
	if meshesFolder then
		local mesh = meshesFolder:FindFirstChild(name)
		if not mesh then
			-- Fallback: Blender FBX exports use snake_case object names
			-- (e.g. "Rubber Duck" → "rubber_duck"). Try that too.
			mesh = meshesFolder:FindFirstChild(name:lower():gsub(" ", "_"))
		end
		if mesh then
			local clone = mesh:Clone()
			clone.Name = name

			-- Ensure PrimaryPart is set (pick largest BasePart by volume if missing)
			if not clone.PrimaryPart then
				local bestVol, bestPart = 0, nil
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then
						local vol = part.Size.X * part.Size.Y * part.Size.Z
						if vol > bestVol then
							bestVol  = vol
							bestPart = part
						end
					end
				end
				if bestPart then
					clone.PrimaryPart = bestPart
				end
			end

			-- Normalize size: scale model so its longest axis = TARGET_MAX studs.
			-- Manually scale Size + Position around the bbox centroid. We tried
			-- Model:ScaleTo() but it only scaled Size, leaving part positions
			-- wildly spread (parts ended up 1000s of studs from primary in spawned items).
			local TARGET_MAX = 4
			do
				local allParts = clone:GetDescendants()
				local basePartCount = 0
				local minV = Vector3.new(math.huge, math.huge, math.huge)
				local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
				for _, part in ipairs(allParts) do
					if part:IsA("BasePart") then
						basePartCount = basePartCount + 1
						local p = part.Position
						local h = part.Size * 0.5
						minV = Vector3.new(math.min(minV.X, p.X - h.X), math.min(minV.Y, p.Y - h.Y), math.min(minV.Z, p.Z - h.Z))
						maxV = Vector3.new(math.max(maxV.X, p.X + h.X), math.max(maxV.Y, p.Y + h.Y), math.max(maxV.Z, p.Z + h.Z))
					end
				end
				if basePartCount > 0 then
					local extent = maxV - minV
					local maxDim = math.max(extent.X, extent.Y, extent.Z)
					if maxDim > 0 then
						local factor = TARGET_MAX / maxDim
						local center = (minV + maxV) * 0.5
						for _, part in ipairs(allParts) do
							if part:IsA("BasePart") then
								part.Size = part.Size * factor
								local rot = part.CFrame - part.CFrame.Position
								local newPos = center + (part.Position - center) * factor
								part.CFrame = rot + newPos
							end
						end
						print(string.format("[Preloader/v4] %s: bbox %.1fx%.1fx%.1f → factor=%.3f → maxDim=%.2f (parts=%d)",
							name, extent.X, extent.Y, extent.Z, factor, maxDim * factor, basePartCount))
					end
				end
			end

			-- Weld all other BaseParts to PrimaryPart so parts stay together
			local primary = clone.PrimaryPart
			if primary then
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") and part ~= primary then
						local alreadyWelded = false
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("WeldConstraint") then
								alreadyWelded = true
								break
							end
						end
						if not alreadyWelded then
							local weld  = Instance.new("WeldConstraint")
							weld.Part0  = primary
							weld.Part1  = part
							weld.Parent = primary
						end
					end
				end
			end

			clone.Parent = folder
			blenderCount = blenderCount + 1

			-- One-time diagnostic: dump part details for select multipart items.
			-- Concatenate into a single print so Studio Output doesn't throttle.
			-- dump removed; was failing on InitialSize (not available in this Studio version)
			continue
		end
	end

	-- 2. Fall back to procedural Part model
	local ok, err = pcall(function()
		ItemModelBuilder.build(name, folder)
	end)
	if ok then
		proceduralCount = proceduralCount + 1
	else
		warn("[ItemModelPreloader] Failed to build " .. name .. ": " .. tostring(err))
	end
end

print(string.format("[ItemModelPreloader] Ready: %d Blender mesh, %d procedural",
	blenderCount, proceduralCount))
