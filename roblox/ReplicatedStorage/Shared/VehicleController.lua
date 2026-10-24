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
--   * Grip: on the ground the turn rate is capped at GRIP_LAT / speed, so a
--     sharp corner at full speed needs a brake or a drift.
--   * Drifting (ctx.drifting): turn rate × DRIFT_TURN_MULT, a higher lateral
--     cap (DRIFT_LAT), and the travel direction lags behind the nose
--     (DRIFT_FOLLOW), so the car slides; sliding costs DRIFT_DRAG. The time
--     spent sliding (state.driftTime) pays a mini-turbo on release (client →
--     server). Nothing writes VehicleSeat.TurnSpeed on the client.
--   * Hits (Shared/CarImpact via the server): VehicleController.knock adds a
--     velocity change and a spin; the sideways part and the spin fade out.
--   * SKY altitude moves ALTITUDE_RATE studs per second of real frame time.
--   * Lift abilities: the chassis attribute "LiftOffset" (server, studs) is
--     added to the hover / suspension target, eased at ABILITY_LIFT.RATE.

local Constants = require(script.Parent.Constants)

local VehicleController = {}

local LIFT = Constants.ABILITY_LIFT

VehicleController.REVERSE_THROTTLE  = -0.5
VehicleController.SKY_TURN_CAP      = 1.5
VehicleController.ALTITUDE_RATE     = 20     -- studs per second at 60 FPS
VehicleController.LEGACY_FRAME_DT   = 1 / 60
VehicleController.DRIFT_TURN_MULT   = Constants.DRIVE.DRIFT_TURN_MULT
VehicleController.DRIFT_SPEED_RATIO = 0.5    -- must be above 50% of MaxSpeed
VehicleController.SUSPENSION_REACH  = 5      -- ray length below the chassis
VehicleController.SUSPENSION_LIFT   = 0.2    -- ride height above the hit
VehicleController.SUSPENSION_STEP   = 1      -- studs between probes along the chassis
-- (0.12 s / 8 studs until 2026-10-24: the hover lagged up a 4-stud ramp, the
-- nose dug in and a car came off the lip at ~30 of ~70 studs/s)
VehicleController.SUSPENSION_AHEAD  = 0.2    -- s of travel probed ahead of the nose
VehicleController.SUSPENSION_AHEAD_MAX = 14  -- studs (a ramp's length)
VehicleController.RAMP_PROBE_RISE   = 5      -- studs: ahead probes for jump ramps start this high
-- extra height over a jump ramp: the hover lags a rising target and the
-- chassis scraped the ramp's top end (Studio: 69 → 36 studs/s at the lip)
VehicleController.RAMP_CLEARANCE    = 0.8

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
	return turnSpeed * VehicleController.DRIFT_TURN_MULT
end

--- Turn rate on the ground at `speed`: the seat's rate, capped by grip
-- (GRIP_LAT / speed), or by DRIFT_LAT / speed while drifting. SKY flyers
-- have no grip limit (they are capped at SKY_TURN_CAP instead).
function VehicleController.effectiveTurn(turnSpeed, speed, isSky, drifting, biome)
	local D = Constants.DRIVE
	local turn = turnSpeed or 1
	if drifting then turn = VehicleController.driftTurnSpeed(turn) end
	turn = VehicleController.turnRate(turn, isSky)
	if isSky then return turn end
	local lat = (drifting and D.DRIFT_LAT or D.GRIP_LAT)
	lat = lat[biome or "FOREST"] or lat.FOREST
	local v = math.abs(speed or 0)
	if v > 1 then turn = math.min(turn, lat / v) end
	return turn
end

--- Fresh per-vehicle drive state (reset it on spawn and respawn).
function VehicleController.newState()
	return { speed = 0, knockX = 0, knockZ = 0, spin = 0, travelYaw = nil, driftTime = 0, drifting = false }
end

function VehicleController.reset(state)
	if not state then return end
	state.speed, state.knockX, state.knockZ, state.spin = 0, 0, 0, 0
	state.travelYaw, state.driftTime, state.drifting = nil, 0, false
end

--- Starts / ends a drift for this frame (the one rule for RacingClient,
-- RaceSim and the offline simulator). Returns "enter", or "exit" plus the
-- mini-turbo level earned (nil when the slide was too short), or nil.
function VehicleController.updateDrift(state, input, speed, maxSpeed, isSky)
	if not state.drifting then
		if VehicleController.shouldEnterDrift(input, false, speed, maxSpeed, isSky) then
			state.drifting, state.driftTime = true, 0
			return "enter"
		end
	elseif not input.driftHeld or isSky or speed < maxSpeed * Constants.DRIVE.DRIFT_EXIT_RATIO then
		state.drifting = false
		local level = VehicleController.turboLevel(state.driftTime)
		state.driftTime = 0
		return "exit", level
	end
	return nil
end

local function wrapAngle(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end
VehicleController.wrapAngle = wrapAngle

--- A hit (Shared/CarImpact): velocity change (dvx, dvz) and spin (rad/s).
-- The part along the car's facing (lx, lz) changes its drive speed; the
-- sideways rest becomes a slide that fades (Constants.IMPACT.KNOCK_DECAY).
function VehicleController.knock(state, dvx, dvz, spin, lx, lz, maxSpeed)
	if not state then return end
	local d = math.sqrt(lx * lx + lz * lz)
	if d < 1e-6 then lx, lz, d = 0, -1, 1 end
	lx, lz = lx / d, lz / d
	local along = dvx * lx + dvz * lz
	local cap = (maxSpeed or 80) * 1.5
	state.speed = math.clamp((state.speed or 0) + along, -cap, cap)
	state.knockX = (state.knockX or 0) + dvx - lx * along
	state.knockZ = (state.knockZ or 0) + dvz - lz * along
	state.spin = (state.spin or 0) + (spin or 0)
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
-- ctx: { maxSpeed, turnSpeed, isSky, drifting, biome,
--        torque, dt, actualForward, yaw }   -- these only matter with `state`
--   yaw: the car's current yaw (LookVector = (-sin, 0, -cos)); enables the
--        travel direction (grip / slide).
--   actualForward: the car's real speed along its TRAVEL direction
--        (VehicleController.travelDir; while sliding that is not the nose).
-- state: optional table from newState(); enables acceleration/coasting.
-- returns { forwardSpeed (studs/s), yawRate (rad/s, +left), climb (-1, 0, 1),
--           travelYaw (direction of travel; nil = along LookVector),
--           knockX, knockZ (extra velocity from hits), slide (rad) }
function VehicleController.command(input, ctx, state)
	local maxSpeed = ctx.maxSpeed or 40
	local speedNow = state and math.abs(state.speed or 0) or math.abs(input.throttle * maxSpeed)
	local turn = VehicleController.effectiveTurn(ctx.turnSpeed, speedNow, ctx.isSky, ctx.drifting, ctx.biome)
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

	local cmd = {
		forwardSpeed = forward,
		yawRate      = input.steer * turn,
		climb        = ctx.isSky and input.climb or 0,
		knockX = 0, knockZ = 0, slide = 0,
	}
	if state then
		local D, I = Constants.DRIVE, Constants.IMPACT
		local dt = ctx.dt or (1 / 60)
		-- hits: fading slide and spin
		local k = math.exp(-I.KNOCK_DECAY * dt)
		state.knockX, state.knockZ = (state.knockX or 0) * k, (state.knockZ or 0) * k
		state.spin = (state.spin or 0) * math.exp(-I.SPIN_DECAY * dt)
		if math.abs(state.knockX) < 0.05 and math.abs(state.knockZ) < 0.05 then state.knockX, state.knockZ = 0, 0 end
		if math.abs(state.spin) < 0.01 then state.spin = 0 end
		cmd.knockX, cmd.knockZ = state.knockX, state.knockZ
		cmd.yawRate += state.spin
		-- travel direction: follows the nose, slowly while drifting
		if ctx.yaw and not ctx.isSky then
			local tyaw = state.travelYaw or ctx.yaw
			local rate = ctx.drifting and D.DRIFT_FOLLOW or D.TRAVEL_FOLLOW
			tyaw = tyaw + wrapAngle(ctx.yaw - tyaw) * (1 - math.exp(-rate * dt))
			state.travelYaw = tyaw
			cmd.travelYaw = tyaw
			cmd.slide = math.abs(wrapAngle(ctx.yaw - tyaw))
			if ctx.drifting and cmd.slide > 0 then
				state.speed = math.max(0, state.speed - D.DRIFT_DRAG * math.sin(math.min(cmd.slide, math.pi / 2)) * dt)
				cmd.forwardSpeed = state.speed
			end
			if ctx.drifting and cmd.slide >= D.DRIFT_TURBO.MIN_SLIDE then
				state.driftTime = (state.driftTime or 0) + dt
			end
		end
	end
	return cmd
end

--- Unit travel direction (x, z) of a drive state for a car at `yaw`.
function VehicleController.travelDir(state, yaw)
	local ty = (state and state.travelYaw) or yaw
	return -math.sin(ty), -math.cos(ty)
end

--- Mini-turbo level (index into Constants.DRIVE.DRIFT_TURBO, or nil) for a
-- drift that slid `driftTime` seconds.
function VehicleController.turboLevel(driftTime)
	local level
	for i, l in ipairs(Constants.DRIVE.DRIFT_TURBO) do
		if (driftTime or 0) >= l.time then level = i end
	end
	return level
end

--- Applies a command to a vehicle built by VehicleBuilder.
-- opts: {
--   biome      = "FOREST" | "OCEAN" | "SKY",
--   raycast    = function(origin: Vector3, direction: Vector3) -> RaycastResult?
--                (FOREST suspension; omit to skip the suspension update)
--   altitudeDt = seconds since the last frame (climb rate is per second)
--   roadRise   = how far the road under the car is above trackTop
--                (RaceProgress.roadRise): OCEAN boats and SKY flyers hold a
--                set height instead of riding the ground, so that height
--                follows a raised road (a flume, a corkscrew)
-- }
-- Returns false when the vehicle is missing its drive movers.
--- After a respawn (the car was moved): the held height (SKY hover, OCEAN
-- water line) starts where the car now is, and `rise` is the road height
-- there above trackTop (RaceProgress.roadRise).
function VehicleController.resetRide(primary, rise)
	for _, name in ipairs({ "HoverPosition", "SuspensionHover" }) do
		local bp = primary:FindFirstChild(name)
		if bp then bp.Position = primary.Position end
	end
	primary:SetAttribute("RoadRiseApplied", rise or 0)
	-- a jump in progress ends with the move (no launch from the old spot)
	primary:SetAttribute("AirT", nil)
	primary:SetAttribute("AirMin", nil)
	primary:SetAttribute("SuspTarget", nil)
	primary:SetAttribute("SpringT", nil)
	primary:SetAttribute("SpringVY", nil)
	primary:SetAttribute("SpringMin", nil)
end

function VehicleController.apply(primary, cmd, opts)
	opts = opts or {}
	local bv  = primary:FindFirstChild("DriveVelocity")
	local bav = primary:FindFirstChild("DriveAngular")
	if not bv or not bav then
		return false
	end

	-- Ability lift (Modules/VehicleLift): the server sets "LiftOffset"; the
	-- offset actually applied ("LiftApplied", local) follows it at LIFT.RATE.
	local dt = opts.altitudeDt or VehicleController.LEGACY_FRAME_DT
	local liftTarget = primary:GetAttribute("LiftOffset") or 0
	local lifted = primary:GetAttribute("LiftApplied") or 0
	local liftStep = math.clamp(liftTarget - lifted, -LIFT.RATE * dt, LIFT.RATE * dt)
	if liftStep ~= 0 then
		primary:SetAttribute("LiftApplied", lifted + liftStep)
	end

	-- Road height: move the held height by however much the road rose or
	-- fell since the last frame ("RoadRiseApplied"; the server resets it on
	-- a respawn).
	local riseStep = 0
	if opts.roadRise then
		local applied = primary:GetAttribute("RoadRiseApplied") or 0
		riseStep = opts.roadRise - applied
		if riseStep ~= 0 then primary:SetAttribute("RoadRiseApplied", opts.roadRise) end
	end

	local hover = primary:FindFirstChild("HoverPosition")
	if hover then
		local dy = liftStep + riseStep
		if cmd.climb ~= 0 then
			dy += cmd.climb * VehicleController.ALTITUDE_RATE * dt
		end
		if dy ~= 0 then
			hover.Position = hover.Position + Vector3.new(0, dy, 0)
		end
	elseif opts.biome ~= "FOREST" then
		-- OCEAN: the ride height is fixed at the water; a lift or a raised
		-- flume moves it
		local susp = primary:FindFirstChild("SuspensionHover")
		if susp and (liftStep ~= 0 or riseStep ~= 0) then
			susp.Position = susp.Position + Vector3.new(0, liftStep + riseStep, 0)
		end
	elseif opts.raycast then
		local susp = primary:FindFirstChild("SuspensionHover")
		if susp then
			-- Ride on the highest ground under the whole chassis (a probe
			-- every SUSPENSION_STEP studs from tail to nose) and a little
			-- ahead of the nose (SUSPENSION_AHEAD s of travel).
			-- History (Studio): with the centre ray alone the nose ran into
			-- ramps; with centre + nose + tail, a car whose centre was 2
			-- studs before a ramp's top edge hung on the slope between the
			-- probes and stopped (2 of 4 bots stuck on JumpRamp_3, 2026-10-21),
			-- and every car hit the ramp face before the hover lifted it,
			-- dropping from ~68 to ~8 studs/s.
			local halfH = primary.Size.Y * 0.5
			local halfL = primary.Size.Z * 0.5
			local down = Vector3.new(0, -(halfH + VehicleController.SUSPENSION_REACH), 0)
			local look = primary.CFrame.LookVector
			local step = VehicleController.SUSPENSION_STEP
			local ahead = math.clamp((cmd.forwardSpeed or 0) * VehicleController.SUSPENSION_AHEAD,
				0, VehicleController.SUSPENSION_AHEAD_MAX)
			local ray
			local rampLift = 0   -- RAMP_CLEARANCE when the highest hit is a jump ramp
			local spring         -- a spring pad under the chassis (gap jumps)
			local d = -halfL
			-- A ray from the chassis centre starts inside a ramp that is higher
			-- than the centre and does not see it: ahead of the centre a
			-- second ray starts RAMP_PROBE_RISE higher and counts only when it
			-- lands on a jump ramp (from up there a wall's top would lift the
			-- car onto the wall). Studio 2026-10-24: the car only rose once it
			-- had hit the ramp, losing half its speed.
			local up = Vector3.new(0, VehicleController.RAMP_PROBE_RISE, 0)
			while true do
				local hit = opts.raycast(primary.Position + look * d, down)
				if d > 0 then
					local high = opts.raycast(primary.Position + look * d + up, down - up)
					if high and high.Instance and string.sub(high.Instance.Name, 1, 9) == "JumpRamp_"
						and (not hit or high.Position.Y > hit.Position.Y) then
						hit = high
					end
				end
				if hit and d <= halfL and hit.Instance and string.sub(hit.Instance.Name, 1, 10) == "SpringPad_" then
					spring = hit.Instance
				end
				if hit and (not ray or hit.Position.Y > ray.Position.Y) then
					ray = hit
					rampLift = (hit.Instance and string.sub(hit.Instance.Name, 1, 9) == "JumpRamp_")
						and VehicleController.RAMP_CLEARANCE or 0
				end
				if d >= halfL + ahead then break end
				d = math.min(d + step, halfL + ahead)
			end
			-- Jump (Constants.DRIVE.JUMP): the ground under the car fell away
			-- at once (a ramp's lip) at speed → fly an arc ("AirT" = seconds
			-- in the air, "AirY0" = the held height at the lip) until it
			-- meets the ground again.
			local J = Constants.DRIVE.JUMP
			local air = primary:GetAttribute("AirT")
			local target
			-- a spring pad is remembered for SPRING_MEMORY s (its VY and MinSpeed)
			if spring then
				primary:SetAttribute("SpringVY", spring:GetAttribute("VY"))
				primary:SetAttribute("SpringMin", spring:GetAttribute("MinSpeed"))
				primary:SetAttribute("SpringT", J.SPRING_MEMORY)
			elseif primary:GetAttribute("SpringT") then
				local left = primary:GetAttribute("SpringT") - dt
				primary:SetAttribute("SpringT", left > 0 and left or nil)
				if left <= 0 then
					primary:SetAttribute("SpringVY", nil)
					primary:SetAttribute("SpringMin", nil)
				end
			end
			local prev = primary:GetAttribute("SuspTarget")
			local ground
			if ray then
				ground = ray.Position.Y + halfH + VehicleController.SUSPENSION_LIFT + rampLift + lifted + liftStep
				target = ground
			end
			primary:SetAttribute("SuspTarget", ground)
			-- launch: the ground fell away at once (a ramp's lip) or is gone
			-- (a gap), at speed or off a spring pad
			local springVY = primary:GetAttribute("SpringVY")
			if not air and prev and ((ground and prev - ground >= J.MIN_DROP) or not ground)
				and ((cmd.forwardSpeed or 0) >= J.MIN_SPEED or springVY) then
				air = 0
				primary:SetAttribute("AirY0", prev)
				primary:SetAttribute("AirVY", springVY or J.VY)
				primary:SetAttribute("AirMin", primary:GetAttribute("SpringMin"))
				primary:SetAttribute("Jumps", (primary:GetAttribute("Jumps") or 0) + 1)
			end
			if air then
				air += dt
				local y0 = primary:GetAttribute("AirY0") or primary.Position.Y
				local y = y0 + (primary:GetAttribute("AirVY") or J.VY) * air - 0.5 * J.GRAVITY * air * air
				if (ground and y <= ground) or (not ground and y < y0 - J.FALL_GIVE_UP) then
					air = nil   -- landed (or fell short: let it drop)
					primary:SetAttribute("LandedOn", ray and ray.Instance and ray.Instance.Name or nil)
					primary:SetAttribute("AirMin", nil)
					if not ground then target = nil end
				else
					target = y
				end
			end
			primary:SetAttribute("AirT", air)
			if target then
				susp.Position = Vector3.new(primary.Position.X, target, primary.Position.Z)
				susp.MaxForce = Vector3.new(0, 4e4, 0)
			else
				susp.MaxForce = Vector3.zero
			end
		end
	end

	local dir = primary.CFrame.LookVector
	if cmd.travelYaw then
		-- sliding: travel along travelYaw, keeping the look vector's slope
		dir = Vector3.new(-math.sin(cmd.travelYaw), dir.Y, -math.cos(cmd.travelYaw))
	end
	-- off a spring pad the car keeps at least its MinSpeed in the air
	local forward = cmd.forwardSpeed
	local airMin = primary:GetAttribute("AirT") and primary:GetAttribute("AirMin")
	if airMin and forward < airMin then forward = airMin end
	bv.Velocity         = dir * forward + Vector3.new(cmd.knockX or 0, 0, cmd.knockZ or 0)
	bav.AngularVelocity = Vector3.new(0, cmd.yawRate, 0)

	local gyro = primary:FindFirstChild("UprightGyro")
	if gyro then
		local _, currentY, _ = primary.CFrame:ToEulerAnglesYXZ()
		gyro.CFrame = CFrame.fromEulerAnglesYXZ(0, currentY, 0)
	end
	return true
end

return VehicleController
