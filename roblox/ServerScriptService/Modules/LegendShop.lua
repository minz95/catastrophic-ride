-- LegendShop.lua
-- Selling Legend Rides (Shared/LegendRides, Modules/LegendStore) and
-- wearing them. Shop.handle sends it the shop screen's legend actions;
-- Shop's ProcessReceipt sends it the Robux product (Products.LEGEND).
--
--   "legend_buy", id     coins: Constants.LEGEND.COINS
--   "legend_robux", id   remembers the listing, opens Roblox's prompt
--   "legend_ride", id    wear an owned ride round the waist ("" = none)
--
-- Every sale pays the original's owner ROYALTY coins: at once when they are
-- on this server, else through the store (`claimFor` when they come back).
-- A worn ride is a small still copy (SCALE) welded round the avatar's
-- waist, massless and touching nothing; off while racing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
local Products = require(ReplicatedStorage.Shared.Products)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LegendStore = require(ServerScriptService.Modules.LegendStore)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local L = Constants.LEGEND
local LegendShop = {}

LegendShop.WORN = "LegendRide"
local _pending = {}   -- userId → listing id picked before a Robux prompt

local function coinsStat(player, rec)
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	if c then c.Value = rec.coins end
end

local function tell(player, msg)
	pcall(function() RemoteEvents.LegendUpdate:FireClient(player, msg) end)
end

--- Pays the owner of listing `l` for one sale.
local function payOwner(l)
	local owner = Players:GetPlayerByUserId(l.ownerId)
	local rec = owner and PlayerStore.get(owner)
	if rec then
		rec.coins += L.ROYALTY
		coinsStat(owner, rec)
		PlayerStore.saveSoon(owner)
		tell(owner, { kind = "royalty", title = l.title, sales = 1, coins = L.ROYALTY })
	else
		LegendStore.royalty(l.ownerId, L.ROYALTY, l.title)
	end
	Telemetry.record("legend_royalty", { userId = l.ownerId, id = l.id, coins = L.ROYALTY, online = rec ~= nil })
end

--- Coins earned while away, paid when the owner is back.
function LegendShop.claimFor(player)
	local rec = PlayerStore.get(player)
	if not rec then return end
	local got = LegendStore.claim(player.UserId)
	if got and (got.coins or 0) > 0 then
		rec.coins += got.coins
		coinsStat(player, rec)
		PlayerStore.saveSoon(player)
		tell(player, { kind = "royalty", title = got.title, sales = got.sales, coins = got.coins })
	end
end

--- The ride show's winner: their ride goes on sale, they own the original.
function LegendShop.listWinner(e)
	if not e or e.userId <= 0 then return nil end
	local l = LegendRides.listing(e, os.time())
	LegendStore.add(l)
	local player = Players:GetPlayerByUserId(e.userId)
	local rec = player and PlayerStore.get(player)
	if rec then
		LegendRides.give(rec, l, true)
		PlayerStore.saveSoon(player)
		tell(player, { kind = "listed", title = l.title, limit = l.limit, days = L.DAYS })
	end
	Telemetry.record("legend_list", { userId = e.userId, id = l.id, title = l.title })
	return l
end

local function bought(player, rec, l, pay)
	LegendRides.give(rec, l, false)
	rec.legendOn = l.id   -- on at once: the point of buying it
	payOwner(l)
	Telemetry.record("legend_buy", { userId = player.UserId, id = l.id, pay = pay, result = "ok" })
	task.defer(LegendShop.refresh, player)
end

--- Shop actions. Returns "ok" or "denied: …".
function LegendShop.handle(player, rec, action, id)
	if type(id) ~= "string" or #id > 64 then return "denied: bad id" end
	local nowT = os.time()
	if action == "legend_ride" then
		if id ~= "" and not (rec.legend and rec.legend[id]) then return "denied: not owned" end
		rec.legendOn = id ~= "" and id or nil
		PlayerStore.saveSoon(player)
		LegendShop.refresh(player)
		return "ok"
	end
	local l = LegendStore.find(id)
	if action == "legend_buy" then
		local res = LegendRides.canBuy(l, rec, player.UserId, nowT, true)
		if res ~= "ok" then return res end
		res = LegendStore.take(id)
		if res ~= "ok" then
			Telemetry.record("legend_buy", { userId = player.UserId, id = id, pay = "coins", result = res })
			return res
		end
		rec.coins -= L.COINS
		coinsStat(player, rec)
		bought(player, rec, l, "coins")
		PlayerStore.saveSoon(player)
		return "ok"
	elseif action == "legend_robux" then
		if Products.LEGEND.id == 0 then return "denied: not sold" end
		local res = LegendRides.canBuy(l, rec, player.UserId, nowT, false)
		if res ~= "ok" then return res end
		_pending[player.UserId] = id
		pcall(function()
			game:GetService("MarketplaceService"):PromptProductPurchase(player, Products.LEGEND.id)
		end)
		return "ok"
	end
	return "denied: bad action"
