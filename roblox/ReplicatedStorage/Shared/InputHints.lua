-- InputHints.lua (client)
-- The name of a control as the player sees it on their device: keyboard
-- players read the key ("E"), gamepad players the button KeyInput.GAMEPAD
-- maps to it ("X"), phone / tablet players the TouchControls button that
-- presses it ("GRAB"). Text on screen that names a control builds it here,
-- so a phone never says "Press E".
--
--   InputHints.mode()            → "keyboard" | "gamepad" | "touch"
--   InputHints.key("grab")       → "E" / "X" / "GRAB"
--   InputHints.tag("grab")       → "[E]" / "[X]" / "[GRAB]"
--   InputHints.hold("steal")     → "[Hold E]" / "[Hold X]" / "[Hold GRAB]"
--   InputHints.onChange(fn)      → fn(mode) when the player switches device

local UserInputService = game:GetService("UserInputService")
local KeyInput = require(script.Parent.KeyInput)

local InputHints = {}

-- action → keyboard key, the key KeyInput sees (for the gamepad lookup) and
-- the TouchControls button label. Keep `touch` equal to TouchControls' text.
InputHints.ACTIONS = {
	grab   = { key = "E",     code = "E",           touch = "GRAB" },
	steal  = { key = "E",     code = "E",           touch = "GRAB" },
	defend = { key = "E",     code = "E",           touch = "GRAB" },
	punch  = { key = "F",     code = "F",           touch = "PUNCH" },
	guard  = { key = "G",     code = "G",           touch = "GUARD" },
	drop   = { key = "X",     code = "X",           touch = "DROP" },
	gadget = { key = "T",     code = "T",           touch = "SMOKE" },
	emote  = { key = "Q",     code = "Q",           touch = "EMOTE" },
	boost  = { key = "F",     code = "F",           touch = "BOOST" },
	item   = { key = "E",     code = "E",           touch = "ITEM" },
	drift  = { key = "Shift", code = "LeftShift",   touch = "DRIFT" },
	reset  = { key = "R",     code = "R",           touch = "RESET" },
	trick  = { key = "T",     code = "T",           touch = "BOMB" },
	taunt  = { key = "Q",     code = "Q",           touch = "😜" },
	climb  = { key = "Space", code = "Space",       touch = "▲" },
	dive   = { key = "Ctrl",  code = "LeftControl", touch = "▼" },
	shop   = { key = "B",     code = "B",           touch = "SHOP" },
	guide  = { key = "J",     code = "J",           touch = "ITEMS" },
	help   = { key = "H",     code = "H",           touch = "Controls" },
}

-- Gamepad button names as printed on the pad.
local PAD_NAMES = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonR1 = "RB", ButtonL1 = "LB", ButtonR2 = "RT", ButtonL2 = "LT",
	DPadUp = "D-pad ↑", DPadDown = "D-pad ↓", DPadLeft = "D-pad ←", DPadRight = "D-pad →",
}

local function padButtonFor(code)
	for button, kc in pairs(KeyInput.GAMEPAD) do
		if kc.Name == code then return PAD_NAMES[button] or button end
	end
	return nil
end

local function lastInputType()
	local ok, t = pcall(function() return UserInputService:GetLastInputType() end)
	return ok and t or nil
end

function InputHints.mode()
	local t = lastInputType()
	if t == Enum.UserInputType.Touch then return "touch" end
	if t and t.Name:match("^Gamepad") then return "gamepad" end
	if t == Enum.UserInputType.Keyboard or (t and t.Name:match("^Mouse")) then return "keyboard" end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return "touch" end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then return "gamepad" end
	return "keyboard"
end

--- Phones and tablets without a keyboard (the TouchControls buttons show).
function InputHints.touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--- Lay the screen out for thumbs: a touch-only device, or a touch screen
-- the player is using right now (a tablet with a keyboard; Studio's Device
-- Simulator reports a keyboard too, and SHOP / ITEMS / Controls stayed on
-- the thumbstick there: launch check 2026-10-30).
function InputHints.touchUI()
	return InputHints.touchOnly() or (UserInputService.TouchEnabled and InputHints.mode() == "touch")
end

--- The control's name on this device ("E", "X", "GRAB").
function InputHints.key(action, mode)
	local a = InputHints.ACTIONS[action]
	if not a then return tostring(action) end
	mode = mode or InputHints.mode()
	if mode == "touch" then return a.touch end
	if mode == "gamepad" then return padButtonFor(a.code) or a.touch end
	return a.key
end

function InputHints.tag(action, mode)
	return "[" .. InputHints.key(action, mode) .. "]"
end

function InputHints.hold(action, mode)
	return "[Hold " .. InputHints.key(action, mode) .. "]"
end

--- fn(mode) whenever the player switches between keyboard, gamepad and touch.
function InputHints.onChange(fn)
	local last = InputHints.mode()
	local ok, conn = pcall(function()
		return UserInputService.LastInputTypeChanged:Connect(function()
			local m = InputHints.mode()
			if m ~= last then
				last = m
				fn(m)
			end
		end)
	end)
	return ok and conn or nil
end

return InputHints
