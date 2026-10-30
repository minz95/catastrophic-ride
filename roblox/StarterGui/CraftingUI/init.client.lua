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
local HttpService  = game:GetService("HttpService")
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
panel.Position              = UDim2.new(0.5, -405, 0.5, -238)   -- the showroom sits on its right
panel.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
panel.BackgroundTransparency = 0   -- opaque: the tutorial guide behind it showed through
panel.BorderSizePixel       = 0
panel.Parent                = screen
local _pc = Instance.new("UICorner"); _pc.CornerRadius = UDim.new(0, 14); _pc.Parent = panel

-- ─── Title ────────────────────────────────────────────────────────────────────

local title = Instance.new("TextLabel")
-- the middle only: ITEMS (left) and SHOP (right) buttons sit in the corners
title.Size                  = UDim2.new(1, -240, 0, 44)
title.Position              = UDim2.new(0, 120, 0, 8)
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

-- Wording follows the device in use (InputHints.onChange below): fixed when
-- the screen was built, it said "click" on a phone in Studio's simulator.
local _InputHints = require(ReplicatedStorage.Shared.InputHints)
local function _infoDefault()
	return _InputHints.touchUI() and "Tap an item to see what it does" or "Point at an item to see what it does"
end
local _infoItem = nil
local function _showInfo(itemName)
	_infoItem = itemName
	local cfg = itemName and ItemConfig[itemName]
	if not cfg then
		infoLbl.Text = _infoDefault()
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
-- 110 × 24: at 90 × 20 it was a 59 × 13 px target on a phone
autoBtn.Size              = UDim2.new(0, 110, 0, 24)
autoBtn.Position          = UDim2.new(1, -120, 0, 210)
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
local function _hintText()
	return _InputHints.touchUI() and "Tap an item, then a slot to place it | tap a slot (nothing picked) to clear it"
		or "Pick an item → click a slot to place it | click a slot (nothing picked) → clear it"
end
hintLbl.Text              = _hintText()
_InputHints.onChange(function()
	hintLbl.Text = _hintText()
	if not _infoItem then _showInfo(nil) end
end)
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
local C_SLOT_NO      = Color3.fromRGB(22,  20,  28)   -- the selected item cannot go here
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
emptyNote.Position          = UDim2.new(0, 10, 1, -86)   -- above Submit (it sat behind it)
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
		-- with an item picked: the slots it fits light up, the rest go dark
		local fits = hasSelected and CraftingRules.fits(slotName, ItemConfig[_selectedItem])
		if item then
			local cfg = ItemConfig[item]
			lbl.Text       = ((cfg and cfg.icon) or "") .. " " .. item
			lbl.TextColor3 = RARITY_COLOUR[(cfg and cfg.rarity) or "Common"]
			btn.BackgroundColor3 = (hasSelected and not fits) and C_SLOT_NO or C_SLOT_FILLED
		else
			lbl.Text       = "—"
			lbl.TextColor3 = Color3.fromRGB(100, 100, 120)
			btn.BackgroundColor3 = hasSelected and (fits and C_SLOT_TARGET or C_SLOT_NO) or C_SLOT_EMPTY
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

		-- which slot it fits (core slots take only their own type; RIDE: Body too)
		local tag = Instance.new("TextLabel")
		tag.Size             = UDim2.new(1, -4, 0, 10)
		tag.Position         = UDim2.new(0, 2, 0, 1)
		tag.BackgroundTransparency = 1
		tag.Text             = cfg and (cfg.slotType .. ((cfg.ride and cfg.slotType ~= "BODY") and " · RIDE" or "")) or ""
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
-- The draft lives on the LocalPlayer too (local attributes, not
-- replicated): this script restarts with every respawn, and a respawn
-- mid-CRAFTING emptied the slots and forgot a Submit.
local function _saveDraft()
	pcall(function()
		LocalPlayer:SetAttribute("CraftDraftSlots", HttpService:JSONEncode(_assignments))
		LocalPlayer:SetAttribute("CraftDraftSubmitted", _submitted or nil)
	end)
end

