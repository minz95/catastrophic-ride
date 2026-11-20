-- TrackFocus.client.lua
-- While you drive the Junk Grand Prix or ride the Alpine Luge (player
-- attribute GpCar / LugeCart, set by GpManager / LugeManager), the town's
-- screens step aside: the lobby countdown and NEXT TRACK, the players
-- list, SHOP / ITEMS, the key strip, INVITE, the music button (playtest
-- 2026-11-20: "Next track shows over the ride; the speedometer and all the
-- rest cover the road"). Only the ride's own HUD (GpHud, LugeHud) and any
-- ScreenGui with the attribute KeepOnTrack stay. What this turned off is
-- turned back on when the ride ends.

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local TrackFocus = {}
TrackFocus.KEEP = { GpHud = true, LugeHud = true }
TrackFocus.ATTRIBUTES = { "GpCar", "LugeCart" }

local _hidden = {}   -- ScreenGui → true (we turned it off)

local function riding()
	for _, a in ipairs(TrackFocus.ATTRIBUTES) do
		if LocalPlayer:GetAttribute(a) then return true end
	end
	return false
end

local function hideAll(pg)
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and not TrackFocus.KEEP[g.Name] and not g:GetAttribute("KeepOnTrack") and g.Enabled then
			g.Enabled = false
			_hidden[g] = true
		end
	end
end

local function restore()
	for g in pairs(_hidden) do
		if g.Parent then g.Enabled = true end
	end
	_hidden = {}
end

task.spawn(function()
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	local was = false
	while true do
		local now = riding()
		if now then
			-- (again every tick: the town's scripts turn their screens on by phase)
			hideAll(pg)
		elseif was then
			restore()
		end
		was = now
		task.wait(0.25)
	end
end)
