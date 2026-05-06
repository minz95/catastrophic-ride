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

print("[FarmingManager] All requires succeeded")

-- ─── State ────────────────────────────────────────────────────────────────────

local _items      = {}   -- { [itemId] = { part, itemName, rarity, taken=false } }
local _contests   = {}   -- { [itemId] = { players={}, presses={}, endTick } }
local _phaseTimer = nil
local _active     = false
local _itemCounter = 0   -- monotonic ID so every spawned part gets a unique key

-- ─── Weighted spawn pool ──────────────────────────────────────────────────────

local function _buildSpawnPool()
	local pool = {}
	for rarity, names in pairs(ItemConfig._byRarity) do
		local count = Constants.RARITY_SPAWN_DIST[rarity] or 0
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

local function _spawnItems(biome)
	_items = {}
	print(string.format("[FarmingManager] _spawnItems called, biome=%s", tostring(biome)))
	local pool = _buildSpawnPool()
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

	-- Derive farm area bounds from FarmSpawnPoint parts inside this biome's map.
	-- Each MapBuilder places tagged FarmSpawnPoint Parts at the correct position
	-- and height for their biome — using them avoids hardcoded coordinates that
	-- break for SKY (floating platforms) and OCEAN (elevated dock/island).
	local spawnCX, spawnCZ, halfX, halfZ, baseY

	-- Per-biome hardcoded spawn zones that match each MapBuilder's farm area exactly.
	-- Bounding-box inference is unreliable (tall trees skew Y; water planes skew X/Z).
	local BIOME_ZONES = {
		FOREST = { cx=0, cz=350, halfX=80, halfZ=120, baseY=1.0 },  -- FarmGround surface Y=1
		OCEAN  = { cx=0, cz=375, halfX=55, halfZ=90,  baseY=5.0 },  -- FarmGrass surface Y=5 (WATER_Y+2.5+0.5)
		SKY    = { cx=0, cz=390, halfX=35, halfZ=70,  baseY=80.0 }, -- FarmPlatform surface Y=80
	}

	-- Always use hardcoded baseY: bounding-box Y is skewed by tall objects (barn, trees).
	local zone = BIOME_ZONES[biome] or BIOME_ZONES.FOREST
	baseY = zone.baseY

	local farmModel = mapModel:FindFirstChild("FarmArea")
	if farmModel then
		-- Use bounding box only for horizontal extent (X/Z), not Y.
		local fcf, fsize = farmModel:GetBoundingBox()
		spawnCX = fcf.Position.X
		spawnCZ = fcf.Position.Z
		halfX   = math.min(fsize.X * 0.45, 80)
		halfZ   = math.min(fsize.Z * 0.45, 150)
	else
		spawnCX = zone.cx
		spawnCZ = zone.cz
		halfX   = zone.halfX
		halfZ   = zone.halfZ
	end
	print(string.format("[FarmingManager] Spawn zone biome=%s cx=%d cz=%d halfX=%d halfZ=%d baseY=%.1f",
		tostring(biome), spawnCX, spawnCZ, halfX, halfZ, baseY))

	local usedPositions = {}
	local MIN_SEPARATION = 6  -- studs

	for i, entry in ipairs(pool) do
		if i > Constants.ITEM_SPAWN_COUNT then break end

		local cfg = ItemConfig[entry.name]
		if not cfg then continue end

		-- Find non-overlapping position (max 20 attempts)
		local pos
		for _ = 1, 20 do
			local candidate = Vector3.new(
				spawnCX + (math.random() * 2 - 1) * halfX,
				baseY,
				spawnCZ + (math.random() * 2 - 1) * halfZ
			)
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

		-- Position model: align the model's overall bottom (lowest point of any
		-- BasePart) with baseY, X/Z centered on pos. Pure translation only —
		-- SetPrimaryPartCFrame/PivotTo don't move FBX-imported nested parts.
		--
		-- IMPORTANT: anchor parts BEFORE translating. Preloader leaves parts
		-- non-anchored with WeldConstraints; setting CFrame on an unanchored
		-- welded part triggers weld snapping that cascades unpredictably across
		-- the model, scattering parts thousands of studs apart. Once both ends
		-- of every weld are anchored, welds become inert and per-part CFrame
		-- translation moves each part exactly by deltaPos.
		local minBottomY = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local b = part.Position.Y - part.Size.Y * 0.5
				if b < minBottomY then minBottomY = b end
				part.Anchored   = true
				part.CanCollide = false
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

		-- Billboard label above item (always visible)
		local billboard = Instance.new("BillboardGui")
		billboard.Size         = UDim2.new(0, 120, 0, 44)
		billboard.StudsOffset  = Vector3.new(0, 3.5, 0)
		billboard.AlwaysOnTop  = false
		billboard.ResetOnSpawn = false
		billboard.Parent       = primary

		local icon = Instance.new("TextLabel")
		icon.Size             = UDim2.new(1, 0, 0.55, 0)
		icon.BackgroundTransparency = 1
		icon.Text             = (cfg.icon or "?")
		icon.TextScaled       = true
		icon.Font             = Enum.Font.GothamBold
		icon.TextColor3       = Color3.new(1, 1, 1)
		icon.Parent           = billboard

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size          = UDim2.new(1, 0, 0.45, 0)
		nameLbl.Position      = UDim2.new(0, 0, 0.55, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text          = entry.name
		nameLbl.TextScaled    = true
		nameLbl.Font          = Enum.Font.Gotham
		local rarityColour = ({
			Common   = Color3.fromRGB(200, 200, 200),
			Uncommon = Color3.fromRGB(80,  200, 80),
			Rare     = Color3.fromRGB(100, 160, 255),
			Epic     = Color3.fromRGB(200, 100, 255),
		})[entry.rarity] or Color3.new(1,1,1)
		nameLbl.TextColor3    = rarityColour
		nameLbl.TextStrokeTransparency = 0.4
		nameLbl.Parent        = billboard

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

	print(string.format("[FarmingManager] Spawned %d items in %s", #usedPositions, biome))
end

-- ─── Rarity rank (lower = weaker) ────────────────────────────────────────────

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }

-- ─── Drop item from inventory (spawns it back in the world) ───────────────────

local function _dropItem(player, slotIndex)
	local data = SessionManager.getData(player)
	if not data or not data.inventory[slotIndex] then return nil end

	local itemName = table.remove(data.inventory, slotIndex)
	local cfg = ItemConfig[itemName]

	-- Spawn a new world item near the player
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local spawnPos = root and (root.Position + Vector3.new(math.random(-3,3), 0, math.random(-3,3)))
		or Vector3.new(0, 5, 0)

	local mapName  = (_active and (function()
		local gm = require(game.ServerScriptService.GameManager)
		return gm.getBiome()
	end)()) or "FOREST"
	mapName = mapName:sub(1,1):upper() .. mapName:sub(2):lower() .. "Map"
	local mapModel = game.Workspace:FindFirstChild("Maps")
		and game.Workspace.Maps:FindFirstChild(mapName)

	local model
	local ok, err = pcall(function()
		model = ItemModelBuilder.build(itemName, mapModel or game.Workspace)
	end)
	if not ok or not model or not model.PrimaryPart then
		if model then model:Destroy() end
		RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)
		return itemName
	end

	local primary = model.PrimaryPart
	local minBottomY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local b = part.Position.Y - part.Size.Y * 0.5
			if b < minBottomY then minBottomY = b end
		end
	end
	local deltaPos = Vector3.new(
		spawnPos.X - primary.Position.X,
		spawnPos.Y - minBottomY,
		spawnPos.Z - primary.Position.Z
	)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame     = part.CFrame + deltaPos
			part.Anchored   = true
			part.CanCollide = false
		end
	end

	local rarity = cfg and cfg.rarity or "Common"

	local nameVal = Instance.new("StringValue")
	nameVal.Name = "ItemName"; nameVal.Value = itemName; nameVal.Parent = primary
	local rarVal = Instance.new("StringValue")
	rarVal.Name = "Rarity"; rarVal.Value = rarity; rarVal.Parent = primary

	pcall(function() ItemVisualUpgrader.apply(model, rarity) end)

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

	RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)
	return itemName
