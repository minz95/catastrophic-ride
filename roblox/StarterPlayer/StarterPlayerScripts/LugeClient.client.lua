-- LugeClient.client.lua
-- Riding the Alpine Luge (LugeManager on the server): once the gate's bar
-- lifts, this client owns its car and runs Shared/LugeCart every frame on
-- the car's movers (gravity down the trough, brake, steering, the lips,
-- bumps from friends' carts sent by the server); a low chase camera that
-- leans into the bends, a side view on the chairlift; the rolling wheels,
-- the gate's bell, scrapes and boinks; Modules/LugeHud. For everyone in
-- town: the chairlift's chairs swing round the loop, other carts rumble.
-- Off the trough too long, or on the gas going nowhere, it asks the
-- marshals (LugeAction "reset").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LugeCart = require(ReplicatedStorage.Shared.LugeCart)
local LugeDriver = require(ReplicatedStorage.Shared.LugeDriver)
local LugeLayout = require(ReplicatedStorage.Shared.LugeLayout)
local KeyInput = require(ReplicatedStorage.Shared.KeyInput)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)
local TouchDrive = require(ReplicatedStorage.Shared.TouchDrive)
local InputHints = require(ReplicatedStorage.Shared.InputHints)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LugeHud = require(script.Parent:WaitForChild("Modules"):WaitForChild("LugeHud"))
local LugeFilm = require(script.Parent.Modules:WaitForChild("LugeFilm"))

local LocalPlayer = Players.LocalPlayer
local L = Constants.LUGE
local O = LobbyLayout.ORIGIN
local V = Vector3.new

local _s            -- the session
local _keys = {}
local _auto         -- Studio harness (TestHarness/LugeTest): { skill, keys, late, blind, runs }

local function report(kind, payload)
	local ch = ReplicatedStorage:FindFirstChild("HarnessChannel")
	if ch then ch:FireServer(kind, payload) end
end

local function ask(action, why)
	task.spawn(function() pcall(function() RemoteEvents.LugeAction:InvokeServer(action, why) end) end)
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

local function oneShot(cfg, parent, volume, pitch)
	local s = sound(cfg, parent)
	if volume then s.Volume = volume end
	if pitch then s.PlaybackSpeed = pitch end
	s:Play()
	game:GetService("Debris"):AddItem(s, 4)
end

-- ── Camera ──────────────────────────────────────────────────────────────────

