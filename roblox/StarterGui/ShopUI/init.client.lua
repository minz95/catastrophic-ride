-- ShopUI/init.client.lua
-- The cosmetics shop: paints and trails bought with coins (Shared/Cosmetics,
-- server: Modules/Shop through RemoteEvents.ShopAction) and Robux coin packs
-- (Shared/Products). Opened with the SHOP button or B in every phase but
-- RACING (the lobby countdown alone was too short to shop); a look bought
-- before the car is built (CRAFTING end) shows on this round's car, and the
-- crafting showroom shows it at once (CraftPreview.refresh). The panel shows
-- the phase clock and gets out of the way before the game needs the player
-- (Shared/ShopTiming): a round starting, the last seconds of CRAFTING, RACING.

local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local Cosmetics    = require(ReplicatedStorage.Shared.Cosmetics)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local ShopTiming   = require(ReplicatedStorage.Shared.ShopTiming)
local SoundFx      = require(ReplicatedStorage.Shared.SoundFx)
local LocalPlayer  = Players.LocalPlayer

-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "ShopUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "ShopUI"
screen.ResetOnSpawn   = false
screen.DisplayOrder   = 20
screen.Enabled        = true
screen.Parent         = LocalPlayer.PlayerGui

local GOLD  = Color3.fromRGB(255, 210, 60)
local PANEL = Color3.fromRGB(28, 24, 46)
local CARD  = Color3.fromRGB(44, 40, 66)

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
end

local function label(parent, text, size, pos, font, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

-- ── Open button ───────────────────────────────────────────────────────────────
local openBtn = Instance.new("TextButton")
openBtn.Name             = "OpenShop"
openBtn.Size             = UDim2.new(0, 120, 0, 40)
-- left edge, mid-height: clear of the key strip and Controls button (bottom
-- left) and the inventory bar; in CRAFTING on the crafting panel (_place)
openBtn.AnchorPoint      = Vector2.new(0, 0.5)
openBtn.Position         = UDim2.new(0, 8, 0.5, 0)
openBtn.BackgroundColor3 = Color3.fromRGB(230, 160, 30)
local function _openText()
	return require(ReplicatedStorage.Shared.InputHints).touchUI() and "SHOP" or "SHOP [B]"
end
openBtn.Text             = _openText()
require(ReplicatedStorage.Shared.InputHints).onChange(function() openBtn.Text = _openText() end)
openBtn.TextColor3       = Color3.new(1, 1, 1)
openBtn.TextScaled       = true
openBtn.Font             = Enum.Font.GothamBlack
openBtn.Visible          = false
openBtn.Parent           = screen
corner(openBtn)

-- ── Notice (why the shop closed itself) ─────────────────────────────────────
local notice = Instance.new("TextLabel")
notice.Name                   = "ShopNotice"
notice.AnchorPoint            = Vector2.new(0.5, 0)
notice.Position               = UDim2.new(0.5, 0, 0.16, 0)
notice.Size                   = UDim2.new(0, 420, 0, 34)
notice.BackgroundColor3       = Color3.fromRGB(28, 24, 46)
notice.BackgroundTransparency = 0.15
notice.TextColor3             = Color3.fromRGB(255, 210, 60)
notice.TextScaled             = true
notice.Font                   = Enum.Font.GothamBold
notice.Visible                = false
notice.Parent                 = screen
corner(notice)
local noticePad = Instance.new("UIPadding")
noticePad.PaddingLeft, noticePad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
noticePad.PaddingTop, noticePad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
noticePad.Parent = notice
local _noticeToken = 0
local function showNotice(text)
	_noticeToken += 1
	local token = _noticeToken
	notice.Text = text
	notice.Visible = true
	task.delay(Constants.SHOP.NOTICE_SECONDS, function()
		if token == _noticeToken then notice.Visible = false end
	end)
end

-- ── Panel ─────────────────────────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.Name             = "Panel"
panel.Size             = UDim2.new(0, 520, 0, 520)
-- centred: a UIScale shrinks about the AnchorPoint (with the old top-left
-- anchor the title, coins and close button went off the top of a phone)
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = PANEL
panel.Visible          = false
panel.Parent           = screen
corner(panel, 10)
-- narrow (phone) screens: scale the whole panel down
local scale = Instance.new("UIScale")
scale.Parent = panel
local ScreenFit = require(ReplicatedStorage.Shared.ScreenFit)
ScreenFit.watch(function()
	scale.Scale = (ScreenFit.scale(520, 520, 12))
end)

label(panel, "SHOP", UDim2.new(0, 160, 0, 36), UDim2.new(0, 14, 0, 8), Enum.Font.GothamBlack, GOLD)
local coinsLbl = label(panel, "", UDim2.new(0, 220, 0, 26), UDim2.new(1, -290, 0, 14), Enum.Font.GothamBold, GOLD)
coinsLbl.TextXAlignment = Enum.TextXAlignment.Right

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 40, 0, 40)
closeBtn.Position         = UDim2.new(1, -50, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 60)
closeBtn.Text             = "X"
closeBtn.TextColor3       = Color3.new(1, 1, 1)
closeBtn.TextScaled       = true
closeBtn.Font             = Enum.Font.GothamBlack
closeBtn.Parent           = panel
corner(closeBtn)

