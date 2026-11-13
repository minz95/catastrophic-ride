-- TouchDrive.lua
-- Touch driving (Constants.TOUCH_DRIVE), a pure rule RacingClient uses on
-- touch screens: the gas is on by itself and the thumbstick only steers, in
-- proportion to how far it is pushed; pulled back past BRAKE_PULL it brakes
-- / reverses. One stick for gas and steering meant pushing diagonally to
-- turn, and a sideways push let go of the gas (playtest 2026-11-13).
-- No Roblox types.

local Constants = require(script.Parent.Constants)

local TouchDrive = {}

--- Drive input from a thumbstick move vector.
-- mx: stick X (-1 left … 1 right); mz: stick Z (-1 pushed up … 1 pulled back);
-- nil when the stick is not touched.
-- Returns throttle (1, 0 or VehicleController's reverse via `back` = true)
-- and steer (+1 = left … -1 = right, VehicleController's sign).
function TouchDrive.map(mx, mz)
	local T = Constants.TOUCH_DRIVE
	mx, mz = mx or 0, mz or 0
	local back = mz >= T.BRAKE_PULL
	local throttle = back and 0 or ((T.AUTO_GAS or mz <= -T.DEADZONE) and 1 or 0)
	local a = math.abs(mx)
	local steer = 0
	if a > T.DEADZONE then
		steer = math.min(1, (a - T.DEADZONE) / (T.FULL_AT - T.DEADZONE)) * (mx > 0 and -1 or 1)
	end
	return throttle, steer, back
end

return TouchDrive
