-- Notice.lua (client)
-- Roblox's corner notification (StarterGui SendNotification) for "Challenge
-- done!" and "Friend joined!". Held back while racing and shown when the
-- race is over: on a phone the popup lands over the BOOST / DRIFT buttons
-- and takes the taps meant for them (challenges finish mid-race: boosts,
-- drift turbos, the finish).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Notice = {}

Notice.HOLD_IN = { RACING = true }

local _held = {}
local _watching = false

local function send(n)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = n.title, Text = n.text, Duration = n.duration or 5 })
	end)
end

--- True when a notice now would be held (pure on the phase name).
function Notice.holds(phase)
	return Notice.HOLD_IN[phase] == true
end

local function watch()
	if _watching then return end
	_watching = true
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		if Notice.holds(ReplicatedStorage:GetAttribute("Phase")) then return end
		local list = _held
		_held = {}
		for i, n in ipairs(list) do
			task.delay((i - 1) * 0.6, send, n)
		end
	end)
end

function Notice.show(title, text, duration)
	watch()
	local n = { title = title, text = text, duration = duration }
	if Notice.holds(ReplicatedStorage:GetAttribute("Phase")) then
		table.insert(_held, n)
	else
		send(n)
	end
end

return Notice
