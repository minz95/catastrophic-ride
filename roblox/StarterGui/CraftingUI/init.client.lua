-- CraftingUI/init.client.lua
-- Crafting phase overlay: countdown timer, collected inventory display,
-- manual vehicle slot assignment, and a submit button.
-- Resolves: Issue #102, #111

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local ItemBlurbs   = require(ReplicatedStorage.Shared.ItemBlurbs)
local CraftingRules = require(ReplicatedStorage.Shared.CraftingRules)
local SoundFx      = require(ReplicatedStorage.Shared.SoundFx)
local LocalPlayer  = Players.LocalPlayer

-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so only one crafting
-- screen shows (Studio bots had two or three timers at once).
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "CraftingUI" and old:IsA("ScreenGui") then old:Destroy() end
end

-- ─── Screen ───────────────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name           = "CraftingUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = false
screen.Parent         = LocalPlayer.PlayerGui

-- ─── Panel ────────────────────────────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name                  = "Panel"
panel.Size                  = UDim2.new(0, 500, 0, 476)
panel.Position              = UDim2.new(0.5, -250, 0.5, -238)
panel.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel       = 0
panel.Parent                = screen
local _pc = Instance.new("UICorner"); _pc.CornerRadius = UDim.new(0, 14); _pc.Parent = panel

-- ─── Title ────────────────────────────────────────────────────────────────────

local title = Instance.new("TextLabel")
title.Size                  = UDim2.new(1, 0, 0, 44)
title.Position              = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text                  = "⚙ CRAFTING"
title.Font                  = Enum.Font.GothamBold
title.TextScaled            = true
title.TextColor3            = Color3.fromRGB(255, 200, 60)
title.Parent                = panel

-- ─── Timer ────────────────────────────────────────────────────────────────────

local timerLabel = Instance.new("TextLabel")
timerLabel.Name              = "TimerLabel"
timerLabel.Size              = UDim2.new(1, 0, 0, 26)
timerLabel.Position          = UDim2.new(0, 0, 0, 54)
timerLabel.BackgroundTransparency = 1
timerLabel.Text              = "..."   -- the time comes from PhaseEndsAt (_startTimer)
timerLabel.Font              = Enum.Font.GothamBold
timerLabel.TextScaled        = true
timerLabel.TextColor3        = Color3.fromRGB(80, 220, 80)
timerLabel.Parent            = panel

-- ─── Section label helper ─────────────────────────────────────────────────────

local function _sectionLabel(text, yPos)
	local lbl = Instance.new("TextLabel")
	lbl.Size                  = UDim2.new(1, -20, 0, 20)
	lbl.Position              = UDim2.new(0, 10, 0, yPos)
	lbl.BackgroundTransparency = 1
	lbl.Text                  = text
	lbl.Font                  = Enum.Font.GothamBold
	lbl.TextScaled            = false
	lbl.TextSize              = 12
	lbl.TextColor3            = Color3.fromRGB(180, 180, 180)
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.Parent                = panel
	return lbl
end

_sectionLabel("Your items", 86)

-- ─── Inventory row ────────────────────────────────────────────────────────────

local invFrame = Instance.new("Frame")
invFrame.Name                = "Inventory"
invFrame.Size                = UDim2.new(1, -20, 0, 66)
invFrame.Position            = UDim2.new(0, 10, 0, 110)
invFrame.BackgroundTransparency = 1
invFrame.ClipsDescendants    = true
invFrame.Parent              = panel

local _il = Instance.new("UIListLayout")
_il.FillDirection            = Enum.FillDirection.Horizontal
_il.VerticalAlignment        = Enum.VerticalAlignment.Center
_il.Padding                  = UDim.new(0, 4)
_il.Parent                   = invFrame

-- What the hovered / picked item does (cards show only icon and name).
local infoLbl = Instance.new("TextLabel")
infoLbl.Name              = "ItemInfo"
infoLbl.Size              = UDim2.new(1, -20, 0, 26)
infoLbl.Position          = UDim2.new(0, 10, 0, 180)
infoLbl.BackgroundTransparency = 1
infoLbl.Font              = Enum.Font.Gotham
infoLbl.TextScaled        = false
infoLbl.TextSize          = 11
infoLbl.TextWrapped       = true
infoLbl.TextXAlignment    = Enum.TextXAlignment.Left
infoLbl.TextYAlignment    = Enum.TextYAlignment.Top
infoLbl.TextColor3        = Color3.fromRGB(220, 220, 235)
infoLbl.Parent            = panel

