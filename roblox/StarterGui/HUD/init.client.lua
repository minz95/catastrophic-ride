-- HUD/init.client.lua
-- Race HUD: position tracker, boost bar, speedometer, ability cooldown.
-- Resolves: Issue #43

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local LocalPlayer  = Players.LocalPlayer

-- ─── Build GUI ────────────────────────────────────────────────────────────────


-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "HUD" and old:IsA("ScreenGui") then old:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "HUD"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled        = false
screenGui.Parent         = LocalPlayer.PlayerGui

-- ── Drift / Boost key hint ──────────────────────────────────────────────────
local keyHint = Instance.new("TextLabel")
keyHint.Name             = "KeyHint"
keyHint.Size             = UDim2.new(0, 240, 0, 14)
keyHint.Position         = UDim2.new(0.5, -120, 1, -38)
keyHint.BackgroundTransparency = 1
keyHint.Text             = "[ SHIFT = Drift  ·  F = Boost ]"
keyHint.TextColor3       = Color3.fromRGB(160, 160, 160)
keyHint.TextScaled       = true
keyHint.Font             = Enum.Font.Gotham
keyHint.Parent           = screenGui

-- ── Finish countdown: shown once the winner is in (RacingManager shortens the
-- race to Constants.FINISH_GRACE and sets PhaseEndsAt) ──────────────────────
local PhaseClock = require(ReplicatedStorage.Shared.PhaseClock)
local raceClock = Instance.new("TextLabel")
raceClock.Name             = "RaceClock"
raceClock.Size             = UDim2.new(0, 260, 0, 34)
raceClock.Position         = UDim2.new(0.5, -130, 0, 64)
raceClock.BackgroundTransparency = 1
raceClock.TextColor3       = Color3.fromRGB(255, 220, 90)
raceClock.TextStrokeTransparency = 0.3
raceClock.TextScaled       = true
raceClock.Font             = Enum.Font.GothamBlack
raceClock.Visible          = false
raceClock.Parent           = screenGui

local function _updateRaceClock()
	local left = PhaseClock.remaining(nil)
	raceClock.Visible = left ~= nil
	if left then raceClock.Text = "🏁 TIME LEFT " .. PhaseClock.format(left) end
end

-- ── Boost Bar ──────────────────────────────────────────────────────────────
local boostBar = Instance.new("Frame")
boostBar.Name            = "BoostBar"
boostBar.Size            = UDim2.new(0, 200, 0, 18)
boostBar.Position        = UDim2.new(0.5, -100, 1, -60)
boostBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
boostBar.BorderSizePixel = 0
boostBar.Parent          = screenGui

local boostCorner = Instance.new("UICorner")
boostCorner.CornerRadius = UDim.new(0, 4)
boostCorner.Parent       = boostBar

local boostFill = Instance.new("Frame")
boostFill.Name             = "Fill"
boostFill.Size             = UDim2.new(1, 0, 1, 0)
boostFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
boostFill.BorderSizePixel  = 0
boostFill.Parent           = boostBar

local boostFillCorner = Instance.new("UICorner")
boostFillCorner.CornerRadius = UDim.new(0, 4)
boostFillCorner.Parent       = boostFill

local boostLabel = Instance.new("TextLabel")
boostLabel.Name             = "Label"
boostLabel.Size             = UDim2.fromScale(1, 1)
boostLabel.BackgroundTransparency = 1
boostLabel.Text             = "BOOST"
boostLabel.TextColor3       = Color3.new(1, 1, 1)
boostLabel.TextScaled       = true
boostLabel.Font             = Enum.Font.GothamBold
boostLabel.Parent           = boostBar

-- ── Speedometer ─────────────────────────────────────────────────────────────
local speedFrame = Instance.new("Frame")
speedFrame.Name            = "Speedometer"
speedFrame.Size            = UDim2.new(0, 80, 0, 50)
speedFrame.Position        = UDim2.new(1, -100, 1, -80)
speedFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
speedFrame.BackgroundTransparency = 0.3
speedFrame.BorderSizePixel = 0
speedFrame.Parent          = screenGui

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius   = UDim.new(0, 8)
speedCorner.Parent         = speedFrame

