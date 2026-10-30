-- TouchControls.client.lua
-- On-screen buttons for phones and tablets (no keyboard): they press the same
-- keys as the keyboard through Shared/KeyInput, so FarmingClient and
-- RacingClient need nothing extra. Steering comes from Roblox's own thumbstick
-- (the seat's ThrottleFloat / SteerFloat, read by RacingClient).
--   FARMING: GRAB (E; hold near a player to steal, tap fast in a contest),
--            PUNCH (F), GUARD (hold G), DROP (X), EMOTE (Q: opens EmoteUI),
--            SMOKE (T, with a gadget)
--   RACING:  DRIFT (hold Shift), BOOST (F), ITEM (E), RESET (R), BOMB (T,
--            with a race trick), taunt (Q), ▲ / ▼ climb / dive (Space /
--            Ctrl, SKY only)
-- Labels are Shared/InputHints' touch names: text elsewhere ("[GRAB] Pick
-- Up") names these buttons.
--
-- Layout: a grid anchored bottom-right, sized from the viewport every time it
-- changes. It stays above Roblox's jump button (and the speedometer) and
-- below the race position list; on a short phone screen where that leaves too
-- little room it moves left of the list. A 74-px grid with a fixed offset ran
-- off the top of a 390-px phone and covered the list.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

if not UserInputService.TouchEnabled then return end

local Constants    = require(ReplicatedStorage.Shared.Constants)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

for _, old in ipairs(PlayerGui:GetChildren()) do
	if old.Name == "TouchControls" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "TouchControls"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true   -- same coordinates as the HUD (also IgnoreGuiInset)
screen.DisplayOrder   = 10
screen.Parent         = PlayerGui

local SIZE, GAP = 74, 12      -- full-size button and gap (scaled down on small screens)
local MIN_SCALE = 0.55
local TOP_BAR   = 60          -- Roblox's top bar buttons
local MARGIN    = 24

-- col counts from the right edge, row from the bottom (1 = bottom-right,
-- under the right thumb).
local LAYOUT = {
	FARMING = {
		{ text = "GRAB",  key = Enum.KeyCode.E, col = 1, row = 1, color = Color3.fromRGB(60, 170, 90) },
		{ text = "PUNCH", key = Enum.KeyCode.F, col = 2, row = 1, color = Color3.fromRGB(210, 80, 60) },
		{ text = "GUARD", key = Enum.KeyCode.G, col = 1, row = 2, color = Color3.fromRGB(70, 110, 200) },
		{ text = "DROP",  key = Enum.KeyCode.X, col = 3, row = 1, color = Color3.fromRGB(110, 110, 125), small = true },
		{ text = "EMOTE", key = Enum.KeyCode.Q, col = 3, row = 2, color = Color3.fromRGB(240, 200, 60), small = true },
		{ text = "SMOKE", key = Enum.KeyCode.T, col = 2, row = 2, color = Color3.fromRGB(90, 90, 100), gadget = true },
	},
	RACING = {
		{ text = "BOOST", key = Enum.KeyCode.F, col = 1, row = 1, color = Color3.fromRGB(60, 150, 240) },
		{ text = "DRIFT", key = Enum.KeyCode.LeftShift, col = 2, row = 1, color = Color3.fromRGB(230, 160, 35) },
		{ text = "ITEM",  key = Enum.KeyCode.E, col = 1, row = 2, color = Color3.fromRGB(170, 80, 220) },
		{ text = "RESET", key = Enum.KeyCode.R, col = 3, row = 1, color = Color3.fromRGB(110, 110, 125), small = true },
		{ text = "BOMB",  key = Enum.KeyCode.T, col = 2, row = 2, color = Color3.fromRGB(220, 90, 40), attr = "RaceTrick" },
		{ text = "😜",    key = Enum.KeyCode.Q, col = 3, row = 2, color = Color3.fromRGB(240, 200, 60), small = true },
		{ text = "▲",     key = Enum.KeyCode.Space, col = 4, row = 2, color = Color3.fromRGB(80, 190, 230), biome = "SKY" },
		{ text = "▼",     key = Enum.KeyCode.LeftControl, col = 4, row = 1, color = Color3.fromRGB(80, 140, 200), biome = "SKY" },
	},
}

-- ─── Held keys: always let go ────────────────────────────────────────────────
-- A finger that slides off a button, a phase change that hides it or a
-- cancelled touch never fired InputEnded on the button: GUARD, DRIFT or a
-- steal stayed held. Every press is tracked and released on whichever comes
-- first.
local _held = {}   -- [button] = KeyCode

local function release(btn)
	local key = _held[btn]
	if not key then return end
	_held[btn] = nil
	KeyInput.release(key)
end

local function releaseAll()
	for btn in pairs(_held) do release(btn) end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- ─── Build ───────────────────────────────────────────────────────────────────

local _sets = {}       -- phase → { frame, entries = { {btn, b} } }
local _phase = nil

local function biomeOk(b)
	return not b.biome or ReplicatedStorage:GetAttribute("Biome") == b.biome
end

for phase, list in pairs(LAYOUT) do
	local frame = Instance.new("Frame")
	frame.Name                   = phase
	frame.AnchorPoint            = Vector2.new(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible                = false
	frame.Parent                 = screen
	local entries = {}
	for _, b in ipairs(list) do
		local btn = Instance.new("TextButton")
		btn.Name                   = b.text
		btn.AnchorPoint            = Vector2.new(1, 1)
		btn.BackgroundColor3       = b.color
		btn.BackgroundTransparency = 0.15
		btn.Text                   = b.text
		btn.TextColor3             = Color3.new(1, 1, 1)
		btn.TextScaled             = true
		btn.Font                   = Enum.Font.GothamBlack
		btn.AutoButtonColor        = true
		btn.Parent                 = frame
		local function show()
			local attr = (b.gadget and "Gadget") or b.attr
			local on = biomeOk(b) and (not attr or LocalPlayer:GetAttribute(attr) ~= nil)
			btn.Visible = on
			if not on then release(btn) end
		end
		local attr = (b.gadget and "Gadget") or b.attr
		if attr then
			-- only with a gadget / race trick equipped (FarmingManager /
			-- AbilityManager set the attribute)
			LocalPlayer:GetAttributeChangedSignal(attr):Connect(show)
		end
		if b.biome then ReplicatedStorage:GetAttributeChangedSignal("Biome"):Connect(show) end
		show()
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.Parent = btn
		btn.InputBegan:Connect(function(input)
			if not isPress(input) or _held[btn] then return end
			_held[btn] = b.key
			KeyInput.press(b.key)
			-- the touch's own end (also when the finger left the button)
			local conn
			conn = input.Changed:Connect(function(prop)
				if prop ~= "UserInputState" then return end
				local st = input.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					conn:Disconnect()
					release(btn)
				end
			end)
		end)
		btn.InputEnded:Connect(function(input)
			if isPress(input) then release(btn) end
		end)
		table.insert(entries, { btn = btn, b = b })
	end
	_sets[phase] = { frame = frame, entries = entries }
end

-- ─── Layout from the viewport ────────────────────────────────────────────────

-- Bottom of the HUD's race position list (screen pixels), nil when not shown.
local function positionList()
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g.Name == "HUD" and g:IsA("ScreenGui") and g.Enabled then
			local list = g:FindFirstChild("PositionTracker")
			if list and list:IsA("GuiObject") and list.Visible and list.AbsoluteSize.Y > 4 then
				return list.AbsolutePosition.Y + list.AbsoluteSize.Y, list.AbsolutePosition.X
			end
		end
	end
	return nil
end

local function layout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1024, 768)
	-- Roblox's touch jump button: 70 px at (-95, -90) on a small screen
	-- (shorter side <= 500), 120 px at (-170, -210) otherwise.
	local small = math.min(vp.X, vp.Y) <= 500
	local bottom = small and 100 or 220
	for phase, set in pairs(_sets) do
		local cols, rows = 1, 1
		for _, e in ipairs(set.entries) do
			if e.btn.Visible or not e.b.biome then
				cols = math.max(cols, e.b.col)
				rows = math.max(rows, e.b.row)
			end
		end
		local gridW = cols * SIZE + (cols - 1) * GAP
		local gridH = rows * SIZE + (rows - 1) * GAP
		local right, top = MARGIN, TOP_BAR
		local listBottom, listLeft = nil, nil
		if phase == "RACING" then listBottom, listLeft = positionList() end
		if listBottom then top = math.max(top, listBottom + 8) end
		local scale = math.min(1, (vp.Y - bottom - top) / gridH, (vp.X * 0.5) / gridW)
		if listBottom and scale < 0.75 then
			-- too little room under the list: stand left of it instead
			right = (vp.X - listLeft) + 12
			top = TOP_BAR
			scale = math.min(1, (vp.Y - bottom - top) / gridH, (vp.X - right - MARGIN) * 0.6 / gridW)
		end
		scale = math.max(MIN_SCALE, scale)
		local s, g = SIZE * scale, GAP * scale
		set.frame.Size = UDim2.fromOffset(gridW * scale, gridH * scale)
		set.frame.Position = UDim2.new(1, -right, 1, -bottom)
		for _, e in ipairs(set.entries) do
			local bs = e.b.small and s * 0.75 or s
			local inset = (s - bs) / 2
			e.btn.Size = UDim2.fromOffset(bs, bs)
			e.btn.Position = UDim2.new(1, -((e.b.col - 1) * (s + g) + inset), 1, -((e.b.row - 1) * (s + g) + inset))
		end
	end
end

local _layoutKey = nil
local function relayoutIfChanged()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.zero
	local lb = _phase == "RACING" and positionList() or nil
	local key = string.format("%d,%d,%s,%s,%s", math.floor(vp.X), math.floor(vp.Y), tostring(_phase),
		tostring(lb and math.floor(lb / 4) or "-"), tostring(ReplicatedStorage:GetAttribute("Biome")))
	if key ~= _layoutKey then
		_layoutKey = key
		layout()
	end
end

-- ─── Phase ───────────────────────────────────────────────────────────────────

local function onPhase(phase)
	if phase ~= _phase then releaseAll() end
	_phase = phase
	for name, set in pairs(_sets) do
		set.frame.Visible = (name == phase) and LocalPlayer:GetAttribute("Spectating") ~= true
	end
	if LocalPlayer:GetAttribute("Spectating") == true then releaseAll() end
	relayoutIfChanged()
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(function()
	onPhase(ReplicatedStorage:GetAttribute("Phase"))
end)
onPhase(ReplicatedStorage:GetAttribute("Phase") or Constants.PHASES.LOBBY)

-- Viewport (rotation, resize) and the position list's height change now and
-- then: check twice a second, lay out only when something moved.
task.spawn(function()
	while screen.Parent do
		relayoutIfChanged()
		task.wait(0.5)
	end
end)
