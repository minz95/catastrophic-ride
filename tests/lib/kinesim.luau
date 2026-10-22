--!nocheck
-- kinesim.luau
-- Offline 2D kinematic race simulator.
--
-- Why kinematic is a fair model here: the game does not simulate tyres or
-- engines. Every Heartbeat the client SETS DriveVelocity = LookVector *
-- throttle * MaxSpeed (BodyVelocity, MaxForce 1e4) and DriveAngular to
-- steer * TurnSpeed, with an upright gyro. So the car follows its commanded
-- velocity almost instantly and slides along low-friction walls. This sim
-- reproduces that on the XZ plane, with collisions against the parts of the
-- actually built map. What it does NOT model: jumps/vertical motion, ramps,
-- physics impulses from car-to-car contact, network latency.
--
--   local result = KineSim.run(world, {
--     car = { maxSpeed, turnSpeed, boostDuration, radius },
--     profile = Autopilot.PROFILES.average, seed = 1,
--     respawn = "legacy" | "track", timeout = 180,
--     onStep = function(ctx) end,   -- optional: abilities (tests/lib/balance.luau)
--     logs = true | { interval = 8, count = 3 },   -- FOREST falling logs (HazardPlan)
--     avoid = false,                -- the driver does not look out for them
--   })
--
-- onStep gets, every step: ctx.t, ctx.s (progress), ctx.speed, ctx.maxSpeed
-- (with every multiplier), ctx.err (heading error), ctx.straight(dist)
-- (true when the next `dist` studs bend less than 12°), ctx.mods / ctx.turn
-- (SpeedModifiers for MaxSpeed / TurnSpeed, expiry on the race clock),
-- ctx.knock(along, side) (a CarImpact shove), ctx.refillBoost(), ctx.gauge(),
-- ctx.ground(untilT) (mud and slow zones do not touch the car until untilT:
-- Drill, or a lift above them) and ctx.res (the result table).

local KineSim = {}

local MapQuery = require("./mapquery")

KineSim.DT = 1 / 60
KineSim.SAMPLE_EVERY = 0.25
KineSim.DEFAULT_ACCEL = 400        -- studs/s², ≈ MaxForce 1e4 / assembly mass 25
KineSim.IMPACT_SPEED = 8           -- normal speed (studs/s) that counts as a hit
KineSim.OFFTRACK_RESCUE = 3        -- seconds off the corridor before pressing R


--- Seat values for `stats` in `biome` (default FOREST).
-- `Constants` is the game's Constants module (any loader env).
function KineSim.carFromStats(stats, Constants, biome)
	biome = biome or "FOREST"
	assert(Constants.RACE_SPEED[biome], "unknown biome " .. tostring(biome))
	-- Same functions VehicleBuilder uses; a spec checks the built seats too.
	return {
		biome     = biome,
		maxSpeed  = Constants.maxSpeedFor(biome, stats),
		turnSpeed = Constants.turnSpeedFor(biome, stats),
		torque    = Constants.torqueFor(biome, stats),
		boostDuration = stats.boostDuration or 2,
		radius    = 1.9,
	}
end

local function yawFromDir(dx, dz)
	return math.atan2(-dx, -dz)
end

