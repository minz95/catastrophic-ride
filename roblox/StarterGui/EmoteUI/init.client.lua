-- EmoteUI/init.client.lua
-- Q-hold radial emote menu with 3 emotes: Wave, Dance, Cheer.
-- Resolves: Issue #15, #45

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

-- ─── Emote definitions ────────────────────────────────────────────────────────

local EMOTES = {
	{ name = "Wave",  icon = "👋", angle =  90, animId = "rbxassetid://507770239" },
	{ name = "Dance", icon = "💃", angle = 210, animId = "rbxassetid://507771019" },
	{ name = "Cheer", icon = "🙌", angle = 330, animId = "rbxassetid://507770677" },
}

local HOLD_THRESHOLD = 0.25   -- seconds Q must be held to open menu

-- ─── Build GUI ────────────────────────────────────────────────────────────────


-- This script runs again after every respawn, but its ScreenGui
-- (ResetOnSpawn = false) survives: drop the old copy so it is not shown twice.
for _, old in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "EmoteUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name           = "EmoteUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.Enabled        = true    -- always present; radial hidden until Q held
screen.Parent         = LocalPlayer.PlayerGui

-- (The "Hold Q  Emote" hint is in TutorialUI's key list; a label of its own
-- here sat on top of the Controls button.)

-- Radial container (hidden by default)
local radial = Instance.new("Frame")
radial.Name              = "Radial"
radial.Size              = UDim2.new(0, 240, 0, 240)
radial.Position          = UDim2.new(0.5, -120, 0.5, -120)
radial.BackgroundTransparency = 1
radial.Visible           = false
radial.Parent            = screen

-- Dark overlay when menu open
local overlay = Instance.new("Frame")
overlay.Name             = "Overlay"
overlay.Size             = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.ZIndex           = 1
overlay.Visible          = false
overlay.Parent           = screen

-- Build radial buttons
local _buttons = {}
for i, emote in ipairs(EMOTES) do
	local rad = math.rad(emote.angle)
	local cx  = 120 + math.cos(rad) * 80
	local cy  = 120 - math.sin(rad) * 80   -- Y flipped in GUI space

	local btn = Instance.new("TextButton")
	btn.Name              = "Emote_" .. emote.name
	btn.Size              = UDim2.new(0, 64, 0, 64)
	btn.Position          = UDim2.new(0, cx - 32, 0, cy - 32)
	btn.BackgroundColor3  = Color3.fromRGB(40, 40, 60)
	btn.BackgroundTransparency = 0.2
	btn.BorderSizePixel   = 0
	btn.Text              = emote.icon .. "\n" .. emote.name
	btn.TextColor3        = Color3.new(1, 1, 1)
	btn.TextScaled        = true
	btn.Font              = Enum.Font.Gotham
	btn.ZIndex            = 2
	btn.Parent            = radial

	local corner = Instance.new("UICorner")
	corner.CornerRadius   = UDim.new(0, 12)
	corner.Parent         = btn

	_buttons[i] = btn
end

-- ─── Emote logic ──────────────────────────────────────────────────────────────

local _activeAnim = nil
local _menuOpen   = false

local function _playEmote(emote)
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animController = hum:FindFirstChildOfClass("Animator")
		or hum:FindFirstChildOfClass("AnimationController")
	if not animController then return end

	if _activeAnim then
		_activeAnim:Stop()
		_activeAnim = nil
	end

	local animObj = Instance.new("Animation")
	animObj.AnimationId = emote.animId
	_activeAnim = hum:LoadAnimation(animObj)
	_activeAnim:Play()
	_activeAnim.Stopped:Connect(function() _activeAnim = nil end)

	-- Broadcast to server for replication
	RemoteEvents.EmoteFired:FireServer(emote.name)
end

local function _openMenu()
	_menuOpen = true
	overlay.Visible = true
	radial.Visible  = true
	TweenService:Create(overlay, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.5
	}):Play()
	for i, btn in ipairs(_buttons) do
		btn.Size = UDim2.new(0, 0, 0, 0)
		btn.Position = UDim2.new(0, 120, 0, 120)  -- start from center
		task.delay((i - 1) * 0.04, function()
			local rad = math.rad(EMOTES[i].angle)
			local cx  = 120 + math.cos(rad) * 80
			local cy  = 120 - math.sin(rad) * 80
			TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
				Size     = UDim2.new(0, 64, 0, 64),
				Position = UDim2.new(0, cx - 32, 0, cy - 32),
			}):Play()
		end)
	end
end

local function _closeMenu(selectedEmote)
	_menuOpen = false
	TweenService:Create(overlay, TweenInfo.new(0.15), {
		BackgroundTransparency = 1
	}):Play()
	task.delay(0.15, function()
		overlay.Visible = false
		radial.Visible  = false
	end)
	if selectedEmote then
		_playEmote(selectedEmote)
	end
end

-- ─── Input handling ───────────────────────────────────────────────────────────

local _qDown     = false
local _qHoldTime = 0
local _holdConn  = nil

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Q then return end
	_qDown     = true
	_qHoldTime = 0

	_holdConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not _qDown then
			if _holdConn then _holdConn:Disconnect(); _holdConn = nil end
			return
		end
		_qHoldTime = _qHoldTime + dt
		if _qHoldTime >= HOLD_THRESHOLD and not _menuOpen then
			if _holdConn then _holdConn:Disconnect(); _holdConn = nil end
			_openMenu()
		end
	end)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.Q then return end
	_qDown = false
	if _menuOpen then
		-- Check if mouse is hovering a button
		local mousePos = UserInputService:GetMouseLocation()
		local selected = nil
		for i, btn in ipairs(_buttons) do
			local absPos  = btn.AbsolutePosition
			local absSize = btn.AbsoluteSize
			if mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
			and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y then
				selected = EMOTES[i]
				break
			end
		end
		_closeMenu(selected)
	end
end)

-- Button clicks (for mouse users who don't hold Q)
for i, btn in ipairs(_buttons) do
	btn.Activated:Connect(function()
		if _menuOpen then
			_closeMenu(EMOTES[i])
		end
	end)
end

-- ─── Server broadcast: replay emotes on other clients ────────────────────────

RemoteEvents.EmoteFired.OnClientEvent:Connect(function(userId, emoteName)
	if userId == LocalPlayer.UserId then return end  -- already played locally
	-- Find the remote player's character and play their emote
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then return end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local emote = nil
	for _, e in ipairs(EMOTES) do
		if e.name == emoteName then emote = e; break end
	end
	if not emote then return end

	local animObj = Instance.new("Animation")
	animObj.AnimationId = emote.animId
	local track = hum:LoadAnimation(animObj)
	track:Play()
end)