local speedValue = Instance.new("TextLabel")
speedValue.Name             = "Value"
speedValue.Size             = UDim2.new(1, 0, 0.6, 0)
speedValue.BackgroundTransparency = 1
speedValue.Text             = "0"
speedValue.TextColor3       = Color3.new(1, 1, 1)
speedValue.TextScaled       = true
speedValue.Font             = Enum.Font.GothamBold
speedValue.Parent           = speedFrame

local speedUnit = Instance.new("TextLabel")
speedUnit.Name              = "Unit"
speedUnit.Size              = UDim2.new(1, 0, 0.4, 0)
speedUnit.Position          = UDim2.new(0, 0, 0.6, 0)
speedUnit.BackgroundTransparency = 1
speedUnit.Text              = "km/h"
speedUnit.TextColor3        = Color3.fromRGB(180, 180, 180)
speedUnit.TextScaled        = true
speedUnit.Font              = Enum.Font.Gotham
speedUnit.Parent            = speedFrame

-- ── Position Tracker ─────────────────────────────────────────────────────────
local posFrame = Instance.new("Frame")
posFrame.Name              = "PositionTracker"
posFrame.Size              = UDim2.new(0, 160, 0, 0)  -- height set by layout
posFrame.Position          = UDim2.new(1, -180, 0, 20)
posFrame.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
posFrame.BackgroundTransparency = 0.4
posFrame.BorderSizePixel   = 0
posFrame.AutomaticSize     = Enum.AutomaticSize.Y
posFrame.Parent            = screenGui

local posCorner = Instance.new("UICorner")
posCorner.CornerRadius     = UDim.new(0, 8)
posCorner.Parent           = posFrame

local posLayout = Instance.new("UIListLayout")
posLayout.SortOrder        = Enum.SortOrder.LayoutOrder
posLayout.Padding          = UDim.new(0, 2)
posLayout.Parent           = posFrame

local posPad = Instance.new("UIPadding")
posPad.PaddingTop          = UDim.new(0, 6)
posPad.PaddingBottom       = UDim.new(0, 6)
posPad.PaddingLeft         = UDim.new(0, 8)
posPad.PaddingRight        = UDim.new(0, 8)
posPad.Parent              = posFrame

-- ── Ability Cooldown ─────────────────────────────────────────────────────────
local abilityFrame = Instance.new("Frame")
abilityFrame.Name          = "AbilitySlot"
abilityFrame.Size          = UDim2.new(0, 60, 0, 60)
abilityFrame.Position      = UDim2.new(0.5, 70, 1, -80)
abilityFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
abilityFrame.BorderSizePixel = 0
abilityFrame.Parent        = screenGui

local abilityCorner = Instance.new("UICorner")
abilityCorner.CornerRadius = UDim.new(0, 8)
abilityCorner.Parent       = abilityFrame

local abilityIcon = Instance.new("TextLabel")
abilityIcon.Name            = "Icon"
abilityIcon.Size            = UDim2.new(1, 0, 0.65, 0)
abilityIcon.BackgroundTransparency = 1
abilityIcon.Text            = "E"
abilityIcon.TextColor3      = Color3.new(1, 1, 1)
abilityIcon.TextScaled      = true
abilityIcon.Font            = Enum.Font.GothamBold
abilityIcon.Parent          = abilityFrame

local abilityCooldownOverlay = Instance.new("Frame")
abilityCooldownOverlay.Name = "CooldownOverlay"
abilityCooldownOverlay.Size = UDim2.fromScale(1, 0)   -- grows from bottom
abilityCooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
abilityCooldownOverlay.AnchorPoint = Vector2.new(0, 1)
abilityCooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
abilityCooldownOverlay.BackgroundTransparency = 0.5
abilityCooldownOverlay.BorderSizePixel = 0
abilityCooldownOverlay.Parent = abilityFrame

