-- RacingClient.client.lua
-- Vehicle controls, drift, boost, screen effects, and ability input.
-- Key bindings: WASD/arrows = drive; Shift = drift slide; F = activate boost;
--   E = ability; R = respawn; Space/Ctrl = altitude (SKY only).
-- Resolves: Issue #30, #31, #66, #114

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)   -- keyboard + touch buttons
local VehicleController = require(ReplicatedStorage.Shared.VehicleController)
local RaceProgress = require(ReplicatedStorage.Shared.RaceProgress)
local AbilitySlots = require(ReplicatedStorage.Shared.AbilitySlots)
local SoundFx      = require(ReplicatedStorage.Shared.SoundFx)
local InputHints   = require(ReplicatedStorage.Shared.InputHints)
local InputSource  = require(script.Parent:WaitForChild("Modules"):WaitForChild("InputSource"))

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local RacingClient = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _active        = false
local _vehicle       = nil   -- Model
local _seat          = nil   -- VehicleSeat
local _stats         = nil   -- vehicleStats table
local _biome         = nil
local _riseSeg       = nil   -- track segment hint for the road height under the car
local _drifting      = false
local _boostActive   = false
local _boostGauge    = 1.0   -- 0–1, charges via DriftCorner zones
local _heartbeatConn = nil
local _baseFOV       = 70
local _abilityReadyAt = {}   -- [itemName] = os.clock() when its cooldown ends
local _abilityIndex  = 1     -- which equipped item (in AbilitySlots.ORDER) E tries first
local _abilityBusy   = false -- a request is in flight
local _prevBotE      = false -- harness bot's E key (InputSource override), last frame
local _driveState    = VehicleController.newState()

-- ─── Input tracking ───────────────────────────────────────────────────────────

local _keys = {
	W = false, A = false, S = false, D = false,
	Up = false, Down = false, Left = false, Right = false,
	Shift = false, Space = false, Ctrl = false,
	E = false,   -- ability
	F = false,   -- boost activation
}

-- A key let go while the game window was not focused never ends: on a Mac
-- Cmd+Tab out of a SKY race left Ctrl (dive) held and the plane flew into
-- the floor (Studio Device Simulator, 2026-10-30). Losing or regaining focus
-- lets go of every key.
local function _releaseAllKeys()
	for k in pairs(_keys) do _keys[k] = false end
end
UserInputService.WindowFocusReleased:Connect(_releaseAllKeys)
UserInputService.WindowFocused:Connect(_releaseAllKeys)

local _suspParams = RaycastParams.new()

_suspParams.IgnoreWater = true   -- OCEAN's Terrain water is not ground (TerrainPlan.WATER)
_suspParams.FilterType = Enum.RaycastFilterType.Exclude
-- Only solid parts carry the car: trigger volumes and see-through scenery
-- (the Sky map's haze planes at Y 28-34 overlap FOREST's spiral, Studio
-- 2026-10-22: cars rode on them 10 studs above the road) are skipped.
_suspParams.RespectCanCollide = true

-- Roblox's control module (PlayerModule): the thumbstick / left stick as a
-- camera-relative move vector (X right, Z back), or nil.
local _controls = nil
local function _stickVector()
	if _controls == nil then
		local ok, c = pcall(function()
			local ps = LocalPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			return pm and require(pm):GetControls()
		end)
		_controls = (ok and c) or false
	end
	if not _controls then return nil end
	local ok, v = pcall(function() return _controls:GetMoveVector() end)
	return (ok and typeof(v) == "Vector3" and v.Magnitude > 0.05) and v or nil
end

local KEY_MAP = {
	[Enum.KeyCode.W]           = "W",
	[Enum.KeyCode.A]           = "A",
	[Enum.KeyCode.S]           = "S",
	[Enum.KeyCode.D]           = "D",
	[Enum.KeyCode.Up]          = "Up",
	[Enum.KeyCode.Down]        = "Down",
	[Enum.KeyCode.Left]        = "Left",
	[Enum.KeyCode.Right]       = "Right",
	[Enum.KeyCode.LeftShift]   = "Shift",
	[Enum.KeyCode.RightShift]  = "Shift",
	[Enum.KeyCode.Space]       = "Space",
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl]= "Ctrl",
	[Enum.KeyCode.E]           = "E",
	[Enum.KeyCode.F]           = "F",
}

-- A short line under the race HUD ("No car ahead"): why T did nothing.
local function _raceNote(text)
	local gui = LocalPlayer.PlayerGui:FindFirstChild("RaceNote")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "RaceNote"
		gui.ResetOnSpawn = false
		gui.Parent = LocalPlayer.PlayerGui
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0.62, 0)
		l.Size = UDim2.new(0, 300, 0, 26)
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.3
		l.TextScaled = true
		l.Font = Enum.Font.GothamBold
		l.Parent = gui
	end
	local l = gui:FindFirstChild("Text")
	l.Text = text
	l.Visible = true
	local token = tostring(os.clock())
	l:SetAttribute("Token", token)
	task.delay(1.6, function()
		if l:GetAttribute("Token") == token then l.Visible = false end
	end)
