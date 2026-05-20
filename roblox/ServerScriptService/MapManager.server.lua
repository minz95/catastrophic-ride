-- MapManager.server.lua
-- Biome random selection, map model loading/unloading, lighting/skybox swap.
-- Resolves: Issue #11

local Players             = game:GetService("Players")
local Lighting            = game:GetService("Lighting")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local BiomeConfig  = require(ServerScriptService.Modules.BiomeConfig)
local GameManager  = require(ServerScriptService.GameManager)

-- ─── Map folder convention ────────────────────────────────────────────────────
-- Each map lives under workspace.Maps.<BiomeName>Map as a Model.
-- The model is Disabled (invisible) by default; MapManager toggles visibility.
-- Studio maps tagged with CollectionService tags: MudZone, UpdraftZone, etc.

local MAP_FOLDER_NAME = "Maps"

local _currentBiome   = nil
local _mapsFolder     = nil

-- ─── Lighting presets ─────────────────────────────────────────────────────────

local LIGHTING_PRESETS = {
	FOREST = {
		Ambient          = Color3.fromRGB(80, 100, 60),
		OutdoorAmbient   = Color3.fromRGB(100, 130, 80),
		Brightness       = 2.5,
		ClockTime        = 12,
		FogEnd           = 800,
		FogColor         = Color3.fromRGB(180, 200, 150),
	},
	OCEAN = {
		Ambient          = Color3.fromRGB(60, 90, 130),
		OutdoorAmbient   = Color3.fromRGB(80, 130, 180),
		Brightness       = 3.0,
		ClockTime        = 14,
		FogEnd           = 1200,
		FogColor         = Color3.fromRGB(160, 200, 230),
	},
	SKY = {
		Ambient          = Color3.fromRGB(120, 100, 160),
		OutdoorAmbient   = Color3.fromRGB(160, 140, 200),
		Brightness       = 2.8,
		ClockTime        = 10,
		FogEnd           = 2000,
		FogColor         = Color3.fromRGB(200, 190, 230),
	},
}

local function _applyLighting(biome)
	local preset = LIGHTING_PRESETS[biome]
	if not preset then return end
	for prop, value in pairs(preset) do
		pcall(function() Lighting[prop] = value end)
	end
end

-- ─── Map visibility helpers ───────────────────────────────────────────────────

local function _getMapsFolder()
	if _mapsFolder then return _mapsFolder end
	_mapsFolder = workspace:FindFirstChild(MAP_FOLDER_NAME)
	if not _mapsFolder then
		-- Create placeholder folder if maps haven't been built yet
		_mapsFolder = Instance.new("Folder")
		_mapsFolder.Name   = MAP_FOLDER_NAME
		_mapsFolder.Parent = workspace
		warn("[MapManager] No Maps folder found in Workspace — biome maps not built yet (#8 #9 #10)")
	end
	return _mapsFolder
end

