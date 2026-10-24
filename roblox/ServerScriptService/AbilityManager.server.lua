-- AbilityManager.server.lua
-- Server-authoritative ability activation, cooldown enforcement,
-- and effect dispatch for every item ability (AbilityConfig).
-- Resolves: Issue #55, #56, #57, #58

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris              = game:GetService("Debris")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local ItemConfig     = require(ReplicatedStorage.Shared.ItemConfig)
local AbilityConfig  = require(ServerScriptService.Modules.AbilityConfig)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local VehicleTuning  = require(ServerScriptService.Modules.VehicleTuning)
local RaceEffects    = require(ServerScriptService.Modules.RaceEffects)
local RaceStart      = require(ServerScriptService.Modules.RaceStart)
local EffectFx       = require(ServerScriptService.Modules.EffectFx)
local VehicleLift    = require(ServerScriptService.Modules.VehicleLift)
local AbilitySlots   = require(ReplicatedStorage.Shared.AbilitySlots)
local TrackDrops     = require(ServerScriptService.Modules.TrackDrops)
local RaceBots       = require(ServerScriptService.Modules.RaceBots)
local CollectionService = game:GetService("CollectionService")

-- ─── Per-player cooldown store ────────────────────────────────────────────────
-- _cooldowns[userId][itemName] = expireTick

local _cooldowns   = {}
local _activeDurations = {}   -- [userId][itemName] = expireTick (effect is live)
local _biome       = nil

local LIFT = Constants.ABILITY_LIFT

-- ─── Helpers ──────────────────────────────────────────────────────────────────
-- Speed / turn changes go through VehicleTuning (named multipliers, never
-- save-and-restore). Harmful effects on another player ask _hurts(target)
-- first, which honours shields (Umbrella, Suitcase, Red Sofa, Rubber Duck).

-- Race bots (Modules/RaceBots) are SessionManager bot proxies: targets like
-- anyone, but they have no client (no screen effects; shoves go to
-- RaceBots.knock).
local function _screen(who, ...)
	if who and not SessionManager.isBot(who) then RemoteEvents.ScreenEffect:FireClient(who, ...) end
end

local function _getVehicle(player)
	local pdata = SessionManager.getData(player)
	return pdata and pdata.vehicleModel
end

local function _getSeat(vehicle)
	return vehicle and vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
end

local function _applySpeedMult(vehicle, mult, duration, id)
	local seat = _getSeat(vehicle)
	if not seat then return end
	VehicleTuning.set(seat, "MaxSpeed", id or "ability", mult, duration)
end

local function _applyTurnMult(vehicle, mult, duration, id)
	local seat = _getSeat(vehicle)
	if not seat then return end
	VehicleTuning.set(seat, "TurnSpeed", id or "ability", mult, duration)
end

-- True when `target` actually takes a harmful effect (not shielded).
local function _hurts(target)
	if not target then return false end
	if RaceEffects.blocksHit(target) then
		EffectFx.play("blocked", target, nil)
		_screen(target, "bubblePop", {})
		Telemetry.record("hit_blocked", { userId = target.UserId, by = "ability" })
		return false
	end
	return true
end

local function _applyBodyForce(vehicle, force, duration, name)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	local bf = Instance.new("BodyForce")
	bf.Name  = name or "AbilityForce"
	bf.Force = force
	bf.Parent = primary
	Debris:AddItem(bf, duration)
end

-- A shove: sent to the car's driver as a CarImpact knock, which the drive
-- model adds to its own velocity (a second BodyVelocity would fight
-- DriveVelocity and do almost nothing).
local function _impulse(vehicle, direction, magnitude)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary or direction.Magnitude < 1e-3 or not magnitude or magnitude <= 0 then return end
	local d = direction.Unit * magnitude
	for _, p in ipairs(SessionManager.actors()) do
		local pd = SessionManager.getData(p)
		if pd and pd.vehicleModel == vehicle then
			if SessionManager.isBot(p) then
				RaceBots.knock(p.UserId, d.X, d.Z, 0)
			else
				RemoteEvents.CarImpact:FireClient(p, d.X, d.Z, 0, magnitude)
			end
			return
		end
	end
end

