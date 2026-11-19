-- GpClient.client.lua
-- Driving at the Junk Grand Prix (GpManager on the server): the player's
-- car runs Shared/GpCar every frame on its movers (the chassis is owned by
-- this client once the lights go out), the camera is an F1 chase cam (FOV
-- and shake with speed, lean into the bend, a TV crash cam when the car
-- goes over, V for the onboard view), sounds (engine pitched by gear and
-- rpm, tyre squeal, the crowd), the HUD (Modules/GpHud) and, for everyone
-- in town, the pit crews (GpEvent "crew") and other cars' engines.
--
-- Rollover: GpCar says when the load stayed over the car's limit (or a
-- crash); then the movers let go and the car tumbles for real. Landing on
-- its wheels it drives on ("SAVED IT!"); on its roof it asks the server to
-- put it back (GpAction "reset").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GpCar = require(ReplicatedStorage.Shared.GpCar)
local GpDriver = require(ReplicatedStorage.Shared.GpDriver)
local GpLayout = require(ReplicatedStorage.Shared.GpLayout)
local GpTiming = require(ReplicatedStorage.Shared.GpTiming)
local KeyInput = require(ReplicatedStorage.Shared.KeyInput)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)
local TouchDrive = require(ReplicatedStorage.Shared.TouchDrive)
local InputHints = require(ReplicatedStorage.Shared.InputHints)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GpHud = require(script.Parent:WaitForChild("Modules"):WaitForChild("GpHud"))
local GpFilm = require(script.Parent.Modules:WaitForChild("GpFilm"))

local LocalPlayer = Players.LocalPlayer
local G = Constants.GP
local O = LobbyLayout.ORIGIN
local V = Vector3.new

local _s            -- the session: { car, chassis, spec, st, … }
local _keys = {}
local _camMode = "chase"
local _auto         -- Studio harness (TestHarness/GpTest): drive on autopilot { skill }

local function report(kind, payload)
	local ch = ReplicatedStorage:FindFirstChild("HarnessChannel")
	if ch then ch:FireServer(kind, payload) end
end

-- ── Input ───────────────────────────────────────────────────────────────────

local KEYS = {
	[Enum.KeyCode.W] = "gas", [Enum.KeyCode.Up] = "gas",
	[Enum.KeyCode.S] = "brake", [Enum.KeyCode.Down] = "brake",
	[Enum.KeyCode.A] = "left", [Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.D] = "right", [Enum.KeyCode.Right] = "right",
}

local _controls
local function stick()
	if _controls == nil then
		local ok, c = pcall(function()
			local ps = LocalPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			return pm and require(pm):GetControls()
		end)
		_controls = (ok and c) or false
	end
	if not _controls then return nil end
	local ok, v = pcall(function() return _controls:GetMoveVector() end)
	return (ok and typeof(v) == "Vector3" and v.Magnitude > 0.05) and v or nil
end

local _steer = 0
-- throttle, brake, steer (+ = left) for this frame
local function readInput(dt)
	local gas = _keys.gas and 1 or 0
	local brake = _keys.brake and 1 or 0
	local want = (_keys.left and 1 or 0) - (_keys.right and 1 or 0)
	local mv = stick()
	if mv and want == 0 and gas == 0 and brake == 0 then
		if InputHints.touchUI() then
			local th, st, back = TouchDrive.map(mv.X, mv.Z)
			gas = back and 0 or th
			brake = back and 1 or 0
			want = st
		else
			gas = math.clamp(-mv.Z, 0, 1)
			brake = math.clamp(mv.Z, 0, 1)
			want = -mv.X
		end
	end
	-- keyboard steering eases in (a tap is a small correction, not full lock)
	local rate = (math.abs(want) > math.abs(_steer) and 5 or 9) * dt
	_steer += math.clamp(want - _steer, -rate, rate)
	return { throttle = gas, brake = brake, steer = _steer }
end

-- ── Sounds ──────────────────────────────────────────────────────────────────

local function sound(cfg, parent, looped)
	local s = Instance.new("Sound")
	s.SoundId = cfg.id
	s.Volume = cfg.volume or 0.5
	s.Looped = looped == true
	s.Parent = parent
	return s
end

-- ── Camera ──────────────────────────────────────────────────────────────────

local _camPos, _shakeT = nil, 0
local function noise(t, k) return math.noise(t * 7.3, k * 13.1, 0.5) end

