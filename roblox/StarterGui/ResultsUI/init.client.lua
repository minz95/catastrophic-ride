-- ResultsUI/init.client.lua
-- Post-race podium, times, your reward and the next-round clock.
-- Resolves: Issue #44

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local Cosmetics    = require(ReplicatedStorage.Shared.Cosmetics)
local LocalPlayer  = Players.LocalPlayer

-- ─── Build GUI ────────────────────────────────────────────────────────────────


-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "ResultsUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "ResultsUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = false
screen.Parent         = LocalPlayer.PlayerGui

local bg = Instance.new("Frame")
bg.Name             = "Background"
bg.Size             = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 8, 20)
bg.BackgroundTransparency = 0.1
bg.BorderSizePixel  = 0
bg.Parent           = screen

-- ── Title ────────────────────────────────────────────────────────────────────
local title = Instance.new("TextLabel")
title.Name              = "Title"
title.Size              = UDim2.new(0.6, 0, 0, 70)
title.Position          = UDim2.new(0.2, 0, 0.04, 0)
title.BackgroundTransparency = 1
title.Text              = "RESULTS"
title.TextColor3        = Color3.fromRGB(255, 220, 60)
title.TextScaled        = true
title.Font              = Enum.Font.GothamBlack
title.Parent            = bg

-- ── Podium ───────────────────────────────────────────────────────────────────
-- 3 podium stands at different heights: 2nd (left), 1st (center), 3rd (right)
local podiumData = {
	{ rank = 2, x = 0.22, h = 0.15, color = Color3.fromRGB(180, 180, 180) },
	{ rank = 1, x = 0.42, h = 0.22, color = Color3.fromRGB(255, 200, 40)  },
	{ rank = 3, x = 0.62, h = 0.10, color = Color3.fromRGB(180, 120, 60)  },
}

local _podiumLabels = {}  -- rank → { name, time }