end

-- ─── Give item to player ──────────────────────────────────────────────────────

local function _giveItem(player, itemId)
	local data = SessionManager.getData(player)
	local item = _items[itemId]
	if not data or not item or item.taken then return false end
	if #data.inventory >= Constants.INVENTORY_SIZE then return false end

	item.taken = true
	table.insert(data.inventory, item.itemName)

	-- Stop idle animation then destroy full model
	if item.model then
		ItemVisualUpgrader.stopIdle(item.model)
		item.model:Destroy()
	else
		item.part:Destroy()
	end

	RemoteEvents.ItemPickedUp:FireAllClients(itemId, player.UserId, {
		rarity = item.rarity,
		userId = player.UserId,
	})
	RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)
	return true
end

-- ─── RequestPickup handler ────────────────────────────────────────────────────

RemoteEvents.RequestPickup.OnServerInvoke = function(player, itemId)
	if not _active then return "denied: phase not active" end

	local item = _items[itemId]
	if not item            then return "denied: item not found" end
	if item.taken          then return "denied: already taken" end

	local data = SessionManager.getData(player)
	if not data then return "denied: no player data" end

	-- Auto-swap: if inventory is full, drop the lowest-rarity item and pick up the new one.
	if #data.inventory >= Constants.INVENTORY_SIZE then
		local newCfg = ItemConfig[item.itemName]
		local newRank = RARITY_RANK[newCfg and newCfg.rarity or "Common"] or 1

		-- Find the weakest item in inventory
		local weakestIdx, weakestRank = 1, 999
		for i, name in ipairs(data.inventory) do
			local r = RARITY_RANK[(ItemConfig[name] and ItemConfig[name].rarity) or "Common"] or 1
			if r < weakestRank then weakestRank = r; weakestIdx = i end
		end

		-- Only swap if the new item is strictly better than the weakest held item
		if newRank <= weakestRank then
			return "inventory_full"
		end

		local droppedName = _dropItem(player, weakestIdx)
		-- Notify client which item was auto-dropped
		if droppedName then
			local cfg = ItemConfig[droppedName]
			RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)
			-- Re-check size after drop
			if #data.inventory >= Constants.INVENTORY_SIZE then
				return "inventory_full"
			end
		end
	end

	-- Distance check
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return "denied: no character" end

	local dist = (root.Position - item.part.Position).Magnitude
	if dist > Constants.PICKUP_RANGE then
		return "denied: too far (" .. math.floor(dist) .. " studs)"
	end

	-- Check if another player is also in range → start contest
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer == player then continue end
		local otherChar = otherPlayer.Character
		local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
		if not otherRoot then continue end
		if (otherRoot.Position - item.part.Position).Magnitude <= Constants.PICKUP_RANGE then
			-- Contest! Both players are competing
			if not _contests[itemId] then
				_contests[itemId] = {
					players = { player, otherPlayer },
					presses = { [player.UserId] = 0, [otherPlayer.UserId] = 0 },
					endTick = tick() + Constants.CONTEST_DURATION,
				}
				-- Notify both clients to start button-mash UI
				RemoteEvents.ContestUpdate:FireClient(player,
					itemId,
					{ userId = player.UserId,      count = 0 },
					{ userId = otherPlayer.UserId, count = 0 }
				)
				RemoteEvents.ContestUpdate:FireClient(otherPlayer,
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

-- ─── RequestDrop handler (Q key — manual drop) ───────────────────────────────

RemoteEvents.RequestDrop.OnServerInvoke = function(player, slotIndex)
	if not _active then return "denied: phase not active" end
	if type(slotIndex) ~= "number" then return "denied: bad slot" end
	local dropped = _dropItem(player, slotIndex)
	return dropped and "ok" or "denied: empty slot"
end

-- ─── RequestContest handler (press count updates) ─────────────────────────────

RemoteEvents.RequestContest.OnServerInvoke = function(player, itemId, presses)
	local contest = _contests[itemId]
	if not contest then return end

	contest.presses[player.UserId] = math.min(presses, 999)  -- sanity cap

	-- Broadcast updated counts to both contestants
	local p1, p2 = contest.players[1], contest.players[2]
	local update = {
		{ userId = p1.UserId, count = contest.presses[p1.UserId] or 0 },
		{ userId = p2.UserId, count = contest.presses[p2.UserId] or 0 },
	}
	RemoteEvents.ContestUpdate:FireClient(p1, itemId, update[1], update[2])
	RemoteEvents.ContestUpdate:FireClient(p2, itemId, update[1], update[2])

	-- Check if contest time is up
	if tick() >= contest.endTick then
		local winner, loser
		if (contest.presses[p1.UserId] or 0) >= (contest.presses[p2.UserId] or 0) then
			winner, loser = p1, p2
		else
			winner, loser = p2, p1
		end

		RemoteEvents.ContestResult:FireAllClients(itemId, winner.UserId)
		_giveItem(winner, itemId)
		_contests[itemId] = nil
	end
end

-- ─── RequestSteal handler ─────────────────────────────────────────────────────

RemoteEvents.RequestSteal.OnServerInvoke = function(thief, targetUserId)
	if not _active then return end

	-- Check steal cooldown
	local thiefData = SessionManager.getData(thief)
	if not thiefData then return end
	if tick() < thiefData.stealCooldownEnd then return end

	-- CRAFTING lock-out
	local timeLeft = Constants.PHASE_DURATION.FARMING
		- (tick() - (_farmingStartTick or 0))
	if timeLeft < Constants.STEAL_DISABLE_BEFORE then return end

	local victim = Players:GetPlayerByUserId(targetUserId)
	if not victim then return end

	local victimData = SessionManager.getData(victim)
	if not victimData then return end
	if #victimData.inventory == 0 then return end

	-- Distance check
	local thiefRoot  = thief.Character  and thief.Character:FindFirstChild("HumanoidRootPart")
	local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not thiefRoot or not victimRoot then return end
	if (thiefRoot.Position - victimRoot.Position).Magnitude > Constants.STEAL_RANGE then return end

	-- Invincibility check
	if tick() < victimData.stealInvincibleEnd then return end

	-- Notify victim — they have STEAL_DEFEND_WINDOW seconds to defend
	RemoteEvents.StealAttempt:FireClient(victim, thief.Name)

	-- Wait for defence window
	task.wait(Constants.STEAL_DEFEND_WINDOW)

	-- Check if victim successfully defended (DefendSteal sets a flag)
	if victimData._defendingSteal then
		victimData._defendingSteal = false
		-- Stun thief briefly
		thiefData.stealCooldownEnd = tick() + 0.5
		return
	end

	-- Steal succeeds: take random item
	local idx = math.random(#victimData.inventory)
	local stolenItem = table.remove(victimData.inventory, idx)
	table.insert(thiefData.inventory, stolenItem)

	thiefData.stealCooldownEnd   = tick() + Constants.STEAL_COOLDOWN
	victimData.stealInvincibleEnd = tick() + Constants.STEAL_INVINCIBLE

	RemoteEvents.InventoryUpdated:FireClient(thief,  thiefData.inventory)
	RemoteEvents.InventoryUpdated:FireClient(victim, victimData.inventory)
	RemoteEvents.ItemStolen:FireAllClients(thief.Name, victim.Name, stolenItem)
end

RemoteEvents.DefendSteal.OnServerInvoke = function(player)
	local data = SessionManager.getData(player)
	if data then
		data._defendingSteal = true
	end
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

_farmingStartTick = 0

print("[FarmingManager] Registering onPhaseChanged callback")
GameManager.onPhaseChanged(function(phase, biome)
	print(string.format("[FarmingManager] onPhaseChanged fired: phase=%s biome=%s", tostring(phase), tostring(biome)))
	if phase == Constants.PHASES.FARMING then
		_active = true
		_farmingStartTick = tick()
		print("[FarmingManager] Starting FARMING phase, biome =", biome)
		_spawnItems(biome)
		print("[FarmingManager] After spawn: total items registered =", (function()
			local n = 0; for _ in pairs(_items) do n = n + 1 end; return n
		end)())

	elseif phase == Constants.PHASES.CRAFTING then
		_active = false
		_contests = {}
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
