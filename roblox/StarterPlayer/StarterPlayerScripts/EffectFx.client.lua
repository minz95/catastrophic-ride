-- EffectFx.client.lua
-- Draws every effect that lands on a car (RemoteEvents.EffectFx), on that
-- car, for every player, and the overlay on the screen of the player it hit
-- (RemoteEvents.ScreenEffect). Looks: ReplicatedStorage/Shared/EffectLook.
--
-- Everything here is visual and local: highlights, labels, particles,
-- beams and anchored non-colliding parts that follow the car. Nothing moves
-- the car (the old AbilityAnimator tweened the chassis CFrame, which
-- teleported a moving car).
--
-- Harness bots report what they drew ("fx" / "screen") so a Studio run can
-- check that the effects were really drawn.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local EffectLook   = require(ReplicatedStorage.Shared.EffectLook)

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local LABEL_SECONDS = 1.4
local HIT_SECONDS   = 0.5    -- highlight time of one-off looks
local MAX_DISTANCE  = 160    -- studs: labels further away are not drawn
local BEAM_SECONDS  = 0.6

-- ─── Harness reporting ────────────────────────────────────────────────────────

local _channel
local function report(kind, payload)
	if not LocalPlayer:GetAttribute("HarnessBot") then return end
	_channel = _channel or ReplicatedStorage:FindFirstChild("HarnessChannel")
	if _channel then _channel:FireServer(kind, payload) end
end

-- ─── Cars ─────────────────────────────────────────────────────────────────────

local _cars = {}   -- [userId] = Model

local function carOf(userId)
	local m = _cars[userId]
	if m and m.Parent and m.PrimaryPart then return m end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == userId and child.PrimaryPart then
			_cars[userId] = child
			return child
		end
	end
	return nil
end

-- ─── Per-car highlight (latest effect's colour while any effect lasts) ───────

local _glow = {}   -- [model] = { hl = Highlight, untilT = number }

local function glow(model, color, seconds)
	local g = _glow[model]
	if not g or not g.hl.Parent then
		local hl = Instance.new("Highlight")
		hl.Name = "EffectGlow"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 0.55
		hl.OutlineTransparency = 0.1
		hl.Adornee = model
		hl.Parent = model
		g = { hl = hl, untilT = 0 }
		_glow[model] = g
	end
	g.hl.FillColor = color
	g.hl.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.4)
	g.hl.Enabled = true
	g.untilT = math.max(g.untilT, os.clock() + seconds)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, g in pairs(_glow) do
		if not model.Parent then
			_glow[model] = nil
		elseif g.untilT <= now and g.hl.Enabled then
			g.hl.Enabled = false
		end
	end
end)

-- ─── Floating label ──────────────────────────────────────────────────────────

