-- ItemGuideUI
-- The item guide: every item with its icon, rarity, slot and what its E
-- ability does in a race (Shared/ItemBlurbs, the crafting screen's lines).
-- 📖 ITEMS button / J opens it in every phase but RACING. Picking up an
-- item you have not had before this session shows a short card saying what
-- it does, so players learn the items while they farm.
-- (Playtest 2026-10-28: "can you learn what each item does just by
-- playing? a manual to read would help".)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local ItemBlurbs   = require(ReplicatedStorage.Shared.ItemBlurbs)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

-- ResetOnSpawn = false: this script runs again after a respawn
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "ItemGuideUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "ItemGuideUI"
screen.ResetOnSpawn   = false
screen.DisplayOrder   = 19
screen.Parent         = LocalPlayer.PlayerGui

local GOLD   = Color3.fromRGB(255, 210, 60)
local PANEL  = Color3.fromRGB(28, 24, 46)
local CARD   = Color3.fromRGB(44, 40, 66)
local RARITY_COLOUR = {
	Common   = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(80, 200, 80),
	Rare     = Color3.fromRGB(100, 160, 255),
	Epic     = Color3.fromRGB(200, 100, 255),
}
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
local TABS = { "BODY", "ENGINE", "SPECIAL" }
local TAB_NAME = { BODY = "Body", ENGINE = "Engine", SPECIAL = "Special" }
local TAB_HINT = {
	BODY    = "What you ride: the car, boat or plane becomes this item. Weight and grip.",
	ENGINE  = "Acceleration and top speed.",
	SPECIAL = "Boost length.",
}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
end

local function label(parent, text, size, pos, font, colour)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Text = text
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = colour or Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

--- Items of one slot type, by rarity then name.
local function itemsOf(slotType)
	local list = {}
	for name, cfg in pairs(ItemConfig) do
		if type(cfg) == "table" and cfg.slotType == slotType then table.insert(list, name) end
	end
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[ItemConfig[a].rarity] or 0, RARITY_ORDER[ItemConfig[b].rarity] or 0
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	return list
end

-- ── Open button ─────────────────────────────────────────────────────────────
-- Right of the SHOP button (ShopUI: left edge, mid-height).

local openBtn = Instance.new("TextButton")
openBtn.Name             = "OpenGuide"
openBtn.Size             = UDim2.new(0, 120, 0, 40)
openBtn.AnchorPoint      = Vector2.new(0, 0.5)
openBtn.Position         = UDim2.new(0, 136, 0.5, 0)
openBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 200)
openBtn.Text             = (UserInputService.KeyboardEnabled and "📖 ITEMS [J]") or "📖 ITEMS"
openBtn.TextColor3       = Color3.new(1, 1, 1)
openBtn.TextScaled       = true
openBtn.Font             = Enum.Font.GothamBlack
openBtn.Parent           = screen
corner(openBtn, 10)
-- clear of the key list (TutorialUI KeyStrip) on short windows
require(ReplicatedStorage.Shared.SideButtons).keepClear(openBtn, screen, 136)

-- ── Panel ───────────────────────────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name             = "Guide"
panel.Size             = UDim2.new(0, 560, 0, 440)
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = PANEL
panel.Visible          = false
panel.Parent           = screen
corner(panel, 14)
local scale = Instance.new("UIScale")
scale.Parent = panel
local function rescale()
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize.X or 1000
	local h = cam and cam.ViewportSize.Y or 800
	scale.Scale = math.min(1, (w - 32) / 560, (h - 32) / 440)
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

label(panel, "📖 Item Guide", UDim2.new(0, 300, 0, 32), UDim2.new(0, 16, 0, 10), Enum.Font.GothamBlack, GOLD)
label(panel, "Put items in Body, Engine or Special, then press E in the race to use their ability.",
	UDim2.new(1, -32, 0, 16), UDim2.new(0, 16, 0, 44), Enum.Font.Gotham, Color3.fromRGB(210, 210, 225))

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 32, 0, 32)
closeBtn.Position         = UDim2.new(1, -44, 0, 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 90)
closeBtn.Text             = "✕"
closeBtn.TextColor3       = Color3.new(1, 1, 1)
closeBtn.TextScaled       = true
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.Parent           = panel
corner(closeBtn, 16)

local tabBtns = {}
local hintLbl = label(panel, "", UDim2.new(1, -32, 0, 16), UDim2.new(0, 16, 0, 104), Enum.Font.GothamMedium, GOLD)

local list = Instance.new("ScrollingFrame")
list.Size                  = UDim2.new(1, -24, 1, -134)
list.Position              = UDim2.new(0, 12, 0, 126)
list.BackgroundTransparency = 1
list.BorderSizePixel       = 0
list.ScrollBarThickness    = 6
list.AutomaticCanvasSize   = Enum.AutomaticSize.Y
list.CanvasSize            = UDim2.new(0, 0, 0, 0)
list.Parent                = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local _tab = "BODY"
local _seen = {}   -- items picked up this session (marked in the list)

