-- TutorialUI/init.client.lua
-- Phase-specific control guide shown at the start of each phase, a small
-- key list that stays on screen all phase (keyboard players: the keys are
-- always there to look up), and the full reference panel (H or F1, or the
-- Controls button). The RACING guide closes at GO so it never covers the
-- road (ReplicatedStorage "RaceGoAt").

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local InputHints   = require(ReplicatedStorage.Shared.InputHints)
local LocalPlayer  = Players.LocalPlayer

-- ─── Build screen ─────────────────────────────────────────────────────────────


-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "TutorialUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "TutorialUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = true
screen.Parent         = LocalPlayer.PlayerGui

-- ─── Phase-specific guide data ───────────────────────────────────────────────

-- `key` is the keyboard text. On a gamepad or a phone the text comes from
-- Shared/InputHints (`act`: the action, `how`: "hold" / "tap3"), or from
-- `pad` / `touch` when given (false: no such control on that device).
local PHASE_GUIDES = {
	FARMING = {
		title = "🌾  FARMING PHASE",
		colour = Color3.fromRGB(80, 180, 60),
		keys = {
			{ key = "E",          act = "grab",   short = "Grab",   desc = "Pick up an item (tap fast to win a tug-of-war)" },
			{ key = "Hold E",     act = "steal",  how = "hold", short = "Steal",  desc = "Next to a player: steal an item" },
			{ key = "Tap E ×3",   act = "defend", how = "tap3", short = "Defend", desc = "Someone is stealing from you: stop them" },
			{ key = "F / Click",  act = "punch",  short = "Punch",  desc = "Punch (4 hits knock an item loose)" },
			{ key = "Hold G",     act = "guard",  how = "hold", short = "Guard",  desc = "Block punches" },
			{ key = "X",          act = "drop",   short = "Drop",   desc = "Drop your oldest item" },
			{ key = "Hold Q",     act = "emote",  short = "Emote",  desc = "Emote menu" },
			{ key = "B",          act = "shop",   short = "Shop",   desc = "Shop: looks for this round's car" },
			{ key = "J",          act = "guide",  short = "Items",  desc = "Item guide: what every item does" },
		},
		tip = "Grab the items with icons and names, or rob other players!\nRarity: grey (Common) < green (Uncommon) < blue (Rare) < purple (Epic)",
	},
	CRAFTING = {
		title = "🔧  CRAFTING PHASE",
		colour = Color3.fromRGB(200, 140, 40),
		keys = {
			{ key = "Click item, slot", touch = "Tap item, slot", pad = "A: item, slot", short = "Place",  desc = "Pick an inventory item, then the slot it goes in" },
			{ key = "Click a slot",     touch = "Tap a slot",     pad = "A on a slot",   short = "Remove", desc = "Remove its item" },
			{ key = "Submit",           touch = "Submit",         pad = "Submit",        short = "Finish", desc = "Finish your vehicle (button)" },
			{ key = "B",                act = "shop",  short = "Shop",   desc = "Shop: the showroom shows a new look at once" },
			{ key = "J",                act = "guide", short = "Items",  desc = "Item guide: what every item does" },
		},
		tip = "BODY + ENGINE + SPECIAL are required!\nMOBILITY (wheels / sail / wings), HEAD and TAIL are optional.",
	},
	RACING = {
		title = "🏎  RACING PHASE",
		colour = Color3.fromRGB(60, 140, 255),
		keys = {
			{ key = "W / ↑",         touch = "Stick up",    pad = "RT",         short = "Gas",     desc = "Accelerate" },
			{ key = "S / ↓",         touch = "Stick down",  pad = "LT",         short = "Brake",   desc = "Brake / reverse" },
			{ key = "A D / ← →",     touch = "Stick ← →",   pad = "Left stick", short = "Steer",   desc = "Steer" },
			{ key = "Shift + steer", act = "drift", how = "hold", short = "Drift",   desc = "Drift (above half speed)" },
			{ key = "F",             act = "boost", short = "Boost",   desc = "Boost (needs a full gauge)" },
			{ key = "E",             act = "item",  short = "Ability", desc = "Use an item ability" },
			{ key = "Space / Ctrl",  touch = "▲ / ▼", pad = "A / D-pad ←", short = "Up/Down", desc = "Climb / dive (SKY)", biome = "SKY" },
			{ key = "R",             act = "reset", short = "Reset",   desc = "Put the car back on the road" },
			{ key = "T",             act = "trick", short = "Bomb",    desc = "Bounce Bomb: the car ahead hops (once a race)", attr = "RaceTrick" },
			{ key = "Q",             act = "taunt", short = "Taunt",   desc = "Taunt the others (more in the SHOP)" },
		},
		tip = "Release a long drift for a mini turbo!\nBoost pads (yellow) give extra speed.",
	},
}

