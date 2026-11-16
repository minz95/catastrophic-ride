-- RideShowUI
-- The ride show (server: RideShowManager): when RESULTS opens with two or
-- more players who raced, their rides stand side by side over the results
-- for RIDE_SHOW.SECONDS. Each card: the ride with its driver, the items,
-- the grade and the four bars (Shared/RideRating: compare yours with your
-- friends'), and a vote button (not on your own). The winner gets a 🏆 and
-- coins; 📸 makes a "vs" picture of all of them to share (Shared/Snapshot).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local RideRating   = require(ReplicatedStorage.Shared.RideRating)
local RideCard     = require(ReplicatedStorage.Shared.RideCard)
local Snapshot     = require(ReplicatedStorage.Shared.Snapshot)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local LocalPlayer  = Players.LocalPlayer

-- ResetOnSpawn = false: this script runs again after a respawn
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "RideShowUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "RideShowUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.DisplayOrder   = 30     -- over the results screen
screen.Enabled        = false
screen.Parent         = LocalPlayer.PlayerGui

local GOLD = Color3.fromRGB(255, 210, 60)

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(14, 10, 30)
bg.BackgroundTransparency = 0.05
bg.BorderSizePixel = 0
bg.Parent = screen

-- a 1000 × 640 stage scaled to the screen, like the results screen
local STAGE_W, STAGE_H = 1000, 640
local stage = Instance.new("Frame")
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(STAGE_W, STAGE_H)
stage.BackgroundTransparency = 1
stage.Parent = bg
local scale = Instance.new("UIScale")
scale.Parent = stage
require(ReplicatedStorage.Shared.ScreenFit).watch(function()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(STAGE_W, STAGE_H)
	scale.Scale = math.min(vp.X / STAGE_W, vp.Y / STAGE_H)
end)

local function label(parent, text, size, pos, font, colour)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size, l.Position = size, pos
	l.Text = text
	l.Font = font or Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = colour or Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

local title = label(stage, "🤣 WHOSE RIDE IS THE FUNNIEST?", UDim2.new(1, -40, 0, 50), UDim2.new(0, 20, 0, 8), nil, GOLD)
local sub = label(stage, "", UDim2.new(1, -40, 0, 26), UDim2.new(0, 20, 0, 60), Enum.Font.GothamBold,
	Color3.fromRGB(220, 220, 240))

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(1, -40, 0, 470)
grid.Position = UDim2.new(0, 20, 0, 96)
grid.Parent = stage
local layout = Instance.new("UIGridLayout")
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.CellPadding = UDim2.fromOffset(12, 12)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

local _cards = {}       -- userId → { frame, votes, button }
local _entries = {}
local _endsAt = nil
local _myVote = nil
local _coins = Constants.RIDE_SHOW.COINS

local snapBtn = Snapshot.button(stage, UDim2.fromOffset(220, 46), UDim2.new(0.5, -110, 1, -62), "📸 SNAPSHOT", function()
	local rides = {}
	for _, e in ipairs(_entries) do
		local p = Players:GetPlayerByUserId(e.userId)
		table.insert(rides, { model = e.model, char = p and p.Character, name = e.name,
			items = RideCard.items(e.slots), grade = e.grade })
	end
	Snapshot.card(rides, #rides > 1 and "WHOSE RIDE IS FUNNIER?" or "MY JUNK RIDE")
end)

local function bar(parent, y, lab, value)
	label(parent, lab, UDim2.new(0.42, 0, 0, 14), UDim2.new(0, 0, 0, y), Enum.Font.GothamBold, Color3.fromRGB(190, 190, 210))
	local back = Instance.new("Frame")
	back.Size = UDim2.new(0.56, 0, 0, 8)
	back.Position = UDim2.new(0.44, 0, 0, y + 3)
	back.BackgroundColor3 = Color3.fromRGB(50, 50, 75)
	back.BorderSizePixel = 0
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(value or 0, 0.03, 1), 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	fill.BorderSizePixel = 0
	fill.Parent = back
end

local function vote(userId)
	if userId == LocalPlayer.UserId then return end
	_myVote = userId
	RemoteEvents.VoteRide:FireServer(userId)
	for id, c in pairs(_cards) do
		if c.button then
			c.button.Text = id == _myVote and "✅ VOTED" or "🤣 FUNNIEST"
			c.button.BackgroundColor3 = id == _myVote and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(230, 120, 40)
		end
	end
end

local function card(entry, i, n, biome)
	local f = Instance.new("Frame")
	f.LayoutOrder = i
	f.BackgroundColor3 = Color3.fromRGB(30, 28, 54)
	f.BorderSizePixel = 0
	f.Parent = grid
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = f
	local mine = entry.userId == LocalPlayer.UserId
	if mine then
		local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 3; st.Parent = f
	end
	local viewSlot = Instance.new("Frame")
	viewSlot.BackgroundTransparency = 1
	viewSlot.Size = UDim2.new(1, -12, 0.46, 0)
	viewSlot.Position = UDim2.new(0, 6, 0, 6)
	viewSlot.ClipsDescendants = true
	viewSlot.Parent = f
	local p = Players:GetPlayerByUserId(entry.userId)
	local view = RideCard.view(viewSlot, entry.model, p and p.Character)
	if view then local vc = Instance.new("UICorner"); vc.CornerRadius = UDim.new(0, 10); vc.Parent = view end
	local votes = label(viewSlot, "", UDim2.new(0.5, 0, 0, 24), UDim2.new(0.5, -6, 0, 4), nil, GOLD)
	votes.TextXAlignment = Enum.TextXAlignment.Right
	votes.ZIndex = 3
	local rating = RideRating.rate(entry.slots or {}, biome)
	entry.grade = rating.grade
	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -16, 0.54, -12)
	info.Position = UDim2.new(0, 8, 0.46, 10)
	info.Parent = f
	label(info, (mine and "YOU · " or "") .. entry.name, UDim2.new(1, -44, 0, 20), UDim2.new(0, 0, 0, 0))
	label(info, RideCard.items(entry.slots), UDim2.new(1, -44, 0, 16), UDim2.new(0, 0, 0, 22), Enum.Font.GothamBold,
		Color3.fromRGB(190, 200, 235))
	local g = label(info, rating.grade, UDim2.fromOffset(38, 38), UDim2.new(1, -38, 0, 0), nil, GOLD)
	g.BackgroundTransparency = 0
	g.BackgroundColor3 = Color3.fromRGB(44, 44, 70)
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 8); gc.Parent = g
	for k, b in ipairs(RideRating.BARS) do
		bar(info, 42 + (k - 1) * 17, b.label, rating.bars[b.key])
	end
	local button
	if mine then
		label(info, "YOUR RIDE", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -30), nil, GOLD)
	else
		button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 34)
		button.Position = UDim2.new(0, 0, 1, -34)
		button.BackgroundColor3 = Color3.fromRGB(230, 120, 40)
		button.Text = "🤣 FUNNIEST"
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextScaled = true
		button.Font = Enum.Font.GothamBlack
		button.Parent = info
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = button
		button.Activated:Connect(function() vote(entry.userId) end)
	end
	_cards[entry.userId] = { frame = f, votes = votes, button = button }