end

local TRICK_NOTES = {
	["denied: no car ahead"] = "💣 No car ahead in range",
	["denied: used"]         = "💣 Bomb used: one per race",
	["denied: countdown"]    = "💣 Wait for GO",
}
function _useRaceTrick()
	local ok, res = pcall(function() return RemoteEvents.UseRaceTrick:InvokeServer() end)
	local note = ok and TRICK_NOTES[res]
	if note then _raceNote(note) end
end

KeyInput.began(function(input, processed)
	local k = KEY_MAP[input.KeyCode]
	-- typing W A S D in the chat box steered the car
	if processed then return end
	if k then _keys[k] = true end
	if not _active then return end

	-- F key: activate boost when gauge is full
	if k == "F" and not _boostActive and _boostGauge >= 1 then
		_triggerBoost()
	end

	if k == "E" then
		_triggerAbility()
	end

	if input.KeyCode == Enum.KeyCode.R then
		RemoteEvents.RequestRespawn:InvokeServer()
	end

	-- T: the shop's race trick (Bounce Bomb), once a race; Q: taunt
	if input.KeyCode == Enum.KeyCode.T and LocalPlayer:GetAttribute("RaceTrick") then
		task.spawn(_useRaceTrick)
	end
	if input.KeyCode == Enum.KeyCode.Q then
		RemoteEvents.Taunt:FireServer()
	end
end)

KeyInput.ended(function(input)
	local k = KEY_MAP[input.KeyCode]
	if k then _keys[k] = false end

	if not _active then return end

	-- Releasing Shift ends a drift in the drive loop (VehicleController.updateDrift).
end)

-- ─── Screen overlay helpers ───────────────────────────────────────────────────

local function _getOverlay()
	local existing = LocalPlayer.PlayerGui:FindFirstChild("RaceOverlay")
	if existing then return existing end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "RaceOverlay"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.Parent         = LocalPlayer.PlayerGui

	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.new(1, 1, 1)
	tint.BackgroundTransparency = 1
	tint.Parent = gui
	return gui
end

function _applyScreenTint(colour, alpha, duration)
	local gui  = _getOverlay()
	local tint = gui:FindFirstChild("Tint")
	if not tint then return end
	tint.BackgroundColor3 = colour
	TweenService:Create(tint, TweenInfo.new(0.1), {
		BackgroundTransparency = 1 - alpha
	}):Play()
	task.delay(duration, function()
		TweenService:Create(tint, TweenInfo.new(0.3), {
			BackgroundTransparency = 1
		}):Play()
	end)
end

-- ─── Boost ────────────────────────────────────────────────────────────────────
-- F key activates boost. Gauge charges from DriftCorner zones.

function _triggerBoost()
	local result = RemoteEvents.RequestBoost:InvokeServer()
	if result ~= "ok" then return end

	_boostActive = true
	_boostGauge  = 0
	_updateBoostHUD()
	SoundFx.play("BOOST_ACTIVATE")

	local boostColor
	if _biome == "OCEAN" then
		boostColor = Color3.fromRGB(60, 200, 255)
	elseif _biome == "SKY" then
		boostColor = Color3.fromRGB(180, 100, 255)
	else
		boostColor = Color3.fromRGB(100, 200, 255)
	end
	_applyScreenTint(boostColor, 0.4, 0.25)

	TweenService:Create(Camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = _baseFOV + 22
	}):Play()

	local dur = (_stats and _stats.boostDuration) or Constants.BOOST_DURATION
	task.delay(dur, function()
		_boostActive = false
		TweenService:Create(Camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			FieldOfView = _baseFOV
		}):Play()
	end)
end

-- ─── Boost HUD ────────────────────────────────────────────────────────────────

local _boostBar   = nil
local _boostLabel = nil

-- The HUD ScreenGui. PlayerGui also holds the LocalScript named "HUD"
-- (StarterGui copies it in), so FindFirstChild("HUD") could return the
-- script and the bar was never found.
local function _hudGui()
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if g.Name == "HUD" and g:IsA("ScreenGui") then return g end
	end
	return nil
end

-- A cached HUD part that is still on screen. The HUD script rebuilds its
-- ScreenGui after every LoadCharacter (each LOBBY, RaceSeat reloads), which
-- destroys the old bar: look again then.
local function _live(inst)
	return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(LocalPlayer.PlayerGui)
end

local function _ensureBoostHUD()
	if _live(_boostBar) then return end
	_boostBar, _boostLabel = nil, nil
	local hud = _hudGui()
	if not hud then return end
	local frame = hud:FindFirstChild("BoostBar")
	if not frame then return end
	_boostBar   = frame:FindFirstChild("Fill")
	_boostLabel = frame:FindFirstChild("Label")
end