local function _flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Every drop is logged so the Studio harness can check it landed on the
-- track and shows its item.
local function _dropLogged(activator, itemName, effectKey, drop)
	local pos = drop.position
	local parts = 0
	for _, d in ipairs(drop.folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "DropHazard" and d.Name ~= "DropRing" and d.Name ~= "DropPuddle" then parts += 1 end
	end
	Telemetry.record("drop_placed", {
		userId = activator.UserId, item = itemName, effect = effectKey,
		x = math.floor(pos.X), y = math.floor(pos.Y * 10) / 10, z = math.floor(pos.Z),
		onGround = drop.surfaceY ~= nil, modelParts = parts,
		size = math.floor(math.max(drop.size.X, drop.size.Y, drop.size.Z) * 10) / 10,
	})
end


-- Disguised players (Cardboard Box) cannot be targeted.
local function _targetable(player)
	return not RaceEffects.has(player, "disguised")
end

local function _nearestEnemy(player, radius)
	local pdata   = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return nil end
	local pos     = vehicle.PrimaryPart.Position

	local best, bestDist = nil, radius or math.huge
	for _, other in ipairs(SessionManager.actors()) do
		if other == player or not _targetable(other) then continue end
		local od = SessionManager.getData(other)
		local ov = od and od.vehicleModel
		if ov and ov.PrimaryPart then
			local d = (ov.PrimaryPart.Position - pos).Magnitude
			if d < bestDist then bestDist = d; best = other end
		end
	end
	return best
end

local function _allInRadius(player, radius)
	local pdata   = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return {} end
	local pos = vehicle.PrimaryPart.Position

	local result = {}
	for _, other in ipairs(SessionManager.actors()) do
		if other == player or not _targetable(other) then continue end
		local od = SessionManager.getData(other)
		local ov = od and od.vehicleModel
		if ov and ov.PrimaryPart then
			if (ov.PrimaryPart.Position - pos).Magnitude <= radius then
				table.insert(result, other)
			end
		end
	end
	return result
end

-- Racers touching `part` (other than `except`), each reported once per call.
local function _onDropTouched(part, except, fn)
	local seen = {}
	part.Touched:Connect(function(hit)
		local v = hit:FindFirstAncestorWhichIsA("Model")
		if not v then return end
		for _, p in ipairs(SessionManager.actors()) do
			if p ~= except and not seen[p] then
				local pd = SessionManager.getData(p)
				if pd and pd.vehicleModel == v then
					seen[p] = true
					task.delay(1, function() seen[p] = nil end)
					fn(p, v)
				end
			end
		end
	end)
end

-- ─── Effect dispatcher ────────────────────────────────────────────────────────
-- Every effect that lands on a car calls EffectFx.play(key, player, ...)
-- just before it applies: all clients draw it on that car
-- (Shared/EffectLook) and the Studio harness measures it (ability_probe).
-- Keys: the effectKey for the activator's own effect, a "victim" key for
-- what happens to others (see EffectLook).

local EFFECTS = {}

-- Ride-height lift (VehicleController reads LiftOffset). A lifted car
-- skips mud and ground drops, and glides at selfSpeed (AbilityConfig).
local function _lift(activator, cfg, studs)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	VehicleLift.set(vehicle, cfg.effectKey, studs or LIFT[cfg.effectKey], cfg.duration)
	if cfg.selfSpeed and cfg.selfSpeed ~= 1 then
		_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "lift")
	end
	return vehicle
end

-- ── SPECIAL ──────────────────────────────────────────────────────────────────

EFFECTS.steerDisable = function(activator, target, cfg)
	if not _hurts(target) then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_applyTurnMult(_getVehicle(target), cfg.victimTurn or 0, cfg.victimFor or cfg.duration, "steerDisable")
	_screen(target, "steerDisable", { duration = cfg.duration })
end