end

--- The Robux product was paid: the picked listing if a copy is left, else
-- its price in coins (a paid purchase must give something). Returns an undo
-- function for when the record cannot be saved.
function LegendShop.grantRobux(player, rec)
	local id = _pending[player.UserId]
	local l = id and LegendStore.find(id)
	if l and LegendRides.canBuy(l, rec, player.UserId, os.time(), false) == "ok" and LegendStore.take(id) == "ok" then
		_pending[player.UserId] = nil
		bought(player, rec, l, "robux")
		return function()
			rec.legend[l.id] = nil
			if rec.legendOn == l.id then rec.legendOn = nil end
		end
	end
	rec.coins += L.COINS
	coinsStat(player, rec)
	tell(player, { kind = "refund", title = l and l.title or "Legend Ride", coins = L.COINS })
	Telemetry.record("legend_buy", { userId = player.UserId, id = id, pay = "robux", result = "coins instead" })
	return function() rec.coins -= L.COINS end
end

-- ── Wearing ──────────────────────────────────────────────────────────────────

local function scaleModel(model, s, pivot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = d.Size * s
			d.CFrame = pivot * (CFrame.new(rel.Position * s) * (rel - rel.Position))
		elseif d:IsA("SpecialMesh") then
			d.Scale = d.Scale * s
			d.Offset = d.Offset * s
		elseif d:IsA("Attachment") then
			d.Position = d.Position * s
		end
	end
end

--- Puts `player`'s worn Legend Ride round their waist (or takes it off).
function LegendShop.refresh(player)
	local character = player.Character
	if not character then return end
	local old = character:FindFirstChild(LegendShop.WORN)
	if old then old:Destroy() end
	local rec = PlayerStore.get(player)
	local id = rec and rec.legendOn
	local ride = id and rec.legend and rec.legend[id]
	local phase = require(ServerScriptService.GameManager).getPhase()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not ride or not root or phase == Constants.PHASES.RACING then return end
	local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
	local model = HallOfFame.buildStill(ride)
	if not model then return end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") then c:Destroy() end   -- the HEAD item: no rider in it
	end
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local pivot = seat and seat.CFrame or model:GetPivot()
	scaleModel(model, L.SCALE, pivot)
	-- stand the avatar in it: facing where they face, the seat over their
	-- feet, the car on the ground
	local hum = character:FindFirstChildOfClass("Humanoid")
	local hip = hum and hum.HipHeight or 2
	local seatAt = seat and seat.Position or pivot.Position
	local seatRot = seat and (seat.CFrame - seat.Position) or CFrame.new()
	local yaw = CFrame.lookAt(Vector3.zero, Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z))
	local turn = CFrame.new(seatAt) * yaw * seatRot:Inverse() * CFrame.new(-seatAt)
	model:PivotTo(turn * model:GetPivot())
	seatAt = seat and seat.Position or model:GetPivot().Position
	local cf, size = model:GetBoundingBox()
	local feetY = root.Position.Y - root.Size.Y / 2 - hip
	local move = Vector3.new(root.Position.X - seatAt.X, feetY - (cf.Position.Y - size.Y / 2), root.Position.Z - seatAt.Z)
	model:PivotTo(CFrame.new(move) * model:GetPivot())
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			if d:IsA("VehicleSeat") or d:IsA("Seat") then d.Disabled = true end
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, d
			w.Parent = d
		end
	end
	model.Name = LegendShop.WORN
	model:SetAttribute("LegendId", id)
	model.Parent = character
end

return LegendShop