-- A guide row's control on this device (nil: not on this device).
local function _keyText(k, mode)
	mode = mode or InputHints.mode()
	if mode == "keyboard" then return k.key end
	if k[mode] ~= nil then return k[mode] or nil end
	if not k.act then return nil end
	local name = InputHints.key(k.act, mode)
	if k.how == "hold" then return "Hold " .. name end
	if k.how == "tap3" then return "Tap " .. name .. " ×3" end
	return name
end

-- "[ H ] Controls" on a keyboard; H does nothing on a phone or a gamepad.
local function _helpText(long)
	if InputHints.mode() == "keyboard" then
		return long and "[ H ] All controls  •  closes by itself" or "[ H ] Controls"
	end
	return long and "Controls button: all controls  •  closes by itself" or "Controls"
end

local function _biome()
	return game:GetService("ReplicatedStorage"):GetAttribute("Biome")
end

-- Keys of a phase that apply in this round's biome.
local function _keysFor(guide)
	local out = {}
	for _, k in ipairs(guide.keys) do
		if (not k.biome or k.biome == _biome())
			and (not k.attr or game:GetService("Players").LocalPlayer:GetAttribute(k.attr) ~= nil)
			and _keyText(k) ~= nil then
			table.insert(out, k)
		end
	end
	return out
end

-- ─── Floating toast (shows at phase start, auto-hides after 6s) ──────────────

local toastFrame = Instance.new("Frame")
toastFrame.Name              = "Toast"
toastFrame.Size              = UDim2.new(0, 360, 0, 0)   -- height auto
toastFrame.Position          = UDim2.new(0.5, -180, 0, 80)
toastFrame.BackgroundColor3  = Color3.fromRGB(15, 15, 25)
toastFrame.BackgroundTransparency = 0.15
toastFrame.BorderSizePixel   = 0
toastFrame.AutomaticSize     = Enum.AutomaticSize.Y
toastFrame.Visible           = false
toastFrame.Parent            = screen

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 12)
toastCorner.Parent       = toastFrame

local toastPad = Instance.new("UIPadding")
toastPad.PaddingTop    = UDim.new(0, 12)
toastPad.PaddingBottom = UDim.new(0, 12)
toastPad.PaddingLeft   = UDim.new(0, 14)
toastPad.PaddingRight  = UDim.new(0, 14)
toastPad.Parent        = toastFrame

local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Padding   = UDim.new(0, 6)
toastLayout.Parent    = toastFrame

local toastAccent = Instance.new("Frame")
toastAccent.Name           = "Accent"
toastAccent.Size           = UDim2.new(1, 0, 0, 3)
toastAccent.BackgroundColor3 = Color3.fromRGB(80, 180, 60)
toastAccent.BorderSizePixel = 0
toastAccent.LayoutOrder    = 0
toastAccent.Parent         = toastFrame

local toastTitle = Instance.new("TextLabel")
toastTitle.Size             = UDim2.new(1, 0, 0, 28)
toastTitle.BackgroundTransparency = 1
toastTitle.TextScaled       = true
toastTitle.Font             = Enum.Font.GothamBlack
toastTitle.TextColor3       = Color3.new(1, 1, 1)
toastTitle.TextXAlignment   = Enum.TextXAlignment.Left
toastTitle.LayoutOrder      = 1
toastTitle.Parent           = toastFrame