_changed = function()
	_refreshDisplay()
	_saveDraft()
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
		if _selectedItem and not CraftingRules.fits(capturedSlot, ItemConfig[_selectedItem]) then
			-- the server would drop it (CraftingRules.validate) and the car would
			-- not change: say why instead (playtest 2026-10-28: "it goes into
			-- Body but the body does not become it")
			infoLbl.Text = CraftingRules.whyNot(capturedSlot, _selectedItem, ItemConfig[_selectedItem])
			infoLbl.TextColor3 = Color3.fromRGB(255, 140, 110)
			SoundFx.play("CONTEST_LOSE")
			return
		elseif _selectedItem then
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
		_saveDraft()
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
	-- only with room right of the showroom (in a window under ~1180 px it
	-- covered the car: Studio ui-layout 2026-10-30); the slots' own labels
	-- and the info line say the same
	local sr = screen:FindFirstChild("Showroom")
	if sr and sr.AbsolutePosition.X + sr.AbsoluteSize.X + 196 > screen.AbsoluteSize.X then return end
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

-- ─── Showroom: the vehicle these slots build, turning slowly ────────────────
-- The server (Modules/CraftPreview) puts a still copy of the vehicle in
-- PlayerGui.CraftPreview on every slot change; it is shown here with the
-- player's avatar seated, turning like a shop window. Drag to turn it.

local UserInputService = game:GetService("UserInputService")

local showroom = Instance.new("Frame")
showroom.Name                  = "Showroom"
showroom.Size                  = UDim2.new(0, 300, 0, 476)
showroom.Position              = UDim2.new(0.5, 105, 0.5, -238)
showroom.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
showroom.BackgroundTransparency = 0.12
showroom.BorderSizePixel       = 0
showroom.Parent                = screen
local _src = Instance.new("UICorner"); _src.CornerRadius = UDim.new(0, 14); _src.Parent = showroom

-- ─── Fit the screen ───────────────────────────────────────────────────────────
-- Panel + showroom are 810 × 476 px: on a phone (≈ 844 × 390) the title row
-- and the Submit button were cut off. Both shrink together (a UIScale each,
-- positions moved to match) to fit the viewport with 16 px to spare.
local STAGE_W, STAGE_H = 810, 476
local _panelScale = Instance.new("UIScale"); _panelScale.Parent = panel
local _showScale  = Instance.new("UIScale"); _showScale.Parent = showroom
-- The screen ignores the top bar's inset, so the stage is centred in the
-- room under it (centred on the whole screen, its ITEMS button sat under
-- Roblox's menu buttons on a phone).
local ScreenFit = require(ReplicatedStorage.Shared.ScreenFit)
local _readable = ScreenFit.keepReadable(panel, function() return _panelScale.Scale end, 9)
ScreenFit.watch(function()
	local k, _, h, top = ScreenFit.scale(STAGE_W, STAGE_H, 8)
	k = math.max(0.3, k)
	_panelScale.Scale = k
	_readable()
	_showScale.Scale  = k
	local midY = top + (h - top) / 2
	panel.Position    = UDim2.new(0.5, -405 * k, 0, midY - 238 * k)
	showroom.Position = UDim2.new(0.5, 105 * k, 0, midY - 238 * k)
end)

local showTitle = Instance.new("TextLabel")
showTitle.Size                  = UDim2.new(1, -20, 0, 30)
showTitle.Position              = UDim2.new(0, 10, 0, 10)
showTitle.BackgroundTransparency = 1
showTitle.Text                  = "Your ride"
showTitle.Font                  = Enum.Font.GothamBold
showTitle.TextScaled            = true
showTitle.TextColor3            = Color3.fromRGB(255, 200, 60)
showTitle.Parent                = showroom

local view = Instance.new("ViewportFrame")
view.Name                  = "View"
view.Size                  = UDim2.new(1, -20, 1, -96)
view.Position              = UDim2.new(0, 10, 0, 46)
view.BackgroundColor3      = Color3.fromRGB(40, 46, 70)
view.BorderSizePixel       = 0
view.Ambient               = Color3.fromRGB(150, 150, 165)
view.LightColor            = Color3.fromRGB(255, 250, 240)
view.LightDirection        = Vector3.new(-0.6, -1, -0.4)
view.Parent                = showroom
local _vc = Instance.new("UICorner"); _vc.CornerRadius = UDim.new(0, 10); _vc.Parent = view
local _vg = Instance.new("UIGradient")
_vg.Color = ColorSequence.new(Color3.fromRGB(120, 140, 200), Color3.fromRGB(40, 40, 60))
_vg.Rotation = 90
_vg.Parent = view

local viewCam = Instance.new("Camera")
viewCam.FieldOfView = 40
viewCam.Parent = view
view.CurrentCamera = viewCam

local showNote = Instance.new("TextLabel")
showNote.Size                  = UDim2.new(1, -20, 0, 40)
showNote.Position              = UDim2.new(0, 10, 1, -46)
showNote.BackgroundTransparency = 1
showNote.Text                  = ""
showNote.Font                  = Enum.Font.Gotham
showNote.TextSize              = 12
showNote.TextWrapped           = true
showNote.TextColor3            = Color3.fromRGB(200, 200, 220)
showNote.Parent                = showroom

local KIND = { FOREST = "car", OCEAN = "boat", SKY = "plane" }
local _shown, _centre, _dist = nil, Vector3.zero, 12
local _angle = math.rad(35)
local _dragging, _dragX = false, 0

-- Bends a joint by `rot` around the joint (Motor6D, or the AnimationConstraint
-- some avatars use; see FarmFx).
local function _bend(char, jointName, rot)
	local j = char:FindFirstChild(jointName, true)
	local obj, prop
	if j and j:IsA("Motor6D") then obj, prop = j, "C0"
	elseif j and j:IsA("AnimationConstraint") and j.Attachment0 then obj, prop = j.Attachment0, "CFrame"
	else return end
	local c0 = obj[prop]
	local pos = c0.Position
	obj[prop] = CFrame.new(pos) * rot * (c0 - pos)
end

-- A still copy of the player's avatar, sitting on `seat`.
local function _rider(seat, parent)
	local char = LocalPlayer.Character
	if not char then return end
	local was = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not copy then return end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ForceField") or d:IsA("Sound") then d:Destroy() end
	end
	local root = copy:FindFirstChild("HumanoidRootPart")
	if not root then copy:Destroy() return end
	root.Anchored = true
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	local q = math.pi / 2
	_bend(copy, "LeftHip", CFrame.Angles(q, 0, 0))
	_bend(copy, "RightHip", CFrame.Angles(q, 0, 0))
	_bend(copy, "LeftKnee", CFrame.Angles(-q, 0, 0))
	_bend(copy, "RightKnee", CFrame.Angles(-q, 0, 0))
	_bend(copy, "LeftShoulder", CFrame.Angles(q * 0.6, 0, 0))
	_bend(copy, "RightShoulder", CFrame.Angles(q * 0.6, 0, 0))
	copy:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + root.Size.Y / 2, 0))
	copy.Parent = parent
	return copy
