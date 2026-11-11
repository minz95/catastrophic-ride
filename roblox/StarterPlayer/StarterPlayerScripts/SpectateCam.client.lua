-- SpectateCam.client.lua
-- Someone who joined during a race (attribute "Spectating", SessionManager)
-- watches it: the camera rides behind a racing car (the race camera's
-- view), and a click or tap moves it to the next car. Before, they looked
-- at the lobby for up to two minutes with one line of text: a new player's
-- first minute (2026-11-12, "why do people leave at once?").

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local _on = false
local _cars, _index, _listAt = {}, 1, 0

local function watching()
	return LocalPlayer:GetAttribute("Spectating") == true
		and ReplicatedStorage:GetAttribute("Phase") == Constants.PHASES.RACING
end

local function refresh()
	_cars = {}
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m.Name:sub(1, 8) == "Vehicle_" and m.PrimaryPart then
			table.insert(_cars, m)
		end
	end
	if _index > #_cars then _index = 1 end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not _on then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		refresh()
		_index = #_cars > 0 and (_index % #_cars + 1) or 1
	end
end)

RunService.RenderStepped:Connect(function()
	if not watching() then
		if _on then
			_on = false
			Camera.CameraType = Enum.CameraType.Custom
		end
		return
	end
	local t = os.clock()
	if t - _listAt > 2 then _listAt = t; refresh() end
	local car = _cars[_index]
	local primary = car and car.Parent and car.PrimaryPart
	if not primary then refresh(); return end
	if not _on then
		_on = true
		Camera.CameraType = Enum.CameraType.Scriptable
	end
	local look = primary.CFrame.LookVector
	local vel = primary.AssemblyLinearVelocity.Magnitude
	local eye = primary.Position - look * (14 + vel * 0.04) + Vector3.new(0, 6 + vel * 0.02, 0)
	Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(eye, primary.Position + Vector3.new(0, 1.5, 0)), 0.1)
end)
