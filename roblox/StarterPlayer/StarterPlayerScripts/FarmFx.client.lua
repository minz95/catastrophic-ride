-- FarmFx.client.lua
-- What players do to each other in FARMING, drawn on their characters for
-- everyone (RemoteEvents.FarmAction from FarmingManager):
--   punch    the attacker's right arm swings, the torso twists; a landed hit
--            makes the victim flinch (red flash, stars, pushed back) and
--            shows the hit count above the head (●●○○); a knock-out pops
--            the dropped item's name; a blocked punch flashes blue.
--   guard    both arms up in front while G is held (and walking slows).
--   grab     a steal opens: the thief reaches with both arms, the victim
--            wriggles, and the victim gets a big "press E" prompt.
--   swat     a defence tap: the victim slaps at the thief.
--   grabEnd  stolen → labels on both; defended → the thief is pushed back.
--   drop     an item leaves an inventory: it flies from the dropper's hands
--            to where it lands, with a dust puff.
-- Poses rotate the shoulder / waist joints in the parent part's space: a
-- Motor6D's C0 (R6, classic R15) or, on avatars with Roblox's newer joints
-- (AnimationConstraint, no Motor6D), the joint's parent-side attachment. With
-- only the Motor6D path every pose silently did nothing on those avatars.
-- Nothing here moves anything the server checks except the local player's
-- own character (knockback, walk speed).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local EffectLook   = require(ReplicatedStorage.Shared.EffectLook)
local SoundFx      = require(ReplicatedStorage.Shared.SoundFx)

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local F = Constants.FIGHT

-- ─── Harness reporting (Studio bots) ─────────────────────────────────────────

local _channel
local _reported = {}
local function report(kind, payload)
	if not LocalPlayer:GetAttribute("HarnessBot") then return end
	local key = kind .. ":" .. tostring(payload and payload.what)
	_reported[key] = (_reported[key] or 0) + 1
	if _reported[key] > 8 then return end
	_channel = _channel or ReplicatedStorage:FindFirstChild("HarnessChannel")
	if _channel then _channel:FireServer(kind, payload) end
end

-- ─── Joints ──────────────────────────────────────────────────────────────────

local JOINTS = {
	right = { "RightShoulder", "Right Shoulder" },
	left  = { "LeftShoulder", "Left Shoulder" },
	waist = { "Waist", "RootJoint" },
	rightLeg = { "RightHip", "Right Hip" },
}

-- A joint handle is the object and CFrame property that place the limb in
-- its parent part's space: { obj = Motor6D, prop = "C0" } or
-- { obj = AnimationConstraint.Attachment0, prop = "CFrame" }.
local _handles = setmetatable({}, { __mode = "k" })   -- [obj] = handle
local _base = setmetatable({}, { __mode = "k" })      -- [obj] = original CFrame

local function handleOf(j)
	local obj, prop
	if j:IsA("Motor6D") then
		obj, prop = j, "C0"
	elseif j:IsA("AnimationConstraint") and j.Attachment0 then
		obj, prop = j.Attachment0, "CFrame"
	else
		return nil
	end
	local h = _handles[obj]
	if not h then
		h = { obj = obj, prop = prop }
		_handles[obj] = h
		_base[obj] = obj[prop]
	end
	return h
end

local function joint(character, which)
	for _, name in ipairs(JOINTS[which]) do
		local j = character:FindFirstChild(name, true)
		local h = j and handleOf(j)
		if h then return h end
	end
	return nil
end

-- The joint's rest CFrame rotated by `rot` around the joint, in the parent
-- part's axes (parent space: -Z forward, Y up, X right).
local function posed(h, rot)
	local c0 = _base[h.obj]
	local p = c0.Position
	return CFrame.new(p) * rot * (c0 - p)
end

local function tweenTo(h, rot, seconds, style)
	if not h then return false end
	TweenService:Create(h.obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ [h.prop] = posed(h, rot) }):Play()
	return true
end

local function release(h, seconds)
	if h and _base[h.obj] then
		TweenService:Create(h.obj, TweenInfo.new(seconds or 0.2), { [h.prop] = _base[h.obj] }):Play()
	end
end

