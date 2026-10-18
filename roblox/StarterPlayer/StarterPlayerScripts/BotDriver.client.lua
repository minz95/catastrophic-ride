-- BotDriver.client.lua
-- Plays the game on a harness bot client (StudioTestService multiplayer test).
-- Does nothing unless the server marks this player with the HarnessBot
-- attribute (TestHarness.MatchHarness), so normal players never run it.
--
--   FARMING  walk to items chosen by BotBrain, pick up, mash contests
--   CRAFTING submit the slots BotBrain picks from the real inventory
--   RACING   drive with Autopilot through InputSource → RacingClient's
--            normal drive loop (same code path as a keyboard)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ScriptContext     = game:GetService("ScriptContext")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer:GetAttribute("HarnessBot") then
	LocalPlayer:GetAttributeChangedSignal("HarnessBot"):Wait()
end

local Constants     = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents  = require(ReplicatedStorage.RemoteEvents)
local BotBrain      = require(ReplicatedStorage.Shared.BotBrain)
local Autopilot     = require(ReplicatedStorage.Shared.Autopilot)
local TrackGeometry = require(ReplicatedStorage.Shared.TrackGeometry)
local VehicleController = require(ReplicatedStorage.Shared.VehicleController)
local InputSource   = require(script.Parent:WaitForChild("Modules"):WaitForChild("InputSource"))

local channel = ReplicatedStorage:WaitForChild("HarnessChannel", 30)
local function report(kind, payload)
	if channel then channel:FireServer(kind, payload) end
end

ScriptContext.Error:Connect(function(message, trace, scriptInst)
	report("client_error", {
		message = message, trace = trace,
		script = scriptInst and scriptInst:GetFullName() or "?",
	})
end)

local farmProfile = BotBrain.PROFILES[LocalPlayer:GetAttribute("BotFarmProfile") or "casual"] or BotBrain.PROFILES.casual
local driverName = LocalPlayer:GetAttribute("BotDriverProfile") or "average"
local TRACKS = {
	FOREST = ReplicatedStorage.Shared.Tracks:FindFirstChild("ForestTrack"),
	OCEAN  = ReplicatedStorage.Shared.Tracks:FindFirstChild("OceanTrack"),
	SKY    = ReplicatedStorage.Shared.Tracks:FindFirstChild("SkyTrack"),
}

local phase, biome = nil, nil
local inventory = {}

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inv)
	inventory = inv or {}
end)
RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(b)
	biome = b
end)

-- ─── FARMING ──────────────────────────────────────────────────────────────────

local function visibleItems()
	local out = {}
	local maps = workspace:FindFirstChild("Maps")
	if not maps then return out end
	for _, d in ipairs(maps:GetDescendants()) do
		if d.Name == "ItemId" and d:IsA("StringValue") then
			local part = d.Parent
			local nameVal = part and part:FindFirstChild("ItemName")
			if part and part:IsA("BasePart") and nameVal then
				table.insert(out, { id = d.Value, name = nameVal.Value, x = part.Position.X, z = part.Position.Z, part = part })
			end
		end
	end
	return out
end

local function farmLoop()
	local target, contestId, presses, giveUpAt = nil, nil, 0, 0
	while phase == Constants.PHASES.FARMING do
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum then
			if contestId then
				presses += math.max(1, math.floor(farmProfile.mashRate * 0.1))
				RemoteEvents.RequestContest:InvokeServer(contestId, presses)
				if os.clock() > giveUpAt then contestId = nil end
			else
				local items = visibleItems()
				if not target or not target.part.Parent then
					target = BotBrain.pickItem(farmProfile, { x = root.Position.X, z = root.Position.Z }, items, inventory)
				end
				if target and farmProfile.mashRate > 0 then
					local d = (Vector3.new(target.x, root.Position.Y, target.z) - root.Position).Magnitude
					if d > Constants.PICKUP_RANGE * 0.7 then
						hum:MoveTo(Vector3.new(target.x, root.Position.Y, target.z))
					else
						local result = RemoteEvents.RequestPickup:InvokeServer(target.id)
						if result == "contested" then
							contestId, presses, giveUpAt = target.id, 0, os.clock() + Constants.CONTEST_DURATION + 1.5
						elseif result ~= "ok" then
							report("pickup_denied", { result = result, item = target.name })
						end
						target = nil
					end
				end
			end
		end
		task.wait(0.1)
	end
end

-- ─── CRAFTING ─────────────────────────────────────────────────────────────────

local function craft()
	task.wait(1 + math.random())
	local slots = BotBrain.chooseSlots(farmProfile, inventory, biome or "FOREST")
	if farmProfile.crafter == "none" then return end
	local result = RemoteEvents.SubmitCraft:InvokeServer(slots)
	report("craft", { result = result, slots = slots, inventory = inventory })
end

-- ─── RACING ───────────────────────────────────────────────────────────────────

local vehicle, autopilot, geo = nil, nil, nil
local raceStart = 0
local lastBoostTry = 0

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, model)
	if userId ~= LocalPlayer.UserId then return end
	vehicle = model
	local data = TRACKS[biome or "FOREST"]
	if data then
		local track = require(data)
		geo = TrackGeometry.new(track.nodes, track.width)
		autopilot = Autopilot.new(geo, Autopilot.PROFILES[driverName] or Autopilot.PROFILES.average, LocalPlayer.UserId)
	end
	raceStart = os.clock()
end)

InputSource.setOverride(function()
	if phase ~= Constants.PHASES.RACING or not vehicle or not vehicle.PrimaryPart then
		return nil
	end
	local primary = vehicle.PrimaryPart
	if not autopilot then
		return { W = true } -- no track data for this biome: just hold W
	end
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
	local v = primary.AssemblyLinearVelocity
	local isSky = primary:FindFirstChild("HoverPosition") ~= nil
	local keys, info = autopilot:update({
		x = primary.Position.X, z = primary.Position.Z, yaw = yaw,
		speed = Vector3.new(v.X, 0, v.Z).Magnitude,
		forward = v:Dot(primary.CFrame.LookVector),
		maxSpeed = seat and seat.MaxSpeed or 40,
		turnSpeed = VehicleController.turnRate(seat and seat.TurnSpeed or 1, isSky),
		t = os.clock() - raceStart,
	})
	if info.respawn then
		task.spawn(function()
			local r = RemoteEvents.RequestRespawn:InvokeServer()
			report("respawn", { result = r, s = math.floor(info.s) })
			autopilot:resetTracking()
		end)
	end
	if os.clock() - lastBoostTry > 1 and math.abs(info.err) < 0.1 then
		lastBoostTry = os.clock()
		task.spawn(function() RemoteEvents.RequestBoost:InvokeServer() end)
	end
	return keys
end)

-- ─── Phase driver ─────────────────────────────────────────────────────────────

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(newPhase)
	phase = newPhase
	if newPhase == Constants.PHASES.FARMING then
		task.spawn(farmLoop)
	elseif newPhase == Constants.PHASES.CRAFTING then
		task.spawn(craft)
	elseif newPhase ~= Constants.PHASES.RACING then
		vehicle, autopilot = nil, nil
	end
end)

report("ready", { farm = LocalPlayer:GetAttribute("BotFarmProfile"), driver = driverName })
