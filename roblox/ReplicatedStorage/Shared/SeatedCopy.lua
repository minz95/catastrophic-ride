-- SeatedCopy.lua
-- A still copy of an avatar sitting on a vehicle's seat, for pictures in a
-- ViewportFrame's WorldModel (the crafting showroom, the lobby line-up), and
-- the vehicle's HEAD item moved onto that copy's head. Client side.

local SeatedCopy = {}

-- Bends a joint by `rot` around the joint (Motor6D, or the AnimationConstraint
-- some avatars use; see FarmFx).
function SeatedCopy.bend(char, jointName, rot)
	local j = char:FindFirstChild(jointName, true)
	local obj, prop
	if j and j:IsA("Motor6D") then obj, prop = j, "C0"
	elseif j and j:IsA("AnimationConstraint") and j.Attachment0 then obj, prop = j.Attachment0, "CFrame"
	else return end
	local c0 = obj[prop]
	local pos = c0.Position
	obj[prop] = CFrame.new(pos) * rot * (c0 - pos)
end

--- A copy of `char` sitting on `seat`, parented to `parent`; nil if it
-- cannot be copied.
function SeatedCopy.rider(seat, parent, char)
	if not char then return nil end
	local was = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not copy then return nil end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ForceField") or d:IsA("Sound") then d:Destroy() end
	end
	local root = copy:FindFirstChild("HumanoidRootPart")
	if not root then copy:Destroy() return nil end
	root.Anchored = true
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	local q = math.pi / 2
	SeatedCopy.bend(copy, "LeftHip", CFrame.Angles(q, 0, 0))
	SeatedCopy.bend(copy, "RightHip", CFrame.Angles(q, 0, 0))
	SeatedCopy.bend(copy, "LeftKnee", CFrame.Angles(-q, 0, 0))
	SeatedCopy.bend(copy, "RightKnee", CFrame.Angles(-q, 0, 0))
	SeatedCopy.bend(copy, "LeftShoulder", CFrame.Angles(q * 0.6, 0, 0))
	SeatedCopy.bend(copy, "RightShoulder", CFrame.Angles(q * 0.6, 0, 0))
	copy:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + root.Size.Y / 2, 0))
	copy.Parent = parent
	return copy
end

--- The HEAD item is worn as a hat (VehicleBuilder.wearHat): onto the copy's head.
function SeatedCopy.wearHat(vehicle, rider)
	local head = rider and rider:FindFirstChild("Head")
	if not head then return end
	for _, c in ipairs(vehicle:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") and c.PrimaryPart then
			local base = c.PrimaryPart.Size.Y / 2
			c:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - (c:GetAttribute("HatSink") or 0) + base, 0))
		end
	end
end

return SeatedCopy