-- the game around the shopper: "Round starts in 0:12" (ShopTiming.line)
local CLOCK_OK, CLOCK_WARN = Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 110, 100)
local clockLbl = label(panel, "", UDim2.new(1, -28, 0, 20), UDim2.new(0, 14, 0, 48), Enum.Font.GothamBold, CLOCK_OK)
clockLbl.Name = "PhaseClock"
clockLbl.TextXAlignment = Enum.TextXAlignment.Left

local hint = label(panel, "Looks only: your car drives the same. Shows on the car you craft.",
	UDim2.new(1, -28, 0, 18), UDim2.new(0, 14, 0, 72), Enum.Font.Gotham, Color3.fromRGB(190, 190, 210))
hint.TextXAlignment = Enum.TextXAlignment.Left

local msgLbl = label(panel, "", UDim2.new(1, -28, 0, 20), UDim2.new(0, 14, 1, -28), Enum.Font.GothamBold, Color3.fromRGB(255, 140, 120))

-- tabs
local TABS = { "ride", "paint", "trail", "hat", "taunt", "trick", "move", "gadget", "coins" }
local TAB_TITLES = { ride = "⭐ Rides", paint = "Paint", trail = "Trail", hat = "🎩 Hats", taunt = "😜 Taunts",
	trick = "💣 Race", move = "Moves", gadget = "Gadgets", coins = "Coins" }
