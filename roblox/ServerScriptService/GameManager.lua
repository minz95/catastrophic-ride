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

local _lastResults = nil

--- The finish order of the last race (set as RESULTS starts):
-- { { userId, time } … finishers in order, then { userId, dnf = true, progress } }.
function GameManager.getLastResults()
	return _lastResults
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

-- Phase timer: `fn` runs `seconds` from now (replacing the previous timer).
-- Kept so a phase can be shortened (GameManager.shortenPhase).
local _phaseEnd, _phaseEndsAt = nil, nil
local function _schedule(seconds, fn)
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	_phaseEnd = fn
	_phaseEndsAt = workspace:GetServerTimeNow() + seconds
	_phaseTimer = task.delay(seconds, function()
		_phaseEnd = nil
		fn()
	end)
end

--- Ends `phase` (if it is the current one) at most `seconds` from now and
-- moves the clients' countdown (PhaseEndsAt). Returns true when it did.
-- Crafting: once most players have submitted; racing: after the winner.
function GameManager.shortenPhase(phase, seconds, showClock)
	if _currentPhase ~= phase or not _phaseEnd then return false end
	local now = workspace:GetServerTimeNow()
	if _phaseEndsAt and _phaseEndsAt - now <= seconds then return false end
	_schedule(seconds, _phaseEnd)
	if showClock ~= false then ReplicatedStorage:SetAttribute("PhaseEndsAt", now + seconds) end
	Telemetry.record("phase_shortened", { phase = phase, seconds = seconds })
	return true
end

-- RacingManager: the standings when the race ends on its timer (finishers,
-- then everyone else by progress). Without it a timed-out race showed no one.
local _raceStandings = nil
function GameManager.setRaceStandings(fn)
	_raceStandings = fn
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

	if Constants.SOLO_TEST_MODE or RunService:IsStudio() then
		-- In test mode: start immediately once at least 1 player is in.
		-- Wait 5s (up from 2s) so the client's character has time to load and
		-- StarterGui scripts can connect their PhaseChanged listeners before we fire.
		repeat task.wait(0.5) until #Players:GetPlayers() >= 1
		task.wait(5)
		_startFarming()
		return
	end

	-- Live: count down LOBBY.MAX_WAIT (PhaseEndsAt, shown in the lobby);
	-- once MIN_TO_START players are in, at most LOBBY.FILL_SECONDS remain.
	-- Nobody here: wait without a clock.
	local L = Constants.LOBBY
	local endsAt = nil
	while true do
		local n = #Players:GetPlayers()
		local now = workspace:GetServerTimeNow()
		if n == 0 then
			endsAt = nil
			ReplicatedStorage:SetAttribute("PhaseEndsAt", nil)
		else
			local target = now + (n >= Constants.MIN_TO_START and L.FILL_SECONDS or L.MAX_WAIT)
			if not endsAt or target < endsAt then
				endsAt = target
				ReplicatedStorage:SetAttribute("PhaseEndsAt", endsAt)
			end
			if now >= endsAt then break end
		end
		task.wait(0.5)
	end
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
	_schedule(seconds, _startCrafting)
end

function _startCrafting()
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	local seconds = _duration("CRAFTING", Constants.PHASE_DURATION.CRAFTING)
	_transition(Constants.PHASES.CRAFTING, seconds)

	_schedule(seconds, _startRacing)
end

function _startRacing()
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	_transition(Constants.PHASES.RACING)

	-- Failsafe timeout, counted from GO (Modules/RaceStart). A winner's
	-- finish shortens it to Constants.FINISH_GRACE (RacingManager).
	_schedule(_duration("RACING", Constants.RACING_TIMEOUT) + Constants.RACE_COUNTDOWN, function()
		local ok, order = pcall(function() return _raceStandings and _raceStandings() end)
		_startResults((ok and order) or {})
	end)
end

function _startResults(finishOrder)
	if _phaseTimer then pcall(task.cancel, _phaseTimer) end
	_phaseEnd = nil
	_lastResults = finishOrder or {}
	local resultsFor = _duration("RESULTS", Constants.PHASE_DURATION.RESULTS)
	_transition(Constants.PHASES.RESULTS, resultsFor)   -- PhaseEndsAt: "next round in" on the results screen
	RemoteEvents.RaceFinished:FireAllClients(finishOrder)

	task.delay(resultsFor, function()
		_startLobby()
	end)
end

-- ─── External triggers ───────────────────────────────────────────────────────
-- Called by CraftingManager when all players submit early

function GameManager.allPlayersSubmittedCraft()
	if _currentPhase == Constants.PHASES.CRAFTING then
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