local _camPos
local _shake = 0
local function updateCamera(dt, out)
	local cam = workspace.CurrentCamera
	local s = _s
	-- filming (harness luge.film): the reel's director has the camera
	local fcf, ffov = LugeFilm.camera(dt, s, out)
	if fcf then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = fcf
		cam.FieldOfView = ffov or 60
		return
	end
	local chassis = s.chassis
	if not chassis or not chassis.Parent then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local cf = chassis.CFrame
	local look = V(cf.LookVector.X, 0, cf.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or V(0, 0, -1)
	local pos, at, fov
	if s.phase == "lift" then
		-- the chairlift: from the side and a little behind, the hill and the trough below
		local want = chassis.Position + V(-16, 6, 14)
		_camPos = _camPos and _camPos:Lerp(want, 1 - math.exp(-3 * dt)) or want
		pos, at, fov = _camPos, chassis.Position + V(-6, -3, -10), 62
	else
		local f = math.clamp((s.st.speed or 0) / L.TOP, 0, 1.2)
		local want = chassis.Position - look * (10 + 3 * f) + V(0, 4 + chassis.Size.Y / 2, 0)
		_camPos = _camPos and _camPos:Lerp(want, 1 - math.exp(-9 * dt)) or want
		pos = _camPos
		at = chassis.Position + look * 10 + V(0, 0.5, 0)
		fov = 66 + 16 * f
	end
	_shake = math.max(0, _shake - dt * 2)
	local t = os.clock()
	local amp = 0.02 + 0.06 * math.clamp((s.st.speed or 0) / L.TOP, 0, 1) + _shake
	local shake = V(math.noise(t * 9, 1), math.noise(t * 9, 2), math.noise(t * 9, 3)) * amp
	local roll = out and (out.lean or 0) * 0.5 or 0
	cam.CFrame = CFrame.lookAt(pos + shake, at) * CFrame.Angles(0, 0, roll)
	cam.FieldOfView = cam.FieldOfView + (fov - cam.FieldOfView) * (1 - math.exp(-5 * dt))
end

-- ── Riding ──────────────────────────────────────────────────────────────────

local _rayParams = RaycastParams.new()
_rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ground(chassis)
	local list = { chassis.Parent }
	local carts = chassis.Parent and chassis.Parent.Parent
	if carts then table.insert(list, carts) end
	if LocalPlayer.Character then table.insert(list, LocalPlayer.Character) end
	_rayParams.FilterDescendantsInstances = list
	_rayParams.RespectCanCollide = true
	return workspace:Raycast(chassis.Position + V(0, 2, 0), V(0, -14, 0), _rayParams)
end

local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function movers(chassis)
	return chassis:FindFirstChild("DriveVelocity"), chassis:FindFirstChild("DriveAngular"),
		chassis:FindFirstChild("UprightGyro"), chassis:FindFirstChild("SuspensionHover")
end

local function holdInSeat(s)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = s.car:FindFirstChildWhichIsA("VehicleSeat", true)
	if not (root and seat) then return end
	local far = (root.Position - seat.Position).Magnitude > 6
	if far and os.clock() - (s.pulledAt or 0) > 0.5 then
		s.pulledAt = os.clock()
		pcall(function() char:PivotTo(CFrame.new(seat.Position + V(0, 2.5, 0)) * root.CFrame.Rotation) end)
	end
	if not far and hum and hum.SeatPart == seat and not s.readySent then
		s.readySent = true
		ask("ready")
	end
end

-- the autopilot's input (harness), like a person on a keyboard when `keys`
local function autoInput(s, x, z, yaw, at, dt)
	if not s.driver then s.driver = LugeDriver.new(s.spec, _auto.skill or 0.95, _auto.blind) end
	local traffic = {}
	if not _auto.blind then
		local carts = s.chassis.Parent and s.chassis.Parent.Parent
		for _, m in ipairs(carts and carts:GetChildren() or {}) do
			local c = m ~= s.car and m:IsA("Model") and m.PrimaryPart
			if c and not c.Anchored then
				local o = LugeLayout.at(c.Position.X - O.X, c.Position.Z - O.Z, c.Position.Y - O.Y)
				table.insert(traffic, { s = o.s, lateral = o.lateral, speed = c.AssemblyLinearVelocity.Magnitude })
			end
		end
	end
	local input = LugeDriver.input(s.driver, s.st, x, z, yaw, at, traffic)
	-- the reel's slip off the side: once, on a chosen run, a hard pull
	-- toward the low side of a straight (harness luge.whoop = { run, s })
	local w = _auto.whoop
	if w and not s.whooped and s.runs == (w.run or 1) and at.s >= (w.s or 600) and at.s < (w.s or 600) + 14 then
		if not s.whoopSide then
			-- toward the trough's lower side (onto the bank, not off a trestle): + steer = left
			local rz = -math.sin(at.yaw)
			s.whoopSide = (LugeLayout.ground(z + rz * 8) < LugeLayout.ground(z - rz * 8)) and -1 or 1
		end
		input.steer = s.whoopSide
		input.brake = 0
		-- (the trough turns a cart back in: for the film it is thrown at the lip)
		if not s.whoopThrown then
			s.whoopThrown = true
			s.st.travelYaw = (s.st.travelYaw or yaw) + s.whoopSide * 0.55
			s.st.loose = 1   -- (and the trough lets it go for a moment: LugeCart st.loose)
		end
	end
	if _auto.keys then
		s.queue = s.queue or {}
		table.insert(s.queue, input)
		local late = s.queue[1]
		while #s.queue > math.max(1, math.floor((_auto.late or 0.2) / math.max(dt, 1 / 120))) do table.remove(s.queue, 1) end
		_keys.gas = late.throttle > 0.5
		_keys.brake = late.brake > 0.3
		_keys.left = late.steer > 0.3
		_keys.right = late.steer < -0.3
		return readInput(dt)
	end
	return input
end

local function drive(dt)
	local s = _s
	local chassis = s.chassis
	if not chassis or not chassis.Parent then return end
	if chassis.Anchored then
		holdInSeat(s)
		if s.phase == "lift" and s.liftAt then
			LugeHud.lift((workspace:GetServerTimeNow() - s.liftAt) / s.liftSecs)
		end
		updateCamera(dt, nil)
		return
	end
	local st = s.st
	local cf = chassis.CFrame
	local yaw = yawOf(cf)
	local x, z = chassis.Position.X - O.X, chassis.Position.Z - O.Z
	local at = LugeLayout.at(x, z, chassis.Position.Y - O.Y, s.hint)
	s.hint = at.seg
	s.lastAt = at
	local hit = ground(chassis)
	local vel = chassis.AssemblyLinearVelocity
	-- the real speed holds the command back (a tree, a post: no stored speed)
	local actual = V(vel.X, 0, vel.Z).Magnitude
	st.speed = math.min(st.speed or 0, actual + 6)
	local input = _auto and autoInput(s, x, z, yaw, at, dt) or readInput(dt)
	if s.finished then input = { throttle = 0, brake = 0.6, steer = input.steer } end
	local kick = s.kick
	s.kick = nil
	local out = LugeCart.step(s.spec, st, input, { dt = dt, yaw = yaw, at = at, kick = kick })
	if out.event == "scrape" then
		s.scrapes += 1
		_shake = math.min(0.5, _shake + 0.15 + (out.power or 0) / 30)
		oneShot(SoundConfig.LUGE.SCRAPE, chassis, math.clamp(0.2 + (out.power or 0) / 15, 0.2, 0.7), 0.9 + math.random() * 0.3)
		if _auto then report("luge_scrape", { power = out.power, s = math.floor(at.s) }) end
	elseif out.event == "hop" then
		s.hops += 1
		s.whooped = true
		LugeFilm.event("hop")
		_shake = 0.6
		LugeHud.banner("WHOOPS!", Color3.fromRGB(255, 200, 80), 1.6, "steer back onto the track")
		if _auto then report("luge_hop", { power = out.power, s = math.floor(at.s) }) end
	elseif out.event == "back" then
		LugeHud.banner("BACK ON TRACK", Color3.fromRGB(140, 230, 150), 1.2)
	end
	if out.wantReset and os.clock() - (s.askedAt or 0) > 2.5 then
		s.askedAt = os.clock()
		ask("reset", "off")
	end
	-- on the gas going nowhere (nose in a tree, no reverse): the marshals
	if (input.throttle or 0) > 0.5 and actual < 1.5 and not s.finished then
		s.pinnedFor = (s.pinnedFor or 0) + dt
		if s.pinnedFor > L.PINNED then
			s.pinnedFor = -2
			ask("reset", "pinned")
		end
	else
		s.pinnedFor = math.max(0, s.pinnedFor or 0)
	end
	local bv, bav, gyro, susp = movers(chassis)
	if bv then bv.Velocity = V(-math.sin(out.travelYaw), 0, -math.cos(out.travelYaw)) * out.speed end
	if bav then bav.AngularVelocity = V(0, out.yawRate, 0) end
	if gyro then gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.Angles(0, 0, -out.lean) end
	if susp and hit then
		local y = hit.Position.Y + chassis.Size.Y / 2 + 0.2
		-- on the grass beside the trough: its floor stands 0.4 - 3 studs over
		-- the grass and its edge stopped the car dead (Studio luge-wild: every
		-- cart that went over a lip was stuck there); near the edge the cart
		-- rides up onto the trough's level, as if up the bank
		if st.off then
			local floorY = O.Y + (at.floor or 0)
			local step = floorY - hit.Position.Y
			if step > 0 and step <= 3 and math.abs(at.lateral or 0) < LugeCart.edge(s.spec) + 4 then
				y = math.max(y, floorY + chassis.Size.Y / 2 + 0.2)
			end
			-- off a trestle, down on the ground under it: no way back up
			if step > 3 then
				s.fellFor = (s.fellFor or 0) + dt
				if s.fellFor > 1.5 and os.clock() - (s.askedAt or 0) > 2.5 then
					s.askedAt = os.clock()
					s.fellFor = 0
					ask("reset", "off")
				end
			else
				s.fellFor = 0
			end
		end
		susp.Position = V(chassis.Position.X, y, chassis.Position.Z)
		if susp.MaxForce.Y == 0 then susp.MaxForce = V(0, 4e4, 0) end
	end
	-- sounds, HUD
	if s.sounds then
		local f = math.clamp(out.speed / L.TOP, 0, 1.2)
		s.sounds.roll.Volume = SoundConfig.LUGE.ROLL.volume * math.clamp(f * 1.4, 0, 1) * (st.off and 0.4 or 1)
		s.sounds.roll.PlaybackSpeed = 0.7 + 0.6 * f
	end
	LugeHud.speed(out.speed * L.KMH)
	if s.runStart and not s.finished then LugeHud.clock(os.clock() - s.runStart, s.best) end
	LugeHud.el().reset.Visible = st.off == true
	-- harness: a sample a second
	if _auto and os.clock() - (s.sampledAt or 0) >= 1 then
		s.sampledAt = os.clock()
		report("luge_sample", { x = math.floor(x * 10) / 10, z = math.floor(z * 10) / 10, y = math.floor((chassis.Position.Y - O.Y) * 10) / 10,
			cmd = math.floor(out.speed), real = math.floor(actual), lat = math.floor((at.lateral or 0) * 10) / 10,
			s = math.floor(at.s), off = st.off == true, surface = hit and hit.Instance.Name or "none" })
	end
	updateCamera(dt, out)
end

-- ── Session ─────────────────────────────────────────────────────────────────

local function stopSession()
	local s = _s
	_s = nil
	if not s then return end
	if s.conn then s.conn:Disconnect() end
	if s.sounds then for _, snd in pairs(s.sounds) do snd:Destroy() end end
	LugeHud.show(false)
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
	local el = LugeHud.build()
	LugeHud.show(not LugeFilm.on)   -- (filming: a clean picture)
	LugeHud.clock(nil, msg.best)
	local s = { car = car, chassis = chassis, spec = msg.spec, st = LugeCart.newState(), best = msg.best, title = msg.title,
		phase = "boarding", scrapes = 0, hops = 0, runs = 0 }
	_s = s
	_camPos = nil
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end) end
	s.sounds = { roll = sound(SoundConfig.LUGE.ROLL, chassis, true) }
	s.sounds.roll.Volume = 0
	s.sounds.roll:Play()
	el.leave.Activated:Connect(function() ask("leave") end)
	el.reset.Activated:Connect(function() ask("reset", "asked") end)
	s.conn = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(drive, math.min(dt, 0.05))
		if not ok then warn("[LugeClient] " .. tostring(err)) end
	end)
