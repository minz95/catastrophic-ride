-- GameManager.server.lua
-- Master phase state machine. Single authority over all phase transitions.
-- All other server managers listen to _phaseChanged BindableEvent
-- or subscribe via GameManager.onPhaseChanged().
-- Resolves: Issue #3

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants     = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents  = require(ReplicatedStorage.RemoteEvents)
local BiomeConfig   = require(ServerScriptService.Modules.BiomeConfig)
local HarnessConfig = require(ServerScriptService.Modules.HarnessConfig)
local Telemetry     = require(ServerScriptService.Modules.Telemetry)

local GameManager = {}

-- ─── Internal state ───────────────────────────────────────────────────────────

local _currentPhase  = Constants.PHASES.LOBBY
local _currentBiome  = nil
local _phaseTimer    = nil   -- active task.delay handle
local _callbacks     = {}    -- registered via onPhaseChanged()
local _harness       = nil   -- HarnessConfig.get() result; nil in normal play
local _round         = 0

-- ─── Public API ───────────────────────────────────────────────────────────────

function GameManager.getPhase()
	return _currentPhase
end

function GameManager.getBiome()
	return _currentBiome
end

function GameManager.onPhaseChanged(callback)
	table.insert(_callbacks, callback)
end

--- Harness args (see Modules/HarnessConfig), or nil in normal play.
function GameManager.getHarness()
	return _harness
end

function GameManager.getRound()
	return _round
end

-- Phase length, with harness overrides when a test asked for them.
local function _duration(phase, default)
	local d = _harness and _harness.durations and _harness.durations[phase]
	if type(d) == "number" then
		return d
	end
	return default
end

--- Effective length of a timed phase in seconds (harness overrides applied).
function GameManager.phaseDuration(phase)
	return _duration(phase, Constants.PHASE_DURATION[phase])
end

-- ─── Phase transition ─────────────────────────────────────────────────────────

-- `seconds`: how long the phase runs (nil = until something ends it). Clients
-- count down to the ReplicatedStorage attribute PhaseEndsAt (server time), so
-- every screen shows the server's real remaining time, harness overrides
-- included, even when the UI script started late.
local function _transition(newPhase, seconds)
	_currentPhase = newPhase
	ReplicatedStorage:SetAttribute("PhaseEndsAt", seconds and (workspace:GetServerTimeNow() + seconds) or nil)
	print("[GameManager] Phase →", newPhase)
	Telemetry.record("phase", { phase = newPhase, biome = _currentBiome, round = _round })

	-- Notify all registered server managers
	for _, cb in ipairs(_callbacks) do
		task.spawn(cb, newPhase, _currentBiome)
	end

	-- Notify all clients. The attributes let a client script that starts late
	-- (after the event went out) read the current phase and biome.
	ReplicatedStorage:SetAttribute("Phase", newPhase)
	ReplicatedStorage:SetAttribute("Biome", _currentBiome)
	RemoteEvents.PhaseChanged:FireAllClients(newPhase)
end

-- ─── Phase entry logic ────────────────────────────────────────────────────────

local function _startLobby()
	_transition(Constants.PHASES.LOBBY)

	if _harness then
		-- Harness: wait for the requested number of (bot) players, then go.
		local want    = _harness.players or 1
		local timeout = _harness.joinTimeout or 60
		local waited  = 0
		while #Players:GetPlayers() < want and waited < timeout do
			task.wait(0.5)
			waited += 0.5
		end
		task.wait(_harness.lobbyDelay or 3)
		_startFarming()
		return
	end

	if Constants.SOLO_TEST_MODE then
		-- In test mode: start immediately once at least 1 player is in.
		-- Wait 5s (up from 2s) so the client's character has time to load and
		-- StarterGui scripts can connect their PhaseChanged listeners before we fire.
		repeat task.wait(0.5) until #Players:GetPlayers() >= 1
		task.wait(5)
		_startFarming()
		return
	end

	-- Production: wait for MIN_TO_START or 30s timeout
	local waited = 0
	repeat
		task.wait(1)
		waited = waited + 1
	until #Players:GetPlayers() >= Constants.MIN_TO_START or waited >= 30
	_startFarming()
end

function _startFarming()
	-- Pick biome once per round (a harness may force one)
	_round += 1
	_currentBiome = (_harness and _harness.biome) or BiomeConfig.random()
	RemoteEvents.BiomeSelected:FireAllClients(_currentBiome)

	local seconds = _duration("FARMING", Constants.PHASE_DURATION.FARMING)
	_transition(Constants.PHASES.FARMING, seconds)

	-- Countdown and auto-advance
	_phaseTimer = task.delay(seconds, function()
		_startCrafting()
	end)
end

function _startCrafting()
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	local seconds = _duration("CRAFTING", Constants.PHASE_DURATION.CRAFTING)
	_transition(Constants.PHASES.CRAFTING, seconds)

	_phaseTimer = task.delay(seconds, function()
		_startRacing()
	end)
end

function _startRacing()
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	_transition(Constants.PHASES.RACING)

	-- Failsafe timeout, counted from GO (Modules/RaceStart)
	_phaseTimer = task.delay(_duration("RACING", Constants.RACING_TIMEOUT) + Constants.RACE_COUNTDOWN, function()
		_startResults({})
	end)
end

function _startResults(finishOrder)
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	_transition(Constants.PHASES.RESULTS)
	RemoteEvents.RaceFinished:FireAllClients(finishOrder)

	-- Wait for Play Again votes or 30s, then restart
	task.delay(_duration("RESULTS", Constants.PHASE_DURATION.RESULTS), function()
		_startLobby()
	end)
end

-- ─── External triggers ───────────────────────────────────────────────────────
-- Called by CraftingManager when all players submit early

function GameManager.allPlayersSubmittedCraft()
	if _currentPhase == Constants.PHASES.CRAFTING then
		task.cancel(_phaseTimer)
		_startRacing()
	end
end

-- Called by RacingManager when all players finish

function GameManager.raceComplete(finishOrder)
	if _currentPhase == Constants.PHASES.RACING then
		_startResults(finishOrder)
	end
end

-- ─── Boot ─────────────────────────────────────────────────────────────────────

task.spawn(function()
	_harness = HarnessConfig.get()
	if _harness and _harness.autoStart == false then
		print("[GameManager] Harness autoStart=false — game loop not started")
		return
	end
	_startLobby()
end)

return GameManager
