-- FarmingManager.server.lua
-- Item spawning, pickup authority, contest system, and inventory stealing.
-- Resolves: Issue #16, #17, #19, #36, #39, #64

print("[FarmingManager] Script started loading")

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local ItemConfig     = require(ServerScriptService.Modules.ItemConfig)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local ItemModelBuilder  = require(ServerScriptService.Modules.ItemModelBuilder)
local ItemVisualUpgrader = require(ServerScriptService.Modules.ItemVisualUpgrader)
local Telemetry          = require(ServerScriptService.Modules.Telemetry)
local FarmingRules       = require(ReplicatedStorage.Shared.FarmingRules)
local Cosmetics          = require(ReplicatedStorage.Shared.Cosmetics)
local PlayerStore        = require(ServerScriptService.Modules.PlayerStore)
local FarmBots           = require(ServerScriptService.Modules.FarmBots)
local FarmRescue         = require(ServerScriptService.Modules.FarmRescue)

print("[FarmingManager] All requires succeeded")

-- ─── State ────────────────────────────────────────────────────────────────────

-- Farm bots (Modules/FarmBots) stand in for players: a table with UserId,
-- Name, Character and isBot. They have no client, so nothing is sent to them.
local function _fireClient(remote, who, ...)
	if who and not (type(who) == "table" and who.isBot) then remote:FireClient(who, ...) end
end

local _resolveContest    -- defined below (contest resolution)
local _items      = {}   -- { [itemId] = { part, itemName, rarity, taken=false } }
local _contests   = {}   -- { [itemId] = { players={}, presses={}, endTick } }
local _phaseTimer = nil
local _active     = false
local _itemCounter = 0   -- monotonic ID so every spawned part gets a unique key
local _farmRound   = 0   -- item waves of an older round do nothing

-- Where the farm is, its floor and where items may land: Shared/FarmBounds
-- (the same numbers the maps build their walls from). The old table here had
-- farm centres at Z 350–390 (the farms are at 850 / 1850) and items were
-- spread over the FarmArea model's bounding box, decoration included.
local FarmBounds = require(ReplicatedStorage.Shared.FarmBounds)

-- ─── Weighted spawn pool ──────────────────────────────────────────────────────