local function floatLabel(primary, text, color, big)
	-- one label per car: a newer effect replaces the older word
	for _, old in ipairs(primary:GetChildren()) do
		if old.Name == "EffectLabel" and old:IsA("BillboardGui") then old:Destroy() end
	end
	local T = EffectLook.TEXT
	local bb = Instance.new("BillboardGui")
	bb.Name = "EffectLabel"
	bb.Size = UDim2.new(0, big and T.BIG_W or T.W, 0, big and T.BIG_H or T.H)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = MAX_DISTANCE
	bb.Adornee = primary
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = bb
	bb.Parent = primary
	TweenService:Create(bb, TweenInfo.new(LABEL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(LABEL_SECONDS * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, LABEL_SECONDS * 0.5),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(bb, LABEL_SECONDS + 0.1)
end

-- ─── Particles ───────────────────────────────────────────────────────────────

local function emitter(primary, offset, props)
	local att = Instance.new("Attachment")
	att.Name = "EffectAttachment"
	att.Position = offset or Vector3.zero
	att.Parent = primary
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0.6
	e.LightInfluence = 0.3
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = att
	return att, e
end

local function seq(a, b) return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) end

-- Emits for `seconds` (or bursts `count` once) and cleans up.
local function particles(primary, offset, props, seconds, count)
	local att, e = emitter(primary, offset, props)
	if count then e:Emit(count) end
	if seconds then e.Rate = props.Rate or 30 end
	local life = (seconds or 0) + 1.5
	if seconds then
		task.delay(seconds, function() if e.Parent then e.Enabled = false end end)
	end
	Debris:AddItem(att, life)
end

-- ─── Drift smoke (every car, seen by everyone) ───────────────────────────────
-- A car whose velocity points away from its nose (VehicleController slide)
-- smokes from the rear corners. Worked out from the replicated velocity,
-- so no network message is needed. Boats throw spray instead.

local DRIFT_SMOKE = { MIN_SPEED = 25, MIN_ANGLE = math.rad(12) }
local _smoke = {}   -- [model] = { emitters }
local _smokeT = 0

local function smokeFor(model)
	local s = _smoke[model]
	if s then return s end
	local primary = model.PrimaryPart
	local half = primary.Size * 0.5
	local isBoat = ReplicatedStorage:GetAttribute("Biome") == "OCEAN"
	s = {}
	for _, side in ipairs({ -1, 1 }) do
		local _, e = emitter(primary, Vector3.new(side * half.X, -half.Y, half.Z), {
			Name = "DriftSmoke",
			Color = ColorSequence.new(isBoat and Color3.fromRGB(220, 240, 255) or Color3.fromRGB(235, 235, 235)),
			Size = seq(1.2, 3.5), Transparency = seq(0.35, 1),
			Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(40, 40), LightEmission = 0.1,
		})
		table.insert(s, e)
	end
	_smoke[model] = s
	return s
end

RunService.Heartbeat:Connect(function(dt)
	_smokeT += dt
	if _smokeT < 0.1 then return end
	_smokeT = 0
	for model in pairs(_smoke) do
		if not model.Parent or not model.PrimaryPart then _smoke[model] = nil end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		local primary = child:IsA("Model") and child:GetAttribute("OwnerUserId") and child.PrimaryPart
		if primary and primary:FindFirstChild("HoverPosition") == nil then
			local v = primary.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z)
			local look = primary.CFrame.LookVector
			look = Vector3.new(look.X, 0, look.Z)
			local sliding = false
			if flat.Magnitude > DRIFT_SMOKE.MIN_SPEED and look.Magnitude > 1e-3 then
				local cosA = flat.Unit:Dot(look.Unit)
				sliding = math.acos(math.clamp(cosA, -1, 1)) > DRIFT_SMOKE.MIN_ANGLE
			end
			if sliding or _smoke[child] then
				for _, e in ipairs(smokeFor(child)) do e.Rate = sliding and 40 or 0 end
			end
		end
	end
end)

-- ─── Follow part (shield bubble, ring) ───────────────────────────────────────

local _followers = {}   -- { part, primary, untilT, offset }

local function followPart(primary, props, seconds)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	for k, v in pairs(props) do p[k] = v end
	p.CFrame = primary.CFrame
	p.Parent = workspace
	table.insert(_followers, { part = p, primary = primary, untilT = os.clock() + seconds })
	return p
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #_followers, 1, -1 do
		local f = _followers[i]
		if now >= f.untilT or not f.primary.Parent then
			f.part:Destroy()
			table.remove(_followers, i)
		else
			f.part.CFrame = CFrame.new(f.primary.Position)
		end
	end
end)

local function ring(primary, color, radius)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Size = Vector3.new(0.3, 2, 2)
	p.CFrame = CFrame.new(primary.Position - Vector3.new(0, primary.Size.Y * 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.6)
end

-- ─── Beam from the car that caused it ────────────────────────────────────────

local function beam(fromPrimary, toPrimary, color)
	local a0 = Instance.new("Attachment"); a0.Name = "EffectBeam0"; a0.Parent = fromPrimary
	local a1 = Instance.new("Attachment"); a1.Name = "EffectBeam1"; a1.Parent = toPrimary
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(color)
	b.LightEmission = 1
	b.Width0, b.Width1 = 0.6, 0.2
	b.FaceCamera = true
	b.Transparency = seq(0.1, 0.5)
	b.Parent = a0
	TweenService:Create(b, TweenInfo.new(BEAM_SECONDS), { Width0 = 0, Width1 = 0 }):Play()
	Debris:AddItem(a0, BEAM_SECONDS + 0.05)
	Debris:AddItem(a1, BEAM_SECONDS + 0.05)
end

-- ─── Ghost (Cardboard Box disguise) ──────────────────────────────────────────

local function ghost(model, seconds)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = 0.75 end
	end
	task.delay(seconds, function()
		if not model.Parent then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
	end)
end

-- ─── Styles ──────────────────────────────────────────────────────────────────

local function fovKick(amount, seconds)
	local base = Camera.FieldOfView
	TweenService:Create(Camera, TweenInfo.new(0.15), { FieldOfView = base + amount }):Play()
	task.delay(seconds, function()
		TweenService:Create(Camera, TweenInfo.new(0.4), { FieldOfView = base }):Play()
	end)
end

local STYLES = {}

STYLES.boost = function(model, primary, look, d, mine)
	local back = Vector3.new(0, 0, primary.Size.Z * 0.5 + 0.3)   -- +Z = rear of the chassis
	particles(primary, back, {
		Color = ColorSequence.new(look.color, Color3.fromRGB(255, 240, 200)),
		Size = seq(1.1, 0), Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(8, 14),
		EmissionDirection = Enum.NormalId.Back, SpreadAngle = Vector2.new(18, 18), Rate = 60,
	}, d)
	glow(model, look.color, d)
	if mine then fovKick(8, d) end
	return { "particles", "highlight" }
end

STYLES.lift = function(model, primary, look, d)
	local under = Vector3.new(0, -primary.Size.Y * 0.5, 0)
	particles(primary, under, {
		Color = ColorSequence.new(look.color, Color3.new(1, 1, 1)),
		Size = seq(0.8, 0.1), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(4, 8),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(40, 40), Rate = 35,
	}, d)
	glow(model, look.color, d)
	return { "particles", "highlight" }
end

STYLES.shield = function(model, primary, look, d)
	local s = math.max(primary.Size.X, primary.Size.Y, primary.Size.Z) * 1.5
	followPart(primary, {
		Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s),
		Material = Enum.Material.ForceField, Color = look.color, Transparency = 0,
	}, math.max(d, HIT_SECONDS))
	glow(model, look.color, math.max(d, HIT_SECONDS))
	return { "bubble", "highlight" }
