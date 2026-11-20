-- LugeFilm.lua
-- The camera director for the Alpine Luge reel (2026-11-20, the user's idea:
-- "a theme park ad, 'come and play at Junk Town resort!', antique, like an
-- old 80s commercial"). Studio only: the harness turns it on (`luge.film`,
-- scenario record-luge; LugeAuto `film`). LugeClient asks it for the camera
-- every frame and tells it what happens; the footage is cut, aged (VHS) and
-- narrated afterwards (tools/video/cuts.json en-luge).
--
-- Shots, by what the cart is doing:
--   lift    the hill from town (the resort), the car on the chairlift from
--           the side, the zigzag from the air with the guests sliding down,
--           the car arriving at the top station
--   gate    the rider's face in a helmet by the bell
--   run     a rotation: in front looking back at the rider, a hairpin's
--           outside as the cart sweeps round, from above, low behind, a
--           telephoto from the side; a bump holds the front, a slip off the
--           side holds the side
--   finish  past the arch, the cart coming at the camera
-- A clean picture: no HUD, chat, player list or prompts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local LugeLayout = require(ReplicatedStorage.Shared.LugeLayout)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local Constants = require(ReplicatedStorage.Shared.Constants)

local LugeFilm = {}
LugeFilm.on = false
LugeFilm.SHOT = 3.6
LugeFilm.ROTATION = { "front", "hairpin", "heli", "chase", "side", "hairpin", "front", "heli" }

local V = Vector3.new
local O = LobbyLayout.ORIGIN
local W = Constants.LUGE.WIDTH

local _phase, _phaseAt = nil, 0
local _shot, _shotAt, _k = nil, 0, 0
local _hold                     -- { name, untilT }
local _fixed                    -- a fixed camera's spot
local _pos, _at
local _fov = 60

local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end

function LugeFilm.start()
	LugeFilm.on = true
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	-- no name tags over the riders
	task.spawn(function()
		while LugeFilm.on do
			for _, pl in ipairs(Players:GetPlayers()) do
				local h = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
				if h then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
			end
			task.wait(1)
		end
	end)
end

function LugeFilm.event(name, data)
	if not LugeFilm.on then return end
	local t = os.clock()
	if name == "lift" or name == "gate" or name == "go" then
		_phase, _phaseAt = name, t
		_shot, _hold, _fixed, _pos, _at = nil, nil, nil, nil, nil
		if name == "go" then _shotAt, _k = t, 0 end
	elseif name == "bump" then
		_hold = { name = "front", untilT = t + 2.4 }
		_fixed = nil
	elseif name == "hop" then
		_hold = { name = "whoops", untilT = t + 3.6 }
		_fixed = nil
	elseif name == "finishLine" then
		_hold = { name = "finish", untilT = t + 5 }
		_fixed = nil
	end
	local _ = data
end

-- each node's distance along the trough
LugeFilm._S = (function()
	local N = LugeLayout.nodes()
	local S, total = { 0 }, 0
	for k = 2, #N do
		total += math.sqrt((N[k][1] - N[k - 1][1]) ^ 2 + (N[k][2] - N[k - 1][2]) ^ 2)
		S[k] = total
	end
	return S
end)()

-- the next hairpin ahead of s (within `reach`): its node and turn sign
local function hairpinAhead(s, reach)
	local geo = LugeLayout.geometry()
	local K = LugeLayout.curves()
	local N = LugeLayout.nodes()
	local _ = geo
	for k = 1, #N do
		local sk = LugeFilm._S[k]
		if sk > s + 12 and sk < s + reach and math.abs(K[k] or 0) > 1 / 14 then
			return N[k], K[k], sk
		end
	end
	return nil
end

local function lerpCam(wantPos, wantAt, dt, rate)
	_pos = _pos and _pos:Lerp(wantPos, 1 - math.exp(-(rate or 6) * dt)) or wantPos
	_at = _at and _at:Lerp(wantAt, 1 - math.exp(-(rate or 6) * 1.5 * dt)) or wantAt
	return CFrame.lookAt(_pos, _at)
end

