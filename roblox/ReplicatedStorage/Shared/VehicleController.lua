-- VehicleController.lua
-- Shared driving logic: key state → drive command → body-mover targets.
--
-- Used by:
--   RacingClient      (players, every Heartbeat)
--   BotDriver         (harness bots, via InputSource override → same path)
--   TestHarness.RaceSim and tests/sim (simulated drivers)
--
-- The pure part (readKeys / command / shouldEnterDrift) has no Roblox types
-- and is unit-tested under Lune. `apply` touches Instances and Vector3 only.
--
-- Driving model
--   * The forward speed command RAMPS toward throttle × MaxSpeed:
--       accelerate at Constants.DRIVE.ACCEL_BASE + Torque × ACCEL_PER_TORQUE
--       coast down at COAST_DECEL when W is released, brake at BRAKE_DECEL
--     so VehicleSeat.Torque (the acceleration stat) matters. Pass a state
--     table (VehicleController.newState()) to get this; without one the
--     command jumps straight to the target (used by a few pure tests).
--   * The command cannot run more than BLOCKED_SLACK ahead of the car's real
--     forward speed, so a car pinned against a wall does not "store" speed.
--   * Drifting (ctx.drifting) multiplies TurnSpeed by DRIFT_TURN_MULT inside
--     the command; nothing writes VehicleSeat.TurnSpeed on the client.
--   * SKY altitude moves ALTITUDE_RATE studs per second of real frame time.

local Constants = require(script.Parent.Constants)

local VehicleController = {}

VehicleController.REVERSE_THROTTLE  = -0.5
VehicleController.SKY_TURN_CAP      = 1.5
VehicleController.ALTITUDE_RATE     = 20     -- studs per second at 60 FPS
VehicleController.LEGACY_FRAME_DT   = 1 / 60
VehicleController.DRIFT_TURN_MULT   = Constants.DRIVE.DRIFT_TURN_MULT
VehicleController.DRIFT_TURN_MIN    = Constants.DRIVE.DRIFT_TURN_MIN
VehicleController.DRIFT_SPEED_RATIO = 0.5    -- must be above 50% of MaxSpeed
VehicleController.SUSPENSION_REACH  = 5      -- ray length below the chassis
VehicleController.SUSPENSION_LIFT   = 0.2    -- ride height above the hit

--- Converts a key-state table into a normalized input.
-- keys: { W, A, S, D, Up, Down, Left, Right, Shift, Space, Ctrl } booleans.
-- S overrides W and D overrides A, exactly like the original if-chain.
function VehicleController.readKeys(keys)
	local throttle = 0
	if keys.W or keys.Up then throttle = 1 end
	if keys.S or keys.Down then throttle = VehicleController.REVERSE_THROTTLE end
	local steer = 0
	if keys.A or keys.Left then steer = 1 end
	if keys.D or keys.Right then steer = -1 end
	local climb = 0
	if keys.Space then
		climb = 1
	elseif keys.Ctrl then
		climb = -1
	end
	return {
		throttle  = throttle,
		steer     = steer,      -- +1 = left (positive yaw), -1 = right
		driftHeld = keys.Shift == true,
		climb     = climb,
	}
end

--- True when this frame should start a drift (ground vehicles only).
function VehicleController.shouldEnterDrift(input, drifting, speed, maxSpeed, isSky)
	if isSky or drifting or not input.driftHeld or input.steer == 0 then
		return false
	end
	return speed > maxSpeed * VehicleController.DRIFT_SPEED_RATIO
end

--- TurnSpeed while drifting.
function VehicleController.driftTurnSpeed(turnSpeed)
	return math.max(turnSpeed * VehicleController.DRIFT_TURN_MULT, VehicleController.DRIFT_TURN_MIN)
end

--- Fresh per-vehicle drive state (reset it on spawn and respawn).
function VehicleController.newState()
	return { speed = 0 }
end

function VehicleController.reset(state)
	if state then state.speed = 0 end
end

--- Acceleration in studs/s² for a seat Torque.
function VehicleController.accelFor(torque)
	local D = Constants.DRIVE
	return D.ACCEL_BASE + (torque or 0) * D.ACCEL_PER_TORQUE