end

-- The HEAD item is worn as a hat (VehicleBuilder.wearHat): onto the copy's head.
local function _wearHat(vehicle, rider)
	local head = rider and rider:FindFirstChild("Head")
	if not head then return end
	for _, c in ipairs(vehicle:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") and c.PrimaryPart then
			local base = c.PrimaryPart.Size.Y / 2
			c:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - (c:GetAttribute("HatSink") or 0) + base, 0))
		end
	end
end

-- Spinning MOBILITY items (wheels, paddle wheels, propellers) turn in the
-- showroom as if driving gently: the parts tagged SpinHub by CraftPreview.
local SHOW_SPEED = 14   -- studs/s the wheels roll at
local _spins = {}
local function _collectSpins(copy)
	_spins = {}
	local byHub = {}
	for _, p in ipairs(copy:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name:sub(1, 8) == "SpinHub_" then
				byHub[p.Name] = byHub[p.Name] or { members = {} }
				byHub[p.Name].hub = p
			elseif p:GetAttribute("SpinHub") then
				byHub[p:GetAttribute("SpinHub")] = byHub[p:GetAttribute("SpinHub")] or { members = {} }
				table.insert(byHub[p:GetAttribute("SpinHub")].members, p)
			end
		end
	end
	for _, g in pairs(byHub) do
		if g.hub and #g.members > 0 then
			local base = g.hub.CFrame
			local rel = {}
			for _, p in ipairs(g.members) do rel[p] = base:ToObjectSpace(p.CFrame) end
			local rate
			if g.hub:GetAttribute("SpinMode") == "prop" then rate = 10 * (g.hub:GetAttribute("SpinDir") or 1)
			else rate = -SHOW_SPEED / math.max(g.hub:GetAttribute("SpinRadius") or 1, 0.1) end
			table.insert(_spins, { base = base, rel = rel, rate = rate, angle = 0,
				axisZ = g.hub:GetAttribute("SpinAxis") == "Z" })
		end
	end
end
local _spinReport = 0
local function _turnSpins(dt)
	-- harness bots report what turns (sim.py showroom check)
	if LocalPlayer:GetAttribute("HarnessBot") and os.clock() - _spinReport > 2 then
		_spinReport = os.clock()
		local ch = ReplicatedStorage:FindFirstChild("HarnessChannel")
		local turned = 0
		for _, sp in ipairs(_spins) do turned += sp.turned or 0 end
		if ch then ch:FireServer("showroom_spin", { groups = #_spins, turned = math.floor(turned) }) end
	end
	for _, sp in ipairs(_spins) do
		sp.turned = (sp.turned or 0) + math.abs(sp.rate * dt)
		sp.angle = (sp.angle + sp.rate * dt) % (2 * math.pi)
		local turn = sp.base * (sp.axisZ and CFrame.Angles(0, 0, sp.angle) or CFrame.Angles(sp.angle, 0, 0))
		for p, rel in pairs(sp.rel) do p.CFrame = turn * rel end
	end
end

local _world = nil
local function _show(model)
	if _world then _world:Destroy() end
	local copy = model:Clone()
	if not copy then return end
	-- a WorldModel lets the avatar's joints pose the limbs
	local world = Instance.new("WorldModel")
	world.Parent = view
	_world = world
	copy.Parent = world
	pcall(_collectSpins, copy)
	local seat = copy:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat then
		local ok, rider = pcall(_rider, seat, world)
		if ok and rider then pcall(_wearHat, copy, rider) end
	end
	local vcf, vsize = copy:GetBoundingBox()   -- the vehicle (the plinth goes under it)
	local cf, size = world:GetBoundingBox()    -- vehicle and rider (the framing)
	-- a round plinth under it, like a shop window
	local plinth = Instance.new("Part")
	plinth.Shape = Enum.PartType.Cylinder
	plinth.Anchored = true
	local r = math.max(vsize.X, vsize.Z) * 0.62 + 1
	plinth.Size = Vector3.new(0.4, r * 2, r * 2)
	plinth.CFrame = CFrame.new(vcf.Position.X, vcf.Position.Y - vsize.Y / 2 - 0.25, vcf.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	plinth.Color = Color3.fromRGB(60, 62, 80)
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Parent = world
	_centre = cf.Position - Vector3.new(0, size.Y * 0.08, 0)
	local radius = math.max(size.Magnitude / 2, 3)
	-- the view is taller than wide: fit the width (horizontal half-angle)
	local aspect = math.max(view.AbsoluteSize.X, 1) / math.max(view.AbsoluteSize.Y, 1)
	local half = math.atan(math.tan(math.rad(viewCam.FieldOfView / 2)) * math.min(aspect, 1))
	_dist = radius / math.tan(half) * 1.05
	_shown = copy
	local biome = model:GetAttribute("Biome")
	local riding = model:GetAttribute("Riding")
	showTitle.Text = "Your " .. (KIND[biome] or "ride")
	showNote.Text = riding and ("Riding your " .. riding .. "  ·  drag to turn")
		or "Put an item in Body to ride it  ·  drag to turn"
end

-- Shows `m` once all its parts are here (attribute Parts, CraftPreview),
-- or after 3 s whatever arrived; a newer preview replaces a waiting one.
local _latest = nil
local function _showWhenWhole(m)
	_latest = m
	local want = m:GetAttribute("Parts") or 0
	local t0 = os.clock()
	while m.Parent and _latest == m and os.clock() - t0 < 3 do
		local n = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
		end
		if n >= want then break end
		task.wait(0.05)
	end
	if _latest == m and m.Parent then _show(m) end
end

local function _watch(folder)
	folder.ChildAdded:Connect(function(m)
		if m:IsA("Model") then task.spawn(_showWhenWhole, m) end
	end)
	local m = folder:FindFirstChildWhichIsA("Model")
	if m then task.spawn(_showWhenWhole, m) end
end
local _pf = LocalPlayer.PlayerGui:FindFirstChild("CraftPreview")
if _pf then _watch(_pf) end
LocalPlayer.PlayerGui.ChildAdded:Connect(function(c)
	if c.Name == "CraftPreview" and c:IsA("Folder") then _watch(c) end
end)

view.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		_dragging, _dragX = true, input.Position.X
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if _dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		_angle -= (input.Position.X - _dragX) * 0.012
		_dragX = input.Position.X
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		_dragging = false
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not screen.Enabled or not _shown then return end
	if not _dragging then _angle += dt * 0.55 end   -- about one turn in 11 s
	_turnSpins(dt)
	local eye = _centre + Vector3.new(math.sin(_angle) * _dist, _dist * 0.38, math.cos(_angle) * _dist)
	viewCam.CFrame = CFrame.lookAt(eye, _centre)
end)

-- ─── Phase gate ───────────────────────────────────────────────────────────────

-- The server sends the phase again after a respawn (SessionManager) and
-- this script reads it at start: the same phase twice is that resend (a
-- round always moves on to another phase). LocalPlayer "CraftingOpen" (the
-- Round) says this CRAFTING phase was already entered by an earlier run of this script
-- (before a respawn): then the saved draft comes back instead of a reset.
local _lastPhase = nil
local function _onPhase(phase)
	if phase == _lastPhase then return end
	_lastPhase = phase
	if phase == Constants.PHASES.CRAFTING then
		-- this round's CRAFTING (ReplicatedStorage "Round", GameManager)
		local round = tostring(ReplicatedStorage:GetAttribute("Round"))
		local resumed = LocalPlayer:GetAttribute("CraftingOpen") == round
		_submitted              = false
		_assignments            = {}
		if resumed then
			local ok, saved = pcall(function()
				return HttpService:JSONDecode(LocalPlayer:GetAttribute("CraftDraftSlots") or "{}")
			end)
			if ok and type(saved) == "table" then _assignments = saved end
			_submitted = LocalPlayer:GetAttribute("CraftDraftSubmitted") == true
		end
		LocalPlayer:SetAttribute("CraftingOpen", round)
		_selectedItem           = nil
		submitBtn.Text          = _submitted and "✓ Submitted" or "Submit"
		submitBtn.BackgroundColor3 = _submitted and Color3.fromRGB(60, 60, 80) or Color3.fromRGB(60, 200, 80)
		_showInfo(nil)
		_refreshDisplay()
		screen.Enabled = true
		_startTimer()
		if not resumed then _showGuide() end
	else
		LocalPlayer:SetAttribute("CraftingOpen", nil)
		LocalPlayer:SetAttribute("CraftDraftSlots", nil)
		LocalPlayer:SetAttribute("CraftDraftSubmitted", nil)
		screen.Enabled = false
		if _runConn then _runConn:Disconnect(); _runConn = nil end
	end
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(_onPhase)

-- Started after the CRAFTING event went out (respawn, slow client): join it.
-- The bag comes with the server's resend (SessionManager CharacterAdded).
if ReplicatedStorage:GetAttribute("Phase") then
	_onPhase(ReplicatedStorage:GetAttribute("Phase"))
end
