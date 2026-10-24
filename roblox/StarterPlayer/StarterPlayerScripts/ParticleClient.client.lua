-- ParticleClient.client.lua
-- Boost trail, mud splatter, water splash, finish confetti.
-- (Ability / passive effects on cars: EffectFx.client.lua.)
-- Resolves: Issue #50

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

-- ─── Particle factory helpers ─────────────────────────────────────────────────

local function _makeEmitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		pcall(function() e[k] = v end)
	end
	e.Parent = parent
	return e
end

local function _burst(part, props, count, duration)
	local e = _makeEmitter(part, props)
	e:Emit(count)
	task.delay(duration or 0.5, function() e:Destroy() end)
end

-- ─── Boost trail ──────────────────────────────────────────────────────────────

local _boostTrail  = nil
local _boostAttach = nil

local function _attachBoostTrail(vehicle)
	if _boostTrail then _boostTrail:Destroy() end
	if not vehicle or not vehicle.PrimaryPart then return end

	_boostAttach = Instance.new("Attachment")
	_boostAttach.Position = Vector3.new(0, 0, 2)   -- rear of vehicle
	_boostAttach.Parent   = vehicle.PrimaryPart

	local rear = Instance.new("Attachment")
	rear.Position = Vector3.new(0, 0, -2)
	rear.Parent   = vehicle.PrimaryPart

	_boostTrail = Instance.new("Trail")
	_boostTrail.Attachment0 = _boostAttach
	_boostTrail.Attachment1 = rear
	_boostTrail.Lifetime    = 0.4
	_boostTrail.MinLength   = 0
	_boostTrail.FaceCamera  = true
	_boostTrail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	_boostTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	_boostTrail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	_boostTrail.Enabled = false
	_boostTrail.Parent  = vehicle.PrimaryPart
end

local function _setBoostTrail(on)
	if _boostTrail then _boostTrail.Enabled = on end
end

-- ─── Speed particle (always-on when moving fast) ──────────────────────────────

local _speedEmitter = nil
local _vehicle      = nil

local function _updateSpeedParticles()
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local speed = _vehicle.PrimaryPart.AssemblyLinearVelocity.Magnitude
	if _speedEmitter then
		_speedEmitter.Rate = math.clamp((speed - 30) * 0.5, 0, 8)
	end
end

local function _attachSpeedEmitter(vehicle)
	if _speedEmitter then _speedEmitter:Destroy() end
	if not vehicle or not vehicle.PrimaryPart then return end

	_speedEmitter = _makeEmitter(vehicle.PrimaryPart, {
		Color = ColorSequence.new(Color3.fromRGB(180, 220, 255)),
		LightEmission  = 0.3,
		LightInfluence = 0.5,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.2, 0.4),
		Speed          = NumberRange.new(3, 6),
		SpreadAngle    = Vector2.new(60, 60),
		Rate           = 0,
		RotSpeed       = NumberRange.new(-45, 45),
		Rotation       = NumberRange.new(0, 360),
	})
end

-- ─── Mud splatter ────────────────────────────────────────────────────────────

local _mudEmitter = nil

local function _startMudSplatter(vehicle)
	if _mudEmitter then _mudEmitter:Destroy() end
	if not vehicle or not vehicle.PrimaryPart then return end

	_mudEmitter = _makeEmitter(vehicle.PrimaryPart, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 70, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 40, 10)),
		}),
		LightEmission  = 0,
		LightInfluence = 1,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.4, 0.8),
		Speed          = NumberRange.new(5, 12),
		SpreadAngle    = Vector2.new(80, 80),
		Rate           = 15,
		Rotation       = NumberRange.new(0, 360),
		RotSpeed       = NumberRange.new(-90, 90),
	})
end

local function _stopMudSplatter()
	if _mudEmitter then
		_mudEmitter:Destroy()
		_mudEmitter = nil
	end
end

-- ─── Water splash ────────────────────────────────────────────────────────────

local function _burstWaterSplash(part)
	_burst(part, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 230, 255)),
		}),
		LightEmission  = 0.2,
		LightInfluence = 0.5,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.5, 1.0),
		Speed          = NumberRange.new(8, 20),
		SpreadAngle    = Vector2.new(90, 90),
		Rotation       = NumberRange.new(0, 360),
	}, 30, 1.0)
end

-- ─── Collision sparks ────────────────────────────────────────────────────────

local function _burstCollisionSparks(part)
	_burst(part, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 10)),
		}),
		LightEmission  = 0.8,
		LightInfluence = 0.2,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.3, 0.7),
		Speed          = NumberRange.new(15, 35),
		SpreadAngle    = Vector2.new(180, 180),
	}, 40, 0.8)
end

-- ─── Finish confetti ─────────────────────────────────────────────────────────