end

--- Turn rate the controller actually applies (SKY flyers are capped).
function VehicleController.turnRate(turnSpeed, isSky)
	local turn = turnSpeed or 1
	if isSky then
		turn = math.min(turn, VehicleController.SKY_TURN_CAP)
	end
	return turn
end

--- Drive command.
-- ctx: { maxSpeed, turnSpeed, isSky, drifting,
--        torque, dt, actualForward }   -- the last three only matter with `state`
-- state: optional table from newState(); enables acceleration/coasting.
-- returns { forwardSpeed (studs/s along LookVector), yawRate (rad/s, +left),
--           climb (-1, 0, 1) }
function VehicleController.command(input, ctx, state)
	local turn = ctx.turnSpeed or 1
	if ctx.drifting then
		turn = VehicleController.driftTurnSpeed(turn)
	end
	turn = VehicleController.turnRate(turn, ctx.isSky)
	local maxSpeed = ctx.maxSpeed or 40
	local target = input.throttle * maxSpeed
	local forward = target

	if state then
		local D = Constants.DRIVE
		local dt = ctx.dt or (1 / 60)
		local v = state.speed or 0
		if ctx.actualForward then
			v = math.clamp(v, ctx.actualForward - D.BLOCKED_SLACK, ctx.actualForward + D.BLOCKED_SLACK)
		end
		if target > v then
			local rate = (v < 0) and D.BRAKE_DECEL or VehicleController.accelFor(ctx.torque)
			v = math.min(v + rate * dt, target)
		elseif target < v then
			local rate
			if input.throttle == 0 and v <= maxSpeed then
				rate = D.COAST_DECEL
			else
				rate = D.BRAKE_DECEL     -- braking, reversing, or over a lowered MaxSpeed
			end
			v = math.max(v - rate * dt, target)
		end
		state.speed = v
		forward = v
	end

	return {
		forwardSpeed = forward,
		yawRate      = input.steer * turn,
		climb        = ctx.isSky and input.climb or 0,
	}
end

--- Applies a command to a vehicle built by VehicleBuilder.
-- opts: {
--   biome      = "FOREST" | "OCEAN" | "SKY",
--   raycast    = function(origin: Vector3, direction: Vector3) -> RaycastResult?
--                (FOREST suspension; omit to skip the suspension update)
--   altitudeDt = seconds since the last frame (climb rate is per second)
-- }
-- Returns false when the vehicle is missing its drive movers.
function VehicleController.apply(primary, cmd, opts)
	opts = opts or {}
	local bv  = primary:FindFirstChild("DriveVelocity")
	local bav = primary:FindFirstChild("DriveAngular")
	if not bv or not bav then
		return false
	end

	local hover = primary:FindFirstChild("HoverPosition")
	if hover then
		if cmd.climb ~= 0 then
			local dt = opts.altitudeDt or VehicleController.LEGACY_FRAME_DT
			hover.Position = hover.Position
				+ Vector3.new(0, cmd.climb * VehicleController.ALTITUDE_RATE * dt, 0)
		end
	elseif opts.biome == "FOREST" and opts.raycast then
		local susp = primary:FindFirstChild("SuspensionHover")
		if susp then
			local halfH = primary.Size.Y * 0.5
			local ray = opts.raycast(
				primary.Position,
				Vector3.new(0, -(halfH + VehicleController.SUSPENSION_REACH), 0)
			)
			if ray then
				susp.Position = Vector3.new(
					primary.Position.X,
					ray.Position.Y + halfH + VehicleController.SUSPENSION_LIFT,
					primary.Position.Z
				)
				susp.MaxForce = Vector3.new(0, 4e4, 0)
			else
				susp.MaxForce = Vector3.zero
			end
		end
	end

	bv.Velocity         = primary.CFrame.LookVector * cmd.forwardSpeed
	bav.AngularVelocity = Vector3.new(0, cmd.yawRate, 0)

	local gyro = primary:FindFirstChild("UprightGyro")
	if gyro then
		local _, currentY, _ = primary.CFrame:ToEulerAnglesYXZ()
		gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, currentY, 0)
	end
	return true
end

return VehicleController