end

RemoteEvents.LugeEvent.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	local kind = msg.kind
	if kind == "denied" then
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Alpine Luge", Text = msg.text or "Not now.", Duration = 5 })
		end)
		if _auto then report("luge_denied", { text = msg.text }) end
		return
	elseif kind == "session" then
		startSession(msg)
		return
	end
	local s = _s
	if not s then return end
	if kind == "lift" then
		s.phase = "lift"
		s.liftAt, s.liftSecs = msg.at, msg.secs
		LugeFilm.event("lift")
		s.finished = false
		LugeHud.lift(0)
		LugeHud.clock(nil, s.best)
	elseif kind == "gate" then
		s.phase = "gate"
		LugeFilm.event("gate")
		LugeHud.lift(nil)
		_camPos = nil
		-- the bell, three times, then GO
		task.spawn(function()
			for k = 3, 1, -1 do
				local t = msg.goAt - k * 0.7
				while workspace:GetServerTimeNow() < t do task.wait() end
				if _s ~= s then return end
				LugeHud.banner(tostring(k), Color3.fromRGB(255, 255, 255), 0.6)
				oneShot(SoundConfig.LUGE.BELL, workspace.CurrentCamera, 0.45, 1)
			end
		end)
	elseif kind == "go" then
		s.phase = "run"
		LugeFilm.event("go")
		s.st = LugeCart.newState()
		s.hint = nil
		s.runStart = os.clock()
		LugeHud.banner("GO!", Color3.fromRGB(255, 230, 90), 1)
		oneShot(SoundConfig.LUGE.BELL, workspace.CurrentCamera, 0.7, 1.15)
	elseif kind == "finish" then
		s.finished = true
		s.runs = msg.runs or (s.runs + 1)
		s.best = msg.best
		LugeHud.clock(msg.time, msg.best)
		LugeHud.banner(string.format("%.2f s", msg.time), msg.pb and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 255, 255), 3,
			msg.pb and "NEW BEST! Again? The chairlift's waiting" or "Again? The chairlift's waiting")
		if _auto then
			report("luge_finish", { time = msg.time, scrapes = s.scrapes, hops = s.hops, runs = s.runs })
			s.scrapes, s.hops = 0, 0
			if s.runs >= (_auto.runs or 2) then task.delay(1, function() ask("leave") end) end
		end
	elseif kind == "bump" then
		local k = s.kick or { x = 0, z = 0 }
		s.kick = { x = k.x + (msg.x or 0), z = k.z + (msg.z or 0) }
		_shake = math.min(0.6, _shake + 0.1 + (msg.power or 0) / 25)
		oneShot(SoundConfig.LUGE.BUMP, s.chassis, math.clamp(0.3 + (msg.power or 0) / 15, 0.3, 0.9), 0.9 + math.random() * 0.3)
		if (msg.power or 0) > 3 then LugeHud.banner("BONK!", Color3.fromRGB(255, 160, 200), 0.8, msg.with and ("you and " .. msg.with) or nil) end
		if _auto then report("luge_bumped", { power = msg.power }) end
		LugeFilm.event("bump")
	elseif kind == "reset" then
		s.st = LugeCart.newState()
		s.hint = nil
		s.pinnedFor = 0
		LugeHud.banner("BACK IN THE TROUGH", Color3.fromRGB(255, 255, 255), 1.4, "the marshals put you back")
		if _auto then report("luge_reset_seen", { reason = msg.reason }) end
	elseif kind == "ended" then
		stopSession()
	end
