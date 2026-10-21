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
		RemoteEvents.ScreenEffect:FireClient(target, "bubblePop", {})
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

local function _impulse(vehicle, direction, magnitude)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary or direction.Magnitude < 1e-3 then return end
	local bv = Instance.new("BodyVelocity")
	bv.Velocity  = direction.Unit * magnitude
	bv.MaxForce  = Vector3.new(1e5, 1e4, 1e5)
	bv.Parent    = primary
	Debris:AddItem(bv, 0.3)
end

local function _flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function _dropPart(position, size, colour, tag, duration)
	local p = Instance.new("Part")
	p.Size     = size
	p.CFrame   = CFrame.new(position)
	p.Anchored = true
	p.Color    = colour
	-- Slippery zones / visual clouds are pass-through; obstacles stay solid.
	p.CanCollide = not (tag == "Slippery" or tag == "SteamCloud")
	p.Parent   = workspace
	if tag then
		local t = Instance.new("StringValue")
		t.Value  = tag
		t.Name   = "DropTag"
		t.Parent = p
	end
	Debris:AddItem(p, duration)
	return p
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
	for _, other in ipairs(Players:GetPlayers()) do
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
	for _, other in ipairs(Players:GetPlayers()) do
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
		for _, p in ipairs(Players:GetPlayers()) do
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

-- Ride-height lift (VehicleController reads LiftOffset).
local function _lift(activator, cfg, studs)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	VehicleLift.set(vehicle, cfg.effectKey, studs or LIFT[cfg.effectKey], cfg.duration)
	return vehicle
end

-- ── SPECIAL ──────────────────────────────────────────────────────────────────

EFFECTS.steerDisable = function(activator, target, cfg)
	if not _hurts(target) then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_applyTurnMult(_getVehicle(target), 0, cfg.duration, "steerDisable")
	RemoteEvents.ScreenEffect:FireClient(target, "steerDisable", { duration = cfg.duration })
end

EFFECTS.slipperyPuddle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local back = _flat(vehicle.PrimaryPart.CFrame.LookVector)
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 1.5, 0) - (back.Magnitude > 0 and back.Unit * 5 or Vector3.zero)
	local isWater = cfg.effectKey ~= "slipperyPuddle"
	local size = (cfg.radius or 4) * 2
	local puddle = _dropPart(pos, Vector3.new(0.3, size, size),
		isWater and Color3.fromRGB(70, 150, 255) or Color3.fromRGB(220, 140, 50), "Slippery", cfg.duration + 6)
	puddle.Shape = Enum.PartType.Cylinder               -- a round puddle lying flat
	puddle.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	puddle.Material = Enum.Material.Glass
	puddle.Transparency = 0.25
	_onDropTouched(puddle, activator, function(p, v)
		if not _hurts(p) then return end
		EffectFx.play("slipped", p, 1.5, activator)
		_applySpeedMult(v, 0.7, 1.5, "slippery")
		RemoteEvents.ScreenEffect:FireClient(p, "slippery", {})
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
	_impulse(vehicle, vehicle.PrimaryPart.CFrame.LookVector, 90)
	_applySpeedMult(vehicle, 2.0, cfg.duration, "sodaBlast")
end

EFFECTS.flagAura = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(_getVehicle(activator), 1.20, cfg.duration, "flagAura")
	local ally = _nearestEnemy(activator, 40)
	if ally then
		EffectFx.play(cfg.effectKey, ally, cfg.duration, activator)
		_applySpeedMult(_getVehicle(ally), 1.20, cfg.duration, "flagAura")
		RemoteEvents.ScreenEffect:FireClient(ally, "flagBuff", { duration = cfg.duration })
	end
end

EFFECTS.cactusObstacle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local back = _flat(vehicle.PrimaryPart.CFrame.LookVector)
	local pos = vehicle.PrimaryPart.Position + Vector3.new(0, 0.5, 0) - (back.Magnitude > 0 and back.Unit * 6 or Vector3.zero)
	local cactus = _dropPart(pos, Vector3.new(1.5, 3, 1.5),
		Color3.fromRGB(30, 130, 40), "Obstacle_Drop", cfg.duration + 8)
	cactus.Material = Enum.Material.Grass
	-- RacingManager connects every part tagged Obstacle, including new ones
	CollectionService:AddTag(cactus, "Obstacle")
end

EFFECTS.umbrellaBlock = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "shield", cfg.duration)   -- blocks the next hit
end

EFFECTS.umbrellaSail = function(activator, _, cfg)
	-- Side-wind speed bonus: lateral force plus a little speed
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyBodyForce(vehicle, vehicle.PrimaryPart.CFrame.RightVector * 600, cfg.duration, "UmbrellaSail")
	_applySpeedMult(vehicle, 1.15, cfg.duration, "umbrellaSail")
