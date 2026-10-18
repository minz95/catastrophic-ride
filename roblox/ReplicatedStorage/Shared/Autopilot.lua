-- Autopilot.lua
-- A simulated driver that follows a TrackGeometry centerline and produces
-- KEYBOARD STATE ({ W, A, S, D, ... }), so it drives through exactly the same
-- VehicleController path as a human. Pure: no Roblox types.
--
-- Used by the harness bots (BotDriver), the Studio RaceSim, and the offline
-- kinematic simulator in tests/.
--
--   local ap = Autopilot.new(geo, Autopilot.PROFILES.average, seed)
--   local keys, info = ap:update({ x, z, yaw, speed, forward, maxSpeed, turnSpeed, t })
--     speed    horizontal speed (studs/s)
--     forward  signed speed along LookVector (negative = reversing); optional
--     turnSpeed the rate the car really turns at (VehicleController.turnRate)
--
-- yaw follows Roblox: LookVector = (-sin(yaw), 0, -cos(yaw)).

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
Autopilot.PROFILES = {
	expert  = { lookahead = 14, speedLook = 0.30, deadband = 0.04, liftAngle = 0.60, reaction = 0.12, anticipation = 1.00, wobble = 0, lineOffset = 0, cornerMargin = 0.95 },
	average = { lookahead = 12, speedLook = 0.25, deadband = 0.08, liftAngle = 0.75, reaction = 0.20, anticipation = 0.90, wobble = 3, lineOffset = 0, cornerMargin = 1.10 },
	novice  = { lookahead = 10, speedLook = 0.20, deadband = 0.14, liftAngle = 0.95, reaction = 0.30, anticipation = 0.75, wobble = 6, lineOffset = 0, cornerMargin = 1.30 },
}

-- Corner speed check: compare the turn rate the next stretch needs at the
-- current speed with what the car can do.
Autopilot.CORNER_LOOK = 3.0   -- × lookahead distance

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
	local err = headingError(state.x, state.z, state.yaw, tx, tz)

	-- Anticipation: where will the car point when this decision lands?
	-- Integrate the keys already "in the pipe" over the reaction delay.
	local turn = state.turnSpeed or 1
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
	local pyaw = state.yaw + dyaw
	local mid = state.yaw + dyaw * 0.5
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
		local far = math.max(look * Autopilot.CORNER_LOOK, 20)
		local turnNeeded = math.abs(wrapAngle(self.geo:yawAt(proj.s + far) - self.geo:yawAt(proj.s)))
		local required = turnNeeded * speed / far
		local margin = (p.cornerMargin or 1) * turn
		if required > margin * 1.4 or math.abs(predErr) > p.liftAngle * 1.6 then
			keys.W = false
			keys.S = true
		elseif required > margin then
			keys.W = false
		end
	end

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