-- Key rows container
local keyContainer = Instance.new("Frame")
keyContainer.Name          = "Keys"
keyContainer.Size          = UDim2.new(1, 0, 0, 0)
keyContainer.BackgroundTransparency = 1
keyContainer.AutomaticSize = Enum.AutomaticSize.Y
keyContainer.LayoutOrder   = 2
keyContainer.Parent        = toastFrame

local keyLayout = Instance.new("UIListLayout")
keyLayout.SortOrder = Enum.SortOrder.LayoutOrder
keyLayout.Padding   = UDim.new(0, 3)
keyLayout.Parent    = keyContainer

local toastTip = Instance.new("TextLabel")
toastTip.Size             = UDim2.new(1, 0, 0, 0)
toastTip.AutomaticSize    = Enum.AutomaticSize.Y
toastTip.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
toastTip.BackgroundTransparency = 0.4
toastTip.BorderSizePixel  = 0
toastTip.TextScaled       = false
toastTip.TextSize         = 11
toastTip.Font             = Enum.Font.Gotham
toastTip.TextColor3       = Color3.fromRGB(200, 200, 220)
toastTip.TextXAlignment   = Enum.TextXAlignment.Left
toastTip.TextWrapped      = true
toastTip.LayoutOrder      = 3
toastTip.Parent           = toastFrame

local toastTipCorner = Instance.new("UICorner")
toastTipCorner.CornerRadius = UDim.new(0, 6)
toastTipCorner.Parent       = toastTip

local toastTipPad = Instance.new("UIPadding")
toastTipPad.PaddingLeft   = UDim.new(0, 8)
toastTipPad.PaddingRight  = UDim.new(0, 8)
toastTipPad.PaddingTop    = UDim.new(0, 5)
toastTipPad.PaddingBottom = UDim.new(0, 5)
toastTipPad.Parent        = toastTip

local toastDismiss = Instance.new("TextLabel")
toastDismiss.Size          = UDim2.new(1, 0, 0, 18)
toastDismiss.BackgroundTransparency = 1
toastDismiss.Text          = _helpText(true)
toastDismiss.TextScaled    = false
toastDismiss.TextSize      = 10
toastDismiss.Font          = Enum.Font.Gotham
toastDismiss.TextColor3    = Color3.fromRGB(140, 140, 160)
toastDismiss.TextXAlignment = Enum.TextXAlignment.Center
toastDismiss.LayoutOrder   = 4
toastDismiss.Parent        = toastFrame

-- ─── Key row builder ─────────────────────────────────────────────────────────

local function _clearKeyRows()
	for _, child in ipairs(keyContainer:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function _buildKeyRow(keyText, descText, order)
	local row = Instance.new("Frame")
	row.Size              = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.LayoutOrder       = order
	row.Parent            = keyContainer

	local keyBadge = Instance.new("TextLabel")
	keyBadge.Size          = UDim2.new(0, 130, 1, 0)
	keyBadge.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	keyBadge.BackgroundTransparency = 0.3
	keyBadge.BorderSizePixel = 0
	keyBadge.Text          = keyText
	keyBadge.TextScaled    = true
	keyBadge.Font          = Enum.Font.GothamBold
	keyBadge.TextColor3    = Color3.fromRGB(255, 220, 60)
	keyBadge.Parent        = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 5)
	badgeCorner.Parent       = keyBadge

	local descLbl = Instance.new("TextLabel")
	descLbl.Size           = UDim2.new(1, -138, 1, 0)
	descLbl.Position       = UDim2.new(0, 138, 0, 0)
	descLbl.BackgroundTransparency = 1
	descLbl.Text           = descText
	descLbl.TextScaled     = true
	descLbl.Font           = Enum.Font.Gotham
	descLbl.TextColor3     = Color3.fromRGB(220, 220, 220)
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.Parent         = row
end

-- ─── Show toast ───────────────────────────────────────────────────────────────

local _toastTimer  = nil
local _toastHideTimer = nil

