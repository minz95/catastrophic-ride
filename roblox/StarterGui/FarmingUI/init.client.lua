-- FarmingUI/init.client.lua
-- Farming phase overlay: countdown timer + 8-slot inventory bar.
-- Resolves: Issue #41 (Farming HUD)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
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
phaseLabel.Text            = "[E] Pick up  [Hold E] Steal  [F] Punch  [Hold G] Guard"
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

local invLayout = Instance.new("UIListLayout")
invLayout.FillDirection  = Enum.FillDirection.Horizontal
invLayout.VerticalAlignment = Enum.VerticalAlignment.Center
invLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
invLayout.Padding        = UDim.new(0, 4)
invLayout.Parent         = invBg

local slots = {}
for i = 1, Constants.INVENTORY_SIZE do
	local slot = Instance.new("Frame")
	slot.Name              = "Slot" .. i
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

local function _updateSlots(inventory)
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

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(_updateSlots)

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

local function _onPhase(phase)
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
