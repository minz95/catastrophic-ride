-- LobbyTour.lua
-- Junk Town with real physics (2026-11-17, "test lobby phases 1 and 2
-- systematically before the release"). Harness arg `lobbyTour`
-- (scenarios lobby-tour, hub-tour): the match stays in LOBBY while the bot
-- client (Modules/LobbyTourClient) walks to every place a player goes:
-- the stage, each Legend pad, each trophy, the shop counter, every
-- townsperson, the TV, round the fountain and through the arch, out the
-- west gate down Auto Street, through Junk Motors and the used-car lot (up
-- the tower's ramp), then (hub)
-- onto each start pad and presses ▶ PLAY. It wears a Legend Ride all the
-- way (a ride-on must not catch on anything). Each stop is reported
-- (`bot_tour_stop`: reached, distance left, seconds, lowest Y); the hub part
-- reports the pad, the countdown and the travel failure Studio gives.
-- `lobbyTour = { hub = true }` runs it in hub mode (GameManager).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local LobbyTour = {}

--- The stops: { name, x, y, z } (y: the floor there), in walking order.
function LobbyTour.stops(LobbyLayout, LobbyNpcs, Departure, hub)
	local O = LobbyLayout.ORIGIN
	local list = {}
	local function add(name, p) table.insert(list, { name = name, x = p.X, z = p.Z, y = p.Y }) end
	local function inward(p, d)
		local c = Vector3.new(O.X, p.Y, O.Z)
		return p + (c - p).Unit * d
	end
	add("arch", LobbyLayout.ARCH + Vector3.new(0, 0, -3))
	add("fountain", LobbyLayout.FOUNTAIN + Vector3.new(8, 0, 6))
	add("tv", inward(LobbyLayout.BOARD, 9))
	local st = LobbyLayout.STAGE
	add("stage", st.at + Vector3.new(0, 0, st.radius + 4))
	for i = 1, LobbyLayout.TROPHY_SLOTS do add("trophy" .. i, inward(LobbyLayout.trophySpot(i), 4)) end
	for _, n in ipairs(LobbyNpcs.LIST) do
		if not n.street then add("npc_" .. n.id, inward(O + n.at, 3)) end
	end
	for i = 1, LobbyLayout.LEGEND_SLOTS do add("legend" .. i, inward(LobbyLayout.legendSpot(i), 7)) end
	add("shop", inward(LobbyLayout.SHOP, 9))
	-- out of the west gate: Auto Street and the Junk Motors showroom
	local V3 = Vector3.new
	add("gate", O + V3(-82, 0, 0))
	add("street", O + V3(-200, 0, 0))
	add("motors_door", O + V3(-150, 0, -16))
	for _, n in ipairs(LobbyNpcs.LIST) do
		if n.street and n.at.Z < 0 then add("npc_" .. n.id, O + n.at + V3(-3, 0, 0)) end
	end
	local S = LobbyLayout.SHOWROOM
	add("motors_aisle", O + V3(-200, 0, (S.rows[1] + S.rows[2]) / 2))
	add("motors_back", O + V3(-262, 0, (S.rows[2] + S.rows[3]) / 2))
	add("motors_out", O + V3(-250, 0, -15))
	-- across the road: the used-car lot, its dealers, up the tower's ramp
	local U = LobbyLayout.USED_LOT
	add("lot_entrance", O + V3(U.entranceX, 0, U.box[3] + 3))
	add("lot_front", O + V3(-200, 0, U.box[3] + 2))
	add("lot_aisle", O + V3(-170, 0, (U.rows[2] + U.officeZ) / 2))
	for _, n in ipairs(LobbyNpcs.LIST) do
		if n.street and n.at.Z > 0 then add("npc_" .. n.id, O + n.at + V3(0, 0, -3)) end
	end
	local T = U.tower
	add("ramp_foot", O + V3(T.ramp.x1 + 4, 0, (T.ramp.z0 + T.ramp.z1) / 2))
	add("deck", O + V3(-280, T.deck, (T.rows[1] + T.rows[2]) / 2))
	add("lot_out", O + V3(U.entranceX, 0, U.box[3] + 3))
	add("gate_back", O + V3(-66, 0, 0))
	if hub then
		for i, d in ipairs(Departure.PADS) do
			local p = LobbyLayout.SHOWCASE[i]
			if p then add("pad_" .. d.id, p) end
		end
	end
	add("spawn", LobbyLayout.SPAWN)
	return list
end

function LobbyTour.run(args, done)
	local HallOfFame  = require(ServerScriptService.Modules.HallOfFame)
	local LegendShop  = require(ServerScriptService.Modules.LegendShop)
	local LegendStore = require(ServerScriptService.Modules.LegendStore)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	local LobbyNpcs   = require(ReplicatedStorage.Shared.LobbyNpcs)
	local Departure   = require(ReplicatedStorage.Shared.Departure)
	local GameManager = require(ServerScriptService.GameManager)
	local opts = type(args.lobbyTour) == "table" and args.lobbyTour or {}
	LegendStore.memoryOnly = true

	local player, rec
	local t0 = os.clock()
	repeat
		task.wait(0.5)
		player = Players:GetPlayers()[1]
		rec = player and PlayerStore.get(player)
	until (rec and player.Character and player.Character:FindFirstChild("HumanoidRootPart")) or os.clock() - t0 > 60
	if not rec then done("no tour player") return end
	task.wait(3)   -- the hub built, the models in

	-- a winner on the stage and the walker's own ride round the waist
	local e = HallOfFame.entry(player.UserId, player.DisplayName, "FOREST", { BODY = "Toilet", ENGINE = "Rocket" }, 5, rec.equipped)
	HallOfFame.record(e)
	local l = LegendRides.listing(e, os.time())
	LegendStore.add(l)
	LegendRides.give(rec, l, true)
	rec.legendOn = l.id
	LegendShop.refresh(player)

	local hub = GameManager.placeMode() == "hub"
	local stops = LobbyTour.stops(LobbyLayout, LobbyNpcs, Departure, hub)
	local channel = ReplicatedStorage:WaitForChild("HarnessChannel")
	channel.OnServerEvent:Connect(function(p, kind)
		if p == player and kind == "tour_done" then
			task.delay(1, function() done("lobby tour") end)
		end
	end)
	player:SetAttribute("LobbyTour", HttpService:JSONEncode({ stops = stops, hub = hub, y = LobbyLayout.ORIGIN.Y,
		timeout = opts.timeout or 14 }))
end

return LobbyTour