local function _hideToast()
	if _toastTimer then
		pcall(task.cancel, _toastTimer)
		_toastTimer = nil
	end
	if _toastHideTimer then
		pcall(task.cancel, _toastHideTimer)
		_toastHideTimer = nil
	end
	if not toastFrame.Visible then return end
	TweenService:Create(toastFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, -180, 0, 40)
	}):Play()
	_toastHideTimer = task.delay(0.25, function()
		toastFrame.Visible = false
		_toastHideTimer = nil
	end)
end

local function _showToast(phase)
	local guide = PHASE_GUIDES[phase]
	-- RACING: no toast. Its keys are on the key strip and the objective and
	-- tips are in RacingClient's RACE START banner under the 3-2-1; the
	-- three of them used to pile up in the middle of the screen. H still
	-- opens the full RACING guide.
	if phase == "RACING" then guide = nil end
	-- CRAFTING: no toast either; it lay over the crafting panel and the
	-- showroom (Studio ui-layout 2026-10-30), which explain themselves
	if phase == "CRAFTING" then guide = nil end
	if not guide then
		-- Phases without a guide (e.g. RESULTS, LOBBY) should clear any
		-- lingering toast so it doesn't persist across phase changes.
		_hideToast()
		return
	end

	-- Cancel any pending hide so we don't immediately tween the new toast away.
	if _toastHideTimer then
		pcall(task.cancel, _toastHideTimer)
		_toastHideTimer = nil
	end

	-- Populate content
	toastAccent.BackgroundColor3 = guide.colour
	toastTitle.Text  = guide.title
	toastTitle.TextColor3 = guide.colour
	toastTip.Text    = guide.tip

	_clearKeyRows()
	-- the key strip (bottom-left) already lists them on a keyboard: the
	-- toast with every key again grew 360 px tall and covered the NEW card
	-- and the inventory bar (Studio ui-layout 2026-10-30)
	-- On a phone the touch buttons carry their names (GRAB, PUNCH, ...): all
	-- nine FARMING rows ran off a 375-px screen for 7 s. Only CRAFTING (no
	-- strip, no buttons) lists its steps here.
	if phase == "CRAFTING" then
		for i, k in ipairs(_keysFor(guide)) do
			_buildKeyRow(_keyText(k), k.desc, i)
		end
	end

	-- Animate in (slide down from top)
	toastFrame.Position = UDim2.new(0.5, -180, 0, 40)
	toastFrame.Visible  = true
	TweenService:Create(toastFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -180, 0, 80)
	}):Play()

	-- Auto-hide after 7 s
	local show = 7
	if _toastTimer then pcall(task.cancel, _toastTimer) end
	_toastTimer = task.delay(show, function()
		_toastTimer = nil
		_hideToast()
	end)
end

-- Click anywhere on the toast to dismiss early.
-- A child TextButton with Size=fromScale(1,1) would participate in the
-- toastFrame's UIListLayout and push all the actual content (title, key
-- rows, tip) out of the visible region — that's exactly the empty-toast
-- bug introduced in #144. Listen for input on the frame itself instead.
toastFrame.Active = true
toastFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		_hideToast()
	end
end)

-- ─── Full reference panel (F1 toggle) ────────────────────────────────────────

-- Scrolls: all three phases' keys are ~800 px, taller than a phone (its
-- title and ✕ were off the screen). As tall as its content, at most the
-- room under the top bar.
local refPanel = Instance.new("ScrollingFrame")
refPanel.Name             = "ReferencePanel"
refPanel.Size             = UDim2.new(0, 440, 0, 300)
refPanel.Position         = UDim2.new(1, -460, 0.5, 0)
refPanel.AnchorPoint      = Vector2.new(0, 0.5)
refPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 22)
refPanel.BackgroundTransparency = 0.05
refPanel.BorderSizePixel  = 0
refPanel.ScrollBarThickness = 6
refPanel.ScrollingDirection = Enum.ScrollingDirection.Y
refPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
refPanel.CanvasSize       = UDim2.new(0, 0, 0, 0)
refPanel.Visible          = false
refPanel.Parent           = screen

local refCorner = Instance.new("UICorner")
refCorner.CornerRadius = UDim.new(0, 14)
refCorner.Parent       = refPanel