local function updateCamera(dt, out)
	if GpFilm.camera(dt, _s, out) then return end   -- filming (TestHarness/GpTest gp.film)
	local cam = workspace.CurrentCamera
	local s = _s
	local chassis = s.chassis
	if not chassis or not chassis.Parent then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local cf = chassis.CFrame
	local look = V(cf.LookVector.X, 0, cf.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or V(0, 0, -1)
	local v = s.st.speed or 0
	local f = math.clamp(v / s.spec.top, 0, 1.2)
	local pos, at, fov
	if s.flippedAt then
		-- TV crash cam: held where the car went over, watching it tumble
		s.crashCam = s.crashCam or (chassis.Position + V(0, 9, 0) - look * 22 + cf.RightVector * 14)
		pos, at, fov = s.crashCam, chassis.Position, 55
	elseif s.pitting then
		-- the pit cam: from the garage side, the crew round the car
		pos = chassis.Position + V(-16, 7, 10)
		at, fov = chassis.Position, 55
	elseif _camMode == "onboard" then
		local seat = s.car:FindFirstChildWhichIsA("VehicleSeat", true)
		local base = seat and seat.Position or chassis.Position
		pos = base + V(0, 3.2, 0) + look * 0.6
		at, fov = pos + look * 30, 78 + 10 * f
	else
		local h = chassis.Size.Y / 2
		local want = chassis.Position - look * (13 + 3 * f) + V(0, 4.5 + h, 0)
		_camPos = _camPos and _camPos:Lerp(want, 1 - math.exp(-12 * dt)) or want
		pos = _camPos
		at = chassis.Position + look * 14 + V(0, 2, 0)
		fov = 68 + 24 * f ^ 1.4
	end
	-- shake: speed, kerbs, a wheel up
	_shakeT += dt
	local amp = 0.03 + 0.2 * f ^ 3
	if out and out.surface == "kerb" then amp += 0.28 end
	if out and out.surface == "grass" or out and out.surface == "gravel" then amp += 0.4 end
	if out and out.lift then amp += 0.18 end
	local shake = V(noise(_shakeT, 1), noise(_shakeT, 2), noise(_shakeT, 3)) * amp
	local roll = out and not s.flippedAt and -(out.lean or 0) * 0.35 or 0
	cam.CFrame = CFrame.lookAt(pos + shake, at) * CFrame.Angles(0, 0, roll)
	cam.FieldOfView = cam.FieldOfView + (fov - cam.FieldOfView) * (1 - math.exp(-6 * dt))
end

-- ── Driving ─────────────────────────────────────────────────────────────────

local function movers(chassis)
	return chassis:FindFirstChild("DriveVelocity"), chassis:FindFirstChild("DriveAngular"),
		chassis:FindFirstChild("UprightGyro"), chassis:FindFirstChild("SuspensionHover")
end

local function letGo(chassis, lean)
	local bv, bav, gyro, susp = movers(chassis)
	if bv then bv.MaxForce = Vector3.zero end
	if bav then bav.MaxTorque = Vector3.zero end
	if gyro then gyro.MaxTorque = Vector3.zero end
	if susp then susp.MaxForce = Vector3.zero end
	local look = chassis.CFrame.LookVector
	local right = chassis.CFrame.RightVector
	local side = (lean or 0) >= 0 and 1 or -1     -- a left bend throws it over to the right
	chassis.AssemblyAngularVelocity = look * (-7 * side) + V(0, side * 1.5, 0)
	chassis.AssemblyLinearVelocity += V(0, 20, 0) + right * (10 * side)
end

local function takeHold(chassis)
	local bv, bav, gyro, susp = movers(chassis)
	if bv then bv.MaxForce = V(3e4, 0, 3e4) end
	if bav then bav.MaxTorque = V(0, 3e4, 0) end
	if gyro then gyro.MaxTorque = V(1e5, 0, 1e5) end
	if susp then susp.MaxForce = V(0, 4e4, 0) end
end

local SURFACES = { GpRoad = "road", GpKerb = "kerb", GpGravel = "gravel", GpGrass = "grass", GpPit = "pit",
	GpChequer = "road", GpWalk = "road" }

local _rayParams = RaycastParams.new()
_rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ground(chassis)
	local list = { chassis.Parent }
	local cars = chassis.Parent and chassis.Parent.Parent
	if cars then table.insert(list, cars) end
	if LocalPlayer.Character then table.insert(list, LocalPlayer.Character) end
	_rayParams.FilterDescendantsInstances = list
	_rayParams.RespectCanCollide = false
	local hit = workspace:Raycast(chassis.Position + V(0, 2, 0), V(0, -12, 0), _rayParams)
	return hit
end

local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- ── Autopilot (harness runs and filming) ────────────────────────────────────

local function pitRoute(box)
	local path = GpLayout.pitPath()
	local stop = GpLayout.box(box)
	-- down the lane's middle, then a shallow line onto the mark (a sharp turn in met the garage wall)
	local lane = GpLayout.PIT.x
	return { path[1], path[2], path[3], V(lane - 1, 0, stop.Z + 24), stop, V(lane - 1, 0, stop.Z - 20), path[4], path[5], path[6] }
end

local function autoInput(s, x, z, yaw)
	local st = s.st
	if not s.driver then
		s.driver = GpDriver.new(s.spec, _auto.skill or 0.92)
		-- out of the garage along the pit lane (straight ahead it meets the pit wall)
		s.route, s.leg, s.pitDone = pitRoute(s.box), 6, false
	end
	if s.route then
		local target = s.route[s.leg]
		if not target then s.route = nil return GpDriver.input(s.driver, st, x, z, yaw) end
		local d = math.sqrt((target.X - x) ^ 2 + (target.Z - z) ^ 2)
		local stopLeg = s.leg == 5
		if stopLeg and (s.pitting or d < 2) then
			if s.pitDone then s.leg += 1 s.pitDone = false end
			return { throttle = 0, brake = 1, steer = 0 }
		end
		if not stopLeg and d < 10 then s.leg += 1 end
		-- slower into the box (at the limit it ran on into the garage: Studio record-gp)
		local want = stopLeg and math.min(G.PIT_LIMIT, math.max(4, d * 1.2)) or (s.leg == 4 and 28 or G.PIT_LIMIT)
		return GpDriver.toward(s.driver, st, x, z, yaw, target.X, target.Z, want, math.max(d, 8))
	end
	local input, p = GpDriver.input(s.driver, st, x, z, yaw)
	local share = p.s / GpLayout.lapLength()
	if st.tyre < G.TYRE.BOX_AT and not s.lastLap and s.lap >= 1 and share > 0.9 and share < 0.97 then
		s.route, s.leg, s.pitDone = pitRoute(s.box), 1, false
	end
	return input
end

local function drive(dt)
	local s = _s
	local chassis = s.chassis
	if not chassis or not chassis.Parent then return end
	if chassis.Anchored then
		updateCamera(dt, nil)
		return
	end
	local st = s.st
	-- over: wait for it to land, then either drive on or call the marshals
	if s.flippedAt then
		local t = os.clock() - s.flippedAt
		local up = chassis.CFrame.UpVector.Y
		local still = chassis.AssemblyLinearVelocity.Magnitude < 4
		if t > 1.2 and up > 0.85 and still then
			s.flippedAt, s.crashCam = nil, nil
			st.flipped, st.over = false, 0
			st.speed = 0
			takeHold(chassis)
			GpHud.banner("SAVED IT!", Color3.fromRGB(80, 230, 120), 2)
		elseif (still and t > G.RESET_SETTLED) or t > G.RESET_MAX then
			if not s.asked then
				s.asked = true
				task.spawn(function() RemoteEvents.GpAction:InvokeServer("reset") end)
			end
		end
		updateCamera(dt, nil)
		return
	end
	local cf = chassis.CFrame
	local yaw = yawOf(cf)
	local hit = ground(chassis)
	local surface = hit and SURFACES[hit.Instance.Name] or "grass"
	local x, z = GpLayout.offset(chassis.Position)
	local inPit = GpLayout.inPit(x, z)
	if inPit and surface ~= "grass" then surface = "pit" end
	local vel = chassis.AssemblyLinearVelocity
	local tdx, tdz = -math.sin(st.travelYaw or yaw), -math.cos(st.travelYaw or yaw)
	local actual = vel.X * tdx + vel.Z * tdz
	local input = _auto and autoInput(s, x, z, yaw) or readInput(dt)
	if s.pitting or s.finishedAt then input = { throttle = 0, brake = 1, steer = 0 } end
	local out = GpCar.step(s.spec, st, input, { dt = dt, yaw = yaw, surface = surface, actual = actual, pit = inPit })
	out.surface = surface
	-- harness runs: a sample a second (tools/gp_trace.py draws them)
	if _auto and os.clock() - (s.sampledAt or 0) >= 1 then
		s.sampledAt = os.clock()
		report("gp_sample", { x = math.floor(x * 10) / 10, z = math.floor(z * 10) / 10, y = math.floor((chassis.Position.Y - O.Y) * 10) / 10,
			cmd = math.floor(out.speed), actual = math.floor(actual), real = math.floor(V(vel.X, 0, vel.Z).Magnitude),
			surface = surface, tyre = math.floor(st.tyre * 100), load = math.floor(out.load * 100) / 100,
			leg = s.route and s.leg or 0, pit = s.pitting == true, thr = input.throttle, br = input.brake })
	end
	if out.flip then
		report("gp_flip", { load = out.load, crash = out.crash, speed = out.speed, surface = surface, x = x, z = z })
		s.flippedAt = os.clock()
		s.asked = false
		letGo(chassis, out.lean)
		GpHud.banner(out.crash and "BIG CRASH!" or "OVER SHE GOES!", Color3.fromRGB(255, 90, 60), 2.5)
		GpHud.radio(out.crash and "Are you okay?! Marshals are on the way." or "Too much! The car's gone over. Marshals coming.", 4)
		if s.sounds then s.sounds.screech.Volume = 0 end
		return
	end
	local filmRise = GpFilm.adjust(s, out, inPit, chassis)
	local bv, bav, gyro, susp = movers(chassis)
	if bv then bv.Velocity = V(-math.sin(out.travelYaw), 0, -math.cos(out.travelYaw)) * out.speed end
	if bav then bav.AngularVelocity = V(0, out.yawRate, 0) end
	if gyro then gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.Angles(0, 0, -out.lean) end
	if susp and hit then
		local bump = (surface == "kerb") and (math.random() * 0.22) or 0
		local y = hit.Position.Y + chassis.Size.Y / 2 + 0.2 + bump + filmRise
		susp.Position = V(chassis.Position.X, y, chassis.Position.Z)
		if susp.MaxForce.Y == 0 then susp.MaxForce = V(0, 4e4, 0) end
	end
	-- sounds
	local snd = s.sounds
	if snd then
		snd.engine.PlaybackSpeed = 0.55 + out.rpm * 1.05 + out.gear * 0.04
		snd.engine.Volume = SoundConfig.GP.ENGINE.volume * (0.55 + 0.45 * input.throttle)
		local squeal = math.clamp(out.slide * 6 + (out.lift and 0.5 or 0) + (out.load > 0.75 and (out.load - 0.75) * 2 or 0), 0, 1)
		if surface ~= "road" and surface ~= "kerb" and surface ~= "pit" then squeal = 0 end
		snd.screech.Volume = SoundConfig.GP.SCREECH.volume * squeal
	end
	-- the HUD
	local boxCall = st.tyre < G.TYRE.BOX_AT and not s.lastLap
	if boxCall and not s.boxCalled then
		s.boxCalled = true
		GpFilm.event("boxcall")
		GpHud.radio("Box, box. Box this lap. Stop on your yellow mark in the pit lane.", 5)
	end
	GpHud.dash(out.speed * G.KMH, out.gear, out.rpm, st.tyre, boxCall)
	if out.lift and not s.liftWarned then
		s.liftWarned = true
		GpHud.radio("Careful! Two wheels in the air there.", 2.5)
		task.delay(6, function() if _s == s then s.liftWarned = false end end)
	end
	updateCamera(dt, out)
end

-- ── Crews (everyone in town sees them) ──────────────────────────────────────
-- A stop that reads as a tyre change (reel feedback 2026-11-19: "they stood
-- there and left; nobody can tell it is a tyre change"): a crewman kneels at
-- each wheel with a wheel gun, the old tyre comes off and is laid down,
-- the new one (a yellow sidewall) goes on; the lollipop, and a stopwatch
-- over the car. Few people: ten round a small car hid the wheels.

local CREW_PART = { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local function part(parent, size, cf, colour, shape, material)
	local q = Instance.new("Part")
	for k, v in pairs(CREW_PART) do q[k] = v end
	q.Size, q.CFrame, q.Color = size, cf, colour
	if shape then q.Shape = shape end
	if material then q.Material = material end
	q.Parent = parent
	return q
end

-- feet at cf's origin, facing cf's look
local function crewMember(parent, cf, colour)
	local m = Instance.new("Model")
	m.Name = "Crew"
	local dark = Color3.fromRGB(30, 30, 36)
	part(m, V(1.6, 2, 1), cf * CFrame.new(0, 2.6, 0), colour)
	part(m, V(1.5, 1.5, 1.5), cf * CFrame.new(0, 4.3, 0), colour, Enum.PartType.Ball)
	part(m, V(1.2, 0.4, 0.3), cf * CFrame.new(0, 4.35, -0.65), Color3.fromRGB(20, 20, 26))
	part(m, V(0.7, 1.6, 0.7), cf * CFrame.new(-0.45, 0.8, 0), dark)
	part(m, V(0.7, 1.6, 0.7), cf * CFrame.new(0.45, 0.8, 0), dark)
	-- arms out in front (holding a gun, a tyre or the jack)
	part(m, V(0.45, 0.45, 1.5), cf * CFrame.new(-0.6, 3.1, -0.75), colour)
	part(m, V(0.45, 0.45, 1.5), cf * CFrame.new(0.6, 3.1, -0.75), colour)
	m.Parent = parent
	return m
end

-- move every part of a model from one base frame to another
local function moveModel(m, from, to, secs)
	for _, limb in ipairs(m:GetChildren()) do
		if limb:IsA("BasePart") then
			local rel = from:ToObjectSpace(limb.CFrame)
			TweenService:Create(limb, TweenInfo.new(secs, Enum.EasingStyle.Quad), { CFrame = to * rel }):Play()
		end
	end
end

local function tween(p, secs, cf)
	TweenService:Create(p, TweenInfo.new(secs, Enum.EasingStyle.Quad), { CFrame = cf }):Play()
end

-- a tyre (axis along the frame's X, like the car's wheels); new ones wear a yellow sidewall
local function tyre(parent, cf, r, width, new)
	local m = Instance.new("Model")
	m.Name = new and "NewTyre" or "OldTyre"
	local rubber = new and Color3.fromRGB(28, 28, 30) or Color3.fromRGB(70, 66, 62)
	local main = part(m, V(width, r * 2, r * 2), cf, rubber, Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
	if new then
		part(m, V(width + 0.06, r * 1.7, r * 1.7), cf, Color3.fromRGB(255, 205, 30), Enum.PartType.Cylinder)
		part(m, V(width + 0.12, r * 1.45, r * 1.45), cf, rubber, Enum.PartType.Cylinder)
	end
	part(m, V(width + 0.18, r * 0.9, r * 0.9), cf, Color3.fromRGB(150, 150, 158), Enum.PartType.Cylinder, Enum.Material.Metal)
	m.PrimaryPart = main
	m.Parent = parent
	return m
end

local function tweenModel(m, secs, cf)
	moveModel(m, m.PrimaryPart.CFrame, cf, secs)
end

-- the car's four wheels: { cf, r, width, side (±1 along the car's right), parts to hide }
local function wheelsOf(car)
	local chassis = car and car.PrimaryPart
	if not chassis then return {} end
	local wheels = {}
	for _, d in ipairs(car:GetDescendants()) do
		local tag, side = d.Name:match("^Wheel(%a-)([LR])$")
		if d:IsA("BasePart") and (tag == "Front" or tag == "Rear") then
			local hide = { d }
			local hub = car:FindFirstChild("Hub" .. tag .. side, true)
			if hub and hub:IsA("BasePart") then table.insert(hide, hub) end
			table.insert(wheels, { cf = d.CFrame, r = d.Size.Y / 2, width = d.Size.X,
				side = side == "L" and -1 or 1, hide = hide })
		end
	end
	if #wheels == 4 then return wheels end
	-- an item for wheels: work on the chassis' corners
	wheels = {}
	local c, h = chassis.CFrame, chassis.Size / 2
	for _, fz in ipairs({ -1, 1 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local r = math.clamp(h.Y, 0.6, 1.2)
			local at = c * CFrame.new(sx * (h.X + 0.3), -h.Y + r - 0.2, fz * (h.Z - r - 0.2))
			table.insert(wheels, { cf = at * CFrame.Angles(0, 0, 0), r = r, width = 0.6, side = sx, hide = {} })
		end
	end
	return wheels
end

local function stopwatch(chassis, seconds)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 54)
	gui.StudsOffsetWorldSpace = V(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = chassis
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	bg.BackgroundTransparency = 0.15
	bg.Parent = gui
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)
	local function label(y, h, font, colour)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position, t.Size = UDim2.fromScale(0, y), UDim2.fromScale(1, h)
		t.Font, t.TextScaled, t.TextColor3 = font, true, colour
		t.Parent = bg
		return t
	end
	local head = label(0.04, 0.36, Enum.Font.GothamBold, Color3.fromRGB(255, 205, 30))
	head.Text = "PIT STOP · NEW TYRES"
	local clock = label(0.4, 0.56, Enum.Font.GothamBlack, Color3.fromRGB(255, 255, 255))
	gui.Parent = chassis
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = math.min(os.clock() - t0, seconds)
		clock.Text = string.format("%.1f s", t)
		if t >= seconds then
			clock.TextColor3 = Color3.fromRGB(60, 220, 90)
			conn:Disconnect()
			task.delay(1.6, function() gui:Destroy() end)
		end
	end)
end

local function pitCrew(box, seconds, car)
	local stop = O + GpLayout.box(box)
	local _, garage = GpLayout.box(box)
	local chassis = car and car.PrimaryPart
	local folder = Instance.new("Folder")
	folder.Name = "GpCrew"
	folder.Parent = workspace
	local colour = Color3.fromHSV(((box * 0.13) % 1), 0.75, 0.9)
	local home = O + garage
	local carCf = chassis and chassis.CFrame or CFrame.lookAt(stop, stop + V(0, 0, -1))
	local look = Vector3.new(carCf.LookVector.X, 0, carCf.LookVector.Z).Unit
	local right = look:Cross(V(0, 1, 0))
	local wheels = wheelsOf(car)
	local ground = (#wheels > 0 and wheels[1].cf.Position.Y - wheels[1].r) or stop.Y
	local IN = 0.35                         -- the crew runs in
	local OFF = seconds * 0.2               -- old tyres off by …
	local ON = seconds * 0.55               -- … new ones on by
	local members = {}
	local function come(at, face)
		local from = CFrame.lookAt(V(home.X, ground, home.Z), V(at.X, ground, at.Z))
		local m = crewMember(folder, from, colour)
		local to = face
		moveModel(m, from, to, IN)
		table.insert(members, { m = m, at = to, home = from })
		return m
	end
	for _, w in ipairs(wheels) do
		local hubP = w.cf.Position
		local out = right * w.side
		-- kneeling past the wheel's end, the gun on the hub (not in front of it:
		-- the wheel shows from the side)
		local ends = (hubP - carCf.Position):Dot(look) >= 0 and 1 or -1
		local spot = V(hubP.X, ground, hubP.Z) + out * (w.width / 2 + 1.3) + look * ends * 1.7
		local kneel = CFrame.lookAt(spot, V(hubP.X, ground, hubP.Z)) * CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-15), 0, 0)
		come(spot, kneel)
		local gun = part(folder, V(0.4, 0.4, 1.1), CFrame.lookAt(home, hubP), Color3.fromRGB(110, 110, 120), nil, Enum.Material.Metal)
		local gunAt = hubP + out * (w.width / 2 + 0.6) + look * ends * 0.5
		tween(gun, IN, CFrame.lookAt(gunAt, hubP + look * ends * 0.5))
		-- the new tyre, rolled in and waiting beside the wheel
		local ready = hubP + out * (w.width / 2 + 1.5) - look * ends * 1.2
		local newT = tyre(folder, w.cf.Rotation + home + V(0, w.r, 0), w.r, w.width, true)
		tweenModel(newT, IN, w.cf.Rotation + ready)
		task.delay(IN, function()
			if not folder.Parent then return end
			-- off comes the old one
			for _, p in ipairs(w.hide) do p.LocalTransparencyModifier = 1 end
			local oldT = tyre(folder, w.cf, w.r, w.width, false)
			tweenModel(oldT, OFF, w.cf + out * (w.width + 1.6))
			task.delay(OFF, function()
				if not oldT.Parent then return end
				-- out and laid down, clear of the new one
				tweenModel(oldT, 0.45, (w.cf + out * (w.width + 2.6) + look * ends * 0.6 - V(0, w.r * 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)))
				-- on goes the new one
				tweenModel(newT, ON - OFF, w.cf)
			end)
		end)
		task.delay(seconds - 0.05, function()
			for _, p in ipairs(w.hide) do p.LocalTransparencyModifier = 0 end
			if newT.Parent then newT:Destroy() end
			if gun.Parent then tween(gun, 0.4, CFrame.lookAt(home, hubP)) end
		end)
	end
	if chassis then
		stopwatch(chassis, seconds)
	end
	-- the lollipop in front of the car
	local lolly = part(folder, V(0.3, 2.4, 2.4), CFrame.new(stop + V(0, 5, -7)) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(220, 30, 30), Enum.PartType.Cylinder)
	-- the wheel guns: off, then on
	local gun = sound(SoundConfig.GP.WRENCH, lolly)
	gun.RollOffMaxDistance = 150
	task.delay(IN, function() if gun.Parent then gun:Play() end end)
	task.delay(IN + ON, function() if gun.Parent then gun:Play() end end)
	task.delay(math.max(0.4, seconds - 0.3), function()
		if lolly.Parent then lolly.Color = Color3.fromRGB(40, 200, 80) end
	end)
	task.delay(seconds, function()
		for _, e in ipairs(members) do moveModel(e.m, e.at, e.home, 0.4) end
		task.delay(0.6, function() folder:Destroy() end)
	end)
