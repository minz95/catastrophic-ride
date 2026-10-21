-- SoundClient.client.lua
-- Handles all client-side audio: BGM fade, biome ambience, SFX playback.
-- Resolves: Issue #73

local Players          = game:GetService("Players")
local SoundService     = game:GetService("SoundService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local SoundConfig  = require(ReplicatedStorage.Shared.SoundConfig)
local LocalPlayer  = Players.LocalPlayer

-- ─── Sound cache ─────────────────────────────────────────────────────────────

local _sfxCache     = {}   -- key → Sound instance (one-shot pool)
local _bgmInstance  = nil  -- current BGM Sound
local _ambiSounds   = {}   -- current ambience Sound list
local _currentBiome = nil

-- ─── Sound builder ───────────────────────────────────────────────────────────

local function _makeSound(cfg, parent)
	if not cfg or not cfg.id or cfg.id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId    = cfg.id
	s.Volume     = cfg.volume or 0.5
	s.Looped     = cfg.looped or false
	s.RollOffMaxDistance = 0   -- 2D sound (no rolloff)
	if cfg.pitch then
		local pitch = Instance.new("PitchShiftSoundEffect")
		pitch.Octave = cfg.pitch
		pitch.Parent = s
	end
	s.Parent = parent or SoundService
	return s
end

-- ─── One-shot SFX ─────────────────────────────────────────────────────────────

local function _playSFX(key)
	local cfg = SoundConfig.SFX[key]
	if not cfg then return end

	-- Reuse cached sound if not playing
	local s = _sfxCache[key]
	if not s or not s.Parent then
		s = _makeSound(cfg, SoundService)
		_sfxCache[key] = s
	end
	if not s then return end  -- empty id, skip

	-- Clone for overlapping hits
	if s.IsPlaying then
		local clone = s:Clone()
		clone.Parent = SoundService
		clone:Play()
		game:GetService("Debris"):AddItem(clone, 5)
	else
		s:Play()
	end
end

-- ─── BGM management ──────────────────────────────────────────────────────────

local function _fadeBGM(targetVolume, duration, callback)
	if not _bgmInstance then
		if callback then callback() end
		return
	end
	TweenService:Create(_bgmInstance, TweenInfo.new(duration or 0.8, Enum.EasingStyle.Quad), {
		Volume = targetVolume
	}):Play()
	if callback then
		task.delay(duration or 0.8, callback)
	end
end

local function _playBGM(cfg)
	if not cfg or not cfg.id or cfg.id == "" then return end

	-- Fade out current BGM
	_fadeBGM(0, 0.8, function()
		if _bgmInstance then
			_bgmInstance:Destroy()
			_bgmInstance = nil
		end
		local s = _makeSound(cfg, SoundService)
		if not s then return end
		s.Volume = 0
		s:Play()
		_bgmInstance = s
		TweenService:Create(s, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
			Volume = cfg.volume
		}):Play()
	end)
end

-- ─── Biome ambience ───────────────────────────────────────────────────────────

local function _stopAmbience()
	for _, s in ipairs(_ambiSounds) do
		TweenService:Create(s, TweenInfo.new(1.0), { Volume = 0 }):Play()
		task.delay(1.0, function() if s and s.Parent then s:Destroy() end end)
	end
	_ambiSounds = {}
end

local function _startAmbience(biome)
	_stopAmbience()
	local ambiList = SoundConfig.AMBIENCE[biome]
	if not ambiList then return end
	for _, cfg in ipairs(ambiList) do
		local s = _makeSound(cfg, SoundService)
		if not s then continue end
		s.Volume = 0
		s:Play()
		TweenService:Create(s, TweenInfo.new(2.0), { Volume = cfg.volume }):Play()
		table.insert(_ambiSounds, s)
	end
end

-- ─── Phase → BGM routing ──────────────────────────────────────────────────────

local function _onPhaseChanged(phase)
	_playSFX("PHASE_TRANSITION")

	if phase == Constants.PHASES.LOBBY then
		_playBGM(SoundConfig.BGM.LOBBY)
		_stopAmbience()

	elseif phase == Constants.PHASES.FARMING then
		local biome = _currentBiome or "FOREST"
		local cfg   = SoundConfig.BGM.FARMING[biome] or SoundConfig.BGM.FARMING.FOREST
		_playBGM(cfg)
		_startAmbience(biome)

	elseif phase == Constants.PHASES.CRAFTING then
		_playBGM(SoundConfig.BGM.CRAFTING)
		_stopAmbience()

	elseif phase == Constants.PHASES.RACING then
		local biome = _currentBiome or "FOREST"
		local cfg   = SoundConfig.BGM.RACING[biome] or SoundConfig.BGM.RACING.FOREST
		_playBGM(cfg)
		_startAmbience(biome)

	elseif phase == Constants.PHASES.RESULTS then
		_stopAmbience()
		-- BGM played after we know finish rank (see RaceFinished below)
	end
end

RemoteEvents.PhaseChanged.OnClientEvent:Connect(_onPhaseChanged)

RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	_currentBiome = biome
end)

-- ─── ScreenEffect → SFX ───────────────────────────────────────────────────────

