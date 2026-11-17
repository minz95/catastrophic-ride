-- StoreModelBake.lua
-- Studio only, by hand: puts the Creator Store items (Shared/StoreModels) into
-- the place as finished models, where ItemModelPreloader takes them first
-- (ServerStorage.ItemMeshes, or ServerStorage when that folder is missing).
--
-- Why: live servers build items from data with
-- AssetService:CreateMeshPartAsync, which loads only meshes the game's owner
-- owns. These meshes belong to their creators, so live games showed grey
-- labelled cubes while Studio (your login) showed the models. MeshParts saved
-- in the place render like any inserted free model.
--
-- Command bar, in the published place (edit mode), then File > Publish:
--   require(game.ServerScriptService.Modules.StoreModelBake)()
-- Run it again after store_models.py changes StoreModelData.
--
-- Junk Town's models (Shared/LobbyModels, Modules/LobbyModelData) go the same
-- way into ServerStorage.LobbyModels, where Maps/LobbyHub takes them.

local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function()
	local StoreModels    = require(game:GetService("ReplicatedStorage").Shared.StoreModels)
	local StoreModelData = require(ServerScriptService.Modules.StoreModelData)
	local ItemDataModel  = require(ServerScriptService.Modules.ItemDataModel)
	local folder = ServerStorage:FindFirstChild("ItemMeshes") or ServerStorage
	local done, failed = {}, {}
	for name in pairs(StoreModels) do
		local model = ItemDataModel.build(name, StoreModelData[name])
		if model then
			local old = folder:FindFirstChild(name)
			if old then old:Destroy() end
			model.Parent = folder
			table.insert(done, name)
		else
			table.insert(failed, name)
		end
	end
	local LobbyModels    = require(game:GetService("ReplicatedStorage").Shared.LobbyModels)
	local LobbyModelData = require(ServerScriptService.Modules.LobbyModelData)
	local lobby = ServerStorage:FindFirstChild("LobbyModels")
	if not lobby then
		lobby = Instance.new("Folder")
		lobby.Name = "LobbyModels"
		lobby.Parent = ServerStorage
	end
	local lobbyDone = 0
	for key in pairs(LobbyModels) do
		local model = LobbyModelData[key] and ItemDataModel.build(key, LobbyModelData[key])
		if model then
			local old = lobby:FindFirstChild(key)
			if old then old:Destroy() end
			model.Parent = lobby
			lobbyDone += 1
		elseif LobbyModelData[key] then
			table.insert(failed, "lobby " .. key)
		end   -- no data: refused by store_models.py (unions, a mesh that does not load)
	end
	table.sort(done); table.sort(failed)
	local msg = ("[StoreModelBake] %d models in %s, %d in %s; failed: %s"):format(
		#done, folder:GetFullName(), lobbyDone, lobby:GetFullName(), #failed > 0 and table.concat(failed, ", ") or "none")
	print(msg)
	return #done + lobbyDone, failed
end