end

-- ── Other cars' engines (the town hears the track) ──────────────────────────

local _engines = {}
local function carEngines()
	local circuit = workspace:FindFirstChild("JunkGP")
	local cars = circuit and circuit:FindFirstChild("Cars")
	if not cars then return end
	local seen = {}
	for _, car in ipairs(cars:GetChildren()) do
		local chassis = car.PrimaryPart
		if chassis and not (_s and _s.car == car) then
			seen[car] = true
			local snd = _engines[car]
			if not snd or not snd.Parent then
				snd = sound(SoundConfig.GP.ENGINE, chassis, true)
				snd.RollOffMaxDistance = 260
				snd.RollOffMinDistance = 12
				snd:Play()
				_engines[car] = snd
			end
			local ok, spec = pcall(function() return HttpService:JSONDecode(car:GetAttribute("Spec") or "{}") end)
			local top = ok and spec.top or 120
			local v = chassis.AssemblyLinearVelocity.Magnitude
			local _, rpm = GpCar.gear({ top = top }, v)
			snd.PlaybackSpeed = 0.5 + rpm * 1.05 + math.min(v / top, 1) * 0.3
		end
	end
	for car, snd in pairs(_engines) do
		if not seen[car] then snd:Destroy() _engines[car] = nil end
	end