local TAB_HINTS = {
	ride   = "Special rides: your whole car, boat or plane becomes a show. Drives the same.",
	paint  = "Looks only: your car drives the same. Shows on the car you craft.",
	trail  = "Looks only: a trail behind your car. Shows on the car you craft.",
	move   = "Farming: how your punch looks. Same reach and power.",
	gadget = "Farming: one trick per round. Press T (or the SMOKE button).",
	coins  = "Coins buy looks and tricks. Win races and come back daily for more.",
	taunt  = "Racing: press Q (or 😜). Everyone sees it; the ones behind you get it on screen.",
	hat    = "On your avatar all game. Looks only.",
	trick  = "Racing: press T (or BOMB) once a race: the car ahead hops and slows.",
}
local tabBtns = {}
for i, key in ipairs(TABS) do
	local b = Instance.new("TextButton")
	b.Name             = "Tab_" .. key
	-- two rows of five
	b.Size             = UDim2.new(0, 92, 0, 30)
	b.Position         = UDim2.new(0, 14 + ((i - 1) % 5) * 99, 0, 98 + ((i - 1) // 5) * 34)
	b.BackgroundColor3 = CARD
	b.Text             = TAB_TITLES[key]
	b.TextColor3       = Color3.new(1, 1, 1)
	b.TextScaled       = true
	b.Font             = Enum.Font.GothamBold
	b.Parent           = panel
	corner(b, 6)
	tabBtns[key] = b
end

local grid = Instance.new("ScrollingFrame")
grid.Name                 = "Items"
grid.Size                 = UDim2.new(1, -28, 1, -208)
grid.Position             = UDim2.new(0, 14, 0, 174)
grid.BackgroundTransparency = 1
grid.BorderSizePixel      = 0
grid.ScrollBarThickness   = 6
grid.AutomaticCanvasSize  = Enum.AutomaticSize.Y
grid.CanvasSize           = UDim2.new()
grid.Parent               = panel
local layout = Instance.new("UIGridLayout")
layout.CellSize    = UDim2.new(0, 156, 0, 152)
layout.CellPadding = UDim2.new(0, 8, 0, 8)
layout.SortOrder   = Enum.SortOrder.LayoutOrder
layout.Parent      = grid

-- ── State ─────────────────────────────────────────────────────────────────────
local _state = nil      -- Modules/Shop.state
local _tab = "ride"
local _busy = false

local function owns(id)
	if Cosmetics.isDefault(id) then return true end
	for _, o in ipairs((_state and _state.owned) or {}) do
		if o == id then return true end
	end
	return false
end

-- ── 3D pictures (server: Modules/ShopPreview) ─────────────────────────────────
-- Each vehicle look turns on this round's vehicle (car / boat / plane) in a
-- ViewportFrame; a rainbow ride cycles its colour like the real one.
local _spinning = {}   -- { vp, cam, center, dist, height, hue = { parts } }

local function previewModel(it)
	local root = ReplicatedStorage:FindFirstChild("ShopPreviews")
	local biome = ReplicatedStorage:GetAttribute("Biome") or "FOREST"
	local folder = root and (root:FindFirstChild(biome) or root:FindFirstChild("FOREST"))
	return folder and folder:FindFirstChild(it.id)
end

local function preview(card, it)
	if it.category ~= "ride" and it.category ~= "paint" and it.category ~= "trail" and it.category ~= "hat" then return false end
	local src = previewModel(it)
	if not src then return false end
	local vp = Instance.new("ViewportFrame")
	vp.Name             = "Preview"
	vp.Size             = UDim2.new(1, -12, 0, 80)
	vp.Position         = UDim2.new(0, 6, 0, 6)
	vp.BackgroundColor3 = Color3.fromRGB(64, 70, 96)
	vp.Ambient          = Color3.fromRGB(150, 150, 160)
	vp.LightColor       = Color3.fromRGB(255, 250, 240)
	vp.LightDirection   = Vector3.new(-1, -2, -0.6)
	vp.Parent           = card
	corner(vp, 6)
	local model = src:Clone()
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude * 0.5
	local hue = {}
	if model:GetAttribute("RideHue") then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("RideBody") then table.insert(hue, d) end
		end
	end
	table.insert(_spinning, {
		cam = cam, center = cf.Position, dist = radius / math.tan(math.rad(cam.FieldOfView * 0.5)) * 0.95,
		height = radius * 0.45, hue = hue, phase = #_spinning * 0.7,
	})
	if it.category == "ride" and not it.body then return true end
	if it.category == "ride" then
		label(vp, "⭐", UDim2.new(0, 22, 0, 22), UDim2.new(0, 4, 0, 2), Enum.Font.GothamBlack, GOLD)
	end
	return true
end

-- 20 times a second: every card's ViewportFrame redraws its whole vehicle
-- when its camera moves, and every frame was heavy on a phone.
local SPIN_STEP = 1 / 20
local _spinAt = 0
game:GetService("RunService").RenderStepped:Connect(function()
	if not panel.Visible then return end
	local t = os.clock()
	if t - _spinAt < SPIN_STEP then return end
	_spinAt = t
	for _, sp in ipairs(_spinning) do
		local a = t * 0.6 + sp.phase
		local eye = sp.center + Vector3.new(math.sin(a) * sp.dist, sp.height, math.cos(a) * sp.dist)
		sp.cam.CFrame = CFrame.lookAt(eye, sp.center)
		if #sp.hue > 0 then
			local c = Color3.fromHSV((t * 0.15) % 1, 0.75, 1)
			for _, p in ipairs(sp.hue) do p.Color = c end
		end
	end
end)

local function swatch(card, it)
	if preview(card, it) then return end
	local s = Instance.new("Frame")
	s.Size             = UDim2.new(1, -12, 0, 80)
	s.Position         = UDim2.new(0, 6, 0, 6)
	s.BorderSizePixel  = 0
	s.BackgroundColor3 = Color3.new(1, 1, 1)
	s.Parent           = card
	corner(s, 6)
	local g = Instance.new("UIGradient")
	if it.category == "taunt" then
		-- the bubble as others see it over your car
		s.BackgroundColor3 = Color3.fromRGB(70, 90, 130)
		local b = label(s, it.emoji .. " " .. it.text, UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0.5, -17), Enum.Font.GothamBlack, Color3.fromRGB(30, 30, 40))
		b.BackgroundTransparency = 0.05
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		corner(b, 17)
		return
	end
	if it.category == "trick" then
		s.BackgroundColor3 = Color3.fromRGB(90, 50, 40)
		label(s, it.trick and "💣 BOOM!" or "—", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBlack, Color3.fromRGB(255, 170, 60))
		return
	end
	if it.category == "move" or it.category == "gadget" then
		s.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
		local icon = (it.style == "kick" and "🦶") or (it.gadget == "smoke" and "💨")
			or (it.category == "move" and "👊") or "—"
		label(s, icon, UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBold, Color3.new(1, 1, 1))
		return
	end
	if it.category == "ride" and not it.body then
		s.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
		label(s, "your build", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBold, Color3.new(1, 1, 1))
		return
	end
	if it.category == "ride" and it.hue then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 200, 40)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
		})
		g.Parent = s
		label(s, "⭐", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBlack, Color3.new(1, 1, 1))
		return
	end
	if it.category == "paint" or it.category == "ride" then
		local body = it.body or Color3.fromRGB(196, 72, 52)
		local accent = it.accent or Color3.fromRGB(235, 190, 70)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, body), ColorSequenceKeypoint.new(0.7, body),
			ColorSequenceKeypoint.new(0.71, accent), ColorSequenceKeypoint.new(1, accent),
		})
	elseif it.rainbow then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 200, 40)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
		})
	elseif it.colors then
		g.Color = ColorSequence.new(it.colors[1], it.colors[2] or it.colors[1])
	else
		s.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
	end
	g.Parent = s
	if it.category == "ride" then
		label(s, "⭐", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBlack, Color3.new(1, 1, 1))
	end
	if it.category == "paint" and not it.body then
		label(s, "biome", UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBold, Color3.new(1, 1, 1))
	end