local INFO_DEFAULT = "Point at an item to see what it does"
local function _showInfo(itemName)
	local cfg = itemName and ItemConfig[itemName]
	if not cfg then
		infoLbl.Text = INFO_DEFAULT
		infoLbl.TextColor3 = Color3.fromRGB(130, 130, 150)
		return
	end
	infoLbl.Text = string.format("%s %s (%s)  ·  %s", cfg.icon or "", itemName, cfg.rarity or "", ItemBlurbs.line(itemName, cfg))
	infoLbl.TextColor3 = Color3.fromRGB(220, 220, 235)
end
_showInfo(nil)

-- ─── Slot section header + auto-assign button ─────────────────────────────────

_sectionLabel("Vehicle slots", 212)

local autoBtn = Instance.new("TextButton")
autoBtn.Size              = UDim2.new(0, 90, 0, 20)
autoBtn.Position          = UDim2.new(1, -100, 0, 212)
autoBtn.BackgroundColor3  = Color3.fromRGB(50, 80, 140)
autoBtn.BorderSizePixel   = 0
autoBtn.Text              = "Auto fill"
autoBtn.Font              = Enum.Font.Gotham
autoBtn.TextScaled        = false
autoBtn.TextSize          = 11
autoBtn.TextColor3        = Color3.new(1, 1, 1)
autoBtn.Parent            = panel
local _abc = Instance.new("UICorner"); _abc.CornerRadius = UDim.new(0, 6); _abc.Parent = autoBtn

-- hint below slots
local hintLbl = Instance.new("TextLabel")
hintLbl.Size              = UDim2.new(1, -20, 0, 16)
hintLbl.Position          = UDim2.new(0, 10, 0, 348)
hintLbl.BackgroundTransparency = 1
hintLbl.Text              = "Pick an item → click a slot to place it | click a slot (nothing picked) → clear it"
hintLbl.Font              = Enum.Font.Gotham
hintLbl.TextScaled        = false
hintLbl.TextSize          = 10
hintLbl.TextColor3        = Color3.fromRGB(130, 130, 150)
hintLbl.Parent            = panel

-- ─── Slots row ────────────────────────────────────────────────────────────────

local slotsFrame = Instance.new("Frame")
slotsFrame.Name              = "Slots"
slotsFrame.Size              = UDim2.new(1, -20, 0, 94)
slotsFrame.Position          = UDim2.new(0, 10, 0, 236)
slotsFrame.BackgroundTransparency = 1
slotsFrame.ClipsDescendants  = true
slotsFrame.Parent            = panel

local _sl = Instance.new("UIListLayout")
_sl.FillDirection            = Enum.FillDirection.Horizontal
_sl.VerticalAlignment        = Enum.VerticalAlignment.Center
_sl.Padding                  = UDim.new(0, 4)
_sl.Parent                   = slotsFrame

local SLOT_ORDER  = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }
local SLOT_KR     = { BODY="Body", ENGINE="Engine", SPECIAL="Special", MOBILITY="Mobility", HEAD="Head", TAIL="Tail" }

local C_SLOT_EMPTY   = Color3.fromRGB(28,  28,  48)
local C_SLOT_FILLED  = Color3.fromRGB(45,  45,  72)
local C_SLOT_TARGET  = Color3.fromRGB(70,  60,  20)   -- when item selected, hoverable
local C_INV_NORMAL   = Color3.fromRGB(35,  35,  58)
local C_INV_SELECTED = Color3.fromRGB(90,  70,  15)
local C_INV_USED     = Color3.fromRGB(22,  22,  38)

local RARITY_COLOUR = {
	Common   = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(80,  200,  80),
	Rare     = Color3.fromRGB(100, 160, 255),
	Epic     = Color3.fromRGB(200, 100, 255),
}

local slotBtns     = {}  -- { [slotName] = TextButton }
local slotItemLbls = {}  -- { [slotName] = TextLabel }