for _, pd in ipairs(podiumData) do
	local stand = Instance.new("Frame")
	stand.Name              = "Stand_" .. pd.rank
	stand.Size              = UDim2.new(0.14, 0, pd.h, 0)
	stand.Position          = UDim2.new(pd.x, 0, 0.72 - pd.h, 0)
	stand.BackgroundColor3  = pd.color
	stand.BorderSizePixel   = 0
	stand.Parent            = bg

	local standCorner = Instance.new("UICorner")
	standCorner.CornerRadius = UDim.new(0, 6)
	standCorner.Parent       = stand

	local rankMark = Instance.new("TextLabel")
	rankMark.Size           = UDim2.fromScale(1, 0.5)
	rankMark.BackgroundTransparency = 1
	rankMark.Text           = "#" .. pd.rank
	rankMark.TextColor3     = Color3.new(0, 0, 0)
	rankMark.TextScaled     = true
	rankMark.Font           = Enum.Font.GothamBlack
	rankMark.Parent         = stand

	-- Name label above stand
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name            = "NameLbl"
	nameLbl.Size            = UDim2.new(0.18, 0, 0, 28)
	nameLbl.Position        = UDim2.new(pd.x - 0.02, 0, 0.72 - pd.h - 0.06, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text            = "—"
	nameLbl.TextColor3      = Color3.new(1, 1, 1)
	nameLbl.TextScaled      = true
	nameLbl.Font            = Enum.Font.GothamBold
	nameLbl.Parent          = bg

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name            = "TimeLbl"
	timeLbl.Size            = UDim2.new(0.18, 0, 0, 20)
	timeLbl.Position        = UDim2.new(pd.x - 0.02, 0, 0.72 - pd.h - 0.03, 0)
	timeLbl.BackgroundTransparency = 1
	timeLbl.Text            = ""
	timeLbl.TextColor3      = Color3.fromRGB(200, 200, 200)
	timeLbl.TextScaled      = true
	timeLbl.Font            = Enum.Font.Gotham
	timeLbl.Parent          = bg

	_podiumLabels[pd.rank] = { name = nameLbl, time = timeLbl }
end

-- ── Full leaderboard ─────────────────────────────────────────────────────────
local lbFrame = Instance.new("Frame")
lbFrame.Name              = "Leaderboard"
lbFrame.Size              = UDim2.new(0.4, 0, 0.22, 0)
lbFrame.Position          = UDim2.new(0.3, 0, 0.74, 0)
lbFrame.BackgroundColor3  = Color3.fromRGB(20, 20, 35)
lbFrame.BackgroundTransparency = 0.3
lbFrame.BorderSizePixel   = 0
lbFrame.AutomaticSize     = Enum.AutomaticSize.Y
lbFrame.Parent            = bg

local lbCorner = Instance.new("UICorner")
lbCorner.CornerRadius     = UDim.new(0, 8)
lbCorner.Parent           = lbFrame

local lbLayout = Instance.new("UIListLayout")
lbLayout.SortOrder        = Enum.SortOrder.LayoutOrder
lbLayout.Padding          = UDim.new(0, 2)
lbLayout.Parent           = lbFrame

local lbPad = Instance.new("UIPadding")
lbPad.PaddingTop          = UDim.new(0, 4)
lbPad.PaddingBottom       = UDim.new(0, 4)
lbPad.PaddingLeft         = UDim.new(0, 8)
lbPad.PaddingRight        = UDim.new(0, 8)
lbPad.Parent              = lbFrame

-- ── Play Again button ────────────────────────────────────────────────────────
-- "Next round in 0:12" (PhaseEndsAt). There is no vote: the next round
-- starts on its own (the old PLAY AGAIN button did nothing).
local nextLbl = Instance.new("TextLabel")
nextLbl.Name                   = "NextRound"
nextLbl.Size                   = UDim2.new(0, 320, 0, 36)
nextLbl.Position               = UDim2.new(0.5, -160, 0.9, 0)
nextLbl.BackgroundTransparency = 1
nextLbl.Text                   = ""
nextLbl.TextColor3             = Color3.fromRGB(220, 220, 235)
nextLbl.TextScaled             = true
nextLbl.Font                   = Enum.Font.GothamBold
nextLbl.Parent                 = bg

-- ── Reward (ProgressionManager → RewardGranted) ──────────────────────────────
local rewardFrame = Instance.new("Frame")
rewardFrame.Name              = "Reward"
rewardFrame.Size              = UDim2.new(0, 360, 0, 132)
rewardFrame.Position          = UDim2.new(0.5, -180, 0.12, 0)
rewardFrame.BackgroundColor3  = Color3.fromRGB(30, 26, 50)
rewardFrame.BackgroundTransparency = 0.2
rewardFrame.BorderSizePixel   = 0
rewardFrame.Visible           = false
rewardFrame.Parent            = bg
local rewardCorner = Instance.new("UICorner")
rewardCorner.CornerRadius = UDim.new(0, 8)
rewardCorner.Parent       = rewardFrame

local function _rewardLabel(name, y, h, font, color)
	local l = Instance.new("TextLabel")
	l.Name                   = name
	l.Size                   = UDim2.new(1, -16, 0, h)
	l.Position               = UDim2.new(0, 8, 0, y)
	l.BackgroundTransparency = 1
	l.TextScaled             = true
	l.Font                   = font
	l.TextColor3             = color
	l.Text                   = ""
	l.Parent                 = rewardFrame
	return l
end
local gainLbl  = _rewardLabel("Gain", 4, 26, Enum.Font.GothamBlack, Color3.fromRGB(255, 220, 60))
local dailyLbl = _rewardLabel("Daily", 31, 16, Enum.Font.GothamBold, Color3.fromRGB(140, 230, 140))
local levelLbl = _rewardLabel("Level", 50, 16, Enum.Font.GothamBold, Color3.new(1, 1, 1))

local xpBar = Instance.new("Frame")
xpBar.Name             = "XpBar"
xpBar.Size             = UDim2.new(1, -16, 0, 10)
xpBar.Position         = UDim2.new(0, 8, 0, 72)
xpBar.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
xpBar.BorderSizePixel  = 0
xpBar.Parent           = rewardFrame
local xpFill = Instance.new("Frame")
xpFill.Name             = "Fill"
xpFill.Size             = UDim2.fromScale(0, 1)
xpFill.BackgroundColor3 = Color3.fromRGB(90, 180, 255)
xpFill.BorderSizePixel  = 0
xpFill.Parent           = xpBar

-- What the coins just earned can buy (Cosmetics.suggest on the shop state),
-- with a button straight to it: the moment after a race is when a player
-- wants to spend.
local buyLbl = _rewardLabel("Suggest", 92, 18, Enum.Font.GothamBold, Color3.fromRGB(255, 220, 60))
buyLbl.Size = UDim2.new(1, -116, 0, 18)
buyLbl.Position = UDim2.new(0, 8, 0, 100)
buyLbl.TextXAlignment = Enum.TextXAlignment.Left
local shopBtn = Instance.new("TextButton")
shopBtn.Name             = "Shop"
shopBtn.Size             = UDim2.new(0, 96, 0, 30)
shopBtn.Position         = UDim2.new(1, -104, 0, 94)
shopBtn.BackgroundColor3 = Color3.fromRGB(230, 160, 30)
shopBtn.Text             = "SHOP"
shopBtn.TextColor3       = Color3.new(1, 1, 1)
shopBtn.TextScaled       = true
shopBtn.Font             = Enum.Font.GothamBlack
shopBtn.Parent           = rewardFrame
local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 6)
shopCorner.Parent       = shopBtn
local _suggestTab = nil
shopBtn.Activated:Connect(function()
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		-- the ScreenGui, not the LocalScript of the same name next to it
		local open = g.Name == "ShopUI" and g:IsA("ScreenGui") and g:FindFirstChild("Open")
		if open then open:Fire(_suggestTab) end
	end
end)

