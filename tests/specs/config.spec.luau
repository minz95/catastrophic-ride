--!nocheck
-- Cross-file consistency of item, ability, asset and track configuration.
-- These are the "it says X in one file and Y in another" bugs that slip in
-- when files are edited in separate sessions.
local fs = require("@lune/fs")
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local ItemTypes = env.requirePath("ReplicatedStorage.Shared.ItemTypes")
local AbilityConfig = env.requirePath("ServerScriptService.Modules.AbilityConfig")
local MeshAssetIds = env.requirePath("ReplicatedStorage.Shared.MeshAssetIds")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
local ForestTrack = env.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
local SoundConfig = env.requirePath("ReplicatedStorage.Shared.SoundConfig")

local items = {}
for name, cfg in pairs(ItemConfig) do
	if type(cfg) == "table" and cfg.slotType then
		items[name] = cfg
	end
end
local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do table.insert(out, k) end
	table.sort(out)
	return out
end

local function serverSources()
	local out = {}
	local function walk(dir)
		for _, n in ipairs(fs.readDir(dir)) do
			local p = dir .. "/" .. n
			if fs.isDir(p) then walk(p) elseif n:match("%.lua$") then out[p] = fs.readFile(p) end
		end
	end
	walk("roblox")
	return out
end
local SOURCES = serverSources()

R.describe("items", function()
	R.it("every item has slotType, rarity, icon and a known rarity tier", function()
		local bad = {}
		for _, name in ipairs(sortedKeys(items)) do
			local c = items[name]
			if not (c.rarity and Constants.RARITY_STAT_MULT[c.rarity]) then table.insert(bad, name .. ": rarity " .. tostring(c.rarity)) end
			if not c.icon then table.insert(bad, name .. ": no icon") end
			if c.slotType ~= "BODY" and c.slotType ~= "ENGINE" and c.slotType ~= "SPECIAL" then
				table.insert(bad, name .. ": slotType " .. tostring(c.slotType))
			end
		end
		R.expect(bad).toBeEmpty("malformed items")
	end)

	R.it("ItemTypes.ALL lists exactly the ItemConfig items with the same slot", function()
		local bad, seen = {}, {}
		for _, e in ipairs(ItemTypes.ALL) do
			seen[e.name] = true
			local c = items[e.name]
			if not c then
				table.insert(bad, "ItemTypes has '" .. e.name .. "' but ItemConfig does not")
			elseif c.slotType ~= e.slotType then
				table.insert(bad, e.name .. ": ItemTypes " .. e.slotType .. " vs ItemConfig " .. c.slotType)
			end
		end
		for _, name in ipairs(sortedKeys(items)) do
			if not seen[name] then table.insert(bad, "ItemConfig has '" .. name .. "' but ItemTypes does not") end
		end
		R.expect(bad).toBeEmpty("ItemTypes / ItemConfig mismatches")
	end)

	R.it("every item has an FBX model in assets/items", function()
		local missing = {}
		for _, name in ipairs(sortedKeys(items)) do
			if not fs.isFile("assets/items/" .. name .. ".fbx") then table.insert(missing, name) end
		end
		R.expect(missing).toBeEmpty("items without assets/items/<name>.fbx")
	end)

	R.known("MeshAssetIds only lists current items", "MeshAssetIds still has entries for removed/never-added items", function()
		local orphans = {}
		for _, name in ipairs(sortedKeys(MeshAssetIds)) do
			if not items[name] then table.insert(orphans, name) end
		end
		R.expect(orphans).toBeEmpty("MeshAssetIds keys with no ItemConfig item")
	end)

	R.known("Studio preview plugin lists current items", "studio-plugin ITEM_NAMES predates the #88 roster change", function()
		local src = fs.readFile("studio-plugin/MapPreviewPlugin.server.lua")
		local block = src:match("local ITEM_NAMES = (%b{})")
		local stale = {}
		for name in block:gmatch('"([^"]+)"') do
			if not items[name] then table.insert(stale, name) end
		end
		R.expect(stale).toBeEmpty("plugin ITEM_NAMES entries that are not items")
	end)
end)

