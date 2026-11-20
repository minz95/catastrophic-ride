-- GpBots.lua
-- The Junk Grand Prix's race bots: Constants.GP.BOTS cars lapping the
-- circuit all the time (boxes 8 …), driven on the server by Shared/GpDriver
-- through the same Shared/GpCar step as players, timed by Shared/GpTiming
-- (they set laps on the board for players to beat), and every
-- BOT_PIT_EVERY laps into the pits for new tyres (the crew comes out for
-- everyone to see: GpManager's onPit).
--
--   GpBots.start(circuit, { onLap = fn(bot, ev), onPit = fn(bot, box, seconds) })
--   GpBots.stop()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GpCar = require(ReplicatedStorage.Shared.GpCar)
local GpDriver = require(ReplicatedStorage.Shared.GpDriver)
local GpLayout = require(ReplicatedStorage.Shared.GpLayout)
local GpTiming = require(ReplicatedStorage.Shared.GpTiming)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)

local GpCars = require(script.Parent.GpCars)

local GpBots = {}

-- who they are and what they drive (town names; rides from the Junk Motors
-- showroom and vote-winner-style builds, so the board has slow and fast cars)
GpBots.LIST = {
	{ name = "Turbo Tom", slots = { BODY = "Toilet", ENGINE = "Rocket" }, shirt = Color3.fromRGB(230, 120, 40) },
	{ name = "Vroom Vera", slots = { BODY = "Piano", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" }, shirt = Color3.fromRGB(200, 60, 160) },
	{ name = "Lap Lenny", slots = { BODY = "Bathtub", ENGINE = "Fan" }, shirt = Color3.fromRGB(60, 120, 230) },
	{ name = "Nitro Nell", slots = { BODY = "Red Sofa", ENGINE = "Hair Dryer" }, shirt = Color3.fromRGB(40, 170, 90) },
	{ name = "Skid Sid", slots = { BODY = "Shopping Cart" }, shirt = Color3.fromRGB(240, 200, 40) },
}
GpBots.FIRST_BOX = 8
GpBots.FLIP_RESET = 3     -- s on its roof before the marshals put it back
GpBots.SPACING = 4        -- s between bots leaving the pits at the start
GpBots.STUCK = 6          -- s without moving before a bot is put back

local _bots = {}
local _conn
local _hooks = {}
local _folder
local _traffic = {}   -- every GP car this frame: { model, s, lateral, speed }

local V = Vector3.new
local O = LobbyLayout.ORIGIN

local function surfaceAt(lat, seg)
	local a = math.abs(lat)
	local half = GpLayout.WIDTH / 2
	if a <= half then return "road" end
	local R = GpDriver.radii()
	if a <= half + GpLayout.KERB and (R[seg] or math.huge) < GpLayout.KERB_RADIUS then return "kerb" end
	return "grass"
end

local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function rideHeight(chassis)
	return O.Y + 0.3 + chassis.Size.Y / 2 + 0.2
end

local function drive(bot, chassis, speed, yawRate, travelYaw, lean, y)
	local bv = chassis:FindFirstChild("DriveVelocity")
	local bav = chassis:FindFirstChild("DriveAngular")
	local gyro = chassis:FindFirstChild("UprightGyro")
	local susp = chassis:FindFirstChild("SuspensionHover")
	if bv then bv.Velocity = V(-math.sin(travelYaw), 0, -math.cos(travelYaw)) * speed end
	if bav then bav.AngularVelocity = V(0, yawRate, 0) end
	if gyro then
		local _, yaw = chassis.CFrame:ToEulerAnglesYXZ()
		gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.Angles(0, 0, -(lean or 0))
	end
	if susp then susp.Position = V(chassis.Position.X, y or rideHeight(chassis), chassis.Position.Z) end
end

local function flipOver(bot, chassis, lean)
	for _, n in ipairs({ "DriveVelocity", "DriveAngular", "SuspensionHover" }) do
		local m = chassis:FindFirstChild(n)
		if m and m:IsA("BodyVelocity") then m.MaxForce = Vector3.zero
		elseif m and m:IsA("BodyAngularVelocity") then m.MaxTorque = Vector3.zero
		elseif m and m:IsA("BodyPosition") then m.MaxForce = Vector3.zero end
	end
	local gyro = chassis:FindFirstChild("UprightGyro")
	if gyro then gyro.MaxTorque = Vector3.zero end
	local look = chassis.CFrame.LookVector
	local side = (lean or 0) >= 0 and 1 or -1
	local T = Constants.GP.TUMBLE
	chassis.AssemblyAngularVelocity = look * (-T.SPIN * side) + V(0, side * T.YAW, 0)
	chassis.AssemblyLinearVelocity += V(0, T.UP, 0) + chassis.CFrame.RightVector * (T.SIDE * side)
	bot.flippedAt = os.clock()
end

local function placeOnTrack(bot, share)
	local geo = GpLayout.geometry()
	local s = (share * geo.length - 30) % geo.length
	local x, z, dx, dz = geo:pointAt(s)
	local chassis = bot.model.PrimaryPart
	local pos = O + V(x, 0, z)
	local cf = CFrame.lookAt(V(pos.X, rideHeight(chassis), pos.Z), V(pos.X + dx, rideHeight(chassis), pos.Z + dz))
	GpCars.place(bot.model, cf)
	bot.state = GpCar.newState()
	bot.state.speed = 0
	bot.flippedAt = nil
end

-- the path a bot drives in the pits: pitPath, with its box between the lane's ends
local function pitRoute(box)
	local path = GpLayout.pitPath()
	local stop = GpLayout.box(box)
	-- down the lane's middle, then a shallow line onto the mark (a sharp turn in met the garage wall)
	local lane = GpLayout.PIT.x
	return { path[1], path[2], path[3], V(lane - 1, 0, stop.Z + 24), stop, V(lane - 1, 0, stop.Z - 20), path[4], path[5], path[6] }, 5
end

local function stepBot(bot, dt, now)
	local model = bot.model
	local chassis = model and model.PrimaryPart
	if not chassis or not chassis.Parent or chassis.Anchored then return end
	-- on its roof: the marshals put it back after a while
	if bot.flippedAt then
		if os.clock() - bot.flippedAt > GpBots.FLIP_RESET then
			local share = GpLayout.where(chassis.Position.X - O.X, chassis.Position.Z - O.Z)
			placeOnTrack(bot, share)
		end
		return
	end
	local x, z = chassis.Position.X - O.X, chassis.Position.Z - O.Z
	-- stuck (against something, off the grounds): the marshals put it back
	if bot.mode ~= "stop" then
		local moved = bot.lastPos and (V(x, 0, z) - bot.lastPos).Magnitude or math.huge
		if moved > 1 then bot.lastPos, bot.lastMoveAt = V(x, 0, z), now end
		if now - (bot.lastMoveAt or now) > GpBots.STUCK or not GpLayout.onCircuit(chassis.Position) then
			bot.lastMoveAt = now
			local share = GpLayout.where(x, z)
			if _hooks.onReset then task.spawn(_hooks.onReset, bot, "stuck", x, z) end
			bot.mode, bot.route = "track", nil
			placeOnTrack(bot, share)
			return
		end
	end
	if _hooks.onSample and now - (bot.sampledAt or 0) >= 2 then
		bot.sampledAt = now
		task.spawn(_hooks.onSample, bot, x, z, bot.state.speed, chassis.AssemblyLinearVelocity.Magnitude)
	end
	local yaw = yawOf(chassis.CFrame)
	local vel = chassis.AssemblyLinearVelocity
	local st = bot.state
	local tdx, tdz = -math.sin(st.travelYaw or yaw), -math.cos(st.travelYaw or yaw)
	local actual = vel.X * tdx + vel.Z * tdz
	local input, p, surface, pit
	if bot.mode == "track" then
		local others = {}
		for _, o in ipairs(_traffic) do
			if o.model ~= model then table.insert(others, o) end
		end
		input, p = GpDriver.input(bot.driver, st, x, z, yaw, others, dt)
		surface = surfaceAt(p.lateral, p.seg)
		-- in for tyres: on the main straight's approach after enough laps
		local share = p.s / GpLayout.lapLength()
		if bot.wantPit and share > 0.9 and share < 0.97 and math.abs(z - GpLayout.PIT.entryZ) < 40 and x < -350 then
			bot.mode, bot.route, bot.leg = "pit", pitRoute(bot.box)
		end
	end
	if bot.mode == "pit" or bot.mode == "stop" then
		pit = true
		surface = "pit"
		local route = bot.route
		local target = route[bot.leg]
		if not target then
			bot.mode = "track"
			bot.wantPit = false
			return
		end
		local d = math.sqrt((target.X - x) ^ 2 + (target.Z - z) ^ 2)
		local stopLeg = bot.leg == 5
		if bot.mode == "stop" then
			input = { throttle = 0, brake = 1, steer = 0 }
			if now >= bot.stopUntil then
				st.tyre = 1
				bot.mode = "pit"
				bot.leg += 1
			end
		else
			local want = stopLeg and math.min(Constants.GP.PIT_LIMIT, math.max(4, d * 1.2)) or Constants.GP.PIT_LIMIT
			input = GpDriver.toward(bot.driver, st, x, z, yaw, target.X, target.Z, want, math.max(d, 8))
			if stopLeg and d < 2.5 then
				bot.mode = "stop"
				local secs = Constants.GP.PIT_STOP + math.random() * Constants.GP.PIT_JITTER
				bot.stopUntil = now + secs
				if _hooks.onPit then task.spawn(_hooks.onPit, bot, bot.box, secs) end
			elseif not stopLeg and d < 10 then
				bot.leg += 1
			end
		end
	end
	local out = GpCar.step(bot.spec, st, input, { dt = dt, yaw = yaw, surface = surface, actual = actual, pit = pit })
	if out.flip then
		if _hooks.onReset then task.spawn(_hooks.onReset, bot, out.crash and "crash" or "flip", x, z) end
		flipOver(bot, chassis, out.lean)
		return
	end
	drive(bot, chassis, out.speed, out.yawRate, out.travelYaw, out.lean)
	-- timing
	local share, lateral = GpLayout.where(x, z)
	for _, ev in ipairs(GpTiming.feed(bot.timing, share, lateral, now, pit)) do
		if ev.kind == "lap" then
			bot.laps += 1
			if bot.laps % Constants.GP.BOT_PIT_EVERY == 0 then bot.wantPit = true end
			if _hooks.onLap then task.spawn(_hooks.onLap, bot, ev) end
		end
	end
end

--- Builds the bots in their garages and starts them, one after another.
function GpBots.start(circuit, hooks)
	GpBots.stop()
	_hooks = hooks or {}
	local folder = circuit:FindFirstChild("Cars") or circuit
	_folder = folder
	local SeatedRider = require(ServerScriptService.Modules.SeatedRider)
	for i, b in ipairs(GpBots.LIST) do
		if i > Constants.GP.BOTS then break end
		local box = GpBots.FIRST_BOX + i - 1
		local stop = GpLayout.box(box)
		local pos = O + stop
		local ride = { title = b.slots.BODY, slots = b.slots, look = {} }
		local model, spec = GpCars.build(ride, CFrame.lookAt(pos + V(0, 3, 0), pos + V(0, 3, -10)), b.name)
		if model then
			model:SetAttribute("Bot", true)
			model:SetAttribute("Box", box)
			model.Parent = folder
			pcall(function()
				local rider = SeatedRider.seat(model, model, b.shirt, { passenger = true, fallback = true })
				if rider then GpCars.wearHelmet(rider, b.shirt) end
			end)
			local chassis = model.PrimaryPart
			local y = rideHeight(chassis)
			model:PivotTo(CFrame.lookAt(V(pos.X, y, pos.Z), V(pos.X, y, pos.Z - 10)))
			local skill = Constants.GP.BOT_SKILL[1] + (Constants.GP.BOT_SKILL[2] - Constants.GP.BOT_SKILL[1]) * (i - 1) / math.max(#GpBots.LIST - 1, 1)
			local bot = {
				name = b.name, model = model, spec = spec, box = box, state = GpCar.newState(),
				driver = GpDriver.new(spec, skill), timing = GpTiming.new(os.clock()), laps = 0,
				mode = "pit", route = select(1, pitRoute(box)), leg = 6, wantPit = false,
			}
			table.insert(_bots, bot)
			task.delay((i - 1) * GpBots.SPACING + 1, function()
				if model.Parent then GpCars.release(model, nil) end
			end)
		end
	end
	_conn = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		_traffic = GpLayout.traffic(_folder)
		for _, bot in ipairs(_bots) do
			local ok, err = pcall(stepBot, bot, math.min(dt, 0.05), now)
			if not ok then warn("[GpBots] " .. tostring(err)) end
		end
	end)
	return _bots
end

function GpBots.stop()
	if _conn then _conn:Disconnect() _conn = nil end
	for _, bot in ipairs(_bots) do
		if bot.model then bot.model:Destroy() end
	end
	_bots = {}
end

function GpBots.list() return _bots end

return GpBots