EFFECTS.slipperyPuddle = function(activator, _, cfg, itemName)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local isWater = cfg.effectKey ~= "slipperyPuddle"
	local size = (cfg.radius or 4) * 2
	local colour = isWater and Color3.fromRGB(70, 150, 255) or Color3.fromRGB(220, 140, 50)
	local drop = TrackDrops.place(itemName or "Pizza", vehicle, {
		behind = 6, show = 4, lifetime = cfg.duration + 6,
		hazard = { kind = "slick", size = Vector3.new(size, 3, size), color = colour },
	})
	if not drop then return end
	-- the slick itself: a glossy puddle on the ground under the item
	local puddle = Instance.new("Part")
	puddle.Name = "DropPuddle"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.2, size, size)
	puddle.CFrame = CFrame.new(drop.position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	puddle.Color = colour
	puddle.Material = Enum.Material.Glass
	puddle.Transparency = 0.3
	puddle.Anchored, puddle.CanCollide, puddle.CanTouch, puddle.CanQuery, puddle.CastShadow = true, false, false, false, false
	puddle.Parent = drop.folder
	_dropLogged(activator, itemName, cfg.effectKey, drop)
	_onDropTouched(drop.hazard, activator, function(p, v)
		if not _hurts(p) then return end
		EffectFx.play("slipped", p, cfg.hitFor, activator)
		_applySpeedMult(v, cfg.hitSpeed, cfg.hitFor, "slippery")
		_screen(p, "slippery", {})
	end)
end

EFFECTS.emergencyFloat = function(activator, _, cfg) _lift(activator, cfg) end
EFFECTS.fullBuoyancy   = EFFECTS.emergencyFloat   -- OCEAN Rubber Duck
EFFECTS.softLanding    = EFFECTS.emergencyFloat   -- SKY Rubber Duck
EFFECTS.groundBounce   = EFFECTS.emergencyFloat   -- FOREST Rubber Duck: a short hop
EFFECTS.rise           = EFFECTS.emergencyFloat   -- Balloon Bunch, Lantern

EFFECTS.reverseBoost = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_impulse(vehicle, vehicle.PrimaryPart.CFrame.LookVector, cfg.push)
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "sodaBlast")
end

EFFECTS.flagAura = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "flagAura")
	local ally = (cfg.allySpeed or 1) ~= 1 and _nearestEnemy(activator, cfg.allyRange or 40)
	if ally then
		EffectFx.play(cfg.effectKey, ally, cfg.duration, activator)
		_applySpeedMult(_getVehicle(ally), cfg.allySpeed, cfg.duration, "flagAura")
		_screen(ally, "flagBuff", { duration = cfg.duration })
	end
end

EFFECTS.cactusObstacle = function(activator, _, cfg, itemName)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local drop = TrackDrops.place(itemName or "Cactus", vehicle, {
		behind = 7, show = 5, lifetime = cfg.duration + 8,
		hazard = { kind = "obstacle", color = Color3.fromRGB(120, 220, 80) },
	})
	if not drop then return end
	_dropLogged(activator, itemName, cfg.effectKey, drop)
	-- RacingManager connects every part tagged Obstacle, including new ones
	CollectionService:AddTag(drop.hazard, "Obstacle")
end

EFFECTS.umbrellaBlock = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "shield", cfg.duration)   -- blocks the next hit
	if cfg.selfSpeed then _applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "umbrella") end
end

EFFECTS.umbrellaSail = function(activator, _, cfg)
	-- Side-wind speed bonus: lateral force plus a little speed
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyBodyForce(vehicle, vehicle.PrimaryPart.CFrame.RightVector * 600, cfg.duration, "UmbrellaSail")
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "umbrellaSail")
end

EFFECTS.parachute = function(activator, _, cfg)
	-- SKY Umbrella: a canopy that lifts the flyer and blocks the next hit
	-- (it used to halve the flyer's speed for 6 s: a pure penalty)
	_lift(activator, cfg)
	RaceEffects.grant(activator, "shield", cfg.duration)
end

EFFECTS.magnetPull = function(activator, target, cfg)
	-- Pull the nearest racer back toward you and slow them while held
	if not _hurts(target) then return end
	local me, them = _getVehicle(activator), _getVehicle(target)
	if not me or not them or not me.PrimaryPart or not them.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_impulse(them, _flat(me.PrimaryPart.Position - them.PrimaryPart.Position), cfg.victimPush)
	_applySpeedMult(them, cfg.victimSpeed, cfg.victimFor or cfg.duration, "magnetPull")
	_screen(target, "magnetPull", { duration = cfg.duration })
end

-- ── ENGINE ────────────────────────────────────────────────────────────────────

EFFECTS.digMode = function(activator, _, cfg)
	-- Drill: mud and off-track slow zones have no effect while active
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "dig", cfg.duration)
	if cfg.selfSpeed then _applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "dig") end
	local seat = _getSeat(_getVehicle(activator))
	if seat then
		VehicleTuning.remove(seat, "MaxSpeed", "mud")
		VehicleTuning.remove(seat, "MaxSpeed", "slowZone")
	end
end