local A = CFrame.Angles
local R = math.rad
-- arm forward: rotate +X; inward: rotate about Y (towards the chest)
local POSE = {
	windup    = A(R(-50), R(-15), 0),
	punchR    = A(R(105), R(22), 0),
	twistR    = A(0, R(20), 0),
	guardR    = A(R(75), R(35), R(15)),
	guardL    = A(R(75), R(-35), R(-15)),
	reachR    = A(R(85), R(-8), 0),
	reachL    = A(R(85), R(8), 0),
	swatR     = A(R(60), R(-40), 0),
	twistL    = A(0, R(-32), 0),
	flinch    = A(R(-14), 0, 0),
	kickWind  = A(R(-30), 0, 0),
	kickR     = A(R(95), 0, 0),
	leanBack  = A(R(-12), 0, 0),
	-- waist: a rotation about X tips the torso's up towards -Z (forward)
	-- only when NEGATIVE; the old +32° leant back and no pick-up showed
	bendDown  = A(R(-55), 0, 0),     -- waist: bow to pick something up
	reachDownR = A(R(35), R(-12), 0),
	reachDownL = A(R(35), R(12), 0),
	liftR     = A(R(150), R(-10), 0), -- arms up: "got it!"
	liftL     = A(R(150), R(10), 0),
}

-- A player's character, or a farm bot's (Modules/FarmBots: tagged "FarmBot",
-- attribute BotUserId).
local function charOf(userId)
	local p = userId and Players:GetPlayerByUserId(userId)
	if p then return p.Character, p end
	if type(userId) == "number" and userId <= -100000 then
		for _, m in ipairs(CollectionService:GetTagged("FarmBot")) do
			if m:GetAttribute("BotUserId") == userId then return m, nil end
		end
	end
	return nil, nil
end

-- A player's display name, or a farm bot's (its model is named after it).
local function nameOf(userId)
	local c, p = charOf(userId)
	return (p and p.DisplayName) or (c and c.Name) or "Someone"
end

-- ─── Small looks ─────────────────────────────────────────────────────────────

