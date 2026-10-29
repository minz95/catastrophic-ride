-- TauntFx.client.lua
-- Taunts (shop "taunt", key Q in RACING): the server sends TauntShown with
-- the part to hang it on (the car, or the head); every client draws a
-- speech bubble there that pops in, wobbles, bobs and fades
-- (Constants.TAUNT.SECONDS). One bubble per car: a new taunt replaces the
-- old. A driver the taunter is ahead of (within BEHIND_RANGE) also gets it
-- on screen with the taunter's name: that is the point of a taunt.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

local W, H = 170, 44   -- px: the bubble (EffectLook.TEXT words sit lower)
local BEHIND_RANGE = 220

-- My car's seat while I race (nil otherwise).
local function mySeat()
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	return seat and seat:IsA("VehicleSeat") and seat or nil
end

local _line
local function screenLine(name, emoji, text)
	if not _line or not _line.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "TauntLine"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 6
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
		_line = Instance.new("TextLabel")
		-- bottom right, over the speedometer: the top centre is the
		-- checkpoint toast's and the effect words' (Studio ui-layout
		-- 2026-10-30: it sat on both, depending on the window)
		_line.AnchorPoint = Vector2.new(1, 1)
		_line.Position = UDim2.new(1, -12, 1, -140)
		_line.Size = UDim2.new(0, 320, 0, 36)
		_line.BackgroundColor3 = Color3.new(1, 1, 1)
		_line.BackgroundTransparency = 0.1
		_line.TextColor3 = Color3.fromRGB(30, 30, 40)
		_line.TextScaled = true
		_line.Font = Enum.Font.GothamBlack
		_line.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = _line
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = _line
	end
	_line.Text = string.format("%s %s: %s", emoji, name, text)
	_line.Visible = true
	_line.Rotation = -6
	TweenService:Create(_line, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true),
		{ Rotation = 6 }):Play()
	local token = tostring(os.clock())
	_line:SetAttribute("Token", token)
	task.delay(Constants.TAUNT.SECONDS, function()
		if _line:GetAttribute("Token") == token then _line.Visible = false; _line.Rotation = 0 end
	end)
end

RemoteEvents.TauntShown.OnClientEvent:Connect(function(userId, part, emoji, text, name)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	local old = part:FindFirstChild("TauntBubble")
	if old then old:Destroy() end
	local seconds = Constants.TAUNT.SECONDS
	local bb = Instance.new("BillboardGui")
	bb.Name = "TauntBubble"
	bb.Size = UDim2.new(0, W, 0, H)
	bb.StudsOffset = Vector3.new(0, 7.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Adornee = part
	local bubble = Instance.new("TextLabel")
	bubble.Size = UDim2.fromScale(0.2, 0.2)
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.BackgroundColor3 = userId == LocalPlayer.UserId and Color3.fromRGB(255, 230, 120) or Color3.new(1, 1, 1)
	bubble.BackgroundTransparency = 0.05
	bubble.Text = tostring(emoji or "") .. " " .. tostring(text or "")
	bubble.TextColor3 = Color3.fromRGB(30, 30, 40)
	bubble.TextScaled = true
	bubble.Font = Enum.Font.GothamBlack
	bubble.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = bubble
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	pad.Parent = bubble
	bb.Parent = part
	-- pop in, bob, fade out
	TweenService:Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1) }):Play()
	TweenService:Create(bb, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 8.3, 0) }):Play()
	task.delay(seconds * 0.75, function()
		if bubble.Parent then
			TweenService:Create(bubble, TweenInfo.new(seconds * 0.25),
				{ TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
	-- wobble like a wagging finger
	bubble.Rotation = -8
	TweenService:Create(bubble, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 8 }):Play()
	Debris:AddItem(bb, seconds)

	-- on the screens of the drivers behind
	local seat = userId ~= LocalPlayer.UserId and mySeat()
	if seat then
		local d = part.Position - seat.Position
		if d.Magnitude < BEHIND_RANGE and d:Dot(seat.CFrame.LookVector) > 0 then
			screenLine(tostring(name or "Someone"), tostring(emoji or ""), tostring(text or ""))
		end
	end
end)
