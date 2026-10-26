-- LobbyUI/init.client.lua
-- Player list, biome reveal countdown, waiting room.
-- Resolves: Issue #41

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local LocalPlayer  = Players.LocalPlayer

-- ─── Build GUI ────────────────────────────────────────────────────────────────


-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "LobbyUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "LobbyUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = true
screen.Parent         = LocalPlayer.PlayerGui

-- ── Background blur feel ─────────────────────────────────────────────────────
local bg = Instance.new("Frame")
bg.Name             = "Background"
bg.Size             = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
bg.BackgroundTransparency = 0.15
bg.BorderSizePixel  = 0
bg.Parent           = screen

-- ── Title ────────────────────────────────────────────────────────────────────
local title = Instance.new("TextLabel")
title.Name              = "Title"
title.Size              = UDim2.new(0.6, 0, 0, 80)
title.Position          = UDim2.new(0.2, 0, 0.08, 0)
title.BackgroundTransparency = 1
title.Text              = "CATASTROPHIC RIDE"
title.TextColor3        = Color3.fromRGB(255, 220, 60)
title.TextScaled        = true
title.Font              = Enum.Font.GothamBlack
title.Parent            = bg

-- ── Biome badge ──────────────────────────────────────────────────────────────
local biomeBadge = Instance.new("Frame")
biomeBadge.Name            = "BiomeBadge"
biomeBadge.Size            = UDim2.new(0, 220, 0, 60)
biomeBadge.Position        = UDim2.new(0.5, -110, 0.2, 0)
biomeBadge.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
biomeBadge.BorderSizePixel = 0
biomeBadge.Parent          = bg

local biomeBadgeCorner = Instance.new("UICorner")
biomeBadgeCorner.CornerRadius = UDim.new(0, 12)
biomeBadgeCorner.Parent       = biomeBadge

local biomeLabel = Instance.new("TextLabel")
biomeLabel.Name             = "BiomeLabel"
biomeLabel.Size             = UDim2.fromScale(1, 1)
biomeLabel.BackgroundTransparency = 1
biomeLabel.Text             = "🌍  Biome: ?"
biomeLabel.TextColor3       = Color3.new(1, 1, 1)
biomeLabel.TextScaled       = true
biomeLabel.Font             = Enum.Font.GothamBold
biomeLabel.Parent           = biomeBadge

-- ── Player list ──────────────────────────────────────────────────────────────
local listFrame = Instance.new("Frame")
listFrame.Name             = "PlayerList"
listFrame.Size             = UDim2.new(0, 280, 0.5, 0)
listFrame.Position         = UDim2.new(0.5, -140, 0.33, 0)
listFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
listFrame.BackgroundTransparency = 0.2
listFrame.BorderSizePixel  = 0
listFrame.Parent           = bg

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius    = UDim.new(0, 10)
listCorner.Parent          = listFrame

local listTitle = Instance.new("TextLabel")
listTitle.Name             = "ListTitle"
listTitle.Size             = UDim2.new(1, 0, 0, 30)
listTitle.BackgroundTransparency = 1
listTitle.Text             = "Players"
listTitle.TextColor3       = Color3.fromRGB(180, 180, 220)
listTitle.TextScaled       = true
listTitle.Font             = Enum.Font.GothamBold
listTitle.Parent           = listFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name           = "Scroll"
scrollFrame.Size           = UDim2.new(1, -10, 1, -35)
scrollFrame.Position       = UDim2.new(0, 5, 0, 30)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 4
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize     = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent         = listFrame

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.SortOrder     = Enum.SortOrder.LayoutOrder
scrollLayout.Padding       = UDim.new(0, 4)
scrollLayout.Parent        = scrollFrame

-- ── Status / countdown ───────────────────────────────────────────────────────
local statusLabel = Instance.new("TextLabel")
statusLabel.Name            = "Status"
statusLabel.Size            = UDim2.new(0.6, 0, 0, 40)
statusLabel.Position        = UDim2.new(0.2, 0, 0.87, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text            = "Waiting for players…"
statusLabel.TextColor3      = Color3.fromRGB(200, 200, 200)
statusLabel.TextScaled      = true
statusLabel.Font            = Enum.Font.Gotham
statusLabel.Parent          = bg

-- ─── Player row builder ───────────────────────────────────────────────────────

-- "Players: 2 / 10  ·  Starting in 0:08" (PhaseEndsAt, GameManager's lobby clock)
local function _updateStatus()
	local left = PhaseClock.remaining(nil)
	local players = string.format("Players: %d / %d", #Players:GetPlayers(), Constants.MAX_PLAYERS)
	statusLabel.Text = left and (players .. "   ·   Starting in " .. PhaseClock.format(left)) or (players .. "   ·   Waiting for players")
end
game:GetService("RunService").Heartbeat:Connect(function()
	if screen.Enabled then _updateStatus() end
end)

local function _buildPlayerList()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i, player in ipairs(Players:GetPlayers()) do
		local row = Instance.new("Frame")
		row.Name              = "Row_" .. player.UserId
		row.Size              = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3  = (player == LocalPlayer)
			and Color3.fromRGB(60, 80, 100)
			or  Color3.fromRGB(35, 38, 55)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel   = 0
		row.LayoutOrder       = i
		row.Parent            = scrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent       = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size          = UDim2.fromScale(1, 1)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text          = (player == LocalPlayer and "★ " or "  ") .. player.Name
		nameLbl.TextColor3    = Color3.new(1, 1, 1)
		nameLbl.TextScaled    = true
		nameLbl.Font          = Enum.Font.Gotham
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent        = row

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.Parent      = nameLbl
	end
	_updateStatus()
end

Players.PlayerAdded:Connect(_buildPlayerList)
Players.PlayerRemoving:Connect(_buildPlayerList)
_buildPlayerList()

-- ─── Biome reveal ─────────────────────────────────────────────────────────────

local _biomeNames = {
	FOREST = "🌲  FOREST",
	OCEAN  = "🌊  OCEAN",
	SKY    = "☁️  SKY",
}
local _biomeColors = {
	FOREST = Color3.fromRGB(60, 160, 60),
	OCEAN  = Color3.fromRGB(40, 100, 220),
	SKY    = Color3.fromRGB(120, 80, 220),
}

RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	biomeLabel.Text = _biomeNames[biome] or biome
	TweenService:Create(biomeBadge, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
		BackgroundColor3 = _biomeColors[biome] or Color3.fromRGB(60, 60, 80)
	}):Play()
	-- Pulse animation
	TweenService:Create(biomeBadge, TweenInfo.new(0.15), {
		Size = UDim2.new(0, 240, 0, 68)
	}):Play()
	task.delay(0.15, function()
		TweenService:Create(biomeBadge, TweenInfo.new(0.2), {
			Size = UDim2.new(0, 220, 0, 60)
		}):Play()
	end)
end)

-- ─── Phase handling ───────────────────────────────────────────────────────────

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.LOBBY then
		screen.Enabled = true
		_buildPlayerList()
	else
		screen.Enabled = false
	end
end)