local function flash(character, color, seconds)
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = 0.45
	hl.OutlineColor = color
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = character
	TweenService:Create(hl, TweenInfo.new(seconds or 0.3), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(hl, (seconds or 0.3) + 0.1)
end

local function burst(character, color, count)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local att = Instance.new("Attachment")
	att.Parent = head
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(8, 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 0.8
	e.Rate = 0
	e.Parent = att
	e:Emit(count or 14)
	Debris:AddItem(att, 1)
end

local function label(character, text, color, seconds, key)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local name = "FarmFxLabel_" .. (key or "x")
	local old = head:FindFirstChild(name)
	if old then old:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.new(0, EffectLook.TEXT.W, 0, EffectLook.TEXT.H)
	gui.StudsOffset = Vector3.new(0, key == "hits" and 2.4 or 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Parent = gui
	gui.Parent = head
	TweenService:Create(gui, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ StudsOffset = gui.StudsOffset + Vector3.new(0, 1, 0) }):Play()
	task.delay(seconds * 0.7, function()
		if t.Parent then TweenService:Create(t, TweenInfo.new(seconds * 0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
	end)
	Debris:AddItem(gui, seconds)
end

local function pips(hits, needed)
	local s = ""
	for i = 1, needed do s ..= (i <= hits) and "●" or "○" end
	return s
end

local function shake(amount, seconds)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - t0
		if age > seconds then conn:Disconnect() return end
		local k = amount * (1 - age / seconds)
		Camera.CFrame = Camera.CFrame * CFrame.Angles((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
	end)
end

local function pushMe(push)
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if root and push then
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + push + Vector3.new(0, F.KNOCK_UP, 0)
	end
end

-- ─── Defence prompt (the victim of a steal) ──────────────────────────────────

local _prompt
local function prompt(text, color, seconds)
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return end
	if not _prompt or not _prompt.Parent then
		_prompt = Instance.new("ScreenGui")
		_prompt.Name = "FarmFxPrompt"
		_prompt.ResetOnSpawn = false
		_prompt.IgnoreGuiInset = true
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.48)   -- mid-screen; at 0.32 it sat on the effect words and the phase toast
		t.Size = UDim2.new(0.7, 0, 0, 64)
		t.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		t.BackgroundTransparency = 0.25
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextStrokeTransparency = 0.3
		t.Parent = _prompt
		Instance.new("UICorner").Parent = t
		_prompt.Parent = pg
	end
	local t = _prompt.Text
	t.Text = text
	t.TextColor3 = color
	t.Visible = true
	local token = {}
	_prompt:SetAttribute("Token", tostring(token))
	task.delay(seconds, function()
		if _prompt and _prompt:GetAttribute("Token") == tostring(token) then t.Visible = false end
	end)
end

-- ─── Guard pose and wriggle loops ────────────────────────────────────────────

local _guarding = {}   -- [character] = true
local _wriggle = {}    -- [character] = untilT

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for character, untilT in pairs(_wriggle) do
		local waist = character.Parent and joint(character, "waist")
		if not waist or now > untilT then
			_wriggle[character] = nil
			release(waist, 0.15)
		else
			waist.obj[waist.prop] = posed(waist, A(0, R(14) * math.sin(now * 40), 0))
		end
	end
end)

local function setGuard(character, player, on)
	local r, l = joint(character, "right"), joint(character, "left")
	local posedOk = r ~= nil and l ~= nil
	if on then
		_guarding[character] = true
		tweenTo(r, POSE.guardR, 0.12)
		tweenTo(l, POSE.guardL, 0.12)
	else
		_guarding[character] = nil
		release(r, 0.15)
		release(l, 0.15)
	end
	if player == LocalPlayer then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			if on then
				hum:SetAttribute("WalkSpeedBeforeGuard", hum:GetAttribute("WalkSpeedBeforeGuard") or hum.WalkSpeed)
				hum.WalkSpeed = hum:GetAttribute("WalkSpeedBeforeGuard") * F.GUARD_SLOW
			elseif hum:GetAttribute("WalkSpeedBeforeGuard") then
				hum.WalkSpeed = hum:GetAttribute("WalkSpeedBeforeGuard")
				hum:SetAttribute("WalkSpeedBeforeGuard", nil)
			end
		end
	end
	return posedOk
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

-- A short streak behind the fist (or foot) while it swings: the arm alone
-- was hard to see from the camera behind the player (playtest 2026-10-28:
-- "F does nothing").
local function streak(character, limbNames, seconds)
	local limb
	for _, n in ipairs(limbNames) do
		limb = character:FindFirstChild(n)
		if limb and limb:IsA("BasePart") then break end
		limb = nil
	end
	if not limb then return end
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	local h = limb.Size.Y / 2
	a0.Position, a1.Position = Vector3.new(-0.3, -h, 0), Vector3.new(0.3, -h, 0)
	a0.Parent, a1.Parent = limb, limb
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.16
	t.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 90))
	t.Transparency = NumberSequence.new(0.15, 1)
	t.WidthScale = NumberSequence.new(1, 0.2)
	t.LightEmission = 0.6
	t.FaceCamera = true
	t.Parent = limb
	Debris:AddItem(t, seconds)
	Debris:AddItem(a0, seconds)
	Debris:AddItem(a1, seconds)
end

-- A punch you can read: wind up (arm back, body turned away, the other
-- fist up), snap through, hold the arm out, come back.
-- Playtest 2026-10-29: the old 0.16 s flick (no hold, one arm) did not read
-- as a punch at all.
local SWING = { WIND = 0.11, STRIKE = 0.08, HOLD = 0.18, BACK = 0.22 }

-- While a pose plays on a character with the Animate script running (your
-- own avatar), its idle / walk tracks are faded out and the joints' motors
-- made strong, then put back. Studio 2026-10-30: on your own avatar the
-- shoulder reached the punch pose (117°) but the arm moved only 15-41° on
-- screen (a bot's arm: 116°); "the bots punch fine, mine does not".
-- One quiet spell per character, put back only when the last pose that
-- asked for it is over (Studio, second run: punches 0.45 s apart put the
-- walk back mid-swing, and only the first punch of a flurry showed).
local _quiet = setmetatable({}, { __mode = "k" })   -- [character] = { untilT, tracks, torques }
local function quietAnim(character, seconds)
	local q = _quiet[character]
	if not q then
		q = { untilT = 0, tracks = {}, torques = {} }
		_quiet[character] = q
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and not q.conn then
		-- a track started meanwhile (you start walking) stays quiet too
		q.conn = animator.AnimationPlayed:Connect(function(t)
			if q.tracks[t] == nil then
				q.tracks[t] = 1
				t:AdjustWeight(0.01, 0.05)
			end
		end)
	end
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			if q.tracks[t] == nil and t.WeightTarget > 0.05 then
				q.tracks[t] = t.WeightTarget
				t:AdjustWeight(0.01, 0.05)
			end
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("AnimationConstraint") and q.torques[d] == nil then
			pcall(function()
				q.torques[d] = d.MaxTorque
				d.MaxTorque = math.huge
			end)
		end
	end
	q.untilT = math.max(q.untilT, os.clock() + seconds)
	task.delay(seconds + 0.01, function()
		if _quiet[character] ~= q or os.clock() < q.untilT then return end
		_quiet[character] = nil
		if q.conn then q.conn:Disconnect() end
		for t, w in pairs(q.tracks) do
			if t.IsPlaying then t:AdjustWeight(w, 0.15) end
		end
		for d, v in pairs(q.torques) do
			pcall(function() d.MaxTorque = v end)
		end
	end)
end

local function swing(character)
	local r, l, waist = joint(character, "right"), joint(character, "left"), joint(character, "waist")
	if not r then return false end
	quietAnim(character, SWING.WIND + SWING.STRIKE + SWING.HOLD + SWING.BACK)
	tweenTo(r, POSE.windup, SWING.WIND)
	tweenTo(waist, POSE.twistR, SWING.WIND)
	tweenTo(l, POSE.guardL, SWING.WIND)
	task.delay(SWING.WIND, function()
		streak(character, { "RightHand", "Right Arm" }, 0.4)
		tweenTo(r, POSE.punchR, SWING.STRIKE, Enum.EasingStyle.Back)
		tweenTo(waist, POSE.twistL, SWING.STRIKE, Enum.EasingStyle.Back)
		task.delay(SWING.STRIKE + SWING.HOLD, function()
			if _guarding[character] then
				tweenTo(r, POSE.guardR, 0.15)
			else
				release(r, SWING.BACK)
				release(l, SWING.BACK)
			end
			release(waist, SWING.BACK)
		end)
	end)
	return true
end

-- The hit itself, where the fist lands: a white flash ball and a ring
-- (client-only parts, no collision).
local function impact(character, big)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso then return end
	local function puff(shape, size0, size1, color, seconds)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = size0
		p.CFrame = CFrame.new(torso.Position) * (shape == Enum.PartType.Cylinder and CFrame.Angles(0, 0, math.rad(90)) or CFrame.new())
		p.Parent = workspace
		TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = size1, Transparency = 1 }):Play()
		Debris:AddItem(p, seconds + 0.05)
	end
	local k = big and 1.6 or 1
	puff(Enum.PartType.Ball, Vector3.one * 0.8, Vector3.one * 4 * k, Color3.fromRGB(255, 255, 230), 0.16)
	puff(Enum.PartType.Cylinder, Vector3.new(0.2, 1, 1), Vector3.new(0.2, 7 * k, 7 * k), Color3.fromRGB(255, 210, 80), 0.22)
