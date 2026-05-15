-- CraftingManager.server.lua
-- Handles SubmitCraft, stat generation, and vehicle spawning.
-- Resolves: Issue #23, #28, #29, #65

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local ItemConfig     = require(ServerScriptService.Modules.ItemConfig)
local VehicleStats   = require(ReplicatedStorage.Shared.VehicleStats)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local BiomeConfig    = require(ServerScriptService.Modules.BiomeConfig)

-- ─── State ────────────────────────────────────────────────────────────────────

local _submitted    = {}   -- { [userId] = true }
local _totalPlayers = 0
local _active       = false

-- ─── Validate and apply a craft submission ────────────────────────────────────

local function _processCraft(player, slots)
	-- slots = {
	--   BODY = "Log", ENGINE = "Kettle", SPECIAL = "Rubber Duck",
	--   MOBILITY = "Kite", HEAD = "Cactus", TAIL = "Rocket"
	-- }
	local data = SessionManager.getData(player)
	if not data then return end

	local biome = GameManager.getBiome()

	-- Validate ownership: each named item must be in player's inventory
	local inventoryCopy = { table.unpack(data.inventory) }
	local used = {}
	for slotName, itemName in pairs(slots) do
		if itemName and itemName ~= "" then
			local found = false
			for i, invItem in ipairs(inventoryCopy) do
				if invItem == itemName and not used[i] then
					used[i] = true
					found = true
					break
				end
			end
			if not found then
				warn(string.format("[CraftingManager] %s: item '%s' not in inventory",
					player.Name, itemName))
				slots[slotName] = nil  -- drop the invalid slot silently
			end
		end
	end

	-- Look up configs
	local bodyCfg    = slots.BODY     and ItemConfig[slots.BODY]
	local engineCfg  = slots.ENGINE   and ItemConfig[slots.ENGINE]
	local specialCfg = slots.SPECIAL  and ItemConfig[slots.SPECIAL]
	local mobCfg     = slots.MOBILITY and ItemConfig[slots.MOBILITY]

	-- Calculate stats
	local stats = VehicleStats.calculate(bodyCfg, engineCfg, specialCfg, biome)
	stats = VehicleStats.applyMobility(stats, mobCfg, biome)

	-- Store HEAD/TAIL passives on stats for VehicleBuilder
	stats.headItem = slots.HEAD
	stats.tailItem = slots.TAIL
	stats.slotAssignments = slots

	SessionManager.setVehicle(player, nil, stats)
	print(string.format("[CraftingManager] %s submitted craft | spd=%.1f accel=%.1f",
		player.Name, stats.speed, stats.acceleration))
end

-- ─── SubmitCraft RemoteFunction ───────────────────────────────────────────────

RemoteEvents.SubmitCraft.OnServerInvoke = function(player, slots)
	if not _active then return "denied: not crafting" end
	if _submitted[player.UserId] then return "denied: already submitted" end

	_processCraft(player, slots)
	_submitted[player.UserId] = true

	-- Check if everyone has now submitted
	local count = 0
	for _ in pairs(_submitted) do count = count + 1 end
	if count >= _totalPlayers then
		GameManager.allPlayersSubmittedCraft()
	end

	return "ok"
end

-- ─── Auto-submit on timer expiry ─────────────────────────────────────────────

local function _autoSubmitAll()
	for _, player in ipairs(Players:GetPlayers()) do
		if not _submitted[player.UserId] then
			local data = SessionManager.getData(player)
			if data then
				-- Build best-effort slots from whatever is in inventory
				local inv = data.inventory
				local slots = {}
				local slotOrder = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }
				local idx = 1
				for _, slotName in ipairs(slotOrder) do
					if inv[idx] then
						slots[slotName] = inv[idx]
						idx = idx + 1
					end
				end
				_processCraft(player, slots)
				_submitted[player.UserId] = true
			end
		end
	end
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

GameManager.onPhaseChanged(function(phase, biome)
	if phase == Constants.PHASES.CRAFTING then
		_submitted    = {}
		_active       = true
		_totalPlayers = #Players:GetPlayers()

	elseif phase == Constants.PHASES.RACING then
		-- Auto-submit anyone who didn't manually submit
		_autoSubmitAll()
		_active = false

		-- Spawn vehicles for all players
		task.spawn(function()
			local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
			local spawnGrid = _buildSpawnGrid(biome)

			for i, player in ipairs(Players:GetPlayers()) do
				local data = SessionManager.getData(player)
				if not data then continue end

				local stats = data.vehicleStats or VehicleStats.calculate(nil, nil, nil, biome)
				local model = VehicleBuilder.build(
					stats,
					biome,
					spawnGrid[i] or CFrame.new(i * 6, 2, 0),
					stats.slotAssignments
				)

				if model then
					-- Anchor PrimaryPart so gravity doesn't drop the vehicle
					-- before the player is seated (critical for SKY biome).
					local primary = model.PrimaryPart
					if primary then primary.Anchored = true end

					model.Parent = game.Workspace

					-- Update SKY hover target to actual spawn Y after parenting
					if biome == "SKY" and primary then
						local hoverPos = primary:FindFirstChild("HoverPosition")
						if hoverPos then
							hoverPos.Position = primary.Position
						end
					end

					SessionManager.setVehicle(player, model, stats)

					-- One frame for replication before firing the client event.
					task.wait()

					local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
					if seat then
						print(string.format("[CraftingManager] Vehicle for %s spawned at %s | seat=%s",
							player.Name, tostring(primary and primary.Position), tostring(seat)))
						-- Seat player BEFORE firing VehicleSpawned so the drive loop
						-- starts only after the character is already welded to the seat.
						if player.Character then
							seat:Sit(player.Character:FindFirstChild("Humanoid"))
						end
						task.wait(0.1)  -- let weld settle
						RemoteEvents.VehicleSpawned:FireClient(player, player.UserId, model)
						-- Unanchor after sit takes effect so vehicle can move
						task.wait(0.1)
						if primary and primary.Parent then
							primary.Anchored = false
						end
					else
						warn("[CraftingManager] No VehicleSeat found in vehicle for", player.Name)
						if primary and primary.Parent then primary.Anchored = false end
						RemoteEvents.VehicleSpawned:FireClient(player, player.UserId, model)
					end
				else
					warn("[CraftingManager] VehicleBuilder.build returned nil for", player.Name)
				end
			end
		end)
	end
end)

-- ─── Build race start grid ────────────────────────────────────────────────────

function _buildSpawnGrid(biome)
	local cfg  = biome and BiomeConfig[biome]
	local startZ = (cfg and cfg.raceStartZ) or 195
	local startY = (cfg and cfg.raceStartY) or 2

	-- 2 rows of 5, staggered 8 studs apart, pointing down-Z (race direction)
	local grid = {}
	for i = 1, Constants.MAX_PLAYERS do
		local row = math.ceil(i / 5)
		local col = ((i - 1) % 5) + 1
		local x   = (col - 3) * 7
		local z   = startZ + (row - 1) * 8  -- row 1 at startZ, row 2 slightly behind
		table.insert(grid, CFrame.new(x, startY, z))
	end
	print(string.format("[CraftingManager] Race spawn grid: biome=%s startZ=%d startY=%d", tostring(biome), startZ, startY))
	return grid
end
