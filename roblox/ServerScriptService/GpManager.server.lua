-- GpManager.server.lua
-- Runs the Junk Grand Prix (Shared/GpLayout): builds the circuit, starts the
-- race bots (Modules/GpBots), and runs each player's session:
--   the gate's desk (prompt GpAction "enter") → a car you own? (a new car or
--   a Legend Ride; else "No car, no race!") → a free garage (boxes 1 …
--   MAX_CARS) → your car built there, you seated with a helmet → five red
--   lights, out → an out lap and Constants.GP.LAPS timed laps (Shared/
--   GpTiming on the server, from the car's position) → back in town at the
--   gate, your best lap on the TOP LAPS board and in your record (rec.gp).
-- Pit stops: stop on your box's mark in the pit lane → the crew (drawn by
-- every client, GpEvent "crew") → new tyres (GpEvent "pit"; the client's
-- GpCar state holds the wear). Resets: the client asks after a flip
-- (GpAction "reset"), the server also puts back a car that is stuck, off
-- the grounds or out of its seat's reach.
-- Open in the hub place (Shared/Places "hub"), Studio with workspace
-- attribute HubTest, or a harness session with `gp = true`; elsewhere the
-- circuit stands but the desk says it opens with the new Junk Town.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GpLayout = require(ReplicatedStorage.Shared.GpLayout)
local GpTiming = require(ReplicatedStorage.Shared.GpTiming)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local Modules = ServerScriptService.Modules
local GpCars = require(Modules.GpCars)
local GpBots = require(Modules.GpBots)
local GpCircuit = require(Modules.Maps.GpCircuit)
local PlayerStore = require(Modules.PlayerStore)
local Telemetry = require(Modules.Telemetry)

local G = Constants.GP
local O = LobbyLayout.ORIGIN
local V = Vector3.new

local _enabled = false
local _circuit
local _sessions = {}   -- userId → session
local _board = {}      -- key → { name, time, car, bot }
local _allBest = nil   -- the session's best lap
local _allSectors = {} -- the session's best sectors
local _boxes = {}      -- box → userId
local harnessRun = false

local TEAM = { Color3.fromRGB(220, 40, 40), Color3.fromRGB(40, 90, 220), Color3.fromRGB(250, 160, 30),
	Color3.fromRGB(30, 170, 90), Color3.fromRGB(150, 60, 200), Color3.fromRGB(30, 180, 200), Color3.fromRGB(240, 240, 240) }

local function now() return workspace:GetServerTimeNow() end

local function send(player, msg)
	pcall(function() RemoteEvents.GpEvent:FireClient(player, msg) end)
end

local function sendAll(msg)
	pcall(function() RemoteEvents.GpEvent:FireAllClients(msg) end)
end

local function publishBoard()
	local list = GpTiming.ranked(_board, G.BOARD)
	ReplicatedStorage:SetAttribute("GpBoard", HttpService:JSONEncode(list))
	if _circuit then GpCircuit.setBoard(_circuit, list, GpTiming.format) end
end

-- a valid lap: onto the board if it beats the driver's line there
local function boardLap(key, name, time, car, bot)
	local e = _board[key]
	if not e or time < e.time then
		_board[key] = { name = name, time = time, car = car, bot = bot }
		publishBoard()
	end
	if not _allBest or time < _allBest then _allBest = time end
end

-- ── Sessions ────────────────────────────────────────────────────────────────

local function freeBox()
	for k = 1, math.min(G.MAX_CARS, GpLayout.PIT.boxes) do
		if not _boxes[k] then return k end
	end
	return nil
end

local function rideHeight(chassis)
	return O.Y + GpCircuit.ROAD_TOP + chassis.Size.Y / 2 + 0.2
end

