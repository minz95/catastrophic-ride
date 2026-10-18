-- AbilityAnimator.client.lua
-- 3-layer ability animation system:
--   Layer 1: TweenService vehicle transform (shake, spin, bounce)
--   Layer 2: BillboardGui floating text above vehicle
--   Layer 3: ParticleEmitter per-effect burst (ability-specific colours)
-- Resolves: Issue #59

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

-- ─── State ────────────────────────────────────────────────────────────────────

local _vehicle = nil

-- ─── Layer 1 helpers: vehicle tweens ─────────────────────────────────────────

local function _shakeVehicle(part, intensity, duration)
	if not part then return end
	local original = part.CFrame
	local steps = math.floor(duration / 0.05)
	task.spawn(function()
		for _ = 1, steps do
			local rx = (math.random() - 0.5) * intensity
			local ry = (math.random() - 0.5) * intensity
			local rz = (math.random() - 0.5) * intensity
			part.CFrame = part.CFrame * CFrame.Angles(rx, ry, rz)
			task.wait(0.05)
		end
	end)
end

local function _bounceVehicle(part, height, duration)
	if not part then return end
	TweenService:Create(part, TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = part.CFrame + Vector3.new(0, height, 0)
	}):Play()
	task.delay(duration / 2, function()
		if part and part.Parent then
			TweenService:Create(part, TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = part.CFrame - Vector3.new(0, height, 0)
			}):Play()
		end
	end)
end

local function _spinVehicle(part, duration)
	if not part then return end
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
		CFrame = part.CFrame * CFrame.Angles(0, math.pi * 2, 0)
	}):Play()
end

-- ─── Layer 2: floating text billboard ────────────────────────────────────────

local function _floatText(part, text, colour, duration)
	if not part then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Size          = UDim2.new(0, 120, 0, 40)
	billboard.StudsOffset   = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop   = false
	billboard.ResetOnSpawn  = false
	billboard.Parent        = part

	local label = Instance.new("TextLabel")
	label.Size              = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text              = text
	label.TextColor3        = colour or Color3.fromRGB(255, 220, 60)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3  = Color3.new(0, 0, 0)
	label.TextScaled        = true
	label.Font              = Enum.Font.GothamBold
	label.Parent            = billboard

	-- Float up and fade
	local startOffset = billboard.StudsOffset
	task.spawn(function()
		local t = 0
		while t < duration do
			task.wait(0.05)
			t = t + 0.05
			local frac = t / duration
			billboard.StudsOffset = startOffset + Vector3.new(0, frac * 3, 0)
			label.TextTransparency = frac
			label.TextStrokeTransparency = 0.3 + frac * 0.7
		end
		billboard:Destroy()
	end)
end

-- ─── Layer 3: ability-specific particle burst ─────────────────────────────────

local function _particleBurst(part, colour, count, speed)
	if not part then return end
	local e = Instance.new("ParticleEmitter")
	e.Color         = ColorSequence.new(colour)
	e.LightEmission = 0.5
	e.LightInfluence = 0.5
	e.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime      = NumberRange.new(0.4, 0.8)
	e.Speed         = NumberRange.new(speed * 0.6, speed)
	e.SpreadAngle   = Vector2.new(180, 180)
	e.Rotation      = NumberRange.new(0, 360)
	e.Parent        = part
	e:Emit(count)
	task.delay(1, function() e:Destroy() end)
end

-- ─── Effect lookup table ──────────────────────────────────────────────────────
-- effectKey → { label, colour, layer1, layer2Colour, particleColour, particleCount, particleSpeed }

