-- RemoteEvents/init.lua
-- Creates all RemoteEvent and RemoteFunction instances at runtime (server)
-- and waits for them (client). Require this module on both server and
-- client to get the events table.
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
--   AbilityActivated    → (userId: number, itemName: string, targetIds: number[], effectKey: string,
--                          info: { cooldown, duration, label })
--   EffectFx            → (key: string, userId: number, info: { duration, from, text })
--                          an effect landed on userId's car (StarterPlayerScripts/EffectFx draws it)
--   AbilityDenied       → (reason: string)                   -- fires to activator only
--   EmoteFired          → (userId: number, emoteId: string)
--   RaceFinished        → (finishOrder: {userId:number, time:number}[])
--   ScreenEffect        → (effectName: string, params: table) -- client-side VFX
--   DriftCharge         → (amount: number)  -- boost gauge fill from DriftCorner zone
--   CheckpointPassed    → (cpIndex: number)  -- fires to passing player only (1 or 2)
--   RaceIntroShown      → (intro: { biome: string })  -- broadcast at race start
--   RaceSeedBroadcast   → (seed: number)  -- per-race seed for client-side variation
--   PlaytestMark        → client→server (note: "bad" | "fun")  -- playtest marker, Studio / test servers only
--   CarImpact           → server→driver (dvx, dvz, spin, strength, otherUserId)
--                          a car-to-car hit (Shared/CarImpact): VehicleController.knock
--   SetGuard            → client→server (on: boolean)  -- FARMING: hold G to guard against punches
--   FarmAction          → server→all (kind, actorUserId, targetUserId, info)
--                          what a player does to another in FARMING, for every
--                          client to animate (StarterPlayerScripts/FarmFx):
--                          "punch" (info.result = hit | blocked | immune | knockout, info.hits),
--                          "guard" (info.on), "grab" (steal opens), "swat" (defence tap),
--                          "grabEnd" (info.result = stolen | defended | denied ...)
--   DriftTurbo          → client→server (level: number, slideSeconds: number)
--                          a released drift earned Constants.DRIVE.DRIFT_TURBO[level]
--   CraftDraft          → client→server (slotAssignments: table)  -- CRAFTING: the slots
--                          as arranged so far; kept if the timer runs out first
--   RewardGranted       → server→client (reward: table) -- RESULTS: Progression.applyRound
--                          result + { saved: bool } (ProgressionManager)
--   ShopUpdated         → server→client (state: table) -- coins changed outside the shop screen (Robux pack)
--   Taunt               → client→server () -- show my equipped taunt (RACING, Constants.TAUNT)
--   TauntShown          → server→client (userId, part: BasePart, emoji, text, name) -- draw it over that car (TauntFx)
--   UseRaceTrick        → () → "ok" | "denied: …"  (RACING, the equipped race trick, AbilityManager)
--
-- RemoteFunctions (server-authoritative):
--   RequestPickup       → itemId: string          → "ok" | "denied: <reason>"
--   RequestContest      → itemId: string, presses: number  → void
--   RequestSteal        → targetUserId: number    → void
--   DefendSteal         → (none)                  → void
--   SubmitCraft         → slotAssignments: table  → "ok" | "denied: <reason>"
--   RequestBoost        → (none)                  → "ok" | "denied: <reason>"
--   RequestAbility      → itemName: string        → "ok" | "denied: <reason>"
--   UseGadget           → (none) → "ok" | "denied: <reason>"  (FARMING, equipped shop gadget)
--   ShopAction          → action: "state" | "buy" | "equip", id: string?  → { result, state }  (Modules/Shop)
--   RequestPunch        → (aimUserId?)            → "hit" | "blocked" | "immune" | "knockout" | "miss" | "denied: <reason>"

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
	"EffectFx",
	"AbilityDenied",
	"EmoteFired",
	"RaceFinished",
	"ScreenEffect",
	"DriftCharge",
	"CheckpointPassed",
	"RaceIntroShown",
	"RaceSeedBroadcast",
	"PlaytestMark",
	"CarImpact",
	"DriftTurbo",
	"SetGuard",
	"FarmAction",
	"CraftDraft",
	"RewardGranted",
	"ShopUpdated",
	"Taunt",
	"TauntShown",
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
	"RequestPunch",
	"ShopAction",
	"UseGadget",
	"UseRaceTrick",
}

local RemoteEvents = {}

-- A pure client only: Studio's edit mode (and -task RunScript, the sim
-- harness's host) is client AND server, and waiting there hung it forever.
local IS_CLIENT = false
pcall(function()
	local rs = game:GetService("RunService")
	IS_CLIENT = rs:IsClient() and not rs:IsServer()
end)

if IS_CLIENT then
	-- Client: the server made every instance at boot; wait for them, never
	-- create one. A copy made here on a slow device (before replication
	-- arrived) is local only: the client would talk to an event no server
	-- listens to, a dead session.
	local WAIT = 30
	local function await(parent, name)
		local child = parent:WaitForChild(name, WAIT)
		if not child then
			warn(("[RemoteEvents] %s not replicated after %d s, still waiting"):format(name, WAIT))
			child = parent:WaitForChild(name)
		end
		return child
	end
	local folder = await(ReplicatedStorage, "RemoteEvents")
	for _, name in ipairs(EVENTS) do
		RemoteEvents[name] = await(folder, name)
	end
	local funcFolder = await(ReplicatedStorage, "RemoteFunctions")
	for _, name in ipairs(FUNCTIONS) do
		RemoteEvents[name] = await(funcFolder, name)
	end
	return RemoteEvents
end

-- Server: create or retrieve each instance
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