local function _buildSpawnPool(dist)
	local pool = {}
	for rarity, names in pairs(ItemConfig._byRarity) do
		local count = (dist or Constants.RARITY_SPAWN_DIST)[rarity] or 0
		for _ = 1, count do
			if #names == 0 then continue end
			local name = names[math.random(#names)]
			table.insert(pool, { name = name, rarity = rarity })
		end
	end
	-- Shuffle
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return pool
end

-- ─── Spawn items ──────────────────────────────────────────────────────────────

-- `count` items (default: the whole pool) drawn with the rarity odds `dist`
-- (default RARITY_SPAWN_DIST). `keep`: add to the items already out (a wave).
local function _spawnItems(biome, count, dist, keep)
	if not keep then _items = {} end
	count = count or Constants.ITEM_SPAWN_COUNT
	print(string.format("[FarmingManager] _spawnItems called, biome=%s count=%d", tostring(biome), count))
	local pool = _buildSpawnPool(dist)
	print(string.format("[FarmingManager] Pool size: %d", #pool))
	local mapCfg = require(ServerScriptService.Modules.BiomeConfig).get(biome)
	-- Convert "FOREST" → "ForestMap" to match MapBuilder naming convention
	local mapName  = biome:sub(1,1):upper() .. biome:sub(2):lower() .. "Map"
	local mapModel = game.Workspace:FindFirstChild("Maps")
		and game.Workspace.Maps:FindFirstChild(mapName)

	if not mapModel then
		warn("[FarmingManager] Map not found for biome:", biome)
		return
	end

	-- Items land on the farm floor, inside the walls and clear of solid
	-- scenery (FarmBounds.itemSpotOk).
	local zone = FarmBounds.get(biome)
	local baseY = zone.floorY

	local usedPositions = {}
	if keep then
		for _, it in pairs(_items) do
			if not it.taken and it.part and it.part.Parent then table.insert(usedPositions, it.part.Position) end
		end
	end
	local already = #usedPositions
	local MIN_SEPARATION = 6  -- studs

	for i, entry in ipairs(pool) do
		if i > count then break end

		local cfg = ItemConfig[entry.name]
		if not cfg then continue end

		-- Find non-overlapping position (max 20 attempts)
		local pos
		for _ = 1, 20 do
			local candidate = FarmBounds.randomItemSpot(biome)
			local ok = true
			for _, used in ipairs(usedPositions) do
				if (candidate - used).Magnitude < MIN_SEPARATION then
					ok = false
					break
				end
			end
			if ok then
				pos = candidate
				break
			end
		end
		if not pos then continue end

		table.insert(usedPositions, pos)

		-- Clone pre-built model from ItemModelPreloader (Blender FBX or procedural)
		local model
		local buildOk, buildErr = pcall(function()
			local itemModels = ServerStorage:FindFirstChild("ItemModels")
			local prebuilt   = itemModels and itemModels:FindFirstChild(entry.name)
			if prebuilt then
				model        = prebuilt:Clone()
				model.Parent = mapModel
			else
				-- Fallback: build procedurally (shouldn't happen if Preloader ran)
				model = ItemModelBuilder.build(entry.name, mapModel)
			end
		end)
		if not buildOk then
			warn("[FarmingManager] Spawn error for '" .. entry.name .. "': " .. tostring(buildErr))
			continue
		end
		local primary = model and model.PrimaryPart
		if not primary then
			if model then model:Destroy() end
			continue
		end

		-- Position model: align the model's world-space AABB bottom with baseY,
		-- X/Z centered on pos. Pure translation only — SetPrimaryPartCFrame /
		-- PivotTo don't move FBX-imported nested parts.
		--
		-- IMPORTANT: anchor parts BEFORE translating. Preloader leaves parts
		-- non-anchored with WeldConstraints; setting CFrame on an unanchored
		-- welded part triggers weld snapping that cascades unpredictably across
		-- the model, scattering parts thousands of studs apart. Once both ends
		-- of every weld are anchored, welds become inert and per-part CFrame
		-- translation moves each part exactly by deltaPos.
		-- Compute the model's world-space AABB bottom Y by checking the 8
		-- corners of each BasePart. The previous shortcut
		-- `part.Position.Y - part.Size.Y * 0.5` is correct only for axis-
		-- aligned parts; FBX-imported models often have rotated subparts
		-- whose true world-space bottom is lower. Model:GetBoundingBox()
		-- isn't usable either because its orientation depends on PrimaryPart.
		--
		-- The bug shows up most visibly in SKY, where the FarmPlatform is a
		-- 9-stud-thick opaque rock slab from Y=71 to Y=80. Even a 0.5-stud
		-- sink hides items inside the slab; FOREST/OCEAN use a thin Baseplate
		-- so the same sink is still visible from above.
		local minBottomY = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored   = true
				part.CanCollide = false
				local cf  = part.CFrame
				local hsx = part.Size.X * 0.5
				local hsy = part.Size.Y * 0.5
				local hsz = part.Size.Z * 0.5
				for sx = -1, 1, 2 do
					for sy = -1, 1, 2 do
						for sz = -1, 1, 2 do
							local corner = cf * Vector3.new(sx * hsx, sy * hsy, sz * hsz)
							if corner.Y < minBottomY then minBottomY = corner.Y end
						end
					end
				end
			end
		end
		local deltaPos = Vector3.new(
			pos.X - primary.Position.X,
			pos.Y - minBottomY,
			pos.Z - primary.Position.Z
		)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CFrame = part.CFrame + deltaPos
			end
		end

		-- Metadata on PrimaryPart (for pickup detection)
		local nameVal = Instance.new("StringValue")
		nameVal.Name  = "ItemName"
		nameVal.Value = entry.name
		nameVal.Parent = primary

		local rarityVal = Instance.new("StringValue")
		rarityVal.Name  = "Rarity"
		rarityVal.Value = entry.rarity
		rarityVal.Parent = primary

		-- Rarity visuals + idle float/rotate
		local visualOk, visualErr = pcall(function()
			ItemVisualUpgrader.apply(model, entry.rarity)
		end)
		if not visualOk then
			warn("[FarmingManager] VisualUpgrader error for '" .. entry.name .. "': " .. tostring(visualErr))
		end

		-- Name label so players can identify items at a glance. Compact compared
		-- to the earlier billboard (removed in 386ae87) — single line, rarity-coloured.
		local cfg = ItemConfig[entry.name] or {}
		local billboard = Instance.new("BillboardGui")
		billboard.Name           = "NameTag"
		billboard.Size           = UDim2.new(0, 110, 0, 22)
		billboard.StudsOffset    = Vector3.new(0, 2.4, 0)
		billboard.AlwaysOnTop    = false
		billboard.MaxDistance    = 35   -- only visible up close so distant items don't clutter
		billboard.LightInfluence = 0
		billboard.Parent         = primary

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size                    = UDim2.fromScale(1, 1)
		nameLbl.BackgroundTransparency  = 1
		nameLbl.Text                    = (cfg.icon and (cfg.icon .. " ") or "") .. entry.name
		nameLbl.TextScaled              = true
		nameLbl.Font                    = Enum.Font.GothamBold
		nameLbl.TextStrokeTransparency  = 0.4
		nameLbl.TextColor3              = ({
			Common   = Color3.fromRGB(220, 220, 220),
			Uncommon = Color3.fromRGB(110, 230, 110),
			Rare     = Color3.fromRGB(120, 170, 255),
			Epic     = Color3.fromRGB(210, 130, 255),
		})[entry.rarity] or Color3.new(1, 1, 1)
		nameLbl.Parent                  = billboard

		-- Unique ID per item so _items keys never collide regardless of part name.
		-- tostring(part) returns the part's Name which is identical for all items
		-- built by the same builder (e.g. every barrel's primary is named "Body").
		_itemCounter = _itemCounter + 1
		local itemId = tostring(_itemCounter)
		local idVal = Instance.new("StringValue")
		idVal.Name   = "ItemId"
		idVal.Value  = itemId
		idVal.Parent = primary

		_items[itemId] = {
			part     = primary,
			model    = model,
			itemName = entry.name,
			rarity   = entry.rarity,
			taken    = false,
		}
	end

	print(string.format("[FarmingManager] Spawned %d items in %s", #usedPositions - already, biome))
	return #usedPositions - already
end

-- ─── Rarity rank (lower = weaker) ────────────────────────────────────────────


-- ─── Drop item from inventory (spawns it back in the world) ───────────────────

local function _dropItem(player, slotIndex, reason)
	local data = SessionManager.getData(player)
	if not data or not data.inventory[slotIndex] then return nil end

	local itemName = table.remove(data.inventory, slotIndex)
	Telemetry.record("item_drop", {
		userId = player.UserId, item = itemName, reason = reason or "manual", inventory = #data.inventory,
	})
	local cfg = ItemConfig[itemName]

	-- Spawn a new world item near the player
	local biome = (_active and (function()
		local gm = require(game.ServerScriptService.GameManager)
		return gm.getBiome()
	end)()) or "FOREST"
	local biomeZone = FarmBounds.get(biome)

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	-- Anchor spawn Y to the biome's farm ground. The previous version used
	-- root.Position.Y, but HumanoidRootPart sits ~2.5 studs above the floor,
	-- so dropped items reappeared floating in mid-air.
	-- Tossed a few studs ahead of the dropper (FarmFx animates the throw), a
	-- little to the side so two drops do not stack.
	local spawnPos
	if root then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
		local side = Vector3.new(-look.Z, 0, look.X)
		local at = root.Position + look * Constants.DROP_TOSS + side * (math.random() * 2 - 1) * 1.5
		-- never past the farm's walls (a drop next to one stays inside)
		local x, z = FarmBounds.clamp(biome, at.X, at.Z)
		spawnPos = Vector3.new(x, biomeZone.floorY, z)
	else
		spawnPos = Vector3.new(biomeZone.cx, biomeZone.floorY, biomeZone.cz)
	end

	local mapName  = biome:sub(1,1):upper() .. biome:sub(2):lower() .. "Map"
	local mapModel = game.Workspace:FindFirstChild("Maps")
		and game.Workspace.Maps:FindFirstChild(mapName)

	-- Clone the preloaded FBX template the same way _spawnItems does. The
	-- previous code went straight to ItemModelBuilder.build, which is the
	-- procedural-cube fallback — so any item dropped via auto-swap or the
	-- Q key reappeared as a white block instead of its real mesh.
	local model
	local ok, err = pcall(function()
		local itemModels = ServerStorage:FindFirstChild("ItemModels")
		local prebuilt   = itemModels and itemModels:FindFirstChild(itemName)
		if prebuilt then
			model        = prebuilt:Clone()
			model.Parent = mapModel or game.Workspace
		else
			model = ItemModelBuilder.build(itemName, mapModel or game.Workspace)
		end
	end)
	if not ok or not model or not model.PrimaryPart then
		if model then model:Destroy() end
		_fireClient(RemoteEvents.InventoryUpdated, player, data.inventory)
		return itemName
	end

	local primary = model.PrimaryPart
	-- Anchor before translating: FBX clones come out with WeldConstraints,
	-- and setting CFrame on an unanchored welded part snaps welds and
	-- scatters children. Same precaution as _spawnItems.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = false
		end
	end
	-- 8-corner world-space bottom-Y so rotated subparts (common in FBX) sit
	-- flush on the ground instead of half-buried.
	local minBottomY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local cf  = part.CFrame
			local hsx = part.Size.X * 0.5
			local hsy = part.Size.Y * 0.5
			local hsz = part.Size.Z * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = cf * Vector3.new(sx * hsx, sy * hsy, sz * hsz)
						if corner.Y < minBottomY then minBottomY = corner.Y end
					end
				end
			end
		end
	end
	local deltaPos = Vector3.new(
		spawnPos.X - primary.Position.X,
		spawnPos.Y - minBottomY,
		spawnPos.Z - primary.Position.Z
	)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = part.CFrame + deltaPos
		end
	end

	local rarity = cfg and cfg.rarity or "Common"

	local nameVal = Instance.new("StringValue")
	nameVal.Name = "ItemName"; nameVal.Value = itemName; nameVal.Parent = primary
	local rarVal = Instance.new("StringValue")
	rarVal.Name = "Rarity"; rarVal.Value = rarity; rarVal.Parent = primary

	pcall(function() ItemVisualUpgrader.apply(model, rarity) end)

	-- Name label (same widget as _spawnItems). Without this, dropped items
	-- reappeared as anonymous meshes with no rarity colour cue.
	local billboard = Instance.new("BillboardGui")
	billboard.Name           = "NameTag"
	billboard.Size           = UDim2.new(0, 110, 0, 22)
	billboard.StudsOffset    = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop    = false
	billboard.MaxDistance    = 35
	billboard.LightInfluence = 0
	billboard.Parent         = primary

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size                    = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency  = 1
	nameLbl.Text                    = ((cfg and cfg.icon) and (cfg.icon .. " ") or "") .. itemName
	nameLbl.TextScaled              = true
	nameLbl.Font                    = Enum.Font.GothamBold
	nameLbl.TextStrokeTransparency  = 0.4
	nameLbl.TextColor3              = ({
		Common   = Color3.fromRGB(220, 220, 220),
		Uncommon = Color3.fromRGB(110, 230, 110),
		Rare     = Color3.fromRGB(120, 170, 255),
		Epic     = Color3.fromRGB(210, 130, 255),
	})[rarity] or Color3.new(1, 1, 1)
	nameLbl.Parent                  = billboard

	_itemCounter = _itemCounter + 1
	local itemId = tostring(_itemCounter)
	local idVal = Instance.new("StringValue")
	idVal.Name = "ItemId"; idVal.Value = itemId; idVal.Parent = primary

	_items[itemId] = {
		part     = primary,
		model    = model,
		itemName = itemName,
		rarity   = rarity,
		taken    = false,
	}

	RemoteEvents.FarmAction:FireAllClients("drop", player.UserId, nil, {
		model = model, to = spawnPos, from = root and root.Position or nil, item = itemName, reason = reason or "manual",
	})
	Telemetry.record("item_dropped_world", { userId = player.UserId, item = itemName, itemId = itemId,
		x = math.floor(spawnPos.X), z = math.floor(spawnPos.Z), parts = #model:GetDescendants() })
	_fireClient(RemoteEvents.InventoryUpdated, player, data.inventory)
	return itemName
end

-- ─── Give item to player ──────────────────────────────────────────────────────

-- With a full inventory the weakest item is swapped out here, when the new
-- item is really handed over (it used to be dropped before the distance and
-- contest checks, so a refused pickup or a lost contest cost an item).
-- A picked-up item model moves (anchored parts, translated like the spawn
-- placement) into the picker's hands over PICKUP_FLY s, then is destroyed.
local function _flyToHands(model, root)
	model.Name = "PickedUp"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		elseif d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then d:Destroy() end
	end
	if not root then model:Destroy() return end
	local T = Constants.PICKUP_FLY
	task.spawn(function()
		-- a fixed number of frames (not the wall clock: a busy server, or the
		-- offline mock, would stretch it)
		local frames = math.max(1, math.ceil(T * 60))
		local i = 0
		while model.Parent and root.Parent do
			i += 1
			local k = math.min(1, i / frames)
			local ok, cf = pcall(function() return model:GetBoundingBox() end)
			if not ok then break end
			local hands = root.Position + root.CFrame.LookVector * 1.2 + Vector3.new(0, 0.8 + 1.5 * k, 0)
			local step = (hands - cf.Position) * math.min(1, k * 0.6 + 0.25)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = d.CFrame + step
					d.Transparency = math.max(d.Transparency, k * k)
				end
			end
			if k >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		model:Destroy()
	end)
end

local function _giveItem(player, itemId)
	local data = SessionManager.getData(player)
	local item = _items[itemId]
	if not data or not item or item.taken then return false end
	local slot, weakestIdx = FarmingRules.pickupSlot(data.inventory, item.itemName, ItemConfig, Constants.INVENTORY_SIZE)
	if slot == "full" then return false end
	if slot == "swap" then
		_dropItem(player, weakestIdx, "swap")
		if #data.inventory >= Constants.INVENTORY_SIZE then return false end
	end

	item.taken = true
	table.insert(data.inventory, item.itemName)

	-- Stop the idle animation; the item flies into the picker's hands
	-- (playtest 2026-10-29: items just vanished, no pick-up motion), then goes.
	if item.model then
		ItemVisualUpgrader.stopIdle(item.model)
		_flyToHands(item.model, player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
	else
		item.part:Destroy()
	end

	Telemetry.record("item_pickup", {
		userId = player.UserId, itemId = itemId, item = item.itemName,
		rarity = item.rarity, inventory = #data.inventory,
	})
	RemoteEvents.ItemPickedUp:FireAllClients(itemId, player.UserId, {
		rarity = item.rarity,
		userId = player.UserId,
		item = item.itemName,   -- ItemGuideUI: what a new item does
	})
	_fireClient(RemoteEvents.InventoryUpdated, player, data.inventory)
	return true
end

-- ─── RequestPickup handler ────────────────────────────────────────────────────

local function _requestPickup(player, itemId)
	if not _active then return "denied: phase not active" end

	local item = _items[itemId]
	if not item            then return "denied: item not found" end
	if item.taken          then return "denied: already taken" end
	-- A running contest locks the item for its two players (a third player
	-- used to take it once they had walked away).
	if _contests[itemId]   then return "contested" end

	local data = SessionManager.getData(player)
	if not data then return "denied: no player data" end

	-- Auto-swap: if inventory is full, drop the lowest-rarity item for a
	-- strictly rarer one (FarmingRules.pickupSlot).
	-- (the swap itself happens in _giveItem, once the pickup succeeds)
	if FarmingRules.pickupSlot(data.inventory, item.itemName, ItemConfig, Constants.INVENTORY_SIZE) == "full" then
		return "inventory_full"
	end

	-- Distance check — measured to the closest BasePart in the model, not just
	-- PrimaryPart. FBX-imported models can have PrimaryPart offset from the
	-- visible mesh; using the model's nearest point matches the client-side
	-- prompt range and avoids "denied: too far" when the player is clearly
	-- touching the item.
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return "denied: no character" end

	local closestDist = math.huge
	if item.model then
		for _, p in ipairs(item.model:GetDescendants()) do
			if p:IsA("BasePart") then
				local d = (root.Position - p.Position).Magnitude
				if d < closestDist then closestDist = d end
			end
		end
	else
		closestDist = (root.Position - item.part.Position).Magnitude
	end
	if closestDist > Constants.PICKUP_RANGE then
		return "denied: too far (" .. math.floor(closestDist) .. " studs)"
	end

	-- Check if another player (or bot) is also in range → start contest
	for _, otherPlayer in ipairs(SessionManager.actors()) do
		if otherPlayer == player then continue end
		local otherChar = otherPlayer.Character
		local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
		if not otherRoot then continue end
		if (otherRoot.Position - item.part.Position).Magnitude <= Constants.PICKUP_RANGE then
			-- Contest! Both players are competing
			if not _contests[itemId] then
				local contest = {
					players = { player, otherPlayer },
					presses = { [player.UserId] = 0, [otherPlayer.UserId] = 0 },
					endTick = tick() + Constants.CONTEST_DURATION,
				}
				_contests[itemId] = contest
				-- Ends on time even if nobody presses again (it used to wait for
				-- the next RequestContest and locked the item for the round).
				task.delay(Constants.CONTEST_DURATION, function()
					_resolveContest(itemId, contest)
				end)
				-- Notify both clients to start button-mash UI
				_fireClient(RemoteEvents.ContestUpdate, player,
					itemId,
					{ userId = player.UserId,      count = 0 },
					{ userId = otherPlayer.UserId, count = 0 }
				)
				_fireClient(RemoteEvents.ContestUpdate, otherPlayer,
					itemId,
					{ userId = player.UserId,      count = 0 },
					{ userId = otherPlayer.UserId, count = 0 }
				)
			end
			return "contested"
		end
	end

	-- Solo pickup
	if _giveItem(player, itemId) then
		return "ok"
	end
	return "denied: give failed"
end
RemoteEvents.RequestPickup.OnServerInvoke = _requestPickup

-- ─── RequestDrop handler (Q key — manual drop) ───────────────────────────────

RemoteEvents.RequestDrop.OnServerInvoke = function(player, slotIndex)
	if not _active then return "denied: phase not active" end
	if type(slotIndex) ~= "number" then return "denied: bad slot" end
	local dropped = _dropItem(player, slotIndex)
	return dropped and "ok" or "denied: empty slot"
end

-- ─── Contest resolution ───────────────────────────────────────────────────────

_resolveContest = function(itemId, contest)
	if _contests[itemId] ~= contest then return end   -- already resolved
	_contests[itemId] = nil
	local p1, p2 = contest.players[1], contest.players[2]
	local c1, c2 = contest.presses[p1.UserId] or 0, contest.presses[p2.UserId] or 0
	local winner, loser = p1, p2
	if FarmingRules.contestWinner(c1, c2) == 2 then winner, loser = p2, p1 end
	-- the winner left the game: the one still here gets it
	if not SessionManager.getData(winner) and SessionManager.getData(loser) then
		winner, loser = loser, winner
	end
	Telemetry.record("contest_result", {
		itemId = itemId, winner = winner.UserId, loser = loser.UserId,
		presses = { [tostring(p1.UserId)] = c1, [tostring(p2.UserId)] = c2 },
	})
	RemoteEvents.ContestResult:FireAllClients(itemId, winner.UserId)
	if _active then _giveItem(winner, itemId) end
end

-- ─── RequestContest handler (press count updates) ─────────────────────────────

local function _contestPress(player, itemId, presses)
	local contest = _contests[itemId]
	if not contest or type(presses) ~= "number" then return end
	if contest.players[1] ~= player and contest.players[2] ~= player then return end

	contest.presses[player.UserId] = math.min(presses, 999)  -- sanity cap

	-- Broadcast updated counts to both contestants
	local p1, p2 = contest.players[1], contest.players[2]
	local update = {
		{ userId = p1.UserId, count = contest.presses[p1.UserId] or 0 },
		{ userId = p2.UserId, count = contest.presses[p2.UserId] or 0 },
	}
	_fireClient(RemoteEvents.ContestUpdate, p1, itemId, update[1], update[2])
	_fireClient(RemoteEvents.ContestUpdate, p2, itemId, update[1], update[2])

	if tick() >= contest.endTick then
		_resolveContest(itemId, contest)
	end
end
RemoteEvents.RequestContest.OnServerInvoke = _contestPress

-- ─── RequestSteal handler ─────────────────────────────────────────────────────

local function _steal(thief, targetUserId)
	if not _active then return "denied: not farming" end

	local thiefData = SessionManager.getData(thief)
	local victim = SessionManager.actorById(targetUserId)
	local victimData = victim and SessionManager.getData(victim)
	if not thiefData or not victimData then return "denied: no such player" end
	local thiefRoot  = thief.Character  and thief.Character:FindFirstChild("HumanoidRootPart")
	local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not thiefRoot or not victimRoot then return "denied: no character" end

	local opened = false
	local function attempt(result)
		Telemetry.record("steal_attempt", { thief = thief.UserId, victim = victim.UserId, result = result })
		if opened then
			RemoteEvents.FarmAction:FireAllClients("grabEnd", thief.UserId, victim.UserId, { result = result })
		end
		return result
	end

	local ok, why = FarmingRules.canSteal({
		now = tick(),
		self = thief == victim,
		thiefBusy = thiefData._stealing ~= nil,
		victimUnderAttack = victimData._stealWindow ~= nil,
		thiefCooldownEnd = thiefData.stealCooldownEnd,
		farmingTimeLeft = (GameManager.phaseDuration("FARMING") or Constants.PHASE_DURATION.FARMING)
			- (tick() - (_farmingStartTick or 0)),
		disableBefore = Constants.STEAL_DISABLE_BEFORE,
		thiefItems = #thiefData.inventory, victimItems = #victimData.inventory,
		inventorySize = Constants.INVENTORY_SIZE,
		distance = (thiefRoot.Position - victimRoot.Position).Magnitude, range = Constants.STEAL_RANGE,
		victimInvincibleEnd = victimData.stealInvincibleEnd,
		victimHiddenEnd = victimData._hiddenUntil,
	})
	if not ok then return attempt("denied: " .. why) end

	-- Open the defence window: the victim's DefendSteal taps count only while
	-- it is open, and nobody else can start a steal on either player.
	local window = { thief = thief.UserId, presses = 0 }
	opened = true
	victimData._stealWindow = window
	thiefData._stealing = window
	_fireClient(RemoteEvents.StealAttempt, victim, thief.Name)
	RemoteEvents.FarmAction:FireAllClients("grab", thief.UserId, victim.UserId, { window = Constants.STEAL_DEFEND_WINDOW })
	local grabbedAt = tick()
	-- the window, cut short when the thief is punched off
	while tick() < grabbedAt + Constants.STEAL_DEFEND_WINDOW and not window.broken do task.wait(0.05) end
	victimData._stealWindow = nil
	thiefData._stealing = nil

	-- the victim threw a Smoke Bomb during the grab: gone, nothing taken
	if (victimData._smokedAt or 0) >= grabbedAt then
		thiefData.stealCooldownEnd = tick() + Constants.STEAL_DEFENDED_COOLDOWN
		return attempt("escaped")
	end

	-- punched mid-grab (FIGHT.BREAKS_GRAB): the thief let go
	if window.broken then
		thiefData.stealCooldownEnd = tick() + Constants.STEAL_DEFENDED_COOLDOWN
		return attempt("punched")
	end

	if FarmingRules.stealOutcome(window.presses, Constants.STEAL_DEFEND_PRESSES) == "defended" then
		thiefData.stealCooldownEnd = tick() + Constants.STEAL_DEFENDED_COOLDOWN
		return attempt("defended")
	end

	-- Re-check what may have changed during the window
	if not _active then return attempt("denied: farming ended") end
	if #victimData.inventory == 0 then return attempt("denied: victim has nothing") end
	if #thiefData.inventory >= Constants.INVENTORY_SIZE then return attempt("denied: thief is full") end

	local idx = math.random(#victimData.inventory)
	local stolenItem = table.remove(victimData.inventory, idx)
	table.insert(thiefData.inventory, stolenItem)

	thiefData.stealCooldownEnd   = tick() + Constants.STEAL_COOLDOWN
	victimData.stealInvincibleEnd = tick() + Constants.STEAL_INVINCIBLE
	victimData._robbedBy, victimData._robbedAt = thief.UserId, tick()   -- FarmBots go after the thief

	_fireClient(RemoteEvents.InventoryUpdated, thief,  thiefData.inventory)
	_fireClient(RemoteEvents.InventoryUpdated, victim, victimData.inventory)
	Telemetry.record("steal", {
		thief = thief.UserId, victim = victim.UserId, item = stolenItem,
		thiefInventory = #thiefData.inventory,
	})
	RemoteEvents.ItemStolen:FireAllClients(thief.Name, victim.Name, stolenItem)
	return attempt("stolen")
end
RemoteEvents.RequestSteal.OnServerInvoke = _steal

-- One call per defence tap. Taps outside an open window do nothing (a tap
-- sent "just in case" used to block the next steal whenever it came).
local function _defend(player)
	local data = SessionManager.getData(player)
	local window = data and data._stealWindow
	if window then
		window.presses += 1
		RemoteEvents.FarmAction:FireAllClients("swat", player.UserId, window.thief, { presses = window.presses })
		return window.presses
	end
	return 0
end
RemoteEvents.DefendSteal.OnServerInvoke = _defend

-- ─── Fights: punch (F) and guard (G) ─────────────────────────────────────────
-- Constants.FIGHT, FarmingRules.canPunch / punch. Every punch, guard, and
-- knock-out is broadcast as RemoteEvents.FarmAction so every client animates
-- it (StarterPlayerScripts/FarmFx); the victim's client also gets pushed back.

local F = Constants.FIGHT

local function _root(player)
	local c = player and player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function _flatUnit(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

-- The player the attacker is facing within reach (nearest), or nil.
-- How the player's punch looks (shop "move", e.g. "kick"); nil = a punch.
local function _moveStyle(player)
	if SessionManager.isBot(player) then return nil end
	local rec = PlayerStore.get(player)
	local mv = rec and Cosmetics.equipped(rec.equipped, "move")
	return mv and mv.style or nil
end

-- ─── Gadgets (shop "gadget"): RemoteEvents.UseGadget ──────────────────────────

RemoteEvents.UseGadget.OnServerInvoke = function(player)
	if not _active then return "denied: not farming" end
	local data = SessionManager.getData(player)
	local rec = PlayerStore.get(player)
	local g = rec and Cosmetics.equipped(rec.equipped, "gadget")
	if not data or not g then return "denied: no gadget" end
	local cfg = Constants.GADGETS[g.gadget]
	if not cfg then return "denied: no gadget" end
	data._gadgetUses = data._gadgetUses or {}
	local used = data._gadgetUses[g.gadget] or 0
	if used >= cfg.USES then return "denied: used" end
	data._gadgetUses[g.gadget] = used + 1
	local now = tick()
	if g.gadget == "smoke" then
		data._hiddenUntil = now + cfg.HIDE
		data._smokedAt = now
		local root = _root(player)
		RemoteEvents.FarmAction:FireAllClients("smoke", player.UserId, nil, {
			hide = cfg.HIDE, cloud = cfg.CLOUD, at = root and root.Position or nil,
		})
	end
	Telemetry.record("gadget", { userId = player.UserId, gadget = g.gadget, escaping = data._stealWindow ~= nil })
	return "ok"
end

-- `hintId`: the player the attacker's client turned to (aim help); taken
-- when within RANGE and in front by ASSIST_ARC (the client's turn may not
-- have reached the server yet), else the nearest one faced within ARC.
local function _punchTarget(attacker, aRoot, hintId)
	local look = _flatUnit(aRoot.CFrame.LookVector)
	local best, bestD
	for _, other in ipairs(SessionManager.actors()) do
		local od = other ~= attacker and SessionManager.getData(other)
		local hidden = od and (od._hiddenUntil or 0) > tick()   -- in a Smoke Bomb
		local r = other ~= attacker and not hidden and _root(other)
		if r then
			local to = Vector3.new(r.Position.X - aRoot.Position.X, 0, r.Position.Z - aRoot.Position.Z)
			local d = to.Magnitude
			local facing = d > 1e-3 and look:Dot(to.Unit) or 1
			local hinted = hintId ~= nil and other.UserId == hintId
			-- the hinted one within the client's own reach (RANGE + ASSIST_REACH):
			-- it swung at someone it saw in reach, who stepped back meanwhile
			local ok = FarmingRules.canPunch({ now = 0, distance = d,
				range = hinted and (F.RANGE + F.ASSIST_REACH) or F.RANGE, facing = facing,
				arc = hinted and F.ASSIST_ARC or F.ARC })
			if ok and hinted then return other end
			if ok and (not bestD or d < bestD) then best, bestD = other, d end
		end
	end
	return best
end

local function _setGuard(player, data, on)
	data._guardUntil = on and (tick() + F.GUARD_MAX) or nil
	local c = player.Character
	if c then c:SetAttribute("Guarding", on or nil) end
	RemoteEvents.FarmAction:FireAllClients("guard", player.UserId, nil, { on = on })
end

local function _guard(player, on)
	if not _active then return end
	local data = SessionManager.getData(player)
	if not data then return end
	on = on == true
	if on == ((data._guardUntil or 0) > tick()) then return end
	_setGuard(player, data, on)
	if on then
		-- a guard cannot be held forever
		local untilT = data._guardUntil
		task.delay(F.GUARD_MAX, function()
			if data._guardUntil == untilT then _setGuard(player, data, false) end
		end)
	end
end
RemoteEvents.SetGuard.OnServerEvent:Connect(_guard)

local function _punch(attacker, hintId)
	if not _active then return "denied: not farming" end
	if type(hintId) ~= "number" then hintId = nil end
	local aData = SessionManager.getData(attacker)
	local aRoot = _root(attacker)
	if not aData or not aRoot then return "denied: no character" end
	local now = tick()
	if now < (aData._punchCooldownEnd or 0) then return "denied: cooldown" end
	aData._punchCooldownEnd = now + F.COOLDOWN
	if (aData._guardUntil or 0) > now then _setGuard(attacker, aData, false) end   -- punching drops your guard

	local victim = _punchTarget(attacker, aRoot, hintId)
	if not victim then
		RemoteEvents.FarmAction:FireAllClients("punch", attacker.UserId, nil, { result = "miss", style = _moveStyle(attacker) })
		Telemetry.record("punch", { attacker = attacker.UserId, result = "miss" })
		return "miss"
	end
	local vData = SessionManager.getData(victim)
	local result, hits = FarmingRules.punch({
		now = now, hits = vData._hits, lastHitAt = vData._lastHitAt, memory = F.HIT_MEMORY,
		guarding = (vData._guardUntil or 0) > now, immuneEnd = vData._knockImmuneEnd,
		needed = F.HITS_TO_DROP, items = #vData.inventory,
	})
	if result == "hit" or result == "knockout" then
		vData._hits, vData._lastHitAt, vData._lastHitBy = hits, now, attacker.UserId
		-- a thief punched mid-grab lets go (FIGHT.BREAKS_GRAB): nothing taken
		if F.BREAKS_GRAB and vData._stealing then vData._stealing.broken = attacker.UserId end
	end
	local dropped
	if result == "knockout" then
		vData._knockImmuneEnd = now + F.DROP_IMMUNE
		dropped = _dropItem(victim, math.random(#vData.inventory), "knocked_out")
	end
	local vRoot = _root(victim)
	local push = vRoot and _flatUnit(vRoot.Position - aRoot.Position) * F.KNOCKBACK
		* (result == "knockout" and F.KO_KNOCKBACK or 1) or Vector3.zero
	-- a farm bot is pushed here (a player's own client pushes them, FarmFx):
	-- a hit must visibly land, not bounce off a statue
	if vRoot and SessionManager.isBot(victim) and (result == "hit" or result == "knockout") then
		pcall(function()
			vRoot.AssemblyLinearVelocity += push * F.BOT_KNOCKBACK + Vector3.new(0, F.KNOCK_UP, 0)
		end)
	end
	RemoteEvents.FarmAction:FireAllClients("punch", attacker.UserId, victim.UserId, {
		style = _moveStyle(attacker),
		result = result, hits = (result == "knockout") and F.HITS_TO_DROP or hits, needed = F.HITS_TO_DROP,
		item = dropped, push = (result == "hit" or result == "knockout") and push or nil,
	})
	Telemetry.record("punch", {
		attacker = attacker.UserId, victim = victim.UserId, result = result, hits = hits, item = dropped,
	})
	return result
end
RemoteEvents.RequestPunch.OnServerInvoke = _punch

-- ─── Phase listener ───────────────────────────────────────────────────────────

_farmingStartTick = 0

print("[FarmingManager] Registering onPhaseChanged callback")
GameManager.onPhaseChanged(function(phase, biome)
	print(string.format("[FarmingManager] onPhaseChanged fired: phase=%s biome=%s", tostring(phase), tostring(biome)))
	if phase == Constants.PHASES.FARMING then
		_active = true
		_farmingStartTick = tick()
		_farmRound += 1
		for _, p in ipairs(Players:GetPlayers()) do
			local d = SessionManager.getData(p)
			if d then d._gadgetUses, d._hiddenUntil, d._smokedAt = nil, nil, nil end
			-- which gadget button to show (TouchControls / FarmingClient)
			local rec = PlayerStore.get(p)
			local g = rec and Cosmetics.equipped(rec.equipped, "gadget")
			p:SetAttribute("Gadget", g and g.gadget or nil)
		end
		local round = _farmRound
		print("[FarmingManager] Starting FARMING phase, biome =", biome)
		-- Item supply follows the player count, and waves of rarer items land
		-- later in the phase (Constants.FARM_SUPPLY): with 100 items for 4
		-- players every inventory was full 15–50 s into a 90 s phase.
		local humans = #Players:GetPlayers()
		-- this round's head count (players + bots; RaceBots reads the same draw)
		require(ServerScriptService.Modules.BotFill).roll()
		local n = humans + FarmBots.wanted(humans, GameManager.getHarness())
		local first = _spawnItems(biome, Constants.farmSupply(n))
		-- Bots fill an empty farm (live servers; harness `fillBots`)
		FarmRescue.start(biome)   -- nobody leaves the farm (Shared/FarmBounds)
		FarmBots.start(biome, {
			items = function() return _items, _contests end,
			pickup = _requestPickup, contestPress = _contestPress, punch = _punch, defend = _defend,
			steal = _steal, guard = _guard,
		})

		Telemetry.record("item_wave", { wave = 0, count = first, players = n })
		local length = GameManager.phaseDuration(Constants.PHASES.FARMING) or Constants.PHASE_DURATION.FARMING
		for w, wave in ipairs(Constants.FARM_SUPPLY.WAVES) do
			task.delay(length * wave.at, function()
				if not _active or _farmRound ~= round then return end
				local players = #SessionManager.actors()
				local count = _spawnItems(biome, math.max(1, math.ceil(players * wave.perPlayer)), wave.dist, true)
				Telemetry.record("item_wave", { wave = w, count = count, players = players })
				RemoteEvents.ScreenEffect:FireAllClients("itemWave", { count = count, rare = wave.label })
			end)
		end
		print("[FarmingManager] After spawn: total items registered =", (function()
			local n = 0; for _ in pairs(_items) do n = n + 1 end; return n
		end)())

	elseif phase == Constants.PHASES.LOBBY then
		FarmRescue.stop()
		FarmBots.clear()
	elseif phase == Constants.PHASES.CRAFTING then
		_active = false
		_contests = {}
		FarmRescue.stop()
		FarmBots.stop()
		-- fights end with the phase: drop guards and hit counts
		for _, p in ipairs(SessionManager.actors()) do
			local d = SessionManager.getData(p)
			if d then
				d._hits, d._lastHitAt, d._knockImmuneEnd, d._punchCooldownEnd = nil, nil, nil, nil
				if (d._guardUntil or 0) > 0 then _setGuard(p, d, false) end
			end
		end
		-- Destroy any remaining unclaimed items
		for _, item in pairs(_items) do
			if not item.taken then
				if item.model and item.model.Parent then
					ItemVisualUpgrader.stopIdle(item.model)
					item.model:Destroy()
				elseif item.part and item.part.Parent then
					item.part:Destroy()
				end
			end
		end
		_items = {}
	end
end)