function _updateBoostHUD()
	_ensureBoostHUD()
	if not _boostBar then return end
	TweenService:Create(_boostBar, TweenInfo.new(0.15), {
		Size = UDim2.new(_boostGauge, 0, 1, 0)
	}):Play()
	if _boostLabel then
		-- "BOOST  [BOOST]" on a touch screen: the button is named BOOST
		_boostLabel.Text = _boostGauge >= 1 and (InputHints.touchUI() and "BOOST READY" or ("BOOST  " .. InputHints.tag("boost"))) or "BOOST"
	end
end
-- the boost label follows the device in use (key name or BOOST READY)
InputHints.onChange(function() if _active then _updateBoostHUD() end end)

function _showBoostReady()
	_ensureBoostHUD()
	if not _boostBar then return end
	local frame = _boostBar.Parent
	TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 220, 0, 22)
	}):Play()
	task.delay(0.25, function()
		TweenService:Create(frame, TweenInfo.new(0.18), {
			Size = UDim2.new(0, 200, 0, 18)
		}):Play()
	end)
	_applyScreenTint(Color3.fromRGB(255, 220, 50), 0.12, 0.2)
end

-- ─── Drift ────────────────────────────────────────────────────────────────────
-- Shift + steer + >50% speed → enter drift (TurnSpeed reduced, slides wide).
-- DriftCorner zone touch (server) → DriftCharge event → fills gauge.
-- F key with full gauge → activate boost slingshot.

local _driftLabel      = nil

local function _ensureDriftLabel()
	if _driftLabel and _driftLabel.Parent then return _driftLabel end
	local overlay = _getOverlay()
	local lbl = Instance.new("TextLabel")
	lbl.Name             = "DriftIndicator"
	lbl.Size             = UDim2.new(0, 160, 0, 40)
	lbl.AnchorPoint      = Vector2.new(0.5, 1)
	lbl.Position         = UDim2.new(0.5, 0, 1, -112)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled       = true
	lbl.Font             = Enum.Font.GothamBold
	lbl.TextStrokeTransparency = 0.4
	lbl.TextTransparency = 1
	lbl.Parent           = overlay
	_driftLabel = lbl
	return lbl
end

local function _showDriftLabel(text, color)
	local lbl = _ensureDriftLabel()
	lbl.Text       = text
	lbl.TextColor3 = color
	TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
end

local function _hideDriftLabel()
	if not _driftLabel then return end
	TweenService:Create(_driftLabel, TweenInfo.new(0.3), {
		TextTransparency = 1,
	}):Play()
end

-- Drifting lowers the turn rate inside VehicleController.command (ctx.drifting);
-- the seat's TurnSpeed is server-owned and never written here.
local function _enterDrift()
	_drifting        = true

	local driftColor, driftText
	if _biome == "OCEAN" then
		driftColor = Color3.fromRGB(40, 170, 255)
		driftText  = "WAKE"
	else
		driftColor = Color3.fromRGB(230, 160, 35)
		driftText  = "DRIFT"
	end
	_applyScreenTint(driftColor, 0.22, 0.12)
	_showDriftLabel(driftText, driftColor)
	SoundFx.play("DRIFT_START")
end

function _exitDrift(level, slid)
	_drifting = false
	_hideDriftLabel()
	-- A long enough slide earns a mini-turbo; the server applies the speed
	-- (VehicleTuning) and draws it on the car for everyone.
	if level then
		local tb = Constants.DRIVE.DRIFT_TURBO[level]
		RemoteEvents.DriftTurbo:FireServer(level, slid)
		SoundFx.play("DRIFT_SLINGSHOT")
		_showDriftLabel(tb.label, level >= 2 and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(80, 190, 255))
		task.delay(0.6, _hideDriftLabel)
	end
end

-- ─── DriftCharge listener ─────────────────────────────────────────────────────

local function _showCornerCharge()
	local overlay = _getOverlay()
	local lbl = overlay:FindFirstChild("CornerFlash")
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Name             = "CornerFlash"
		lbl.Size             = UDim2.new(0, 180, 0, 28)
		lbl.AnchorPoint      = Vector2.new(0.5, 1)
		lbl.Position         = UDim2.new(0.5, 0, 1, -158)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled       = true
		lbl.Font             = Enum.Font.GothamBold
		lbl.TextStrokeTransparency = 0.4
		lbl.Parent           = overlay
	end

	local text, color
	if _biome == "OCEAN" then
		text  = "WAKE BONUS +"
		color = Color3.fromRGB(60, 220, 255)
	elseif _biome == "SKY" then
		text  = "RING BONUS +"
		color = Color3.fromRGB(200, 140, 255)
	else
		text  = "CORNER +"
		color = Color3.fromRGB(255, 220, 50)
	end
	lbl.Text       = text
	lbl.TextColor3 = color
	lbl.TextTransparency = 0
	TweenService:Create(lbl, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
	}):Play()
	_applyScreenTint(color, 0.15, 0.15)
end