end

-- ── Session ─────────────────────────────────────────────────────────────────

local function stopSession()
	local s = _s
	_s = nil
	if not s then return end
	if s.conn then s.conn:Disconnect() end
	if s.sounds then for _, snd in pairs(s.sounds) do snd:Destroy() end end
	GpHud.show(false)
	GpHud.lights(nil)
	GpHud.hideResults()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
		cam.CameraSubject = hum
	end
end

local function startSession(msg)
	stopSession()
	local car = msg.car
	local chassis = car and car.PrimaryPart
	if not chassis then return end
	GpHud.build()
	GpHud.show(true)
	GpHud.clearSectors()
	GpHud.clock("0.000", "OUT LAP")
	local s = {
		car = car, chassis = chassis, spec = msg.spec, st = GpCar.newState(), laps = msg.laps, lap = 0, box = msg.box,
		lapStart = nil, best = msg.best, title = msg.title,
	}
	_s = s
	GpFilm.event("session", { lightsAt = msg.lightsAt })
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end) end
	s.sounds = {
		engine = sound(SoundConfig.GP.ENGINE, chassis, true),
		screech = sound(SoundConfig.GP.SCREECH, chassis, true),
	}
	s.sounds.screech.Volume = 0
	s.sounds.engine:Play()
	s.sounds.screech:Play()
	local el = GpHud.el()
	el.leave.Activated:Connect(function() RemoteEvents.GpAction:InvokeServer("leave") end)
	el.reset.Activated:Connect(function() RemoteEvents.GpAction:InvokeServer("reset") end)
	GpHud.radio("Radio check. " .. tostring(msg.title) .. " is ready. Wait for the lights.", 4)
	-- the lights: one every STEP, then out
	task.spawn(function()
		local rev = sound(SoundConfig.GP.REV, workspace.CurrentCamera)
		for k = 1, 5 do
			local at = msg.lightsAt + (k - 1) * G.LIGHTS.STEP
			while workspace:GetServerTimeNow() < at do task.wait() end
			if _s ~= s then rev:Destroy() return end
			GpHud.lights(k)
			GpFilm.event("light", k)
			if k == 3 then rev:Play() end
		end
		while workspace:GetServerTimeNow() < msg.outAt do task.wait() end
		if _s ~= s then rev:Destroy() return end
		GpHud.lights("out")
		GpFilm.event("out")
		GpHud.banner("LIGHTS OUT AND AWAY WE GO!", Color3.fromRGB(255, 255, 255), 2.2)
		GpHud.radio("Out lap. Warm the tyres, mind the pit limiter.", 4)
		task.wait(1.2)
		GpHud.lights(nil)
		task.wait(3)
		rev:Destroy()
	end)
	s.conn = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(drive, math.min(dt, 0.05))
		if not ok then warn("[GpClient] " .. tostring(err)) end
		-- the clock
		if s.lapStart then
			GpHud.clock(GpTiming.format(os.clock() - s.lapStart))
		end
		el.reset.Visible = s.flippedAt ~= nil
	end)
