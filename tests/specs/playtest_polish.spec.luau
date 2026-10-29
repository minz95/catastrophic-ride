--!nocheck
-- Small things playtests found that a player should never see or hear.
local R = require("../lib/runner")
local fs = require("@lune/fs")
local Loader = require("../lib/loader")

local env = Loader.boot()
local SoundConfig = env.requirePath("ReplicatedStorage.Shared.SoundConfig")

R.describe("playtest polish", function()
	R.it("farm spawn markers are invisible in every biome (they floated as yellow plates)", function()
		for _, b in ipairs({ "Forest", "Ocean", "Sky" }) do
			local src = fs.readFile("roblox/ServerScriptService/Modules/Maps/" .. b .. "Map.lua")
			local i = src:find('Name = "FarmSpawnPoint"', 1, true)
			R.expect(i ~= nil).toBe(true)
			local blk = src:sub(i, (src:find("})", i, true)))
			R.expect(blk:find("Transparency = 1", 1, true) ~= nil).toBe(true)
		end
	end)

	R.it("race start and bumps are not loud bangs", function()
		-- the air horn at GO and a wall-impact thud on every bump
		for _, key in ipairs({ "COUNTDOWN_GO", "COLLISION" }) do
			local id = SoundConfig.SFX[key].id
			R.expect(id ~= "rbxassetid://9113071178" and id ~= "rbxassetid://9113437833").toBe(true)
		end
		R.expect(SoundConfig.SFX.COLLISION.volume).toBeLessThan(0.6)
		R.expect(SoundConfig.COLLISION_GAP).toBeGreaterThan(0)
	end)

	R.it("no effect is an explosion, crash or banned id (playtest 2026-10-29: bangs on every pickup and item use)", function()
		local banned = {}
		for _, id in ipairs(SoundConfig.BANNED) do banned["rbxassetid://" .. id] = true end
		local src = fs.readFile("roblox/ReplicatedStorage/Shared/SoundConfig.lua")
		local sfx = src:sub(src:find("SoundConfig.SFX = {", 1, true), src:find("SoundConfig.BANNED", 1, true))
		for _, word in ipairs({ "Explosion", "Crash", "Thud", "Big Thuds", "Air Horn" }) do
			R.expect(sfx:find(word, 1, true) == nil).toBe(true)
		end
		for key, cfg in pairs(SoundConfig.SFX) do
			if banned[cfg.id] then error(key .. " uses banned id " .. cfg.id) end
			R.expect(cfg.volume).toBeLessThan(0.81)
		end
	end)

	R.it("the pick-up bow leans forward (playtest 2026-10-30: +32° leant back, no pick-up showed)", function()
		local roblox = require("@lune/roblox")
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmFx.client.lua")
		local deg = tonumber(src:match("bendDown%s*=%s*A%(R%((%-?%d+)%)"))
		-- the waist pose turns the upper body in its parent's space (-Z forward)
		local up = roblox.CFrame.Angles(math.rad(deg), 0, 0).UpVector
		R.expect(up.Z).toBeLessThan(-0.6)
	end)

	R.it("every music tryout candidate has an id and a title", function()
		for slot, list in pairs(SoundConfig.TRY) do
			R.expect(#list).toBeGreaterThan(2)
			for _, t in ipairs(list) do
				R.expect(t.id:match("^%d+$") ~= nil).toBe(true)
				R.expect(#t.title).toBeGreaterThan(0)
			end
		end
	end)
end)

R.describe("a ridden item is the vehicle (playtest: 'pasted on the default car')", function()
	local roblox = require("@lune/roblox")
	local env2 = Loader.boot({ quiet = true })
	env2.run(env2.find("ServerScriptService.ItemModelPreloader"))
	local VB = env2.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VS = env2.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local VD = env2.requirePath("ServerScriptService.Modules.VehicleDesign")
	local IC = env2.requirePath("ReplicatedStorage.Shared.ItemConfig")
	R.it("a ridden item lies nose-forward (playtest 2026-10-29: rockets and the duck rode backwards)", function()
		local Mock = require("../lib/mock")
		local SS = env2.game:GetService("ServerStorage")
		-- where the template's `axis` (its own up for a lying item, its own
		-- +X for the duck, whose head is +X in the mesh) ends up on the vehicle
		local function dirOf(item, axis, biome)
			local m = VB.build(VS.calculate(IC[item], nil, nil, biome), biome, roblox.CFrame.new(), { BODY = item })
			local holder = m:FindFirstChild("Item_BODY_" .. item, true)
			local a
			for _, p in ipairs(holder:GetDescendants()) do if p:IsA("BasePart") then a = p break end end
			local b
			for _, p in ipairs(SS.ItemModels:FindFirstChild(item):GetDescendants()) do
				if p:IsA("BasePart") and p.Name == a.Name then b = p break end
			end
			local ca, cb = Mock.props(a).CFrame, Mock.props(b).CFrame
			return ca:VectorToWorldSpace(cb:VectorToObjectSpace(axis))
		end
		for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
			for _, item in ipairs({ "Rocket", "Soda Bottle" }) do
				R.expect(dirOf(item, roblox.Vector3.new(0, 1, 0), biome).Z).toBeLessThan(-0.9)
			end
			-- Studio gallery: the duck's head looked back with a +90° turn
			R.expect(VD.RIDE_LOOK["Rubber Duck"].yaw).toBe(-90)
		end
	end)

	R.it("a ridden plane's wings are grey and only a little wider than the item", function()
		local plain = VB.build(VS.calculate(IC.Pizza, nil, nil, "SKY"), "SKY", roblox.CFrame.new(), {})
		local m = VB.build(VS.calculate(IC.Pizza, nil, nil, "SKY"), "SKY", roblox.CFrame.new(), { BODY = "Pizza" })
		local wing, plainWing = m:FindFirstChild("Wing", true), plain:FindFirstChild("Wing", true)
		R.expect(wing.Color == VD.COLORS.metal).toBe(true)
		R.expect(plainWing.Color == VD.COLORS.metal).toBe(false)
		R.expect(wing.Size.X).toBeLessThan(plainWing.Size.X + 1e-6)
		R.expect(VD.RIDE_MIN.FOREST.X).toBeGreaterThan(4)
	end)
end)

R.describe("item guide (ItemGuideUI, J)", function()
	local src = fs.readFile("roblox/StarterGui/ItemGuideUI/init.client.lua")
	local IC = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local Blurbs = env.requirePath("ReplicatedStorage.Shared.ItemBlurbs")
	R.it("covers every Body / Engine / Special item, each with an ability line", function()
		local n = 0
		for name, cfg in pairs(IC) do
			if type(cfg) == "table" and cfg.slotType then
				R.expect(cfg.slotType == "BODY" or cfg.slotType == "ENGINE" or cfg.slotType == "SPECIAL").toBe(true)
				R.expect(Blurbs.ABILITY[name] ~= nil).toBe(true)
				n += 1
			end
		end
		R.expect(n).toBeGreaterThan(30)
	end)
	R.it("survives respawns, opens with J and shows new items from the pickup event", function()
		R.expect(src:find('old.Name == "ItemGuideUI"', 1, true) ~= nil).toBe(true)
		R.expect(src:find("KeyCode.J", 1, true) ~= nil).toBe(true)
		local fm = fs.readFile("roblox/ServerScriptService/FarmingManager.server.lua")
		R.expect(fm:find("item = item.itemName,", 1, true) ~= nil).toBe(true)
	end)
	R.it("opening the shop makes no sound", function()
		local shop = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		R.expect(shop:find('else SoundFx.play("SLOT_ASSIGN")', 1, true)).toBe(nil)
	end)
end)
