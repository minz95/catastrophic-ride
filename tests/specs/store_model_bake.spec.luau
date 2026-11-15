--!nocheck
-- Playtest 2026-11-15 (phone, live game): the 22 Creator Store items were
-- grey cubes. Live servers load with AssetService:CreateMeshPartAsync only
-- meshes the game's owner owns; these belong to their creators. Studio (your
-- login) loads them, so Modules/StoreModelBake builds them there into
-- ServerStorage, saved with the place, and ItemModelPreloader takes a model
-- found there before the data.
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
		local want = 0
		for _ in pairs(StoreModels) do want += 1 end
		R.expect(count).toBe(want)
		R.expect(failed).toBeEmpty("items the bake could not build")
		local ServerStorage = env.game:GetService("ServerStorage")
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