local function _showSuggestion()
	buyLbl.Text = "New looks in the SHOP"
	_suggestTab = nil
	local ok, res = pcall(function() return RemoteEvents.ShopAction:InvokeServer("state") end)
	local tip = ok and type(res) == "table" and res.state and Cosmetics.suggest(res.state)
	if not tip then return end
	_suggestTab = tip.item.category
	buyLbl.Text = tip.affordable
		and string.format("You can buy %s now!", tip.item.name)
		or string.format("%s: %d more coins", tip.item.name, tip.short)
end

local function _showReward(r)
	if type(r) ~= "table" then return end
	gainLbl.Text = string.format("+%d XP    +%d Coins", r.xp or 0, (r.coins or 0) + (r.daily or 0))
	if (r.daily or 0) > 0 then
		dailyLbl.Text = (r.streak or 1) > 1
			and string.format("Daily bonus +%d  ·  %d-day streak", r.daily, r.streak)
			or  string.format("Daily bonus +%d  ·  come back tomorrow for more", r.daily)
	else
		dailyLbl.Text = r.saved == false and "Progress is not saved in this session" or ""
	end
	levelLbl.Text = string.format("%sLevel %d  ·  %d / %d XP  ·  %d Coins",
		(r.levelsGained or 0) > 0 and "LEVEL UP!  " or "", r.level or 1, r.xpInLevel or 0, r.xpToNext or 1, r.totalCoins or 0)
	levelLbl.TextColor3 = (r.levelsGained or 0) > 0 and Color3.fromRGB(255, 200, 80) or Color3.new(1, 1, 1)
	xpFill.Size = UDim2.fromScale(0, 1)
	rewardFrame.Visible = true
	task.spawn(_showSuggestion)
	TweenService:Create(xpFill, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(math.clamp((r.xpInLevel or 0) / math.max(1, r.xpToNext or 1), 0, 1), 1),
	}):Play()
end

-- ─── Populate results ─────────────────────────────────────────────────────────

local function _formatTime(seconds)
	if type(seconds) ~= "number" then return "DNF" end   -- did not finish in time
	return string.format("%d:%05.2f", math.floor(seconds / 60), seconds % 60)
end

local function _populateResults(finishOrder)
	-- Clear leaderboard rows
	for _, child in ipairs(lbFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for rank, entry in ipairs(finishOrder) do
		local player = Players:GetPlayerByUserId(entry.userId)
		local name   = player and player.Name or (entry.bot and ("🤖 " .. tostring(entry.name))) or entry.name or ("User" .. entry.userId)
		local timeStr = _formatTime(entry.time)

		-- Podium (top 3)
		if rank <= 3 and _podiumLabels[rank] then
			_podiumLabels[rank].name.Text = name
			_podiumLabels[rank].time.Text = timeStr
		end

		-- Leaderboard row
		local row = Instance.new("Frame")
		row.Name              = "Row" .. rank
		row.Size              = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = (entry.userId == LocalPlayer.UserId) and 0.5 or 1
		row.BackgroundColor3  = Color3.fromRGB(60, 80, 100)
		row.BorderSizePixel   = 0
		row.LayoutOrder       = rank
		row.Parent            = lbFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent       = row

		local rowLbl = Instance.new("TextLabel")
		rowLbl.Size            = UDim2.fromScale(1, 1)
		rowLbl.BackgroundTransparency = 1
		rowLbl.Text            = string.format("#%d  %s  —  %s", rank, name, timeStr)
		rowLbl.TextColor3      = (entry.userId == LocalPlayer.UserId)
			and Color3.fromRGB(255, 220, 60)
			or  Color3.new(1, 1, 1)
		rowLbl.TextScaled      = true
		rowLbl.Font            = (rank <= 3) and Enum.Font.GothamBold or Enum.Font.Gotham
		rowLbl.TextXAlignment  = Enum.TextXAlignment.Left
		rowLbl.Parent          = row

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 6)
		rowPad.Parent      = rowLbl
	end
end

-- ─── Animate in ───────────────────────────────────────────────────────────────

local function _animateIn()
	bg.BackgroundTransparency = 1
	screen.Enabled = true
	TweenService:Create(bg, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0.1
	}):Play()
end

-- ─── Next-round clock ───────────────────────────────────────────────────────

game:GetService("RunService").Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local left = PhaseClock.remaining(nil)
	nextLbl.Text = left and ("Next round in " .. PhaseClock.format(left) .. "   ·   SHOP is open") or ""
end)

-- ─── Remote listeners ────────────────────────────────────────────────────────

RemoteEvents.RaceFinished.OnClientEvent:Connect(function(finishOrder)
	_populateResults(finishOrder)
end)

RemoteEvents.RewardGranted.OnClientEvent:Connect(_showReward)

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.RESULTS then
		_animateIn()
	elseif phase == Constants.PHASES.LOBBY then
		screen.Enabled = false
		rewardFrame.Visible = false
	end
end)
