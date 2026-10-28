-- FarmRescue.lua
-- The farm's safety net (FARMING only). Walls close every farm
-- (Shared/FarmBounds, Maps/FarmKit), but anyone whose character still ends
-- up off it (under the floor, flung high over it, past a wall, or back in the
-- lobby after a respawn) is put on the nearest farm spawn marker, players and
-- FarmBots NPCs alike. Each rescue is logged as Telemetry "farm_rescue"
-- { userId, bot, reason = "fell" | "flung" | "out", x, y, z }.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FarmBounds = require(ReplicatedStorage.Shared.FarmBounds)
local SessionManager = require(ServerScriptService.SessionManager)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local FarmRescue = {}

local _conn = nil

--- The spot (Vector3) a rescued character at `pos` goes to: over the
-- nearest spawn marker.
function FarmRescue.spotFor(biome, pos)
	local best, bestD
	for _, p in ipairs(FarmBounds.spawnPoints(biome)) do
		local d = (pos and Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude) or 0
		if not bestD or d < bestD then best, bestD = p, d end
	end
	return best + Vector3.new(0, FarmBounds.SPAWN_LIFT, 0)
end

local function rootOf(actor)
	local char = actor.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, root
end

--- One pass over every player and bot. Returns how many were put back.
function FarmRescue.check(biome)
	local n = 0
	for _, actor in ipairs(SessionManager.actors()) do
		local char, root = rootOf(actor)
		if root then
			local pos = root.Position
			local reason = FarmBounds.offFarm(biome, pos)
			if reason then
				local spot = FarmRescue.spotFor(biome, pos)
				pcall(function()
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end)
				local moved = pcall(function() char:PivotTo(CFrame.new(spot)) end)
				if not moved or (root.Position - spot).Magnitude > 1 then root.CFrame = CFrame.new(spot) end
				n += 1
				Telemetry.record("farm_rescue", {
					userId = actor.UserId, bot = SessionManager.isBot(actor) or nil, reason = reason,
					x = math.floor(pos.X), y = math.floor(pos.Y), z = math.floor(pos.Z),
				})
			end
		end
	end
	return n
end

--- Checks every FarmBounds.CHECK_EVERY s from GRACE s on, until stop().
function FarmRescue.start(biome)
	FarmRescue.stop()
	local t, nextAt = 0, FarmBounds.GRACE
	_conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t < nextAt then return end
		nextAt = t + FarmBounds.CHECK_EVERY
		local ok, err = pcall(FarmRescue.check, biome)
		if not ok then warn("[FarmRescue] " .. tostring(err)) end
	end)
end

function FarmRescue.stop()
	if _conn then _conn:Disconnect(); _conn = nil end
end

return FarmRescue
