-- CheckpointService.lua
-- Race-finish gating via 2 ordered checkpoints per track.
-- Players must touch Checkpoint1 then Checkpoint2 (in order) before a FinishLine
-- touch counts. CP2 before CP1 is ignored. State persists across respawns; only
-- resetAll() (called at race start) clears it.
--
-- Maps add Checkpoint1 / Checkpoint2 by CollectionService tag.
-- If a map has no Checkpoint1/Checkpoint2 tagged parts, isActive() returns false
-- and the RacingManager skips the gate (back-compat for maps not yet rebuilt).
--
-- Resolves: Issue #126

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local SessionManager = require(ServerScriptService.SessionManager)

local CheckpointService = {}

local _state = {}        -- [userId] = { cp1 = bool, cp2 = bool }
local _connections = {}  -- RBXScriptConnection list, cleared on setup() re-entry

local function _ensure(userId)
	if not _state[userId] then
		_state[userId] = { cp1 = false, cp2 = false }
	end
	return _state[userId]
end

local function _findPlayerByVehicle(vehicle)
	for _, player in ipairs(Players:GetPlayers()) do
		local pdata = SessionManager.getData(player)
		if pdata and pdata.vehicleModel == vehicle then
			return player
		end
	end
	return nil
end

local function _connectCheckpoint(part, cpIndex)
	return part.Touched:Connect(function(hit)
		local vehicle = hit:FindFirstAncestorWhichIsA("Model")
		if not vehicle then return end
		local player = _findPlayerByVehicle(vehicle)
		if not player then return end

		local s = _ensure(player.UserId)
		if cpIndex == 1 then
			if not s.cp1 then
				s.cp1 = true
				RemoteEvents.CheckpointPassed:FireClient(player, 1)
			end
		elseif cpIndex == 2 then
			-- In-order only: CP2 counts only if CP1 already passed.
			if s.cp1 and not s.cp2 then
				s.cp2 = true
				RemoteEvents.CheckpointPassed:FireClient(player, 2)
			end
		end
	end)
end

function CheckpointService.resetAll()
	_state = {}
	for _, player in ipairs(Players:GetPlayers()) do
		_state[player.UserId] = { cp1 = false, cp2 = false }
	end
end

function CheckpointService.hasCompleted(player)
	local s = _state[player.UserId]
	return s ~= nil and s.cp1 and s.cp2
end

function CheckpointService.isActive()
	return #CollectionService:GetTagged("Checkpoint1") > 0
		and #CollectionService:GetTagged("Checkpoint2") > 0
end

function CheckpointService.setup()
	-- Drop previous connections so re-entries don't double-fire.
	for _, c in ipairs(_connections) do c:Disconnect() end
	_connections = {}

	for _, part in ipairs(CollectionService:GetTagged("Checkpoint1")) do
		table.insert(_connections, _connectCheckpoint(part, 1))
	end
	for _, part in ipairs(CollectionService:GetTagged("Checkpoint2")) do
		table.insert(_connections, _connectCheckpoint(part, 2))
	end
end

Players.PlayerRemoving:Connect(function(player)
	_state[player.UserId] = nil
end)

return CheckpointService
