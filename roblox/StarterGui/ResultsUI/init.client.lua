-- ResultsUI/init.client.lua
-- Post-race podium, time display, Play Again vote.
-- Resolves: Issue #44

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Constants    = require(ReplicatedStorage.Shared.Constants)
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
local playAgainBtn = Instance.new("TextButton")
playAgainBtn.Name           = "PlayAgain"
playAgainBtn.Size           = UDim2.new(0, 200, 0, 50)
playAgainBtn.Position       = UDim2.new(0.5, -100, 0.9, 0)
playAgainBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
playAgainBtn.BorderSizePixel = 0
playAgainBtn.Text           = "PLAY AGAIN"
playAgainBtn.TextColor3     = Color3.new(1, 1, 1)
playAgainBtn.TextScaled     = true
playAgainBtn.Font           = Enum.Font.GothamBold
playAgainBtn.Parent         = bg

local playAgainCorner = Instance.new("UICorner")
playAgainCorner.CornerRadius = UDim.new(0, 10)
playAgainCorner.Parent       = playAgainBtn

local voteLabel = Instance.new("TextLabel")
voteLabel.Name              = "VoteLabel"
voteLabel.Size              = UDim2.new(0, 200, 0, 20)
voteLabel.Position          = UDim2.new(0.5, -100, 0.95, 0)
voteLabel.BackgroundTransparency = 1
voteLabel.Text              = "Votes: 0 / 0"
voteLabel.TextColor3        = Color3.fromRGB(180, 180, 180)
voteLabel.TextScaled        = true
voteLabel.Font              = Enum.Font.Gotham
voteLabel.Parent            = bg

-- ─── Populate results ─────────────────────────────────────────────────────────

local function _formatTime(seconds)
	return string.format("%d:%05.2f", math.floor(seconds / 60), seconds % 60)
end

local function _populateResults(finishOrder)
	-- Clear leaderboard rows
	for _, child in ipairs(lbFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for rank, entry in ipairs(finishOrder) do
		local player = Players:GetPlayerByUserId(entry.userId)
		local name   = player and player.Name or ("User" .. entry.userId)
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

-- ─── Vote state ───────────────────────────────────────────────────────────────

local _myVote = false
local _voteCount = 0
local _totalPlayers = 0

playAgainBtn.Activated:Connect(function()
	if _myVote then return end
	_myVote = true
	_voteCount = _voteCount + 1
	playAgainBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
	playAgainBtn.Text = "✓ VOTED"
	voteLabel.Text = string.format("Votes: %d / %d", _voteCount, _totalPlayers)
	-- Fire to server (RemoteEvent not defined yet; placeholder)
	-- RemoteEvents.VotePlayAgain:FireServer()
end)

-- ─── Remote listeners ────────────────────────────────────────────────────────

RemoteEvents.RaceFinished.OnClientEvent:Connect(function(finishOrder)
	_totalPlayers = #finishOrder
	_populateResults(finishOrder)
end)

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.RESULTS then
		_animateIn()
	elseif phase == Constants.PHASES.LOBBY then
		screen.Enabled = false
		_myVote = false
		_voteCount = 0
	end
end)
