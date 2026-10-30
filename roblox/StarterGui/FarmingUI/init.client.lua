-- FarmingUI/init.client.lua
-- Farming phase overlay: countdown timer + 8-slot inventory bar.
-- Resolves: Issue #41 (Farming HUD)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local InputHints   = require(ReplicatedStorage.Shared.InputHints)
local LocalPlayer  = Players.LocalPlayer

-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so only one timer shows.
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "FarmingUI" and old:IsA("ScreenGui") then old:Destroy() end
end

-- ─── Screen ───────────────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name           = "FarmingUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = false
screen.Parent         = LocalPlayer.PlayerGui

-- ─── Timer bar (top center) ──────────────────────────────────────────────────

local timerBg = Instance.new("Frame")
timerBg.Name             = "TimerBg"
timerBg.Size             = UDim2.new(0, 260, 0, 46)
timerBg.Position         = UDim2.new(0.5, -130, 0, 14)
timerBg.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
timerBg.BackgroundTransparency = 0.25
timerBg.BorderSizePixel  = 0
timerBg.Parent           = screen

local _tc = Instance.new("UICorner"); _tc.CornerRadius = UDim.new(0, 10); _tc.Parent = timerBg

local timerLabel = Instance.new("TextLabel")
timerLabel.Name            = "TimerLabel"
timerLabel.Size            = UDim2.new(1, 0, 0.5, 0)
timerLabel.Position        = UDim2.new(0, 0, 0, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Text            = "FARMING"   -- the time comes from PhaseEndsAt (_startTimer)
timerLabel.Font            = Enum.Font.GothamBold
timerLabel.TextScaled      = true
timerLabel.TextColor3      = Color3.fromRGB(80, 220, 80)
timerLabel.Parent          = timerBg

local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name            = "PhaseLabel"
phaseLabel.Size            = UDim2.new(1, 0, 0.5, 0)
phaseLabel.Position        = UDim2.new(0, 0, 0.5, 0)
phaseLabel.BackgroundTransparency = 1
local function _keyLine()
	-- on a touch screen the buttons are named: the four-part line wrapped
	-- into two tiny lines under the timer (Studio Device Simulator)
	if InputHints.touchUI() then return "Hold GRAB next to someone to steal" end
	return string.format("%s Pick up  %s Steal  %s Punch  %s Guard",
		InputHints.tag("grab"), InputHints.hold("steal"), InputHints.tag("punch"), InputHints.hold("guard"))
end
phaseLabel.Text            = _keyLine()
InputHints.onChange(function() phaseLabel.Text = _keyLine() end)
phaseLabel.Font            = Enum.Font.Gotham
phaseLabel.TextScaled      = true
phaseLabel.TextColor3      = Color3.fromRGB(200, 200, 200)
phaseLabel.Parent          = timerBg

-- ─── Inventory bar (bottom center) ───────────────────────────────────────────

local invBg = Instance.new("Frame")
invBg.Name             = "InventoryBar"
invBg.Size             = UDim2.new(0, 8 * 60 + 18, 0, 64)
invBg.Position         = UDim2.new(0.5, -(8 * 60 + 18) / 2, 1, -82)
invBg.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
invBg.BackgroundTransparency = 0.25
invBg.BorderSizePixel  = 0
invBg.Parent           = screen

local _ic = Instance.new("UICorner"); _ic.CornerRadius = UDim.new(0, 10); _ic.Parent = invBg

-- One row of eight on a keyboard; on a touch screen two rows of four
-- between the thumbstick's side and the buttons (Shared/TouchLayout.bag):
-- the long bar ran under both (playtest 2026-10-30).
local invLayout = Instance.new("UIGridLayout")
invLayout.FillDirection  = Enum.FillDirection.Horizontal
invLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
invLayout.VerticalAlignment = Enum.VerticalAlignment.Center
invLayout.SortOrder      = Enum.SortOrder.LayoutOrder
invLayout.CellPadding    = UDim2.fromOffset(4, 4)
invLayout.CellSize       = UDim2.fromOffset(54, 54)
invLayout.FillDirectionMaxCells = 8
invLayout.Parent         = invBg

local TouchLayout = require(ReplicatedStorage.Shared.TouchLayout)
local function _layoutBag()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and InputHints.touchUI() then
		local b = TouchLayout.bag(vp.X, vp.Y, TouchLayout.gridLeft(LocalPlayer.PlayerGui))
		invLayout.CellSize = UDim2.fromOffset(b.cell, b.cell)
		invLayout.CellPadding = UDim2.fromOffset(TouchLayout.BAG_GAP, TouchLayout.BAG_GAP)
		invLayout.FillDirectionMaxCells = 4
		invBg.Size = UDim2.fromOffset(b.w, b.h)
		invBg.Position = UDim2.fromOffset(b.x, b.y)
	else
		invLayout.CellSize = UDim2.fromOffset(54, 54)
		invLayout.CellPadding = UDim2.fromOffset(4, 4)
		invLayout.FillDirectionMaxCells = 8
		invBg.Size = UDim2.new(0, 8 * 60 + 18, 0, 64)
		invBg.Position = UDim2.new(0.5, -(8 * 60 + 18) / 2, 1, -82)
	end
end

local slots = {}
for i = 1, Constants.INVENTORY_SIZE do
	local slot = Instance.new("Frame")
	slot.Name              = "Slot" .. i
	slot.LayoutOrder       = i
	slot.Size              = UDim2.new(0, 54, 0, 54)
	slot.BackgroundColor3  = Color3.fromRGB(35, 35, 50)
	slot.BorderSizePixel   = 0
	slot.Parent            = invBg

	local _sc = Instance.new("UICorner"); _sc.CornerRadius = UDim.new(0, 6); _sc.Parent = slot

	local icon = Instance.new("TextLabel")
	icon.Name              = "Icon"
	icon.Size              = UDim2.new(1, 0, 0.58, 0)
	icon.BackgroundTransparency = 1
	icon.Text              = ""
	icon.Font              = Enum.Font.GothamBold
	icon.TextScaled        = true
	icon.TextColor3        = Color3.new(1, 1, 1)
	icon.Parent            = slot

	local name = Instance.new("TextLabel")
	name.Name              = "ItemName"
	name.Size              = UDim2.new(1, 0, 0.42, 0)
	name.Position          = UDim2.new(0, 0, 0.58, 0)
	name.BackgroundTransparency = 1
	name.Text              = ""
	name.Font              = Enum.Font.Gotham
	name.TextScaled        = true
	name.TextColor3        = Color3.fromRGB(180, 180, 180)
	name.Parent            = slot

	-- tap twice to drop this item (the touch screen's DROP button is gone;
	-- a click works too)
	local hit = Instance.new("TextButton")
	hit.Name                   = "Hit"
	hit.Size                   = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text                   = ""
	hit.ZIndex                 = 3
	hit.Parent                 = slot
	local stroke = Instance.new("UIStroke")
	stroke.Name      = "Armed"
	stroke.Color     = Color3.fromRGB(255, 90, 70)
	stroke.Thickness = 2
	stroke.Enabled   = false
	stroke.Parent    = slot

	slots[i] = slot
end

-- ─── Inventory update ─────────────────────────────────────────────────────────

local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)