end

local function lapLine(e)
	local text = string.format("LAP %d   %s", e.lap, GpTiming.format(e.time))
	if not e.valid then text ..= "   (track limits)" end
	return { text = text, colour = e.valid and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(140, 140, 150) }
end

RemoteEvents.GpEvent.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	local kind = msg.kind
	if kind == "crew" then
		if msg.box then task.spawn(pitCrew, msg.box, msg.seconds or 2.4, msg.car) end
		return
	elseif kind == "denied" then
		-- a corner notice in town (the HUD is not up)
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Junk Grand Prix", Text = msg.text or "Not now.", Duration = 5 })
		end)
		return
	elseif kind == "session" then
		startSession(msg)
		return
	end
	local s = _s
	if not s then return end
	if kind == "sector" then
		GpHud.sector(msg.index, msg.colour, msg.time)
		if msg.colour == "purple" then GpHud.radio("Purple sector! Keep it up.", 2) end
	elseif kind == "lap" then
		s.lap = msg.lap
		s.lapStart = os.clock()
		GpHud.clearSectors()
		local last = GpHud.el().last
		last.Text = "LAST " .. GpTiming.format(msg.time) .. (msg.valid and "" or "  (deleted)")
		last.TextColor3 = GpHud.COLOURS[msg.colour] or Color3.fromRGB(255, 255, 255)
		if msg.lap < msg.of then
			GpHud.clock("0.000", string.format("LAP %d / %d", msg.lap + 1, msg.of))
			if msg.colour == "purple" then
				GpHud.radio("Fastest lap of anyone! P1 on the board.", 4)
			elseif msg.colour == "green" then
				GpHud.radio("Personal best. Good job, good job.", 3)
			end
		else
			s.lastLap = true
			s.finishedAt = os.clock()
			GpFilm.event("finish")
			GpHud.banner("CHEQUERED FLAG", Color3.fromRGB(255, 255, 255), 3)
		end
	elseif kind == "start" then
		s.lapStart = os.clock()
		GpHud.clock("0.000", string.format("LAP 1 / %d", s.laps))
		GpHud.radio(string.format("Timing starts. Lap 1 of %d. Go go go!", s.laps), 3.5)
	elseif kind == "radio" then
		GpHud.radio(msg.text or "", 3.5)
	elseif kind == "limits" then
		GpHud.banner("TRACK LIMITS: LAP DELETED", Color3.fromRGB(255, 200, 40), 2.2)
	elseif kind == "pit" then
		if msg.phase == "stop" then
			s.pitting = true
			GpFilm.event("pit")
			GpHud.banner("PIT STOP", Color3.fromRGB(255, 220, 60), msg.seconds)
		else
			s.pitting = false
			s.pitDone = true
			GpFilm.event("pitgo")
			s.st.tyre = 1
			s.boxCalled = false
			GpHud.banner(string.format("%.1f s STOP!", msg.seconds or 0), Color3.fromRGB(80, 230, 120), 2)
			GpHud.radio("New tyres on. Go go go!", 3)
		end
	elseif kind == "reset" then
		-- the autopilot: put back in the pits it drives out along the lane,
		-- on the track its pit route starts over next lap
		local cx, cz = GpLayout.offset(s.chassis.Position)
		if _auto and GpLayout.inPit(cx, cz) then s.route, s.leg = pitRoute(s.box), 6 else s.route = nil end
		s.flippedAt, s.crashCam, s.asked = nil, nil, false
		s.st.flipped, s.st.over, s.st.speed, s.st.travelYaw = false, 0, 0, nil
		task.delay(0.35, function() if _s == s and s.chassis.Parent then takeHold(s.chassis) end end)
		if msg.reason ~= "flip" then GpHud.radio("Marshals put you back on the road.", 3) end
	elseif kind == "done" then
		local lines = {}
		for _, e in ipairs(msg.laps or {}) do table.insert(lines, lapLine(e)) end
		table.insert(lines, { text = "BEST " .. GpTiming.format(msg.best) .. (msg.rank and string.format("   ·   P%d of %d", msg.rank, msg.of) or ""),
			colour = Color3.fromRGB(255, 220, 60) })
		if msg.pb then table.insert(lines, { text = "NEW PERSONAL BEST!", colour = GpHud.COLOURS.purple }) end
		GpHud.results(lines, "CHEQUERED FLAG")
		GpHud.radio(msg.pb and "That's a personal best! What a drive." or "Good run. Want a faster car? Junk Motors is open.", 5)
	elseif kind == "ended" then
		stopSession()
	end
