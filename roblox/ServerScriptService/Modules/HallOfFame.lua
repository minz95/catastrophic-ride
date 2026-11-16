-- HallOfFame.lua
-- The latest ride show winner on show in the lobby (2026-11-16: "the
-- winning ride, with its driver on it, in the lobby"). RideShowManager
-- calls `record` when a vote closes; the ride is built still (the race's
-- VehicleBuilder with the winner's paint / trail / ride look), the winner's
-- own avatar seated on it (their Roblox look, shop hat and ride pose), into
-- ReplicatedStorage.HallOfFame for LobbyUI. Live servers share it through a
-- DataStore (`STORE`, key `KEY`): a new server shows the last winner of any
-- server and checks for a newer one every `POLL` s. Studio and harness
-- sessions keep it in memory.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)

local HallOfFame = {}

HallOfFame.FOLDER = "HallOfFame"
HallOfFame.STORE = "HallOfFame_v1"
HallOfFame.KEY = "latest"
HallOfFame.POLL = 180
HallOfFame.MAX_SLOT_KEYS = 12

local _latest = nil   -- the entry on show
HallOfFame.live = false   -- the DataStore is used (set by start)

local STRIP = { "BaseScript", "BodyMover", "Constraint", "ParticleEmitter", "Trail", "Beam", "Sound",
	"Light", "Fire", "Smoke", "Sparkles" }

--- A clean entry from a winner's data, or nil.
function HallOfFame.entry(userId, name, biome, slots, votes, equipped, at)
	if type(userId) ~= "number" or type(slots) ~= "table" then return nil end
	local clean, n = {}, 0
	for k, v in pairs(slots) do
		n += 1
		if n > HallOfFame.MAX_SLOT_KEYS then break end
		if type(k) == "string" and type(v) == "string" then clean[k] = v end
	end
	local look = {}
	for _, cat in ipairs({ "ride", "paint", "trail", "hat", "pose" }) do
		local it = Cosmetics.equipped(equipped, cat)
		if it then look[cat] = it.id end
	end
	return { userId = userId, name = tostring(name or "?"), biome = biome or "FOREST", slots = clean,
		votes = tonumber(votes) or 0, look = look, at = at or os.time() }
end

-- The winner's seated avatar: their own look when Roblox gives it.
local function seatWinner(model, e)
	local SeatedRider = require(ServerScriptService.Modules.SeatedRider)
	local desc
	if e.userId > 0 then
		local ok, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, e.userId)
		if ok then desc = d end
	end
	local pose = e.look.pose and Cosmetics.get(e.look.pose)
	local rider = SeatedRider.seat(model, model, nil,
		{ still = true, fallback = true, description = desc, pose = pose and pose.pose })
	if not rider then return nil end
	local head = rider:FindFirstChild("Head")
	-- the crafted HEAD item on the head (as in the race), else the shop hat
	local crafted = false
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") and c.PrimaryPart then
			if head then
				crafted = true
				local base = c.PrimaryPart.Size.Y / 2
				c:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - (c:GetAttribute("HatSink") or 0) + base, 0))
			else
				c:Destroy()
			end
		end
	end
	if head and not crafted and e.look.hat then
		local ShopHat = require(ServerScriptService.Modules.ShopHat)
		local hat = ShopHat.wear(rider, e.look.hat)
		if hat then
			for _, p in ipairs(hat:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true end
			end
		end
	end
	return rider
end

--- Builds entry `e` into ReplicatedStorage.HallOfFame (a Model with
-- attributes Name, UserId, Votes, Biome, At). Returns it, or nil.
function HallOfFame.build(e)
	if not e then return nil end
	local ok, model = pcall(function()
		local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
		local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
		local sl = e.slots
		local stats = VehicleStats.calculate(sl.BODY and ItemConfig[sl.BODY], sl.ENGINE and ItemConfig[sl.ENGINE],
			sl.SPECIAL and ItemConfig[sl.SPECIAL], e.biome)
		stats = VehicleStats.applyMobility(stats, sl.MOBILITY and ItemConfig[sl.MOBILITY], e.biome)
		local equipped = {}
		for cat, id in pairs(e.look) do equipped[cat] = id end
		return VehicleBuilder.build(stats, e.biome, CFrame.new(), sl, Cosmetics.look(equipped))
	end)
	if not ok or not model then
		warn("[HallOfFame] build: " .. tostring(model))
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		local strip = false
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then strip = true break end
		end
		if strip then d:Destroy() elseif d:IsA("BasePart") then d.Anchored = true end
	end
	pcall(seatWinner, model, e)
	model.Name = "Winner"
	model:SetAttribute("Name", e.name)
	model:SetAttribute("UserId", e.userId)
	model:SetAttribute("Votes", e.votes)
	model:SetAttribute("Biome", e.biome)
	model:SetAttribute("At", e.at)
	local folder = ReplicatedStorage:FindFirstChild(HallOfFame.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = HallOfFame.FOLDER
		folder.Parent = ReplicatedStorage
	end
	folder:ClearAllChildren()
	model.Parent = folder
	return model
end

local function store()
	return game:GetService("DataStoreService"):GetDataStore(HallOfFame.STORE)
end

--- A ride show winner: on show here now, and (live) for every server.
function HallOfFame.record(e)
	if not e then return end
	_latest = e
	HallOfFame.build(e)
	if HallOfFame.live then
		task.spawn(function()
			local ok, err = pcall(function()
				store():UpdateAsync(HallOfFame.KEY, function(old)
					if type(old) == "table" and (old.at or 0) > e.at then return nil end
					return e
				end)
			end)
			if not ok then warn("[HallOfFame] save: " .. tostring(err)) end
		end)
	end
end

function HallOfFame.latest()
	return _latest
end

local function fetch()
	local ok, e = pcall(function() return store():GetAsync(HallOfFame.KEY) end)
	if ok and type(e) == "table" and type(e.slots) == "table" and type(e.look) == "table"
		and (not _latest or (e.at or 0) > _latest.at) then
		_latest = e
		HallOfFame.build(e)
	end
end

--- Live servers: show the stored winner, look for newer ones now and then.
-- `waitFor`: s to wait for the item models (ShopPreview.buildShowcase does too).
function HallOfFame.start(live)
	HallOfFame.live = live == true
	if not HallOfFame.live then return end
	task.spawn(function()
		local ServerStorage = game:GetService("ServerStorage")
		local t0 = os.clock()
		while os.clock() - t0 < 20 do
			local f = ServerStorage:FindFirstChild("ItemModels")
			if f and f:GetAttribute("Ready") then break end
			task.wait(0.25)
		end
		while true do
			fetch()
			task.wait(HallOfFame.POLL)
		end
	end)
end

--- Live: not Studio and no harness session.
function HallOfFame.isLive()
	local ok, harness = pcall(function() return require(ServerScriptService.Modules.HarnessConfig).get() end)
	return not RunService:IsStudio() and not (ok and harness)
end

return HallOfFame