end)

KeyInput.began(function(input, processed)
	if processed then return end
	local k = KEYS[input.KeyCode]
	if k then _keys[k] = true return end
	if not _s then return end
	if input.KeyCode == Enum.KeyCode.R and _s.phase == "run" then
		ask("reset", "asked")
	elseif input.KeyCode == Enum.KeyCode.L then
		ask("leave")
	end
end)
KeyInput.ended(function(input)
	local k = KEYS[input.KeyCode]
	if k then _keys[k] = false end
end)

-- ── For everyone: the chairlift's chairs, other carts rolling ───────────────

local _rolls = {}
task.spawn(function()
	local hill = workspace:WaitForChild("AlpineLuge", 60)
	if not hill then return end
	local folder = hill:WaitForChild("LiftChairs", 30)
	local carts = hill:WaitForChild("Carts", 30)
	local chairs = folder and folder:GetChildren() or {}
	local Lf = LugeLayout.LIFT
	local a, b = O + Lf.bottom + V(0, Lf.hang, 0), O + Lf.top + V(0, Lf.hang, 0)
	local len = (b - a).Magnitude
	local up = (b - a).Unit
	local flat = V(up.X, 0, up.Z).Unit
	local offsets = {}
	for _, c in ipairs(chairs) do
		local base = c.PrimaryPart and c.PrimaryPart.CFrame
		offsets[c] = {}
		for _, p in ipairs(c:GetChildren()) do
			if p:IsA("BasePart") and base then offsets[c][p] = base:ToObjectSpace(p.CFrame) end
		end
	end
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam or (cam.CFrame.Position - (a + b) / 2).Magnitude > 900 then return end
		local t = workspace:GetServerTimeNow()
		for i, c in ipairs(chairs) do
			local f = (t * L.LIFT_SPEED / (2 * len) + i / #chairs) % 1
			local pos, dir
			if f < 0.5 then
				pos = a:Lerp(b, f * 2) + V(-2.6, 0, 0)
				dir = flat
			else
				pos = b:Lerp(a, (f - 0.5) * 2) + V(2.6, 0, 0)
				dir = -flat
			end
			local base = CFrame.lookAt(pos, pos + dir)
			for p, off in pairs(offsets[c] or {}) do p.CFrame = base * off end
		end
	end)
	-- other carts rumble as they roll
	while true do
		task.wait(0.25)
		local seen = {}
		for _, m in ipairs(carts and carts:GetChildren() or {}) do
			local c = m:IsA("Model") and m.PrimaryPart
			if c and not (_s and _s.car == m) then
				seen[m] = true
				local snd = _rolls[m]
				if not snd or not snd.Parent then
					snd = sound(SoundConfig.LUGE.ROLL, c, true)
					snd.RollOffMaxDistance = 140
					snd.RollOffMinDistance = 8
					snd:Play()
					_rolls[m] = snd
				end
				local v = c.Anchored and 0 or c.AssemblyLinearVelocity.Magnitude
				snd.Volume = SoundConfig.LUGE.ROLL.volume * math.clamp(v / L.TOP * 1.4, 0, 1)
				snd.PlaybackSpeed = 0.7 + 0.6 * math.clamp(v / L.TOP, 0, 1.2)
			end
		end
		for m, snd in pairs(_rolls) do
			if not seen[m] then snd:Destroy() _rolls[m] = nil end
		end
	end
end)

-- Studio harness: ride on autopilot (TestHarness/LugeTest)
local function autoStart()
	local raw = LocalPlayer:GetAttribute("LugeAuto")
	if not raw then return end
	local ok, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
	_auto = ok and cfg or { skill = 0.95 }
	if _auto.film then LugeFilm.start() end
	task.spawn(function()
		for _ = 1, 15 do
			local ok2, res = pcall(function() return RemoteEvents.LugeAction:InvokeServer("enter") end)
			report("luge_enter_try", { result = ok2 and res or "error" })
			if (ok2 and res == "ok") or _s then return end
			task.wait(2)
		end
	end)
end
LocalPlayer:GetAttributeChangedSignal("LugeAuto"):Connect(autoStart)
autoStart()
