-- CraftingClient.client.lua
-- Crafting phase UI: 6-slot assignment, real-time stat preview,
-- decoration effect reveal, timer, and COMBINE submit.
-- Resolves: Issue #21, #22, #29, #65

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local PhaseClock   = require(ReplicatedStorage.Shared.PhaseClock)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local ItemTypes    = require(ReplicatedStorage.Shared.ItemTypes)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

local CraftingClient = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _slots = {         -- current assignments: slotName → itemName | nil
	BODY     = nil,
	ENGINE   = nil,
	SPECIAL  = nil,
	MOBILITY = nil,
	HEAD     = nil,
	TAIL     = nil,
}
local _inventory      = {}   -- { itemName }  synced from server
local _selectedSlot   = nil  -- which slot button is currently active
local _biome          = nil
local _active         = false
local _submitted      = false
local _timerConn      = nil
local _decorEffects   = {}   -- { slotIndex → effectName } from server

-- ─── Colour palette ───────────────────────────────────────────────────────────

local COLOURS = {
	bg          = Color3.fromRGB(18,  18,  30),
	panel       = Color3.fromRGB(28,  28,  45),
	slotEmpty   = Color3.fromRGB(45,  45,  70),
	slotFilled  = Color3.fromRGB(60,  100, 160),
	slotActive  = Color3.fromRGB(90,  160, 255),
	border      = Color3.fromRGB(80,  80,  120),
	text        = Color3.fromRGB(220, 220, 255),
	accent      = Color3.fromRGB(120, 200, 255),
	combine     = Color3.fromRGB(60,  180, 90),
	combineHov  = Color3.fromRGB(80,  220, 110),
	statBar     = Color3.fromRGB(60,  140, 220),
	timerOk     = Color3.fromRGB(80,  220, 120),
	timerWarn   = Color3.fromRGB(220, 180, 60),
	timerDanger = Color3.fromRGB(220, 80,  60),
	rarityColor = {
		Common   = Color3.fromRGB(200, 200, 200),
		Uncommon = Color3.fromRGB(80,  200, 80),
		Rare     = Color3.fromRGB(80,  140, 255),
		Epic     = Color3.fromRGB(180, 80,  255),
	},
}

-- ─── UI References ────────────────────────────────────────────────────────────

local _gui          = nil   -- ScreenGui
local _slotButtons  = {}    -- { slotName → Frame }
local _statBars     = {}    -- { statName → Frame (fill bar) }
local _statLabels   = {}    -- { statName → TextLabel }
local _inventoryGrid = nil  -- ScrollingFrame
local _timerLabel   = nil   -- TextLabel
local _combineBtn   = nil   -- TextButton
local _decorFrames  = {}    -- { 1,2,3 → Frame }

-- ─── UI Builder ───────────────────────────────────────────────────────────────

local function makeFrame(props)
	local f = Instance.new("Frame")
	for k, v in pairs(props) do f[k] = v end
	return f
end

local function makeLabel(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font      = Enum.Font.GothamBold
	l.TextColor3 = COLOURS.text
	for k, v in pairs(props) do l[k] = v end
	return l
end

local function makeButton(props)
	local b = Instance.new("TextButton")
	b.Font       = Enum.Font.GothamBold
	b.TextColor3 = COLOURS.text
	for k, v in pairs(props) do b[k] = v end
	return b
end

local function addCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
end

local function addPadding(parent, px)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px)
	p.PaddingLeft  = u;  p.PaddingRight  = u
	p.PaddingTop   = u;  p.PaddingBottom = u
	p.Parent = parent
end

local function addStroke(parent, colour, thickness)
	local s = Instance.new("UIStroke")
	s.Color     = colour or COLOURS.border
	s.Thickness = thickness or 1
	s.Parent    = parent
end

-- ─── Slot button factory ──────────────────────────────────────────────────────

local SLOT_ORDER = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }
local SLOT_ICONS = {
	BODY     = "🚗", ENGINE  = "⚙️",  SPECIAL  = "✨",
	MOBILITY = "🔩", HEAD    = "▶",   TAIL     = "◀",
}

local function _slotDisplayName(slotName)
	if slotName == "MOBILITY" and _biome then
		return Constants.MOBILITY_SLOT_NAMES[_biome] or "MOBILITY"
	end
	return slotName
end