end

-- Your own landed hit: the view kicks in and back (a short zoom) and shakes.
local function hitKick(big)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local fov = cam.FieldOfView
	local d = big and 9 or 6
	TweenService:Create(cam, TweenInfo.new(0.05), { FieldOfView = fov - d }):Play()
	task.delay(0.06, function()
		TweenService:Create(cam, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { FieldOfView = fov }):Play()
	end)
	shake(big and 0.07 or 0.045, 0.22)
end

-- Flying Kick (shop move "kick"): the right leg instead of the right arm.
local function kick(character)
	local leg, waist = joint(character, "rightLeg"), joint(character, "waist")
	if not leg then return false end
	quietAnim(character, 0.5)
	tweenTo(leg, POSE.kickWind, 0.07)
	task.delay(0.07, function()
		streak(character, { "RightFoot", "Right Leg" }, 0.4)
		tweenTo(leg, POSE.kickR, 0.09, Enum.EasingStyle.Back)
		tweenTo(waist, POSE.leanBack, 0.09)
		task.delay(0.2, function()
			release(leg, 0.2)
			release(waist, 0.2)
		end)
	end)
	return true
end

-- A comic word that pops on a landed hit.
local POW_WORDS = { "POW!", "BAM!", "WHAM!", "BONK!", "SMACK!" }
local function pow(character, big)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local T = EffectLook.TEXT
	local gui = Instance.new("BillboardGui")
	gui.Name = "FarmFxPow"
	gui.Size = UDim2.new(0, 0, 0, 0)
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 1.5, 1.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.LuckiestGuy
	t.Text = POW_WORDS[math.random(#POW_WORDS)]
	t.TextColor3 = big and Color3.fromRGB(255, 90, 60) or Color3.fromRGB(255, 225, 60)
	t.TextStrokeColor3 = Color3.fromRGB(120, 20, 20)
	t.TextStrokeTransparency = 0
	t.Rotation = math.random(-14, 14)
	t.Parent = gui
	gui.Parent = head
	local w, h = big and T.BIG_W or T.W, big and T.BIG_H or T.H
	TweenService:Create(gui, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, w, 0, h) }):Play()
	task.delay(0.45, function()
		if t.Parent then TweenService:Create(t, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
	end)
	Debris:AddItem(gui, 0.7)
end

-- Our own punch swings when F is pressed (FarmingClient sets PunchAt); the
-- server's echo of it then only draws the hit.
local _predictedAt = -math.huge
local function punchNow()
	local c = LocalPlayer.Character
	if not c then return end
	_predictedAt = os.clock()
	local isKick = LocalPlayer:GetAttribute("MoveStyle") == "kick"
	local swung = if isKick then kick(c) else swing(c)
	if LocalPlayer:GetAttribute("HarnessBot") then
		-- Studio harness: our own swing (the F path) really posed the joint
		local h = joint(c, isKick and "rightLeg" or "right")
		-- and how far the arm really turned against the torso on screen
		local arm = c:FindFirstChild(isKick and "RightUpperLeg" or "RightUpperArm") or c:FindFirstChild(isKick and "Right Leg" or "Right Arm")
		local torso = c:FindFirstChild(isKick and "LowerTorso" or "UpperTorso") or c:FindFirstChild("Torso")
		local rest = arm and torso and torso.CFrame:ToObjectSpace(arm.CFrame)
		local posedMax, turned, t0, conn = 0, 0, os.clock(), nil
		conn = RunService.Heartbeat:Connect(function()
			if h then
				local a, b = h.obj[h.prop], _base[h.obj]
				posedMax = math.max(posedMax, math.deg(math.acos(math.clamp(a.UpVector:Dot(b.UpVector), -1, 1))))
			end
			if rest and arm.Parent and torso.Parent then
				local now = torso.CFrame:ToObjectSpace(arm.CFrame)
				turned = math.max(turned, math.deg(math.acos(math.clamp(now.UpVector:Dot(rest.UpVector), -1, 1))))
			end
			if os.clock() - t0 > 0.5 then
				conn:Disconnect()
				report("farmfx", { what = isKick and "ownKick" or "ownPunch", drawn = swung and posedMax > 60 and turned > 60,
					posed = math.floor(posedMax), turned = math.floor(turned), joint = h and h.prop })
			end
		end)
	end
	SoundFx.play("PUNCH_SWING")
	local root = c:FindFirstChild("HumanoidRootPart")
	if root then
		local look = root.CFrame.LookVector
		root.AssemblyLinearVelocity += Vector3.new(look.X, 0, look.Z) * F.LUNGE
	end
end
LocalPlayer:GetAttributeChangedSignal("PunchAt"):Connect(function()
	local ok, err = pcall(punchNow)
	if not ok then report("farmfx", { what = "punchNow", error = tostring(err) }) end
end)

local function onPunch(attackerId, victimId, info)
	local aChar = charOf(attackerId)
	local vChar, victim = charOf(victimId)
	local result = info and info.result
	local isKick = info and info.style == "kick"
	local mine = attackerId == LocalPlayer.UserId and os.clock() - _predictedAt < 0.8
	local swung = aChar ~= nil and (mine or (isKick and kick(aChar) or (not isKick and swing(aChar))))
	if LocalPlayer:GetAttribute("HarnessBot") then
		-- Studio harness: drawn = the attacker's arm really turned against the
		-- torso during the swing (largest angle over 0.4 s), not just "a
		-- character exists" (that passed while every pose did nothing)
		local arm = aChar and (isKick and (aChar:FindFirstChild("RightUpperLeg") or aChar:FindFirstChild("Right Leg"))
			or (aChar:FindFirstChild("RightUpperArm") or aChar:FindFirstChild("Right Arm")))
		local torso = aChar and (isKick and (aChar:FindFirstChild("LowerTorso") or aChar:FindFirstChild("Torso"))
			or (aChar:FindFirstChild("UpperTorso") or aChar:FindFirstChild("Torso")))
		local rest = arm and torso and torso.CFrame:ToObjectSpace(arm.CFrame)
		local h = aChar and joint(aChar, isKick and "rightLeg" or "right")
		local function angle(a, b)
			return math.deg(math.acos(math.clamp(a.UpVector:Dot(b.UpVector), -1, 1)))
		end
		local turned, posedMax, t0, conn = 0, 0, os.clock(), nil
		conn = RunService.Heartbeat:Connect(function()
			if rest and arm.Parent and torso.Parent then
				turned = math.max(turned, angle(torso.CFrame:ToObjectSpace(arm.CFrame), rest))
			end
			if h then posedMax = math.max(posedMax, angle(h.obj[h.prop], _base[h.obj])) end
			if os.clock() - t0 > 0.4 then
				conn:Disconnect()
				-- the joint reached the punch pose and the arm moved on screen
				-- (turned is measured from wherever the arm was, so it is
				-- smaller when punches overlap)
				report("farmfx", { what = isKick and "kick" or "punch", result = result, drawn = swung and posedMax > 60 and turned > 10,
					joint = h and h.prop, posed = math.floor(posedMax), turned = math.floor(turned),
					attacker = attackerId })
			end
		end)
	end
	if not vChar then return end
	-- our own swing started when F went down: the hit shows as soon as the
	-- server says so; someone else's swing starts now and lands after the wind-up
	task.delay(mine and 0 or SWING.WIND + 0.02, function()
		if result == "hit" or result == "knockout" then
			pow(vChar, result == "knockout")
			impact(vChar, result == "knockout")
			if attackerId == LocalPlayer.UserId then hitKick(result == "knockout") end
			flash(vChar, Color3.fromRGB(255, 70, 60), 0.3)
			burst(vChar, Color3.fromRGB(255, 230, 90), (result == "knockout" and 30 or 14) * (isKick and 2 or 1))
			if isKick then label(vChar, "🦶 KICK!", Color3.fromRGB(255, 200, 80), 0.9, "kick") end
			local waist = joint(vChar, "waist")
			tweenTo(waist, POSE.flinch, 0.06)
			task.delay(0.14, function() release(waist, 0.2) end)
			label(vChar, pips(info.hits or 0, info.needed or F.HITS_TO_DROP), Color3.fromRGB(255, 120, 90), 2.5, "hits")
			if result == "knockout" then
				local icon = info.item and ItemConfig[info.item] and ItemConfig[info.item].icon or ""
				label(vChar, "💥 " .. icon .. " " .. tostring(info.item or "") .. " DROPPED!", Color3.fromRGB(255, 220, 80), 2.2)
			end
			if victim == LocalPlayer then
				pushMe(info.push)
				shake(result == "knockout" and 0.06 or 0.03, 0.25)
			end
		elseif result == "blocked" then
			flash(vChar, Color3.fromRGB(90, 170, 255), 0.25)
			burst(vChar, Color3.fromRGB(150, 210, 255), 8)
			label(vChar, "🛡️ BLOCKED!", Color3.fromRGB(140, 200, 255), 1.2)
		elseif result == "immune" then
			label(vChar, "✨ IMMUNE", Color3.fromRGB(230, 230, 255), 1)
		end
	end)
end

local function onGrab(thiefId, victimId, info)
	local tChar = charOf(thiefId)
	local vChar, victim = charOf(victimId)
	local window = (info and info.window) or Constants.STEAL_DEFEND_WINDOW
	local reached = false
	if tChar then
		reached = tweenTo(joint(tChar, "right"), POSE.reachR, 0.15)
		reached = tweenTo(joint(tChar, "left"), POSE.reachL, 0.15) and reached
		label(tChar, "🖐️ STEALING…", Color3.fromRGB(255, 200, 90), window)
	end
	if vChar then
		_wriggle[vChar] = os.clock() + window
	end
	if victim == LocalPlayer then
		prompt(("⚠️ %s is stealing from you!  Mash E or punch (F)! (0/%d)"):format(nameOf(thiefId),
			Constants.STEAL_DEFEND_PRESSES), Color3.fromRGB(255, 210, 80), window + 0.3)
		shake(0.02, 0.3)
	end
	report("farmfx", { what = "grab", drawn = reached and vChar ~= nil })
end

local function onSwat(victimId, thiefId, info)
	local vChar, victim = charOf(victimId)
	local swatted = false
	if vChar then
		local r = joint(vChar, "right")
		swatted = tweenTo(r, POSE.swatR, 0.06)
		task.delay(0.1, function() release(r, 0.12) end)
	end
	if victim == LocalPlayer then
		local n = info and info.presses or 0
		local done = n >= Constants.STEAL_DEFEND_PRESSES
		prompt(done and "🛡️ DEFENDED!" or ("⚠️ %s is stealing!  Mash E or punch (F)! (%d/%d)"):format(
			nameOf(thiefId), n, Constants.STEAL_DEFEND_PRESSES),
			done and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 210, 80), done and 1 or 0.8)
	end
	report("farmfx", { what = "swat", drawn = swatted })
