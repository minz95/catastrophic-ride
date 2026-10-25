-- SeatedRider.lua
-- A plain avatar sitting in a vehicle's seat, legs bent like the sit pose.
-- Used for race bots (Modules/RaceBots: the car has a driver like a
-- player's) and by the Studio gallery / store pictures (TestHarness).

local Players = game:GetService("Players")

local SeatedRider = {}

-- Bends a joint by `rot` around the joint, in its parent part's axes. Avatars
-- may have AnimationConstraint joints instead of Motor6D (see FarmFx).
function SeatedRider.bend(char, jointName, rot)
	local j = char:FindFirstChild(jointName, true)
	local obj, prop
	if j and j:IsA("Motor6D") then obj, prop = j, "C0"
	elseif j and j:IsA("AnimationConstraint") and j.Attachment0 then obj, prop = j.Attachment0, "CFrame"
	else return false end
	local c0 = obj[prop]
	local p = c0.Position
	obj[prop] = CFrame.new(p) * rot * (c0 - p)
	return true
end

-- Root + head + Humanoid, where an R15 avatar cannot be made (offline tests).
local function minimalRig(shirt)
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = shirt
	root.Parent = char
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = char
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, head
	w.Parent = root
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = root
	return char
end

--- Seats a new avatar in `model`'s VehicleSeat, parented to `folder`.
-- opts.passenger: massless, no collision or touch (a race bot's driver must
-- not change how its car handles or set off Touched handlers);
-- opts.fallback: a minimal rig when an R15 avatar cannot be made.
-- Returns the character and the seat, or nil.
function SeatedRider.seat(model, folder, shirt, opts)
	opts = opts or {}
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then return nil end
	shirt = shirt or Color3.fromRGB(60, 140, 230)
	local ok, char = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = Color3.fromRGB(255, 220, 180)
		desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
		desc.TorsoColor = shirt
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(60, 60, 80), Color3.fromRGB(60, 60, 80)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not char then
		if not opts.fallback then return nil end
		char = minimalRig(shirt)
	end
	char.Name = "Rider"
	local hum = char:FindFirstChildOfClass("Humanoid")
	pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
	if opts.passenger then
		-- a server-side NPC: never get up, never die of a bump
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
		hum.JumpHeight = 0
	end
	local animate = char:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			if opts.passenger then
				p.Massless = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
			end
		end
	end
	char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	char.Parent = folder
	seat:Sit(hum)
	-- the pose: thighs forward, shins down, hands on the knees
	local q = math.pi / 2
	SeatedRider.bend(char, "LeftHip", CFrame.Angles(q, 0, 0))
	SeatedRider.bend(char, "RightHip", CFrame.Angles(q, 0, 0))
	SeatedRider.bend(char, "LeftKnee", CFrame.Angles(-q, 0, 0))
	SeatedRider.bend(char, "RightKnee", CFrame.Angles(-q, 0, 0))
	SeatedRider.bend(char, "LeftShoulder", CFrame.Angles(q * 0.6, 0, 0))
	SeatedRider.bend(char, "RightShoulder", CFrame.Angles(q * 0.6, 0, 0))
	return char, seat
end

return SeatedRider
