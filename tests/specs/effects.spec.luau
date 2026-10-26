--!nocheck
-- Ability wiring between server and clients, checked on the sources and the
-- shared modules (the client scripts themselves do not run under Lune).
--
-- History (2026-10-21): E never fired an ability in a real game (RacingClient
-- read a PlayerGui folder nothing created), three client listeners read the
-- AbilityActivated arguments in the wrong order, and ten ScreenEffect names
-- the server sent had no client handler. None of it errored.
local fs = require("@lune/fs")
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local roblox = require("@lune/roblox")

local function read(path) return fs.readFile("roblox/" .. path) end

local function walk(dir, out)
	for _, name in ipairs(fs.readDir(dir)) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then walk(p, out) elseif name:match("%.luau?$") then table.insert(out, p) end
	end
	return out
end

-- Read every source up front (fs is async; see CLAUDE.md).
local SOURCES = {}
for _, p in ipairs(walk("roblox", {})) do SOURCES[p] = fs.readFile(p) end
local CLIENT = {
	read("StarterPlayer/StarterPlayerScripts/RacingClient.client.lua"),
	read("StarterPlayer/StarterPlayerScripts/ParticleClient.client.lua"),
	read("StarterPlayer/StarterPlayerScripts/EffectFx.client.lua"),
}
local env = Loader.boot()
local EffectLook = env.requirePath("ReplicatedStorage.Shared.EffectLook")
local AbilitySlots = env.requirePath("ReplicatedStorage.Shared.AbilitySlots")

R.describe("effect wiring", function()
	R.it("every ScreenEffect the server sends has a client handler", function()
		local missing = {}
		for path, src in pairs(SOURCES) do
			if path:find("ServerScriptService") then
				for name in src:gmatch('ScreenEffect:Fire%w*%([^,]*,%s*"(%w+)"') do
					local handled = EffectLook.SCREEN[name] ~= nil
					for _, c in ipairs(CLIENT) do
						if c:find('effectName == "' .. name .. '"', 1, true) then handled = true end
					end
					if not handled then missing[name] = path end
				end
			end
		end
		local list = {}
		for k, v in pairs(missing) do table.insert(list, k .. " (" .. v .. ")") end
		R.expect(list).toBeEmpty("ScreenEffect names nobody draws")
	end)

	R.it("every literal EffectFx key in the server has a look", function()
		local missing = {}
		for path, src in pairs(SOURCES) do
			if path:find("ServerScriptService") then
				for key in src:gmatch('EffectFx%.play%(%s*"(%w+)"') do
					if not EffectLook.CAR[key] then table.insert(missing, key .. " (" .. path .. ")") end
				end
			end
		end
		R.expect(missing).toBeEmpty("EffectFx keys without EffectLook.CAR")
	end)

	R.it("every ability effectKey has a look (self effects use it as their key)", function()
		local missing = {}
		local src = read("ServerScriptService/Modules/AbilityConfig.lua")
		for key in src:gmatch('effectKey%s*=%s*"(%w+)"') do
			if not EffectLook.CAR[key] and not ({ slipperyPuddle = 1, waterPuddle = 1, waterPuddleLarge = 1,
				cactusObstacle = 1, logObstacle = 1, steamCloud = 1 })[key] then   -- drops use "dropTrap"
				table.insert(missing, key)
			end
		end
		R.expect(missing).toBeEmpty("ability effectKeys without a look")
	end)

	R.it("AbilityActivated listeners take (userId, itemName, targetIds, effectKey, info)", function()
		local bad = {}
		for path, src in pairs(SOURCES) do
			for args in src:gmatch("AbilityActivated%.OnClientEvent:Connect%(function%(([^)]*)%)") do
				local n = select(2, args:gsub(",", ","))
				if n >= 2 and not args:find("targetIds") and not args:find("_targets") then
					table.insert(bad, path .. ": (" .. args .. ")")
				end
			end
		end
		R.expect(bad).toBeEmpty("listeners that read effectKey from the targetIds position")
	end)

	R.it("no client script moves a car by tweening its CFrame", function()
		local bad = {}
		for path, src in pairs(SOURCES) do
			if path:find("StarterPlayer") or path:find("StarterGui") then
				if src:find("TweenService:Create%(part,") or src:find("part%.CFrame = part%.CFrame %*") then
					table.insert(bad, path)
				end
			end
		end
		R.expect(bad).toBeEmpty("scripts that tween a vehicle part")
	end)
end)