local function _buildSlotButton(slotName, parent, layoutOrder)
	local btn = makeFrame({
		Name              = "Slot_" .. slotName,
		Size              = UDim2.new(1, 0, 0, 82),
		BackgroundColor3  = COLOURS.slotEmpty,
		LayoutOrder       = layoutOrder,
		Parent            = parent,
	})
	addCorner(btn, 8)
	addStroke(btn)

	-- Icon
	local icon = makeLabel({
		Name     = "Icon",
		Size     = UDim2.new(0, 36, 0, 36),
		Position = UDim2.new(0, 8, 0.5, -18),
		Text     = SLOT_ICONS[slotName] or "?",
		TextScaled = true,
		Parent   = btn,
	})

	-- Slot name
	local nameLabel = makeLabel({
		Name     = "SlotName",
		Size     = UDim2.new(1, -54, 0, 18),
		Position = UDim2.new(0, 50, 0, 8),
		Text     = _slotDisplayName(slotName),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent   = btn,
	})

	-- Assigned item label
	local itemLabel = makeLabel({
		Name     = "ItemLabel",
		Size     = UDim2.new(1, -54, 0, 24),
		Position = UDim2.new(0, 50, 0, 30),
		Text     = "— empty —",
		TextColor3 = Color3.fromRGB(120, 120, 160),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font     = Enum.Font.Gotham,
		Parent   = btn,
	})

	-- Rarity badge
	local badge = makeLabel({
		Name     = "Badge",
		Size     = UDim2.new(0, 70, 0, 18),
		Position = UDim2.new(0, 50, 0, 56),
		Text     = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Font     = Enum.Font.Gotham,
		Parent   = btn,
	})

	-- Click to select
	local clickTarget = Instance.new("TextButton")
	clickTarget.Size              = UDim2.fromScale(1, 1)
	clickTarget.BackgroundTransparency = 1
	clickTarget.Text              = ""
	clickTarget.ZIndex            = 2
	clickTarget.Parent            = btn

	clickTarget.MouseButton1Click:Connect(function()
		if not _active or _submitted then return end
		_selectedSlot = (_selectedSlot == slotName) and nil or slotName
		_refreshSlotHighlights()
	end)

	_slotButtons[slotName] = btn
	return btn
end

-- ─── Stat bar factory ─────────────────────────────────────────────────────────

local STATS_TO_SHOW = { "speed", "acceleration", "stability", "floatability", "flyability" }
local STAT_LABELS   = {
	speed = "Speed", acceleration = "Accel", stability = "Stability",
	floatability = "Float", flyability = "Fly"
}