end

EFFECTS.parachute = function(activator, _, cfg)
	local vehicle = _lift(activator, cfg)
	_applySpeedMult(vehicle, 0.5, cfg.duration, "parachute")   -- drift slowly
end

EFFECTS.magnetPull = function(activator, target, cfg)
	-- Pull the nearest racer back toward you and slow them while held
	if not _hurts(target) then return end
	local me, them = _getVehicle(activator), _getVehicle(target)
	if not me or not them or not me.PrimaryPart or not them.PrimaryPart then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_impulse(them, _flat(me.PrimaryPart.Position - them.PrimaryPart.Position), 35)
	_applySpeedMult(them, 0.8, cfg.duration, "magnetPull")
	RemoteEvents.ScreenEffect:FireClient(target, "magnetPull", { duration = cfg.duration })
end

-- ── ENGINE ────────────────────────────────────────────────────────────────────

EFFECTS.digMode = function(activator, _, cfg)
	-- Drill: mud and off-track slow zones have no effect while active
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "dig", cfg.duration)
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
	_applySpeedMult(vehicle, 2.0, cfg.duration, "redline")
	_applyTurnMult(vehicle, 0, cfg.duration, "redline")
	RemoteEvents.ScreenEffect:FireClient(activator, "redlineActive", { duration = cfg.duration })
end

EFFECTS.steamCloud = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local back = _flat(vehicle.PrimaryPart.CFrame.LookVector)
	local pos = vehicle.PrimaryPart.Position - (back.Magnitude > 0 and back.Unit * 8 or Vector3.zero)
	local cloud = _dropPart(pos, Vector3.new(10, 6, 10),
		Color3.fromRGB(235, 235, 235), "SteamCloud", cfg.duration)
	cloud.Transparency = 1          -- the cloud itself is particles
	cloud.CanCollide   = false
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 245))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1.2, 2)
	steam.Rate = 40
	steam.Speed = NumberRange.new(1, 3)
	steam.SpreadAngle = Vector2.new(180, 180)
	steam.Parent = cloud
	_onDropTouched(cloud, activator, function(p)
		if not _hurts(p) then return end
		EffectFx.play("steamed", p, math.min(3, cfg.duration), activator)
		RemoteEvents.ScreenEffect:FireClient(p, "steamBlind", { duration = math.min(3, cfg.duration) })
	end)
end

EFFECTS.noodleSnare = function(activator, target, cfg)
	if not _hurts(target) then return end
	EffectFx.play(cfg.effectKey, target, cfg.duration, activator)
	_applySpeedMult(_getVehicle(target), 0.70, cfg.duration, "noodleSnare")
	RemoteEvents.ScreenEffect:FireClient(target, "noodleSnare", { duration = cfg.duration })
end

EFFECTS.rocketBurst = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, 3.0, cfg.duration, "rocketBurst")
	local primary = vehicle and vehicle.PrimaryPart
	if primary then _impulse(vehicle, primary.CFrame.LookVector, 60) end
end

EFFECTS.windBlast = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local origin  = vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.Position or Vector3.zero
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 12)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			EffectFx.play("blown", target, nil, activator)
			_impulse(tv, _flat(tv.PrimaryPart.Position - origin), 55)
			RemoteEvents.ScreenEffect:FireClient(target, "windBlast", {})
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
				_impulse(tv, side, 45)
				_applySpeedMult(tv, 0.85, cfg.duration, "gustBlast")
				RemoteEvents.ScreenEffect:FireClient(target, "windBlast", {})
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
	_impulse(vehicle, rotated, 70)
	_applySpeedMult(vehicle, 2.0, cfg.duration, "spinBurst")
end

EFFECTS.windRide = function(activator, _, cfg)
	local mult = (_biome == "SKY") and 1.6 or ((_biome == "OCEAN") and 1.4 or 1.2)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(_getVehicle(activator), mult, cfg.duration, "windRide")
end

-- ── BODY ──────────────────────────────────────────────────────────────────────

EFFECTS.disguise = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "disguised", cfg.duration)
end

EFFECTS.raftGlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyTurnMult(vehicle, 3, cfg.duration, "raftGlide")   -- slippery but steerable
	_applySpeedMult(vehicle, 1.15, cfg.duration, "raftGlide")
end

