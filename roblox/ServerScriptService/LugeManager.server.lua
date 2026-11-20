-- LugeManager.server.lua
-- Runs the Alpine Luge (Shared/LugeLayout): builds the hill
-- (Modules/Maps/LugeHill) and each rider's session, round and round:
--   the ticket booth in town (prompt LugeAction "enter") → a car you own?
--   (a new car or a Legend Ride; else "No car, no ride!") → your car built
--   at the bottom station, you seated with a helmet → the chairlift carries
--   it up (anchored, tweened along the cable) → the start gate (two slots
--   side by side; the bar lifts START_HOLD s later, once the client says it
--   sits in its car) → down the trough, driven by your client
--   (Shared/LugeCart on the car's movers) → past the finish your time
--   (and best, rec.luge) → FINISH_HOLD s, then the chairlift again. LEAVE
--   ends it any time: back in town by the booth.
-- Carts pass through each other (collision group LugeCart); every frame
-- the server finds touching pairs (Shared/CarBump) and sends each rider a
-- push (LugeEvent "bump"): friends bump, nobody stops dead. Resets: the
-- client asks (off the trough too long, pinned, R), the server also puts
-- back a cart that is stuck or off the hill.
-- Open where the Junk GP is (the hub place, HubTest, or a harness session
-- with `luge`); elsewhere the hill stands and the booth says it opens with
-- the new Junk Town.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LugeLayout = require(ReplicatedStorage.Shared.LugeLayout)
local LugeCart = require(ReplicatedStorage.Shared.LugeCart)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local CarBump = require(ReplicatedStorage.Shared.CarBump)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local Modules = ServerScriptService.Modules
local GpCars = require(Modules.GpCars)
local LugeHill = require(Modules.Maps.LugeHill)
local PlayerStore = require(Modules.PlayerStore)
local Telemetry = require(Modules.Telemetry)

local L = Constants.LUGE
local O = LobbyLayout.ORIGIN
local V = Vector3.new

local GROUP = "LugeCart"   -- carts pass through each other (GpCars.passThrough)

local _enabled = false
local _hill
local _sessions = {}   -- userId → session
local _askedAt = {}
local _bumpedAt = {}

local HELMETS = { Color3.fromRGB(240, 120, 40), Color3.fromRGB(60, 150, 230), Color3.fromRGB(240, 200, 40),
	Color3.fromRGB(80, 190, 110), Color3.fromRGB(220, 80, 160) }

local function now() return workspace:GetServerTimeNow() end

local function send(player, msg)
	pcall(function() RemoteEvents.LugeEvent:FireClient(player, msg) end)
end

local function count()
	local n = 0
	for _ in pairs(_sessions) do n += 1 end
	return n
end

-- the chassis' centre over a floor at height y (offsets) at (x, z), facing yaw
local function cartCF(chassis, x, y, z, yaw)
	local p = O + V(x, y + chassis.Size.Y / 2 + 0.2, z)
	return CFrame.new(p) * CFrame.Angles(0, yaw, 0)
end

-- ── Sessions ────────────────────────────────────────────────────────────────

local function endSession(s, reason)
	if not s or s.ended then return end
	s.ended = true
	_sessions[s.player.UserId] = nil
	local player = s.player
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Sit = false end
	if s.car then s.car:Destroy() end
	player:SetAttribute("LugeCart", nil)
	if char then
		GpCars.takeOffHelmet(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and player.Parent then
			local spot = O + LugeLayout.EXIT + V(math.random(-2, 2), 3 + (hum and hum.HipHeight or 2), math.random(-2, 2))
			task.defer(function()
				if char.Parent then char:PivotTo(CFrame.lookAt(spot, spot + V(0, 0, 1))) end
			end)
		end
	end
	if player.Parent then
		send(player, { kind = "ended", reason = reason })
		pcall(function() require(Modules.LegendShop).refresh(player) end)
	end
	Telemetry.record("luge_end", { userId = player.UserId, reason = reason, runs = s.runs, best = s.best })
end

local function deny(player, reason, text)
	send(player, { kind = "denied", reason = reason, text = text })
	Telemetry.record("luge_denied", { userId = player.UserId, reason = reason })
	return "denied: " .. reason
end

-- puts the cart down in the trough at distance `along` (anchored a moment,
-- the movers back on: GpCars.place)
local function placeAt(s, along)
	local geo = LugeLayout.geometry()
	along = math.clamp(along, 2, geo.length - 2)
	local x, z, dx, dz = geo:pointAt(along)
	GpCars.place(s.car, cartCF(s.chassis, x, geo:heightAt(along), z, math.atan2(-dx, -dz)))
	s.hint = nil
	s.lastPos = nil
	s.lastMoveAt = now()
end

local function resetCart(s, reason)
	if not s.chassis or s.phase ~= "run" then return end
	local x, z = s.chassis.Position.X - O.X, s.chassis.Position.Z - O.Z
	placeAt(s, (s.maxS or 0) - 8)
	s.resets += 1
	s.lastReset = now()
	send(s.player, { kind = "reset", reason = reason })
	Telemetry.record("luge_reset", { userId = s.player.UserId, reason = reason, x = math.floor(x), z = math.floor(z) })
end

-- a free start slot (1 or 2): none of the other carts at the gate holds it
local function freeSlot()
	for k = 1, 2 do
		local taken = false
		for _, o in pairs(_sessions) do
			if o.phase == "gate" and o.slot == k then taken = true end
		end
		if not taken then return k end
	end
	return nil
end

-- the hanger from the cable down to the car while it rides the lift
local function carrier(s)
	local model = s.car
	local _, size = model:GetBoundingBox()
	local top = s.chassis.Position.Y - s.chassis.Size.Y / 2 + size.Y + 0.2
	local cable = s.chassis.Position.Y - s.chassis.Size.Y / 2 - 0.2 + LugeLayout.LIFT.hang
	local h = math.max(1, cable - top)
	local p = Instance.new("Part")
	p.Name = "LugeCarrier"
	p.Size = V(0.3, h, 0.3)
	p.CFrame = CFrame.new(s.chassis.Position.X, top + h / 2, s.chassis.Position.Z)
	p.Color = Color3.fromRGB(60, 60, 66)
	p.Material = Enum.Material.Metal
	p.Massless = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.Anchored = false, false, false, false
	local grip = Instance.new("Part")
	grip.Name = "LugeGrip"
	grip.Size = V(3, 0.3, 0.3)
	grip.CFrame = CFrame.new(s.chassis.Position.X, top + h, s.chassis.Position.Z)
	grip.Color = p.Color
	grip.Material = Enum.Material.Metal
	grip.Massless = true
	grip.CanCollide, grip.CanQuery, grip.CanTouch, grip.Anchored = false, false, false, false
	for _, q in ipairs({ p, grip }) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = s.chassis, q
		w.Parent = q
		q.Parent = model
	end
	return { p, grip }
end

-- moves the anchored cart from `a` to `b` over `secs` (eased when `ease`),
-- a step every frame; false when the session ended on the way
local function carry(s, a, b, secs, ease)
	local t0 = now()
	while not s.ended do
		local f = math.clamp((now() - t0) / secs, 0, 1)
		local g = ease and (1 - math.cos(f * math.pi)) / 2 or f
		if s.chassis.Parent then s.chassis.CFrame = a:Lerp(b, g) end
		if f >= 1 then return true end
		task.wait(1 / 30)
	end
	return false
end

-- one loop: up the lift, the gate, down the trough (the run is watched by
-- stepSession; the next loop starts after the finish)
local function ride(s)
	if s.ended then return end
	local chassis = s.chassis
	-- hooked on at the bottom station, facing up the hill
	s.phase = "lift"
	chassis.Anchored = true
	local Lf = LugeLayout.LIFT
	local yaw = math.atan2(-(Lf.top.X - Lf.bottom.X), -(Lf.top.Z - Lf.bottom.Z))
	s.car:PivotTo(cartCF(chassis, Lf.bottom.X, Lf.bottom.Y, Lf.bottom.Z, yaw))
	local parts = carrier(s)
	local secs = LugeLayout.liftLength() / L.LIFT_SPEED
	send(s.player, { kind = "lift", secs = secs, at = now() })
	local goal = cartCF(chassis, Lf.top.X, Lf.top.Y, Lf.top.Z, yaw)
	if not carry(s, chassis.CFrame, goal, secs, false) then return end
	for _, q in ipairs(parts) do q:Destroy() end
	-- off the lift, down to the gate (wait for a free slot)
	local slot = freeSlot()
	while not slot and not s.ended do task.wait(0.25) slot = freeSlot() end
	if s.ended then return end
	s.slot = slot
	s.phase = "gate"
	local p, gyaw = LugeLayout.startSlot(slot)
	if not carry(s, chassis.CFrame, cartCF(chassis, p.X, p.Y, p.Z, gyaw), 1.2, true) then return end
	local goAt = now() + L.START_HOLD
	send(s.player, { kind = "gate", goAt = goAt, slot = slot })
	while now() < goAt and not s.ended do task.wait(0.05) end
	-- the client says it sits in its car (it owns its character; see GpManager)
	local waitFrom = now()
	while not s.ready and now() - waitFrom < L.READY_WAIT and not s.ended do task.wait(0.05) end
	if s.ended then return end
	GpCars.release(s.car, s.player)
	s.phase = "run"
	s.runStart = now()
	s.maxS, s.hint, s.lastPos, s.lastMoveAt = 0, nil, nil, now()
	send(s.player, { kind = "go" })
	Telemetry.record("luge_go", { userId = s.player.UserId, slot = slot, ready = s.ready == true })
end

local function finish(s)
	s.phase = "done"
	local time = now() - s.runStart
	s.runs += 1
	local pb = not s.best or time < s.best
	if pb then s.best = time end
	local rec = PlayerStore.get(s.player)
	if rec then
		rec.luge = rec.luge or {}
		rec.luge.runs = (rec.luge.runs or 0) + 1
		if not rec.luge.best or time < rec.luge.best then
			rec.luge.best = time
			rec.luge.car = s.title
		end
		pcall(function() PlayerStore.saveSoon(s.player) end)
	end
	send(s.player, { kind = "finish", time = time, best = s.best, pb = pb, alltime = rec and rec.luge.best, runs = s.runs })
	Telemetry.record("luge_run", { userId = s.player.UserId, time = time, pb = pb, car = s.title })
	task.delay(L.FINISH_HOLD, function()
		if not s.ended and s.phase == "done" then ride(s) end
	end)
end

local function stepSession(s, dt)
	local player = s.player
	local car = s.car
	local chassis = s.chassis
	if not chassis or not chassis.Parent or not player.Parent then return endSession(s, "gone") end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or (hum.Health or 100) <= 0 then return endSession(s, "died") end
	local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
	if not GpCars.hasHelmet(char) then
		GpCars.takeOffHelmet(char)
		GpCars.wearHelmet(char, s.helmet)
	end
	-- out of the seat (Space): put back in it, or out after a while
	if seat and seat.Occupant ~= hum then
		s.offSeatSince = s.offSeatSince or now()
		pcall(function() seat:Sit(hum) end)
		if now() - s.offSeatSince > 3 then return endSession(s, "left_seat") end
	else
		s.offSeatSince = nil
	end
	if s.phase ~= "run" then return end
	local pos = chassis.Position
	if not LugeLayout.onGrounds(pos) then return resetCart(s, "off_grounds") end
	local t = now()
	local at = LugeLayout.at(pos.X - O.X, pos.Z - O.Z, pos.Y - O.Y, s.hint)
	s.hint = at.seg
	-- progress (a jump further than a cart can roll does not count)
	if at.s > s.maxS and at.s - s.maxS < (L.TOP * 2 + 10) * dt + 4 then s.maxS = at.s end
	if s.lastPos then
		local moved = (V(pos.X, 0, pos.Z) - V(s.lastPos.X, 0, s.lastPos.Z)).Magnitude
		if moved > 1 then s.lastMoveAt = t end
	end
	s.lastPos = pos
	if t - s.lastMoveAt > L.STUCK then return resetCart(s, "stuck") end
	if s.maxS >= LugeLayout.finishS() then finish(s) end
end

local function enter(player)
	if not _enabled then
		return deny(player, "closed", "The Alpine Luge opens with the new Junk Town. Soon!")
	end
	if _sessions[player.UserId] then return "denied: already" end
	if player:GetAttribute("GpCar") then return deny(player, "racing", "Finish your Grand Prix first!") end
	local rec = PlayerStore.get(player)
	if not rec then return deny(player, "loading", "Still loading your garage, try again in a moment.") end
	if not GpCars.ownsAny(rec) then
		return deny(player, "no_car", "No car, no ride! Pick one up at Junk Motors, then come back.")
	end
	if count() >= L.MAX_CARTS then return deny(player, "full", "The hill is full. Try again in a minute!") end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or (hum.Health or 100) <= 0 then return "denied: no character" end
	local owned = GpCars.rideOf(player, rec)
	if not owned then return deny(player, "no_car", "No car, no ride!") end
	local Lf = LugeLayout.LIFT
	local car, _, bars = nil, nil, nil
	car = GpCars.build(owned, CFrame.new(O + Lf.bottom + V(0, 3, 0)), player.Name)
	if not car then return deny(player, "build", "The lift man dropped a spanner. Try again!") end
	bars = select(2, GpCars.specOf(owned, nil))
	car.Name = "Luge_" .. player.Name
	car:SetAttribute("GpCar", nil)
	car:SetAttribute("LugeCart", true)
	car:SetAttribute("UserId", player.UserId)
	GpCars.passThrough(car, GROUP)
	local _, width = GpCars.shapeOf(car)
	local spec = LugeCart.spec(bars, width / 2)
	car.Parent = _hill:FindFirstChild("Carts") or _hill
	player:SetAttribute("LugeCart", true)
	local worn = char:FindFirstChild(require(Modules.LegendShop).WORN)
	if worn then worn:Destroy() end
	local s = {
		player = player, car = car, chassis = car.PrimaryPart, spec = spec, title = owned.title, runs = 0, resets = 0,
		best = nil, phase = "boarding", helmet = HELMETS[(math.abs(player.UserId) % #HELMETS) + 1], lastReset = 0,
	}
	_sessions[player.UserId] = s
	GpCars.wearHelmet(char, s.helmet)
	local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
	task.spawn(function()
		-- by the car first, then seated (as at the GP: the client owns its
		-- character, and the seated root leads the car once it is let go)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and seat then
			char:PivotTo(CFrame.new(seat.Position + V(-4, 3, 0)) * root.CFrame.Rotation)
			task.wait(0.4)
		end
		for _ = 1, 10 do
			if s.ended then return end
			if seat and seat.Occupant == hum then break end
			pcall(function() seat:Sit(hum) end)
			task.wait(0.15)
		end
		send(player, { kind = "session", car = car, spec = spec, title = owned.title, best = rec.luge and rec.luge.best })
		ride(s)
	end)
	Telemetry.record("luge_enter", { userId = player.UserId, car = owned.title })
	return "ok"
end

-- ── Carts touching ───────────────────────────────────────────────────────────

local function contacts()
	local folder = _hill and _hill:FindFirstChild("Carts")
	if not folder then return end
	local list, owner = {}, {}
	for _, s in pairs(_sessions) do
		local c = s.chassis
		if s.phase == "run" and c and c.Parent and not c.Anchored then
			local look = c.CFrame.LookVector
			local vel = c.AssemblyLinearVelocity
			table.insert(list, { id = s.car, x = c.Position.X, z = c.Position.Z, vx = vel.X, vz = vel.Z,
				yaw = math.atan2(-look.X, -look.Z), length = c.Size.Z, width = c.Size.X })
			owner[s.car] = s
		end
	end
	if #list < 2 then return end
	local t = now()
	for _, h in ipairs(CarBump.find(list, L.BUMP)) do
		local key = h.a.Name .. "|" .. h.b.Name
		if t - (_bumpedAt[key] or 0) >= L.BUMP.GAP then
			_bumpedAt[key] = t
			local sa, sb = owner[h.a], owner[h.b]
			send(sa.player, { kind = "bump", x = h.ax, z = h.az, power = h.power, with = sb.player.DisplayName })
			send(sb.player, { kind = "bump", x = h.bx, z = h.bz, power = h.power, with = sa.player.DisplayName })
			local p = h.a.PrimaryPart.Position
			Telemetry.record("luge_bump", { a = sa.player.Name, b = sb.player.Name, power = math.floor(h.power * 10) / 10,
				x = math.floor(p.X - O.X), z = math.floor(p.Z - O.Z) })
		end
	end
end

-- ── Remotes ─────────────────────────────────────────────────────────────────

RemoteEvents.LugeAction.OnServerInvoke = function(player, action, why)
	local s = _sessions[player.UserId]
	if action == "enter" then
		return enter(player)
	elseif action == "leave" then
		if s then endSession(s, "leave") return "ok" end
		return "denied: none"
	elseif action == "ready" then
		if s then s.ready = true end
		return "ok"
	elseif action == "reset" then
		if not s or s.phase ~= "run" then return "denied: none" end
		if now() - (_askedAt[player.UserId] or 0) < 2 or now() - s.lastReset < 2 then return "denied: wait" end
		_askedAt[player.UserId] = now()
		local reason = (why == "off" or why == "pinned") and why or "asked"
		resetCart(s, reason)
		return "ok"
	end
	return "denied: bad action"
end

Players.PlayerRemoving:Connect(function(player)
	local s = _sessions[player.UserId]
	if s then endSession(s, "left") end
	_askedAt[player.UserId] = nil
end)

local function hookPrompt(hill)
	for _, d in ipairs(hill:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d:GetAttribute("LugeAction") == "enter" then
			d.ObjectText = _enabled and "Alpine Luge" or "Opens with the new Junk Town"
			d.Triggered:Connect(function(player)
				local ok, err = pcall(enter, player)
				if not ok then warn("[LugeManager] enter: " .. tostring(err)) end
			end)
		end
	end
end

-- ── Boot ────────────────────────────────────────────────────────────────────

local function isEnabled()
	local t0 = os.clock()
	while ReplicatedStorage:GetAttribute("PlaceMode") == nil and os.clock() - t0 < 10 do task.wait(0.1) end
	if ReplicatedStorage:GetAttribute("PlaceMode") == "hub" then return true end
	local ok, harness = pcall(function() return require(Modules.HarnessConfig).get() end)
	return ok and type(harness) == "table" and ((harness.luge ~= nil and harness.luge ~= false) or (harness.gp ~= nil and harness.gp ~= false))
end

task.spawn(function()
	_hill = LugeHill.build(workspace)
	_enabled = isEnabled()
	ReplicatedStorage:SetAttribute("LugeOpen", _enabled)
	hookPrompt(_hill)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(contacts)
		if not ok then warn("[LugeManager] contacts: " .. tostring(err)) end
	end)
	local last = os.clock()
	while true do
		task.wait(0.1)
		local t = os.clock()
		local step = math.max(t - last, 0.05)
		last = t
		for _, s in pairs(_sessions) do
			local ok, err = pcall(stepSession, s, step)
			if not ok then warn("[LugeManager] " .. tostring(err)) end
		end
	end
end)