local refLayout = Instance.new("UIListLayout")
refLayout.SortOrder = Enum.SortOrder.LayoutOrder
refLayout.Padding   = UDim.new(0, 0)
refLayout.Parent    = refPanel

local refPad = Instance.new("UIPadding")
refPad.PaddingTop    = UDim.new(0, 14)
refPad.PaddingBottom = UDim.new(0, 16)
refPad.PaddingLeft   = UDim.new(0, 16)
refPad.PaddingRight  = UDim.new(0, 16)
refPad.Parent        = refPanel

-- Title bar
local refTitleBar = Instance.new("Frame")
refTitleBar.Size              = UDim2.new(1, 0, 0, 36)
refTitleBar.BackgroundTransparency = 1
refTitleBar.LayoutOrder       = 0
refTitleBar.Parent            = refPanel

local refTitle = Instance.new("TextLabel")
refTitle.Size            = UDim2.new(0.8, 0, 1, 0)
refTitle.BackgroundTransparency = 1
refTitle.Text            = "🎮  Controls"
refTitle.TextScaled      = true
refTitle.Font            = Enum.Font.GothamBlack
refTitle.TextColor3      = Color3.fromRGB(255, 220, 60)
refTitle.TextXAlignment  = Enum.TextXAlignment.Left
refTitle.Parent          = refTitleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size            = UDim2.new(0, 36, 0, 28)
closeBtn.Position        = UDim2.new(1, -36, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text            = "✕"
closeBtn.TextScaled      = true
closeBtn.Font            = Enum.Font.GothamBold
closeBtn.TextColor3      = Color3.new(1, 1, 1)
closeBtn.Parent          = refTitleBar

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 6)
closeBtnCorner.Parent       = closeBtn

-- Divider
local divider = Instance.new("Frame")
divider.Size              = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3  = Color3.fromRGB(60, 60, 80)
divider.BorderSizePixel   = 0
divider.LayoutOrder       = 1
divider.Parent            = refPanel

-- Build all 3 sections in the panel
local function _buildSection(guidePhase, layoutOrder)
	local guide = PHASE_GUIDES[guidePhase]
	if not guide then return end

	local section = Instance.new("Frame")
	section.Size              = UDim2.new(1, 0, 0, 0)
	section.BackgroundTransparency = 1
	section.AutomaticSize    = Enum.AutomaticSize.Y
	section.LayoutOrder      = layoutOrder
	section.Parent           = refPanel

	local sLayout = Instance.new("UIListLayout")
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sLayout.Padding   = UDim.new(0, 4)
	sLayout.Parent    = section

	local sTitle = Instance.new("TextLabel")
	sTitle.Size           = UDim2.new(1, 0, 0, 26)
	sTitle.BackgroundTransparency = 1
	sTitle.Text           = guide.title
	sTitle.TextScaled     = true
	sTitle.Font           = Enum.Font.GothamBold
	sTitle.TextColor3     = guide.colour
	sTitle.TextXAlignment = Enum.TextXAlignment.Left
	sTitle.LayoutOrder    = 0
	sTitle.Parent         = section

	for i, k in ipairs(guide.keys) do
		local row = Instance.new("Frame")
		row.Size             = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.LayoutOrder      = i
		row.Parent           = section

		local badge = Instance.new("TextLabel")
		badge.Size           = UDim2.new(0, 140, 1, 0)
		badge.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
		badge.BackgroundTransparency = 0.2
		badge.BorderSizePixel = 0
		badge.Text           = _keyText(k) or k.key
		badge.TextScaled     = true
		badge.Font           = Enum.Font.GothamBold
		badge.TextColor3     = Color3.fromRGB(255, 220, 60)
		badge.Parent         = row
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)

		local desc = Instance.new("TextLabel")
		desc.Size            = UDim2.new(1, -148, 1, 0)
		desc.Position        = UDim2.new(0, 148, 0, 0)
		desc.BackgroundTransparency = 1
		desc.Text            = k.desc
		desc.TextScaled      = true
		desc.Font            = Enum.Font.Gotham
		desc.TextColor3      = Color3.fromRGB(210, 210, 220)
		desc.TextXAlignment  = Enum.TextXAlignment.Left
		desc.Parent          = row
	end

	-- Tip
	local tipLbl = Instance.new("TextLabel")
	tipLbl.Size           = UDim2.new(1, 0, 0, 0)
	tipLbl.AutomaticSize  = Enum.AutomaticSize.Y
	tipLbl.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
	tipLbl.BackgroundTransparency = 0.2
	tipLbl.BorderSizePixel = 0
	tipLbl.TextScaled     = false
	tipLbl.TextSize       = 11
	tipLbl.Font           = Enum.Font.Gotham
	tipLbl.TextColor3     = Color3.fromRGB(180, 200, 180)
	tipLbl.TextXAlignment = Enum.TextXAlignment.Left
	tipLbl.TextWrapped    = true
	tipLbl.Text           = "💡 " .. guide.tip
	tipLbl.LayoutOrder    = #guide.keys + 1
	tipLbl.Parent         = section
	Instance.new("UICorner", tipLbl).CornerRadius = UDim.new(0, 6)
	local tp = Instance.new("UIPadding", tipLbl)
	tp.PaddingLeft = UDim.new(0,7); tp.PaddingRight = UDim.new(0,7)
	tp.PaddingTop  = UDim.new(0,5); tp.PaddingBottom = UDim.new(0,5)

	-- Gap between sections
	local gap = Instance.new("Frame")
	gap.Size = UDim2.new(1, 0, 0, 10)
	gap.BackgroundTransparency = 1
	gap.LayoutOrder = #guide.keys + 2
	gap.Parent = section