local function endSession(s, reason)
	if not s or s.ended then return end
	s.ended = true
	_sessions[s.player.UserId] = nil
	if _boxes[s.box] == s.player.UserId then _boxes[s.box] = nil end
	local player = s.player
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Sit = false end
	if s.car then s.car:Destroy() end
	player:SetAttribute("GpCar", nil)
	if char then
		GpCars.takeOffHelmet(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and player.Parent then
			local spot = O + GpLayout.EXIT + V(math.random(-3, 3), 3 + (hum and hum.HipHeight or 2), math.random(-5, 5))
			task.defer(function()
				if char.Parent then char:PivotTo(CFrame.lookAt(spot, spot + V(1, 0, 0))) end
			end)
		end
	end
	if player.Parent then
		send(player, { kind = "ended", reason = reason })
		pcall(function() require(Modules.LegendShop).refresh(player) end)
	end
	Telemetry.record("gp_end", { userId = player.UserId, reason = reason, laps = s.lapsDone, best = s.best })
end

local function deny(player, reason, text)
	send(player, { kind = "denied", reason = reason, text = text })
	Telemetry.record("gp_denied", { userId = player.UserId, reason = reason })
	return "denied: " .. reason
end

local function enter(player)
	if not _enabled then
		return deny(player, "closed", "The Junk Grand Prix opens with the new Junk Town. Soon!")
	end
	if _sessions[player.UserId] then return "denied: already" end
	local rec = PlayerStore.get(player)
	if not rec then return deny(player, "loading", "Still loading your garage, try again in a moment.") end
	if not GpCars.ownsAny(rec) then
		return deny(player, "no_car", "No car, no race! Buy one at Junk Motors or Junk Auto Mart, then come back.")
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or (hum.Health or 100) <= 0 then return "denied: no character" end
	local box = freeBox()
	if not box then return deny(player, "full", "The track is full. Grab a seat in the grandstand!") end
	local ride = GpCars.rideOf(player, rec)
	if not ride then return deny(player, "no_car", "No car, no race!") end
	local stop = O + GpLayout.box(box)
	local car, spec = GpCars.build(ride, CFrame.lookAt(stop + V(0, 3, 0), stop + V(0, 3, -10)), player.Name)
	if not car then return deny(player, "build", "The mechanics dropped a spanner. Try again!") end
	_boxes[box] = player.UserId
	local chassis = car.PrimaryPart
	local y = rideHeight(chassis)
	car:PivotTo(CFrame.lookAt(V(stop.X, y, stop.Z), V(stop.X, y, stop.Z - 10)))
	car:SetAttribute("Box", box)
	car:SetAttribute("UserId", player.UserId)
	car.Parent = _circuit:FindFirstChild("Cars") or _circuit
	player:SetAttribute("GpCar", true)
	local worn = char:FindFirstChild(require(Modules.LegendShop).WORN)
	if worn then worn:Destroy() end
	GpCars.wearHelmet(char, TEAM[(box - 1) % #TEAM + 1])
	local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
	local t = now()
	local lightsAt = t + 1.5
	local outAt = lightsAt + 5 * G.LIGHTS.STEP + G.LIGHTS.HOLD[1] + math.random() * (G.LIGHTS.HOLD[2] - G.LIGHTS.HOLD[1])
	local s = {
		player = player, car = car, box = box, spec = spec, title = ride.title,
		timing = GpTiming.new(t), lapsDone = 0, best = nil, laps = {}, mySectors = {}, myBest = rec.gp and rec.gp.best,
		outAt = outAt, released = false, lastPos = nil, lastMoveAt = t, offSeatSince = nil, pits = 0, resets = 0,
		lastReset = 0,
	}
	_sessions[player.UserId] = s
	task.spawn(function()
		-- by the car first: the client owns its character, and seated far
		-- away it pulled the car to where it thought it stood (Studio
		-- gp-drive: the car turned up on the plaza at the lights)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and seat then
			char:PivotTo(CFrame.new(seat.Position + V(-5, 3, 0)) * root.CFrame.Rotation)
			task.wait(0.4)
		end
		-- seat them (a few tries: Sit can miss while the character settles)
		for _ = 1, 10 do
			if s.ended then return end
			if seat and seat.Occupant == hum then break end
			pcall(function() seat:Sit(hum) end)
			task.wait(0.15)
		end
		send(player, { kind = "session", car = car, box = box, spec = spec, laps = G.LAPS, title = ride.title,
			lightsAt = lightsAt, outAt = outAt, best = s.myBest })
		task.wait(math.max(0, outAt - now()))
		if s.ended then return end
		GpCars.release(car, player)
		s.released = true
		s.lastMoveAt = now()
	end)
	rec.gp = rec.gp or {}
	rec.gp.runs = (rec.gp.runs or 0) + 1
	PlayerStore.saveSoon(player)
	Telemetry.record("gp_enter", { userId = player.UserId, car = ride.title, box = box,
		top = math.floor(spec.top), grip = math.floor(spec.grip), stability = math.floor(spec.stability * 100) / 100 })
	return "ok"
end

local function resetCar(s, reason)
	local chassis = s.car and s.car.PrimaryPart
	if not chassis then return end
	s.resets += 1
	s.lastReset = now()
	local x, z = GpLayout.offset(chassis.Position)
	local cf
	if GpLayout.inPit(x, z) then
		local stop = O + GpLayout.box(s.box)
		local y = rideHeight(chassis)
		cf = CFrame.lookAt(V(stop.X, y, stop.Z), V(stop.X, y, stop.Z - 10))
	else
		local geo = GpLayout.geometry()
		local p = geo:project(x, z)
		local back = (p.s - 25) % geo.length
		local px, pz, dx, dz = geo:pointAt(back)
		local pos = O + V(px, 0, pz)
		local y = rideHeight(chassis)
		cf = CFrame.lookAt(V(pos.X, y, pos.Z), V(pos.X + dx, y, pos.Z + dz))
	end
	GpCars.place(s.car, cf)
	s.lastPos = nil
	s.lastMoveAt = now()
	send(s.player, { kind = "reset", reason = reason })
	Telemetry.record("gp_reset", { userId = s.player.UserId, reason = reason, x = math.floor(x), z = math.floor(z),
		y = math.floor(chassis.Position.Y - O.Y) })
end

local function finish(s)
	if s.finished then return end
	s.finished = true
	local list = GpTiming.ranked(_board, 100)
	local rank
	for i, e in ipairs(list) do
		if e.key == s.player.UserId then rank = i break end
	end
	local rec = PlayerStore.get(s.player)
	local pb = false
	if rec and s.best then
		rec.gp = rec.gp or {}
		if not rec.gp.best or s.best < rec.gp.best then
			rec.gp.best = s.best
			rec.gp.car = s.title
			pb = true
			PlayerStore.saveSoon(s.player)
		end
	end
	send(s.player, { kind = "done", laps = s.laps, best = s.best, rank = rank, of = #list, pb = pb,
		allBest = _allBest, title = s.title })
	Telemetry.record("gp_done", { userId = s.player.UserId, best = s.best, rank = rank, pits = s.pits, resets = s.resets })
	task.delay(G.DONE_SECONDS, function() endSession(s, "done") end)
end

local function onTiming(s, ev)
	if ev.kind == "sector" then
		local colour = GpTiming.colour(ev.time, s.mySectors[ev.index], _allSectors[ev.index])
		if s.timing.valid then
			if not s.mySectors[ev.index] or ev.time < s.mySectors[ev.index] then s.mySectors[ev.index] = ev.time end
			if not _allSectors[ev.index] or ev.time < _allSectors[ev.index] then _allSectors[ev.index] = ev.time end
		end
		send(s.player, { kind = "sector", index = ev.index, time = ev.time, colour = colour })
	elseif ev.kind == "lap" then
		local colour = ev.valid and GpTiming.colour(ev.time, s.best, _allBest) or "invalid"
		-- the last sector, timed at the line
		local s3 = ev.sectors[3]
		if s3 and ev.counted then
			local c3 = GpTiming.colour(s3, s.mySectors[3], _allSectors[3])
			if ev.valid then
				if not s.mySectors[3] or s3 < s.mySectors[3] then s.mySectors[3] = s3 end
				if not _allSectors[3] or s3 < _allSectors[3] then _allSectors[3] = s3 end
			end
			send(s.player, { kind = "sector", index = 3, time = s3, colour = c3 })
		end
		s.lapsDone += 1
		table.insert(s.laps, { lap = ev.lap, time = ev.time, valid = ev.valid })
		if ev.valid then
			if not s.best or ev.time < s.best then s.best = ev.time end
			boardLap(s.player.UserId, s.player.DisplayName, ev.time, s.title, false)
		end
		send(s.player, { kind = "lap", lap = ev.lap, time = ev.time, valid = ev.valid, colour = colour,
			of = G.LAPS, best = s.best })
		Telemetry.record("gp_lap", { userId = s.player.UserId, lap = ev.lap, time = ev.time, valid = ev.valid })
		if s.lapsDone >= G.LAPS then finish(s) end
	elseif ev.kind == "limits" then
		send(s.player, { kind = "limits" })
	elseif ev.kind == "start" then
		send(s.player, { kind = "start" })
	end
end

local function pitStop(s)
	s.pitting = true
	s.pits += 1
	local secs = G.PIT_STOP + math.random() * G.PIT_JITTER
	send(s.player, { kind = "pit", phase = "stop", seconds = secs })
	sendAll({ kind = "crew", box = s.box, seconds = secs, car = s.car })
	Telemetry.record("gp_pit", { userId = s.player.UserId, seconds = secs })
	task.delay(secs, function()
		if s.ended then return end
		send(s.player, { kind = "pit", phase = "go", seconds = secs })
		s.pitting = false
		s.pitDoneAt = now()
	end)
end

local function stepSession(s, dt)
	local player = s.player
	local car = s.car
	local chassis = car and car.PrimaryPart
	if not chassis or not chassis.Parent or not player.Parent then return endSession(s, "gone") end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or (hum.Health or 100) <= 0 then return endSession(s, "died") end
	local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
	if s.released then
		-- out of the seat (Space, a reset): put back in it, or out after a while
		if seat and seat.Occupant ~= hum then
			s.offSeatSince = s.offSeatSince or now()
			pcall(function() seat:Sit(hum) end)
			if now() - s.offSeatSince > 3 then return endSession(s, "left_seat") end
		else
			s.offSeatSince = nil
		end
	end
	if not s.released or s.finished then return end
	local pos = chassis.Position
	local t = now()
	local x, z = GpLayout.offset(pos)
	-- fell, flung off the grounds
	if not GpLayout.onCircuit(pos) then return resetCar(s, "off_grounds") end
	-- moving at all?
	if s.lastPos then
		local moved = (V(pos.X, 0, pos.Z) - V(s.lastPos.X, 0, s.lastPos.Z)).Magnitude
		-- a jump no car can make spoils the lap (G.TOP's best with room)
		if moved > (G.TOP[2] * 1.5 + 20) * dt then s.timing.valid = false end
		if moved > 1.5 then s.lastMoveAt = t end
	end
	s.lastPos = pos
	if not s.pitting and t - s.lastMoveAt > G.STUCK and t - (s.pitDoneAt or 0) > G.STUCK then
		return resetCar(s, "stuck")
	end
	local inPit = GpLayout.inPit(x, z)
	local share, lateral = GpLayout.where(x, z)
	for _, ev in ipairs(GpTiming.feed(s.timing, share, lateral, t, inPit)) do
		onTiming(s, ev)
		if s.ended or s.finished then return end
	end
	-- a stop on your own mark
	-- (not on the way out of the garage: only once the timing has started)
	if inPit and s.timing.started and not s.pitting and t - (s.pitDoneAt or 0) > 6 then
		local stop = O + GpLayout.box(s.box)
		local d = (V(pos.X, 0, pos.Z) - V(stop.X, 0, stop.Z)).Magnitude
		local v = chassis.AssemblyLinearVelocity
		if d <= G.PIT_STOP_RADIUS and V(v.X, 0, v.Z).Magnitude <= G.PIT_STOP_SPEED then pitStop(s) end
	end
end

-- ── Remotes and the prompt ──────────────────────────────────────────────────

local _askedAt = {}
RemoteEvents.GpAction.OnServerInvoke = function(player, action)
	local s = _sessions[player.UserId]
	if action == "leave" then
		if s then endSession(s, "leave") return "ok" end
		return "denied: none"
	elseif action == "reset" then
		if not s or not s.released or s.finished then return "denied: none" end
		if now() - (_askedAt[player.UserId] or 0) < 2 or now() - s.lastReset < 2 then return "denied: wait" end
		_askedAt[player.UserId] = now()
		resetCar(s, "flip")
		return "ok"
	elseif action == "enter" then
		return enter(player)
	end
	return "denied: bad action"
end

Players.PlayerRemoving:Connect(function(player)
	local s = _sessions[player.UserId]
	if s then endSession(s, "left") end
	_askedAt[player.UserId] = nil
end)

local function hookPrompt(circuit)
	for _, d in ipairs(circuit:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d:GetAttribute("GpAction") == "enter" then
			d.ObjectText = _enabled and "Junk Grand Prix" or "Opens with the new Junk Town"
			d.Triggered:Connect(function(player)
				local ok, err = pcall(enter, player)
				if not ok then warn("[GpManager] enter: " .. tostring(err)) end
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
	return ok and type(harness) == "table" and harness.gp ~= nil and harness.gp ~= false
end

task.spawn(function()
	_circuit = GpCircuit.build(workspace)
	_enabled = isEnabled()
	local okH, harness = pcall(function() return require(Modules.HarnessConfig).get() end)
	harnessRun = okH and harness ~= nil
	ReplicatedStorage:SetAttribute("GpOpen", _enabled)
	hookPrompt(_circuit)
	publishBoard()
	if _enabled then
		-- wait for the item models (the cars are built from them)
		local ServerStorage = game:GetService("ServerStorage")
		local t0 = os.clock()
		while os.clock() - t0 < 20 do
			local f = ServerStorage:FindFirstChild("ItemModels")
			if f and f:GetAttribute("Ready") then break end
			task.wait(0.25)
		end
		GpBots.start(_circuit, {
			onLap = function(bot, ev)
				if ev.valid then boardLap("bot:" .. bot.name, bot.name, ev.time, bot.model:GetAttribute("Title"), true) end
			end,
			onPit = function(bot, box, secs)
				sendAll({ kind = "crew", box = box, seconds = secs, car = bot.model })
			end,
			onReset = function(bot, reason, x, z)
				Telemetry.record("gp_bot_reset", { name = bot.name, reason = reason, x = math.floor(x), z = math.floor(z) })
			end,
			-- harness runs only: where each bot is every 2 s (tools/gp_trace.py)
			onSample = harnessRun and function(bot, x, z, cmd, real)
				Telemetry.record("gp_bot_sample", { name = bot.name, x = math.floor(x), z = math.floor(z),
					cmd = math.floor(cmd), real = math.floor(real), mode = bot.mode })
			end or nil,
		})
	end
	-- every session ten times a second (timing, pits, resets)
	local last = os.clock()
	while true do
		task.wait(0.1)
		local t = os.clock()
		local step = math.max(t - last, 0.05)
		last = t
		for _, s in pairs(_sessions) do
			local ok, err = pcall(stepSession, s, step)
			if not ok then warn("[GpManager] " .. tostring(err)) end
		end
	end
end)