RemoteEvents.DriftCharge.OnClientEvent:Connect(function(amount)
	_boostGauge = math.min(1, _boostGauge + (amount or Constants.DRIFT_CHARGE_PER_CORNER))
	_updateBoostHUD()
	_showCornerCharge()
	if _boostGauge >= 1 then
		_showBoostReady()
	end
end)

-- ─── Checkpoint indicator (Issue #131) ────────────────────────────────────────
-- Shows CP1 / CP2 progress so players understand why a finish-line touch
-- doesn't count. Server gating lives in CheckpointService (Issue #126).

local _cpFrame   = nil
local _cpLabels  = { nil, nil }
local _cpPassed  = { false, false }

local CP_INACTIVE_COLOR = Color3.fromRGB(180, 180, 195)
local CP_PASSED_COLOR   = Color3.fromRGB(80, 230, 120)

local function _ensureCheckpointHUD()
	if _cpFrame and _cpFrame.Parent then return _cpFrame end
	local overlay = _getOverlay()
	local frame = Instance.new("Frame")
	frame.Name        = "CheckpointIndicator"
	frame.Size        = UDim2.new(0, 200, 0, 32)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position    = UDim2.new(0.5, 0, 0, 16)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.4
	frame.BorderSizePixel = 0
	frame.Parent      = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	for i = 1, 2 do
		local lbl = Instance.new("TextLabel")
		lbl.Name           = "CP" .. i
		lbl.Size           = UDim2.new(0.5, -4, 1, -4)
		lbl.Position       = UDim2.new((i - 1) * 0.5, 2, 0, 2)
		lbl.BackgroundTransparency = 1
		lbl.Font           = Enum.Font.GothamBold
		lbl.TextScaled     = true
		lbl.TextStrokeTransparency = 0.5
		lbl.Text           = "CP" .. i .. " ⬜"
		lbl.TextColor3     = CP_INACTIVE_COLOR
		lbl.Parent         = frame
		_cpLabels[i] = lbl
	end

	_cpFrame = frame
	return frame
end

local function _updateCheckpointHUD()
	_ensureCheckpointHUD()
	for i = 1, 2 do
		local lbl = _cpLabels[i]
		if lbl then
			lbl.Text       = "CP" .. i .. " " .. (_cpPassed[i] and "✅" or "⬜")
			lbl.TextColor3 = _cpPassed[i] and CP_PASSED_COLOR or CP_INACTIVE_COLOR
		end
	end
end

local function _resetCheckpointHUD()
	_cpPassed[1] = false
	_cpPassed[2] = false
	_updateCheckpointHUD()
end

local function _flashCheckpoint(cpIndex)
	local lbl = _cpLabels[cpIndex]
	if not lbl then return end
	local original = lbl.TextSize
	TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	_applyScreenTint(CP_PASSED_COLOR, 0.15, 0.2)
end

local function _showCheckpointPassToast(cpIndex)
	local overlay = _getOverlay()
	local lbl = overlay:FindFirstChild("CPPassToast")
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Name                   = "CPPassToast"
		lbl.Size                   = UDim2.new(0, 280, 0, 56)
		lbl.AnchorPoint            = Vector2.new(0.5, 0)
		lbl.Position               = UDim2.new(0.5, 0, 0, 72)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled             = true
		lbl.Font                   = Enum.Font.GothamBlack
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent                 = overlay
	end
	lbl.Text             = "CP " .. cpIndex .. " PASSED ✅"
	lbl.TextColor3       = CP_PASSED_COLOR
	lbl.TextTransparency = 0
	TweenService:Create(lbl, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
	}):Play()
end

if RemoteEvents.CheckpointPassed then
	RemoteEvents.CheckpointPassed.OnClientEvent:Connect(function(cpIndex)
		if cpIndex == 1 or cpIndex == 2 then
			_cpPassed[cpIndex] = true
			_updateCheckpointHUD()
			_flashCheckpoint(cpIndex)
			_showCheckpointPassToast(cpIndex)
		end
	end)
end

