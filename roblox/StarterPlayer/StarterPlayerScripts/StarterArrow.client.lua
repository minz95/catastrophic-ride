-- StarterArrow.client.lua
-- Points at your starter junk (Shared/StarterItems: FarmingManager puts a
-- few items in front of you when FARMING starts): a big bouncing arrow over
-- the nearest one you have not picked up, until all are gone, the phase
-- ends or Constants.STARTER.RESERVE runs out. With a friend in the server
-- one of them is a rarer bonus, and a corner notice says so.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Notice       = require(ReplicatedStorage.Shared.Notice)

local LocalPlayer = Players.LocalPlayer

local ARROW_NAME = "StarterArrow"
local BOUNCE = 0.8     -- studs up and down
local SPEED  = 5       -- radians a second
-- studs over the item: low, so it stays under the FARMING toast at the top
-- of the screen (Studio first-minute: at 5 it hid behind the toast)
local HEIGHT = 3
local TURN_BACK, TURN_UP = 14, 7   -- camera behind / over you when it turns to them

local _parts = {}      -- [itemId] = primary part of a starter item still out
local _bonus = {}      -- [itemId] = true for the friend bonus item
local _until = 0
local _arrow = nil     -- BillboardGui
local _arrowOn = nil   -- part it hangs on

local function makeArrow()
	local gui = Instance.new("BillboardGui")
	gui.Name           = ARROW_NAME
	gui.Size           = UDim2.new(0, 110, 0, 96)
	gui.AlwaysOnTop    = true
	gui.LightInfluence = 0
	gui.MaxDistance    = 200
	local tip = Instance.new("TextLabel")
	tip.Name                   = "Tip"
	tip.Size                   = UDim2.new(1, 0, 0, 28)
	tip.BackgroundTransparency = 1
	tip.Text                   = "GRAB ME!"
	tip.TextColor3             = Color3.fromRGB(255, 230, 80)
	tip.TextStrokeTransparency = 0
	tip.TextScaled             = true
	tip.Font                   = Enum.Font.GothamBlack
	tip.Parent                 = gui
	local arrow = Instance.new("TextLabel")
	arrow.Name                   = "Arrow"
	arrow.Size                   = UDim2.new(1, 0, 0, 68)
	arrow.Position               = UDim2.new(0, 0, 0, 28)
	arrow.BackgroundTransparency = 1
	arrow.Text                   = "▼"
	arrow.TextColor3             = Color3.fromRGB(255, 220, 40)
	arrow.TextStrokeColor3       = Color3.fromRGB(90, 50, 0)
	arrow.TextStrokeTransparency = 0
	arrow.TextScaled             = true
	arrow.Font                   = Enum.Font.GothamBlack
	arrow.Parent                 = gui
	return gui
end

local function clear()
	_parts, _bonus = {}, {}
	if _arrow then _arrow:Destroy(); _arrow = nil end
	_arrowOn = nil
end

local function findPart(itemId)
	for _, v in ipairs(workspace:GetDescendants()) do
		if v.Name == "ItemId" and v:IsA("StringValue") and v.Value == itemId and v.Parent and v.Parent:IsA("BasePart") then
			return v.Parent
		end
	end
	return nil
end

-- Turn you and the camera toward your starter items: the server puts them
-- in front of your avatar, but after the teleport to the farm the camera
-- often looked at your face, and the items lay behind it under the bag
-- (Studio Device Simulator, iPhone XR, 2026-11-11). Your own character is
-- yours to move on this client; the camera is turned as below.
local function faceStarters()
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not root or not cam then return end
	local sum, n = Vector3.zero, 0
	for _, part in pairs(_parts) do
		if part.Parent then sum += part.Position; n += 1 end
	end
	if n == 0 then return end
	local centre = sum / n
	local flat = Vector3.new(centre.X - root.Position.X, 0, centre.Z - root.Position.Z)
	if flat.Magnitude < 1 then return end
	local dir = flat.Unit
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	-- the default camera keeps its own yaw: a CFrame set while it runs was
	-- back where it was a second later. Hand it over for a frame and back:
	-- it starts again from the CFrame it finds.
	if cam.CameraType ~= Enum.CameraType.Custom then return end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(root.Position - dir * TURN_BACK + Vector3.new(0, TURN_UP, 0), centre)
	RunService.RenderStepped:Wait()
	cam.CameraType = Enum.CameraType.Custom
end

RemoteEvents.StarterItems.OnClientEvent:Connect(function(list, friendBonus)
	clear()
	if type(list) ~= "table" then return end
	_until = os.clock() + Constants.STARTER.RESERVE
	local function take(e)
		local part = findPart(e.itemId)
		if part then
			_parts[e.itemId] = part
			_bonus[e.itemId] = e.bonus == true
		end
		return part ~= nil
	end
	for _, e in ipairs(list) do
		if type(e) == "table" and type(e.itemId) == "string" and not take(e) then
			-- the model may arrive a moment after the event
			task.delay(0.5, take, e)
		end
	end
	task.delay(0.7, faceStarters)   -- after the late models (above) arrived
	if friendBonus then
		Notice.show("Friend bonus!", "A friend is here: +1 rare junk next to you", 6)
	end
end)

RemoteEvents.ItemPickedUp.OnClientEvent:Connect(function(itemId)
	_parts[itemId] = nil
end)

RunService.RenderStepped:Connect(function()
	if not next(_parts) and not _arrow then return end
	if os.clock() > _until or ReplicatedStorage:GetAttribute("Phase") ~= Constants.PHASES.FARMING then
		clear()
		return
	end
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local best, bestD, bestId = nil, math.huge, nil
	for id, part in pairs(_parts) do
		if not part.Parent then
			_parts[id] = nil
		else
			local d = root and (part.Position - root.Position).Magnitude or 0
			if d < bestD then best, bestD, bestId = part, d, id end
		end
	end
	if not best then clear() return end
	if not _arrow then _arrow = makeArrow() end
	if _arrowOn ~= best then
		_arrowOn = best
		_arrow.Adornee = best
		_arrow.Parent = best
		_arrow.Tip.Text = _bonus[bestId] and "FRIEND BONUS!" or "GRAB ME!"
	end
	_arrow.StudsOffset = Vector3.new(0, HEIGHT + math.sin(os.clock() * SPEED) * BOUNCE, 0)
end)
