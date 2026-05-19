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

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local RacingClient = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _active        = false
local _vehicle       = nil   -- Model
local _seat          = nil   -- VehicleSeat
local _stats         = nil   -- vehicleStats table
local _biome         = nil
local _drifting      = false
local _boostActive   = false
local _boostGauge    = 1.0   -- 0–1, charges via DriftCorner zones
local _heartbeatConn = nil
local _baseFOV       = 70
local _abilitySlots  = {}    -- { slotName → itemName } from crafting

-- ─── Input tracking ───────────────────────────────────────────────────────────

local _keys = {
	W = false, A = false, S = false, D = false,
	Up = false, Down = false, Left = false, Right = false,
	Shift = false, Space = false, Ctrl = false,
	E = false,   -- ability
	F = false,   -- boost activation
}

local _suspParams = RaycastParams.new()
_suspParams.FilterType = Enum.RaycastFilterType.Exclude

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

UserInputService.InputBegan:Connect(function(input, processed)
	local k = KEY_MAP[input.KeyCode]
	if k then _keys[k] = true end

	if processed then return end
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
end)

UserInputService.InputEnded:Connect(function(input)
	local k = KEY_MAP[input.KeyCode]
	if k then _keys[k] = false end

	if not _active then return end

	if k == "Shift" and _drifting then
		_exitDrift()
	end
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

local function _ensureBoostHUD()
	if _boostBar then return end
	local hud = LocalPlayer.PlayerGui:FindFirstChild("HUD")
	if not hud then return end
	local frame = hud:FindFirstChild("BoostBar")
	if not frame then return end
	_boostBar   = frame:FindFirstChild("Fill")
	_boostLabel = frame:FindFirstChild("Label")
end

function _updateBoostHUD()
	if not _boostBar then _ensureBoostHUD() end
	if not _boostBar then return end
	TweenService:Create(_boostBar, TweenInfo.new(0.15), {
		Size = UDim2.new(_boostGauge, 0, 1, 0)
	}):Play()
	if _boostLabel then
		_boostLabel.Text = _boostGauge >= 1 and "BOOST  [F]" or "BOOST"
	end
end

function _showBoostReady()
	if not _boostBar then _ensureBoostHUD() end
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

local _driftGripBackup = nil
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

local function _enterDrift()
	if not _seat or _drifting then return end
	_drifting        = true
	_driftGripBackup = _seat.TurnSpeed
	_seat.TurnSpeed  = math.max(_seat.TurnSpeed * 0.35, 0.3)

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
end

function _exitDrift()
	if not _seat or not _drifting then return end
	_drifting = false
	if _driftGripBackup then
		_seat.TurnSpeed = _driftGripBackup
		_driftGripBackup = nil
	end
	_hideDriftLabel()
	-- No local slingshot: DriftCorner zones charge the boost gauge instead.
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
		lbl.Text           = "CP" .. i .. "  ☐"
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
			lbl.Text       = "CP" .. i .. (_cpPassed[i] and "  ✓" or "  ☐")
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

if RemoteEvents.CheckpointPassed then
	RemoteEvents.CheckpointPassed.OnClientEvent:Connect(function(cpIndex)
		if cpIndex == 1 or cpIndex == 2 then
			_cpPassed[cpIndex] = true
			_updateCheckpointHUD()
			_flashCheckpoint(cpIndex)
		end
	end)
end

-- ─── Vehicle drive loop ───────────────────────────────────────────────────────

local function _driveLoop()
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local primary = _vehicle.PrimaryPart

	local bv  = primary:FindFirstChild("DriveVelocity")
	local bav = primary:FindFirstChild("DriveAngular")
	if not bv or not bav then return end

	local maxSpeed  = _seat and _seat.MaxSpeed  or 40
	local turnSpeed = _seat and _seat.TurnSpeed or 1
	local throttle, steer

	-- Detect SKY mode by the vehicle's HoverPosition constraint rather than
	-- the _biome client variable. BiomeSelected can race against PhaseChanged
	-- on client load and leave _biome nil/stale — but the vehicle is
	-- authoritative about its own physics setup.
	local hover = primary:FindFirstChild("HoverPosition")
	local isSky = hover ~= nil

	throttle = 0
	if _keys.W or _keys.Up   then throttle =  1 end
	if _keys.S or _keys.Down then throttle = -0.5 end
	steer = 0
	if _keys.A or _keys.Left  then steer =  1 end
	if _keys.D or _keys.Right then steer = -1 end

	if isSky then
		turnSpeed = math.min(turnSpeed, 1.5)
		if hover then
			local dt = 1 / 60
			if _keys.Space then
				hover.Position = hover.Position + Vector3.new(0, 20 * dt, 0)
			elseif _keys.Ctrl then
				hover.Position = hover.Position - Vector3.new(0, 20 * dt, 0)
			end
		end
	else

		local isSteering = _keys.A or _keys.D or _keys.Left or _keys.Right
		if _keys.Shift and isSteering and not _drifting then
			local vel = primary.AssemblyLinearVelocity.Magnitude
			if vel > maxSpeed * 0.5 then _enterDrift() end
		end

		if _biome == "FOREST" then
			local susp = primary:FindFirstChild("SuspensionHover")
			if susp then
				local halfH = primary.Size.Y * 0.5
				local ray   = workspace:Raycast(
					primary.Position,
					Vector3.new(0, -(halfH + 5), 0),
					_suspParams
				)
				if ray then
					susp.Position = Vector3.new(
						primary.Position.X,
						ray.Position.Y + halfH + 0.2,
						primary.Position.Z
					)
					susp.MaxForce = Vector3.new(0, 4e4, 0)
				else
					susp.MaxForce = Vector3.zero
				end
			end
		end
	end

	local forward = primary.CFrame.LookVector
	bv.Velocity         = forward * throttle * maxSpeed
	bav.AngularVelocity = Vector3.new(0, steer * turnSpeed, 0)

	local gyro = primary:FindFirstChild("UprightGyro")
	if gyro then
		local _, currentY, _ = primary.CFrame:ToEulerAnglesYXZ()
		gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, currentY, 0)
	end