-- ─── Race intro overlay (Issue #131 follow-up) ────────────────────────────────
-- Shown once at race start: explains the CP1/CP2 gating rule so players know
-- they need to drive through both arches before the finish line counts.

local function _showRaceIntro()
	_resetCheckpointHUD()
	local overlay = _getOverlay()
	local existing = overlay:FindFirstChild("RaceIntroBanner")
	if existing then existing:Destroy() end

	local frame = Instance.new("Frame")
	frame.Name                   = "RaceIntroBanner"
	-- the only thing under the 3-2-1 (RaceCountdown, 0.22): the objective and
	-- two tips (the tutorial shows no RACING toast; its keys are on the strip)
	frame.Size                   = UDim2.new(0.92, 0, 0, 124)
	frame.AnchorPoint            = Vector2.new(0.5, 0)
	frame.Position               = UDim2.new(0.5, 0, 0.40, 0)
	frame.BackgroundColor3       = Color3.fromRGB(15, 18, 28)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel        = 0
	frame.Parent                 = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local maxW = Instance.new("UISizeConstraint")
	maxW.MaxSize = Vector2.new(560, 124)
	maxW.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, -20, 0, 36)
	title.Position               = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text                   = "🏁 RACE START!"
	title.TextColor3             = Color3.fromRGB(255, 220, 80)
	title.Font                   = Enum.Font.GothamBlack
	title.TextScaled             = true
	title.TextStrokeTransparency = 0.4
	title.Parent                 = frame

	local body = Instance.new("TextLabel")
	body.Size                    = UDim2.new(1, -20, 0, 44)
	body.Position                = UDim2.new(0, 10, 0, 46)
	body.BackgroundTransparency  = 1
	body.Text                    = "Drive through CP 1 → CP 2 → Finish!"
	body.TextColor3              = Color3.fromRGB(220, 230, 245)
	body.Font                    = Enum.Font.GothamBold
	body.TextScaled              = true
	body.TextStrokeTransparency  = 0.5
	body.Parent                  = frame

	local tip = Instance.new("TextLabel")
	tip.Size                     = UDim2.new(1, -20, 0, 26)
	tip.Position                 = UDim2.new(0, 10, 0, 92)
	tip.BackgroundTransparency   = 1
	tip.Text                     = "Long drift = mini turbo  ·  Yellow pads = speed"
	tip.TextColor3               = Color3.fromRGB(255, 220, 80)
	tip.Font                     = Enum.Font.GothamBold
	tip.TextScaled               = true
	tip.TextStrokeTransparency   = 0.5
	tip.Parent                   = frame

	task.delay(3.4, function()
		if not frame.Parent then return end
		local tw = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		})
		tw:Play()
		for _, child in ipairs(frame:GetDescendants()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		tw.Completed:Wait()
		frame:Destroy()
	end)
end

-- 3-2-1-GO in the middle of the screen, counted to the server's GO time
-- (ReplicatedStorage "RaceGoAt", set by Modules/RaceStart). Every car is
-- held on the grid until then.
local _countdownConn = nil
local function _showCountdown()
	local overlay = _getOverlay()
	local old = overlay:FindFirstChild("RaceCountdown")
	if old then old:Destroy() end
	if _countdownConn then _countdownConn:Disconnect(); _countdownConn = nil end

	local label = Instance.new("TextLabel")
	label.Name                   = "RaceCountdown"
	-- from under the checkpoint indicator (16..48) down to at most 27% of
	-- the window, so the RACE START banner (40%) stays clear: centred on 22%
	-- with a fixed 160 px it covered the indicator in a short window
	-- (Studio ui-layout 2026-10-30)
	label.Size                   = UDim2.new(0, 260, 0.27, 0)
	label.AnchorPoint            = Vector2.new(0.5, 0)
	label.Position               = UDim2.new(0.5, 0, 0, 56)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(260, 160)
	cap.Parent = label
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBlack
	label.TextScaled             = true
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Text                   = ""
	label.Parent                 = overlay

	_countdownConn = RunService.Heartbeat:Connect(function()
		local goAt = ReplicatedStorage:GetAttribute("RaceGoAt")
		if type(goAt) ~= "number" then return end
		local left = goAt - workspace:GetServerTimeNow()
		if left > 3 then
			label.Text = ""
		elseif left > 0 then
			label.Text = tostring(math.ceil(left))
			label.TextColor3 = Color3.fromRGB(255, 220, 80)
		elseif left > -0.8 then
			label.Text = "GO!"
			label.TextColor3 = Color3.fromRGB(90, 255, 120)
		else
			label:Destroy()
			if _countdownConn then _countdownConn:Disconnect(); _countdownConn = nil end
		end
	end)
end

if RemoteEvents.RaceIntroShown then
	RemoteEvents.RaceIntroShown.OnClientEvent:Connect(function(_intro)
		_showRaceIntro()
		_showCountdown()
	end)
end

-- Store per-race seed broadcast (placeholder for future client-side variation)
local _raceSeed = nil
if RemoteEvents.RaceSeedBroadcast then
	RemoteEvents.RaceSeedBroadcast.OnClientEvent:Connect(function(seed)
		_raceSeed = seed
	end)
end

-- ─── Vehicle drive loop ───────────────────────────────────────────────────────

