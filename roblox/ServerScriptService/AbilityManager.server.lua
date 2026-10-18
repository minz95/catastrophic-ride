-- AbilityManager.server.lua
-- Server-authoritative ability activation, cooldown enforcement,
-- and physics effect dispatch for all 37 item abilities.
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

-- ─── Per-player cooldown store ────────────────────────────────────────────────
-- _cooldowns[userId][itemName] = expireTick

local _cooldowns   = {}
local _activeDurations = {}   -- [userId][itemName] = expireTick (effect is live)

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function _getVehicle(player)
	local pdata = SessionManager.getData(player)
	return pdata and pdata.vehicleModel
end

local function _getSeat(vehicle)
	return vehicle and vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
end

local function _applySpeedMult(vehicle, mult, duration)
	local seat = _getSeat(vehicle)
	if not seat then return end
	local old = seat.MaxSpeed
	seat.MaxSpeed = old * mult
	task.delay(duration, function()
		if seat and seat.Parent then seat.MaxSpeed = old end
	end)
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
	if not primary then return end
	local bv = Instance.new("BodyVelocity")
	bv.Velocity  = direction * magnitude
	bv.MaxForce  = Vector3.new(1e5, 1e4, 1e5)
	bv.Parent    = primary
	Debris:AddItem(bv, 0.3)
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

local function _nearestEnemy(player, radius)
	local pdata   = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return nil end
	local pos     = vehicle.PrimaryPart.Position

	local best, bestDist = nil, radius or math.huge
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player then continue end
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
		if other == player then continue end
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

-- ─── Effect dispatcher ────────────────────────────────────────────────────────

local EFFECTS = {}

-- ── SPECIAL ──────────────────────────────────────────────────────────────────

EFFECTS.steerDisable = function(activator, target, cfg)
	if not target then return end
	local tv = _getVehicle(target)
	local seat = _getSeat(tv)
	if not seat then return end
	local old = seat.TurnSpeed
	seat.TurnSpeed = 0
	RemoteEvents.ScreenEffect:FireClient(target, "steerDisable", { duration = cfg.duration })
	task.delay(cfg.duration, function()
		if seat and seat.Parent then seat.TurnSpeed = old end
	end)
end

EFFECTS.slipperyPuddle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 1.5, 4)
	local puddle = _dropPart(pos, Vector3.new(8, 0.3, 8),
		Color3.fromRGB(220, 140, 50), "Slippery", cfg.duration)
	puddle.Touched:Connect(function(hit)
		local v = hit:FindFirstAncestorWhichIsA("Model")
		if not v then return end
		for _, p in ipairs(Players:GetPlayers()) do
			if p == activator then continue end
			local pd = SessionManager.getData(p)
			if pd and pd.vehicleModel == v then
				_applySpeedMult(v, 0.7, 1.5)
				RemoteEvents.ScreenEffect:FireClient(p, "slippery", {})
			end
		end
	end)
end

EFFECTS.emergencyFloat = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 2500, 0), cfg.duration, "EmergencyFloat")
	RemoteEvents.AbilityActivated:FireAllClients(activator.UserId, "Rubber Duck", {})
end

EFFECTS.fullBuoyancy = EFFECTS.emergencyFloat   -- OCEAN variant, stronger handled by multiplier

EFFECTS.softLanding = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 3500, 0), cfg.duration, "SoftLanding")
end

EFFECTS.groundBounce = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_impulse(vehicle, Vector3.new(0, 1, 0), 40)
end

EFFECTS.rise = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 2800, 0), cfg.duration, "Rise")
end

EFFECTS.reverseBoost = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local fwd = vehicle.PrimaryPart.CFrame.LookVector
	_impulse(vehicle, fwd, 90)   -- large forward burst
	_applySpeedMult(vehicle, 2.0, cfg.duration)
end

EFFECTS.flagAura = function(activator, _, cfg)
	_applySpeedMult(_getVehicle(activator), 1.20, cfg.duration)
	local ally = _nearestEnemy(activator, 40)
	if ally then
		_applySpeedMult(_getVehicle(ally), 1.20, cfg.duration)
		RemoteEvents.ScreenEffect:FireClient(ally, "flagBuff", { duration = cfg.duration })
	end
	RemoteEvents.AbilityActivated:FireAllClients(activator.UserId, "Racing Flag", {})
end

-- EFFECTS.soundBlast removed in SPECIAL overhaul (was only used by Boombox)