EFFECTS.logObstacle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	EffectFx.play("dropTrap", activator, nil)
	local back = _flat(vehicle.PrimaryPart.CFrame.LookVector)
	local pos = vehicle.PrimaryPart.Position + Vector3.new(0, 0.5, 0) - (back.Magnitude > 0 and back.Unit * 7 or Vector3.zero)
	local log = _dropPart(pos, Vector3.new(4, 1, 1),
		Color3.fromRGB(100, 60, 30), "Obstacle_Log", 12)
	log.Shape    = Enum.PartType.Cylinder
	log.Material = Enum.Material.Wood
	log.Anchored = false
	log.CFrame   = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi, 0)
	CollectionService:AddTag(log, "Obstacle")
end

EFFECTS.sofaFortress = function(activator, _, cfg)
	-- Red Sofa: full stop, but nothing can hurt you meanwhile
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	RaceEffects.grant(activator, "invincible", cfg.duration)
	_applySpeedMult(_getVehicle(activator), 0, cfg.duration, "sofaFortress")
end

EFFECTS.cartRam = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_impulse(vehicle, primary.CFrame.LookVector, 50)
	for _, target in ipairs(_allInRadius(activator, 6)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			EffectFx.play("rammed", target, nil, activator)
			_impulse(tv, _flat(tv.PrimaryPart.Position - primary.Position), 40)
			RemoteEvents.ScreenEffect:FireClient(target, "collision", {})
		end
	end
end

EFFECTS.barrelRoll = function(activator, _, cfg)
	-- Barrel: sideways roll that knocks adjacent racers aside
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(vehicle, 1.1, cfg.duration, "barrelRoll")
	for _, target in ipairs(_allInRadius(activator, 8)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart and _hurts(target) then
			local right = _flat(primary.CFrame.RightVector)
			local to = _flat(tv.PrimaryPart.Position - primary.Position)
			local dir = (right:Dot(to) >= 0) and right or -right
			EffectFx.play("rammed", target, nil, activator)
			_impulse(tv, dir, 45)
			RemoteEvents.ScreenEffect:FireClient(target, "collision", {})
		end
	end
end

EFFECTS.lockdown = function(activator, _, cfg)
	-- Suitcase: brief stop, then the next hit is absorbed
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applySpeedMult(_getVehicle(activator), 0.3, 0.5, "lockdown")
	RaceEffects.grant(activator, "shield", cfg.duration)
end

EFFECTS.microFreeze = function(activator, _, cfg)
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, target in ipairs(_allInRadius(activator, cfg.radius or 12)) do
		if _hurts(target) then
			EffectFx.play("frozen", target, cfg.duration, activator)
			_applySpeedMult(_getVehicle(target), 0, cfg.duration, "microFreeze")
			RemoteEvents.ScreenEffect:FireClient(target, "microFreeze", { duration = cfg.duration })
		end
	end
end

EFFECTS.bathSplash = function(activator, target, cfg)
	EffectFx.play(cfg.effectKey, activator, nil)
	for _, t in ipairs(_allInRadius(activator, cfg.radius or 8)) do
		if _hurts(t) then
			EffectFx.play("splashed", t, cfg.duration * 0.5, activator)
			RemoteEvents.ScreenEffect:FireClient(t, "bathSplash", { duration = cfg.duration })
			_applySpeedMult(_getVehicle(t), 0.80, cfg.duration * 0.5, "bathSplash")
		end
	end
end

EFFECTS.backpackBoost = function(activator, _, cfg)
	-- Backpack: the client refills its boost gauge
	EffectFx.play(cfg.effectKey, activator, nil)
	RemoteEvents.ScreenEffect:FireClient(activator, "boostRecharge", {})
end

EFFECTS.skateSlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	EffectFx.play(cfg.effectKey, activator, cfg.duration)
	_applyTurnMult(vehicle, 4, cfg.duration, "skateSlide")   -- very twitchy
	_applySpeedMult(vehicle, 1.25, cfg.duration, "skateSlide")
end

EFFECTS.lifeFloat = function(activator, _, cfg) _lift(activator, cfg) end
EFFECTS.kiteLift  = EFFECTS.lifeFloat
EFFECTS.kiteGlide = function(activator, _, cfg)
	local vehicle = _lift(activator, cfg)
	_applySpeedMult(vehicle, 1.3, cfg.duration, "kiteGlide")
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

	-- Set cooldown before dispatching (prevents double-fire)
	_cooldowns[userId][itemName] = tick() + abilCfg.cooldown

	-- Dispatch effect
	local effectFn = EFFECTS[abilCfg.effectKey]
	if effectFn then
		task.spawn(effectFn, player, target, abilCfg)
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
RemoteEvents.RequestAbility.OnServerInvoke = function(player, itemName)
	local result = _handleAbilityRequest(player, itemName)
	Telemetry.record("ability", { userId = player.UserId, item = itemName, result = result })
	return result
end