local EFFECT_ANIMS = {
	-- SPECIAL tier
	speedBoost      = { "BOOST!",    Color3.fromRGB(100, 200, 255), "bounce",  Color3.fromRGB(80, 180, 255),  Color3.fromRGB(100, 200, 255), 30, 25 },
	paperBoost      = { "SPEED!",    Color3.fromRGB(255, 240, 200), "bounce",  Color3.fromRGB(255, 220, 180), Color3.fromRGB(255, 230, 180), 20, 20 },
	leafBoost       = { "LEAF!",     Color3.fromRGB(80, 200, 60),   "bounce",  Color3.fromRGB(60, 180, 40),   Color3.fromRGB(80, 200, 60),   25, 20 },
	flagAura        = { "FLAG!",     Color3.fromRGB(255, 80, 80),   "bounce",  Color3.fromRGB(255, 60, 60),   Color3.fromRGB(255, 100, 80),  20, 15 },
	cactusObstacle  = { "CACTUS!",   Color3.fromRGB(80, 200, 80),   "shake",   Color3.fromRGB(60, 200, 60),   Color3.fromRGB(60, 180, 60),   20, 18 },
	leafPile        = { "LEAF PILE!",Color3.fromRGB(80, 200, 60),   "shake",   Color3.fromRGB(60, 180, 40),   Color3.fromRGB(80, 200, 60),   20, 18 },
	duckFloat       = { "FLOAT!",    Color3.fromRGB(255, 240, 60),  "bounce",  Color3.fromRGB(255, 230, 40),  Color3.fromRGB(255, 240, 60),  20, 15 },
	balloonLift     = { "LIFT!",     Color3.fromRGB(200, 100, 255), "bounce",  Color3.fromRGB(180, 80, 255),  Color3.fromRGB(200, 100, 255), 25, 18 },
	sodaBoost       = { "SODA!",     Color3.fromRGB(60, 200, 255),  "spin",    Color3.fromRGB(40, 180, 255),  Color3.fromRGB(60, 200, 255),  40, 35 },
	-- ENGINE tier
	overclock       = { "OVERCLOCK!",Color3.fromRGB(255, 160, 40),  "shake",   Color3.fromRGB(255, 140, 20),  Color3.fromRGB(255, 160, 40),  30, 25 },
	hover           = { "HOVER!",    Color3.fromRGB(100, 200, 255), "bounce",  Color3.fromRGB(80, 180, 255),  Color3.fromRGB(100, 200, 255), 20, 15 },
	redline         = { "REDLINE!",  Color3.fromRGB(255, 60, 60),   "shake",   Color3.fromRGB(255, 40, 40),   Color3.fromRGB(255, 60, 60),   35, 30 },
	windBlast       = { "WIND!",     Color3.fromRGB(180, 220, 255), "spin",    Color3.fromRGB(160, 210, 255), Color3.fromRGB(180, 220, 255), 25, 28 },
	steamCloud      = { "STEAM!",    Color3.fromRGB(200, 200, 200), "shake",   Color3.fromRGB(180, 180, 180), Color3.fromRGB(200, 200, 200), 20, 12 },
	rocketBurst     = { "ROCKET!",   Color3.fromRGB(255, 120, 40),  "spin",    Color3.fromRGB(255, 100, 20),  Color3.fromRGB(255, 120, 40),  40, 40 },
	noodleSnare     = { "SLURP!",    Color3.fromRGB(255, 180, 60),  "shake",   Color3.fromRGB(255, 160, 40),  Color3.fromRGB(255, 180, 60),  25, 18 },
	kettleBoost     = { "KETTLE!",   Color3.fromRGB(255, 200, 100), "bounce",  Color3.fromRGB(255, 180, 80),  Color3.fromRGB(255, 200, 100), 30, 28 },
	-- BODY tier
	sofaFortress    = { "FORTRESS!", Color3.fromRGB(180, 60, 60),   "shake",   Color3.fromRGB(160, 40, 40),   Color3.fromRGB(180, 60, 60),   20, 15 },
	cartRam         = { "RAM!",      Color3.fromRGB(200, 200, 200), "spin",    Color3.fromRGB(180, 180, 180), Color3.fromRGB(200, 200, 200), 25, 30 },
	bathSplash      = { "SPLASH!",   Color3.fromRGB(100, 160, 255), "shake",   Color3.fromRGB(80, 140, 255),  Color3.fromRGB(100, 160, 255), 30, 22 },
	microFreeze     = { "FREEZE!",   Color3.fromRGB(180, 240, 255), "shake",   Color3.fromRGB(160, 230, 255), Color3.fromRGB(180, 240, 255), 25, 15 },
	hackControls    = { "HACKED!",   Color3.fromRGB(60, 255, 60),   "shake",   Color3.fromRGB(40, 255, 40),   Color3.fromRGB(60, 255, 60),   20, 15 },
	disguise        = { "DISGUISE!", Color3.fromRGB(180, 120, 255), "spin",    Color3.fromRGB(160, 100, 255), Color3.fromRGB(180, 120, 255), 20, 15 },
	raftGlide       = { "GLIDE!",    Color3.fromRGB(100, 200, 150), "bounce",  Color3.fromRGB(80, 180, 130),  Color3.fromRGB(100, 200, 150), 20, 18 },
	logObstacle     = { "TIMBER!",   Color3.fromRGB(140, 90, 50),   "shake",   Color3.fromRGB(120, 70, 30),   Color3.fromRGB(140, 90, 50),   20, 18 },
	laptopHack      = { "HACK!",     Color3.fromRGB(60, 255, 60),   "shake",   Color3.fromRGB(40, 255, 40),   Color3.fromRGB(60, 255, 60),   20, 15 },
	backpackBlock   = { "BLOCK!",    Color3.fromRGB(100, 100, 180), "bounce",  Color3.fromRGB(80, 80, 160),   Color3.fromRGB(100, 100, 180), 15, 15 },
}