EFFECTS.cactusObstacle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 0.5, 6)
	local cactus = _dropPart(pos, Vector3.new(1.5, 3, 1.5),
		Color3.fromRGB(30, 130, 40), "Obstacle_Drop", cfg.duration + 8)
	game:GetService("CollectionService"):AddTag(cactus, "Obstacle")
end

EFFECTS.leafPile = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 1.5, 5)
	local pile = _dropPart(pos, Vector3.new(6, 0.4, 6),
		Color3.fromRGB(120, 180, 40), "Slippery", cfg.duration + 5)
	pile.Touched:Connect(function(hit)
		local v = hit:FindFirstAncestorWhichIsA("Model")
		if not v then return end
		for _, p in ipairs(Players:GetPlayers()) do
			local pd = SessionManager.getData(p)
			if pd and pd.vehicleModel == v and p ~= activator then
				_applySpeedMult(v, 0.60, cfg.duration)
				RemoteEvents.ScreenEffect:FireClient(p, "leafPile", {})
			end
		end
	end)
end

EFFECTS.leafPileLarge = EFFECTS.leafPile   -- biome variant; radius handled by override

EFFECTS.steerHinder = function(activator, target, cfg)
	if not target then return end
	local seat = _getSeat(_getVehicle(target))
	if not seat then return end
	local old = seat.TurnSpeed
	seat.TurnSpeed = old * 0.10
	RemoteEvents.ScreenEffect:FireClient(target, "scarfTangle", { duration = cfg.duration })
	task.delay(cfg.duration, function()
		if seat and seat.Parent then seat.TurnSpeed = old end
	end)
end

EFFECTS.umbrellaBlock = function(activator, _, cfg)
	local pdata = SessionManager.getData(activator)
	if pdata then pdata._bubbleShield = true end   -- reuse shield flag
	RemoteEvents.AbilityActivated:FireAllClients(activator.UserId, "Umbrella", {})
	task.delay(cfg.duration, function()
		if pdata then pdata._bubbleShield = false end
	end)
end

EFFECTS.umbrellaSail = function(activator, _, cfg)
	-- Side-wind speed bonus: read vehicle facing, apply lateral force
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local right = vehicle.PrimaryPart.CFrame.RightVector
	_applyBodyForce(vehicle, right * 600, cfg.duration, "UmbrellaSail")
end

EFFECTS.parachute = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 4000, 0), cfg.duration, "Parachute")
	_applySpeedMult(vehicle, 0.5, cfg.duration)   -- drift down slowly
end

-- EFFECTS.bubbleShield removed in SPECIAL overhaul (was only used by Bubble Wrap;
-- Umbrella's umbrellaBlock still writes pdata._bubbleShield for legacy reasons)

-- ── ENGINE ────────────────────────────────────────────────────────────────────

EFFECTS.digMode = function(activator, _, cfg)
	-- Immunity flagged server-side; MudZone handler checks this flag
	local pdata = SessionManager.getData(activator)
	if pdata then pdata._digMode = true end
	task.delay(cfg.duration, function()
		if pdata then pdata._digMode = false end
	end)
	RemoteEvents.AbilityActivated:FireAllClients(activator.UserId, "Shovel", {})
end

EFFECTS.itemAttract = function(activator, _, cfg)
	-- Pulls nearby unclaimed Farming items toward the player
	local pdata   = SessionManager.getData(activator)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos     = vehicle.PrimaryPart.Position

	local FarmingManager = require(ServerScriptService.FarmingManager)
	for id, item in pairs(FarmingManager and FarmingManager._items or {}) do
		if not item.taken and item.part then
			local d = (item.part.Position - pos).Magnitude
			if d < 20 then
				-- Tween item part toward player
				local bv = Instance.new("BodyVelocity")
				bv.Velocity  = (pos - item.part.Position).Unit * 25
				bv.MaxForce  = Vector3.new(1e4, 1e4, 1e4)
				bv.Parent    = item.part
				Debris:AddItem(bv, 1.2)
			end
		end
	end
end

EFFECTS.overclock = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applySpeedMult(vehicle, 1.5, cfg.duration)
	task.delay(cfg.duration, function()   -- stall
		_applySpeedMult(vehicle, 0.2, 1.0)
	end)
end

EFFECTS.hover = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 3200, 0), cfg.duration, "HoverForce")
end