local function _buildStatBar(statName, parent, layoutOrder)
	local row = makeFrame({
		Name            = statName,
		Size            = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder     = layoutOrder,
		Parent          = parent,
	})

	makeLabel({
		Size   = UDim2.new(0, 70, 1, 0),
		Text   = STAT_LABELS[statName] or statName,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = row,
	})

	local track = makeFrame({
		Size             = UDim2.new(1, -80, 0, 12),
		Position         = UDim2.new(0, 75, 0.5, -6),
		BackgroundColor3 = Color3.fromRGB(40, 40, 60),
		Parent           = row,
	})
	addCorner(track, 4)

	local fill = makeFrame({
		Name             = "Fill",
		Size             = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COLOURS.statBar,
		Parent           = track,
	})
	addCorner(fill, 4)

	local valueLabel = makeLabel({
		Name     = "Value",
		Size     = UDim2.new(0, 35, 1, 0),
		Position = UDim2.new(1, -80, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Text    = "0",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = true,
		Parent  = row,
	})

	_statBars[statName]   = fill
	_statLabels[statName] = valueLabel
end

-- ─── Decoration effect frames (#22) ──────────────────────────────────────────

local DECOR_EFFECT_ICONS = {
	boost          = { icon = "⚡", colour = Color3.fromRGB(255, 220, 60),  label = "BOOST +50%"     },
	specialAbility = { icon = "🌟", colour = Color3.fromRGB(180, 80,  255), label = "SPECIAL ABILITY" },
	cosmetic       = { icon = "🎨", colour = Color3.fromRGB(80,  200, 200), label = "COSMETIC ONLY"   },
	fireworks      = { icon = "🎆", colour = Color3.fromRGB(255, 100, 60),  label = "FIREWORKS TRAP"  },
}

local function _buildDecorSlot(idx, parent)
	local frame = makeFrame({
		Name             = "Decor_" .. idx,
		Size             = UDim2.new(0.3, -4, 1, 0),
		BackgroundColor3 = Color3.fromRGB(35, 35, 55),
		LayoutOrder      = idx,
		Parent           = parent,
	})
	addCorner(frame, 8)
	addStroke(frame, Color3.fromRGB(80, 60, 120))

	local questionLabel = makeLabel({
		Name      = "Question",
		Size      = UDim2.fromScale(1, 0.6),
		Text      = "?",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(120, 120, 180),
		Parent    = frame,
	})

	local effectLabel = makeLabel({
		Name      = "Effect",
		Size      = UDim2.new(1, -8, 0.35, 0),
		Position  = UDim2.new(0, 4, 0.62, 0),
		Text      = "Hover to reveal",
		TextColor3 = Color3.fromRGB(100, 100, 140),
		TextScaled = true,
		Font      = Enum.Font.Gotham,
		Parent    = frame,
	})

	-- Reveal on hover
	local btn = makeButton({
		Size              = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text              = "",
		ZIndex            = 3,
		Parent            = frame,
	})

	btn.MouseEnter:Connect(function()
		local effect = _decorEffects[idx]
		if not effect then return end
		local info = DECOR_EFFECT_ICONS[effect]
		if not info then return end

		questionLabel.Text      = info.icon
		questionLabel.TextColor3 = info.colour
		effectLabel.Text        = info.label
		effectLabel.TextColor3  = info.colour
		frame.BackgroundColor3  = Color3.fromRGB(45, 35, 65)
	end)

	btn.MouseLeave:Connect(function()
		questionLabel.Text       = "?"
		questionLabel.TextColor3 = Color3.fromRGB(120, 120, 180)
		effectLabel.Text         = "Hover to reveal"
		effectLabel.TextColor3   = Color3.fromRGB(100, 100, 140)
		frame.BackgroundColor3   = Color3.fromRGB(35, 35, 55)
	end)

	_decorFrames[idx] = frame
end

-- ─── Inventory card factory ───────────────────────────────────────────────────

local function _buildInventoryCard(itemName, parent)
	local cfg = ItemConfig[itemName]
	if not cfg then return end

	local card = makeButton({
		Name             = "Card_" .. itemName,
		Size             = UDim2.new(0, 76, 0, 76),
		BackgroundColor3 = Color3.fromRGB(35, 35, 55),
		Text             = "",
		Parent           = parent,
	})
	addCorner(card, 8)
	addStroke(card, COLOURS.rarityColor[cfg.rarity] or COLOURS.border, 2)

	makeLabel({
		Size      = UDim2.new(1, 0, 0.55, 0),
		Text      = cfg.icon or "?",
		TextScaled = true,
		Parent    = card,
	})

	makeLabel({
		Size     = UDim2.new(1, -4, 0.35, 0),
		Position = UDim2.new(0, 2, 0.6, 0),
		Text     = itemName,
		TextColor3 = COLOURS.rarityColor[cfg.rarity] or COLOURS.text,
		TextScaled = true,
		Font     = Enum.Font.Gotham,
		Parent   = card,
	})

	-- Click to assign to selected slot
	card.MouseButton1Click:Connect(function()
		if not _active or _submitted then return end
		if not _selectedSlot then return end
		_assignItem(_selectedSlot, itemName)
	end)

	-- Hover glow
	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = Color3.fromRGB(55, 55, 80)
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
	end)

	return card
end

-- ─── Full UI construction ─────────────────────────────────────────────────────

local function _buildUI()
	if _gui then _gui:Destroy() end

	_gui = Instance.new("ScreenGui")
	_gui.Name             = "CraftingUI"
	_gui.ResetOnSpawn     = false
	_gui.IgnoreGuiInset   = true
	_gui.Enabled          = false
	_gui.Parent           = PlayerGui

	-- Background overlay
	local overlay = makeFrame({
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex           = 0,
		Parent           = _gui,
	})

	-- ── Timer bar (top centre) ────────────────────────────────────────────────
	local timerFrame = makeFrame({
		Size             = UDim2.new(0, 260, 0, 44),
		Position         = UDim2.new(0.5, -130, 0, 16),
		BackgroundColor3 = COLOURS.panel,
		Parent           = _gui,
	})
	addCorner(timerFrame, 10)

	_timerLabel = makeLabel({
		Size      = UDim2.fromScale(1, 1),
		Text      = "2:00",
		TextScaled = true,
		TextColor3 = COLOURS.timerOk,
		Parent    = timerFrame,
	})

	-- ── Main window ───────────────────────────────────────────────────────────
	local main = makeFrame({
		Size             = UDim2.new(0, 860, 0, 520),
		Position         = UDim2.new(0.5, -430, 0.5, -260),
		BackgroundColor3 = COLOURS.bg,
		Parent           = _gui,
	})
	addCorner(main, 14)
	addPadding(main, 16)

	-- Title
	makeLabel({
		Size     = UDim2.new(1, 0, 0, 30),
		Text     = "CRAFT YOUR VEHICLE",
		TextScaled = true,
		TextColor3 = COLOURS.accent,
		Parent   = main,
	})

	-- ── Left panel: Slots ─────────────────────────────────────────────────────
	local leftPanel = makeFrame({
		Size             = UDim2.new(0, 300, 1, -60),
		Position         = UDim2.new(0, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent           = main,
	})

	local slotList = Instance.new("UIListLayout")
	slotList.SortOrder  = Enum.SortOrder.LayoutOrder
	slotList.Padding    = UDim.new(0, 6)
	slotList.Parent     = leftPanel

	for i, slotName in ipairs(SLOT_ORDER) do
		_buildSlotButton(slotName, leftPanel, i)
	end

	-- Decoration slots (#22)
	local decorTitle = makeLabel({
		Size     = UDim2.new(0, 300, 0, 22),
		Position = UDim2.new(0, 0, 1, -100),
		Text     = "DECORATION EFFECTS",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(160, 120, 220),
		Parent   = main,
	})

	local decorRow = makeFrame({
		Size             = UDim2.new(0, 300, 0, 68),
		Position         = UDim2.new(0, 0, 1, -74),
		BackgroundTransparency = 1,
		Parent           = main,
	})
	local decorLayout = Instance.new("UIListLayout")
	decorLayout.FillDirection = Enum.FillDirection.Horizontal
	decorLayout.Padding       = UDim.new(0, 6)
	decorLayout.Parent        = decorRow

	for i = 1, 3 do
		_buildDecorSlot(i, decorRow)
	end

	-- ── Middle panel: Stats ───────────────────────────────────────────────────
	local midPanel = makeFrame({
		Size             = UDim2.new(0, 220, 1, -60),
		Position         = UDim2.new(0, 316, 0, 40),
		BackgroundColor3 = COLOURS.panel,
		Parent           = main,
	})
	addCorner(midPanel, 10)
	addPadding(midPanel, 12)

	makeLabel({
		Size     = UDim2.new(1, 0, 0, 24),
		Text     = "STATS PREVIEW",
		TextScaled = true,
		TextColor3 = COLOURS.accent,
		Parent   = midPanel,
	})

	local statsContainer = makeFrame({
		Size             = UDim2.new(1, 0, 1, -34),
		Position         = UDim2.new(0, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent           = midPanel,
	})
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding   = UDim.new(0, 8)
	statsLayout.Parent    = statsContainer

	for i, stat in ipairs(STATS_TO_SHOW) do
		_buildStatBar(stat, statsContainer, i)
	end

	-- Biome hint
	makeLabel({
		Name     = "BiomeHint",
		Size     = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -28),
		Text     = "",
		TextScaled = true,
		Font     = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(140, 200, 140),
		Parent   = midPanel,
	})

	-- COMBINE button
	_combineBtn = makeButton({
		Size             = UDim2.new(1, 0, 0, 44),
		Position         = UDim2.new(0, 0, 1, -48),
		BackgroundColor3 = COLOURS.combine,
		Text             = "COMBINE",
		TextScaled       = true,
		Font             = Enum.Font.GothamBlack,
		TextColor3       = Color3.new(1, 1, 1),
		Parent           = midPanel,
	})
	addCorner(_combineBtn, 8)

	_combineBtn.MouseEnter:Connect(function()
		_combineBtn.BackgroundColor3 = COLOURS.combineHov
	end)
	_combineBtn.MouseLeave:Connect(function()
		_combineBtn.BackgroundColor3 = COLOURS.combine
	end)
	_combineBtn.MouseButton1Click:Connect(_submitCraft)

	-- ── Right panel: Inventory ────────────────────────────────────────────────
	local rightPanel = makeFrame({
		Size             = UDim2.new(1, -554, 1, -60),
		Position         = UDim2.new(0, 552, 0, 40),
		BackgroundColor3 = COLOURS.panel,
		Parent           = main,
	})
	addCorner(rightPanel, 10)

	makeLabel({
		Size     = UDim2.new(1, -16, 0, 24),
		Position = UDim2.new(0, 8, 0, 6),
		Text     = "INVENTORY",
		TextScaled = true,
		TextColor3 = COLOURS.accent,
		Parent   = rightPanel,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                = "InventoryGrid"
	scroll.Size                = UDim2.new(1, -12, 1, -40)
	scroll.Position            = UDim2.new(0, 6, 0, 36)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness  = 4
	scroll.ScrollBarImageColor3 = COLOURS.border
	scroll.Parent              = rightPanel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize    = UDim2.new(0, 76, 0, 76)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder   = Enum.SortOrder.LayoutOrder
	grid.Parent      = scroll

	_inventoryGrid = scroll
end

-- ─── Slot highlights ──────────────────────────────────────────────────────────

local function _refreshSlotHighlights()
	for slotName, btn in pairs(_slotButtons) do
		if slotName == _selectedSlot then
			btn.BackgroundColor3 = COLOURS.slotActive
			TweenService:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = COLOURS.slotActive
			}):Play()
		elseif _slots[slotName] then
			btn.BackgroundColor3 = COLOURS.slotFilled
		else
			btn.BackgroundColor3 = COLOURS.slotEmpty
		end
	end
end

-- ─── Assign item to slot ──────────────────────────────────────────────────────

local function _assignItem(slotName, itemName)
	-- Return previous item to inventory if swapping
	if _slots[slotName] then
		-- already handled: it stays in _inventory, UI reflects slots separately
	end

	_slots[slotName] = itemName

	-- Update slot button label
	local btn = _slotButtons[slotName]
	if btn then
		local cfg = ItemConfig[itemName]
		local lbl = btn:FindFirstChild("ItemLabel")
		if lbl then
			lbl.Text = (cfg and cfg.icon or "") .. " " .. itemName
			lbl.TextColor3 = cfg and COLOURS.rarityColor[cfg.rarity] or COLOURS.text
		end
		local badge = btn:FindFirstChild("Badge")
		if badge and cfg then
			badge.Text      = cfg.rarity
			badge.TextColor3 = COLOURS.rarityColor[cfg.rarity] or COLOURS.text
		end
	end

	_selectedSlot = nil
	_refreshSlotHighlights()
	_updateStats()
end

-- ─── Stats preview ────────────────────────────────────────────────────────────

local function _updateStats()
	if not _biome then return end

	local bodyCfg    = _slots.BODY     and ItemConfig[_slots.BODY]
	local engineCfg  = _slots.ENGINE   and ItemConfig[_slots.ENGINE]
	local specialCfg = _slots.SPECIAL  and ItemConfig[_slots.SPECIAL]
	local mobCfg     = _slots.MOBILITY and ItemConfig[_slots.MOBILITY]

	local stats = VehicleStats.calculate(bodyCfg, engineCfg, specialCfg, _biome)
	stats = VehicleStats.applyMobility(stats, mobCfg, _biome)

	-- Update bars (max possible normalised value ≈ STAT_BUDGET)
	local maxVal = Constants.BALANCE.STAT_BUDGET

	for _, statName in ipairs(STATS_TO_SHOW) do
		local fill  = _statBars[statName]
		local label = _statLabels[statName]
		local val   = stats[statName] or 0

		if fill then
			local ratio = math.clamp(val / maxVal, 0, 1)
			TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
				Size = UDim2.new(ratio, 0, 1, 0)
			}):Play()
		end
		if label then
			label.Text = string.format("%.0f", val)
		end
	end

	-- Biome hint in stats panel
	local hint = _gui and _gui:FindFirstChild("CraftingUI", true) -- skip
	if _slotButtons.MOBILITY then
		local slotNameLabel = _slotButtons.MOBILITY:FindFirstChild("SlotName")
		if slotNameLabel then
			slotNameLabel.Text = Constants.MOBILITY_SLOT_NAMES[_biome] or "MOBILITY"
		end
	end
end

-- ─── Inventory grid rebuild ───────────────────────────────────────────────────

local function _rebuildInventory()
	if not _inventoryGrid then return end

	for _, child in ipairs(_inventoryGrid:GetChildren()) do
		if child:IsA("GuiObject") and child.Name:sub(1, 5) == "Card_" then
			child:Destroy()
		end
	end

	for i, itemName in ipairs(_inventory) do
		local card = _buildInventoryCard(itemName, _inventoryGrid)
		if card then card.LayoutOrder = i end
	end

	-- Update canvas size
	local grid = _inventoryGrid:FindFirstChildOfClass("UIGridLayout")
	if grid then
		local cols  = math.max(1, math.floor((_inventoryGrid.AbsoluteSize.X - 12) / 82))
		local rows  = math.ceil(#_inventory / cols)
		_inventoryGrid.CanvasSize = UDim2.new(0, 0, 0, rows * 82)
	end
end

-- ─── Submit ───────────────────────────────────────────────────────────────────

function _submitCraft()
	if not _active or _submitted then return end

	local result = RemoteEvents.SubmitCraft:InvokeServer({
		BODY     = _slots.BODY,
		ENGINE   = _slots.ENGINE,
		SPECIAL  = _slots.SPECIAL,
		MOBILITY = _slots.MOBILITY,
		HEAD     = _slots.HEAD,
		TAIL     = _slots.TAIL,
	})

	if result == "ok" then
		_submitted = true
		_combineBtn.Text             = "SUBMITTED ✅"
		_combineBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
		_combineBtn.Active           = false

		-- Darken the slot panel to indicate locked-in
		for _, btn in pairs(_slotButtons) do
			btn.BackgroundTransparency = 0.3
		end
	else
		-- Flash red on button
		_combineBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
		task.delay(0.8, function()
			if _combineBtn then
				_combineBtn.BackgroundColor3 = COLOURS.combine
			end
		end)
	end
end

-- ─── Timer ───────────────────────────────────────────────────────────────────

local function _startTimer(duration)
	local endTime = tick() + duration

	if _timerConn then _timerConn:Disconnect() end
	_timerConn = RunService.Heartbeat:Connect(function()
		if not _timerLabel then return end
		local remaining = PhaseClock.remaining(math.max(0, endTime - tick()))
		_timerLabel.Text = PhaseClock.format(remaining)

		if remaining > 30 then
			_timerLabel.TextColor3 = COLOURS.timerOk
		elseif remaining > 10 then
			_timerLabel.TextColor3 = COLOURS.timerWarn
			-- Pulse effect in last 10s
		else
			_timerLabel.TextColor3 = COLOURS.timerDanger
		end

		if remaining <= 0 then
			_timerConn:Disconnect()
			_timerConn = nil
		end
	end)
end

-- ─── Enable / Disable ─────────────────────────────────────────────────────────

function CraftingClient.enable()
	_active    = true
	_submitted = false
	_slots     = { BODY=nil, ENGINE=nil, SPECIAL=nil, MOBILITY=nil, HEAD=nil, TAIL=nil }
	_selectedSlot = nil

	if not _gui then _buildUI() end
	_gui.Enabled = true

	_rebuildInventory()
	_refreshSlotHighlights()
	_updateStats()
	_startTimer(Constants.PHASE_DURATION.CRAFTING)
end

function CraftingClient.disable()
	_active = false
	if _gui then _gui.Enabled = false end
	if _timerConn then
		_timerConn:Disconnect()
		_timerConn = nil
	end
end

-- ─── Remote listeners ─────────────────────────────────────────────────────────

-- Inventory sync (shared with FarmingClient)
RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inventory)
	_inventory = inventory
	if _active then _rebuildInventory() end
end)

-- Biome determines MOBILITY slot name
RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(biome)
	_biome = biome
	if _active then
		_updateStats()
	end
end)

-- Decoration effects pre-rolled by server (#22)
-- Server fires this at start of CRAFTING phase
-- Format: { [1]="boost", [2]="cosmetic", [3]="fireworks" }
RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == Constants.PHASES.CRAFTING then
		-- Request decor effects (server sends via a dedicated event or encodes in PhaseChanged)
		-- For now, randomise client-side as placeholder (server authority in full impl)
		local effects = { "boost", "specialAbility", "cosmetic", "fireworks" }
		for i = 1, 3 do
			_decorEffects[i] = effects[math.random(#effects)]
		end
	end
end)

return CraftingClient
