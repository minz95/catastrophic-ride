-- SessionManager.server.lua
-- Handles player join/leave, skin assignment, and per-player state.
-- Resolves: Issue #4

local Players             = game:GetService("Players")
local ServerStorage       = game:GetService("ServerStorage")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GameManager  = require(ServerScriptService.GameManager)

-- ─── PlayerData store ─────────────────────────────────────────────────────────
-- PlayerData[userId] = {
--   skinIndex    : number,
--   inventory    : { itemName: string }[],
--   vehicleStats : table | nil,
--   vehicleModel : Model | nil,
--   raceProgress : number,     -- 0–1200 along track axis
--   raceRank     : number,
--   finishTime   : number | nil,
--   stealCooldownEnd     : number,  -- tick()
--   stealInvincibleEnd   : number,  -- tick()
-- }

local PlayerData = {}
local SessionManager = {}

-- ─── Skin slot tracker ────────────────────────────────────────────────────────

local _takenSkins = {}   -- { [skinIndex] = userId }

local function _assignSkin(userId)
	for i = 1, Constants.SKIN_COUNT do
		if not _takenSkins[i] then
			_takenSkins[i] = userId
			return i
		end
	end
	return 1  -- fallback (shouldn't happen with MAX_PLAYERS ≤ SKIN_COUNT)
end

local function _freeSkin(userId)
	for i, uid in pairs(_takenSkins) do
		if uid == userId then
			_takenSkins[i] = nil
			return
		end
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function SessionManager.getData(player)
	return PlayerData[player.UserId]
end

function SessionManager.getAllData()
	return PlayerData
end

-- ─── Bots ─────────────────────────────────────────────────────────────────────
-- Server bots (Modules/FarmBots, Modules/RaceBots) stand in for players: a
-- proxy table { UserId (negative), Name, DisplayName, isBot = true,
-- Character = their NPC model or nil, profile }. Their data lives here like
-- a player's, so farming, abilities and race effects treat them the same.
-- They have no client: never FireClient to one (SessionManager.isBot).

local _bots = {}   -- [userId] = proxy

function SessionManager.isBot(who)
	return type(who) == "table" and who.isBot == true
end

function SessionManager.addBot(proxy)
	_bots[proxy.UserId] = proxy
	PlayerData[proxy.UserId] = PlayerData[proxy.UserId] or {
		skinIndex = 1, inventory = {}, vehicleStats = nil, vehicleModel = nil,
		raceProgress = 0, raceRank = 0, finishTime = nil, stealCooldownEnd = 0, stealInvincibleEnd = 0,
		bot = true,
	}
	return PlayerData[proxy.UserId]
end

function SessionManager.removeBot(userId)
	local d = PlayerData[userId]
	if d and d.vehicleModel and d.vehicleModel.Parent then d.vehicleModel:Destroy() end
	PlayerData[userId] = nil
	_bots[userId] = nil
end

--- Bot proxies, in id order (-100001 first).
function SessionManager.bots()
	local out = {}
	for _, b in pairs(_bots) do table.insert(out, b) end
	table.sort(out, function(a, b) return a.UserId > b.UserId end)
	return out
end

--- Players and bots.
function SessionManager.actors()
	local out = Players:GetPlayers()
	for _, b in ipairs(SessionManager.bots()) do table.insert(out, b) end
	return out
end

--- A player or a bot by id.
function SessionManager.actorById(userId)
	if type(userId) ~= "number" then return nil end
	return _bots[userId] or Players:GetPlayerByUserId(userId)
end

function SessionManager.setVehicle(player, model, stats)
	local d = PlayerData[player.UserId]
	if d then
		d.vehicleModel = model
		d.vehicleStats = stats
	end
end

function SessionManager.setRaceProgress(player, progress, rank)
	local d = PlayerData[player.UserId]
	if d then
		d.raceProgress = progress
		d.raceRank     = rank
	end
end

function SessionManager.setFinished(player, time)
	local d = PlayerData[player.UserId]
	if d then
		d.finishTime = time
	end
end

-- ─── Join handler ─────────────────────────────────────────────────────────────

local function _onPlayerAdded(player)
	local skinIndex = _assignSkin(player.UserId)

	PlayerData[player.UserId] = {
		skinIndex          = skinIndex,
		inventory          = {},
		vehicleStats       = nil,
		vehicleModel       = nil,
		raceProgress       = 0,
		raceRank           = 0,
		finishTime         = nil,
		stealCooldownEnd   = 0,
		stealInvincibleEnd = 0,
	}

	print(string.format("[SessionManager] %s joined → skin #%d", player.Name, skinIndex))

	-- Joined during a race or its results: watch until the next round
	local nowPhase = GameManager.getPhase()
	player:SetAttribute("Spectating", nowPhase == Constants.PHASES.RACING or nowPhase == Constants.PHASES.RESULTS)

	-- If mid-game, send current phase immediately (handles rejoins, but client
	-- scripts may not be connected yet on first join — handled by CharacterAdded below)
	local phase = GameManager.getPhase()
	if phase ~= Constants.PHASES.LOBBY then
		RemoteEvents.PhaseChanged:FireClient(player, phase)
		local biome = GameManager.getBiome()
		if biome then
			RemoteEvents.BiomeSelected:FireClient(player, biome)
		end
	end

	-- Re-send phase on every character load so StarterGui scripts (which run
	-- after the character spawns) reliably receive the current phase.
	-- Without this, clients miss PhaseChanged on first join if FARMING starts
	-- before their character has loaded and connected event listeners.
	-- Clients treat the same phase twice as this resend (never a new phase:
	-- the round always moves on), so it does not restart music, toasts,
	-- gauges or the crafting draft. The StarterGui scripts that restarted
	-- with the character start empty: the bag goes with it (FarmingUI's
	-- slots, CraftingUI's inventory).
	player.CharacterAdded:Connect(function()
		task.wait(0.5)  -- allow StarterGui LocalScripts to connect their OnClientEvent
		local currentPhase = GameManager.getPhase()
		RemoteEvents.PhaseChanged:FireClient(player, currentPhase)
		local currentBiome = GameManager.getBiome()
		if currentBiome then
			RemoteEvents.BiomeSelected:FireClient(player, currentBiome)
		end
		local data = PlayerData[player.UserId]
		if data and data.inventory then
			RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)
		end
	end)
end

-- ─── Leave handler ────────────────────────────────────────────────────────────

local function _onPlayerRemoving(player)
	local data = PlayerData[player.UserId]
	if not data then return end

	-- Clean up vehicle model if racing
	if data.vehicleModel and data.vehicleModel.Parent then
		data.vehicleModel:Destroy()
		data.vehicleModel = nil
	end

	_freeSkin(player.UserId)
	PlayerData[player.UserId] = nil

	print(string.format("[SessionManager] %s left — data cleaned up", player.Name))
end

-- ─── Per-round reset ──────────────────────────────────────────────────────────
-- Destroy spawned vehicles and clear per-round state when a new cycle begins.
-- Without this, the previous race's vehicle persisted in workspace and the
-- player stayed seated in it (BodyAngularVelocity / SuspensionHover kept the
-- chassis spinning in mid-air) when the FARMING phase of the next round
-- started, so players showed up in the new farm area still glued to the old
-- car.

local function _resetForNewRound()
	for _, data in pairs(PlayerData) do
		if data.vehicleModel and data.vehicleModel.Parent then
			data.vehicleModel:Destroy()
		end
		data.vehicleModel       = nil
		data.vehicleStats       = nil
		data.inventory          = {}
		data.raceProgress       = 0
		data.raceRank           = 0
		data.finishTime         = nil
		data.stealCooldownEnd   = 0
		data.stealInvincibleEnd = 0
	end

	-- LoadCharacter respawns at SpawnLocation. Required because destroying the
	-- VehicleSeat alone leaves the humanoid stranded mid-air where the seat
	-- used to be (SKY especially — vehicle hovers at Y≈80 with no ground
	-- beneath the player).
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function() player:LoadCharacter() end)
	end
end

GameManager.onPhaseChanged(function(phase)
	if phase == Constants.PHASES.LOBBY then
		_resetForNewRound()
	end
end)

-- ─── Wire up ──────────────────────────────────────────────────────────────────

-- Everyone plays from the next FARMING on.
GameManager.onPhaseChanged(function(phase)
	if phase == Constants.PHASES.FARMING then
		for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("Spectating", false) end
	end
end)

Players.PlayerAdded:Connect(_onPlayerAdded)
Players.PlayerRemoving:Connect(_onPlayerRemoving)

-- Handle players already in game when script loads (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(_onPlayerAdded, player)
end

return SessionManager
