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

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)

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
	windup    = A(R(-35), 0, 0),
	punchR    = A(R(95), R(12), 0),
	guardR    = A(R(75), R(35), R(15)),
	guardL    = A(R(75), R(-35), R(-15)),
	reachR    = A(R(85), R(-8), 0),
	reachL    = A(R(85), R(8), 0),
	swatR     = A(R(60), R(-40), 0),
	twistL    = A(0, R(-18), 0),
	flinch    = A(R(-14), 0, 0),
}

local function charOf(userId)
	local p = userId and Players:GetPlayerByUserId(userId)
	return p and p.Character, p
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
	gui.Size = UDim2.new(0, 160, 0, 36)
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
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + push + Vector3.new(0, 14, 0)
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
		t.Position = UDim2.fromScale(0.5, 0.32)
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

local function swing(character)
	local r, waist = joint(character, "right"), joint(character, "waist")
	if not r then return false end
	tweenTo(r, POSE.windup, 0.07)
	tweenTo(waist, POSE.twistL, 0.07)
	task.delay(0.07, function()
		tweenTo(r, POSE.punchR, 0.08, Enum.EasingStyle.Back)
		task.delay(0.16, function()
			if _guarding[character] then tweenTo(r, POSE.guardR, 0.15) else release(r, 0.18) end
			release(waist, 0.18)
		end)
	end)
	return true
end

local function onPunch(attackerId, victimId, info)
	local aChar = charOf(attackerId)
	local vChar, victim = charOf(victimId)
	local result = info and info.result
	local swung = aChar ~= nil and swing(aChar)
	if LocalPlayer:GetAttribute("HarnessBot") then
		-- Studio harness: drawn = the attacker's arm really turned against the
		-- torso during the swing (largest angle over 0.4 s), not just "a
		-- character exists" (that passed while every pose did nothing)
		local arm = aChar and (aChar:FindFirstChild("RightUpperArm") or aChar:FindFirstChild("Right Arm"))
		local torso = aChar and (aChar:FindFirstChild("UpperTorso") or aChar:FindFirstChild("Torso"))
		local rest = arm and torso and torso.CFrame:ToObjectSpace(arm.CFrame)
		local h = aChar and joint(aChar, "right")
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
				report("farmfx", { what = "punch", result = result, drawn = swung and posedMax > 60 and turned > 10,
					joint = h and h.prop, posed = math.floor(posedMax), turned = math.floor(turned),
					attacker = attackerId })
			end
		end)
	end
	if not vChar then return end
	task.delay(0.12, function()
		if result == "hit" or result == "knockout" then
			flash(vChar, Color3.fromRGB(255, 70, 60), 0.3)
			burst(vChar, Color3.fromRGB(255, 230, 90), result == "knockout" and 30 or 14)
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
		local thief = Players:GetPlayerByUserId(thiefId)
		prompt(("⚠️ %s is stealing from you!  Mash E! (0/%d)"):format(thief and thief.DisplayName or "?",
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
		local thief = Players:GetPlayerByUserId(thiefId)
		local n = info and info.presses or 0
		local done = n >= Constants.STEAL_DEFEND_PRESSES
		prompt(done and "🛡️ DEFENDED!" or ("⚠️ %s is stealing!  Mash E! (%d/%d)"):format(
			thief and thief.DisplayName or "?", n, Constants.STEAL_DEFEND_PRESSES),
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
	if victim == LocalPlayer and result ~= "defended" then
		prompt(result == "stolen" and "😱 An item was stolen!" or "", Color3.fromRGB(255, 120, 120), result == "stolen" and 1.5 or 0.01)
	end
	report("farmfx", { what = "grabEnd", result = result, drawn = tChar ~= nil })
end

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
		end
	end)
	if not ok then report("farmfx", { what = kind, error = tostring(err) }) end
end)