EFFECTS.bloomCleanse = function(activator, _, cfg)
	-- Flower: shake off every active slowdown and stay protected briefly
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	local seat = _getSeat(_getVehicle(activator))
	local removed = seat and VehicleTuning.cleanse(seat) or 0
	RaceEffects.grant(activator, "shield", cfg.duration)
	if cfg.selfSpeed then _applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "bloom") end
	Telemetry.record("cleanse", { userId = activator.UserId, removed = removed })
end

EFFECTS.overclock = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, 1.5, cfg.duration, "overclock")
	task.delay(cfg.duration, function()   -- stall
		EffectFx.play("stall", activator, 1.0)
		_applySpeedMult(vehicle, 0.2, 1.0, "overclockStall")
	end)
end

EFFECTS.hover = function(activator, _, cfg) _lift(activator, cfg) end

EFFECTS.redline = function(activator, _, cfg)
	-- Treadmill: much faster, but no steering while it lasts
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "redline")
	_applyTurnMult(vehicle, cfg.selfTurn or 0, cfg.duration, "redline")
	_screen(activator, "redlineActive", { duration = cfg.duration })
end

EFFECTS.steamCloud = function(activator, _, cfg, itemName)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local drop = TrackDrops.place(itemName or "Kettle", vehicle, {
		behind = 8, show = 4, lifetime = cfg.duration,
		hazard = { kind = "cloud", size = Vector3.new(12, 7, 12), color = Color3.fromRGB(235, 235, 245) },
	})
	if not drop then return end
	local steam = Instance.new("ParticleEmitter")   -- the kettle keeps steaming
	steam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 245))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1.2, 2)
	steam.Rate = 40
	steam.Speed = NumberRange.new(1, 3)
	steam.SpreadAngle = Vector2.new(180, 180)
	steam.Parent = drop.hazard
	_dropLogged(activator, itemName, cfg.effectKey, drop)
	_onDropTouched(drop.hazard, activator, function(p)
		if not _hurts(p) then return end
		EffectFx.play("steamed", p, math.min(3, cfg.duration), activator)
		_screen(p, "steamBlind", { duration = math.min(3, cfg.duration) })
		if cfg.hitSpeed then _applySpeedMult(_getVehicle(p), cfg.hitSpeed, cfg.hitFor, "steamed") end
	end)
end

EFFECTS.noodleSnare = function(activator, target, cfg)
	if not _hurts(target) then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_applySpeedMult(_getVehicle(target), cfg.victimSpeed, cfg.victimFor or cfg.duration, "noodleSnare")
	_screen(target, "noodleSnare", { duration = cfg.duration })
end

EFFECTS.rocketBurst = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "rocketBurst")
	local primary = vehicle and vehicle.PrimaryPart
	if primary then _impulse(vehicle, primary.CFrame.LookVector, cfg.push) end
end

EFFECTS.windBlast = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local origin  = vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.Position or Vector3.zero
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 12)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			EffectFx.play("blown", target, nil, activator)
			_impulse(tv, _flat(tv.PrimaryPart.Position - origin), cfg.victimPush)
			if cfg.victimSpeed then _applySpeedMult(tv, cfg.victimSpeed, cfg.victimFor or cfg.duration, "windBlast") end
			_screen(target, "windBlast", {})
		end
	end
end

EFFECTS.gustBlast = function(activator, _, cfg)
	-- Fan: shoves racers IN FRONT of you sideways and slows them a little
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, activator, nil)
	local origin = vehicle.PrimaryPart.Position
	local look = _flat(vehicle.PrimaryPart.CFrame.LookVector)
	if look.Magnitude < 1e-3 then return end
	look = look.Unit
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 10)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart then
			local to = _flat(tv.PrimaryPart.Position - origin)
			if to.Magnitude > 1e-3 and look:Dot(to.Unit) > 0.3 and _hurts(target) then
				local side = Vector3.new(-look.Z, 0, look.X)
				if side:Dot(to) < 0 then side = -side end
				EffectFx.play("blown", target, cfg.duration, activator)
				_impulse(tv, side, cfg.victimPush)
				_applySpeedMult(tv, cfg.victimSpeed, cfg.victimFor or cfg.duration, "gustBlast")
				_screen(target, "windBlast", {})
			end
		end
	end
end

EFFECTS.waterPuddle = EFFECTS.slipperyPuddle      -- same slick, water coloured
EFFECTS.waterPuddleLarge = EFFECTS.slipperyPuddle

