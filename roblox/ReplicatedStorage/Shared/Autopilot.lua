-- Autopilot.lua
-- A simulated driver that follows a TrackGeometry centerline and produces
-- KEYBOARD STATE ({ W, A, S, D, ... }), so it drives through exactly the same
-- VehicleController path as a human. Pure: no Roblox types.
--
-- Used by the harness bots (BotDriver), the Studio RaceSim, and the offline
-- kinematic simulator in tests/.
--
--   local ap = Autopilot.new(geo, Autopilot.PROFILES.average, seed)
--   local keys, info = ap:update({ x, z, yaw, speed, forward, maxSpeed, turnSpeed, t,
--                                  isSky, biome, travelYaw })
--     speed    horizontal speed (studs/s)
--     forward  signed speed along LookVector (negative = reversing); optional
--     turnSpeed the rate the car really turns at (VehicleController.turnRate)
--
-- yaw follows Roblox: LookVector = (-sin(yaw), 0, -cos(yaw)).

local VehicleController = require(script.Parent.VehicleController)

local Autopilot = {}
Autopilot.__index = Autopilot

-- Driver profiles. Numbers are deliberately human-ish: digital (keyboard)
-- steering with a dead band, a reaction delay, and imperfect lines.
--   lookahead   base distance to the aim point (studs), grows with speed
--   speedLook   extra lookahead per stud/s of speed
--   deadband    heading error (radians) tolerated before pressing A/D
--   liftAngle   heading error (radians) above which the driver lets go of W
--   reaction    seconds between seeing and pressing
--   wobble      amplitude (studs) of a slow sideways drift of the aim line
--   lineOffset  constant offset from the centerline (studs, + = right)
--   anticipation 0..1: how well the driver predicts where the car will be
--               pointing once their reaction delay has passed (1 = perfectly).
--               Without it, keyboard steering at TurnSpeed 3 rad/s overshoots.
--   cornerMargin how much of the car's turn rate a corner may demand before
--               the driver lifts (×1) or brakes (×1.4); > 1 = brakes late.
--   drift       holds Shift through a corner that is too sharp for grip at
--               this speed but not for a drift (instead of braking).
Autopilot.PROFILES = {
	expert  = { lookahead = 14, speedLook = 0.30, deadband = 0.04, liftAngle = 0.60, reaction = 0.12, anticipation = 1.00, wobble = 0, lineOffset = 0, cornerMargin = 0.95, drift = true },
	average = { lookahead = 12, speedLook = 0.25, deadband = 0.08, liftAngle = 0.75, reaction = 0.20, anticipation = 0.90, wobble = 3, lineOffset = 0, cornerMargin = 1.10, drift = true },
	novice  = { lookahead = 10, speedLook = 0.20, deadband = 0.14, liftAngle = 0.95, reaction = 0.30, anticipation = 0.75, wobble = 6, lineOffset = 0, cornerMargin = 1.30 },
}

-- Corner speed check: compare the turn rate the next stretch needs at the
-- current speed with what the car can do.
Autopilot.CORNER_LOOK = 3.0   -- × lookahead distance
Autopilot.CORNER_STEPS = { 1.5, 2.25, 3.0 }   -- windows checked (× lookahead)
Autopilot.DRIFT_AIM = 0.6     -- while drifting, steer by nose + this share of the slide
Autopilot.DRIFT_TURN = math.rad(50)   -- a bend this big ahead is worth a drift (turbo)
Autopilot.DRIFT_HOLD = math.rad(15)   -- keep drifting while this much turn is still near

-- "Stuck" = no new track progress, regardless of wiggling in place.
Autopilot.PROGRESS_EPS  = 6     -- studs of new progress that count as moving on
Autopilot.STUCK_TIME    = 2.5   -- seconds without progress before backing out
Autopilot.REVERSE_TIME  = 0.8
Autopilot.RESPAWN_AFTER = 7.0   -- seconds without progress before pressing R

local function wrapAngle(a)
	while a > math.pi do a -= 2 * math.pi end
	while a < -math.pi do a += 2 * math.pi end
	return a
end