local function row(name, order)
	local cfg = ItemConfig[name]
	local f = Instance.new("Frame")
	f.Size             = UDim2.new(1, -10, 0, 54)
	f.BackgroundColor3 = CARD
	f.LayoutOrder      = order
	f.Parent           = list
	corner(f, 8)
	local icon = label(f, cfg.icon or "❔", UDim2.new(0, 40, 0, 40), UDim2.new(0, 8, 0, 7), Enum.Font.GothamBold)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	local title = name .. (_seen[name] and "  ✓" or "")
	label(f, title, UDim2.new(0.5, -60, 0, 20), UDim2.new(0, 56, 0, 6), Enum.Font.GothamBlack,
		RARITY_COLOUR[cfg.rarity] or Color3.new(1, 1, 1))
	local tags = { cfg.rarity or "" }
	if cfg.ride and cfg.slotType ~= "BODY" then table.insert(tags, "rideable: fits Body too") end
	local tagLbl = label(f, table.concat(tags, "  ·  "), UDim2.new(0.5, -10, 0, 14), UDim2.new(0.5, 0, 0, 9),
		Enum.Font.Gotham, Color3.fromRGB(170, 170, 190))
	tagLbl.TextXAlignment = Enum.TextXAlignment.Right
	label(f, "E: " .. (ItemBlurbs.ABILITY[name] or "no ability"), UDim2.new(1, -66, 0, 18), UDim2.new(0, 56, 0, 30),
		Enum.Font.GothamMedium, Color3.fromRGB(235, 235, 245))
end

local function redraw()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for t, b in pairs(tabBtns) do
		b.BackgroundColor3 = (t == _tab) and Color3.fromRGB(230, 160, 30) or Color3.fromRGB(60, 56, 86)
	end
	hintLbl.Text = TAB_NAME[_tab] .. ": " .. TAB_HINT[_tab]
	for i, name in ipairs(itemsOf(_tab)) do row(name, i) end
	list.CanvasPosition = Vector2.new(0, 0)
end

for i, t in ipairs(TABS) do
	local b = Instance.new("TextButton")
	b.Size       = UDim2.new(0, 120, 0, 30)
	b.Position   = UDim2.new(0, 16 + (i - 1) * 128, 0, 68)
	b.Text       = TAB_NAME[t]
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Font       = Enum.Font.GothamBold
	b.Parent     = panel
	corner(b, 8)
	tabBtns[t] = b
	b.Activated:Connect(function() _tab = t; redraw() end)
end

local function open(tab)
	if tab and TAB_NAME[tab] then _tab = tab end
	redraw()
	panel.Visible = true
end
local function toggle()
	if not openBtn.Visible then return end
	if panel.Visible then panel.Visible = false else open() end
end
openBtn.Activated:Connect(toggle)
closeBtn.Activated:Connect(function() panel.Visible = false end)
KeyInput.began(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J then toggle() end
end)

-- Every phase but RACING (the keys are busy driving then).
local function onPhase(phase)
	openBtn.Visible = phase ~= Constants.PHASES.RACING
	if not openBtn.Visible then panel.Visible = false end
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
onPhase(ReplicatedStorage:GetAttribute("Phase"))

-- ── "New item!" card on the first pickup of each item ──────────────────────

local card = Instance.new("Frame")
card.Name             = "NewItem"
card.Size             = UDim2.new(0, 360, 0, 64)
card.AnchorPoint      = Vector2.new(0.5, 0)
card.Position         = UDim2.new(0.5, 0, 0, 96)
card.BackgroundColor3 = PANEL
card.BackgroundTransparency = 0.1
card.Visible          = false
card.Parent           = screen
corner(card, 10)
local cardIcon = label(card, "", UDim2.new(0, 44, 0, 44), UDim2.new(0, 10, 0, 10), Enum.Font.GothamBold)
cardIcon.TextXAlignment = Enum.TextXAlignment.Center
local cardTitle = label(card, "", UDim2.new(1, -70, 0, 22), UDim2.new(0, 62, 0, 8), Enum.Font.GothamBlack, GOLD)
local cardText = label(card, "", UDim2.new(1, -70, 0, 18), UDim2.new(0, 62, 0, 34), Enum.Font.GothamMedium)
local _cardToken = 0

local function showNew(name)
	local cfg = ItemConfig[name]
	if not cfg then return end
	cardIcon.Text = cfg.icon or "❔"
	cardTitle.Text = "NEW: " .. name .. "  (" .. (TAB_NAME[cfg.slotType] or "") .. ")"
	cardTitle.TextColor3 = RARITY_COLOUR[cfg.rarity] or GOLD
	cardText.Text = "E: " .. (ItemBlurbs.ABILITY[name] or "no ability") .. "   [J] all items"
	_cardToken += 1
	local token = _cardToken
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0, 70)
	TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 96) }):Play()
	task.delay(4, function()
		if token == _cardToken then card.Visible = false end
	end)
end

RemoteEvents.ItemPickedUp.OnClientEvent:Connect(function(_itemId, userId, info)
	if userId ~= LocalPlayer.UserId or type(info) ~= "table" or type(info.item) ~= "string" then return end
	if _seen[info.item] then return end
	_seen[info.item] = true
	showNew(info.item)
	if panel.Visible then redraw() end
end)