EFFECTS.redline = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local seat    = _getSeat(vehicle)
	if not seat then return end
	local old = seat.MaxSpeed
	seat.MaxSpeed = 9999   -- uncapped
	-- Disable steering on client side via ScreenEffect flag
	RemoteEvents.ScreenEffect:FireClient(activator, "redlineActive",
		{ duration = cfg.duration })
	task.delay(cfg.duration, function()
		if seat and seat.Parent then seat.MaxSpeed = old end
	end)
end

EFFECTS.steamCloud = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 0, 8)
	local cloud = _dropPart(pos, Vector3.new(10, 6, 10),
		Color3.fromRGB(220, 220, 220), "SteamCloud", cfg.duration)
	cloud.Transparency = 0.6
	cloud.CanCollide   = false
	cloud.Touched:Connect(function(hit)
		local v = hit:FindFirstAncestorWhichIsA("Model")
		if not v then return end
		for _, p in ipairs(Players:GetPlayers()) do
			local pd = SessionManager.getData(p)
			if pd and pd.vehicleModel == v and p ~= activator then
				RemoteEvents.ScreenEffect:FireClient(p, "steamBlind",
					{ duration = math.min(3, cfg.duration) })
			end
		end
	end)
end

EFFECTS.noodleSnare = function(activator, target, cfg)
	if not target then return end
	_applySpeedMult(_getVehicle(target), 0.70, cfg.duration)
	RemoteEvents.ScreenEffect:FireClient(target, "noodleSnare",
		{ duration = cfg.duration })
end

EFFECTS.rocketBurst = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applySpeedMult(vehicle, 3.0, cfg.duration)
	local primary = vehicle and vehicle.PrimaryPart
	if primary then
		local fwd = primary.CFrame.LookVector
		_impulse(vehicle, fwd, 60)
	end
end

EFFECTS.windBlast = function(activator, _, cfg)
	local targets = _allInRadius(activator, cfg.radius or 12)
	local vehicle = _getVehicle(activator)
	local origin  = vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.Position
		or Vector3.new(0, 0, 0)
	for _, target in ipairs(targets) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart then
			local dir = (tv.PrimaryPart.Position - origin).Unit
			_impulse(tv, dir, 55)
			RemoteEvents.ScreenEffect:FireClient(target, "windBlast", {})
		end
	end
end

EFFECTS.waterPuddle = EFFECTS.slipperyPuddle   -- reuse with different colour (server-side only visual)
EFFECTS.waterPuddleLarge = EFFECTS.slipperyPuddle

EFFECTS.spinBurst = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	local fwd = primary.CFrame.LookVector
	-- Random slight direction offset (the "chaos")
	local angle = (math.random() - 0.5) * math.pi * 0.4
	local rotated = Vector3.new(
		fwd.X * math.cos(angle) - fwd.Z * math.sin(angle),
		fwd.Y,
		fwd.X * math.sin(angle) + fwd.Z * math.cos(angle)
	)
	_impulse(vehicle, rotated, 70)
	_applySpeedMult(vehicle, 2.0, cfg.duration)
end

EFFECTS.windRide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local mult    = (_biome == "SKY") and 1.6 or ((_biome == "OCEAN") and 1.4 or 1.2)
	_applySpeedMult(vehicle, mult, cfg.duration)
end

-- ── BODY ──────────────────────────────────────────────────────────────────────

EFFECTS.disguise = function(activator, _, cfg)
	local pdata = SessionManager.getData(activator)
	if pdata then pdata._disguised = true end
	RemoteEvents.AbilityActivated:FireAllClients(activator.UserId, "Cardboard Box", {})
	task.delay(cfg.duration, function()
		if pdata then pdata._disguised = false end
	end)
end

EFFECTS.raftGlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local seat    = _getSeat(vehicle)
	if not seat then return end
	local old = seat.TurnSpeed
	seat.TurnSpeed = old * 3   -- slippery but steerable
	_applySpeedMult(vehicle, 1.15, cfg.duration)
	task.delay(cfg.duration, function()
		if seat and seat.Parent then seat.TurnSpeed = old end
	end)
end

EFFECTS.logObstacle = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 0.5, 7)
	local log = _dropPart(pos, Vector3.new(4, 1, 1),
		Color3.fromRGB(100, 60, 30), "Obstacle_Log", 12)
	log.Anchored = false
	log.CFrame   = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi, 0)
end

EFFECTS.sofaFortress = function(activator, _, cfg)
	local pdata = SessionManager.getData(activator)
	if pdata then pdata._invincible = true end
	local seat = _getSeat(_getVehicle(activator))
	if seat then
		local old = seat.MaxSpeed
		seat.MaxSpeed = 0
		task.delay(cfg.duration, function()
			if seat and seat.Parent then seat.MaxSpeed = old end
			if pdata then pdata._invincible = false end
		end)
	end