RemoteEvents.ScreenEffect.OnClientEvent:Connect(function(effectName, params)
	if effectName == "collision"       then _playSFX("COLLISION")
	elseif effectName == "mudWarning"  then _playSFX("MUD_ENTER")
	elseif effectName == "updraftWarning" then _playSFX("UPDRAFT_ENTER")
	elseif effectName == "boostStart"  then _playSFX("BOOST_ACTIVATE")
	elseif effectName == "boostPad"    then _playSFX("BOOST_PAD")
	elseif effectName == "respawn"     then _playSFX("RESPAWN")
	elseif effectName == "bubblePop"   then _playSFX("BUBBLE_POP")
	elseif effectName == "driftStart"  then _playSFX("DRIFT_START")
	elseif effectName == "driftSlingshot" then _playSFX("DRIFT_SLINGSHOT")
	end
end)

-- ─── Ability SFX ─────────────────────────────────────────────────────────────

RemoteEvents.AbilityActivated.OnClientEvent:Connect(function(userId, itemName, effectKey)
	if userId ~= LocalPlayer.UserId then return end
	local sfxKey = SoundConfig.ABILITY_SFX[effectKey] or "ABILITY_GENERIC"
	_playSFX(sfxKey)
end)

-- ─── Farming SFX ─────────────────────────────────────────────────────────────

RemoteEvents.ItemPickedUp.OnClientEvent:Connect(function(pickupData)
	if pickupData and pickupData.userId == LocalPlayer.UserId then
		local rarity = pickupData.rarity or "Common"
		if rarity == "Epic" then
			_playSFX("ITEM_PICKUP_EPIC")
		elseif rarity == "Rare" then
			_playSFX("ITEM_PICKUP_RARE")
		else
			_playSFX("ITEM_PICKUP")
		end
	end
end)

RemoteEvents.ContestUpdate.OnClientEvent:Connect(function(data)
	if data and data.phase == "start" then
		_playSFX("CONTEST_START")
	end
end)

-- FarmingManager fires (itemId, winnerUserId) to everyone; only the two
-- contestants hear a result (they got ContestUpdate for this item).
local _myContests = {}
RemoteEvents.ContestUpdate.OnClientEvent:Connect(function(itemId)
	_myContests[itemId] = true
end)
RemoteEvents.ContestResult.OnClientEvent:Connect(function(itemId, winnerUserId)
	if _myContests[itemId] then
		_myContests[itemId] = nil
		if winnerUserId == LocalPlayer.UserId then
			_playSFX("CONTEST_WIN")
		else
			_playSFX("CONTEST_LOSE")
		end
	end
end)

-- FarmingManager fires (thiefName, victimName, itemName) to everyone.
RemoteEvents.ItemStolen.OnClientEvent:Connect(function(_thiefName, victimName)
	if victimName == LocalPlayer.Name then
		_playSFX("ITEM_STOLEN")
	end
end)

-- ─── Race finish SFX ─────────────────────────────────────────────────────────

RemoteEvents.RaceFinished.OnClientEvent:Connect(function(finishOrder)
	for rank, entry in ipairs(finishOrder) do
		if entry.userId == LocalPlayer.UserId then
			if rank == 1 then
				_playBGM(SoundConfig.BGM.RESULTS_WIN)
				_playSFX("FINISH_1ST")
			else
				_playBGM(SoundConfig.BGM.RESULTS_LOSE)
				_playSFX("FINISH_OTHER")
			end
			break
		end
	end
end)

-- ─── Countdown SFX ───────────────────────────────────────────────────────────
-- Listen to a countdown timer firing from GameClient
-- (or we can listen to a dedicated RemoteEvent if added)

local _countdownConn = nil

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if _countdownConn then _countdownConn:Disconnect(); _countdownConn = nil end

	if phase == Constants.PHASES.RACING then
		-- 3-2-1-Go, on the server's GO time (ReplicatedStorage "RaceGoAt",
		-- Modules/RaceStart); the cars leave the grid on the GO sound.
		local beepsFired = {}
		_countdownConn = game:GetService("RunService").Heartbeat:Connect(function()
			local goAt = ReplicatedStorage:GetAttribute("RaceGoAt")
			if type(goAt) ~= "number" then return end
			local left = goAt - workspace:GetServerTimeNow()
			for i, t in ipairs({ 3, 2, 1 }) do
				if left <= t and left > 0 and not beepsFired[i] then
					beepsFired[i] = true
					_playSFX("COUNTDOWN_BEEP")
				end
			end
			if left <= 0 and not beepsFired[4] then
				beepsFired[4] = true
				_playSFX("COUNTDOWN_GO")
				if _countdownConn then _countdownConn:Disconnect(); _countdownConn = nil end
			end
		end)
	end
end)

-- ─── Timer low warning ────────────────────────────────────────────────────────
-- When phase timer drops below 10s (client tracks via PhaseChanged timestamp)

local _phaseStartTick = 0
local _timerWarned   = false

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	_phaseStartTick = tick()
	_timerWarned    = false
end)

game:GetService("RunService").Heartbeat:Connect(function()
	if _timerWarned then return end
	local phase = nil  -- would need to track current phase
	-- Simplified: warn at 10s remaining for farming/crafting
	-- (full implementation needs phase duration awareness)
end)

-- ─── Player join SFX ─────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	if player ~= LocalPlayer then
		_playSFX("PLAYER_JOIN")
	end
end)

-- ─── Craft slot assign SFX ───────────────────────────────────────────────────
-- CraftingClient fires a BindableEvent when a slot is assigned
-- For now hook into a simple approach: expose a function

local SoundClient = {}

function SoundClient.playSFX(key)
	_playSFX(key)
end

function SoundClient.playBGM(cfg)
	_playBGM(cfg)
end

-- Make accessible to other scripts via a BindableFunction or shared module if needed
return SoundClient