R.describe("abilities", function()
	local amSrc = SOURCES["roblox/ServerScriptService/AbilityManager.server.lua"]
	local handlers = {}
	-- Definitions (`EFFECTS.x = function`) and aliases (`EFFECTS.x = EFFECTS.y`)
	for name in amSrc:gmatch("\nEFFECTS%.([%w_]+)%s*=[^=]") do handlers[name] = true end
	for name in amSrc:gmatch("function%s+EFFECTS%.([%w_]+)") do handlers[name] = true end

	R.it("AbilityManager defines effect handlers", function()
		R.expect(#sortedKeys(handlers)).toBeGreaterThan(20)
	end)

	R.known("every item has an AbilityConfig entry", "Drill (Rare ENGINE) has no ability, so pressing E with it does nothing", function()
		local missing = {}
		for _, name in ipairs(sortedKeys(items)) do
			if type(AbilityConfig[name]) ~= "table" then table.insert(missing, name) end
		end
		R.expect(missing).toBeEmpty("items with no ability")
	end)

	R.known("every effectKey has a handler in AbilityManager",
		"these abilities fire, consume their cooldown and do nothing (AbilityManager warns 'No effect handler')",
		function()
			local missing = {}
			for _, item in ipairs(sortedKeys(AbilityConfig)) do
				local cfg = AbilityConfig[item]
				if type(cfg) == "table" and cfg.effectKey then
					if not handlers[cfg.effectKey] then
						table.insert(missing, item .. " → " .. cfg.effectKey)
					end
					for biome, v in pairs(cfg.biomeEffect or {}) do
						if v.effectKey and not handlers[v.effectKey] then
							table.insert(missing, item .. " (" .. biome .. ") → " .. v.effectKey)
						end
					end
				end
			end
			R.expect(missing).toBeEmpty("abilities whose effectKey has no handler")
		end)

	R.known("HEAD/TAIL passives are read by game code",
		"VehicleStats.HEAD_PASSIVES / TAIL_PASSIVES are defined but nothing reads them, so HEAD/TAIL slots are cosmetic",
		function()
			local users = {}
			for path, src in pairs(SOURCES) do
				if not path:find("VehicleStats") and (src:find("HEAD_PASSIVES", 1, true) or src:find("TAIL_PASSIVES", 1, true)) then
					table.insert(users, path)
				end
			end
			R.expect(#users).toBeGreaterThan(0)
		end)
end)

R.describe("biomes", function()
	R.known("every BiomeConfig hazard type is implemented",
		"fallingLog / waveFlood / gustZone are configured but no code spawns them",
		function()
			local missing = {}
			for _, biome in ipairs(Constants.BIOMES) do
				for _, hz in ipairs(BiomeConfig[biome].hazards or {}) do
					local used = false
					for path, src in pairs(SOURCES) do
						if not path:find("BiomeConfig") and (src:find('"' .. hz.type .. '"', 1, true) or (hz.tag and src:find('"' .. hz.tag .. '"', 1, true))) then
							used = true
							break
						end
					end
					if not used then table.insert(missing, biome .. ": " .. hz.type) end
				end
			end
			R.expect(missing).toBeEmpty("hazards with no implementation")
		end)

	R.it("FOREST track data agrees with Constants and BiomeConfig", function()
		local t = Constants.TRACK.FOREST
		R.expect(ForestTrack.finishZ).toBe(t.zFinish)
		R.expect(ForestTrack.nodes[1][2]).toBe(t.zStart)
		R.expect(ForestTrack.width).toBe(t.width)
		local startZ = BiomeConfig.FOREST.raceStartZ
		R.expect(startZ).toBe(ForestTrack.startGrid.rows[1])
	end)
end)

R.describe("audio", function()
	R.known("every sound has an asset id", "BGM and ambience ids in SoundConfig are still empty placeholders", function()
		local empty = {}
		local function scan(prefix, t)
			for k, v in pairs(t) do
				if type(v) == "table" then
					if v.id ~= nil and (v.id == "" or v.id == "rbxassetid://0") then
						table.insert(empty, prefix .. tostring(k))
					else
						scan(prefix .. tostring(k) .. ".", v)
					end
				end
			end
		end
		scan("", SoundConfig)
		table.sort(empty)
		R.expect(empty).toBeEmpty("sounds without an id")
	end)
end)
