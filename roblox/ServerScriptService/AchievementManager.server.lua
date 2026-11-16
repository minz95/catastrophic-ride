-- AchievementManager.server.lua
-- Achievements (Shared/Achievements): counts each player's Telemetry events,
-- and when one is done unlocks and puts on its reward (hat, trail, ride
-- pose), awards its Roblox badge, tells the player
-- (RemoteEvents.AchievementUpdate) and, when the owner has uploaded the
-- reward as an avatar item (`ugc` id), opens Roblox's prompt to get it.
-- RemoteEvents.AchievementAction("ugc", key) opens that prompt again for an
-- achievement the player has (the Awards tab's button).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local GameManager = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local Badges = require(ServerScriptService.Modules.Badges)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)
local Shop = require(ServerScriptService.Modules.Shop)

local UGC_GAP = 3   -- s between two get-item prompts asked by one player
local _lastUgc = {}

local function bodyOf(userId)
	local p = Players:GetPlayerByUserId(userId)
	local d = p and SessionManager.getData(p)
	local slots = d and d.vehicleStats and d.vehicleStats.slotAssignments
	return slots and slots.BODY
end

--- Roblox's get-item prompt for each of achievement `a`'s avatar items the
-- player does not own yet, one after the other (a prompt open hides the
-- next). False when the achievement has none uploaded.
local PROMPT_WAIT = 90   -- s to wait for a prompt to be closed
local function promptUgc(player, a)
	local ids = Achievements.ugcIds(a)
	if #ids == 0 then return false end
	task.spawn(function()
		local MarketplaceService = game:GetService("MarketplaceService")
		for _, id in ipairs(ids) do
			local ok, owns = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, player, id)
			if not (ok and owns) and player.Parent then
				local closed = false
				local conn
				pcall(function()
					conn = MarketplaceService.PromptPurchaseFinished:Connect(function(p, asset)
						if p == player and asset == id then closed = true end
					end)
				end)
				pcall(MarketplaceService.PromptPurchase, MarketplaceService, player, id)
				local t0 = os.clock()
				while conn and not closed and player.Parent and os.clock() - t0 < PROMPT_WAIT do task.wait(0.5) end
				if conn then conn:Disconnect() end
			end
		end
	end)
	return true
end

local function earned(player, rec, list)
	for _, a in ipairs(list) do
		Badges.award(player, "ach_" .. a.key)
		local it = Cosmetics.get(a.reward)
		RemoteEvents.AchievementUpdate:FireClient(player, {
			key = a.key, name = a.name, text = a.text,
			reward = it and it.name, category = it and it.category, ugc = Achievements.hasUgc(a),
		})
		promptUgc(player, a)
		-- task.defer: this runs inside Telemetry.record's loop
		task.defer(Telemetry.record, "achievement", { userId = player.UserId, key = a.key, reward = a.reward })
	end
	PlayerStore.saveSoon(player)
	-- the reward is on now: hat / pose on the avatar, the car's trail on the next build
	require(ServerScriptService.Modules.ShopHat).refresh(player)
	require(ServerScriptService.Modules.CraftPreview).refresh(player)
	RemoteEvents.ShopUpdated:FireClient(player, Shop.state(rec))
end

Telemetry.onRecord(function(kind, e)
	local evs = Achievements.eventsOf(kind, e, { biome = GameManager.getBiome(), bodyOf = bodyOf })
	for _, x in ipairs(evs) do
		local player = Players:GetPlayerByUserId(x.userId)
		local rec = player and PlayerStore.get(player)
		if rec then
			local list = Achievements.step(rec, x.ev, x.value)
			if #list > 0 then
				earned(player, rec, list)
			else
				PlayerStore.saveSoon(player)
			end
		end
	end
end)

RemoteEvents.AchievementAction.OnServerInvoke = function(player, action, key)
	local rec = PlayerStore.get(player)
	if not rec then return { result = "denied: loading" } end
	if action == "state" then
		return { result = "ok", list = Achievements.view(rec) }
	elseif action == "ugc" then
		local a = type(key) == "string" and Achievements.get(key)
		if not a then return { result = "denied: unknown" } end
		if not Achievements.state(rec).done[a.key] then return { result = "denied: not earned" } end
		local now = os.clock()
		if _lastUgc[player.UserId] and now - _lastUgc[player.UserId] < UGC_GAP then
			return { result = "denied: busy" }
		end
		_lastUgc[player.UserId] = now
		return { result = promptUgc(player, a) and "ok" or "denied: no item" }
	end
	return { result = "denied: bad action" }
end

Players.PlayerRemoving:Connect(function(player)
	_lastUgc[player.UserId] = nil
end)