local function _driveLoop(dt)
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local primary = _vehicle.PrimaryPart

	if not primary:FindFirstChild("DriveVelocity") or not primary:FindFirstChild("DriveAngular") then
		return
	end

	local maxSpeed  = _seat and _seat.MaxSpeed  or 40
	local turnSpeed = _seat and _seat.TurnSpeed or 1

	-- Detect SKY mode by the vehicle's HoverPosition constraint rather than
	-- the _biome client variable. BiomeSelected can race against PhaseChanged
	-- on client load and leave _biome nil/stale — but the vehicle is
	-- authoritative about its own physics setup.
	local isSky = primary:FindFirstChild("HoverPosition") ~= nil

	-- Keyboard state, or a harness bot's synthetic keys (InputSource override).
	local rawKeys = InputSource.read(_keys)
	-- Touch thumbstick / gamepad stick: drive from Roblox's control module
	-- when no drive key is down. It wrote the seat's ThrottleFloat /
	-- SteerFloat only when its vehicle mode noticed the seat, and in a race
	-- it did not: the stick walked the (seated) avatar and the car stood
	-- still (Studio Device Simulator, iPhone XR, 2026-10-30). Its move vector
	-- is read directly; the seat's floats stay as a fallback.
	-- Each axis on its own: gas from a key or RT (KeyInput maps it to Up)
	-- with steering from the stick, or the other way round (a pad player
	-- holding RT could not steer: launch check 2026-10-30).
	if not InputSource.isOverridden() and _seat then
		local k = rawKeys
		local gasKey = k.W or k.S or k.Up or k.Down
		local steerKey = k.A or k.D or k.Left or k.Right
		if not (gasKey and steerKey) then
			local th, st = _seat.ThrottleFloat, _seat.SteerFloat
			if math.abs(th) <= 0.3 and math.abs(st) <= 0.3 then
				local mv = _stickVector()
				if mv then th, st = -mv.Z, mv.X end
			end
			if (not gasKey and math.abs(th) > 0.3) or (not steerKey and math.abs(st) > 0.3) then
				rawKeys = table.clone(rawKeys)
				if not gasKey then
					rawKeys.W = th > 0.3
					rawKeys.S = th < -0.3
				end
				if not steerKey then
					rawKeys.A = st < -0.3   -- SteerFloat −1 is left
					rawKeys.D = st > 0.3
				end
			end
		end
	end
	local input = VehicleController.readKeys(rawKeys)
	-- A bot presses E through the same path as the keyboard's InputBegan.
	if InputSource.isOverridden() then
		local e = rawKeys.E == true
		if e and not _prevBotE then _triggerAbility() end
		_prevBotE = e
	end

	-- Drift: one rule for players, bots and simulators. A released drift
	-- that slid long enough asks the server for its mini-turbo.
	local vel = primary.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local slid = _driveState.driftTime or 0
	local change, level = VehicleController.updateDrift(_driveState, input, flatSpeed, maxSpeed, isSky)
	if change == "enter" then
		_enterDrift()
	elseif change == "exit" then
		_exitDrift(level, slid)
	end
	_drifting = _driveState.drifting

	local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
	local tx, tz = VehicleController.travelDir(_driveState, yaw)
	local cmd = VehicleController.command(input, {
		maxSpeed      = maxSpeed,
		turnSpeed     = turnSpeed,
		isSky         = isSky,
		drifting      = _drifting,
		biome         = (_biome == "OCEAN") and "OCEAN" or "FOREST",
		yaw           = yaw,
		torque        = _seat and _seat.Torque or 0,
		dt            = dt,
		actualForward = vel.X * tx + vel.Z * tz,
	}, _driveState)
	-- local only (not replicated): BotDriver's autopilot steers by the slide
	primary:SetAttribute("TravelYaw", _driveState.travelYaw)
	-- Boats and flyers hold a height: it follows a raised road (flume,
	-- corkscrew). FOREST rides the ground with its suspension rays.
	local rise = nil
	if isSky or _biome == "OCEAN" then
		local pos = primary.Position
		rise, _riseSeg = RaceProgress.roadRise(isSky and "SKY" or "OCEAN", pos.X, pos.Z, _riseSeg, pos.Y)
	end
	VehicleController.apply(primary, cmd, {
		biome      = _biome,
		altitudeDt = dt,
		roadRise   = rise,
		raycast    = function(origin, direction)
			return workspace:Raycast(origin, direction, _suspParams)
		end,
	})
end

