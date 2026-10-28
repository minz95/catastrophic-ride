-- CameraController.lua
-- Farming follow-cam, crafting orbit. (The race camera is RacingClient's.)
-- Required by GameClient.
-- Resolves: Issue #49

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local CameraController = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _mode       = "default"
local _conn       = nil
local _target     = nil   -- Part or Model to follow
local _orbitAngle = 0
local _baseFOV    = 70

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function _disconnect()
	if _conn then _conn:Disconnect(); _conn = nil end
end

local function _setScriptable(on)
	Camera.CameraType = on and Enum.CameraType.Scriptable or Enum.CameraType.Custom
end

-- ─── FARMING follow-cam ───────────────────────────────────────────────────────
-- Top-down isometric follow of the player's character.

local function _farmingLoop()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then return end

	local offset = Vector3.new(0, 40, 20)
	_conn = RunService.Heartbeat:Connect(function()
		if _mode ~= "farming" then return end
		local char2 = LocalPlayer.Character
		if not char2 then return end
		local hrp = char2:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local target = hrp.Position
		local desired = CFrame.new(target + offset, target)
		Camera.CFrame = Camera.CFrame:Lerp(desired, 0.15)
	end)
end

-- ─── CRAFTING orbit-cam ───────────────────────────────────────────────────────
-- Slowly orbits the player's vehicle / workbench area.

local function _craftingLoop(focusPoint)
	focusPoint = focusPoint or Vector3.new(0, 5, 0)
	local radius = 18
	local height = 8
	local speed  = 0.3  -- rad/s

	_conn = RunService.Heartbeat:Connect(function(dt)
		if _mode ~= "crafting" then return end
		_orbitAngle = (_orbitAngle + speed * dt) % (2 * math.pi)
		local x = focusPoint.X + math.cos(_orbitAngle) * radius
		local z = focusPoint.Z + math.sin(_orbitAngle) * radius
		local pos = Vector3.new(x, focusPoint.Y + height, z)
		Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(pos, focusPoint), 0.1)
	end)
end

-- ─── RACING ──────────────────────────────────────────────────────────────────
-- RacingClient owns the race camera (chase cam behind the car's nose, shakes,
-- boost FOV). This module stays out of it.
-- History (2026-10-28): a second chase cam ran here at the same time. For
-- SKY it aimed along the chassis' RightVector (left over from a cylinder
-- fuselage the planes no longer have), and the two cameras settled ~45°
-- apart: the plane looked to fly diagonally and steering felt wrong.

-- ─── Public API ──────────────────────────────────────────────────────────────

function CameraController.setMode(mode, arg)
	_disconnect()
	_mode = mode

	if mode == "default" then
		_setScriptable(false)
		Camera.FieldOfView = _baseFOV

	elseif mode == "farming" then
		_setScriptable(true)
		Camera.FieldOfView = 60
		_farmingLoop()

	elseif mode == "crafting" then
		_setScriptable(true)
		Camera.FieldOfView = _baseFOV
		-- arg: Vector3 focus point (vehicle spawn area)
		_craftingLoop(arg)

	elseif mode == "racing" then
		-- arg: vehicle Model; the camera itself is RacingClient's
		_target = arg

	elseif mode == "results" then
		_setScriptable(false)
		TweenService:Create(Camera, TweenInfo.new(1, Enum.EasingStyle.Quad), {
			FieldOfView = 50
		}):Play()
	end
end

function CameraController.updateVehicle(vehicle)
	_target = vehicle
	-- If currently in racing mode, the loop already reads _target
end

function CameraController.shake(intensity, duration)
	local steps = math.floor(duration / 0.05)
	task.spawn(function()
		for _ = 1, steps do
			local rx = (math.random() - 0.5) * intensity
			local ry = (math.random() - 0.5) * intensity
			Camera.CFrame = Camera.CFrame * CFrame.Angles(rx, ry, 0)
			task.wait(0.05)
		end
	end)
end

return CameraController