function KineSim.run(world, opts)
	local env = world.env
	local VehicleController = env.requirePath("ReplicatedStorage.Shared.VehicleController")
	local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
	local SpeedModifiers = env.requirePath("ReplicatedStorage.Shared.SpeedModifiers")
	local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")

	local geo, track = world.geo, world.track
	local car = opts.car
	local isSky = world.biome == "SKY"
	-- What the controller will actually turn at (SKY caps it), so the
	-- autopilot plans with the real rate.
	local effTurn = VehicleController.turnRate(car.turnSpeed, isSky)
	local r = car.radius or 1.9
	local dt = KineSim.DT
	local timeout = opts.timeout or Constants.RACING_TIMEOUT
	local accel = opts.accel or KineSim.DEFAULT_ACCEL
	local respawnMode = opts.respawn or "legacy"
	local seed = opts.seed or 1
	local rng = Random and Random.new and nil

	-- Start pose: grid slot `opts.slot` (1..10), facing down the track.
	local slot = opts.slot or 3
	local cols, rows = track.startGrid.cols, track.startGrid.rows
	local col = ((slot - 1) % #cols) + 1
	local row = math.ceil(slot / #cols)
	local x, z = cols[col], rows[row] or rows[1]
	local roadY = geo:heightAt(0)
	local _, _, sdx, sdz = geo:pointAt(0)
	local yaw = yawFromDir(sdx, sdz)
	local vx, vz = 0, 0

	local ap = Autopilot.new(geo, opts.profile, seed)
	local driveState = VehicleController.newState()
	local mods = SpeedModifiers.new(car.maxSpeed, Constants.SPEED_STACK_MAX)
	-- Falling logs, as HazardManager drops them: a warning marker LOG_WARN s
	-- before the log, which then lies still for LOG_LIFETIME s.
	local HazardPlan = env.requirePath("ReplicatedStorage.Shared.HazardPlan")
	local H = Constants.HAZARDS
	local logCfg = opts.logs == true and {} or opts.logs
	local logs, nextDrop, logClear = {}, (logCfg and (logCfg.interval or 8)) or math.huge, nil
	local logRng = (function()
		local st = (opts.seed or 1) * 7907 + 3
		return function()
			st = (st * 1103515245 + 12345) % 2147483648
			return st / 2147483648
		end
	end)()
	local turnMods = SpeedModifiers.new(1)
	local groundFreeUntil = -1
	local raceStartY = BiomeConfig[world.biome].raceStartY

	-- Boost pads: the race activates a seeded K-of-N subset (RacingManager).
	local pads = {}
	for _, tr in ipairs(world.triggers) do
		if table.find(tr.tags, "BoostPad") then table.insert(pads, tr) end
	end
	table.sort(pads, function(a, b) return a.name < b.name end)
	local active = {}
	do
		local order = {}
		for i = 1, #pads do order[i] = i end
		local state = seed * 7919 + 17
		for i = #order, 2, -1 do
			state = (state * 1103515245 + 12345) % 2147483648
			local j = (state % i) + 1
			order[i], order[j] = order[j], order[i]
		end
		local k = math.max(1, math.ceil(#pads * Constants.RACE_BOOST_PAD_ACTIVE_RATIO))
		for i = 1, math.min(k, #pads) do active[pads[order[i]]] = true end
	end

	local res = {
		finished = false, time = nil,
		checkpoints = {}, impacts = {}, contacts = 0, escapes = {}, respawns = {},
		samples = {}, sections = {}, effects = {}, blockedBy = {},
		pads = { active = 0 }, logHits = 0, logsDropped = 0,
		car = car, profile = opts.profileName, seed = seed,
		visibility = world.visibility, respawnMode = respawnMode,
		drifts = 0, turbos = 0, driftSeconds = 0,
	}
	for _ in pairs(active) do res.pads.active += 1 end

	local cp = { false, false }
	local padCooldown = {}
	local cornerCooldown = {}
	local gauge = 1
	local boostCooldownEnd = 0
	local offTrackSince = nil
	local lastSample = -1
	local maxS = 0
	local insideMud, insideSlow = false, false
	local sectionIdx = 1
	res.sections[1] = { name = track.sections[1].name, enter = 0 }

	local function sectionFor(s)
		local _, _, _, _, seg = geo:pointAt(s)
		for i, sec in ipairs(track.sections) do
			if seg >= sec.from and seg < sec.to then return i end
		end
		return #track.sections
	end

	local function onTrack(px, pz)
		local p = geo:project(px, pz)
		return p.dist <= track.width / 2 - r, p
	end

	local prevX, prevZ = x, z

	local function respawn(t, reason, s)
		local entry = { t = t, reason = reason, s = s, from = { x = x, z = z } }
		-- "legacy" = whatever RaceProgress.respawnPoint (the live game) returns
		local lx, _, lz, lyaw = RaceProgress.respawnPoint(world.biome, x, z, raceStartY, ap.segHint, roadY + 2)
		local ok, p = onTrack(lx, lz)
		entry.legacy = { x = lx, z = lz, onTrack = ok, lateral = p.lateral }
		if respawnMode == "legacy" then
			x, z = lx, lz
			yaw = lyaw
		else
			local ts = math.max(s - RaceProgress.RESPAWN_STEP_BACK, 0)
			local px, pz, ddx, ddz = geo:pointAt(ts)
			x, z, yaw = px, pz, yawFromDir(ddx, ddz)
		end
		vx, vz = 0, 0
		prevX, prevZ = x, z
		roadY = geo:heightAt(math.max(s - RaceProgress.RESPAWN_STEP_BACK, 0))
		VehicleController.reset(driveState)
		entry.to = { x = x, z = z }
		table.insert(res.respawns, entry)
		ap:resetTracking()
		offTrackSince = nil
	end

	for _, tr in ipairs(world.triggers) do
		tr.isGate = table.find(tr.tags, "Checkpoint1") or table.find(tr.tags, "Checkpoint2")
			or table.find(tr.tags, "FinishLine") or nil
	end

	local t = 0
	local steps = math.floor(timeout / dt)
	-- Road height under the car (a raised road / a spiral): obstacles and
	-- triggers on another layer of the road are not touched.
	local layered = geo.hasHeights
	local band = world.band or { 0.6, 3.0 }
	for _ = 1, steps do
		t += dt
		local speed = math.sqrt(vx * vx + vz * vz)
		local turnK = turnMods:value(t)
		local seen = nil
		if logCfg then
			if t >= nextDrop then
				nextDrop = t + (logCfg.interval or 8)
				logClear = logClear or HazardPlan.keepClear(geo, track)
				for _, sp in ipairs(HazardPlan.logSpots(geo, track.width, maxS, logCfg.count or 3, logRng, logClear)) do
					local lo, hi = HazardPlan.span(sp)
					table.insert(logs, { spot = sp, landAt = t + H.LOG_WARN, goneAt = t + H.LOG_WARN + H.LOG_LIFETIME,
						half = (hi - lo) / 2, hit = false })
					res.logsDropped += 1
				end
			end
			if opts.avoid ~= false then
				seen = {}
				for _, lg in ipairs(logs) do
					if t < lg.goneAt and (not layered or math.abs((lg.spot.y or roadY) - roadY) < 10) then
						table.insert(seen, { x = lg.spot.x, z = lg.spot.z, half = lg.half })
					end
				end
			end
		end
		local keys, info = ap:update({
			hazards = seen,
			x = x, z = z, y = roadY + 2, yaw = yaw, speed = speed,
			forward = vx * -math.sin(yaw) + vz * -math.cos(yaw),
			maxSpeed = mods:value(t), turnSpeed = effTurn * turnK, t = t,
			isSky = isSky, biome = world.biome, travelYaw = driveState.travelYaw,
		})
		if opts.noDrift then keys.Shift = nil end
		local s = info.s
		if s > maxS then maxS = s end
		roadY = geo:heightAt(s)
		if opts.onStep then
			opts.onStep({
				t = t, s = s, speed = speed, maxSpeed = mods:value(t), err = info.err, keys = keys,
				mods = mods, turn = turnMods, res = res,
				straight = function(dist)
					local y0 = geo:yawAt(s)
					for d = 10, dist, 10 do
						if math.abs(VehicleController.wrapAngle(geo:yawAt(s + d) - y0)) > math.rad(12) then return false end
					end
					return true
				end,
				knock = function(along, side)
					local lx, lz = -math.sin(yaw), -math.cos(yaw)
					VehicleController.knock(driveState, lx * along - lz * (side or 0), lz * along + lx * (side or 0), 0, lx, lz, mods:value(t))
				end,
				refillBoost = function() gauge = 1 end,
				gauge = function() return gauge end,
				ground = function(untilT) groundFreeUntil = math.max(groundFreeUntil, untilT) end,
			})
		end

		-- Section bookkeeping (by furthest progress)
		local sec = sectionFor(maxS)
		if sec > sectionIdx then
			res.sections[sectionIdx].exit = t
			sectionIdx = sec
			res.sections[sectionIdx] = { name = track.sections[sec].name, enter = t }
		end

		-- Off-track rescue / stuck respawn (player presses R)
		local here = geo:project(x, z, info.seg, 2)
		local outside = here.dist > track.width / 2 + 2.5
		if outside then
			if not offTrackSince then
				offTrackSince = t
				table.insert(res.escapes, { t = t, s = s, x = x, z = z, lateral = info.lateral })
			elseif t - offTrackSince > KineSim.OFFTRACK_RESCUE then
				respawn(t, "off_track", s)
				continue
			end
		else
			offTrackSince = nil
		end
		if info.respawn then
			respawn(t, "stuck", s)
			continue
		end

		-- Triggers: checkpoints, finish, pads, drift corners, mud, slow zones.
		-- Gates are tested along the whole move of this step: a fast car covers
		-- more than a thin gate's depth in one 60 Hz step (Roblox steps physics
		-- at 240 Hz and the car body is several studs long, so it never skips).
		local nowMud, nowSlow = false, false
		for _, tr in ipairs(world.triggers) do
			local inside
			if layered and not (tr.yMax > roadY and tr.yMin < roadY + 8) then
				inside = false
			elseif tr.isGate then
				inside = MapQuery.crosses(tr, prevX, prevZ, x, z)
			else
				inside = MapQuery.contains(tr, x, z)
			end
			if inside then
				local tags = tr.tags
				if table.find(tags, "Checkpoint1") and not cp[1] then
					cp[1] = true
					table.insert(res.checkpoints, { index = 1, t = t })
				elseif table.find(tags, "Checkpoint2") and cp[1] and not cp[2] then
					cp[2] = true
					table.insert(res.checkpoints, { index = 2, t = t })
				elseif table.find(tags, "FinishLine") then
					if cp[1] and cp[2] then
						res.finished = true
						res.time = t
					elseif not res.finishRejected then
						res.finishRejected = t
					end
				elseif table.find(tags, "BoostPad") and active[tr] then
					if (padCooldown[tr] or 0) <= t then
						padCooldown[tr] = t + 5
						mods:set("pad", 1.4, t + 2)
						table.insert(res.effects, { t = t, effect = "boost_pad", s = s })
					end
				elseif table.find(tags, "DriftCorner") then
					if (cornerCooldown[tr] or 0) <= t then
						cornerCooldown[tr] = t + Constants.DRIFT_CORNER_COOLDOWN
						gauge = math.min(1, gauge + Constants.DRIFT_CHARGE_PER_CORNER)
					end
				elseif table.find(tags, "MudZone") then
					nowMud = true
				elseif table.find(tags, "SlowZone") then
					nowSlow = true
				end
			end
		end
		if res.finished then break end
		if t < groundFreeUntil then nowMud, nowSlow = false, false end
		if nowMud ~= insideMud then
			insideMud = nowMud
			if nowMud then mods:set("mud", Constants.MUD_SPEED_MULT) else mods:remove("mud") end
			table.insert(res.effects, { t = t, effect = nowMud and "mud_enter" or "mud_exit", s = s })
		end
		if nowSlow ~= insideSlow then
			insideSlow = nowSlow
			if nowSlow then mods:set("slow", Constants.SLOW_ZONE_MULT) else mods:remove("slow") end
		end

		-- Boost (F): use a full gauge on a straight-ish stretch.
		if gauge >= 1 and t >= boostCooldownEnd and math.abs(info.err) < 0.1 and keys.W then
			gauge = 0
			boostCooldownEnd = t + Constants.BOOST_COOLDOWN
			mods:set("boost", Constants.BOOST_MULTIPLIER, t + car.boostDuration)
			table.insert(res.effects, { t = t, effect = "boost", s = s })
		end

		-- Drive: exactly the client's command path.
		local input = VehicleController.readKeys(keys)
		-- speed along the direction the car is travelling (the nose while gripping)
		local ty0 = driveState.travelYaw or yaw
		local tx0, tz0 = -math.sin(ty0), -math.cos(ty0)
		-- Drift: entered and left exactly like RacingClient; a released
		-- drift pays its mini-turbo (the server's VehicleTuning multiplier).
		local maxNow = mods:value(t)
		local change, level = VehicleController.updateDrift(driveState, input, speed, maxNow, isSky)
		if change == "enter" then
			res.drifts += 1
		elseif level then
			local tb = Constants.DRIVE.DRIFT_TURBO[level]
			mods:set("driftTurbo", tb.mult, t + tb.duration)
			res.turbos += 1
		end
		local drifting = driveState.drifting
		local cmd = VehicleController.command(input, {
			maxSpeed = maxNow, turnSpeed = car.turnSpeed * turnK, isSky = isSky, drifting = drifting,
			biome = world.biome, yaw = yaw,
			torque = car.torque, dt = dt, actualForward = vx * tx0 + vz * tz0,
		}, driveState)
		if drifting then res.driftSeconds += dt end
		yaw += cmd.yawRate * dt
		local tyaw = cmd.travelYaw or yaw
		local lx, lz = -math.sin(tyaw), -math.cos(tyaw)
		local tvx, tvz = lx * cmd.forwardSpeed + cmd.knockX, lz * cmd.forwardSpeed + cmd.knockZ
		local dvx, dvz = tvx - vx, tvz - vz
		local dmag = math.sqrt(dvx * dvx + dvz * dvz)
		local maxDv = accel * dt
		if dmag > maxDv then
			dvx, dvz = dvx / dmag * maxDv, dvz / dmag * maxDv
		end
		vx += dvx
		vz += dvz
		prevX, prevZ = x, z   -- start of this step's move (gate sweep next step)
		x += vx * dt
		z += vz * dt

		-- Collisions: circle vs. part footprints, slide along surfaces.
		for _ = 1, 3 do
			local pushed = false
			for _, ob in ipairs(world.obstacleGrid.near(x, z, r + 2)) do
				if layered and not MapQuery.inBand(ob, roadY, band) then continue end
				local cx, cz, inside = MapQuery.closest(ob, x, z)
				local nx, nz = x - cx, z - cz
				local d = math.sqrt(nx * nx + nz * nz)
				if inside or d < r then
					if inside or d < 1e-6 then
						-- Centre inside the part: push out along the shallowest axis.
						local _, _, _, u, v = MapQuery.closest(ob, x, z)
						local pu, pv = ob.hu - math.abs(u), ob.hv - math.abs(v)
						if pu < pv then
							local sgn = u >= 0 and 1 or -1
							nx, nz, d = ob.ux * sgn, ob.uz * sgn, -pu
						else
							local sgn = v >= 0 and 1 or -1
							nx, nz, d = ob.vx * sgn, ob.vz * sgn, -pv
						end
					else
						nx, nz = nx / d, nz / d
					end
					local pen = r - d
					x += nx * pen
					z += nz * pen
					local vn = vx * nx + vz * nz
					if vn < 0 then
						vx -= vn * nx
						vz -= vn * nz
						res.contacts += 1
						if -vn > KineSim.IMPACT_SPEED then
							table.insert(res.impacts, { t = t, s = s, x = x, z = z, part = ob.name, speed = -vn })
						end
						res.blockedBy[ob.name] = (res.blockedBy[ob.name] or 0) + 1
					end
					pushed = true
				end
			end
			if not pushed then break end
		end

		-- Landed logs: a rectangle (long axis across the lane); the first touch
		-- is the RacingManager obstacle hit (× OBSTACLE_BOUNCE_SPEED_MULT and a
		-- knock away), then the car slides along it.
		for _, lg in ipairs(logs) do
			if t >= lg.landAt and t < lg.goneAt and (not layered or math.abs((lg.spot.y or roadY) - roadY) < 10) then
				local sp = lg.spot
				local ux, uz = math.cos(sp.yaw), -math.sin(sp.yaw)     -- CFrame X axis (long)
				local wx, wz = -uz, ux
				local dx, dz = x - sp.x, z - sp.z
				local u, w = dx * ux + dz * uz, dx * wx + dz * wz
				local hu, hw = sp.length / 2 + r, H.LOG_SIZE[2] / 2 + r
				if math.abs(u) < hu and math.abs(w) < hw then
					local pu, pw = hu - math.abs(u), hw - math.abs(w)
					local nx, nz
					if pu < pw then
						nx, nz = ux * (u >= 0 and 1 or -1), uz * (u >= 0 and 1 or -1)
						x += nx * pu; z += nz * pu
					else
						nx, nz = wx * (w >= 0 and 1 or -1), wz * (w >= 0 and 1 or -1)
						x += nx * pw; z += nz * pw
					end
					local vn = vx * nx + vz * nz
					if vn < 0 then vx -= vn * nx; vz -= vn * nz end
					if not lg.hit then
						lg.hit = true
						res.logHits += 1
						mods:set("obstacle", Constants.OBSTACLE_BOUNCE_SPEED_MULT, t + Constants.OBSTACLE_BOUNCE_PENALTY_DURATION)
						local lx, lz = -math.sin(yaw), -math.cos(yaw)
						VehicleController.knock(driveState, nx * Constants.OBSTACLE_BOUNCE_PUSH, nz * Constants.OBSTACLE_BOUNCE_PUSH, 0, lx, lz, mods:value(t))
						table.insert(res.effects, { t = t, effect = "log_hit", s = s })
					end
				end
			end
		end

		if t - lastSample >= KineSim.SAMPLE_EVERY then
			lastSample = t
			table.insert(res.samples, {
				t = math.floor(t * 100) / 100,
				x = math.floor(x * 10) / 10, z = math.floor(z * 10) / 10,
				s = math.floor(s), lat = math.floor(info.lateral * 10) / 10,
				speed = math.floor(math.sqrt(vx * vx + vz * vz) * 10) / 10,
				drift = driveState.drifting or nil,
				slide = driveState.drifting and math.floor((driveState.travelYaw and math.abs(VehicleController.wrapAngle(yaw - driveState.travelYaw)) or 0) * 100) / 100 or nil,
			})
		end
	end

	res.sections[sectionIdx].exit = res.time or t
	res.maxProgress = maxS
	res.trackLength = geo.length
	res.endT = t
	return res
end

return KineSim