local abilityCooldownCorner = Instance.new("UICorner")
abilityCooldownCorner.CornerRadius = UDim.new(0, 8)
abilityCooldownCorner.Parent       = abilityCooldownOverlay

local abilityKeyHint = Instance.new("TextLabel")
abilityKeyHint.Name             = "KeyHint"
abilityKeyHint.Size             = UDim2.new(1, 0, 0.35, 0)
abilityKeyHint.Position         = UDim2.new(0, 0, 0.65, 0)
abilityKeyHint.BackgroundTransparency = 1
abilityKeyHint.Text             = "[E]"
abilityKeyHint.TextColor3       = Color3.fromRGB(200, 200, 200)
abilityKeyHint.TextScaled       = true
abilityKeyHint.Font             = Enum.Font.Gotham
abilityKeyHint.Parent           = abilityFrame

-- ─── Position row builder ─────────────────────────────────────────────────────

local _posRows = {}

local function _getRankColor(rank)
	if rank == 1 then return Color3.fromRGB(255, 215, 0)
	elseif rank == 2 then return Color3.fromRGB(200, 200, 200)
	elseif rank == 3 then return Color3.fromRGB(205, 127, 50)
	else return Color3.new(1, 1, 1)
	end
end

local function _updatePositionTracker(data)
	-- data: array of { userId, progress, rank }
	-- Sort by rank
	table.sort(data, function(a, b) return a.rank < b.rank end)

	-- Reuse or create rows
	for i, entry in ipairs(data) do
		local row = _posRows[i]
		if not row then
			row = Instance.new("Frame")
			row.Name              = "Row" .. i
			row.Size              = UDim2.new(1, 0, 0, 20)
			row.BackgroundTransparency = 1
			row.LayoutOrder       = i
			row.Parent            = posFrame

			local rankLbl = Instance.new("TextLabel")
			rankLbl.Name          = "Rank"
			rankLbl.Size          = UDim2.new(0.15, 0, 1, 0)
			rankLbl.BackgroundTransparency = 1
			rankLbl.TextScaled    = true
			rankLbl.Font          = Enum.Font.GothamBold
			rankLbl.Parent        = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name          = "Name"
			nameLbl.Size          = UDim2.new(0.85, 0, 1, 0)
			nameLbl.Position      = UDim2.new(0.15, 0, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextScaled    = true
			nameLbl.Font          = Enum.Font.Gotham
			nameLbl.Parent        = row

			_posRows[i] = row
		end

		local player = game:GetService("Players"):GetPlayerByUserId(entry.userId)
		local name   = player and player.Name or ("User" .. entry.userId)
		local color  = _getRankColor(entry.rank)

		-- Highlight local player
		local isMe  = entry.userId == LocalPlayer.UserId
		row.BackgroundTransparency = isMe and 0.7 or 1
		if isMe then row.BackgroundColor3 = Color3.fromRGB(80, 80, 80) end

		row:FindFirstChild("Rank").Text       = "#" .. entry.rank
		row:FindFirstChild("Rank").TextColor3 = color
		row:FindFirstChild("Name").Text       = name
		row:FindFirstChild("Name").TextColor3 = isMe and Color3.new(1, 1, 1) or Color3.fromRGB(220, 220, 220)
	end

	-- Hide extra rows
	for i = #data + 1, #_posRows do
		if _posRows[i] then _posRows[i].Visible = false end
	end
end

-- ─── Speedometer update ───────────────────────────────────────────────────────

local _lastSpeed = 0

local function _updateSpeed(vehicle)
	if not vehicle or not vehicle.PrimaryPart then
		speedValue.Text = "0"
		return
	end
	local vel = vehicle.PrimaryPart.AssemblyLinearVelocity.Magnitude
	-- Convert studs/s → approximate km/h (1 stud ≈ 0.28m)
	local kmh = math.floor(vel * 0.28 * 3.6)
	if kmh ~= _lastSpeed then
		_lastSpeed = kmh
		speedValue.Text = tostring(kmh)
		-- Color: green < 60, yellow < 100, red otherwise
		if kmh < 60 then
			speedValue.TextColor3 = Color3.fromRGB(80, 255, 80)
		elseif kmh < 100 then
			speedValue.TextColor3 = Color3.fromRGB(255, 230, 60)
		else
			speedValue.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
	end
end

-- ─── Ability icon update ──────────────────────────────────────────────────────

-- Args: (userId, itemName, targetIds, effectKey, info = { cooldown, ... }).
local _cooldownOf = {}   -- [itemName] = seconds (from the server)
RemoteEvents.AbilityActivated.OnClientEvent:Connect(function(userId, itemName, _targetIds, _effectKey, info)
	if userId ~= LocalPlayer.UserId then return end
	if type(info) == "table" and info.cooldown then _cooldownOf[itemName] = info.cooldown end
	-- Brief flash feedback
	TweenService:Create(abilityFrame, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(255, 220, 60)
	}):Play()
	task.delay(0.2, function()
		TweenService:Create(abilityFrame, TweenInfo.new(0.3), {
			BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		}):Play()
	end)
end)

