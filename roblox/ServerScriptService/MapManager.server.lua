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
local MapVisibility = require(ServerScriptService.Modules.MapVisibility)
local TerrainPainter = require(ServerScriptService.Modules.TerrainPainter)

-- ─── Map folder convention ────────────────────────────────────────────────────
-- Each map lives under workspace.Maps.<BiomeName>Map as a Model.
-- The model is Disabled (invisible) by default; MapManager toggles visibility.
-- Studio maps tagged with CollectionService tags: MudZone, UpdraftZone, etc.

local MAP_FOLDER_NAME = "Maps"

local _currentBiome   = nil
local _mapsFolder     = nil

-- ─── Lighting presets ─────────────────────────────────────────────────────────

local LIGHTING_PRESETS = require(ServerScriptService.Modules.LightingPresets)

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
	MapVisibility.hideAll(_getMapsFolder())
end

local function _showMap(biome)
	local mapName  = MapVisibility.mapName(biome)
	local mapModel = _getMapsFolder():FindFirstChild(mapName)

	if not mapModel then
		warn(string.format("[MapManager] Map model '%s' not found — build it in Studio (#8 #9 #10)", mapName))
		return false
	end

	return MapVisibility.show(mapModel)
end

-- ─── Store original transparencies (called once at startup) ──────────────────

local function _cacheTransparencies()
	MapVisibility.cacheOriginals(_getMapsFolder())
end

-- ─── Biome selection ──────────────────────────────────────────────────────────

local function _selectAndLoadBiome()
	local biome = BiomeConfig.random()
	_currentBiome = biome

	_hideAllMaps()
	local loaded = _showMap(biome)
	_applyLighting(biome)
	TerrainPainter.paint(biome)

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
	local mapModel = _getMapsFolder():FindFirstChild(MapVisibility.mapName(biome))
	MapVisibility.setSubVisible(mapModel, subName, visible)
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

GameManager.onPhaseChanged(function(phase, biome)
	-- IMPORTANT: use the biome provided by GameManager (already authoritative).
	-- Never call BiomeConfig.random() here — GameManager owns biome selection.

	if phase == Constants.PHASES.FARMING then
		if not biome then return end
		_currentBiome = biome
		-- the map with its farm area, every other map and the race track hidden
		local folder = _getMapsFolder()
		local mapModel = folder:FindFirstChild(MapVisibility.mapName(biome))
		if not mapModel then
			warn(string.format("[MapManager] Map model '%s' not found", MapVisibility.mapName(biome)))
		end
		MapVisibility.applyPhase(folder, mapModel, "FarmArea")
		_applyLighting(biome)
		TerrainPainter.paint(biome)

	elseif phase == Constants.PHASES.RACING then
		if not _currentBiome then return end
		-- Show race track; hide farm area during racing phase
		local folder = _getMapsFolder()
		MapVisibility.applyPhase(folder, folder:FindFirstChild(MapVisibility.mapName(_currentBiome)), "RaceTrack")

	elseif phase == Constants.PHASES.LOBBY then
		-- at LOBBY, not on a RESULTS-length timer: a shortened RESULTS let
		-- that timer fire during the next FARMING (no track at RACING)
		_currentBiome = nil
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
	TerrainPainter.paint(biome)
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
