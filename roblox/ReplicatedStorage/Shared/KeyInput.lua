-- KeyInput.lua (client)
-- Key presses from the keyboard, gamepad buttons (KeyInput.GAMEPAD) and
-- on-screen buttons (TouchControls on phones and tablets) through one path. Game scripts connect with
-- KeyInput.began / KeyInput.ended exactly like UserInputService.InputBegan /
-- InputEnded (handler(input, processed), input.KeyCode); a touch button calls
-- KeyInput.press(keyCode) / release(keyCode) and every handler sees an input
-- with that KeyCode.

local UserInputService = game:GetService("UserInputService")

local KeyInput = {}

-- Gamepad buttons → the keyboard keys the game listens for (driving itself
-- comes from the seat's throttle / steer, which the gamepad already sets).
KeyInput.GAMEPAD = {   -- by KeyCode name
	ButtonX  = Enum.KeyCode.E,          -- grab / item
	ButtonB  = Enum.KeyCode.F,          -- punch / boost
	ButtonR1 = Enum.KeyCode.G,          -- guard
	ButtonL1 = Enum.KeyCode.LeftShift,  -- drift
	ButtonY  = Enum.KeyCode.R,          -- reset car
	DPadDown = Enum.KeyCode.X,          -- drop item
	DPadUp   = Enum.KeyCode.T,          -- gadget / race trick
	DPadRight = Enum.KeyCode.Q,         -- emote menu / taunt
	-- gas / brake on the triggers (they relied on the seat's ThrottleFloat,
	-- which Roblox's control module never wrote in a race); the left stick
	-- steers through RacingClient's move vector.
	ButtonR2 = Enum.KeyCode.Up,
	ButtonL2 = Enum.KeyCode.Down,
	-- SKY climb / dive (RacingClient reads Space / Ctrl); A also jumps on
	-- foot, which nothing here listens to as Space.
	ButtonA  = Enum.KeyCode.Space,      -- climb (SKY)
	DPadLeft = Enum.KeyCode.LeftControl, -- dive (SKY)
}

local _began, _ended = {}, {}

local function connect(list, signal, fn)
	local entry = { fn = fn }
	table.insert(list, entry)
	local real = signal:Connect(function(input, processed)
		local kc = input.KeyCode
		local mapped = kc and KeyInput.GAMEPAD[kc.Name]
		if mapped then
			fn({ KeyCode = mapped, UserInputType = input.UserInputType, Virtual = true }, processed)
		else
			fn(input, processed)
		end
	end)
	return {
		Disconnect = function()
			real:Disconnect()
			local i = table.find(list, entry)
			if i then table.remove(list, i) end
		end,
	}
end

function KeyInput.began(fn)
	return connect(_began, UserInputService.InputBegan, fn)
end

function KeyInput.ended(fn)
	return connect(_ended, UserInputService.InputEnded, fn)
end

local function fire(list, keyCode)
	local input = { KeyCode = keyCode, UserInputType = Enum.UserInputType.Touch, Virtual = true }
	for _, entry in ipairs(table.clone(list)) do
		task.spawn(entry.fn, input, false)
	end
end

--- An on-screen button went down / up.
function KeyInput.press(keyCode) fire(_began, keyCode) end
function KeyInput.release(keyCode) fire(_ended, keyCode) end

return KeyInput