end

local function open(data)
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	_cards, _myVote = {}, nil
	_entries = data.entries or {}
	_endsAt = data.endsAt
	_coins = data.coins or _coins
	local n = #_entries
	-- one row up to five rides, two rows above
	local perRow = n <= 5 and n or math.ceil(n / 2)
	local rows = n <= 5 and 1 or 2
	local w = math.min(230, (960 - (perRow - 1) * 12) / perRow)
	local h = rows == 1 and 440 or 225
	layout.CellSize = UDim2.fromOffset(w, h)
	local biome = ReplicatedStorage:GetAttribute("Biome") or "FOREST"
	for i, e in ipairs(_entries) do card(e, i, n, biome) end
	title.Text = "🤣 WHOSE RIDE IS THE FUNNIEST?"
	screen.Enabled = true
end

local function counts(list)
	local by = {}
	for _, e in ipairs(type(list) == "table" and list or {}) do by[e.userId] = e.votes end
	for id, card in pairs(_cards) do
		local v = by[id] or 0
		card.votes.Text = v > 0 and ("🤣 " .. v) or ""
	end
end

local function closed(data)
	counts(data.counts)
	for _, c in pairs(_cards) do if c.button then c.button.Visible = false end end
	local names = {}
	for _, id in ipairs(data.winners or {}) do
		local c = _cards[id]
		if c then
			local st = c.frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			st.Color, st.Thickness, st.Parent = GOLD, 5, c.frame
			label(c.frame, "🏆 FUNNIEST RIDE", UDim2.new(1, -12, 0, 30), UDim2.new(0, 6, 0, -14), nil, GOLD).ZIndex = 4
		end
		for _, e in ipairs(_entries) do if e.userId == id then table.insert(names, e.name) end end
	end
	_endsAt = nil
	title.Text = #names > 0 and ("🏆 " .. table.concat(names, " & ") .. " wins!") or "No votes this time"
	sub.Text = #names > 0 and string.format("+%d coins  ·  📸 for a picture", data.coins or _coins) or ""
	task.delay(Constants.RIDE_SHOW.WINNER_SHOWN, function() screen.Enabled = false end)
end

RemoteEvents.RideShow.OnClientEvent:Connect(function(kind, data)
	data = type(data) == "table" and data or {}
	if kind == "open" then open(data)
	elseif kind == "votes" then counts(data.counts)
	elseif kind == "closed" then closed(data) end
end)

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase ~= Constants.PHASES.RESULTS then screen.Enabled = false end
end)

-- A harness bot client votes like a press (BotDriver sets RideVoteFor).
LocalPlayer:GetAttributeChangedSignal("RideVoteFor"):Connect(function()
	local id = LocalPlayer:GetAttribute("RideVoteFor")
	if type(id) == "number" and _cards[id] then vote(id) end
end)

game:GetService("RunService").Heartbeat:Connect(function()
	if not screen.Enabled or not _endsAt then return end
	local left = _endsAt - workspace:GetServerTimeNow()
	sub.Text = string.format("Vote for a friend's ride (not your own)  ·  winner gets %d coins  ·  %s",
		_coins, PhaseClock.format(math.max(0, left)))
end)

snapBtn.ZIndex = 2
