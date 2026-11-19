-- GpFilm.lua
-- The camera director for the Junk Grand Prix reel (2026-11-19, the user's
-- idea: "film it like an F1 race, helmets on, dead serious and absurd, no
-- lines, English narration; and the famous 'box, box'"). Studio only: the
-- harness turns it on (`gp.film`, scenario record-gp; GpAuto `film`).
-- GpClient asks it for the camera every frame and tells it what happens;
-- the footage is cut and narrated afterwards (tools/video/cuts.json en-gp).
--
-- Shots, by what the car is doing:
--   garage   the visor, close, pulling back to the toilet in its box
--   lights   the gantry's five red lights (lit here, as the HUD's)
--   pit lane telephoto from the pit wall
--   racing   a rotation: T-cam over the helmet, trackside telephoto,
--            camera car in front (the face), low chase, helicopter, side
--   box call the visor while the radio says "box, box"
--   pit stop over the crew from the pit wall
--   the lift once a run on lap 2: the car is held up on two wheels through
--            a fast bend (`GpFilm.adjust`), seen low from the front
--   finish   the line from the grandstand, telephoto
-- A clean picture: no HUD, chat, player list or prompts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GpLayout = require(ReplicatedStorage.Shared.GpLayout)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)

local GpFilm = {}

GpFilm.on = false
GpFilm.SHOT = 4.2              -- seconds a racing shot lasts
GpFilm.ROTATION = { "tcam", "trackside", "front", "low", "heli", "side", "trackside", "front" }
GpFilm.LIFT_LEAN = 0.48        -- radians the car is held over in the lift
GpFilm.LIFT_SECONDS = 1.8
GpFilm.LIFT_LOAD = 0.62        -- starts in a bend at least this loaded
GpFilm.BOX_SHOT = 3.2          -- the visor shot when the box call comes
GpFilm.BOX_TYRE = 0.43         -- tyre life set on lap 2 (under Constants.GP.TYRE.BOX_AT)

local V = Vector3.new
local O = LobbyLayout.ORIGIN
local LocalPlayer = Players.LocalPlayer

local _shot, _shotAt, _k = nil, 0, 0
local _hold = nil              -- a shot that stays until its time: { name, untilT }
local _fixed                   -- a trackside camera's spot
local _pos, _at                -- smoothed camera
local _lift                    -- { at, side }
local _lifted = false
local _lightsAt

local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end

local function head(chassis)
	local c = LocalPlayer.Character
	local h = c and c:FindFirstChild("Head")
	-- not yet in the car (still walking in town): no head to film
	if h and chassis and (h.Position - chassis.Position).Magnitude > 10 then return nil end
	return h
end

local function clean()
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	pcall(function() game:GetService("ProximityPromptService").Enabled = false end)
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled then g.Enabled = false end
		end
	end
end

--- Turns the director on (GpClient, GpAuto `film`).
function GpFilm.start()
	if GpFilm.on then return end
	GpFilm.on = true
	RunService:BindToRenderStep("GpFilmClean", Enum.RenderPriority.Last.Value, clean)
end

local function lamps(n)
	local circuit = workspace:FindFirstChild("JunkGP")
	if not circuit then return end
	for k = 1, 5 do
		local lamp = circuit:FindFirstChild("GpLight" .. k, true)
		if lamp then lamp.Color = (n and k <= n) and Color3.fromRGB(255, 20, 20) or Color3.fromRGB(60, 10, 10) end
	end
end

local function hold(name, seconds)
	_hold = { name = name, untilT = os.clock() + seconds, from = os.clock() }
	_fixed = nil
end

--- What happened (GpClient): "session" (lightsAt), "light" (k), "out",
-- "boxcall", "pit", "pitgo", "flip", "finish".
function GpFilm.event(kind, data)
	if not GpFilm.on then return end
	if kind == "session" then
		_lightsAt = data and data.lightsAt
		_shot, _hold, _lifted, _lift = "garage", nil, false, nil
		_shotAt = os.clock()
		lamps(nil)
	elseif kind == "light" then
		lamps(data)
	elseif kind == "out" then
		lamps(nil)
		hold("getaway", 3.4)
	elseif kind == "boxcall" then
		hold("visor", GpFilm.BOX_SHOT)
	elseif kind == "pit" then
		hold("crew", 6)
	elseif kind == "pitgo" then
		hold("pitexit", 2.6)
	elseif kind == "finish" then
		hold("line", 5)
	end
