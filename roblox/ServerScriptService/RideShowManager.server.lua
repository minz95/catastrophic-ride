-- RideShowManager.server.lua
-- The ride show (playtest 2026-11-15: "friends will want to bet on whose
-- ride is the coolest or funniest; show it off, compare, take a picture").
-- When RESULTS starts with Constants.RIDE_SHOW.MIN_PLAYERS or more players
-- who raced, every client gets their rides (RemoteEvents.RideShow "open":
-- the car models, still parked in the world until the next round, and the
-- items in their slots) and StarterGui/RideShowUI lays them side by side.
-- Everyone votes for the funniest ride but their own (VoteRide, rules in
-- Shared/RideVote) for SECONDS; the winner gets COINS (telemetry
-- "ride_vote"). Bots do not show or vote, except in a Studio recording:
-- harness `rideShowBots` = n puts n race bots' rides in and lets them vote
-- (a one-client recording never reached MIN_PLAYERS; nil live).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RideVote       = require(ReplicatedStorage.Shared.RideVote)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local PlayerStore    = require(ServerScriptService.Modules.PlayerStore)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local Shop           = require(ServerScriptService.Modules.Shop)
local HarnessConfig  = require(ServerScriptService.Modules.HarnessConfig)
local HallOfFame     = require(ServerScriptService.Modules.HallOfFame)

local S = Constants.RIDE_SHOW

HallOfFame.start(HallOfFame.isLive())

local _show = nil   -- { entries = { [userId] = true }, votes = {}, round = n }
local _lastVote = {}

local function _entries()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local d = SessionManager.getData(p)
		local model = d and d.vehicleModel
		if model and model.Parent and p:GetAttribute("Spectating") ~= true then
			local slots = d.vehicleStats and d.vehicleStats.slotAssignments or {}
			table.insert(list, {
				userId = p.UserId, name = p.DisplayName or p.Name, model = model,
				slots = table.clone(slots),
			})
		end
	end
	local harness = HarnessConfig.peek()
	local extra = harness and tonumber(harness.rideShowBots) or 0
	for _, b in ipairs(SessionManager.bots()) do
		if extra <= 0 then break end
		local d = SessionManager.getData(b)
		local model = d and d.vehicleModel
		if model and model.Parent then
			extra -= 1
			local slots = d.vehicleStats and d.vehicleStats.slotAssignments or {}
			table.insert(list, { userId = b.UserId, name = b.Name, model = model, slots = table.clone(slots), bot = true })
		end
	end
	table.sort(list, function(a, b) return a.userId < b.userId end)
	return list
end

-- { { userId, votes } }: a table keyed by user id does not cross a remote
-- intact (sparse number keys)
local _onVote   -- forward: a vote landed (fires the new counts)

local function _countList(votes)
	local out = {}
	for id, n in pairs(RideVote.counts(votes)) do table.insert(out, { userId = id, votes = n }) end
	return out
end

local function _pay(userId, votes)
	local p = Players:GetPlayerByUserId(userId)
	local rec = p and PlayerStore.get(p)
	if not rec then return 0 end
	rec.coins += S.COINS
	local ls = p:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	if c then c.Value = rec.coins end
	RemoteEvents.ShopUpdated:FireClient(p, Shop.state(rec))
	task.spawn(PlayerStore.saveSoon, p)
	Telemetry.record("ride_vote", { userId = userId, coins = S.COINS, votes = votes })
	return S.COINS
end

local function _close(show)
	if _show ~= show then return end
	_show = nil
	local winners, best = RideVote.winners(show.votes)
	for _, id in ipairs(winners) do _pay(id, best) end
	-- the lobby's hall of fame: the first winner's ride with them on it
	local first = winners[1]
	local e = first and show.byId and show.byId[first]
	if e then
		local p = Players:GetPlayerByUserId(first)
		local rec = p and PlayerStore.get(p)
		task.spawn(HallOfFame.record, HallOfFame.entry(first, e.name, GameManager.getBiome(), e.slots, best,
			rec and rec.equipped or {}))
	end
	RemoteEvents.RideShow:FireAllClients("closed",
		{ winners = winners, counts = _countList(show.votes), coins = S.COINS })
end

GameManager.onPhaseChanged(function(phase)
	if phase ~= Constants.PHASES.RESULTS then
		if _show then _close(_show) end
		return
	end
	local list = _entries()
	if #list < S.MIN_PLAYERS then return end
	local show = { entries = {}, votes = {}, byId = {} }
	for _, e in ipairs(list) do
		show.entries[e.userId] = true
		show.byId[e.userId] = e
	end
	_show = show
	local endsAt = workspace:GetServerTimeNow() + S.SECONDS
	RemoteEvents.RideShow:FireAllClients("open", { entries = list, endsAt = endsAt, coins = S.COINS })
	Telemetry.record("ride_show", { rides = #list })
	task.delay(S.SECONDS, _close, show)
	-- harness bots in the show vote for someone else, one after another
	for k, e in ipairs(list) do
		if e.bot then
			task.delay(1.5 + k * 1.2, function()
				if _show ~= show then return end
				local others = {}
				for _, o in ipairs(list) do if o.userId ~= e.userId then table.insert(others, o.userId) end end
				if #others > 0 and RideVote.cast(show.votes, show.entries, e.userId, others[math.random(#others)]) == "ok" then
					_onVote(show)
				end
			end)
		end
	end
end)

_onVote = function(show)
	RemoteEvents.RideShow:FireAllClients("votes", { counts = _countList(show.votes) })
end

RemoteEvents.VoteRide.OnServerEvent:Connect(function(player, target)
	local show = _show
	if not show then return end
	local now = os.clock()
	if _lastVote[player.UserId] and now - _lastVote[player.UserId] < S.VOTE_GAP then return end
	_lastVote[player.UserId] = now
	if RideVote.cast(show.votes, show.entries, player.UserId, target) == "ok" then
		_onVote(show)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	_lastVote[player.UserId] = nil
	local show = _show
	if show then show.votes[player.UserId] = nil end
end)