end)

KeyInput.began(function(input, processed)
	if processed then return end
	local k = KEYS[input.KeyCode]
	if k then _keys[k] = true return end
	if not _s then return end
	if input.KeyCode == Enum.KeyCode.V then
		_camMode = _camMode == "chase" and "onboard" or "chase"
	elseif input.KeyCode == Enum.KeyCode.R then
		if _s.flippedAt or (_s.st.speed or 0) < 3 then
			task.spawn(function() RemoteEvents.GpAction:InvokeServer("reset") end)
		end
	elseif input.KeyCode == Enum.KeyCode.L then
		task.spawn(function() RemoteEvents.GpAction:InvokeServer("leave") end)
	end
end)
KeyInput.ended(function(input)
	local k = KEYS[input.KeyCode]
	if k then _keys[k] = false end
end)

-- the tower, other cars and the crowd, for everyone
task.spawn(function()
	local crowd
	while true do
		task.wait(0.25)
		pcall(carEngines)
		if _s then GpHud.board(LocalPlayer.DisplayName) end
		if not crowd then
			local circuit = workspace:FindFirstChild("JunkGP")
			local roof = circuit and circuit:FindFirstChild("GpStandRoof", true)
			if roof then
				crowd = sound(SoundConfig.GP.CROWD, roof, true)
				crowd.RollOffMaxDistance = 320
				crowd.RollOffMinDistance = 30
				crowd:Play()
			end
		end
	end
end)

-- Studio harness: drive a run on autopilot (TestHarness/GpTest)
local function autoStart()
	local raw = LocalPlayer:GetAttribute("GpAuto")
	if not raw then return end
	local ok, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
	_auto = ok and cfg or { skill = 0.92 }
	if _auto.camera then _camMode = _auto.camera end
	if _auto.film then GpFilm.start() end
	task.spawn(function()
		-- (a character still loading is turned away: try again)
		for _ = 1, 15 do
			local res = RemoteEvents.GpAction:InvokeServer("enter")
			report("gp_enter", { result = res })
			if res == "ok" or _s then return end
			task.wait(2)
		end
	end)
end
LocalPlayer:GetAttributeChangedSignal("GpAuto"):Connect(autoStart)
autoStart()
