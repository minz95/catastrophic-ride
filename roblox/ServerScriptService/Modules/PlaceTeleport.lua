-- PlaceTeleport.lua
-- Sends players between the hub and the race place (Shared/Places).
-- A group goes in one TeleportAsync call, so Roblox keeps it in one server:
-- a public race server with room, or (reserve) a new private one. The
-- teleport data names the party. A failure is told to the player
-- (TravelUpdate) and `onFailed` listeners hear it (DepartureManager lets
-- them step on again). Teleports do not work in Studio: that is a failure
-- too, with its own words.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local PlaceTeleport = {}

local _failed = {}

--- `fn(player, reason)` when a player's teleport failed.
function PlaceTeleport.onFailed(fn)
	table.insert(_failed, fn)
end

local function service()
	return game:GetService("TeleportService")
end

local function fail(player, reason)
	Telemetry.record("travel_fail", { userId = player.UserId, reason = tostring(reason):sub(1, 120) })
	local studio = false
	pcall(function() studio = RunService:IsStudio() end)
	local text = studio and "Teleports only work in the live game."
		or "Couldn't get there. Try again in a moment."
	pcall(function() RemoteEvents.TravelUpdate:FireClient(player, { kind = "failed", text = text }) end)
	for _, fn in ipairs(_failed) do task.spawn(fn, player, reason) end
end

local _hooked = false
local function hook()
	if _hooked then return end
	_hooked = true
	pcall(function()
		service().TeleportInitFailed:Connect(function(player, result, message)
			fail(player, tostring(result) .. " " .. tostring(message))
		end)
	end)
end

--- Sends `players` together to `placeId`. opts: { reserve = bool, data = table }.
-- Returns true when the teleport started.
function PlaceTeleport.send(players, placeId, opts)
	opts = opts or {}
	hook()
	local list = {}
	for _, p in ipairs(players) do
		if p.Parent == Players then table.insert(list, p) end
	end
	if #list == 0 then return false end
	for _, p in ipairs(list) do
		pcall(function() RemoteEvents.TravelUpdate:FireClient(p, { kind = "leaving" }) end)
	end
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		if opts.reserve then options.ShouldReserveServer = true end
		if opts.data then options:SetTeleportData(opts.data) end
		return service():TeleportAsync(placeId, list, options)
	end)
	if not ok then
		for _, p in ipairs(list) do fail(p, err) end
	end
	return ok
end

return PlaceTeleport
