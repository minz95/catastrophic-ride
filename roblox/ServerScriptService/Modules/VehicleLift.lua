-- VehicleLift.lua
-- Named ride-height lifts for a car (abilities like Balloon Bunch or
-- Propeller Hat). The chassis attribute "LiftOffset" is the highest active
-- lift in studs; VehicleController adds it to the hover / suspension target
-- on the client that drives the car. Like VehicleTuning, effects are named
-- and expire on their own, so overlapping lifts never leave a car floating.

local VehicleLift = {}

VehicleLift.ATTR = "LiftOffset"

local _lifts = setmetatable({}, { __mode = "k" })   -- [primary] = { [id] = { studs, untilT } }

local function refresh(primary)
	local list = _lifts[primary]
	local now = os.clock()
	local best = 0
	if list then
		for id, l in pairs(list) do
			if l.untilT <= now then
				list[id] = nil
			elseif l.studs > best then
				best = l.studs
			end
		end
	end
	if primary.Parent then
		primary:SetAttribute(VehicleLift.ATTR, best > 0 and best or nil)
	end
end

--- Lifts `vehicle` by `studs` for `duration` seconds under the name `id`.
function VehicleLift.set(vehicle, id, studs, duration)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary or not studs or studs <= 0 then return end
	_lifts[primary] = _lifts[primary] or {}
	_lifts[primary][id] = { studs = studs, untilT = os.clock() + (duration or 1) }
	refresh(primary)
	task.delay((duration or 1) + 0.02, function()
		refresh(primary)
	end)
end

--- Current lift of a car (studs).
function VehicleLift.get(vehicle)
	local primary = vehicle and vehicle.PrimaryPart
	return primary and primary:GetAttribute(VehicleLift.ATTR) or 0
end

return VehicleLift