end

-- ─── Ability activation ───────────────────────────────────────────────────────

local _abilityOrder = { "SPECIAL", "ENGINE", "BODY" }
local _abilityIndex = 1

function _triggerAbility()
	local slotName = _abilityOrder[_abilityIndex]
	local itemName = _abilitySlots[slotName]
	if not itemName then
		_abilityIndex = (_abilityIndex % #_abilityOrder) + 1
		slotName  = _abilityOrder[_abilityIndex]
		itemName  = _abilitySlots[slotName]
		if not itemName then return end
	end

	local result = RemoteEvents.RequestAbility:InvokeServer(itemName)
	if result == "ok" then
		_abilityIndex = (_abilityIndex % #_abilityOrder) + 1
	end
end

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
		_applyScreenTint(Color3.fromRGB(255, 255, 255), 0.9, 0.5)

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

local function _updateCamera()
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local primary = _vehicle.PrimaryPart
	local lookDir = primary.CFrame.LookVector
	local camPos  = primary.Position - lookDir * 12 + Vector3.new(0, 5, 0)
	Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(camPos, primary.Position + Vector3.new(0, 1.5, 0)), 0.12)
end

-- ─── Speedometer update ───────────────────────────────────────────────────────

local _speedLabel = nil

local function _updateSpeedHUD()
	if not _speedLabel then
		local hud = LocalPlayer.PlayerGui:FindFirstChild("HUD")
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

-- ─── Enable / Disable ─────────────────────────────────────────────────────────

function RacingClient.enable()
	_active       = true
	_boostActive  = false
	_boostGauge   = 1
	_drifting     = false
	_abilityIndex = 1
	_updateBoostHUD()
	_resetCheckpointHUD()

	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpHeight = 0 end

	local tag = LocalPlayer.PlayerGui:FindFirstChild("CraftSlots")
	if tag then
		for _, v in ipairs(tag:GetChildren()) do
			if v:IsA("StringValue") then
				_abilitySlots[v.Name] = v.Value ~= "" and v.Value or nil
			end
		end
	end

	if _heartbeatConn then _heartbeatConn:Disconnect() end
	_heartbeatConn = RunService.Heartbeat:Connect(function()
		if not _active then return end
		_driveLoop()
		_updateCamera()
		_updateSpeedHUD()
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

	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.JumpHeight = 7.2 end
end

-- ─── Biome / Phase listeners ─────────────────────────────────────────────────

RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	_biome = biome
end)

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.RACING then
		RacingClient.enable()
	else
		RacingClient.disable()
	end
end)

return RacingClient