R.describe("AbilitySlots", function()
	local slots = { SPECIAL = "Pizza", ENGINE = "Rocket", BODY = "Log", HEAD = "Cactus" }

	R.it("only BODY / ENGINE / SPECIAL items can fire", function()
		R.expect(AbilitySlots.slotOf(slots, "Rocket")).toBe("ENGINE")
		R.expect(AbilitySlots.slotOf(slots, "Cactus")).toBe(nil)
		R.expect(AbilitySlots.slotOf(nil, "Rocket")).toBe(nil)
	end)

	R.it("E picks the next item that is off cooldown, in order", function()
		R.expect(AbilitySlots.pick(slots, {}, 0, 1)).toBe("Pizza")
		R.expect(AbilitySlots.pick(slots, {}, 0, 2)).toBe("Rocket")
		R.expect(AbilitySlots.pick(slots, { Pizza = 5 }, 0, 1)).toBe("Rocket")
		R.expect(AbilitySlots.pick(slots, {}, 0, 4)).toBe("Pizza")   -- wraps
		local item, _, soonest, at = AbilitySlots.pick(slots, { Pizza = 5, Rocket = 3, Log = 9 }, 0, 1)
		R.expect(item).toBe(nil)
		R.expect(soonest).toBe("Rocket")
		R.expect(at).toBe(3)
		R.expect(AbilitySlots.pick({}, {}, 0, 1)).toBe(nil)
	end)

	R.it("VehicleBuilder writes the car's ability items onto the model", function()
		local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
		local model = VehicleBuilder.build(VehicleStats.calculate(nil, nil, nil, "FOREST"), "FOREST",
			roblox.CFrame.new(0, 2, 0), { SPECIAL = "Pizza", ENGINE = "Rocket", HEAD = "Cactus" })
		local back = AbilitySlots.read(model)
		R.expect(back.SPECIAL).toBe("Pizza")
		R.expect(back.ENGINE).toBe("Rocket")
		R.expect(back.BODY).toBe(nil)
		R.expect(back.HEAD).toBe(nil)
	end)
end)

-- 2026-10-26: the floating words ("STOLEN!", "RAM!") of two cars or players
-- side by side ran into each other in the trailer footage.
R.describe("effect words", function()
	R.it("are small (EffectLook.TEXT), one per car, and both effect scripts use that size", function()
		local env = Loader.boot()
		local T = env.requirePath("ReplicatedStorage.Shared.EffectLook").TEXT
		R.expect(T.W <= 130 and T.H <= 28).toBe(true)
		R.expect(T.BIG_W <= 170 and T.BIG_H <= 36).toBe(true)
		R.expect(T.SCREEN_H <= 0.07 and T.SCREEN_MAX_PX <= 44).toBe(true)
		local fx = read("StarterPlayer/StarterPlayerScripts/EffectFx.client.lua")
		local farm = read("StarterPlayer/StarterPlayerScripts/FarmFx.client.lua")
		R.expect(fx:find("T.BIG_W or T.W", 1, true) ~= nil).toBe(true)
		R.expect(fx:find('old.Name == "EffectLabel"', 1, true) ~= nil).toBe(true)
		R.expect(fx:find("UITextSizeConstraint", 1, true) ~= nil).toBe(true)
		R.expect(farm:find("EffectLook.TEXT.W", 1, true) ~= nil).toBe(true)
	end)
end)