end

EFFECTS.cartRam = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return end
	local fwd = primary.CFrame.LookVector
	_impulse(vehicle, fwd, 50)
	-- Push anyone in front
	for _, target in ipairs(_allInRadius(activator, 6)) do
		local tv = _getVehicle(target)
		if tv and tv.PrimaryPart then
			local dir = (tv.PrimaryPart.Position - primary.Position).Unit
			_impulse(tv, dir, 40)
			RemoteEvents.ScreenEffect:FireClient(target, "collision", {})
		end
	end
end

EFFECTS.microFreeze = function(activator, _, cfg)
	local targets = _allInRadius(activator, cfg.radius or 12)
	for _, target in ipairs(targets) do
		local tv = _getVehicle(target)
		local seat = _getSeat(tv)
		if seat then
			local old = seat.MaxSpeed
			seat.MaxSpeed = 0
			RemoteEvents.ScreenEffect:FireClient(target, "microFreeze", {})
			task.delay(cfg.duration, function()
				if seat and seat.Parent then seat.MaxSpeed = old end
			end)
		end
	end
end

EFFECTS.bathSplash = function(activator, target, cfg)
	local targets = _allInRadius(activator, cfg.radius or 8)
	for _, t in ipairs(targets) do
		RemoteEvents.ScreenEffect:FireClient(t, "bathSplash", { duration = cfg.duration })
		_applySpeedMult(_getVehicle(t), 0.80, cfg.duration * 0.5)
	end
end

EFFECTS.backpackBoost = function(activator, _, cfg)
	local phase = GameManager.getPhase()
	if phase == Constants.PHASES.FARMING then
		-- +2 inventory slots temporarily
		local pdata = SessionManager.getData(activator)
		if pdata then pdata._extraSlots = 2 end
		task.delay(cfg.duration, function()
			if pdata then pdata._extraSlots = nil end
		end)
	else
		-- Free boost charge
		RemoteEvents.ScreenEffect:FireClient(activator, "boostRecharge", {})
	end
end

EFFECTS.hackControls = function(activator, target, cfg)
	if not target then return end
	RemoteEvents.ScreenEffect:FireClient(target, "hackControls", { duration = cfg.duration })
end

EFFECTS.stickTrap = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	if not vehicle or not vehicle.PrimaryPart then return end
	local pos = vehicle.PrimaryPart.Position - Vector3.new(0, 0.8, 5)
	local stick = _dropPart(pos, Vector3.new(3, 0.4, 0.4),
		Color3.fromRGB(120, 80, 40), "Obstacle_Stick", 10)
end

EFFECTS.skateSlide = function(activator, _, cfg)
	local seat = _getSeat(_getVehicle(activator))
	if not seat then return end
	local oldTurn = seat.TurnSpeed
	seat.TurnSpeed = oldTurn * 4   -- very twitchy
	_applySpeedMult(_getVehicle(activator), 1.25, cfg.duration)
	task.delay(cfg.duration, function()
		if seat and seat.Parent then seat.TurnSpeed = oldTurn end
	end)
end

EFFECTS.lifeFloat = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 3800, 0), cfg.duration, "LifeFloat")
end

EFFECTS.kiteLift  = EFFECTS.lifeFloat
EFFECTS.kiteGlide = function(activator, _, cfg)
	local vehicle = _getVehicle(activator)
	_applyBodyForce(vehicle, Vector3.new(0, 5000, 0), cfg.duration, "KiteGlide")
	_applySpeedMult(vehicle, 1.3, cfg.duration)
end

-- ─── RequestAbility handler ───────────────────────────────────────────────────

local _biome = nil
GameManager.onPhaseChanged(function(phase, biome)
	_biome = biome
	if phase ~= Constants.PHASES.RACING then
		_cooldowns        = {}
		_activeDurations  = {}
	end
end)

local function _handleAbilityRequest(player, itemName)
	-- Phase check (Flower is FARMING-only)
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

	-- Check item is actually in player's slot assignments
	local pdata = SessionManager.getData(player)
	if not pdata then return "denied: no data" end

	local itemCfg = ItemConfig[itemName]
	if not itemCfg then return "denied: unknown item" end

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

	-- Broadcast to clients for animation
	local targetIds = target and { target.UserId } or {}
	RemoteEvents.AbilityActivated:FireAllClients(userId, itemName, targetIds)

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
