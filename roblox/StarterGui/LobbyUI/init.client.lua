-- LobbyUI/init.client.lua
-- The first screen a player sees: the game's name, what you do in it, a
-- line-up of junk rides turning (your own avatar on the middle one), the
-- next track spinning like a roulette until it is drawn, and a big
-- countdown to the round. Players and INVITE FRIENDS on the side.
--
-- History (2026-11-12): it was a dark panel over the world with an empty
-- player list, "Biome: ?" and a line saying it waits for players (the solo lobby starts
-- by itself after 8 s): nothing said "this looks fun" and new players left
-- within a second.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local SeatedCopy   = require(ReplicatedStorage.Shared.SeatedCopy)
local LocalPlayer  = Players.LocalPlayer

local GOLD   = Color3.fromRGB(255, 214, 60)
local WHITE  = Color3.new(1, 1, 1)
local INK    = Color3.fromRGB(24, 20, 48)
local TAGLINE = "🛒 GRAB JUNK  →  🔧 BUILD A RIDE  →  🏁 RACE!"
local BIOMES = {
	{ key = "FOREST", text = "🌲 FOREST", color = Color3.fromRGB(70, 170, 70) },
	{ key = "OCEAN",  text = "🌊 OCEAN",  color = Color3.fromRGB(40, 120, 230) },
	{ key = "SKY",    text = "☁️ SKY",    color = Color3.fromRGB(140, 90, 230) },
}
local ROULETTE_STEP = 0.12   -- s per biome while the draw is open
local SPIN_STEP = 1 / 20     -- the line-up redraws 20 times a second (phones)

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

-- ── Backdrop: bright, not a dark veil ────────────────────────────────────────
local bg = Instance.new("Frame")
bg.Name             = "Background"
bg.Size             = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = WHITE
bg.BackgroundTransparency = 0.08
bg.BorderSizePixel  = 0
bg.Parent           = screen
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 120, 235)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 80, 220)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 90, 150)),
})
grad.Rotation = 90
grad.Parent = bg

-- ── Title and what you do ────────────────────────────────────────────────────
local title = Instance.new("TextLabel")
title.Name                   = "Title"
title.AnchorPoint            = Vector2.new(0.5, 0)
title.BackgroundTransparency = 1
title.Text                   = "CATASTROPHIC RIDE"
title.TextColor3             = GOLD
title.TextScaled             = true
title.Font                   = Enum.Font.GothamBlack
title.Parent                 = bg
stroke(title, 3)

local tagline = Instance.new("TextLabel")
tagline.Name                   = "Tagline"
tagline.AnchorPoint            = Vector2.new(0.5, 0)
tagline.BackgroundTransparency = 1
tagline.Text                   = TAGLINE
tagline.TextColor3             = WHITE
tagline.TextScaled             = true
tagline.Font                   = Enum.Font.GothamBlack
tagline.Parent                 = bg
stroke(tagline, 2)

-- ── The line-up (server: Modules/ShopPreview.buildShowcase) ─────────────────
local view = Instance.new("ViewportFrame")
view.Name                   = "Showcase"
view.AnchorPoint            = Vector2.new(0.5, 0)
view.BackgroundTransparency = 1
view.Ambient                = Color3.fromRGB(170, 170, 185)
view.LightColor             = Color3.fromRGB(255, 250, 240)
view.LightDirection         = Vector3.new(-1, -2, -0.8)
view.Parent                 = bg
local viewCam = Instance.new("Camera")
viewCam.FieldOfView = 34
viewCam.Parent = view
view.CurrentCamera = viewCam

local _world, _turning = nil, {}   -- _turning: { { group, pivot } }

local function seatMe(group, vehicle)
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	local char = LocalPlayer.Character
	if not seat or not char or not char:FindFirstChild("Head") then return end
	local old = group:FindFirstChild("Me")
	if old then old:Destroy() end
	local rider = SeatedCopy.rider(seat, group, char)
	if rider then
		rider.Name = "Me"
		pcall(SeatedCopy.wearHat, vehicle, rider)
	end
end