function Autopilot.new(geo, profile, seed)
	local self = setmetatable({}, Autopilot)
	self.geo = geo
	self.profile = profile or Autopilot.PROFILES.average
	self.seed = seed or 1
	self.segHint = nil
	self.queue = {}         -- delayed decisions { at, keys }
	self.bestS = nil
	self.bestAt = nil
	self.reversedAt = nil
	self.reverseUntil = nil
	self.lastT = nil
	self.lastKeys = { W = false, S = false, A = false, D = false }
	self.reverseSteer = 1
	return self
end

--- Resets tracking after a teleport (respawn).
function Autopilot:resetTracking()
	self.segHint = nil
	self.bestS = nil
	self.bestAt = nil
	self.reversedAt = nil
	self.reverseUntil = nil
	self.queue = {}
end

-- Heading error toward a world point. Positive = point is to the RIGHT.
local function headingError(x, z, yaw, tx, tz)
	local lx, lz = -math.sin(yaw), -math.cos(yaw)
	local dx, dz = tx - x, tz - z
	local cross = lx * dz - lz * dx
	local dot = lx * dx + lz * dz
	return math.atan2(cross, dot)
end
Autopilot.headingError = headingError

--- Decide keys for this frame.
-- state: { x, z, yaw, speed, maxSpeed, turnSpeed, t }
-- returns keys, info { s, lateral, seg, err, respawn }
function Autopilot:update(state)
	local p = self.profile
	local t = state.t or 0
	local dt = self.lastT and math.max(t - self.lastT, 0) or 0
	self.lastT = t

	local proj = self.geo:project(state.x, state.z, self.segHint, 3)
	if self.segHint == nil then
		-- First frame / after respawn: global search to find our place.
		proj = self.geo:project(state.x, state.z)
	end
	self.segHint = proj.seg

	local look = p.lookahead + p.speedLook * (state.speed or 0)
	local wobble = 0
	if p.wobble > 0 then
		wobble = p.wobble * math.sin(proj.s / 90 + self.seed * 1.7)
	end
	local tx, tz = self.geo:offsetPoint(proj.s + look, p.lineOffset + wobble)
	-- While sliding, the car moves along travelYaw, not where its nose
	-- points: steer by a heading between the two (by the nose alone the
	-- driver counter-steers out of every drift).
	local yaw = state.yaw
	if self.drifting and state.travelYaw then
		yaw = state.yaw - wrapAngle(state.yaw - state.travelYaw) * Autopilot.DRIFT_AIM
	end
	local err = headingError(state.x, state.z, yaw, tx, tz)

	-- Anticipation: where will the car point when this decision lands?
	-- Integrate the keys already "in the pipe" over the reaction delay.
	-- The rate the car can really turn at this speed (grip), and drifting.
	local speedNow = state.speed or 0
	local gripTurn = VehicleController.effectiveTurn(state.turnSpeed or 1, speedNow, state.isSky, false, state.biome)
	local driftTurn = VehicleController.effectiveTurn(state.turnSpeed or 1, speedNow, state.isSky, true, state.biome)
	local turn = self.drifting and driftTurn or gripTurn
	local function omega(k)
		if k.A then return turn elseif k.D then return -turn end
		return 0
	end
	local horizon = t + p.reaction
	local cursor, active, dyaw = t, self.lastKeys, 0
	for _, q in ipairs(self.queue) do
		if q.at >= horizon then break end
		if q.at > cursor then
			dyaw += omega(active) * (q.at - cursor)
			cursor = q.at
		end
		active = q.keys
	end
	dyaw += omega(active) * math.max(horizon - cursor, 0)
	dyaw *= (p.anticipation or 1)
	local pyaw = yaw + dyaw
	local mid = yaw + dyaw * 0.5
	local travel = (state.speed or 0) * p.reaction * (p.anticipation or 1)
	local px = state.x - math.sin(mid) * travel
	local pz = state.z - math.cos(mid) * travel
	local predErr = headingError(px, pz, pyaw, tx, tz)

	-- Raw decision
	local keys = { W = false, S = false, A = false, D = false }
	if math.abs(predErr) > p.deadband then
		if predErr > 0 then keys.D = true else keys.A = true end
	end
	keys.W = math.abs(predErr) < p.liftAngle

	-- Slow for corners: the car keeps its speed when W is released now.
	-- Only while moving FORWARD: S on a reversing car only reverses harder,
	-- which used to rock a stalled car back and forth at sharp corners.
	local speed = state.speed or 0
	local forward = state.forward or speed
	if forward > 5 then
		-- The sharpest bend within CORNER_LOOK × lookahead, judged over a few
		-- distances (one long window averages a hairpin with its straights).
		-- Brake / lift: the turn over CORNER_LOOK × lookahead. Drift: also
		-- the sharpest bend over shorter windows (CORNER_STEPS), since one
		-- long window averages a hairpin with its straights.
		local yaw0 = self.geo:yawAt(proj.s)
		local far = math.max(look * Autopilot.CORNER_LOOK, 20)
		local required = math.abs(wrapAngle(self.geo:yawAt(proj.s + far) - yaw0)) * speed / far
		local sharpest, bigTurn, nearTurn = required, 0, 0
		for i, f in ipairs(Autopilot.CORNER_STEPS) do
			local w = math.max(look * f, 12)
			local turnNeeded = math.abs(wrapAngle(self.geo:yawAt(proj.s + w) - yaw0))
			sharpest = math.max(sharpest, turnNeeded * speed / w)
			bigTurn = turnNeeded   -- net turn over the longest window (a slalom cancels out)
			if i == 1 then nearTurn = turnNeeded end
		end
		local margin = (p.cornerMargin or 1) * gripTurn
		local canDrift = p.drift and not state.isSky and state.maxSpeed
			and speed > state.maxSpeed * (VehicleController.DRIFT_SPEED_RATIO + 0.05)
		local driftLimit = (p.cornerMargin or 1) * driftTurn * 1.15
		local driftable = canDrift and sharpest <= driftLimit
		if canDrift and sharpest > driftLimit then
			-- too fast even for a drift (e.g. a turbo into the next corner): brake
			keys.W = false
			keys.S = true
		elseif driftable and bigTurn >= Autopilot.DRIFT_TURN then
			keys.Shift = true          -- drift through it (turbo on the way out), keep the throttle
		elseif self.drifting and canDrift and (sharpest > margin * 0.7 or nearTurn >= Autopilot.DRIFT_HOLD) then
			keys.Shift = true          -- hold the drift to the corner exit
		elseif required > margin * 1.4 or math.abs(predErr) > p.liftAngle * 1.6 then
			keys.W = false
			keys.S = true
		elseif required > margin then
			keys.W = false
		end
	end
	self.drifting = keys.Shift == true

	-- Stuck handling: back out, then ask for a respawn.
	local info = { s = proj.s, lateral = proj.lateral, seg = proj.seg, err = err, respawn = false }
	if not self.bestS or proj.s > self.bestS + Autopilot.PROGRESS_EPS then
		self.bestS = proj.s
		self.bestAt = t
		self.reversedAt = nil
	end
	local stalled = t - (self.bestAt or t)
	if stalled > Autopilot.RESPAWN_AFTER then
		info.respawn = true
		self.bestAt = t
		self.reversedAt = nil
	elseif stalled > Autopilot.STUCK_TIME and not self.reverseUntil
		and (not self.reversedAt or t - self.reversedAt > Autopilot.STUCK_TIME) then
		self.reverseUntil = t + Autopilot.REVERSE_TIME
		self.reversedAt = t
		self.reverseSteer = (err > 0) and 1 or -1
	end
	if self.reverseUntil then
		if t < self.reverseUntil then
			keys = { W = false, S = true, A = self.reverseSteer > 0, D = self.reverseSteer < 0 }
		else
			self.reverseUntil = nil
		end
	end

	-- Reaction delay: act on what was decided `reaction` seconds ago.
	table.insert(self.queue, { at = t + p.reaction, keys = keys })
	local out = self.lastKeys
	while #self.queue > 0 and self.queue[1].at <= t do
		out = table.remove(self.queue, 1).keys
	end
	self.lastKeys = out
	return out, info
end

Autopilot.wrapAngle = wrapAngle

return Autopilot
