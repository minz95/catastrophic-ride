--!nocheck
-- VehicleController: the shared key → drive-command path used by players,
-- bots and simulators.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local env = Loader.boot()
local VC = env.requirePath("ReplicatedStorage.Shared.VehicleController")
local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")

R.describe("VehicleController.readKeys", function()
	R.it("W drives forward, S overrides W with -0.5", function()
		R.expect(VC.readKeys({ W = true }).throttle).toBe(1)
		R.expect(VC.readKeys({ W = true, S = true }).throttle).toBe(-0.5)
		R.expect(VC.readKeys({ Up = true }).throttle).toBe(1)
		R.expect(VC.readKeys({}).throttle).toBe(0)
	end)
	R.it("A steers left (+1), D overrides A (-1)", function()
		R.expect(VC.readKeys({ A = true }).steer).toBe(1)
		R.expect(VC.readKeys({ A = true, D = true }).steer).toBe(-1)
		R.expect(VC.readKeys({ Right = true }).steer).toBe(-1)
	end)
	R.it("Space climbs, Ctrl descends, Space wins", function()
		R.expect(VC.readKeys({ Space = true, Ctrl = true }).climb).toBe(1)
		R.expect(VC.readKeys({ Ctrl = true }).climb).toBe(-1)
	end)
end)

R.describe("VehicleController.command", function()
	R.it("forward speed is throttle × MaxSpeed and yaw is steer × TurnSpeed", function()
		local cmd = VC.command({ throttle = 1, steer = -1, climb = 0 }, { maxSpeed = 70, turnSpeed = 3 })
		R.expect(cmd.forwardSpeed).toBe(70)
		R.expect(cmd.yawRate).toBe(-3)
	end)
	R.it("SKY caps the turn rate at 1.5", function()
		local cmd = VC.command({ throttle = 0, steer = 1, climb = 1 }, { maxSpeed = 70, turnSpeed = 3, isSky = true })
		R.expect(cmd.yawRate).toBe(1.5)
		R.expect(cmd.climb).toBe(1)
	end)
	R.it("without a drive state the command jumps straight to the target", function()
		R.expect(VC.command(VC.readKeys({}), { maxSpeed = 70, turnSpeed = 3 }).forwardSpeed).toBe(0)
	end)
	R.it("drifting lowers the yaw rate inside the command", function()
		local cmd = VC.command({ throttle = 1, steer = 1, climb = 0 }, { maxSpeed = 70, turnSpeed = 3, drifting = true })
		R.expect(cmd.yawRate).toBeNear(1.05, 1e-9)
	end)
end)

R.describe("VehicleController acceleration (drive state)", function()
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local D = Constants.DRIVE
	local function drive(keys, seconds, ctx, state)
		state = state or VC.newState()
		local cmd
		for _ = 1, math.floor(seconds * 60 + 0.5) do
			ctx.dt = 1 / 60
			cmd = VC.command(VC.readKeys(keys), ctx, state)
		end
		return cmd.forwardSpeed, state
	end
	R.it("a higher Torque reaches top speed sooner", function()
		local low = drive({ W = true }, 1, { maxSpeed = 70, turnSpeed = 3, torque = 20 })
		local high = drive({ W = true }, 1, { maxSpeed = 70, turnSpeed = 3, torque = 180 })
		R.expect(low).toBeNear(D.ACCEL_BASE + 20 * D.ACCEL_PER_TORQUE, 0.5)
		R.expect(high).toBeGreaterThan(low)
		local top = drive({ W = true }, 10, { maxSpeed = 70, turnSpeed = 3, torque = 180 })
		R.expect(top).toBe(70)
	end)
	R.it("releasing W coasts down instead of stopping dead", function()
		local _, st = drive({ W = true }, 10, { maxSpeed = 70, turnSpeed = 3, torque = 100 })
		local v = drive({}, 0.5, { maxSpeed = 70, turnSpeed = 3, torque = 100 }, st)
		R.expect(v).toBeNear(70 - D.COAST_DECEL * 0.5, 0.6)
	end)
	R.it("S brakes harder than coasting", function()
		local _, st = drive({ W = true }, 10, { maxSpeed = 70, turnSpeed = 3, torque = 100 })
		local v = drive({ S = true }, 0.5, { maxSpeed = 70, turnSpeed = 3, torque = 100 }, st)
		R.expect(v).toBeLessThan(70 - D.COAST_DECEL * 0.5)
	end)
	R.it("a lowered MaxSpeed (mud) pulls the speed down quickly", function()
		local _, st = drive({ W = true }, 10, { maxSpeed = 70, turnSpeed = 3, torque = 100 })
		local v = drive({ W = true }, 0.5, { maxSpeed = 35, turnSpeed = 3, torque = 100 }, st)
		R.expect(v).toBe(35)
	end)
	R.it("a car pinned against a wall does not store speed", function()
		local state = VC.newState()
		local v = drive({ W = true }, 3, { maxSpeed = 70, turnSpeed = 3, torque = 180, actualForward = 0 }, state)
		-- clamped to real speed + slack, then at most one frame of acceleration
		R.expect(v).toBeAtMost(D.BLOCKED_SLACK + VC.accelFor(180) / 60 + 1e-6)
	end)
end)

