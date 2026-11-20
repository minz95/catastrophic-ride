-- LugeCrowd.lua
-- Other guests on the Alpine Luge for filming (harness `luge.crowd = n`,
-- scenario record-luge): server-driven carts with a seated rider in a
-- helmet ride the chairlift and come down the trough round and round
-- (Shared/LugeDriver through Shared/LugeCart, the same step as players),
-- so the hill looks like a busy resort day. `follow(session)` puts one of
-- them on the lift just behind a player and lets it go a moment after that
-- player at the gate, a little faster: it catches up and bumps (the reel's
-- "bonk"). LugeManager resolves their touches with players (`knock`).
-- Live servers never start it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LugeCart = require(ReplicatedStorage.Shared.LugeCart)
local LugeDriver = require(ReplicatedStorage.Shared.LugeDriver)
local LugeLayout = require(ReplicatedStorage.Shared.LugeLayout)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local NewCars = require(ReplicatedStorage.Shared.NewCars)

local GpCars = require(script.Parent.GpCars)

local LugeCrowd = {}

LugeCrowd.LIST = {
	{ car = "Rubber Duck", shirt = Color3.fromRGB(250, 200, 40), skill = 0.85 },
	{ car = "Bathtub", shirt = Color3.fromRGB(80, 160, 230), skill = 0.8 },
	{ car = "Shopping Cart", shirt = Color3.fromRGB(230, 80, 80), skill = 0.95 },
	{ car = "Pizza", shirt = Color3.fromRGB(240, 140, 40), skill = 0.9 },
	{ car = "Red Sofa", shirt = Color3.fromRGB(150, 80, 200), skill = 0.75 },
	{ car = "Watermelon", shirt = Color3.fromRGB(60, 180, 90), skill = 0.85 },
	{ car = "Suitcase", shirt = Color3.fromRGB(240, 110, 170), skill = 0.8 },
	{ car = "Teddy Bear", shirt = Color3.fromRGB(120, 200, 220), skill = 0.85 },
}

local L = Constants.LUGE
local O = LobbyLayout.ORIGIN
local V = Vector3.new

local _bots = {}
local _conn
local _ray = RaycastParams.new()
_ray.FilterType = Enum.RaycastFilterType.Exclude
_ray.RespectCanCollide = true

local function cartCF(chassis, p, yaw)
	return CFrame.new(O + V(p.X, p.Y + chassis.Size.Y / 2 + 0.2, p.Z)) * CFrame.Angles(0, yaw, 0)
end

local LIFT_YAW = (function()
	local Lf = LugeLayout.LIFT
	return math.atan2(-(Lf.top.X - Lf.bottom.X), -(Lf.top.Z - Lf.bottom.Z))
end)()

local function setMovers(chassis, on)
	local bv, bav = chassis:FindFirstChild("DriveVelocity"), chassis:FindFirstChild("DriveAngular")
	if bv then bv.MaxForce = on and V(GpCars.MAX_FORCE, 0, GpCars.MAX_FORCE) or Vector3.zero end
	if bav then bav.MaxTorque = on and V(0, GpCars.MAX_FORCE, 0) or Vector3.zero end
end

-- back on the chairlift at `f` of the way up (anchored)
local function toLift(bot, f, now)
	bot.phase = "lift"
	bot.chassis.Anchored = true
	bot.liftSecs = LugeLayout.liftLength() / L.LIFT_SPEED
	bot.liftFrom = now - (f or 0) * bot.liftSecs
	bot.model:PivotTo(cartCF(bot.chassis, LugeLayout.liftAt(f or 0), LIFT_YAW))
end

local function release(bot, now)
	bot.phase = "run"
	bot.st = LugeCart.newState()
	bot.hint = nil
	bot.chassis.Anchored = false
	pcall(function() bot.chassis:SetNetworkOwner(nil) end)
	setMovers(bot.chassis, true)
	bot.goAt = now
end