local RARITY_COLOUR = {
	Common   = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(80,  200, 80),
	Rare     = Color3.fromRGB(100, 160, 255),
	Epic     = Color3.fromRGB(200, 100, 255),
}

-- Tap a slot: it turns red ("Drop?"); tap it again within ARM_SECONDS to drop.
local ARM_SECONDS = 2.5
local _inventory = {}
local _armed, _armedAt = nil, 0
local _updateSlots
local function _disarm()
	if _armed and slots[_armed] then slots[_armed]:FindFirstChild("Armed").Enabled = false end
	_armed = nil
	_updateSlots(_inventory)
end
for i, slot in ipairs(slots) do
	slot:FindFirstChild("Hit").Activated:Connect(function()
		if not _inventory[i] then return end
		if _armed == i and os.clock() - _armedAt < ARM_SECONDS then
			_disarm()
			task.spawn(function() RemoteEvents.RequestDrop:InvokeServer(i) end)
			return
		end
		if _armed then _disarm() end
		_armed, _armedAt = i, os.clock()
		slot:FindFirstChild("Armed").Enabled = true
		slot:FindFirstChild("ItemName").Text = "Drop?"
		slot:FindFirstChild("ItemName").TextColor3 = Color3.fromRGB(255, 120, 100)
		local at = _armedAt
		task.delay(ARM_SECONDS, function()
			if _armed == i and _armedAt == at then _disarm() end
		end)
	end)