end

_buildSection("FARMING",  2)
_buildSection("CRAFTING", 3)
_buildSection("RACING",   4)

do
	local ScreenFit = require(ReplicatedStorage.Shared.ScreenFit)
	local function fit()
		local w, h, top = ScreenFit.view()
		local want = refLayout.AbsoluteContentSize.Y + 30   -- + padding
		local width = math.min(440, w - 24)
		refPanel.Size = UDim2.new(0, width, 0, math.min(want, h - top - 16))
		refPanel.Position = UDim2.new(1, -(width + 12), 0, top + (h - top) / 2)
	end
	refLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	ScreenFit.watch(fit)
end

-- ─── F1 panel toggle ─────────────────────────────────────────────────────────

local _panelOpen = false

local function _togglePanel()
	_panelOpen = not _panelOpen
	if _panelOpen then
		refPanel.Visible = true
		refPanel.BackgroundTransparency = 1
		TweenService:Create(refPanel, TweenInfo.new(0.2), {
			BackgroundTransparency = 0.05
		}):Play()
	else
		TweenService:Create(refPanel, TweenInfo.new(0.2), {
			BackgroundTransparency = 1
		}):Play()
		task.delay(0.2, function() refPanel.Visible = false end)
	end
end

closeBtn.Activated:Connect(_togglePanel)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F1 or input.KeyCode == Enum.KeyCode.H then
		_togglePanel()
	end
end)

-- ─── Controls button (always visible, bottom-left) ───────────────────────────

local hintBtn = Instance.new("TextButton")
hintBtn.Name             = "HintButton"
hintBtn.Size             = UDim2.new(0, 120, 0, 28)
hintBtn.Position         = UDim2.new(0, 8, 1, -36)
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	-- phones: with SHOP / ITEMS at the top right, off the thumbstick's side
	-- (SideButtons); this screen ignores the top bar's inset
	local _, _, top = require(ReplicatedStorage.Shared.ScreenFit).view()
	hintBtn.Position = UDim2.new(1, -(264 + 120), 0, top + 8 + 6)
end
hintBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
hintBtn.BackgroundTransparency = 0.3
hintBtn.BorderSizePixel  = 0
hintBtn.Text             = _helpText(false)
hintBtn.TextScaled       = true
hintBtn.Font             = Enum.Font.Gotham
hintBtn.TextColor3       = Color3.fromRGB(180, 180, 220)
hintBtn.Parent           = screen

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius  = UDim.new(0, 7)
hintCorner.Parent        = hintBtn

hintBtn.Activated:Connect(_togglePanel)

