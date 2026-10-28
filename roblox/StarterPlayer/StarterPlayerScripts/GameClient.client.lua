-- GameClient.client.lua
-- Central client orchestrator. Listens to PhaseChanged and routes
-- show/hide + enable/disable to all sub-modules.
-- Resolves: Issue #35, #38

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local LocalPlayer = Players.LocalPlayer

-- Lazy-load sub-modules (they may not all exist yet during dev)
local function safeRequire(path)
	local ok, mod = pcall(require, path)
	return ok and mod or nil
end

local Scripts = LocalPlayer:WaitForChild("PlayerScripts")

local FarmingClient  = safeRequire(Scripts:WaitForChild("FarmingClient",  5))
local CraftingClient = safeRequire(Scripts:WaitForChild("CraftingClient", 5))
local RacingClient   = safeRequire(Scripts:WaitForChild("RacingClient",   5))
local UIManager      = safeRequire(Scripts:WaitForChild("Modules", 5)
	and Scripts.Modules:WaitForChild("UIManager", 5))
local CameraController = safeRequire(Scripts:WaitForChild("Modules", 5)
	and Scripts.Modules:WaitForChild("CameraController", 5))

-- ─── Phase routing table ──────────────────────────────────────────────────────

local phaseHandlers = {
	[Constants.PHASES.LOBBY] = function(biome)
		if UIManager        then UIManager.setPhase("LOBBY", biome)     end
		if FarmingClient    then FarmingClient.disable()                 end
		if CraftingClient   then CraftingClient.disable()               end
		if RacingClient     then RacingClient.disable()                 end
		if CameraController then CameraController.setMode("default")    end
	end,

	[Constants.PHASES.FARMING] = function(biome)
		if UIManager        then UIManager.setPhase("FARMING", biome)   end
		if FarmingClient    then FarmingClient.enable()                  end
		if CraftingClient   then CraftingClient.disable()               end
		if RacingClient     then RacingClient.disable()                 end
		if CameraController then CameraController.setMode("default")    end
	end,

	[Constants.PHASES.CRAFTING] = function(biome)
		if UIManager        then UIManager.setPhase("CRAFTING", biome)  end
		if FarmingClient    then FarmingClient.disable()                 end
		if CraftingClient   then CraftingClient.enable()                end
		if RacingClient     then RacingClient.disable()                 end
		if CameraController then CameraController.setMode("crafting")   end
	end,

	[Constants.PHASES.RACING] = function(biome)
		if UIManager        then UIManager.setPhase("RACING", biome)    end
		if FarmingClient    then FarmingClient.disable()                 end
		if CraftingClient   then CraftingClient.disable()               end
		if RacingClient     then RacingClient.enable()                  end
		-- Camera mode set to "racing" after vehicle spawns (see VehicleSpawned below)
	end,

	[Constants.PHASES.RESULTS] = function(biome)
		if UIManager        then UIManager.setPhase("RESULTS", biome)   end
		if RacingClient     then RacingClient.disable()                 end
		if CameraController then CameraController.setMode("results")    end
	end,
}

-- ─── Wire up ──────────────────────────────────────────────────────────────────

local _currentBiome = nil

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	local handler = phaseHandlers[phase]
	if handler then
		handler(_currentBiome)
	else
		warn("[GameClient] Unknown phase:", phase)
	end
end)

RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	_currentBiome = biome
	if UIManager then UIManager.applyBiomeTheme(biome) end
end)

-- When the vehicle spawns: racing mode (the camera itself is RacingClient's)
RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, vehicleModel)
	if userId ~= LocalPlayer.UserId then return end
	if CameraController then
		CameraController.setMode("racing", vehicleModel)
	end
end)

-- ─── Boot into LOBBY by default ───────────────────────────────────────────────

local handler = phaseHandlers[Constants.PHASES.LOBBY]
if handler then handler(nil) end