--- The camera this frame (CFrame, FOV), or nil to leave it to LugeClient.
function LugeFilm.camera(dt, s, out)
	if not LugeFilm.on or not s or not s.chassis then return nil end
	local chassis = s.chassis
	local p = chassis.Position
	local t = os.clock()
	local look = chassis.CFrame.LookVector
	local fwd = V(look.X, 0, look.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or V(0, 0, -1)
	if out and out.travelYaw then fwd = V(-math.sin(out.travelYaw), 0, -math.cos(out.travelYaw)) end
	local side = V(-fwd.Z, 0, fwd.X)
	local up = V(0, 1, 0)
	if _phase == "lift" then
		local e = t - _phaseAt
		local secs = s.liftSecs or 17
		if e < 4.6 then
			-- the resort from town: over the booth, the hill and its chairlift
			local from = O + LugeLayout.DESK + V(-6, 16, 10)
			local hill = O + V(-205, 38, -280)
			local f = smooth(e / 4.6)
			return CFrame.lookAt(from + V(-8 * f, 4 * f, -10 * f), hill + V(0, 8 * f, -20 * f)), 50
		elseif e < 10 then
			-- the car on the chairlift, from the side, the hill falling away
			return lerpCam(p + V(11, -1.5, 5), p + V(0, 1.2, -2), dt, 4), 58
		elseif e < secs - 3.4 then
			-- the zigzag from the air, the guests sliding down
			local f = smooth((e - 10) / math.max(secs - 13.4, 1))
			return CFrame.lookAt(O + V(-150 - 40 * f, 150, -470 + 30 * f), O + V(-215, 45, -250 + 20 * f)), 55
		else
			-- the top station: the car coming up to it (from the west, clear of the cabin's roof)
			local top = O + LugeLayout.LIFT.top
			return CFrame.lookAt(top + V(-24, -3, 16), p + V(0, 1, 0)), 50
		end
	elseif _phase == "gate" then
		-- the rider's face by the bell
		return CFrame.lookAt(p + fwd * 9 + up * 3 + side * 2.2, p + up * 2.3), 46
	elseif _phase ~= "go" then
		return nil
	end
	-- the run
	local name
	if _hold and t < _hold.untilT then
		name = _hold.name
	else
		_hold = nil
		if not _shot or t - _shotAt > LugeFilm.SHOT then
			_k = _k % #LugeFilm.ROTATION + 1
			_shot, _shotAt, _fixed = LugeFilm.ROTATION[_k], t, nil
			_pos, _at = nil, nil
		end
		name = _shot
	end
	local at = s.lastAt
	if at and at.s > LugeLayout.finishS() - 55 and name ~= "finish" then
		_hold = { name = "finish", untilT = t + 8 }
		name, _fixed, _pos, _at = "finish", nil, nil, nil
	end
	-- (moving shots ride with the cart: smoothed, they lagged a cart's speed
	-- behind and the rider's legs filled the frame)
	if name == "front" then
		return CFrame.lookAt(p + fwd * 12 + up * 3.4 + side * 1.2, p + up * 2.3), 50
	elseif name == "chase" then
		return CFrame.lookAt(p - fwd * 8 + up * 2.6, p + fwd * 10 + up * 0.8), 70
	elseif name == "heli" then
		return CFrame.lookAt(p + up * 24 - fwd * 12 + side * 8, p + fwd * 12), 58
	elseif name == "hairpin" then
		if not _fixed then
			local n, k = hairpinAhead(at and at.s or 0, 90)
			if n then
				-- outside the bend, up on the bank
				local geo = LugeLayout.geometry()
				local pr = geo:project(n[1], n[2])
				local seg = geo.segments[pr.seg]
				local rx, rz = -seg.dz, seg.dx
				local out = (k > 0) and -1 or 1
				_fixed = { pos = O + V(n[1] + rx * out * (W / 2 + 6), n[3] + 4.5, n[2] + rz * out * (W / 2 + 6)) }
			else
				_fixed = { pos = p + fwd * 30 + up * 5 + side * 9 }
			end
		end
		return CFrame.lookAt(_fixed.pos, p + up * 1.2), 46
	elseif name == "side" or name == "whoops" then
		if not _fixed then
			-- across the hill, telephoto (downhill side, so the cart stands against the slope)
			local s0 = side
			if LugeLayout.ground((p + side * 10).Z - O.Z) > LugeLayout.ground((p - side * 10).Z - O.Z) then s0 = -side end
			_fixed = { pos = p + s0 * 38 + fwd * 18 + up * 7 }
		end
		return CFrame.lookAt(_fixed.pos, p + up * 1), name == "whoops" and 34 or 26
	elseif name == "finish" then
		if not _fixed then
			local geo = LugeLayout.geometry()
			local fs = math.min(LugeLayout.finishS() + 16, geo.length - 2)
			local x, z, dx, dz = geo:pointAt(fs)
			local y = geo:heightAt(fs)
			_fixed = { pos = O + V(x - dz * 3.5, y + 3.2, z + dx * 3.5) }
		end
		return CFrame.lookAt(_fixed.pos, p + up * 1.2), 44
	end
	return nil
end

return LugeFilm