for _, slotName in ipairs(SLOT_ORDER) do
	local btn = Instance.new("TextButton")
	btn.Name             = slotName
	btn.Size             = UDim2.new(0, 74, 1, 0)
	btn.BackgroundColor3 = C_SLOT_EMPTY
	btn.BorderSizePixel  = 0
	btn.Text             = ""
	btn.AutoButtonColor  = false
	btn.Parent           = slotsFrame
	local _sfc = Instance.new("UICorner"); _sfc.CornerRadius = UDim.new(0, 6); _sfc.Parent = btn

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size             = UDim2.new(1, 0, 0.30, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text             = SLOT_KR[slotName]
	nameLbl.Font             = Enum.Font.Gotham
	nameLbl.TextScaled       = false
	nameLbl.TextSize         = 11
	nameLbl.TextColor3       = Color3.fromRGB(140, 140, 160)
	nameLbl.Parent           = btn

	local itemLbl = Instance.new("TextLabel")
	itemLbl.Name             = "Item"
	itemLbl.Size             = UDim2.new(1, -4, 0.70, 0)
	itemLbl.Position         = UDim2.new(0, 2, 0.30, 0)
	itemLbl.BackgroundTransparency = 1
	itemLbl.Text             = "—"
	itemLbl.Font             = Enum.Font.GothamBold
	itemLbl.TextScaled       = false
	itemLbl.TextSize         = 10
	itemLbl.TextWrapped      = true
	itemLbl.TextColor3       = Color3.fromRGB(100, 100, 120)
	itemLbl.Parent           = btn

	slotBtns[slotName]     = btn
	slotItemLbls[slotName] = itemLbl
end

-- ─── Submit button ────────────────────────────────────────────────────────────

local submitBtn = Instance.new("TextButton")
submitBtn.Size              = UDim2.new(0, 220, 0, 48)
submitBtn.Position          = UDim2.new(0.5, -110, 1, -64)
submitBtn.BackgroundColor3  = Color3.fromRGB(60, 200, 80)
submitBtn.BorderSizePixel   = 0
submitBtn.Text              = "Submit"
submitBtn.Font              = Enum.Font.GothamBold
submitBtn.TextScaled        = true
submitBtn.TextColor3        = Color3.new(1, 1, 1)
submitBtn.Parent            = panel
local _btc = Instance.new("UICorner"); _btc.CornerRadius = UDim.new(0, 10); _btc.Parent = submitBtn

local emptyNote = Instance.new("TextLabel")
emptyNote.Size              = UDim2.new(1, -20, 0, 18)
emptyNote.Position          = UDim2.new(0, 10, 1, -38)
emptyNote.BackgroundTransparency = 1
emptyNote.Text              = "No items → you get a basic junk vehicle"
emptyNote.Font              = Enum.Font.Gotham
emptyNote.TextScaled        = false
emptyNote.TextSize          = 11
emptyNote.TextColor3        = Color3.fromRGB(180, 120, 60)
emptyNote.Visible           = false
emptyNote.Parent            = panel

-- ─── State ────────────────────────────────────────────────────────────────────

local _submitted        = false
local _currentInventory = {}
local _assignments      = {}   -- { [slotName] = itemName }
local _selectedItem     = nil  -- currently highlighted inventory item

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function _usedSet()
	local s = {}
	for _, name in pairs(_assignments) do s[name] = true end
	return s
end

local function _slotOf(itemName)
	for slotName, name in pairs(_assignments) do
		if name == itemName then return slotName end
	end
	return nil
end

-- ─── Display refresh ─────────────────────────────────────────────────────────

local function _refreshSlots()
	local hasSelected = _selectedItem ~= nil
	for _, slotName in ipairs(SLOT_ORDER) do
		local btn  = slotBtns[slotName]
		local lbl  = slotItemLbls[slotName]
		local item = _assignments[slotName]
		if item then
			local cfg = ItemConfig[item]
			lbl.Text       = ((cfg and cfg.icon) or "") .. " " .. item
			lbl.TextColor3 = RARITY_COLOUR[(cfg and cfg.rarity) or "Common"]
			btn.BackgroundColor3 = C_SLOT_FILLED
		else
			lbl.Text       = "—"
			lbl.TextColor3 = Color3.fromRGB(100, 100, 120)
			btn.BackgroundColor3 = hasSelected and C_SLOT_TARGET or C_SLOT_EMPTY
		end
	end
end

local _changed   -- defined after _refreshDisplay (its click handlers call it)

local function _refreshDisplay()
	emptyNote.Visible = (#_currentInventory == 0)
	-- Rebuild inventory row
	for _, child in ipairs(invFrame:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end

	local used = _usedSet()
	for _, itemName in ipairs(_currentInventory) do
		local cfg        = ItemConfig[itemName]
		local isUsed     = used[itemName] == true
		local isSelected = (_selectedItem == itemName)

		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(0, 56, 1, 0)
		btn.BackgroundColor3 = isSelected and C_INV_SELECTED or (isUsed and C_INV_USED or C_INV_NORMAL)
		btn.BorderSizePixel  = 0
		btn.Text             = ""
		btn.AutoButtonColor  = false
		btn.Parent           = invFrame
		local _bc = Instance.new("UICorner"); _bc.CornerRadius = UDim.new(0, 6); _bc.Parent = btn

		if isSelected then
			local stroke = Instance.new("UIStroke")
			stroke.Color     = Color3.fromRGB(255, 200, 60)
			stroke.Thickness = 2
			stroke.Parent    = btn
		end

		local icon = Instance.new("TextLabel")
		icon.Size            = UDim2.new(1, 0, 0.52, 0)
		icon.BackgroundTransparency = 1
		icon.Text            = (cfg and cfg.icon) or "?"
		icon.TextScaled      = true
		icon.Font            = Enum.Font.GothamBold
		icon.TextColor3      = isUsed and Color3.fromRGB(80, 80, 80) or Color3.new(1, 1, 1)
		icon.Parent          = btn

		local lbl = Instance.new("TextLabel")
		lbl.Size             = UDim2.new(1, 0, 0.48, 0)
		lbl.Position         = UDim2.new(0, 0, 0.52, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text             = itemName
		lbl.TextScaled       = false
		lbl.TextSize         = 9
		lbl.TextWrapped      = true
		lbl.Font             = Enum.Font.Gotham
		lbl.TextColor3       = isUsed
			and Color3.fromRGB(80, 80, 80)
			or RARITY_COLOUR[(cfg and cfg.rarity) or "Common"]
		lbl.Parent           = btn

		-- which slot it fits (core slots take only their own type)
		local tag = Instance.new("TextLabel")
		tag.Size             = UDim2.new(1, -4, 0, 10)
		tag.Position         = UDim2.new(0, 2, 0, 1)
		tag.BackgroundTransparency = 1
		tag.Text             = cfg and cfg.slotType or ""
		tag.TextSize         = 8
		tag.Font             = Enum.Font.GothamBold
		tag.TextXAlignment   = Enum.TextXAlignment.Left
		tag.TextColor3       = Color3.fromRGB(150, 150, 175)
		tag.ZIndex           = 2
		tag.Parent           = btn

		btn.MouseEnter:Connect(function() _showInfo(itemName) end)
		btn.MouseLeave:Connect(function() _showInfo(_selectedItem) end)

		-- Click handler
		local capturedName = itemName
		btn.MouseButton1Click:Connect(function()
			if _submitted then return end
			if isUsed then
				-- Remove from slot → back to free
				local slot = _slotOf(capturedName)
				if slot then _assignments[slot] = nil end
				_selectedItem = nil
			elseif _selectedItem == capturedName then
				_selectedItem = nil   -- deselect
			else
				_selectedItem = capturedName
			end
			_showInfo(_selectedItem or capturedName)
			_changed()
		end)
	end

	_refreshSlots()
end

-- After the player changes a slot: redraw, and tell the server the
-- arrangement so far (CraftingManager keeps it if the timer runs out before
-- Submit). Only on real changes, so a redraw never sends an empty draft.
_changed = function()
	_refreshDisplay()
	if screen.Enabled and not _submitted then
		RemoteEvents.CraftDraft:FireServer(_assignments)
		SoundFx.play("SLOT_ASSIGN")
	end
end

-- ─── Slot click handlers ──────────────────────────────────────────────────────

for _, slotName in ipairs(SLOT_ORDER) do
	local capturedSlot = slotName
	slotBtns[slotName].MouseButton1Click:Connect(function()
		if _submitted then return end
		local current = _assignments[capturedSlot]  -- item already in this slot
		if _selectedItem then
			-- Assign selected item to this slot
			-- If selected item was in another slot, clear that slot first
			local prevSlot = _slotOf(_selectedItem)
			if prevSlot then _assignments[prevSlot] = nil end
			-- If slot was occupied, make that item free (it stays in inventory unassigned)
			_assignments[capturedSlot] = _selectedItem
			_selectedItem = nil
		elseif current then
			-- Nothing selected — clicking a filled slot clears it
			_assignments[capturedSlot] = nil
		end
		_changed()
	end)
end

-- ─── Auto-assign button ───────────────────────────────────────────────────────

autoBtn.MouseButton1Click:Connect(function()
	if _submitted then return end
	-- each core slot gets an item of its own type (filling in inventory
	-- order put e.g. an ENGINE in BODY, and the server dropped it)
	_assignments  = CraftingRules.autoSlots(_currentInventory, ItemConfig)
	_selectedItem = nil
	_changed()
end)

-- ─── Submit ───────────────────────────────────────────────────────────────────

submitBtn.MouseButton1Click:Connect(function()
	if _submitted then return end
	local ok, result = pcall(function()
		return RemoteEvents.SubmitCraft:InvokeServer(_assignments)
	end)
	if ok and (result == "ok" or (type(result) == "string" and result:sub(1, 2) == "ok")) then
		_submitted                 = true
		SoundFx.play("CRAFT_COMPLETE")
		submitBtn.Text             = "✓ Submitted"
		submitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	end
end)

-- ─── Inventory sync ───────────────────────────────────────────────────────────

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inventory)
	_currentInventory = inventory
	if screen.Enabled then
		_refreshDisplay()
	end
end)

-- ─── Timer ────────────────────────────────────────────────────────────────────

local _runConn   = nil

local function _startTimer()
	if _runConn then _runConn:Disconnect() end
	local function update()
		-- no time until the server's PhaseEndsAt has arrived (no guessed duration)
		local remaining = PhaseClock.remaining(nil)
		if not remaining then
			timerLabel.Text = "..."
			return
		end
		timerLabel.Text = PhaseClock.format(remaining)
		timerLabel.TextColor3 = remaining <= 15
			and Color3.fromRGB(255, 60, 60)
			or  Color3.fromRGB(80, 220, 80)
	end
	update()   -- right away: the label still says "2:00" until the first frame
	_runConn = RunService.Heartbeat:Connect(function()
		if screen.Enabled then update() end
	end)
end

-- ─── Slot guide overlay (right side, auto-fades) ─────────────────────────────

local guideBg = Instance.new("Frame")
guideBg.Name                  = "SlotGuide"
guideBg.Size                  = UDim2.new(0, 180, 0, 200)
guideBg.Position              = UDim2.new(1, 20, 0.5, -100)
guideBg.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
guideBg.BackgroundTransparency = 0.15
guideBg.BorderSizePixel       = 0
guideBg.Visible               = false
guideBg.Parent                = screen
local _gc = Instance.new("UICorner"); _gc.CornerRadius = UDim.new(0, 12); _gc.Parent = guideBg

local guideTitle = Instance.new("TextLabel")
guideTitle.Size               = UDim2.new(1, -12, 0, 26)
guideTitle.Position           = UDim2.new(0, 6, 0, 6)
guideTitle.BackgroundTransparency = 1
guideTitle.Text               = "Slot guide"
guideTitle.Font               = Enum.Font.GothamBold
guideTitle.TextScaled         = false
guideTitle.TextSize           = 13
guideTitle.TextColor3         = Color3.fromRGB(255, 200, 60)
guideTitle.TextXAlignment     = Enum.TextXAlignment.Left
guideTitle.Parent             = guideBg

local GUIDE_ROWS = {
	{ hint = "Body — weight, stability" },
	{ hint = "Engine — power, acceleration" },
	{ hint = "Special — boost" },
	{ hint = "Mobility — biome handling" },
	{ hint = "Head — collision passive" },
	{ hint = "Tail — rear passive" },
}
for i, row in ipairs(GUIDE_ROWS) do
	local r = Instance.new("TextLabel")
	r.Size                = UDim2.new(1, -12, 0, 24)
	r.Position            = UDim2.new(0, 6, 0, 26 + (i - 1) * 26)
	r.BackgroundTransparency = 1
	r.Text                = row.hint
	r.Font                = Enum.Font.Gotham
	r.TextScaled          = false
	r.TextSize            = 11
	r.TextColor3          = Color3.fromRGB(200, 200, 220)
	r.TextXAlignment      = Enum.TextXAlignment.Left
	r.Parent              = guideBg
end

local function _showGuide()
	guideBg.Position              = UDim2.new(1, 20, 0.5, -100)
	guideBg.BackgroundTransparency = 0.15
	for _, child in ipairs(guideBg:GetChildren()) do
		if child:IsA("TextLabel") then child.TextTransparency = 0 end
	end
	guideBg.Visible = true
	TweenService:Create(guideBg, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -196, 0.5, -100)
	}):Play()
	task.delay(5, function()
		if not screen.Enabled then guideBg.Visible = false return end
		TweenService:Create(guideBg, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, child in ipairs(guideBg:GetChildren()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
		end
		task.delay(0.45, function() guideBg.Visible = false end)
	end)
end

-- ─── Phase gate ───────────────────────────────────────────────────────────────

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.CRAFTING then
		_submitted              = false
		_assignments            = {}
		_selectedItem           = nil
		submitBtn.Text          = "Submit"
		submitBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
		_showInfo(nil)
		_refreshDisplay()
		screen.Enabled = true
		_startTimer()
		_showGuide()
	else
		screen.Enabled = false
		if _runConn then _runConn:Disconnect(); _runConn = nil end
	end
end)