local function _hideAllMaps()
	local folder = _getMapsFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			child:SetAttribute("MapVisible", false)
			-- Hide all descendant BaseParts
			for _, desc in ipairs(child:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Transparency = 1
					desc.CanCollide   = false
				end
			end
		end
	end
end

local function _showMap(biome)
	local folder   = _getMapsFolder()
	local mapName  = biome:sub(1, 1):upper() .. biome:sub(2):lower() .. "Map"
	local mapModel = folder:FindFirstChild(mapName)

	if not mapModel then
		warn(string.format("[MapManager] Map model '%s' not found — build it in Studio (#8 #9 #10)", mapName))
		return false
	end

	mapModel:SetAttribute("MapVisible", true)
	for _, desc in ipairs(mapModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			local storedT  = desc:GetAttribute("OriginalTransparency")
			local storedCC = desc:GetAttribute("OriginalCanCollide")
			desc.Transparency = storedT  ~= nil and storedT  or 0
			desc.CanCollide   = storedCC ~= nil and storedCC or true
		end
	end
	return true
end

-- ─── Store original transparencies (called once at startup) ──────────────────

local function _cacheTransparencies()
	local folder = _getMapsFolder()
	for _, mapModel in ipairs(folder:GetChildren()) do
		for _, desc in ipairs(mapModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc:GetAttribute("OriginalTransparency") == nil then
					desc:SetAttribute("OriginalTransparency", desc.Transparency)
				end
				if desc:GetAttribute("OriginalCanCollide") == nil then
					desc:SetAttribute("OriginalCanCollide", desc.CanCollide)
				end
			end
		end
	end
end

-- ─── Biome selection ──────────────────────────────────────────────────────────

local function _selectAndLoadBiome()
	local biome = BiomeConfig.random()
	_currentBiome = biome

	_hideAllMaps()
	local loaded = _showMap(biome)
	_applyLighting(biome)

	-- Broadcast biome to all clients
	RemoteEvents.BiomeSelected:FireAllClients(biome)

	if loaded then
		print(string.format("[MapManager] Loaded biome: %s", biome))
	else
		print(string.format("[MapManager] Biome selected: %s (no map model yet)", biome))
	end

	return biome
end

-- ─── Sub-model visibility (FarmArea / RaceTrack) ─────────────────────────────

local function _setSubVisible(biome, subName, visible)
	local mapName  = biome:sub(1,1):upper() .. biome:sub(2):lower() .. "Map"
	local mapModel = _getMapsFolder():FindFirstChild(mapName)
	if not mapModel then return end
	local sub = mapModel:FindFirstChild(subName)
	if not sub then return end
	for _, desc in ipairs(sub:GetDescendants()) do
		if desc:IsA("BasePart") then
			if visible then
				local storedT  = desc:GetAttribute("OriginalTransparency")
				local storedCC = desc:GetAttribute("OriginalCanCollide")
				desc.Transparency = storedT  ~= nil and storedT  or 0
				desc.CanCollide   = storedCC ~= nil and storedCC or true
			else
				desc.Transparency = 1
				desc.CanCollide   = false
			end
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			-- GUIs ignore the Part.Transparency of their adornee, so the
			-- transparency loop above won't hide their text. Without this
			-- branch the floating checkpoint labels stayed visible all phases.
			desc.Enabled = visible
		end
	end
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

GameManager.onPhaseChanged(function(phase, biome)
	-- IMPORTANT: use the biome provided by GameManager (already authoritative).
	-- Never call BiomeConfig.random() here — GameManager owns biome selection.

	if phase == Constants.PHASES.FARMING then
		if not biome then return end
		_currentBiome = biome
		_hideAllMaps()
		_showMap(biome)
		_applyLighting(biome)
		-- Show farm area only; hide race track during farming phase
		_setSubVisible(biome, "FarmArea",  true)
		_setSubVisible(biome, "RaceTrack", false)

	elseif phase == Constants.PHASES.RACING then
		if not _currentBiome then return end
		-- Show race track; hide farm area during racing phase
		_setSubVisible(_currentBiome, "FarmArea",  false)
		_setSubVisible(_currentBiome, "RaceTrack", true)

	elseif phase == Constants.PHASES.RESULTS then
		task.delay(Constants.PHASE_DURATION.RESULTS or 15, function()
			_currentBiome = nil
		end)
	end
end)

-- ─── Expose current biome to other server modules ────────────────────────────

local MapManager = {}

function MapManager.getCurrentBiome()
	return _currentBiome
end

function MapManager.forceSelectBiome(biome)
	-- Used in testing / admin commands
	_currentBiome = nil
	_currentBiome = biome
	_hideAllMaps()
	_showMap(biome)
	_applyLighting(biome)
	RemoteEvents.BiomeSelected:FireAllClients(biome)
end

-- ─── Startup ─────────────────────────────────────────────────────────────────

-- Hide the default Roblox Baseplate so it doesn't show through transparent
-- water (Ocean) or below the SKY platforms.
local function _hideBaseplate()
	local bp = workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		bp.Transparency = 1
		bp.CanCollide   = false
	end
end

task.defer(_cacheTransparencies)
task.defer(_hideBaseplate)

return MapManager