local function buildLineup()
	local folder = ReplicatedStorage:FindFirstChild("LobbyShowcase")
	if not folder then return false end
	if _world then _world:Destroy() end
	_turning = {}
	local world = Instance.new("WorldModel")   -- lets the avatar's joints pose
	world.Parent = view
	_world = world
	-- OCEAN left, FOREST (with you on it) in the middle, SKY right
	local order = { "2_OCEAN", "1_FOREST", "3_SKY" }
	local copies, widths = {}, {}
	for k, name in ipairs(order) do
		local src = folder:FindFirstChild(name)
		if src then
			local group = Instance.new("Model")
			group.Name = name
			local copy = src:Clone()
			copy.Parent = group
			if k == 2 then pcall(seatMe, group, copy) end
			group.Parent = world
			local _, size = group:GetBoundingBox()
			table.insert(copies, group)
			table.insert(widths, math.max(size.X, size.Z))
		end
	end
	if #copies == 0 then return false end
	local gap, total = 2, 0
	for _, w in ipairs(widths) do total += w end
	total += gap * (#widths - 1)
	local x = -total / 2
	local top = 0
	for i, group in ipairs(copies) do
		local cf, size = group:GetBoundingBox()
		local at = Vector3.new(x + widths[i] / 2, size.Y / 2, 0)
		group:TranslateBy(at - cf.Position)   -- its box centred on `at`, standing on Y 0
		group.WorldPivot = CFrame.new(at)
		top = math.max(top, size.Y)
		table.insert(_turning, { group = group, at = at, phase = i * 1.3 })
		x += widths[i] + gap
	end
	-- frame them all: the width decides (the view is wide)
	local aspect = math.max(view.AbsoluteSize.X, 1) / math.max(view.AbsoluteSize.Y, 1)
	local halfH = math.rad(viewCam.FieldOfView / 2)
	local halfW = math.atan(math.tan(halfH) * aspect)
	local dist = math.max((total / 2 + 1) / math.tan(halfW), (top / 2 + 1.5) / math.tan(halfH)) + 4
	local centre = Vector3.new(0, top * 0.42, 0)
	viewCam.CFrame = CFrame.lookAt(centre + Vector3.new(0, dist * 0.32, dist), centre)
	return true
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("LobbyShowcase", 60)
	if folder then pcall(buildLineup) end
end)
LocalPlayer.CharacterAdded:Connect(function(char)
	char:WaitForChild("Head", 10)
	task.wait(1)   -- accessories and clothes
	if screen.Enabled then pcall(buildLineup) end
end)

local _spinAt = 0
RunService.RenderStepped:Connect(function()
	if not screen.Enabled or #_turning == 0 then return end
	local t = os.clock()
	if t - _spinAt < SPIN_STEP then return end
	_spinAt = t
	for _, sp in ipairs(_turning) do
		if sp.group.Parent then
			sp.group:PivotTo(CFrame.new(sp.at) * CFrame.Angles(0, t * 0.7 + sp.phase, 0))
		end
	end
end)

-- ── Next track: a roulette until the server draws it ─────────────────────────
local biomePill = Instance.new("Frame")
biomePill.Name             = "BiomePill"
biomePill.AnchorPoint      = Vector2.new(0.5, 0)
biomePill.BackgroundColor3 = BIOMES[1].color
biomePill.BorderSizePixel  = 0
biomePill.Parent           = bg
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

-- ── Countdown ───────────────────────────────────────────────────────────────
local countPill = Instance.new("Frame")
countPill.Name             = "Countdown"
countPill.AnchorPoint      = Vector2.new(0.5, 0)
countPill.BackgroundColor3 = INK
countPill.BackgroundTransparency = 0.15
countPill.BorderSizePixel  = 0
countPill.ClipsDescendants = true
countPill.Parent           = bg
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

-- ── Players + invite, on the side ───────────────────────────────────────────
local listFrame = Instance.new("Frame")
listFrame.Name             = "PlayerList"
listFrame.AnchorPoint      = Vector2.new(1, 0)
listFrame.BackgroundColor3 = INK
listFrame.BackgroundTransparency = 0.35
listFrame.BorderSizePixel  = 0
listFrame.Parent           = bg
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

local INVITE_H = 38
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
	listTitle.Text = string.format("Players %d / %d", #Players:GetPlayers(), Constants.MAX_PLAYERS)
	for i, player in ipairs(Players:GetPlayers()) do
		local row = Instance.new("TextLabel")
		row.Name                   = "Row_" .. player.UserId
		row.Size                   = UDim2.new(1, 0, 0, 22)
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
	local top = inset + 6
	local titleH = clamp(h * 0.1, 34, 76)
	title.Size, title.Position = UDim2.new(0, math.min(w * 0.6, titleH * 9), 0, titleH), UDim2.new(0.5, 0, 0, top)
	local tagH = clamp(h * 0.045, 15, 28)
	tagline.Size = UDim2.new(0, math.min(w * 0.62, tagH * 26), 0, tagH)
	tagline.Position = UDim2.new(0.5, 0, 0, top + titleH + 2)
	local countH = clamp(h * 0.1, 40, 62)
	local countW = math.min(w * 0.42, 460)
	countPill.Size, countPill.Position = UDim2.new(0, countW, 0, countH), UDim2.new(0.5, 0, 1, -countH - 12)
	local pillH = clamp(h * 0.07, 28, 46)
	biomePill.Size = UDim2.new(0, math.min(w * 0.36, pillH * 8), 0, pillH)
	biomePill.Position = UDim2.new(0.5, 0, 1, -countH - 12 - pillH - 8)
	local viewTop = top + titleH + tagH + 8
	local viewBottom = h - countH - 12 - pillH - 14
	local listW = small and 150 or 200
	view.Size = UDim2.new(0, math.max(w - 2 * (listW + 24), w * 0.5), 0, math.max(viewBottom - viewTop, 60))
	view.Position = UDim2.new(0.5, 0, 0, viewTop)
	listFrame.Size = UDim2.new(0, listW, 0, math.max(viewBottom - viewTop, 120))
	listFrame.Position = UDim2.new(1, -12, 0, viewTop)
	task.defer(function() pcall(buildLineup) end)
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- ── Every frame: the countdown, the roulette ────────────────────────────────
local _longest = nil   -- the countdown's start (for the bar)
RunService.Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local left = PhaseClock.remaining(nil)
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
		pcall(buildLineup)
	else
		screen.Enabled = false
	end
end)