local function stepBot(bot, dt, now, traffic)
	local chassis = bot.chassis
	if not chassis or not chassis.Parent then return end
	if bot.phase == "lift" then
		local f = (now - bot.liftFrom) / bot.liftSecs
		if f >= 1 then
			-- to the gate (slot 2: players take slot 1 first)
			bot.phase = "gate"
			local p, yaw = LugeLayout.startSlot(bot.slot or 2)
			bot.model:PivotTo(cartCF(chassis, p, yaw))
			bot.gateUntil = now + (bot.wait or 1.5)
			return
		end
		chassis.CFrame = cartCF(chassis, LugeLayout.liftAt(f), LIFT_YAW)
		return
	elseif bot.phase == "gate" then
		if bot.holdFor then
			-- following a player: off a moment after them
			local s = bot.holdFor
			if s.ended then bot.holdFor = nil
			elseif s.phase == "run" and s.runStart then
				if not bot.goAfter then bot.goAfter = now + (bot.followGap or 1.0) end
			end
			if not bot.goAfter or now < bot.goAfter then return end
			bot.holdFor, bot.goAfter = nil, nil
			release(bot, now)
		elseif now >= bot.gateUntil then
			release(bot, now)
		end
		return
	end
	-- down the trough, driven here
	local pos = chassis.Position
	local x, z = pos.X - O.X, pos.Z - O.Z
	local at = LugeLayout.at(x, z, pos.Y - O.Y, bot.hint)
	bot.hint = at.seg
	if at.s >= LugeLayout.length() - 3 or not LugeLayout.onGrounds(pos) then
		bot.laps += 1
		bot.driver = LugeDriver.new(bot.spec, bot.skill, bot.blind)
		bot.slot = 2
		toLift(bot, 0, now)
		return
	end
	local look = chassis.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local vel = chassis.AssemblyLinearVelocity
	local st = bot.st
	st.speed = math.min(st.speed or 0, V(vel.X, 0, vel.Z).Magnitude + 6)
	local others = {}
	for _, o in ipairs(traffic) do if o.model ~= bot.model then table.insert(others, o) end end
	local input = LugeDriver.input(bot.driver, st, x, z, yaw, at, others)
	local kick = bot.kick
	bot.kick = nil
	local out = LugeCart.step(bot.spec, st, input, { dt = dt, yaw = yaw, at = at, kick = kick })
	if out.wantReset then
		local geo = LugeLayout.geometry()
		local s = math.max(2, at.s - 8)
		local px, pz, dx, dz = geo:pointAt(s)
		chassis.Anchored = true
		bot.model:PivotTo(cartCF(chassis, V(px, geo:heightAt(s), pz), math.atan2(-dx, -dz)))
		task.delay(0.3, function() if chassis.Parent then chassis.Anchored = false end end)
		bot.st = LugeCart.newState()
		bot.hint = nil
		return
	end
	local bv, bav = chassis:FindFirstChild("DriveVelocity"), chassis:FindFirstChild("DriveAngular")
	local gyro, susp = chassis:FindFirstChild("UprightGyro"), chassis:FindFirstChild("SuspensionHover")
	if bv then bv.Velocity = V(-math.sin(out.travelYaw), 0, -math.cos(out.travelYaw)) * out.speed end
	if bav then bav.AngularVelocity = V(0, out.yawRate, 0) end
	if gyro then gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.Angles(0, 0, -out.lean) end
	_ray.FilterDescendantsInstances = { bot.model.Parent }
	local hit = workspace:Raycast(pos + V(0, 2, 0), V(0, -14, 0), _ray)
	if susp and hit then
		local y = hit.Position.Y + chassis.Size.Y / 2 + 0.2
		if st.off then
			local floorY = O.Y + (at.floor or 0)
			local step = floorY - hit.Position.Y
			if step > 0 and step <= 3 and math.abs(at.lateral or 0) < LugeCart.edge(bot.spec) + 4 then
				y = math.max(y, floorY + chassis.Size.Y / 2 + 0.2)
			end
		end
		susp.Position = V(pos.X, y, pos.Z)
	end
end

