-- TauntFx.client.lua
-- Taunts (shop "taunt", key Q in RACING): the server sends TauntShown with
-- the part to hang it on (the car, or the head); every client draws a
-- speech bubble there that pops in, bobs and fades (Constants.TAUNT.SECONDS).
-- One bubble per car: a new taunt replaces the old.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

local W, H = 150, 40   -- px: the bubble (EffectLook.TEXT words sit lower)

RemoteEvents.TauntShown.OnClientEvent:Connect(function(userId, part, emoji, text)
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
	Debris:AddItem(bb, seconds)
end)