end

local _redraw

local function act(action, id)
	if _busy then return end
	_busy = true
	local ok, res = pcall(function() return RemoteEvents.ShopAction:InvokeServer(action, id) end)
	_busy = false
	if not ok or type(res) ~= "table" then
		msgLbl.Text = "The shop is not available right now"
		return
	end
	if res.state then _state = res.state end
	local r = res.result or "?"
	if r == "ok" then
		msgLbl.Text = ""
		-- a buy or an equip clicks; opening the shop ("state") is silent
		-- (playtest 2026-10-28: a loud sound every time the shop opened)
		if action == "buy" then SoundFx.play("CRAFT_COMPLETE") elseif action == "equip" then SoundFx.play("SLOT_ASSIGN") end
	elseif r == "denied: coins" then
		msgLbl.Text = "Not enough coins: win races and come back daily for more"
	elseif r:sub(1, 14) == "denied: level " then
		msgLbl.Text = "Reach level " .. r:sub(15) .. " to buy this"
	elseif r == "denied: loading" then
		msgLbl.Text = "Loading your coins..."
	else
		msgLbl.Text = "Could not do that (" .. r .. ")"
	end
	_redraw()
end

local function itemCard(it, order)
	local card = Instance.new("Frame")
	card.Name             = it.id
	card.BackgroundColor3 = CARD
	card.LayoutOrder      = order
	card.Parent           = grid
	corner(card)
	swatch(card, it)
	label(card, it.name, UDim2.new(1, -12, 0, 20), UDim2.new(0, 6, 0, 89), Enum.Font.GothamBold)

	local equipped = _state and _state.equipped and _state.equipped[it.category]
	local isOn = equipped == it.id or (equipped == nil and Cosmetics.isDefault(it.id))
	local btn = Instance.new("TextButton")
	btn.Size       = UDim2.new(1, -16, 0, 34)
	btn.Position   = UDim2.new(0, 8, 1, -42)
	btn.TextScaled = true
	btn.Font       = Enum.Font.GothamBold
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent     = card
	corner(btn, 6)
	local level = (_state and _state.level) or 1
	if isOn then
		btn.Text = "Equipped"
		btn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
		btn.AutoButtonColor = false
	elseif owns(it.id) then
		btn.Text = "Equip"
		btn.BackgroundColor3 = Color3.fromRGB(70, 110, 200)
		btn.Activated:Connect(function() act("equip", it.id) end)
	elseif level < (it.minLevel or 1) then
		btn.Text = "Level " .. it.minLevel
		btn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		btn.AutoButtonColor = false
	else
		btn.Text = "Buy  " .. it.price
		local enough = ((_state and _state.coins) or 0) >= it.price
		btn.BackgroundColor3 = enough and Color3.fromRGB(220, 150, 30) or Color3.fromRGB(120, 95, 60)
		btn.Activated:Connect(function() act("buy", it.id) end)
	end