-- ─── Ability activation ───────────────────────────────────────────────────────
-- E fires the next equipped ability item that is off cooldown, in
-- AbilitySlots.ORDER (SPECIAL → ENGINE → BODY). The car's items come from its
-- model attributes (written by the server's VehicleBuilder). The HUD reads
-- the LocalPlayer attributes AbilityNext / AbilityReadyAt set here.

local function _publishAbilityHUD()
	local slots = AbilitySlots.read(_vehicle)
	local now = os.clock()
	local item, _, soonest, soonestAt = AbilitySlots.pick(slots, _abilityReadyAt, now, _abilityIndex)
	LocalPlayer:SetAttribute("AbilityNext", item or soonest)
	LocalPlayer:SetAttribute("AbilityWait", (not item and soonestAt) and math.max(0, soonestAt - now) or 0)
end

function _triggerAbility()
	if _abilityBusy or not _vehicle then return end
	local slots = AbilitySlots.read(_vehicle)
	local itemName, index = AbilitySlots.pick(slots, _abilityReadyAt, os.clock(), _abilityIndex)
	if not itemName then return end
	_abilityBusy = true
	task.spawn(function()
		local ok, result = pcall(function()
			return RemoteEvents.RequestAbility:InvokeServer(itemName)
		end)
		_abilityBusy = false
		if ok and result == "ok" then
			_abilityIndex = index + 1
		elseif ok and result == "denied: cooldown" then
			-- out of sync with the server: try the next item on the next press
			_abilityReadyAt[itemName] = os.clock() + 1
		end
		_publishAbilityHUD()
	end)
end

RemoteEvents.AbilityActivated.OnClientEvent:Connect(function(userId, itemName, _targets, _effectKey, info)
	if userId ~= LocalPlayer.UserId or type(itemName) ~= "string" then return end
	_abilityReadyAt[itemName] = os.clock() + ((type(info) == "table" and info.cooldown) or 0)
	_publishAbilityHUD()
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		if _active and _vehicle then _publishAbilityHUD() end
	end
end)

-- ─── ScreenEffect listener ───────────────────────────────────────────────────

RemoteEvents.ScreenEffect.OnClientEvent:Connect(function(effectName, params)
	if effectName == "collision" then
		_applyScreenTint(Color3.fromRGB(255, 100, 50), 0.4, 0.3)
		local steps = math.floor(0.4 / 0.05)
		task.spawn(function()
			for _ = 1, steps do
				Camera.CFrame = Camera.CFrame * CFrame.Angles(
					(math.random() - 0.5) * 0.04,
					(math.random() - 0.5) * 0.04, 0)
				task.wait(0.05)
			end
		end)

	elseif effectName == "mudWarning" then
		_applyScreenTint(Color3.fromRGB(100, 70, 30), 0.25, 0.5)

	elseif effectName == "updraftWarning" then
		_applyScreenTint(Color3.fromRGB(100, 200, 255), 0.2, 0.4)

	elseif effectName == "boostPad" then
		_applyScreenTint(Color3.fromRGB(255, 220, 60), 0.3, 0.25)
		TweenService:Create(Camera, TweenInfo.new(0.2), { FieldOfView = _baseFOV + 10 }):Play()
		task.delay(0.4, function()
			TweenService:Create(Camera, TweenInfo.new(0.3), { FieldOfView = _baseFOV }):Play()
		end)

	elseif effectName == "respawn" then
		VehicleController.reset(_driveState)
		_applyScreenTint(Color3.fromRGB(255, 255, 255), 0.9, 0.5)

	elseif effectName == "boostRecharge" then
		-- Backpack ability: refill the boost gauge
		_boostGauge = 1
		_updateBoostHUD()
		_showBoostReady()

	elseif effectName == "bubblePop" then
		_applyScreenTint(Color3.fromRGB(150, 220, 255), 0.5, 0.3)
		local steps = math.floor(0.2 / 0.05)
		task.spawn(function()
			for _ = 1, steps do
				Camera.CFrame = Camera.CFrame * CFrame.Angles(
					(math.random() - 0.5) * 0.03,
					(math.random() - 0.5) * 0.03, 0)
				task.wait(0.05)
			end
		end)

	elseif effectName == "hackControls" then
		_applyScreenTint(Color3.fromRGB(50, 200, 50), 0.4, (params and params.duration) or 5)
	end
end)

-- ─── Camera follow ────────────────────────────────────────────────────────────

-- The only race camera (Modules/CameraController leaves racing alone):
-- behind the chassis' nose (LookVector is the nose for car, boat and plane
-- alike), a little further back and higher at speed.
local function _updateCamera()
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local primary = _vehicle.PrimaryPart
	local lookDir = primary.CFrame.LookVector
	local vel     = primary.AssemblyLinearVelocity.Magnitude
	local camPos  = primary.Position - lookDir * (12 + vel * 0.04) + Vector3.new(0, 5 + vel * 0.02, 0)
	Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(camPos, primary.Position + Vector3.new(0, 1.5, 0)), 0.12)
end

-- ─── Speedometer update ───────────────────────────────────────────────────────

local _speedLabel = nil

local function _updateSpeedHUD()
	if not _live(_speedLabel) then
		_speedLabel = nil
		local hud = _hudGui()
		local sf  = hud and hud:FindFirstChild("Speedometer")
		_speedLabel = sf and sf:FindFirstChild("Value")
	end
	if not _speedLabel or not _vehicle or not _vehicle.PrimaryPart then return end
	local vel = _vehicle.PrimaryPart.AssemblyLinearVelocity.Magnitude
	_speedLabel.Text = tostring(math.floor(vel * 0.28 * 3.6))
end

-- ─── VehicleSpawned listener ─────────────────────────────────────────────────

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, vehicleModel)
	if userId ~= LocalPlayer.UserId then return end
	_vehicle = vehicleModel
	_seat    = vehicleModel:FindFirstChildWhichIsA("VehicleSeat", true)
	_riseSeg = nil
	VehicleController.reset(_driveState)
	_suspParams.FilterDescendantsInstances = {vehicleModel}

	if not _seat then
		task.spawn(function()
			local deadline = tick() + 3
			repeat task.wait(0.05); _seat = vehicleModel:FindFirstChildWhichIsA("VehicleSeat", true)
			until _seat or tick() > deadline
			if not _seat then warn("[RacingClient] VehicleSeat never found") end
		end)
	end

	Camera.CameraType  = Enum.CameraType.Scriptable
	Camera.FieldOfView = _baseFOV