end

local function onGrabEnd(thiefId, victimId, info)
	local tChar, thief = charOf(thiefId)
	local vChar, victim = charOf(victimId)
	if tChar then
		release(joint(tChar, "right"), 0.2)
		release(joint(tChar, "left"), 0.2)
	end
	if vChar then _wriggle[vChar] = 0 end
	local result = info and info.result
	if result == "stolen" then
		if tChar then label(tChar, "😈 STOLEN!", Color3.fromRGB(255, 150, 60), 1.6) end
		if vChar then label(vChar, "😱 ROBBED!", Color3.fromRGB(255, 110, 110), 1.6); flash(vChar, Color3.fromRGB(255, 120, 60), 0.4) end
	elseif result == "punched" then
		-- punched off mid-grab (FIGHT.BREAKS_GRAB)
		if vChar then label(vChar, "👊 BROKE FREE!", Color3.fromRGB(120, 230, 140), 1.4); flash(vChar, Color3.fromRGB(120, 230, 140), 0.3) end
		if tChar then label(tChar, "💫 LET GO!", Color3.fromRGB(230, 230, 240), 1.2) end
		if victim == LocalPlayer then prompt("👊 You punched them off!", Color3.fromRGB(120, 230, 140), 1.2) end
	elseif result == "escaped" then
		if vChar then label(vChar, "💨 ESCAPED!", Color3.fromRGB(220, 220, 230), 1.4) end
	elseif result == "defended" then
		if vChar then label(vChar, "🛡️ DEFENDED!", Color3.fromRGB(120, 230, 140), 1.4); flash(vChar, Color3.fromRGB(120, 230, 140), 0.3) end
		if tChar then flash(tChar, Color3.fromRGB(200, 200, 200), 0.2) end
		if thief == LocalPlayer and tChar and vChar then
			local a, b = tChar:FindFirstChild("HumanoidRootPart"), vChar:FindFirstChild("HumanoidRootPart")
			if a and b then
				local d = Vector3.new(a.Position.X - b.Position.X, 0, a.Position.Z - b.Position.Z)
				pushMe(d.Magnitude > 1e-3 and d.Unit * F.KNOCKBACK * 0.8 or nil)
			end
		end
	end
	if victim == LocalPlayer and result ~= "defended" and result ~= "escaped" and result ~= "punched" then
		prompt(result == "stolen" and "😱 An item was stolen!" or "", Color3.fromRGB(255, 120, 120), result == "stolen" and 1.5 or 0.01)
	end
	report("farmfx", { what = "grabEnd", result = result, drawn = tChar ~= nil })