end

local function packCard(p, order)
	local card = Instance.new("Frame")
	card.Name             = "Pack" .. p.id
	card.BackgroundColor3 = CARD
	card.LayoutOrder      = order
	card.Parent           = grid
	corner(card)
	label(card, tostring(p.coins), UDim2.new(1, -12, 0, 40), UDim2.new(0, 6, 0, 8), Enum.Font.GothamBlack, GOLD)
	label(card, p.name, UDim2.new(1, -12, 0, 22), UDim2.new(0, 6, 0, 54), Enum.Font.GothamBold)
	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(1, -16, 0, 34)
	btn.Position         = UDim2.new(0, 8, 1, -42)
	btn.Text             = "R$ " .. tostring(p.robux)
	btn.TextScaled       = true
	btn.Font             = Enum.Font.GothamBold
	btn.TextColor3       = Color3.new(1, 1, 1)
	btn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
	btn.Parent           = card
	corner(btn, 6)
	btn.Activated:Connect(function()
		pcall(function() MarketplaceService:PromptProductPurchase(LocalPlayer, p.id) end)
	end)
end

_redraw = function()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	table.clear(_spinning)
	for key, b in pairs(tabBtns) do
		b.BackgroundColor3 = key == _tab and Color3.fromRGB(230, 160, 30) or CARD
	end
	hint.Text = TAB_HINTS[_tab] or ""
	coinsLbl.Text = _state and string.format("Level %d   ·   %d Coins", _state.level or 1, _state.coins or 0) or "..."
	if _tab == "coins" then
		local packs = (_state and _state.packs) or {}
		for i, p in ipairs(packs) do packCard(p, i) end
		if #packs == 0 then
			local l = label(grid, "Coin packs are coming soon. Earn coins by racing!", UDim2.new(1, 0, 0, 30), UDim2.new(), Enum.Font.GothamBold)
			l.LayoutOrder = 1
		end
	else
		for i, it in ipairs(Cosmetics.ITEMS[_tab]) do itemCard(it, i) end
	end
end

