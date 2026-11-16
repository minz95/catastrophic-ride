-- RidePoses.lua
-- How an avatar sits on its ride (Cosmetics "pose", earned through
-- Shared/Achievements). Angles in degrees about the parent part's axes
-- (X right, Y up, -Z forward), the same convention as FarmFx's poses:
-- an arm hanging down turns forward with +X, up over the head at ~170;
-- about Z a right arm goes out to the side with +, a left arm with -
-- (CFrame.Angles(x, y, z) turns about Z first). An elbow turns in its
-- upper arm's axes.
-- StarterPlayerScripts/RidePoseFx holds them on every seated rider whose
-- player has the attribute RidePose; still copies (SeatedCopy) take them
-- through `applyStill`.

local RidePoses = {}

RidePoses.JOINTS = {
	right      = { "RightShoulder", "Right Shoulder" },
	left       = { "LeftShoulder", "Left Shoulder" },
	rightElbow = { "RightElbow" },   -- R15 only
	leftElbow  = { "LeftElbow" },
	waist      = { "Waist", "RootJoint" },
}

RidePoses.POSES = {
	-- both arms straight up, a roller-coaster rider
	handsup = { right = { 165, 0, 15 }, left = { 165, 0, -15 } },
	-- leaning back, one hand behind the head, the other arm resting out
	lean = { waist = { 14, 0, 0 }, right = { 170, 0, 20 }, rightElbow = { -100, 0, -60 }, left = { 20, 0, -50 } },
	-- arms out to the sides, elbows up: a strongman flex
	flex = { right = { 0, 0, 90 }, left = { 0, 0, -90 }, rightElbow = { 0, 0, 100 }, leftElbow = { 0, 0, -100 } },
}

local function rot(deg)
	return CFrame.Angles(math.rad(deg[1]), math.rad(deg[2]), math.rad(deg[3]))
end

--- The pose's joints: { [jointName] = degrees }, or nil.
function RidePoses.get(name)
	return name and RidePoses.POSES[name] or nil
end

--- The Transform that turns a joint (rest C0 `c0`) by `deg` about its
-- parent part's axes (Transform is applied in C0's own axes).
function RidePoses.transform(c0, deg)
	local r0 = c0 - c0.Position
	return r0:Inverse() * rot(deg) * r0
end

--- The joint objects of `character` for one pose key (Motor6D or
-- AnimationConstraint), or nil.
function RidePoses.jointOf(character, which)
	for _, name in ipairs(RidePoses.JOINTS[which] or {}) do
		local j = character:FindFirstChild(name, true)
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then return j end
	end
	return nil
end

--- Rest frame of a joint: Motor6D C0 or the AnimationConstraint's
-- Attachment0 CFrame.
function RidePoses.restOf(j)
	if j:IsA("Motor6D") then return j.C0 end
	return j.Attachment0 and j.Attachment0.CFrame or CFrame.new()
end

--- Poses a still copy (no Animator: viewports, the lobby) by setting
-- Transform once. Returns how many joints it set.
function RidePoses.applyStill(character, name)
	local pose = RidePoses.get(name)
	if not pose or not character then return 0 end
	local n = 0
	for which, deg in pairs(pose) do
		local j = RidePoses.jointOf(character, which)
		if j then
			pcall(function() j.Transform = RidePoses.transform(RidePoses.restOf(j), deg) end)
			n += 1
		end
	end
	return n
end

return RidePoses