EFFECTS.spinBurst = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	local fwd = primary.CFrame.LookVector
	local angle = (math.random() - 0.5) * math.pi * 0.4   -- the "chaos"
	local rotated = Vector3.new(
		fwd.X * math.cos(angle) - fwd.Z * math.sin(angle),
		fwd.Y,
		fwd.X * math.sin(angle) + fwd.Z * math.cos(angle)
	)
	_impulse(vehicle, rotated, cfg.push)
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "spinBurst")
end

EFFECTS.windRide = function(activator, _, cfg)
	-- stronger in SKY / OCEAN: AbilityConfig biomeEffect
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "windRide")
end

-- ── BODY ──────────────────────────────────────────────────────────────────────

EFFECTS.disguise = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "disguised", cfg.duration)
end

EFFECTS.raftGlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyTurnMult(vehicle, cfg.selfTurn or 1, cfg.duration, "raftGlide")   -- slippery but steerable
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "raftGlide")
end

EFFECTS.logObstacle = function(activator, _, cfg, itemName)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local drop = TrackDrops.place(itemName or "Log", vehicle, {
		behind = 7, show = 7, lifetime = 12,
		hazard = { kind = "obstacle", color = Color3.fromRGB(200, 140, 70) },
	})
	if not drop then return end
	_dropLogged(activator, itemName, cfg.effectKey, drop)
	CollectionService:AddTag(drop.hazard, "Obstacle")
end

EFFECTS.sofaFortress = function(activator, _, cfg)
	-- Red Sofa: nothing can hurt you, and racers next to you bounce off
	-- (it used to stop the sofa dead for 2 s: a trap for its own driver)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "invincible", cfg.duration)
	if cfg.selfSpeed then _applySpeedMult(vehicle, cfg.selfSpeed, cfg.selfFor or cfg.duration, "sofaFortress") end
	if not primary then return end
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 8)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			EffectFx.play("rammed", target, nil, activator)
			_impulse(tv, _flat(tv.PrimaryPart.Position - primary.Position), cfg.victimPush)
			if cfg.victimSpeed then _applySpeedMult(tv, cfg.victimSpeed, cfg.victimFor or cfg.duration, "sofaBounce") end
			_screen(target, "collision", {})
		end
	end
end

EFFECTS.cartRam = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_impulse(vehicle, primary.CFrame.LookVector, cfg.push)
	if cfg.selfSpeed then _applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "cartRam") end
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 6)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			EffectFx.play("rammed", target, nil, activator)
			_impulse(tv, _flat(tv.PrimaryPart.Position - primary.Position), cfg.victimPush)
			_screen(target, "collision", {})
		end
	end
end

EFFECTS.barrelRoll = function(activator, _, cfg)
	-- Barrel: sideways roll that knocks adjacent racers aside
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "barrelRoll")
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 8)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			local right = _flat(primary.CFrame.RightVector)
			local to = _flat(tv.PrimaryPart.Position - primary.Position)
			local dir = (right:Dot(to) >= 0) and right or -right
			EffectFx.play("rammed", target, nil, activator)
			_impulse(tv, dir, cfg.victimPush)
			_screen(target, "collision", {})
		end
	end
end

EFFECTS.lockdown = function(activator, _, cfg)
	-- Suitcase: locks shut, the next hit is absorbed
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	if cfg.selfSpeed then _applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.selfFor or 0.5, "lockdown") end
	RaceEffects.grant(activator, "shield", cfg.duration)
end

EFFECTS.microFreeze = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 12)) do
		if _hurts(target) then
			EffectFx.play("frozen", target, cfg.duration, activator)
			_applySpeedMult(_getVehicle(target), cfg.victimSpeed, cfg.victimFor or cfg.duration, "microFreeze")
			_screen(target, "microFreeze", { duration = cfg.duration })
		end
	end
end

EFFECTS.bathSplash = function(activator, target, cfg)
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, t in ipairs(_allInRadius(activator, cfg.radius or 8)) do
		if _hurts(t) then
			EffectFx.play("splashed", t, cfg.victimFor, activator)
			_screen(t, "bathSplash", { duration = cfg.duration })
			_applySpeedMult(_getVehicle(t), cfg.victimSpeed, cfg.victimFor, "bathSplash")
		end
	end
end

EFFECTS.backpackBoost = function(activator, _, cfg)
	-- Backpack: the client refills its boost gauge
	EffectFx.play(cfg.effectKey, activator, nil)
	_screen(activator, "boostRecharge", {})
	if cfg.selfSpeed then _applySpeedMult(_getVehicle(activator), cfg.selfSpeed, cfg.duration, "backpack") end
