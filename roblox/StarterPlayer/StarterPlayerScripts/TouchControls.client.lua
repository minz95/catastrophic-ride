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

local TouchLayout = require(ReplicatedStorage.Shared.TouchLayout)
local LAYOUT = TouchLayout.LAYOUT   -- buttons per phase; where they go: TouchLayout.compute

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

-- ─── Icons (TouchLayout.ICONS) ──────────────────────────────────────────────
-- Out of the button grid: things pressed now and then (emote, taunt, reset).
-- A tap presses the key like a grid button (a touch toggles EmoteUI's menu).
local _icons = {}   -- phase → { {btn, entry} }
for phase, list in pairs(TouchLayout.ICONS) do
	if not _icons[phase] then
		_icons[phase] = {}
		for _, b in ipairs(list) do
			local btn = Instance.new("TextButton")
			btn.Name                   = "Icon_" .. phase .. "_" .. b.key.Name
			btn.Size                   = UDim2.fromOffset(TouchLayout.ICON_SIZE, TouchLayout.ICON_SIZE)
			btn.BackgroundColor3       = b.color
			btn.BackgroundTransparency = 0.15
			btn.Text                   = b.text
			btn.TextScaled             = true
			btn.TextColor3             = Color3.new(1, 1, 1)
			btn.Font                   = Enum.Font.GothamBlack
			btn.Visible                = false
			btn.Parent                 = screen
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = btn
			btn.InputBegan:Connect(function(input)
				if not isPress(input) or _held[btn] then return end
				_held[btn] = b.key
				KeyInput.press(b.key)
				-- let go when the touch ends anywhere (a finger slid off)
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
			table.insert(_icons[phase], { btn = btn, b = b })
		end
	end
end
local function placeIcons(phase, show)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1024, 768)
	local _, _, top = require(ReplicatedStorage.Shared.ScreenFit).view()
	for name, list in pairs(_icons) do
		local on = show and name == phase
		local boxes = on and TouchLayout.icons(name, vp.X, vp.Y, top) or {}
		for i, e in ipairs(list) do
			e.btn.Visible = on
			if not on then release(e.btn) end
			local box = boxes[i]
			if box then e.btn.Position = UDim2.fromOffset(box.box[1], box.box[2]) end
		end
	end
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
	for phase, set in pairs(_sets) do
		local list = nil
		if phase == "RACING" then
			local lb, ll = positionList()
			if lb then list = { bottom = lb, left = ll } end
		end
		local byEntry = {}
		for _, e in ipairs(set.entries) do byEntry[e.b] = e.btn end
		local r = TouchLayout.compute(vp.X, vp.Y, phase, function(b) return byEntry[b].Visible end, list)
		set.frame.Size = UDim2.fromOffset(r.frame[3], r.frame[4])
		set.frame.Position = UDim2.new(1, -r.framePos[1], 1, -r.framePos[2])
		for _, rb in ipairs(r.buttons) do
			local btn = byEntry[rb.b]
			btn.Size = UDim2.fromOffset(rb.size, rb.size)
			btn.Position = UDim2.new(1, -rb.offset[1], 1, -rb.offset[2])
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

-- The race buttons come at GO: before it nothing works, and on a phone
-- they covered the RACE START banner (objective and tips).
local function raceGone()
	local goAt = ReplicatedStorage:GetAttribute("RaceGoAt")
	return type(goAt) == "number" and workspace:GetServerTimeNow() >= goAt - 0.5
end

local function refreshVisible()
	for name, set in pairs(_sets) do
		set.frame.Visible = (name == _phase) and LocalPlayer:GetAttribute("Spectating") ~= true
			and (name ~= "RACING" or raceGone())
	end
	local spectating = LocalPlayer:GetAttribute("Spectating") == true
	placeIcons(_phase, not (spectating and _phase == "RACING") and (_phase ~= "RACING" or raceGone()))
end

local function onPhase(phase)
	if phase ~= _phase then releaseAll() end
	_phase = phase
	refreshVisible()
	if LocalPlayer:GetAttribute("Spectating") == true then releaseAll() end
	relayoutIfChanged()
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(function()
	onPhase(ReplicatedStorage:GetAttribute("Phase"))
end)
onPhase(ReplicatedStorage:GetAttribute("Phase") or Constants.PHASES.LOBBY)

-- Viewport (rotation, resize) and the position list's height change now and
-- then: check four times a second, lay out only when something moved (and
-- show the race buttons at GO).
task.spawn(function()
	local InputHints = require(ReplicatedStorage.Shared.InputHints)
	while screen.Parent do
		-- a touch-screen PC used with keyboard and mouse shows no buttons
		local want = InputHints.touchUI()
		if screen.Enabled ~= want then
			screen.Enabled = want
			if not want then releaseAll() end
		end
		relayoutIfChanged()
		refreshVisible()
		task.wait(0.25)
	end
end)