-- The item E fires next and its remaining cooldown (RacingClient sets the
-- LocalPlayer attributes AbilityNext / AbilityWait).
local function _updateAbilitySlot()
	local item = LocalPlayer:GetAttribute("AbilityNext")
	local wait = LocalPlayer:GetAttribute("AbilityWait") or 0
	local cfg = item and ItemConfig[item]
	abilityFrame.Visible = item ~= nil
	abilityIcon.Text = cfg and cfg.icon or "E"
	local total = (item and _cooldownOf[item]) or 10
	abilityCooldownOverlay.Size = UDim2.fromScale(1, math.clamp(wait / total, 0, 1))
	abilityKeyHint.Text = wait > 0 and string.format("%.0f", math.ceil(wait)) or "[E]"
end
LocalPlayer:GetAttributeChangedSignal("AbilityNext"):Connect(_updateAbilitySlot)
LocalPlayer:GetAttributeChangedSignal("AbilityWait"):Connect(_updateAbilitySlot)

-- ─── Phase / enable handling ──────────────────────────────────────────────────

local _vehicle = nil
local _runConn = nil

local function _enableHUD(biome)
	screenGui.Enabled = true

	-- Biome colour theming
	local barColour
	if biome == "FOREST" then
		barColour = Color3.fromRGB(80, 200, 80)
	elseif biome == "OCEAN" then
		barColour = Color3.fromRGB(60, 140, 255)
	elseif biome == "SKY" then
		barColour = Color3.fromRGB(180, 120, 255)
	else
		barColour = Color3.fromRGB(80, 180, 255)
	end
	boostFill.BackgroundColor3 = barColour

	-- Speed update loop
	if _runConn then _runConn:Disconnect() end
	_runConn = RunService.Heartbeat:Connect(function()
		_updateSpeed(_vehicle)
		_updateRaceClock()
	end)
end

local function _disableHUD()
	screenGui.Enabled = false
	if _runConn then _runConn:Disconnect(); _runConn = nil end
	_vehicle = nil
end

-- ─── Remote listeners ────────────────────────────────────────────────────────

local _cachedBiome = nil

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	local Constants = require(ReplicatedStorage.Shared.Constants)
	if phase == Constants.PHASES.RACING then
		_enableHUD(_cachedBiome)
	elseif phase ~= Constants.PHASES.RACING then
		_disableHUD()
	end
end)

RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	-- Cache biome; HUD only activates when RACING phase starts.
	_cachedBiome = biome
end)

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, vehicleModel)
	if userId == LocalPlayer.UserId then
		_vehicle = vehicleModel
	end
end)

RemoteEvents.PlayerPositionSync.OnClientEvent:Connect(function(data)
	if not screenGui.Enabled then return end
	_updatePositionTracker(data)
end)