end

STYLES.slow = function(model, primary, look, d)
	particles(primary, Vector3.zero, {
		Color = ColorSequence.new(look.color), Size = seq(0.5, 0.2), Transparency = seq(0, 1),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, -20, 0), SpreadAngle = Vector2.new(180, 180), Rate = 25,
	}, math.max(d, HIT_SECONDS))
	glow(model, look.color, math.max(d, HIT_SECONDS))
	return { "particles", "highlight" }
end

STYLES.stun = function(model, primary, look, d)
	particles(primary, Vector3.zero, {
		Color = ColorSequence.new(look.color), Size = seq(0.7, 0.3), Transparency = seq(0, 1),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(2, 5),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		SpreadAngle = Vector2.new(180, 180), Rate = 20,
	}, math.max(d, HIT_SECONDS), 15)
	glow(model, look.color, math.max(d, HIT_SECONDS))
	return { "particles", "highlight" }
end

STYLES.blind = function(model, primary, look, d)
	particles(primary, Vector3.new(0, 1, 0), {
		Color = ColorSequence.new(look.color), Size = seq(2.5, 5), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rate = 30, LightEmission = 0.1,
	}, math.max(d, HIT_SECONDS))
	glow(model, look.color, math.max(d, HIT_SECONDS))
	return { "particles", "highlight" }
end

STYLES.hit = function(model, primary, look)
	particles(primary, Vector3.zero, {
		Color = ColorSequence.new(look.color, Color3.new(1, 1, 1)), Size = seq(0.5, 0),
		Transparency = seq(0, 1), Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(15, 25),
		SpreadAngle = Vector2.new(180, 180),
	}, nil, 25)
	glow(model, look.color, HIT_SECONDS)
	return { "particles", "highlight" }
end

STYLES.wave = function(model, primary, look)
	ring(primary, look.color, 12)
	glow(model, look.color, HIT_SECONDS)
	return { "ring", "highlight" }
end

STYLES.ghost = function(model, _primary, look, d)
	ghost(model, d)
	return { "ghost" }
end

STYLES.cleanse = function(model, primary, look, d)
	particles(primary, Vector3.new(0, 1, 0), {
		Color = ColorSequence.new(look.color, Color3.new(1, 1, 1)), Size = seq(0.6, 0.2),
		Transparency = seq(0, 1), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(5, 10),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-180, 180),
		Acceleration = Vector3.new(0, -6, 0), SpreadAngle = Vector2.new(180, 180),
	}, nil, 40)
	glow(model, Color3.new(1, 1, 1), 0.3)
	return { "particles", "highlight" }
end

STYLES.aura = function(model, primary, look, d)
	particles(primary, Vector3.zero, {
		Color = ColorSequence.new(look.color), Size = seq(0.4, 0), Transparency = seq(0, 1),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(2, 4),
		Acceleration = Vector3.new(0, 8, 0), SpreadAngle = Vector2.new(180, 180), Rate = 30,
	}, math.max(d, HIT_SECONDS))
	glow(model, look.color, math.max(d, HIT_SECONDS))
	return { "particles", "highlight" }
end