-- ─── Play animation for an effectKey ─────────────────────────────────────────

local function _playAbilityAnim(effectKey)
	if not _vehicle or not _vehicle.PrimaryPart then return end
	local primary = _vehicle.PrimaryPart

	local anim = EFFECT_ANIMS[effectKey]
	if not anim then
		-- Generic fallback
		_floatText(primary, "!", Color3.fromRGB(255, 220, 60), 1.0)
		_particleBurst(primary, Color3.fromRGB(255, 220, 60), 15, 15)
		return
	end

	local label, labelColour, layer1, layer2Colour, partColour, partCount, partSpeed = table.unpack(anim)

	-- Layer 1: vehicle transform
	if layer1 == "shake" then
		_shakeVehicle(primary, 0.08, 0.4)
	elseif layer1 == "bounce" then
		_bounceVehicle(primary, 1.5, 0.4)
	elseif layer1 == "spin" then
		_spinVehicle(primary, 0.5)
	end

	-- Layer 2: floating text
	_floatText(primary, label, labelColour, 1.2)

	-- Layer 3: particle burst
	_particleBurst(primary, partColour, partCount, partSpeed)
end

-- ─── Remote listener ──────────────────────────────────────────────────────────

-- Server sends (userId, itemName, targetIds, effectKey)
RemoteEvents.AbilityActivated.OnClientEvent:Connect(function(userId, itemName, _targetIds, effectKey)
	if userId == LocalPlayer.UserId then
		_playAbilityAnim(effectKey)
	else
		-- Other player's ability: play lighter version on their vehicle
		-- (Vehicle reference not tracked for others; skip Layer 1, do Layer 2/3 only)
		-- Future: track per-player vehicles via VehicleSpawned
	end
end)

-- ─── Vehicle tracking ─────────────────────────────────────────────────────────

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, vehicleModel)
	if userId == LocalPlayer.UserId then
		_vehicle = vehicleModel
	end
end)

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	local Constants = require(ReplicatedStorage.Shared.Constants)
	if phase ~= Constants.PHASES.RACING then
		_vehicle = nil
	end
end)
