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
-- A worn ride is a still copy welded round the avatar like a ride-on
-- costume (WEAR_LENGTH long, its seat at the waist), massless and touching
-- nothing; off for the race and the results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
local NewCars = require(ReplicatedStorage.Shared.NewCars)
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

--- Pays the owner of listing `l` for one sale to `buyer` (a name, may be
-- nil); an owner on this server is told who bought it and how many are sold.
local function payOwner(l, buyer)
	local owner = Players:GetPlayerByUserId(l.ownerId)
	local rec = owner and PlayerStore.get(owner)
	if rec then
		rec.coins += L.ROYALTY
		coinsStat(owner, rec)
		PlayerStore.saveSoon(owner)
		local cur = LegendStore.find(l.id)
		tell(owner, { kind = "royalty", title = l.title, sales = 1, coins = L.ROYALTY,
			sold = cur and cur.sold or nil, limit = l.limit, buyer = buyer })
	else
		LegendStore.royalty(l.ownerId, L.ROYALTY, l.title)
	end
	Telemetry.record("legend_royalty", { userId = l.ownerId, id = l.id, coins = L.ROYALTY, online = rec ~= nil })
end
LegendShop.payOwner = payOwner

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
	-- the copy's number: the sold count right after this sale was taken
	local cur = LegendStore.find(l.id)
	LegendRides.give(rec, l, false, cur and cur.sold or nil)
	rec.legendOn = l.id   -- on at once: the point of buying it
	payOwner(l, player.DisplayName)
	Telemetry.record("legend_buy", { userId = player.UserId, id = l.id, pay = pay, result = "ok" })
	task.defer(LegendShop.refresh, player)
end

--- Shop actions. Returns "ok" or "denied: …".
function LegendShop.handle(player, rec, action, id)
	if type(id) ~= "string" or #id > 64 then return "denied: bad id" end
	local nowT = os.time()
	if action == "legend_ride" then
		local car = NewCars.itemOf(id)
		if car then
			if not NewCars.owns(rec, car) then return "denied: not owned" end
		elseif id ~= "" and not (rec.legend and rec.legend[id]) then
			return "denied: not owned"
		end
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

--- What `player` wears round the waist: a car they are trying on at Junk
-- Motors, else their worn Legend Ride or new car. Returns ride, id.
function LegendShop.worn(player, rec)
	local trying, key = require(ServerScriptService.Modules.CarDealer).trying(player)
	if trying then return trying, key end
	local id = rec and rec.legendOn
	local car = NewCars.itemOf(id)
	if car then
		if NewCars.owns(rec, car) then return NewCars.ride(car), id end
		return nil, nil
	end
	return id and rec.legend and rec.legend[id], id
end

--- Puts `player`'s worn ride round their waist (or takes it off).
function LegendShop.refresh(player)
	local character = player.Character
	if not character then return end
	local old = character:FindFirstChild(LegendShop.WORN)
	if old then old:Destroy() end
	local rec = PlayerStore.get(player)
	local ride, id = LegendShop.worn(player, rec)
	local phase = require(ServerScriptService.GameManager).getPhase()
	-- off for the race and the results: the avatar sits in the race car
	-- (a ride-on round a seated driver stuck through the parked car)
	if not ride or phase == Constants.PHASES.RACING or phase == Constants.PHASES.RESULTS then return end
	-- off at the Junk Grand Prix too: the avatar sits in the GP car (GpManager)
	if player:GetAttribute("GpCar") then return end
	LegendShop.wear(character, ride, id)
end

--- Builds owned ride `ride` (a record's `legend` entry) round `character`'s
-- waist with its tag. Returns the model, or nil.
-- The world box of a model's visible parts (a ride hides its chassis):
-- lowest corner, size; nil when nothing shows.
local function visibleBox(model)
	local lo, hi = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local w = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
						lo = lo and lo:Min(w) or w
						hi = hi and hi:Max(w) or w
					end
				end
			end
		end
	end
	if not lo then return nil end
	return lo, hi - lo
end

function LegendShop.wear(character, ride, id)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
	local model = HallOfFame.buildStill(ride)
	if not model then return end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") then c:Destroy() end   -- the HEAD item: no rider in it
	end
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local pivot = seat and seat.CFrame or model:GetPivot()
	-- a ride-on costume: WEAR_LENGTH long whatever the ride (the old 0.5×
	-- copy of a short toilet hid between the legs, reel 2026-11-17)
	local _, size0 = visibleBox(model)
	local long = size0 and math.max(size0.X, size0.Z) or 0
	if long > 0 then
		require(ServerScriptService.Modules.ModelScale).scale(model, L.WEAR_LENGTH / long, pivot)
	end
	-- turned where the avatar faces, the seat over its middle
	local hum = character:FindFirstChildOfClass("Humanoid")
	-- the legs' length under the torso: HipHeight on R15, 0 on R6 (legs 2)
	local hip = hum and hum.HipHeight or 2
	if hip < 0.5 then hip = 2 end
	local seatAt = seat and seat.Position or pivot.Position
	local seatRot = seat and (seat.CFrame - seat.Position) or CFrame.new()
	local yaw = CFrame.lookAt(Vector3.zero, Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z))
	local turn = CFrame.new(seatAt) * yaw * seatRot:Inverse() * CFrame.new(-seatAt)
	model:PivotTo(turn * model:GetPivot())
	-- the seat's top at the waist (legs inside the ride, the body out of the
	-- seat), lifted if that put the ride into the floor
	local waistY = root.Position.Y - root.Size.Y / 2
	local feetY = waistY - hip
	seatAt = seat and seat.Position or model:GetPivot().Position
	local seatTop = seat and (seat.Position.Y + seat.Size.Y / 2) or nil
	local lo = visibleBox(model)
	local dy = seatTop and (waistY - seatTop) or (lo and feetY - lo.Y or 0)
	if lo and lo.Y + dy < feetY then dy = feetY - lo.Y end
	model:PivotTo(CFrame.new(root.Position.X - seatAt.X, dy, root.Position.Z - seatAt.Z) * model:GetPivot())
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
	-- its tag where everyone sees it: "⭐ ORIGINAL" or "#7/50", and whose it was
	local tagAt = seat or model:FindFirstChildWhichIsA("BasePart", true)
	if tagAt then
		local bb = Instance.new("BillboardGui")
		bb.Name = "LegendTag"
		bb.Size = UDim2.new(0, 150, 0, 34)
		bb.StudsOffset = Vector3.new(0, -1.4, 0)
		bb.MaxDistance = 70
		bb.LightInfluence = 0
		local list = Instance.new("UIListLayout")   -- the tag, then the name under it
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = bb
		local t = Instance.new("TextLabel")
		t.LayoutOrder = 1
		t.Size = UDim2.fromScale(1, 0.6)
		t.BackgroundTransparency = 1
		t.Text = LegendRides.tag(ride)
		t.TextColor3 = ride.original and Color3.fromRGB(255, 214, 60) or Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.Parent = bb
		local n = Instance.new("TextLabel")
		n.Size = UDim2.fromScale(1, 0.4)
		n.LayoutOrder = 2
		n.BackgroundTransparency = 1
		n.Text = tostring(ride.title)
		n.TextColor3 = Color3.fromRGB(230, 230, 245)
		n.TextStrokeTransparency = 0.4
		n.TextScaled = true
		n.Font = Enum.Font.GothamBold
		n.Parent = bb
		bb.Parent = tagAt   -- a BillboardGui in a part shows over that part
	end
	model.Name = LegendShop.WORN
	model:SetAttribute("LegendId", id)
	model.Parent = character
	return model
end

return LegendShop