end

-- Smoke Bomb (shop gadget): a grey cloud where it was thrown, and the
-- thrower fades out while hidden (FarmingManager: no punch or steal lands).
local function onSmoke(actorId, info)
	local c = charOf(actorId)
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local at = (info and info.at) or (root and root.Position)
	if at then
		local cloud = Instance.new("Part")
		cloud.Name = "SmokeCloud"
		cloud.Anchored, cloud.CanCollide, cloud.CanQuery, cloud.CanTouch = true, false, false, false
		cloud.Transparency = 1
		cloud.Size = Vector3.new(1, 1, 1)
		cloud.CFrame = CFrame.new(at)
		cloud.Parent = workspace
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205), Color3.fromRGB(120, 120, 130))
		e.Size = NumberSequence.new(4, 9)
		e.Transparency = NumberSequence.new(0.15, 1)
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(3, 7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 60
		e.Parent = cloud
		e:Emit(40)
		task.delay((info and info.cloud) or 6, function() e.Enabled = false end)
		game:GetService("Debris"):AddItem(cloud, ((info and info.cloud) or 6) + 3)
	end
	if c then
		local fade = Players:GetPlayerByUserId(actorId) == LocalPlayer and 0.5 or 0.9
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = fade end
		end
		task.delay((info and info.hide) or 3.5, function()
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
			end
		end)
		label(c, "💨", Color3.fromRGB(230, 230, 235), 1.2, "smoke")
	end
	report("farmfx", { what = "smoke", drawn = at ~= nil })
end

-- Drop (Q, a full-inventory swap, a knock-out): the item flies out of the
-- dropper's hands in an arc, spinning, and lands where the server put it
-- with a puff of dust. Only this client's copy moves (the parts are anchored
-- at the landing spot on the server).
local DROP_TIME = 0.55
local function onDrop(actorId, info)
	local model = info and info.model
	local to = info and info.to
	if not model or not model.Parent or not to then
		report("farmfx", { what = "drop", drawn = false })
		return
	end
	local c = charOf(actorId)
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local from = (root and root.Position + Vector3.new(0, 1.5, 0)) or info.from or to
	local parts, finals = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			finals[d] = d.CFrame
		end
	end
	local pivot = model.PrimaryPart and model.PrimaryPart.Position or to
	local height = 3 + (from - to).Magnitude * 0.25
	local spin = (math.random() < 0.5 and -1 or 1) * math.pi * 2
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / DROP_TIME, 0, 1)
		if not model.Parent then conn:Disconnect() return end
		-- position along the arc relative to the landing spot
		local offset = (from - pivot) * (1 - k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
		local turn = CFrame.new(pivot) * CFrame.Angles(spin * (1 - k) * 0.4, spin * (1 - k), 0) * CFrame.new(-pivot)
		for _, p in ipairs(parts) do
			if p.Parent then p.CFrame = CFrame.new(offset) * turn * finals[p] end
		end
		if k >= 1 then
			conn:Disconnect()
			for _, p in ipairs(parts) do if p.Parent then p.CFrame = finals[p] end end
			local puff = Instance.new("Part")
			puff.Anchored, puff.CanCollide, puff.CanQuery, puff.CanTouch = true, false, false, false
			puff.Transparency = 1
			puff.Size = Vector3.new(1, 1, 1)
			puff.CFrame = CFrame.new(to + Vector3.new(0, 0.3, 0))
			puff.Parent = workspace
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(210, 190, 160))
			e.Size = NumberSequence.new(1.2, 2.6)
			e.Transparency = NumberSequence.new(0.3, 1)
			e.Lifetime = NumberRange.new(0.4, 0.7)
			e.Speed = NumberRange.new(4, 7)
			e.SpreadAngle = Vector2.new(80, 10)
			e.Rate = 0
			e.Parent = puff
			e:Emit(14)
			Debris:AddItem(puff, 1.2)
		end
	end)
	if c then label(c, "📦 " .. tostring(info.item or "item"), Color3.fromRGB(255, 220, 140), 1.0, "drop") end
	report("farmfx", { what = "drop", drawn = true, arc = math.floor((from - to).Magnitude * 10) / 10 })