end

--- The lift (once a run, from lap 2): held over on two wheels through a
-- loaded bend. Changes `out` (lean, lift) in place; returns the extra
-- ride height for the chassis (it pivots on its outer wheels).
function GpFilm.adjust(s, out, inPit, chassis)
	if not GpFilm.on or not out then return 0 end
	local now = os.clock()
	-- worn tyres half way round lap 2: the box call and a stop that lap
	-- (on their own they wore out on the last lap: no stop, Studio take 1)
	if not s.filmWorn and (s.lap or 0) == 1 and s.lapStart and now - s.lapStart > 10 and s.st then
		s.filmWorn = true
		s.st.tyre = math.min(s.st.tyre, GpFilm.BOX_TYRE)
	end
	if not _lift and not _lifted and not inPit and (s.lap or 0) >= 1 and not s.lastLap
		and (out.load or 0) >= GpFilm.LIFT_LOAD and math.abs(out.lean or 0) > 0.01 then
		_lift = { at = now, side = (out.lean > 0) and 1 or -1 }
		_lifted = true
		hold("lift", GpFilm.LIFT_SECONDS + 0.8)
	end
	if not _lift then return 0 end
	local t = (now - _lift.at) / GpFilm.LIFT_SECONDS
	if t >= 1 then _lift = nil return 0 end
	local a = math.sin(math.pi * math.clamp(t, 0, 1)) ^ 0.6
	local lean = GpFilm.LIFT_LEAN * a * _lift.side
	if math.abs(lean) > math.abs(out.lean or 0) then out.lean = lean end
	out.lift = true
	local w = chassis and chassis.Size.X or 6
	return (w / 2) * math.abs(math.sin(lean))
end

-- a point on the circuit `ahead` studs further on from the car, `side` studs out
local function trackPoint(chassis, ahead, side)
	local geo = GpLayout.geometry()
	local x, z = GpLayout.offset(chassis.Position)
	local p = geo:project(x, z)
	local s = (p.s + ahead) % geo.length
	local px, pz = geo:offsetPoint(s, side)
	return O + V(px, 0, pz)
end

local function racing(name, t, chassis, look, rt, speed, dt)
	local p = chassis.Position
	local up = V(0, 1, 0)
	local h = head(chassis)
	local hp = h and h.Position or (p + V(0, 3, 0))
	if name == "tcam" then
		local pos = hp + up * 2.3 - look * 3.6
		return pos, hp + look * 30 + up * 0.5, 72, false
	elseif name == "trackside" then
		if not _fixed then
			local ahead = math.clamp(speed * 2.4, 60, 160)
			local side = (math.random() < 0.5) and -24 or 24
			_fixed = trackPoint(chassis, ahead, side) + V(0, 5 + math.random() * 3, 0)
		end
		local d = (p - _fixed).Magnitude
		local fov = math.clamp(math.deg(2 * math.atan(16 / math.max(d, 1))), 9, 55)
		return _fixed, p + up * 1.5, fov, false
	elseif name == "front" then
		return p + look * 15 + up * 2.2 + rt * 2, p:Lerp(hp, 0.45), 40, true
	elseif name == "low" then
		return p - look * 8 + up * 0.9 + rt * 2.2, p + look * 25 + up * 1.2, 84, true
	elseif name == "heli" then
		return p + up * 42 - look * 26 + rt * 10, p, 42, true
	elseif name == "side" then
		return p + rt * 15 + up * 2.2 + look * 2, p + up * 1.2, 46, true
	end
	return p - look * 14 + up * 6, p + look * 14, 70, true
end