end

EFFECTS.skateSlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyTurnMult(vehicle, cfg.selfTurn or 1, cfg.duration, "skateSlide")   -- very twitchy
	_applySpeedMult(vehicle, cfg.selfSpeed, cfg.duration, "skateSlide")
end

EFFECTS.lifeFloat = function(activator, _, cfg) _lift(activator, cfg) end
EFFECTS.kiteLift  = EFFECTS.lifeFloat
EFFECTS.kiteGlide = function(activator, _, cfg)
	_lift(activator, cfg)
end

-- ─── RequestAbility handler ───────────────────────────────────────────────────

GameManager.onPhaseChanged(function(phase, biome)
	_biome = biome
	if phase ~= Constants.PHASES.RACING then
		_cooldowns        = {}
		_activeDurations  = {}
	end
end)

local function _handleAbilityRequest(player, itemName)
	if type(itemName) ~= "string" then return "denied: bad item" end
	local abilCfg = AbilityConfig.get(itemName, _biome)
	if not abilCfg then return "denied: no config" end

	local phase = GameManager.getPhase()
	if abilCfg.phaseRestrict then
		if phase ~= Constants.PHASES[abilCfg.phaseRestrict] then
			return "denied: wrong phase"
		end
	else
		if phase ~= Constants.PHASES.RACING then return "denied: not racing" end
	end

	-- Cooldown check
	local userId = player.UserId
	_cooldowns[userId] = _cooldowns[userId] or {}
	if tick() < (_cooldowns[userId][itemName] or 0) then
		return "denied: cooldown"
	end

	if not RaceStart.isGo() then return "denied: countdown" end

	local pdata = SessionManager.getData(player)
	if not pdata then return "denied: no data" end

	local itemCfg = ItemConfig[itemName]
	if not itemCfg then return "denied: unknown item" end

	-- Only an item crafted into one of the car's ability slots can fire
	-- (the client sends just an item name).
	local slots = pdata.vehicleStats and pdata.vehicleStats.slotAssignments
	if not AbilitySlots.slotOf(slots, itemName) then return "denied: not equipped" end
	if not pdata.vehicleModel or not pdata.vehicleModel.PrimaryPart then return "denied: no vehicle" end

	-- Apply Epic bonus if applicable
	if itemCfg.rarity == Constants.RARITY.EPIC then
		abilCfg = AbilityConfig.applyEpicBonus(abilCfg)
	end

	-- Determine target
	local target = nil
	if abilCfg.targetType == "nearest" then
		target = _nearestEnemy(player, 60)
	elseif abilCfg.targetType == "random_enemy" then
		local enemies = _allInRadius(player, 9999)  -- all players
		if #enemies > 0 then target = enemies[math.random(#enemies)] end
	end

	if target then
		Telemetry.record("ability_target", { userId = userId, item = itemName, target = target.UserId,
			bot = SessionManager.isBot(target) or nil })
	end

	-- Set cooldown before dispatching (prevents double-fire)
	_cooldowns[userId][itemName] = tick() + abilCfg.cooldown

	-- Dispatch effect
	local effectFn = EFFECTS[abilCfg.effectKey]
	if effectFn then
		task.spawn(effectFn, player, target, abilCfg, itemName)
	else
		warn("[AbilityManager] No effect handler for:", abilCfg.effectKey)
		Telemetry.record("ability_unhandled", { userId = userId, item = itemName, effect = abilCfg.effectKey })
	end

	-- Broadcast: the HUD (cooldown), sounds and the activator's label.
	-- What lands on each car goes out separately as EffectFx.
	local targetIds = target and { target.UserId } or {}
	RemoteEvents.AbilityActivated:FireAllClients(userId, itemName, targetIds, abilCfg.effectKey, {
		cooldown = abilCfg.cooldown, duration = abilCfg.duration, label = abilCfg.uiHint,
	})

	return "ok"
end

-- Telemetry wrapper: logs every ability request and its result, including
-- each early "denied" return above. (OnServerInvoke is write-only in Roblox,
-- so the handler is a local function wrapped here.)
local function _request(player, itemName)
	local result = _handleAbilityRequest(player, itemName)
	Telemetry.record("ability", { userId = player.UserId, item = itemName, result = result,
		bot = SessionManager.isBot(player) or nil })
	return result
end
RemoteEvents.RequestAbility.OnServerInvoke = _request
-- race bots fire through the same checks
RaceBots.setAbilityHandler(_request)