end

-- Picking an item up (anyone, on every client): bow and reach down, then
-- both arms up with the item's icon over the head, while the item itself
-- flies into the hands (FarmingManager). Playtest 2026-10-29: items just
-- vanished with no pick-up motion.
local PICKUP = { BOW = 0.15, LOW = 0.2, RISE = 0.2, UP = 0.45, BACK = 0.25 }   -- s

local function onPickup(userId, info)
	local c, p = charOf(userId)
	if not c then return end
	local r, l, waist = joint(c, "right"), joint(c, "left"), joint(c, "waist")
	quietAnim(c, PICKUP.BOW + PICKUP.LOW + PICKUP.RISE + PICKUP.UP)
	tweenTo(waist, POSE.bendDown, PICKUP.BOW)
	tweenTo(r, POSE.reachDownR, PICKUP.BOW)
	tweenTo(l, POSE.reachDownL, PICKUP.BOW)
	-- your own character stops for the bow (walking on, it hardly showed)
	local hum = p == LocalPlayer and not _guarding[c] and c:FindFirstChildOfClass("Humanoid")
	if hum and not hum:GetAttribute("WalkSpeedBeforePickup") then
		hum:SetAttribute("WalkSpeedBeforePickup", hum.WalkSpeed)
		hum.WalkSpeed = 0
		task.delay(PICKUP.BOW + PICKUP.LOW, function()
			local was = hum:GetAttribute("WalkSpeedBeforePickup")
			hum:SetAttribute("WalkSpeedBeforePickup", nil)
			if was and hum.WalkSpeed == 0 then hum.WalkSpeed = was end
		end)
	end
	task.delay(PICKUP.BOW + PICKUP.LOW, function()
		release(waist, PICKUP.RISE)
		tweenTo(r, POSE.liftR, PICKUP.RISE, Enum.EasingStyle.Back)
		tweenTo(l, POSE.liftL, PICKUP.RISE, Enum.EasingStyle.Back)
		local cfg = info and info.item and ItemConfig[info.item]
		label(c, (cfg and cfg.icon or "✨") .. " " .. tostring(info and info.item or ""),
			Color3.fromRGB(255, 240, 160), 1.0, "pickup")
		burst(c, Color3.fromRGB(255, 240, 150), 10)
		task.delay(PICKUP.RISE + PICKUP.UP, function()
			if _guarding[c] then return end
			release(r, PICKUP.BACK)
			release(l, PICKUP.BACK)
		end)
	end)
	report("farmfx", { what = "pickup", drawn = waist ~= nil and r ~= nil, bow = waist and -55 or nil })
end
RemoteEvents.ItemPickedUp.OnClientEvent:Connect(function(_itemId, userId, info)
	local ok, err = pcall(onPickup, userId, info)
	if not ok then report("farmfx", { what = "pickup", error = tostring(err) }) end
end)

RemoteEvents.FarmAction.OnClientEvent:Connect(function(kind, actorId, targetId, info)
	local ok, err = pcall(function()
		if kind == "punch" then
			onPunch(actorId, targetId, info)
		elseif kind == "guard" then
			local c, p = charOf(actorId)
			local posedOk = c ~= nil and setGuard(c, p, info and info.on)
			report("farmfx", { what = "guard", drawn = posedOk })
		elseif kind == "grab" then
			onGrab(actorId, targetId, info)
		elseif kind == "swat" then
			onSwat(actorId, targetId, info)
		elseif kind == "grabEnd" then
			onGrabEnd(actorId, targetId, info)
		elseif kind == "smoke" then
			onSmoke(actorId, info)
		elseif kind == "drop" then
			onDrop(actorId, info)
		end
	end)
	if not ok then report("farmfx", { what = kind, error = tostring(err) }) end
end)
