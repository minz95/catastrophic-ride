-- RaceSeat.lua
-- Keeps every racer in their own car during RACING. RacingManager calls
-- RaceSeat.check for each racer every Constants.RACE_SEAT.CHECK_EVERY s.
--
-- A driver can end up out of the seat two ways:
--   * Space (Jump) on a seated humanoid breaks the SeatWeld whatever its
--     JumpHeight: RacingClient turns the Jumping state off, this is the
--     safety net if a jump gets through anyway.
--   * The character died (fell off into the sea) and respawned at the
--     farm's SpawnLocation: the race went on without them and they could
--     not get back to it (playtest 2026-10-25).
-- Either way, after RESEAT_AFTER s the character is moved onto the seat and
-- seated again. A dead character is reloaded at once (no 5 s respawn wait).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local RaceSeat = {}

local _out = {}      -- [userId] = time the driver was first seen out of the seat
local _reload = {}   -- [userId] = the dead character a reload was asked for
local _char = {}     -- [userId] = character last seated

function RaceSeat.reset()
	_out, _reload, _char = {}, {}, {}
end

local function seatOf(vehicle)
	return vehicle and vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
end

--- One check for `player` and its race `vehicle` at time `now`.
-- Returns "reseated" | "respawned" (put back in the car), "reload" (dead,
-- a new character was asked for) or nil (nothing to do yet).
function RaceSeat.check(player, vehicle, now)
	local uid = player.UserId
	local seat = seatOf(vehicle)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not seat then _out[uid] = nil return nil end
	if hum and (hum.Health or 100) <= 0 then
		_out[uid] = nil
		if _reload[uid] ~= char and player.LoadCharacter then
			_reload[uid] = char
			task.spawn(function() pcall(player.LoadCharacter, player) end)
			return "reload"
		end
		return nil
	end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return nil end
	if seat.Occupant == hum then
		_out[uid] = nil
		_char[uid] = char
		return nil
	end
	if seat.Occupant ~= nil then return nil end   -- never pull someone else out
	local since = _out[uid]
	if not since then
		_out[uid] = now
		return nil
	end
	if now - since < Constants.RACE_SEAT.RESEAT_AFTER then return nil end
	_out[uid] = nil
	local why = (_char[uid] and _char[uid] ~= char) and "respawned" or "reseated"
	_char[uid] = char
	hum.JumpHeight = 0
	char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(hum)
	return why
end

return RaceSeat
