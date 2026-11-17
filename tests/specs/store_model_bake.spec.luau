--!nocheck
-- Playtest 2026-11-15 (phone, live game): the 22 Creator Store items were
-- grey cubes. Live servers load with AssetService:CreateMeshPartAsync only
-- meshes the game's owner owns; these belong to their creators. Studio (your
-- login) loads them, so Modules/StoreModelBake builds them there into
-- ServerStorage, saved with the place, and ItemModelPreloader takes a model
-- found there before the data. Junk Town's lobby models go the same way
-- (ServerStorage.LobbyModels, 2026-11-17).
local R = require("../lib/runner")
local Loader = require("../lib/loader")

R.describe("Creator Store items baked into the place", function()
	R.it("the bake leaves a finished model per store item, and the preloader uses it", function()
		local env = Loader.boot()
		local Mock = env.mock
		local AssetService = env.game:GetService("AssetService")
		local loaded = 0
		rawset(AssetService, "CreateMeshPartAsync", function(_, id)
			loaded += 1
			local p = Mock.Instance.new("MeshPart")
			p:SetAttribute("Mesh", id)
			return p
		end)
		local StoreModels = env.requirePath("ReplicatedStorage.Shared.StoreModels")
		local count, failed = env.requirePath("ServerScriptService.Modules.StoreModelBake")()
		local LobbyModels = env.requirePath("ReplicatedStorage.Shared.LobbyModels")
		local LobbyModelData = env.requirePath("ServerScriptService.Modules.LobbyModelData")
		local want = 0
		for _ in pairs(StoreModels) do want += 1 end
		for key in pairs(LobbyModels) do
			if LobbyModelData[key] then want += 1 end   -- no data: refused by store_models.py
		end
		R.expect(count).toBe(want)
		R.expect(failed).toBeEmpty("items the bake could not build")
		local ServerStorage = env.game:GetService("ServerStorage")
		-- Junk Town's models, where Maps/LobbyHub looks for them
		local lobby = ServerStorage:FindFirstChild("LobbyModels")
		for key in pairs(LobbyModelData) do
			R.expect(LobbyModels[key] ~= nil).toBe(true, key .. " has data but is not in the approved list")
			local m = lobby and lobby:FindFirstChild(key)
			R.expect(m ~= nil and m:FindFirstChildWhichIsA("BasePart", true) ~= nil).toBe(true, "lobby " .. key)
		end
		local folder = ServerStorage:FindFirstChild("ItemMeshes") or ServerStorage
		for name in pairs(StoreModels) do
			local m = folder:FindFirstChild(name)
			R.expect(m ~= nil and m:FindFirstChildWhichIsA("BasePart", true) ~= nil).toBe(true, name)
		end
		-- a live server has no mesh API that works for these: take it away,
		-- the preloader must still show the store items as their meshes
		rawset(AssetService, "CreateMeshPartAsync", nil)
		env.run(env.find("ServerScriptService.ItemModelPreloader"))
		local built = ServerStorage:FindFirstChild("ItemModels")
		for name in pairs(StoreModels) do
			local m = built:FindFirstChild(name)
			R.expect(m ~= nil and m:FindFirstChildWhichIsA("MeshPart", true) ~= nil).toBe(true, name .. " is a cube")
		end
		R.expect(loaded).toBeGreaterThan(0)
	end)
end)

return R
