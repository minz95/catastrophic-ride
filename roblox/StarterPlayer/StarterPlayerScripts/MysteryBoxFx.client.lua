-- MysteryBoxFx.client.lua
-- Item boxes on the race track (server: Modules/MysteryBoxes, tag
-- "MysteryBox"): every client turns and bobs them and cycles their colour
-- (a server spin would replicate every frame), pops a box when it is taken
-- (attribute Taken) and chimes when you got a power.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundFx = require(ReplicatedStorage.Shared.SoundFx)

local LocalPlayer = Players.LocalPlayer
local TAG = "MysteryBox"

local _boxes = {}   -- [part] = { base = CFrame, phase }

local function pop(part)
	local ball = Instance.new("Part")
	ball.Name = "BoxPop"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(3, 3, 3)
	ball.CFrame = part.CFrame
	ball.Anchored, ball.CanCollide, ball.CanTouch, ball.CanQuery, ball.CastShadow = true, false, false, false, false
	ball.Material = Enum.Material.Neon
	ball.Color = part.Color
	ball.Transparency = 0.2
	ball.Parent = workspace
	TweenService:Create(ball, TweenInfo.new(0.35), { Size = Vector3.new(11, 11, 11), Transparency = 1 }):Play()
	task.delay(0.4, function() ball:Destroy() end)
end

local function add(part)
	if not part:IsA("BasePart") or _boxes[part] then return end
	_boxes[part] = { base = part.CFrame, phase = math.random() * math.pi * 2 }
	part:GetAttributeChangedSignal("Taken"):Connect(function()
		if part:GetAttribute("Taken") then pop(part) end
	end)
end

for _, p in ipairs(CollectionService:GetTagged(TAG)) do add(p) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(p) _boxes[p] = nil end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for part, b in pairs(_boxes) do
		if not part.Parent then
			_boxes[part] = nil
		elseif not part:GetAttribute("Taken") then
			local bob = math.sin(t * 2.2 + b.phase) * 0.5
			part.CFrame = CFrame.new(b.base.Position + Vector3.new(0, bob, 0))
				* CFrame.Angles(math.rad(20), t * 1.6 + b.phase, math.rad(10))
			part.Color = Color3.fromHSV((t * 0.15 + b.phase / 6.28) % 1, 0.65, 1)
		end
	end
end)

LocalPlayer:GetAttributeChangedSignal("BoxPower"):Connect(function()
	if LocalPlayer:GetAttribute("BoxPower") then
		pcall(SoundFx.play, "ITEM_PICKUP_RARE")
	end
end)
