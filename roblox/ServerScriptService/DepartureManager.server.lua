-- DepartureManager.server.lua
-- Travel between the places (Shared/Places). In the hub: the start pads
-- (Shared/Departure, built by LobbyHub.departurePads) every DEPART.CHECK s:
-- who stands on each, the pad's status line, the player attributes
-- DepartPad / DepartAt (LobbyUI's "leaving in"), and the groups that leave
-- (Modules/PlaceTeleport, telemetry "depart"). PlaceAction: "play" puts you
-- on the race pad (the hub's ▶ PLAY), "hub" sends you back from the race
-- place (LobbyUI's ← JUNK TOWN).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Departure = require(ReplicatedStorage.Shared.Departure)
local Places = require(ReplicatedStorage.Shared.Places)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GameManager = require(ServerScriptService.GameManager)
local PlaceTeleport = require(ServerScriptService.Modules.PlaceTeleport)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local D = Constants.DEPART

local _pending = {}   -- userId → os.clock() when sent (the teleport is loading)
local _since = {}     -- userId → { pad, t }: when they stepped on
local _last = {}      -- userId → os.clock() of the last PlaceAction

PlaceTeleport.onFailed(function(player)
	_pending[player.UserId] = nil
end)

local function pending(userId)
	local t = _pending[userId]
	if t and os.clock() - t > D.PENDING then
		_pending[userId] = nil
		return false
	end
	return t ~= nil
end

local function findPads()
	local hub = workspace:FindFirstChild("LobbyHub")
	if not hub then return nil end
	local pads = {}
	for _, d in ipairs(Departure.PADS) do
		local pad = hub:FindFirstChild("Depart_" .. d.id)
		if not pad then return nil end
		pads[d.id] = pad
	end
	return pads, hub
end

-- user ids on each pad now, the earliest on first
local function whoIsOn(pads, now)
	local on = {}
	for id in pairs(pads) do on[id] = {} end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local found = nil
		if root and not pending(p.UserId) then
			for id, pad in pairs(pads) do
				local d = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z).Magnitude
				local dy = root.Position.Y - pad.Position.Y
				if d <= D.RADIUS and dy > -1 and dy < D.HEIGHT then
					found = id
					break
				end
			end
		end
		if found then
			local s = _since[p.UserId]
			if not s or s.pad ~= found then _since[p.UserId] = { pad = found, t = now } end
			table.insert(on[found], p.UserId)
		else
			_since[p.UserId] = nil
		end
	end
	for _, ids in pairs(on) do
		table.sort(ids, function(a, b)
			local ta, tb = _since[a].t, _since[b].t
			if ta ~= tb then return ta < tb end
			return a < b
		end)
	end
	return on
end

local function send(group)
	local players = {}
	for _, id in ipairs(group.ids) do
		local p = Players:GetPlayerByUserId(id)
		if p then
			table.insert(players, p)
			_pending[id] = os.clock()
			_since[id] = nil
			p:SetAttribute("DepartPad", nil)
			p:SetAttribute("DepartAt", nil)
		end
	end
	if #players == 0 then return end
	Telemetry.record("depart", { pad = group.pad, kind = group.kind, n = #players, ids = group.ids })
	PlaceTeleport.send(players, Places.RACE, {
		reserve = group.kind == "private",
		data = { party = group.ids, pad = group.pad },
	})
end

local function runPads()
	local state = Departure.new()
	local pads, hub = findPads()
	while not pads do
		task.wait(0.5)
		pads, hub = findPads()
	end
	local LobbyHub = require(ServerScriptService.Modules.Maps.LobbyHub)
	while true do
		local now = workspace:GetServerTimeNow()
		local on = whoIsOn(pads, now)
		local leaving, view = Departure.step(state, on, now, D.SECONDS, Constants.MAX_PLAYERS)
		for id, v in pairs(view) do
			local text = "step on!"
			if v.count > 0 and v.leavesAt then
				text = string.format("%d on pad · leaving in %d", v.count, math.max(0, math.ceil(v.leavesAt - now)))
			end
			LobbyHub.setPad(hub, id, text)
			for _, uid in ipairs(on[id]) do
				local p = Players:GetPlayerByUserId(uid)
				if p and not pending(uid) then
					p:SetAttribute("DepartPad", id)
					p:SetAttribute("DepartAt", v.leavesAt)
				end
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if not _since[p.UserId] and p:GetAttribute("DepartPad") then
				p:SetAttribute("DepartPad", nil)
				p:SetAttribute("DepartAt", nil)
			end
		end
		for _, g in ipairs(leaving) do send(g) end
		task.wait(D.CHECK)
	end
end

-- ▶ PLAY: onto the race pad, a little apart from whoever is on it
local _spread = 0
local function toRacePad(player)
	local pads = findPads()
	local pad = pads and pads[Departure.PADS[1].id]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not pad or not root then return "denied: not ready" end
	_spread += 1
	local a = _spread * 2.1
	local r = (_spread % 3) * 1.4
	local pos = pad.Position + Vector3.new(math.cos(a) * r, 3.5, math.sin(a) * r)
	pcall(function() character:PivotTo(CFrame.new(pos)) end)
	return "ok"
end

RemoteEvents.PlaceAction.OnServerInvoke = function(player, action)
	local now = os.clock()
	if _last[player.UserId] and now - _last[player.UserId] < D.GAP then return "denied: too fast" end
	_last[player.UserId] = now
	local mode = GameManager.placeMode()
	if action == "play" then
		if mode ~= "hub" then return "denied: not here" end
		return toRacePad(player)
	elseif action == "hub" then
		if mode ~= "race" then return "denied: not here" end
		if pending(player.UserId) then return "denied: already going" end
		_pending[player.UserId] = os.clock()
		Telemetry.record("to_hub", { userId = player.UserId })
		if PlaceTeleport.send({ player }, Places.HUB, { data = { from = "race" } }) then return "ok" end
		return "denied: failed"
	end
	return "denied: unknown"
end

Players.PlayerRemoving:Connect(function(player)
	_pending[player.UserId] = nil
	_since[player.UserId] = nil
	_last[player.UserId] = nil
end)

task.spawn(function()
	if GameManager.placeMode() == "hub" then runPads() end
end)
