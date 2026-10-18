-- PlaytestMarker.client.lua
-- Playtest feedback keys (Studio, or test servers with the PlaytestMarkers
-- attribute on ReplicatedStorage): M = "this is frustrating", N = "this is fun".
-- The server logs the spot (PlaytestReporter); the end-of-round report lists
-- markers per track section. Does nothing in live games.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")

if not (RunService:IsStudio() or ReplicatedStorage:GetAttribute("PlaytestMarkers") == true) then
	return
end

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local KEYS = {
	[Enum.KeyCode.M] = { note = "bad", text = "Marked: frustrating here" },
	[Enum.KeyCode.N] = { note = "fun", text = "Marked: fun here" },
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local k = KEYS[input.KeyCode]
	if not k then return end
	RemoteEvents.PlaytestMark:FireServer(k.note)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Playtest", Text = k.text, Duration = 1.5 })
	end)
end)
