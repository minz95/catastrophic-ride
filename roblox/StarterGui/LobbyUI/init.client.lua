-- LobbyUI/init.client.lua
-- The lobby's heads-up display. The lobby itself is Junk Town, a plaza
-- players walk around (2026-11-17: "explore, chat, see the hall of fame,
-- shop, like a Roblox room"; LobbyManager, Modules/Maps/LobbyHub): the
-- hall of fame stage, Legend Rides, the trophy room, the shop booth, the
-- townsfolk to talk to. This screen only adds what the plaza cannot say:
-- the next track spinning like a roulette until it is drawn, the countdown
-- to the round, who is here and INVITE FRIENDS. Nothing covers the world.
--
-- With two places (Shared/Places): in the hub there is no round to count
-- down to; the pill says to step on a start pad (and counts down once you
-- are on one: player attributes DepartPad / DepartAt), ▶ PLAY puts you on
-- the race pad. In the race place ← JUNK TOWN goes back to the hub.
--
-- History: 2026-11-12 a dark panel saying "waiting" (players left within a
-- second) became a bright full-screen card with a line-up of junk rides;
-- 2026-11-17 the card gave way to the plaza.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local Departure    = require(ReplicatedStorage.Shared.Departure)
local Notice       = require(ReplicatedStorage.Shared.Notice)
local LocalPlayer  = Players.LocalPlayer

local WHITE  = Color3.new(1, 1, 1)
local INK    = Color3.fromRGB(24, 20, 48)
local HINT   = "Explore Junk Town: 🏆 hall of fame · 🚗 Legend Rides · 🛒 shop · talk to the locals"
local HUB_HINT = "🏁 Step on a pad to race · 🏆 hall of fame · 🚗 Legend Rides · 🛒 shop · talk to the locals"
local BIOMES = {
	{ key = "FOREST", text = "🌲 FOREST", color = Color3.fromRGB(70, 170, 70) },
	{ key = "OCEAN",  text = "🌊 OCEAN",  color = Color3.fromRGB(40, 120, 230) },
	{ key = "SKY",    text = "☁️ SKY",    color = Color3.fromRGB(140, 90, 230) },
}
local ROULETTE_STEP = 0.12   -- s per biome while the draw is open

-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "LobbyUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local function phaseIsLobby()
	local p = ReplicatedStorage:GetAttribute("Phase")
	return p == nil or p == Constants.PHASES.LOBBY
end

local screen = Instance.new("ScreenGui")
screen.Name           = "LobbyUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = phaseIsLobby()
screen.Parent         = LocalPlayer.PlayerGui

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

-- ── Countdown (top centre) ───────────────────────────────────────────────────
local countPill = Instance.new("Frame")
countPill.Name             = "Countdown"
countPill.AnchorPoint      = Vector2.new(0.5, 0)
countPill.BackgroundColor3 = INK
countPill.BackgroundTransparency = 0.15
countPill.BorderSizePixel  = 0
countPill.ClipsDescendants = true
countPill.Parent           = screen
corner(countPill, 14)
local countFill = Instance.new("Frame")
countFill.Name             = "Fill"
countFill.Size             = UDim2.fromScale(0, 1)
countFill.BackgroundColor3 = Color3.fromRGB(70, 200, 100)
countFill.BorderSizePixel  = 0
countFill.Parent           = countPill
corner(countFill, 14)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name                   = "Status"
statusLabel.Size                   = UDim2.new(1, -20, 1, -8)
statusLabel.Position               = UDim2.new(0, 10, 0, 4)
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = "GET READY!"
statusLabel.TextColor3             = WHITE
statusLabel.TextScaled             = true
statusLabel.Font                   = Enum.Font.GothamBlack
statusLabel.ZIndex                 = 2
statusLabel.Parent                 = countPill
stroke(statusLabel, 2)

-- ── Next track: a roulette until the server draws it ─────────────────────────
local biomePill = Instance.new("Frame")
biomePill.Name             = "BiomePill"
biomePill.AnchorPoint      = Vector2.new(0.5, 0)
biomePill.BackgroundColor3 = BIOMES[1].color
biomePill.BorderSizePixel  = 0
biomePill.Parent           = screen
corner(biomePill, 12)
stroke(biomePill, 3, WHITE)
local biomeLabel = Instance.new("TextLabel")
biomeLabel.Name                   = "BiomeLabel"
biomeLabel.Size                   = UDim2.new(1, -16, 1, -6)
biomeLabel.Position               = UDim2.new(0, 8, 0, 3)
biomeLabel.BackgroundTransparency = 1
biomeLabel.Text                   = "NEXT TRACK: " .. BIOMES[1].text
biomeLabel.TextColor3             = WHITE
biomeLabel.TextScaled             = true
biomeLabel.Font                   = Enum.Font.GothamBlack
biomeLabel.Parent                 = biomePill
stroke(biomeLabel, 2)

local _drawn, _rollAt, _rollI = nil, 0, 1

local function placeMode()
	return ReplicatedStorage:GetAttribute("PlaceMode") or "single"
end

-- ── Travel (two places): ▶ PLAY in the hub, ← JUNK TOWN in the race place ───
local travelBtn = Instance.new("TextButton")
travelBtn.Name             = "Travel"
travelBtn.AnchorPoint      = Vector2.new(0.5, 0)
travelBtn.BackgroundColor3 = Color3.fromRGB(70, 200, 100)
travelBtn.BorderSizePixel  = 0
travelBtn.Text             = "▶ PLAY"
travelBtn.TextColor3       = WHITE
travelBtn.TextScaled       = true
travelBtn.Font             = Enum.Font.GothamBlack
travelBtn.Visible          = false
travelBtn.Parent           = screen
corner(travelBtn, 12)
stroke(travelBtn, 3, WHITE)
local _going = nil   -- text while a teleport loads
travelBtn.Activated:Connect(function()
	local action = placeMode() == "hub" and "play" or "hub"
	local ok, res = pcall(function() return RemoteEvents.PlaceAction:InvokeServer(action) end)
	if ok and res == "ok" and action == "hub" then _going = "OFF TO JUNK TOWN…" end
end)
RemoteEvents.TravelUpdate.OnClientEvent:Connect(function(m)
	if type(m) ~= "table" then return end
	if m.kind == "leaving" then
		_going = placeMode() == "hub" and "OFF TO THE RACE!" or "OFF TO JUNK TOWN…"
	elseif m.kind == "failed" then
		_going = nil
		Notice.show("Couldn't travel", tostring(m.text or ""))
	end
end)

-- ── What there is to do (bottom centre, small) ───────────────────────────────
local hint = Instance.new("TextLabel")
hint.Name                   = "Hint"
hint.AnchorPoint            = Vector2.new(0.5, 1)
hint.BackgroundColor3       = INK
hint.BackgroundTransparency = 0.4
hint.Text                   = HINT
hint.TextColor3             = WHITE
hint.TextScaled             = true
hint.Font                   = Enum.Font.GothamBold
hint.Parent                 = screen
corner(hint, 8)
local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft, hintPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
hintPad.Parent = hint

-- ── Players + invite (top right, compact) ────────────────────────────────────
local listFrame = Instance.new("Frame")
listFrame.Name             = "PlayerList"
listFrame.AnchorPoint      = Vector2.new(1, 0)
listFrame.BackgroundColor3 = INK
listFrame.BackgroundTransparency = 0.35
listFrame.BorderSizePixel  = 0
listFrame.Parent           = screen
corner(listFrame, 10)

local listTitle = Instance.new("TextLabel")
listTitle.Name                   = "ListTitle"
listTitle.Size                   = UDim2.new(1, -12, 0, 22)
listTitle.Position               = UDim2.new(0, 6, 0, 4)
listTitle.BackgroundTransparency = 1
listTitle.TextColor3             = Color3.fromRGB(220, 220, 255)
listTitle.TextScaled             = true
listTitle.Font                   = Enum.Font.GothamBold
listTitle.TextXAlignment         = Enum.TextXAlignment.Left
listTitle.Parent                 = listFrame

local INVITE_H = 34
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name                = "Scroll"
scrollFrame.Size                = UDim2.new(1, -10, 1, -30 - INVITE_H - 12)
scrollFrame.Position            = UDim2.new(0, 5, 0, 28)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel     = 0
scrollFrame.ScrollBarThickness  = 3
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize          = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent              = listFrame
local scrollLayout = Instance.new("UIListLayout")
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Padding   = UDim.new(0, 3)
scrollLayout.Parent    = scrollFrame

-- Invite friends (Shared/Invite), at the foot of the player list
require(ReplicatedStorage.Shared.Invite).button(listFrame,
	UDim2.new(0, 6, 1, -INVITE_H - 6), UDim2.new(1, -12, 0, INVITE_H), true)

local function _buildPlayerList()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	listTitle.Text = placeMode() == "hub" and string.format("In town: %d", #Players:GetPlayers())
		or string.format("Players %d / %d", #Players:GetPlayers(), Constants.MAX_PLAYERS)
	for i, player in ipairs(Players:GetPlayers()) do
		local row = Instance.new("TextLabel")
		row.Name                   = "Row_" .. player.UserId
		row.Size                   = UDim2.new(1, 0, 0, 20)
		row.BackgroundColor3       = (player == LocalPlayer) and Color3.fromRGB(80, 100, 150) or Color3.fromRGB(45, 45, 75)
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel        = 0
		row.LayoutOrder            = (player == LocalPlayer) and 0 or i
		row.Text                   = (player == LocalPlayer and "⭐ " or "") .. player.DisplayName
		row.TextColor3             = WHITE
		row.TextScaled             = true
		row.Font                   = Enum.Font.GothamBold
		row.TextXAlignment         = Enum.TextXAlignment.Left
		row.Parent                 = scrollFrame
		corner(row, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.Parent = row
	end
end
Players.PlayerAdded:Connect(_buildPlayerList)
Players.PlayerRemoving:Connect(function() task.defer(_buildPlayerList) end)
_buildPlayerList()

-- ── Layout: from the screen's size (phones are ~400 px tall) ────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function layout()
	local w, h = screen.AbsoluteSize.X, screen.AbsoluteSize.Y
	if w < 10 or h < 10 then return end
	local inset = GuiService.TopbarInset.Height
	local small = h < 520
	local top = inset + 8
	local countH = clamp(h * 0.07, 30, 48)
	local countW = math.min(w * 0.36, 380)
	countPill.Size, countPill.Position = UDim2.new(0, countW, 0, countH), UDim2.new(0.5, 0, 0, top)
	local pillH = clamp(h * 0.05, 24, 36)
	biomePill.Size = UDim2.new(0, math.min(w * 0.3, pillH * 8), 0, pillH)
	biomePill.Position = UDim2.new(0.5, 0, 0, top + countH + 6)
	local hintH = clamp(h * 0.035, 16, 24)
	hint.Size = UDim2.new(0, math.min(w * 0.7, hintH * 34), 0, hintH)
	hint.Position = UDim2.new(0.5, 0, 1, -10)
	hint.Visible = not small   -- phones: the plaza's own signs say it
	local listW = small and 140 or 180
	listFrame.Size = UDim2.new(0, listW, 0, clamp(h * 0.4, 150, 300))
	listFrame.Position = UDim2.new(1, -12, 0, top)
	local mode = placeMode()
	travelBtn.Visible = mode == "hub" or mode == "race"
	biomePill.Visible = mode ~= "hub"
	hint.Text = mode == "hub" and HUB_HINT or HINT
	if mode == "hub" then
		travelBtn.Text = "▶ PLAY"
		travelBtn.BackgroundColor3 = Color3.fromRGB(70, 200, 100)
		travelBtn.AnchorPoint = Vector2.new(0.5, 0)
		travelBtn.Size = UDim2.new(0, math.min(w * 0.3, 220), 0, clamp(h * 0.07, 34, 52))
		travelBtn.Position = UDim2.new(0.5, 0, 0, top + countH + 8)
	else
		travelBtn.Text = "← JUNK TOWN"
		travelBtn.BackgroundColor3 = Color3.fromRGB(120, 140, 255)
		travelBtn.AnchorPoint = Vector2.new(1, 0)
		travelBtn.Size = UDim2.new(0, listW, 0, 34)
		travelBtn.Position = UDim2.new(1, -12, 0, top + listFrame.Size.Y.Offset + 8)
	end
end
ReplicatedStorage:GetAttributeChangedSignal("PlaceMode"):Connect(function()
	layout()
	_buildPlayerList()
end)
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- ── Every frame: the countdown, the roulette ────────────────────────────────
local _longest = nil   -- the countdown's start (for the bar)
RunService.Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local left = PhaseClock.remaining(nil)
	if _going then
		statusLabel.Text = _going
		countFill.Size = UDim2.fromScale(1, 1)
		return
	end
	if placeMode() == "hub" then
		-- no round here: step on a start pad (DepartureManager counts down)
		local pad = Departure.pad(LocalPlayer:GetAttribute("DepartPad") or "")
		local at = LocalPlayer:GetAttribute("DepartAt")
		if pad and at then
			local l = math.max(0, at - workspace:GetServerTimeNow())
			statusLabel.Text = string.format("LEAVING IN %d", math.ceil(l))
			countFill.Size = UDim2.fromScale(1 - l / Constants.DEPART.SECONDS, 1)
		else
			statusLabel.Text = "STEP ON A 🏁 PAD TO RACE"
			countFill.Size = UDim2.fromScale(0, 1)
		end
		return
	end
	if left and left > 0 then
		_longest = math.max(_longest or 0, left)
		statusLabel.Text = string.format("RACE STARTS IN %d", math.ceil(left))
		countFill.Size = UDim2.fromScale(1 - left / math.max(_longest, 1), 1)
	else
		statusLabel.Text = "GET READY!"
		countFill.Size = UDim2.fromScale(0, 1)
	end
	if not _drawn and os.clock() - _rollAt >= ROULETTE_STEP then
		_rollAt = os.clock()
		_rollI = _rollI % #BIOMES + 1
		local b = BIOMES[_rollI]
		biomeLabel.Text = "NEXT TRACK: " .. b.text
		biomePill.BackgroundColor3 = b.color
	end
end)

-- ── The draw lands ──────────────────────────────────────────────────────────
RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	for _, b in ipairs(BIOMES) do
		if b.key == biome then
			_drawn = biome
			biomeLabel.Text = "NEXT TRACK: " .. b.text
			biomePill.BackgroundColor3 = b.color
			local size = biomePill.Size
			TweenService:Create(biomePill, TweenInfo.new(0.15), {
				Size = UDim2.new(size.X.Scale, size.X.Offset * 1.12, size.Y.Scale, size.Y.Offset * 1.12),
			}):Play()
			task.delay(0.15, function()
				TweenService:Create(biomePill, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = size }):Play()
			end)
		end
	end
end)

-- ─── Phase handling ───────────────────────────────────────────────────────────
RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.LOBBY then
		if not screen.Enabled then
			_drawn, _longest = nil, nil   -- a new round: roll again
		end
		screen.Enabled = true
		_buildPlayerList()
	else
		screen.Enabled = false
	end
end)