local function open()
	panel.Visible = true
	msgLbl.Text = ""
	_redraw()
	task.spawn(act, "state")
end

local function toggle()
	if not openBtn.Visible then return end
	if panel.Visible then panel.Visible = false else open() end
end
openBtn.Activated:Connect(toggle)
-- clear of the key list (TutorialUI KeyStrip) on short windows
require(ReplicatedStorage.Shared.SideButtons).keepClear(openBtn, screen, 8)
KeyInput.began(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then toggle() end
end)
closeBtn.Activated:Connect(function() panel.Visible = false end)

-- Other screens open the shop through this (ResultsUI's SHOP button), on a
-- tab: Fire(tab?).
local openEvent = Instance.new("BindableEvent")
openEvent.Name = "Open"
openEvent.Parent = screen
openEvent.Event:Connect(function(tab)
	if not openBtn.Visible then return end
	if type(tab) == "string" and tabBtns[tab] then _tab = tab end
	open()
end)
for key, b in pairs(tabBtns) do
	b.Activated:Connect(function()
		_tab = key
		msgLbl.Text = ""
		_redraw()
	end)
end

RemoteEvents.ShopUpdated.OnClientEvent:Connect(function(state)
	_state = state
	if panel.Visible then _redraw() end
end)

-- Where the button sits: the left edge, mid-height, except in CRAFTING,
-- where that spot is the crafting screen's Body slot: there the button goes
-- into the crafting panel itself, top-right beside the title (drawn with the
-- panel; the shop panel still opens from this ScreenGui, above it).
local function _craftPanel()
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		-- the ScreenGui, not the LocalScript of the same name next to it
		if g.Name == "CraftingUI" and g:IsA("ScreenGui") then return g:FindFirstChild("Panel") end
	end
	return nil
end

local function _place(phase)
	local craftPanel = phase == Constants.PHASES.CRAFTING and _craftPanel()
	if craftPanel then
		openBtn.AnchorPoint = Vector2.new(1, 0)
		openBtn.Position    = UDim2.new(1, -10, 0, 12)
		openBtn.Size        = UDim2.new(0, 100, 0, 30)
		openBtn.ZIndex      = 5
		openBtn.Parent      = craftPanel
	else
		openBtn.AnchorPoint = Vector2.new(0, 0.5)
		openBtn.Position    = UDim2.new(0, 8, 0.5, 0)
		openBtn.Size        = UDim2.new(0, 120, 0, 40)
		openBtn.ZIndex      = 1
		openBtn.Parent      = screen
	end
end

-- Open in every phase but RACING (driving needs the whole screen). An open
-- panel closes itself when the game needs the player (ShopTiming.closeFor).
local _phase = nil
local _timing = { craftClosed = false }

local function _closeIfDue(from)
	local left = PhaseClock.remaining(nil)
	if panel.Visible then
		local close, why = ShopTiming.closeFor(_phase, from, left, _timing)
		if close then
			panel.Visible = false
			if why then showNotice(why) end
		end
	end
	-- once under the mark the choice is the player's: reopening stays open
	if _phase == Constants.PHASES.CRAFTING and left and left <= Constants.SHOP.CRAFT_CLOSE_AT then
		_timing.craftClosed = true
	end
end

local function onPhase(phase)
	local from = _phase
	_phase = phase
	if phase ~= from then _timing.craftClosed = false end
	openBtn.Visible = phase ~= Constants.PHASES.RACING
	_closeIfDue(from)
	if phase == Constants.PHASES.RACING then panel.Visible = false end
	_place(phase)
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
onPhase(ReplicatedStorage:GetAttribute("Phase") or Constants.PHASES.LOBBY)

game:GetService("RunService").Heartbeat:Connect(function()
	if not _phase then return end
	_closeIfDue(nil)
	if panel.Visible then
		local text, warn = ShopTiming.line(_phase, PhaseClock.remaining(nil))
		clockLbl.Text = text
		clockLbl.TextColor3 = warn and CLOCK_WARN or CLOCK_OK
	end
end)