end)

-- ─── Car-to-car hits (server: RacingManager + Shared/CarImpact) ──────────────
-- The drive model overwrites Roblox's own collision response every frame, so
-- the server resolves each hit and sends this driver a knock: a velocity
-- change (forward part → drive speed, sideways part → a fading slide) and a
-- spin. The camera shakes with the closing speed.
RemoteEvents.CarImpact.OnClientEvent:Connect(function(dvx, dvz, spin, strength)
	if not _active or not _vehicle or not _vehicle.PrimaryPart then return end
	local look = _vehicle.PrimaryPart.CFrame.LookVector
	VehicleController.knock(_driveState, dvx or 0, dvz or 0, spin or 0, look.X, look.Z,
		_seat and _seat.MaxSpeed or 60)
	local amount = math.min((strength or 0) * Constants.IMPACT.SHAKE_PER_HIT, 0.8)
	if amount > 0.05 then
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local age = os.clock() - t0
			if age > 0.35 then conn:Disconnect() return end
			local k = amount * (1 - age / 0.35)
			Camera.CFrame = Camera.CFrame * CFrame.Angles((math.random() - 0.5) * k * 0.1, (math.random() - 0.5) * k * 0.1, 0)
		end)
	end
end)

-- ─── No jumping out of the car ───────────────────────────────────────────────
-- Space on a seated humanoid jumps it off the seat whatever its JumpHeight
-- (playtest 2026-10-25: Space in an OCEAN race dropped the driver into the
-- sea). With the Jumping state off the humanoid cannot leave the seat; SKY
-- still reads Space as "climb" through KeyInput. Modules/RaceSeat on the
-- server puts back anyone who gets out anyway.
local _jumpConn = nil
local function _lockJump(char, on)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if _jumpConn then _jumpConn:Disconnect(); _jumpConn = nil end
	if not hum then return end
	hum.JumpHeight = on and 0 or 7.2
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not on) end)
	if on then
		_jumpConn = hum:GetPropertyChangedSignal("Jump"):Connect(function()
			if hum.Jump then hum.Jump = false end
		end)
	end
end

LocalPlayer.CharacterAdded:Connect(function(char)
	if not _active then return end
	char:WaitForChild("Humanoid", 5)
	if _active then _lockJump(char, true) end
end)

-- ─── Enable / Disable ─────────────────────────────────────────────────────────

function RacingClient.enable()
	-- a client that started late missed BiomeSelected
	_biome        = _biome or ReplicatedStorage:GetAttribute("Biome")
	_active       = true
	_boostActive  = false
	_boostGauge   = 1
	_drifting     = false
	_abilityIndex = 1
	_updateBoostHUD()
	_resetCheckpointHUD()
	if _cpFrame then _cpFrame.Visible = true end

	_lockJump(LocalPlayer.Character, true)

	_abilityReadyAt = {}
	_abilityBusy    = false
	LocalPlayer:SetAttribute("AbilityNext", nil)

	if _heartbeatConn then _heartbeatConn:Disconnect() end
	_heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not _active then return end
		_driveLoop(dt)
		_updateCamera()
		_updateSpeedHUD()
		-- the HUD was rebuilt (respawn): draw the gauge on the new bar
		if not _live(_boostBar) then _updateBoostHUD() end
	end)
end

function RacingClient.disable()
	_active = false
	if _heartbeatConn then _heartbeatConn:Disconnect(); _heartbeatConn = nil end
	Camera.CameraType  = Enum.CameraType.Custom
	Camera.FieldOfView = _baseFOV
	_vehicle = nil
	_seat    = nil
	_hideDriftLabel()
	-- "CP1 ⬜ CP2 ⬜" stayed on screen through results, the lobby and every
	-- later phase (hidden behind the farming timer, plain in crafting)
	if _cpFrame then _cpFrame.Visible = false end

	_lockJump(LocalPlayer.Character, false)
end

-- ─── Biome / Phase listeners ─────────────────────────────────────────────────

_biome = ReplicatedStorage:GetAttribute("Biome")
RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	_biome = biome
end)
ReplicatedStorage:GetAttributeChangedSignal("Biome"):Connect(function()
	_biome = ReplicatedStorage:GetAttribute("Biome") or _biome
end)

-- The server sends the phase again after every respawn (SessionManager,
-- for StarterGui scripts that restart). The same phase twice is that resend,
-- never a new phase (the round always moves on to another one): enabling
-- again mid-race reset the gauge, the cooldowns and the checkpoint HUD.
local _lastPhase = nil
RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == _lastPhase then return end
	_lastPhase = phase
	if phase == Constants.PHASES.RACING then
		RacingClient.enable()
	else
		RacingClient.disable()
	end
end)

return RacingClient