--- Builds n guests into `folder` and starts them, spread up the chairlift.
-- Returns the list.
function LugeCrowd.start(folder, n)
	LugeCrowd.stop()
	local SeatedRider = require(ServerScriptService.Modules.SeatedRider)
	local now = os.clock()
	for k = 1, math.min(n or 6, #LugeCrowd.LIST) do
		local g = LugeCrowd.LIST[k]
		local ride = NewCars.ride(g.car)
		local model = ride and GpCars.build(ride, CFrame.new(O + LugeLayout.LIFT.bottom + V(0, 3, 0)), "Guest" .. k)
		if model then
			model.Name = "LugeGuest" .. k
			model:SetAttribute("GpCar", nil)
			model:SetAttribute("LugeCart", true)
			model:SetAttribute("Guest", true)
			GpCars.passThrough(model, "LugeCart")
			model.Parent = folder
			pcall(function()
				local rider = SeatedRider.seat(model, model, g.shirt, { passenger = true, fallback = true })
				if rider then GpCars.wearHelmet(rider, g.shirt) end
			end)
			local _, bars = GpCars.specOf(ride, nil)
			local _, width = GpCars.shapeOf(model)
			local spec = LugeCart.spec(bars, width / 2)
			local bot = { model = model, chassis = model.PrimaryPart, spec = spec, skill = g.skill, laps = 0, slot = 2,
				driver = LugeDriver.new(spec, g.skill), st = LugeCart.newState() }
			setMovers(bot.chassis, true)
			-- spread up the lift, a couple straight onto the hill
			toLift(bot, (k - 1) / math.max(n, 1), now)
			table.insert(_bots, bot)
		end
	end
	_conn = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		local traffic = {}
		for _, b in ipairs(_bots) do
			local c = b.chassis
			if b.phase == "run" and c and c.Parent then
				local o = LugeLayout.at(c.Position.X - O.X, c.Position.Z - O.Z, c.Position.Y - O.Y, b.hint)
				table.insert(traffic, { model = b.model, s = o.s, lateral = o.lateral, speed = c.AssemblyLinearVelocity.Magnitude })
			end
		end
		for _, b in ipairs(_bots) do
			local ok, err = pcall(stepBot, b, math.min(dt, 0.05), t, traffic)
			if not ok then warn("[LugeCrowd] " .. tostring(err)) end
		end
	end)
	return _bots
end

--- One guest onto the lift just behind player session `s` (it waits at
-- the gate for them, then goes `gap` s later, a little faster and not
-- looking: it catches up and bumps).
function LugeCrowd.follow(s, gap)
	local best
	for _, b in ipairs(_bots) do
		if not b.following and (b.phase == "lift" or b.phase == "gate") then best = b break end
	end
	best = best or _bots[1]
	if not best then return end
	best.following = true
	best.holdFor = s
	best.followGap = gap or 1.0
	best.goAfter = nil
	best.slot = 2
	best.skill = 1.15
	best.blind = true
	best.driver = LugeDriver.new(best.spec, best.skill, true)
	toLift(best, 0, os.clock() + 1.5)   -- (starts up 1.5 s after the player)
	task.delay(90, function() best.following = false best.blind = false end)
end

--- A touch from another cart (LugeManager): guest `model` is pushed by (dx, dz).
function LugeCrowd.knock(model, dx, dz)
	for _, b in ipairs(_bots) do
		if b.model == model then
			local k = b.kick or { x = 0, z = 0 }
			b.kick = { x = k.x + dx, z = k.z + dz }
			return true
		end
	end
	return false
end

--- The guests riding now (for LugeManager's touches).
function LugeCrowd.riding()
	local out = {}
	for _, b in ipairs(_bots) do
		if b.phase == "run" and b.chassis and b.chassis.Parent and not b.chassis.Anchored then table.insert(out, b) end
	end
	return out
end

function LugeCrowd.stop()
	if _conn then _conn:Disconnect() _conn = nil end
	for _, b in ipairs(_bots) do if b.model then b.model:Destroy() end end
	_bots = {}
end

return LugeCrowd
