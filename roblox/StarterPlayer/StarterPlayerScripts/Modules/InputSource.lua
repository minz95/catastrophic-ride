-- InputSource.lua
-- Lets something other than the keyboard drive the local vehicle.
-- RacingClient reads keys through InputSource.read(); the harness BotDriver
-- installs an override that returns synthetic key states. With no override
-- installed this is a pass-through, so normal play is unaffected.

local InputSource = {}

local _override = nil

--- fn() -> keys table ({ W, A, S, D, Shift, Space, Ctrl, ... }) or nil.
function InputSource.setOverride(fn)
	_override = fn
end

function InputSource.clearOverride()
	_override = nil
end

function InputSource.isOverridden()
	return _override ~= nil
end

function InputSource.read(keys)
	if _override then
		local k = _override()
		if k then return k end
	end
	return keys
end

return InputSource