--- The camera this frame. Returns true when it set it (GpClient skips its own).
function GpFilm.camera(dt, s, out)
	if not GpFilm.on or not s then return false end
	local chassis = s.chassis
	if not chassis or not chassis.Parent then return false end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local cf = chassis.CFrame
	local look = V(cf.LookVector.X, 0, cf.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or V(0, 0, -1)
	local rt = V(-look.Z, 0, look.X)
	local p = chassis.Position
	local up = V(0, 1, 0)
	local now = os.clock()
	local speed = s.st and s.st.speed or 0
	local h = head(chassis)
	local hp = h and h.Position or (p + V(0, 3, 0))
	local face = h and V(h.CFrame.LookVector.X, 0, h.CFrame.LookVector.Z) or look
	face = face.Magnitude > 0.01 and face.Unit or look
	local serverNow = workspace:GetServerTimeNow()

	local pos, at, fov, follow
	if _hold and now > _hold.untilT then _hold = nil _fixed = nil _shotAt = now end
	local name = _hold and _hold.name
	local ht = _hold and (now - _hold.from) or 0
	if s.flippedAt then
		s.crashCam = s.crashCam or (p + V(0, 8, 0) - look * 20 + rt * 13)
		pos, at, fov = s.crashCam, p, 50
	elseif chassis.Anchored and _lightsAt and serverNow >= _lightsAt - 0.3 then
		-- the gantry's lights, from the grid
		local z = GpLayout.LINE_Z
		local lamps = O + V(-360, 13.2, z + 2)
		pos, at, fov = lamps + V(0, -2.5, 30), lamps, 34
	elseif chassis.Anchored then
		-- the visor, pulling back to the car in its box
		local a = smooth((now - _shotAt) / 7)
		pos = hp + face * (3.2 + a * 10) + up * (0.1 + a * 2) + rt * (a * 3.5)
		at, fov = hp:Lerp(p, a * 0.5), 50 - a * 8
	elseif name == "getaway" then
		-- out of the box, down the pit lane: from ahead on the lane
		if not _fixed then _fixed = p + look * 70 + rt * 7 + up * 3 end
		pos, at, fov = _fixed, p + up * 1.5, math.clamp(math.deg(2 * math.atan(18 / math.max((p - _fixed).Magnitude, 1))), 12, 60)
	elseif name == "visor" then
		pos, at, fov, follow = hp + face * (4.2 - ht * 0.3) + up * 0.2, hp, 40, true
	elseif name == "crew" then
		-- low, from the pit wall side: the wheels coming off and going on
		pos, at, fov = p + rt * 7.5 + look * 1.2 + up * 1.4, p + up * 0.2 - rt * 0.4, 50
	elseif name == "pitexit" then
		if not _fixed then _fixed = p + look * 45 + V(8, 3, 0) end
		pos, at, fov = _fixed, p + up * 1.5, 30
	elseif name == "lift" then
		local side = _lift and _lift.side or 1
		pos, at, fov, follow = p + look * 12 - rt * (5 * side) + up * 0.7, p + up * 1.6, 52, true
	elseif name == "line" then
		local z = GpLayout.LINE_Z
		pos, at, fov = O + V(-335, 14, z - 4), p + up * 1.5, math.clamp(math.deg(2 * math.atan(16 / math.max((p - (O + V(-335, 14, z - 4))).Magnitude, 1))), 10, 50)
	else
		-- the rotation (the pit lane: telephoto from the pit wall)
		local x, z = GpLayout.offset(p)
		if GpLayout.inPit(x, z) then
			pos, at, fov = O + V(GpLayout.PIT.wallX + 1, 6, z - 40), p + up * 1.5, 28
		else
			if not _shot or _shot == "garage" or now - _shotAt > GpFilm.SHOT then
				_k = _k % #GpFilm.ROTATION + 1
				_shot, _shotAt, _fixed = GpFilm.ROTATION[_k], now, nil
			end
			pos, at, fov, follow = racing(_shot, now - _shotAt, chassis, look, rt, speed, dt)
		end
	end
	-- a moving camera eases after the car (a hard cut when the shot changes)
	local key = (name or _shot or "") .. tostring(_hold and _hold.from or _shotAt)
	if follow and _pos and _at and GpFilm._key == key then
		local k = 1 - math.exp(-10 * dt)
		_pos, _at = _pos:Lerp(pos, k), _at:Lerp(at, k)
	else
		_pos, _at = pos, at
	end
	GpFilm._key = key
	-- a little shake at speed (TV cameras on the car)
	local shake = V(0, 0, 0)
	if follow then
		local f = math.clamp(speed / 120, 0, 1)
		local tt = now * 9
		shake = V(math.noise(tt, 1.3), math.noise(tt, 2.7), math.noise(tt, 4.1)) * (0.04 + 0.12 * f ^ 2)
	end
	local roll = (name == "lift" or name == "tcam" or _shot == "tcam") and out and -(out.lean or 0) * 0.5 or 0
	cam.CFrame = CFrame.lookAt(_pos + shake, _at) * CFrame.Angles(0, 0, roll)
	cam.FieldOfView = fov
	return true
end

return GpFilm
