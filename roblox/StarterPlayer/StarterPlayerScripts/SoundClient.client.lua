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
local SoundFx      = require(ReplicatedStorage.Shared.SoundFx)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local LocalPlayer  = Players.LocalPlayer

local _bgmInstance  = nil  -- current BGM Sound
local _ambiSounds   = {}   -- current ambience Sound list
local _currentBiome = nil
local _phase        = nil

local _makeSound = SoundFx.make
local _playSFX = SoundFx.play

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
		local s = _makeSound(cfg, SoundService, "Music")
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
		local s = _makeSound(cfg, SoundService, "Ambience")
		if not s then continue end
		s.Volume = 0
		s:Play()
		TweenService:Create(s, TweenInfo.new(2.0), { Volume = cfg.volume }):Play()
		table.insert(_ambiSounds, s)
	end
end

-- ─── Phase → BGM routing ──────────────────────────────────────────────────────

local function _onPhaseChanged(phase)
	_phase = phase
	-- a client that joins late missed BiomeSelected (ReplicatedStorage "Biome")
	_currentBiome = _currentBiome or ReplicatedStorage:GetAttribute("Biome")
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
	elseif effectName == "boostPad"    then _playSFX("BOOST_PAD")
	elseif effectName == "respawn"     then _playSFX("RESPAWN")
	elseif effectName == "bubblePop"   then _playSFX("BUBBLE_POP")
	-- boost and drift sounds: RacingClient (client-side actions)
	end
end)

-- ─── Ability SFX ─────────────────────────────────────────────────────────────

-- Args: (userId, itemName, targetIds, effectKey, info). This used to read
-- the third argument (targetIds) as the effect key: always the generic sound.
RemoteEvents.AbilityActivated.OnClientEvent:Connect(function(userId, itemName, _targetIds, effectKey)
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

-- Fights and grabs (FarmAction, broadcast): only the two players involved hear them.
RemoteEvents.FarmAction.OnClientEvent:Connect(function(what, actorId, targetId, info)
	local me = LocalPlayer.UserId
	if actorId ~= me and targetId ~= me then return end
	info = info or {}
	if what == "punch" then
		if info.result == "knockout" then _playSFX("KNOCKOUT")
		elseif info.result == "hit" then _playSFX("PUNCH_HIT")
		elseif info.result == "blocked" then _playSFX("PUNCH_BLOCKED")
		end
	elseif what == "grab" and targetId == me then
		_playSFX("GRAB_WARN")
	elseif what == "grabEnd" and info.result == "defended" then
		_playSFX("ITEM_DEFENDED")
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
-- Once per FARMING / CRAFTING phase, at 10 s left on the PhaseEndsAt clock.

local TIMER_LOW_AT = 10
local _timerWarned = false
local _phaseSince  = 0

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function()
	_timerWarned = false
	_phaseSince  = os.clock()
end)

game:GetService("RunService").Heartbeat:Connect(function()
	if _timerWarned then return end
	if _phase ~= Constants.PHASES.FARMING and _phase ~= Constants.PHASES.CRAFTING then return end
	if os.clock() - _phaseSince < 1 then return end   -- PhaseEndsAt may still be the last phase's
	local left = PhaseClock.remaining(nil)
	if left and left > 0 and left <= TIMER_LOW_AT then
		_timerWarned = true
		_playSFX("TIMER_LOW")
	end
end)

-- ─── Player join SFX ─────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	if player ~= LocalPlayer then
		_playSFX("PLAYER_JOIN")
	end
end)

-- ─── Music on / off ──────────────────────────────────────────────────────────
-- A 🎵 button by Roblox's own top-left buttons mutes the Music group (BGM
-- only: effects and ambience stay). Per session.

local function _musicButton()
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("MusicToggle")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MusicToggle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	local b = Instance.new("TextButton")
	b.Name = "Button"
	b.Size = UDim2.new(0, 36, 0, 36)
	b.Position = UDim2.new(0, 112, 0, 4)
	b.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	b.BackgroundTransparency = 0.35
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = gui
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	local music = SoundFx.group("Music")
	local function draw()
		local on = music.Volume > 0
		b.Text = on and "🎵" or "🔇"
	end
	b.MouseButton1Click:Connect(function()
		music.Volume = (music.Volume > 0) and 0 or SoundConfig.GROUPS.Music
		draw()
	end)
	draw()
	gui.Parent = pg
end
task.spawn(_musicButton)
