-- TutorialUI/init.client.lua
-- Phase-specific control guide shown at the start of each phase.
-- Pressing F1 (or tapping the ? button) toggles the full reference panel.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Constants    = require(ReplicatedStorage.Shared.Constants)
local LocalPlayer  = Players.LocalPlayer

-- ─── Build screen ─────────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name           = "TutorialUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = true
screen.Parent         = LocalPlayer.PlayerGui

-- ─── Phase-specific guide data ───────────────────────────────────────────────

local PHASE_GUIDES = {
	FARMING = {
		title = "🌾  FARMING PHASE",
		colour = Color3.fromRGB(80, 180, 60),
		keys = {
			{ key = "E",        desc = "아이템 줍기 / 경쟁 연타" },
			{ key = "E (길게)", desc = "인벤토리 도둑질 시도 (0.9초)" },
			{ key = "E (빠르게×3)", desc = "도둑질 방어" },
			{ key = "Q (길게)",     desc = "이모트 메뉴 열기" },
		},
		tip = "아이콘과 이름이 표시된 아이템을 수집하세요!\n희귀도: 회색(Common) < 초록(Uncommon) < 파랑(Rare) < 보라(Epic)",
	},
	CRAFTING = {
		title = "🔧  CRAFTING PHASE",
		colour = Color3.fromRGB(200, 140, 40),
		keys = {
			{ key = "클릭 & 드래그", desc = "인벤토리 아이템을 슬롯에 배치" },
			{ key = "슬롯 클릭",     desc = "배치된 아이템 제거" },
			{ key = "COMBINE",      desc = "차량 조합 완료 (버튼 클릭)" },
		},
		tip = "BODY + ENGINE + SPECIAL 슬롯은 필수!\nMOBILITY(바퀴/돛/날개), HEAD, TAIL은 선택 슬롯입니다.",
	},
	RACING = {
		title = "🏎  RACING PHASE",
		colour = Color3.fromRGB(60, 140, 255),
		keys = {
			{ key = "W / ↑",      desc = "전진" },
			{ key = "S / ↓",      desc = "후진/감속" },
			{ key = "A / ←  D / →", desc = "조향" },
			{ key = "SHIFT",      desc = "부스트 발동 (게이지 필요)" },
			{ key = "SHIFT + 방향", desc = "드리프트 (속도 50% 이상)" },
			{ key = "E",          desc = "아이템 어빌리티 사용" },
		},
		tip = "드리프트 종료 시 순간 가속 보너스!\n부스트 패드(노란 패드)를 밟으면 추가 가속.",
	},
}

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
toastDismiss.Text          = "[ F1 ] 전체 조작 가이드 보기  •  잠시 후 자동으로 사라집니다"
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
	for i, k in ipairs(guide.keys) do
		_buildKeyRow(k.key, k.desc, i)
	end

	-- Animate in (slide down from top)
	toastFrame.Position = UDim2.new(0.5, -180, 0, 40)
	toastFrame.Visible  = true
	TweenService:Create(toastFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -180, 0, 80)
	}):Play()

	-- Auto-hide after 7s
	if _toastTimer then pcall(task.cancel, _toastTimer) end
	_toastTimer = task.delay(7, function()
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

local refPanel = Instance.new("Frame")
refPanel.Name             = "ReferencePanel"
refPanel.Size             = UDim2.new(0, 440, 0, 0)
refPanel.Position         = UDim2.new(1, -460, 0.5, 0)
refPanel.AnchorPoint      = Vector2.new(0, 0.5)
refPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 22)
refPanel.BackgroundTransparency = 0.05
refPanel.BorderSizePixel  = 0
refPanel.AutomaticSize    = Enum.AutomaticSize.Y
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
refTitle.Text            = "🎮  조작 가이드"
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
		badge.Text           = k.key
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
	if input.KeyCode == Enum.KeyCode.F1 then
		_togglePanel()
	end
end)

-- ─── F1 hint button (always visible, bottom-left) ────────────────────────────

local hintBtn = Instance.new("TextButton")
hintBtn.Name             = "HintButton"
hintBtn.Size             = UDim2.new(0, 90, 0, 28)
hintBtn.Position         = UDim2.new(0, 8, 1, -36)
hintBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
hintBtn.BackgroundTransparency = 0.3
hintBtn.BorderSizePixel  = 0
hintBtn.Text             = "[ F1 ] 도움말"
hintBtn.TextScaled       = true
hintBtn.Font             = Enum.Font.Gotham
hintBtn.TextColor3       = Color3.fromRGB(180, 180, 220)
hintBtn.Parent           = screen

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius  = UDim.new(0, 7)
hintCorner.Parent        = hintBtn

hintBtn.Activated:Connect(_togglePanel)

-- ─── Phase listener ───────────────────────────────────────────────────────────

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	-- Auto-show relevant toast
	task.wait(0.5)   -- slight delay so other UIs settle first
	_showToast(phase)

	-- Close reference panel on phase change
	if _panelOpen then _togglePanel() end
end)