-- ─── Key list (always on screen during a phase, left edge) ───────────────────
-- Keyboard players can always look a key up without opening anything; phones
-- and tablets have labelled buttons instead (TouchControls).

local strip = Instance.new("Frame")
strip.Name                   = "KeyStrip"
strip.AnchorPoint            = Vector2.new(0, 1)
strip.Position               = UDim2.new(0, 8, 1, -44)
strip.Size                   = UDim2.new(0, 170, 0, 0)
strip.AutomaticSize          = Enum.AutomaticSize.Y
strip.BackgroundColor3       = Color3.fromRGB(12, 12, 22)
strip.BackgroundTransparency = 0.45
strip.BorderSizePixel        = 0
strip.Visible                = false
strip.Parent                 = screen
Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 8)
local stripPad = Instance.new("UIPadding", strip)
stripPad.PaddingTop, stripPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
stripPad.PaddingLeft, stripPad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
local stripLayout = Instance.new("UIListLayout", strip)
stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
stripLayout.Padding   = UDim.new(0, 2)

local function _touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function _showStrip(phase)
	for _, c in ipairs(strip:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local guide = PHASE_GUIDES[phase]
	if not guide or phase == "CRAFTING" or _touchOnly() then
		strip.Visible = false
		return
	end
	for i, k in ipairs(_keysFor(guide)) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 17)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = strip
		local key = Instance.new("TextLabel")
		key.Size = UDim2.new(0, 92, 1, 0)
		key.BackgroundTransparency = 1
		key.Text = _keyText(k)
		key.TextScaled = true
		key.Font = Enum.Font.GothamBold
		key.TextColor3 = Color3.fromRGB(255, 220, 60)
		key.TextXAlignment = Enum.TextXAlignment.Right
		key.Parent = row
		local what = Instance.new("TextLabel")
		what.Size = UDim2.new(1, -100, 1, 0)
		what.Position = UDim2.new(0, 100, 0, 0)
		what.BackgroundTransparency = 1
		what.Text = k.short
		what.TextScaled = true
		what.Font = Enum.Font.Gotham
		what.TextColor3 = Color3.fromRGB(225, 225, 235)
		what.TextXAlignment = Enum.TextXAlignment.Left
		what.Parent = row
	end
	strip.Visible = true
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

-- the race trick key shows once the server says one is equipped
game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("RaceTrick"):Connect(function()
	local phase = game:GetService("ReplicatedStorage"):GetAttribute("Phase")
	if phase then _showStrip(phase) end
end)

-- The server sends the phase again after every respawn (SessionManager),
-- and this script restarts with the character: the same phase twice is that
-- resend, not a new phase. LocalPlayer "TutorialToastPhase" outlives the
-- restart, so the phase's toast shows once (it came back on every respawn).
local _lastPhase = nil
local function _onPhase(phase)
	if phase == _lastPhase then return end
	_lastPhase = phase
	_showStrip(phase)
	-- (Round, Phase): ReplicatedStorage "Round" counts the rounds (GameManager)
	local key = phase .. "#" .. tostring(game:GetService("ReplicatedStorage"):GetAttribute("Round"))
	local seen = LocalPlayer:GetAttribute("TutorialToastPhase") == key
	LocalPlayer:SetAttribute("TutorialToastPhase", key)
	if seen then return end
	-- Close reference panel on phase change
	if _panelOpen then _togglePanel() end
	task.wait(0.5)   -- slight delay so other UIs settle first
	if _lastPhase ~= phase then return end
	_showToast(phase)
end

RemoteEvents.PhaseChanged.OnClientEvent:Connect(_onPhase)

-- Joined (or respawned) mid-phase: show that phase's key list now.
local phaseNow = game:GetService("ReplicatedStorage"):GetAttribute("Phase")
if phaseNow then _showStrip(phaseNow) end

-- Switched between keyboard, gamepad and touch: name the controls again.
InputHints.onChange(function()
	hintBtn.Text = _helpText(false)
	toastDismiss.Text = _helpText(true)
	local phase = game:GetService("ReplicatedStorage"):GetAttribute("Phase")
	if phase then _showStrip(phase) end
end)
