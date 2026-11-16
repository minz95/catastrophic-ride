-- RidePoseFx.client.lua
-- Holds every seated rider in their ride pose (Cosmetics "pose", player
-- attribute RidePose set by Modules/ShopHat). Runs on Stepped, after the
-- Animator wrote this frame's joints, so the pose wins over the sit
-- animation on the posed joints only (legs keep sitting). Looks only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RidePoses = require(ReplicatedStorage.Shared.RidePoses)

local _cache = setmetatable({}, { __mode = "k" })   -- [character] = { name, joints = { { j, transform } } }

local function jointsFor(character, name)
	local c = _cache[character]
	if c and c.name == name then return c.joints end
	local joints = {}
	for which, deg in pairs(RidePoses.get(name) or {}) do
		local j = RidePoses.jointOf(character, which)
		if j then table.insert(joints, { j, RidePoses.transform(RidePoses.restOf(j), deg) }) end
	end
	_cache[character] = { name = name, joints = joints }
	return joints
end

RunService.Stepped:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local name = player:GetAttribute("RidePose")
		local character = player.Character
		if type(name) == "string" and character then
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart then
				for _, jt in ipairs(jointsFor(character, name)) do
					jt[1].Transform = jt[2]
				end
			end
		end
	end
end)