STYLES.drop = function(_model, primary, look)
	local back = Vector3.new(0, 0, primary.Size.Z * 0.5 + 1)
	particles(primary, back, {
		Color = ColorSequence.new(look.color, Color3.fromRGB(120, 120, 120)), Size = seq(1, 0),
		Transparency = seq(0.2, 1), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(180, 180),
	}, nil, 20)
	return { "particles" }
end

STYLES.badge = function()
	return {}
end

-- ─── EffectFx listener ───────────────────────────────────────────────────────

local _reported = {}       -- [key] = draws reported (harness bots)
local REPORT_PER_KEY = 6

RemoteEvents.EffectFx.OnClientEvent:Connect(function(key, userId, info)
	info = type(info) == "table" and info or {}
	local model = carOf(userId)
	if not model then
		report("fx", { key = key, on = userId, drawn = {}, missing = "car" })   -- always: a failure
		return
	end
	local primary = model.PrimaryPart
	local look = EffectLook.car(key)
	local d = tonumber(info.duration) or 0
	local mine = userId == LocalPlayer.UserId
	local ok, drawn = pcall(STYLES[look.style] or STYLES.hit, model, primary, look, d, mine)
	drawn = ok and drawn or {}
	if look.label then
		local text = info.text and (look.label .. " " .. info.text) or look.label
		floatLabel(primary, text, look.color, mine)
		table.insert(drawn, "label")
	end
	if look.beam and info.from then
		local src = carOf(info.from)
		if src and src.PrimaryPart then
			beam(src.PrimaryPart, primary, look.color)
			table.insert(drawn, "beam")
		end
	end
	if (_reported[key] or 0) < REPORT_PER_KEY or not ok then
		_reported[key] = (_reported[key] or 0) + 1
		report("fx", { key = key, on = userId, drawn = drawn, error = (not ok) and tostring(drawn) or nil })
	end
end)

-- ─── Screen overlay for the player who was hit ───────────────────────────────

local _overlay, _tint, _text

local function overlay()
	if _overlay and _overlay.Parent then return end
	_overlay = Instance.new("ScreenGui")
	_overlay.Name = "EffectOverlay"
	_overlay.ResetOnSpawn = false
	_overlay.IgnoreGuiInset = true
	_overlay.DisplayOrder = 5
	_tint = Instance.new("Frame")
	_tint.Size = UDim2.fromScale(1, 1)
	_tint.BackgroundTransparency = 1
	_tint.BorderSizePixel = 0
	_tint.Parent = _overlay
	_text = Instance.new("TextLabel")
	local T = EffectLook.TEXT
	_text.AnchorPoint = Vector2.new(0.5, 0)
	_text.Size = UDim2.new(T.SCREEN_W, 0, T.SCREEN_H, 0)
	_text.Position = UDim2.new(0.5, 0, 0.28, 0)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = T.SCREEN_MAX_PX
	cap.Parent = _text
	_text.BackgroundTransparency = 1
	_text.TextScaled = true
	_text.Font = Enum.Font.GothamBlack
	_text.TextColor3 = Color3.new(1, 1, 1)
	_text.TextStrokeTransparency = 0.1
	_text.TextTransparency = 1
	_text.TextStrokeColor3 = Color3.new(0, 0, 0)
	_text.Parent = _overlay
	_overlay.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local _screenToken = 0

local function shake(amount, seconds)
	task.spawn(function()
		local t = 0
		while t < seconds do
			Camera.CFrame = Camera.CFrame * CFrame.Angles((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
			t += task.wait()
		end
	end)
end

RemoteEvents.ScreenEffect.OnClientEvent:Connect(function(name, params)
	local look = EffectLook.SCREEN[name]
	if not look then return end   -- other names are drawn by RacingClient / ParticleClient
	overlay()
	local seconds = (type(params) == "table" and tonumber(params.duration)) or look.seconds or 1.5
	_screenToken += 1
	local token = _screenToken
	_tint.BackgroundColor3 = look.color
	_tint.BackgroundTransparency = 1 - look.alpha
	_text.Text = look.text or ""
	_text.TextColor3 = look.color:Lerp(Color3.new(1, 1, 1), 0.5)
	_text.TextTransparency = 0
	_text.TextStrokeTransparency = 0.1
	if look.shake then shake(look.shake, math.min(seconds, 0.5)) end
	task.delay(seconds, function()
		if token ~= _screenToken then return end
		TweenService:Create(_tint, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(_text, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	report("screen", { name = name, seconds = seconds })
end)

-- a new phase only: the same phase again is the server's resend after a
-- respawn (it cleared the effects on every car mid-race)
local _lastPhase = nil
RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == _lastPhase then return end
	_lastPhase = phase
	_cars = {}
end)
