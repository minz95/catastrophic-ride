-- RemoteEvents/init.lua
-- Creates all RemoteEvent and RemoteFunction instances at runtime.
-- Require this module on both server and client to get the events table.
-- Resolves: Issue #5
--
-- Payload reference (inline documentation):
--   PhaseChanged        → (phaseName: string)
--   BiomeSelected       → (biome: string)
--   ItemPickedUp        → (itemId: string, pickerUserId: number)
--   InventoryUpdated    → (inventory: {itemName: string}[])  -- fires to owner only
--   ContestUpdate       → (itemId: string, p1: {userId,count}, p2: {userId,count})
--   ContestResult       → (itemId: string, winnerUserId: number)
--   StealAttempt        → (thiefName: string)                -- fires to victim only
--   ItemStolen          → (thiefName: string, victimName: string, itemName: string)
--   VehicleSpawned      → (userId: number, vehicleModel: Model)
--   PlayerPositionSync  → ({userId: number, progress: number, rank: number}[])
--   AbilityActivated    → (userId: number, itemName: string, targetIds: number[]|nil)
--   AbilityDenied       → (reason: string)                   -- fires to activator only
--   EmoteFired          → (userId: number, emoteId: string)
--   RaceFinished        → (finishOrder: {userId:number, time:number}[])
--   ScreenEffect        → (effectName: string, params: table) -- client-side VFX
--   DriftCharge         → (amount: number)  -- boost gauge fill from DriftCorner zone
--   CheckpointPassed    → (cpIndex: number)  -- fires to passing player only (1 or 2)
--   RaceIntroShown      → (intro: { biome: string })  -- broadcast at race start
--   RaceSeedBroadcast   → (seed: number)  -- per-race seed for client-side variation
--
-- RemoteFunctions (server-authoritative):
--   RequestPickup       → itemId: string          → "ok" | "denied: <reason>"
--   RequestContest      → itemId: string, presses: number  → void
--   RequestSteal        → targetUserId: number    → void
--   DefendSteal         → (none)                  → void
--   SubmitCraft         → slotAssignments: table  → "ok" | "denied: <reason>"
--   RequestBoost        → (none)                  → "ok" | "denied: <reason>"
--   RequestAbility      → itemName: string        → "ok" | "denied: <reason>"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	"PhaseChanged",
	"BiomeSelected",
	"ItemPickedUp",
	"InventoryUpdated",
	"ContestUpdate",
	"ContestResult",
	"StealAttempt",
	"ItemStolen",
	"VehicleSpawned",
	"PlayerPositionSync",
	"AbilityActivated",
	"AbilityDenied",
	"EmoteFired",
	"RaceFinished",
	"ScreenEffect",
	"DriftCharge",
	"CheckpointPassed",
	"RaceIntroShown",
	"RaceSeedBroadcast",
}

local FUNCTIONS = {
	"RequestPickup",
	"RequestContest",
	"RequestSteal",
	"DefendSteal",
	"SubmitCraft",
	"RequestBoost",
	"RequestAbility",
	"RequestRespawn",
	"RequestDrop",
}

local RemoteEvents = {}

-- Lazily create or retrieve each instance
local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	or Instance.new("Folder", ReplicatedStorage)
folder.Name = "RemoteEvents"

for _, name in ipairs(EVENTS) do
	local existing = folder:FindFirstChild(name)
	if not existing then
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = folder
		RemoteEvents[name] = re
	else
		RemoteEvents[name] = existing
	end
end

local funcFolder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
	or Instance.new("Folder", ReplicatedStorage)
funcFolder.Name = "RemoteFunctions"

for _, name in ipairs(FUNCTIONS) do
	local existing = funcFolder:FindFirstChild(name)
	if not existing then
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = funcFolder
		RemoteEvents[name] = rf
	else
		RemoteEvents[name] = existing
	end
end

return RemoteEvents