end

_updateSlots = function(inventory)
	_inventory = inventory or {}
	if _armed and not _inventory[_armed] then
		slots[_armed]:FindFirstChild("Armed").Enabled = false
		_armed = nil
	end
	for i = 1, Constants.INVENTORY_SIZE do
		local slot = slots[i]
		local itemName = inventory[i]
		if itemName then
			local cfg = ItemConfig[itemName]
			slot:FindFirstChild("Icon").Text     = (cfg and cfg.icon) or "?"
			slot:FindFirstChild("ItemName").Text = itemName
			slot:FindFirstChild("ItemName").TextColor3 =
				RARITY_COLOUR[(cfg and cfg.rarity) or "Common"]
			slot.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
		else
			slot:FindFirstChild("Icon").Text     = ""
			slot:FindFirstChild("ItemName").Text = ""
			slot.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
		end
	end
end

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inv)
	if _armed then
		slots[_armed]:FindFirstChild("Armed").Enabled = false
		_armed = nil
	end
	_updateSlots(inv)
end)

-- the bag's place follows the screen and the device in use
_layoutBag()
InputHints.onChange(_layoutBag)
task.spawn(function()
	while screen.Parent do
		if screen.Enabled then _layoutBag() end
		task.wait(0.5)
	end
end)

-- ─── Timer countdown ─────────────────────────────────────────────────────────

local _runConn     = nil

local function _startTimer()
	if _runConn then _runConn:Disconnect() end
	local function update()
		-- Server end time (PhaseClock). Until PhaseEndsAt has arrived show no
		-- time (a guessed Constants duration showed 1:30 in a 60 s round).
		local remaining = PhaseClock.remaining(nil)
		if not remaining then
			timerLabel.Text = "FARMING"
			return
		end
		timerLabel.Text = "FARMING  " .. PhaseClock.format(remaining)

		-- Pulse red in last 15 seconds
		if remaining <= 15 then
			local blink = math.floor(remaining * 2) % 2 == 0
			timerLabel.TextColor3 = blink
				and Color3.fromRGB(255, 60, 60)
				or  Color3.fromRGB(255, 180, 60)
		else
			timerLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
		end
	end
	update()   -- right away, before the first frame shows the old text
	_runConn = RunService.Heartbeat:Connect(function()
		if screen.Enabled then update() end
	end)
end

local function _stopTimer()
	if _runConn then _runConn:Disconnect(); _runConn = nil end
end

-- ─── Phase gate ───────────────────────────────────────────────────────────────

-- The server sends the phase again after a respawn (SessionManager); this
-- script also reads it at start. The same phase twice is that resend (the
-- round always moves on to another phase), not a new round: emptying the
-- bar then lost the items on screen (the server sends the bag right after).
local _lastPhase = nil
local function _onPhase(phase)
	if phase == _lastPhase then return end
	_lastPhase = phase
	if phase == Constants.PHASES.FARMING then
		_updateSlots({})
		screen.Enabled = true
		-- Only start timer if not already running (prevent reset on CharacterAdded re-send)
		if not _runConn then
			_startTimer()
		end
	else
		screen.Enabled = false
		_stopTimer()
	end
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(_onPhase)

-- Started after the FARMING event went out (respawn, slow client): join it.
if ReplicatedStorage:GetAttribute("Phase") then
	_onPhase(ReplicatedStorage:GetAttribute("Phase"))
end