R.describe("drift", function()
	R.it("needs Shift + steering + more than half of MaxSpeed", function()
		local held = { throttle = 1, steer = 1, driftHeld = true }
		R.expect(VC.shouldEnterDrift(held, false, 40, 70, false)).toBe(true)
		R.expect(VC.shouldEnterDrift(held, false, 30, 70, false)).toBe(false)
		R.expect(VC.shouldEnterDrift({ throttle = 1, steer = 0, driftHeld = true }, false, 60, 70, false)).toBe(false)
		R.expect(VC.shouldEnterDrift(held, false, 60, 70, true)).toBe(false)
	end)
	R.it("drifting reduces TurnSpeed to 35% (min 0.3)", function()
		R.expect(VC.driftTurnSpeed(3)).toBeNear(1.05, 1e-9)
		R.expect(VC.driftTurnSpeed(0.5)).toBe(0.3)
	end)
end)

R.describe("VehicleController.apply on a VehicleBuilder car", function()
	local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
	local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 590), {})
	local primary = model.PrimaryPart

	R.it("sets DriveVelocity along LookVector and DriveAngular to the yaw rate", function()
		local ok = VC.apply(primary, { forwardSpeed = 50, yawRate = 2, climb = 0 }, { biome = "FOREST" })
		R.expect(ok).toBe(true)
		local v = primary.DriveVelocity.Velocity
		local look = primary.CFrame.LookVector
		R.expect((v - look * 50).Magnitude).toBeNear(0, 1e-4)
		R.expect(primary.DriveAngular.AngularVelocity.Y).toBe(2)
	end)

	R.it("FOREST suspension follows the ground hit", function()
		VC.apply(primary, { forwardSpeed = 0, yawRate = 0, climb = 0 }, {
			biome = "FOREST",
			raycast = function() return { Position = Vector3.new(0, 1, 590) } end,
		})
		local susp = primary.SuspensionHover
		R.expect(susp.Position.Y).toBeNear(1 + primary.Size.Y / 2 + 0.2, 1e-4)
	end)

	-- Studio run (2026-10-20): with one ray from the chassis centre the nose
	-- hit the JumpRamp face while SuspensionHover held the car at flat-ground
	-- height; DriveVelocity (horizontal only) could not push it up. Expert
	-- stopped at JumpRamp_1, 0/4 bots finished a FOREST match.
	R.it("FOREST suspension rises when the nose is over a ramp", function()
		local look = primary.CFrame.LookVector
		local halfLen = primary.Size.Z / 2
		local origins = {}
		VC.apply(primary, { forwardSpeed = 40, yawRate = 0, climb = 0 }, {
			biome = "FOREST",
			raycast = function(origin)
				table.insert(origins, origin)
				-- ground at Y 1 under the centre, ramp top at Y 3 ahead of it
				local ahead = (origin - primary.Position):Dot(look)
				return { Position = Vector3.new(origin.X, ahead > halfLen * 0.5 and 3 or 1, origin.Z) }
			end,
		})
		R.expect(#origins >= 2).toBe(true)
		R.expect(primary.SuspensionHover.Position.Y).toBeNear(3 + primary.Size.Y / 2 + 0.2, 1e-4)
	end)

	-- Studio run (2026-10-20, after the nose probe): a slow car (mud just
	-- before JumpRamp_2) whose centre passed the ramp's top edge was pulled
	-- down onto that edge by the hover and stuck there until respawned.
	R.it("FOREST suspension keeps riding the ramp while the tail is still on it", function()
		local look = primary.CFrame.LookVector
		local halfLen = primary.Size.Z / 2
		VC.apply(primary, { forwardSpeed = 10, yawRate = 0, climb = 0 }, {
			biome = "FOREST",
			raycast = function(origin)
				-- ramp top (Y 4.7) behind the centre, ground (Y 1) from the centre on
				local behind = (origin - primary.Position):Dot(look) < -halfLen * 0.5
				return { Position = Vector3.new(origin.X, behind and 4.7 or 1, origin.Z) }
			end,
		})
		R.expect(primary.SuspensionHover.Position.Y).toBeNear(4.7 + primary.Size.Y / 2 + 0.2, 1e-4)
	end)

	-- Studio match (2026-10-21): with probes only at the tail, centre and
	-- nose, a car whose centre was 2 studs before JumpRamp_3's top edge rode
	-- at the centre's slope height, its belly caught the higher slope just
	-- ahead and it stopped (2 of 4 bots stuck for the rest of the race).
	-- Ramp along the car's axis: rises from Y 1 to Y 5 over 14 studs, then
	-- drops back to the ground (Y 1).
	local function rampAt(edge)
		local look = primary.CFrame.LookVector
		return function(origin)
			local a = (origin - primary.Position):Dot(look)
			local y = 1
			if a <= edge and a >= edge - 14 then y = 1 + 4 * (a - (edge - 14)) / 14 end
			return { Position = Vector3.new(origin.X, y, origin.Z) }
		end
	end

	R.it("FOREST suspension clears a ramp's top edge that is under the chassis between centre and nose", function()
		VC.apply(primary, { forwardSpeed = 10, yawRate = 0, climb = 0 }, { biome = "FOREST", raycast = rampAt(2) })
		R.expect(primary.SuspensionHover.Position.Y).toBeGreaterThan(4.9 + primary.Size.Y / 2)
	end)

	R.it("FOREST suspension lifts before the nose reaches a ramp at speed", function()
		local halfLen = primary.Size.Z / 2
		-- the ramp starts 3 studs ahead of the nose; at 68 studs/s that is 0.04 s away
		VC.apply(primary, { forwardSpeed = 68, yawRate = 0, climb = 0 }, { biome = "FOREST", raycast = rampAt(halfLen + 3 + 14) })
		R.expect(primary.SuspensionHover.Position.Y).toBeGreaterThan(1.5 + primary.Size.Y / 2)
		-- standing still, nothing ahead is probed
		VC.apply(primary, { forwardSpeed = 0, yawRate = 0, climb = 0 }, { biome = "FOREST", raycast = rampAt(halfLen + 3 + 14) })
		R.expect(primary.SuspensionHover.Position.Y).toBeNear(1 + primary.Size.Y / 2 + 0.2, 1e-4)
	end)

	R.it("returns false when the drive movers are missing", function()
		local bare = env.mock.Instance.new("Part")
		R.expect(VC.apply(bare, { forwardSpeed = 1, yawRate = 0, climb = 0 }, {})).toBe(false)
	end)
end)