local function _burstFinishConfetti()
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local colors = {
		Color3.fromRGB(255, 60, 60),
		Color3.fromRGB(60, 200, 255),
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(80, 255, 80),
		Color3.fromRGB(200, 80, 255),
	}

	for i, colour in ipairs(colors) do
		task.delay(i * 0.08, function()
			_burst(hrp, {
				Color          = ColorSequence.new(colour),
				LightEmission  = 0.1,
				LightInfluence = 0.8,
				Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.08) }),
				Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime       = NumberRange.new(1.5, 3.0),
				Speed          = NumberRange.new(10, 25),
				SpreadAngle    = Vector2.new(120, 120),
				Rotation       = NumberRange.new(0, 360),
				RotSpeed       = NumberRange.new(-180, 180),
			}, 25, 3.5)
		end)
	end
end

-- ─── Boost activation flash ───────────────────────────────────────────────────

local function _burstBoostFlash(vehicle)
	if not vehicle or not vehicle.PrimaryPart then return end
	_burst(vehicle.PrimaryPart, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		LightEmission  = 0.9,
		LightInfluence = 0.1,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.3, 0.6),
		Speed          = NumberRange.new(20, 40),
		SpreadAngle    = Vector2.new(180, 180),
	}, 50, 0.7)
	_setBoostTrail(true)
end

-- ─── Updraft lift ────────────────────────────────────────────────────────────

local _updraftEmitter = nil

local function _startUpdraftParticles(vehicle)
	if _updraftEmitter then _updraftEmitter:Destroy() end
	if not vehicle or not vehicle.PrimaryPart then return end

	_updraftEmitter = _makeEmitter(vehicle.PrimaryPart, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		LightEmission  = 0.4,
		Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) }),
		Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime       = NumberRange.new(0.5, 1.0),
		Speed          = NumberRange.new(5, 15),
		SpreadAngle    = Vector2.new(20, 20),
		Rate           = 20,
		EmissionDirection = Enum.NormalId.Top,
	})
end

local function _stopUpdraftParticles()
	if _updraftEmitter then
		_updraftEmitter:Destroy()
		_updraftEmitter = nil
	end
end

-- ─── ScreenEffect → particle mapping ────────────────────────────────────────

RemoteEvents.ScreenEffect.OnClientEvent:Connect(function(effectName, params)
	local vehicle = _vehicle

	if effectName == "boostStart" or effectName == "boostPad" then
		_burstBoostFlash(vehicle)
		task.delay(2.5, function() _setBoostTrail(false) end)

	elseif effectName == "collision" then
		if vehicle and vehicle.PrimaryPart then
			_burstCollisionSparks(vehicle.PrimaryPart)
		end

	elseif effectName == "mudWarning" then
		_startMudSplatter(vehicle)

	elseif effectName == "updraftWarning" then
		_startUpdraftParticles(vehicle)
		-- the lift lasts Constants.UPDRAFT.DURATION (no exit message comes)
		local emitter = _updraftEmitter
		task.delay(require(ReplicatedStorage.Shared.Constants).UPDRAFT.DURATION, function()
			if _updraftEmitter == emitter then _stopUpdraftParticles() end
		end)

	elseif effectName == "respawn" then
		_stopMudSplatter()
		_stopUpdraftParticles()
		_setBoostTrail(false)

	elseif effectName == "bubblePop" then
		if vehicle and vehicle.PrimaryPart then
			_burst(vehicle.PrimaryPart, {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 220, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 240, 255)),
				}),
				LightEmission  = 0.3,
				Size           = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
				Transparency   = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime       = NumberRange.new(0.4, 0.8),
				Speed          = NumberRange.new(10, 20),
				SpreadAngle    = Vector2.new(180, 180),
			}, 20, 1.0)
		end
	end
end)

-- Ability and passive effects on cars: EffectFx.client.lua.

-- ─── RaceFinished → confetti ─────────────────────────────────────────────────

RemoteEvents.RaceFinished.OnClientEvent:Connect(function(finishOrder)
	-- Only confetti if local player finished in top 3
	for rank, entry in ipairs(finishOrder) do
		if entry.userId == LocalPlayer.UserId and rank <= 3 then
			_burstFinishConfetti()
			break
		end
	end
end)

-- ─── Vehicle tracking ─────────────────────────────────────────────────────────

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, vehicleModel)
	if userId ~= LocalPlayer.UserId then return end
	_vehicle = vehicleModel
	_attachBoostTrail(vehicleModel)
	_attachSpeedEmitter(vehicleModel)
end)

-- ─── Speed particle update loop ──────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	_updateSpeedParticles()
	-- Stop mud/updraft if vehicle left zone (handled via ScreenEffect)
end)

-- ─── Phase reset ─────────────────────────────────────────────────────────────

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	local Constants = require(ReplicatedStorage.Shared.Constants)
	if phase ~= Constants.PHASES.RACING then
		_stopMudSplatter()
		_stopUpdraftParticles()
		_setBoostTrail(false)
		_vehicle = nil
	end
end)
