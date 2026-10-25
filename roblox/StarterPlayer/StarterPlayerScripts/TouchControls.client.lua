-- TouchControls.client.lua
-- On-screen buttons for phones and tablets (no keyboard): they press the same
-- keys as the keyboard through Shared/KeyInput, so FarmingClient and
-- RacingClient need nothing extra. Steering comes from Roblox's own thumbstick
-- (the seat's ThrottleFloat / SteerFloat, read by RacingClient).
--   FARMING: GRAB (E; hold near a player to steal, tap fast in a contest),
--            PUNCH (F), GUARD (hold G), DROP (Q), SMOKE (T, with a gadget)
--   RACING:  DRIFT (hold Shift), BOOST (F), ITEM (E), RESET (R)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

if not UserInputService.TouchEnabled then return end

local Constants    = require(ReplicatedStorage.Shared.Constants)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "TouchControls" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name         = "TouchControls"
screen.ResetOnSpawn = false
screen.DisplayOrder = 10
screen.Parent       = LocalPlayer.PlayerGui

-- Buttons sit right of centre, above Roblox's jump button area.
local SIZE = 74
local LAYOUT = {
	FARMING = {
		{ text = "GRAB",  key = Enum.KeyCode.E, col = 1, row = 1, color = Color3.fromRGB(60, 170, 90) },
		{ text = "PUNCH", key = Enum.KeyCode.F, col = 2, row = 1, color = Color3.fromRGB(210, 80, 60) },
		{ text = "GUARD", key = Enum.KeyCode.G, col = 2, row = 2, color = Color3.fromRGB(70, 110, 200) },
		{ text = "DROP",  key = Enum.KeyCode.X, col = 1, row = 2, color = Color3.fromRGB(110, 110, 125) },
		{ text = "SMOKE", key = Enum.KeyCode.T, col = 1, row = 0, color = Color3.fromRGB(90, 90, 100), gadget = true },
	},
	RACING = {
		{ text = "DRIFT", key = Enum.KeyCode.LeftShift, col = 2, row = 1, color = Color3.fromRGB(230, 160, 35) },
		{ text = "BOOST", key = Enum.KeyCode.F, col = 1, row = 1, color = Color3.fromRGB(60, 150, 240) },
		{ text = "ITEM",  key = Enum.KeyCode.E, col = 1, row = 2, color = Color3.fromRGB(170, 80, 220) },
		{ text = "RESET", key = Enum.KeyCode.R, col = 2, row = 2, color = Color3.fromRGB(110, 110, 125), small = true },
	},
}

local _sets = {}
for phase, list in pairs(LAYOUT) do
	local frame = Instance.new("Frame")
	frame.Name                   = phase
	frame.Size                   = UDim2.new(0, SIZE * 2 + 12, 0, SIZE * 2 + 12)
	frame.Position               = UDim2.new(1, -(SIZE * 2 + 12) - 24, 1, -(SIZE * 2 + 12) - 150)
	frame.BackgroundTransparency = 1
	frame.Visible                = false
	frame.Parent                 = screen
	for _, b in ipairs(list) do
		local btn = Instance.new("TextButton")
		btn.Name                   = b.text
		local s = b.small and SIZE * 0.75 or SIZE
		btn.Size                   = UDim2.new(0, s, 0, s)
		btn.Position               = UDim2.new(0, (b.col - 1) * (SIZE + 12) + (SIZE - s) / 2, 0, (b.row - 1) * (SIZE + 12) + (SIZE - s) / 2)
		btn.BackgroundColor3       = b.color
		btn.BackgroundTransparency = 0.15
		btn.Text                   = b.text
		btn.TextColor3             = Color3.new(1, 1, 1)
		btn.TextScaled             = true
		btn.Font                   = Enum.Font.GothamBlack
		btn.AutoButtonColor        = true
		btn.Parent                 = frame
		if b.gadget then
			-- only with a gadget equipped (FarmingManager sets the attribute)
			local function show() btn.Visible = LocalPlayer:GetAttribute("Gadget") ~= nil end
			LocalPlayer:GetAttributeChangedSignal("Gadget"):Connect(show)
			show()
		end
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.Parent = btn
		local down = false
		btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if down then return end
				down = true
				KeyInput.press(b.key)
			end
		end)
		btn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if not down then return end
				down = false
				KeyInput.release(b.key)
			end
		end)
	end
	_sets[phase] = frame
end

local function onPhase(phase)
	for name, frame in pairs(_sets) do
		frame.Visible = (name == phase) and LocalPlayer:GetAttribute("Spectating") ~= true
	end
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(function()
	onPhase(ReplicatedStorage:GetAttribute("Phase"))
end)
onPhase(ReplicatedStorage:GetAttribute("Phase") or Constants.PHASES.LOBBY)
