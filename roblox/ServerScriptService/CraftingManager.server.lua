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
local CraftingRules  = require(ReplicatedStorage.Shared.CraftingRules)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local BiomeConfig    = require(ServerScriptService.Modules.BiomeConfig)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local RaceStart      = require(ServerScriptService.Modules.RaceStart)

-- ─── State ────────────────────────────────────────────────────────────────────

local _submitted    = {}   -- { [userId] = true }
local _totalPlayers = 0
local _active       = false

-- ─── Validate and apply a craft submission ────────────────────────────────────

local function _processCraft(player, submitted, auto)
	local data = SessionManager.getData(player)
	if not data then return end

	local biome = GameManager.getBiome()

	local slots, rejected = CraftingRules.validate(submitted, data.inventory, ItemConfig)
	if not slots then return end
	for _, r in ipairs(rejected) do
		warn(string.format("[CraftingManager] %s: %s ← '%s' dropped (%s)", player.Name, r.slot, r.item, r.reason))
	end

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
	Telemetry.record("craft", {
		userId = player.UserId,
		auto = auto == true,
		rejected = rejected,
		slots = table.clone(slots),
		stats = {
			speed = stats.speed, acceleration = stats.acceleration,
			stability = stats.stability, floatability = stats.floatability,
			flyability = stats.flyability, boostDuration = stats.boostDuration,
		},
	})
	print(string.format("[CraftingManager] %s submitted craft | spd=%.1f accel=%.1f",
		player.Name, stats.speed, stats.acceleration))
end

-- ─── SubmitCraft RemoteFunction ───────────────────────────────────────────────

RemoteEvents.SubmitCraft.OnServerInvoke = function(player, slots)
	if not _active then return "denied: not crafting" end
	if _submitted[player.UserId] then return "denied: already submitted" end
	if type(slots) ~= "table" then return "denied: bad slots" end

	_processCraft(player, slots, false)
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

-- Best-effort slots for a player who did not submit: the first item of each
-- category goes to BODY / ENGINE / SPECIAL, leftovers to MOBILITY, HEAD, TAIL.
function _autoSlots(inventory)
	local slots, used = {}, {}
	for _, slotName in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
		for i, name in ipairs(inventory) do
			local cfg = ItemConfig[name]
			if not used[i] and cfg and cfg.slotType == slotName then
				slots[slotName] = name
				used[i] = true
				break
			end
		end
	end
	for _, slotName in ipairs({ "MOBILITY", "HEAD", "TAIL" }) do
		for i, name in ipairs(inventory) do
			if not used[i] then
				slots[slotName] = name
				used[i] = true
				break
			end
		end
	end
	return slots
end

local function _autoSubmitAll()
	for _, player in ipairs(Players:GetPlayers()) do
		if not _submitted[player.UserId] then
			local data = SessionManager.getData(player)
			if data then
				_processCraft(player, _autoSlots(data.inventory), true)
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
					-- Held on the grid until GO (Modules/RaceStart): every car
					-- leaves at the same moment, whatever order they were seated in.
					RaceStart.hold(primary)

					-- Seat everyone in parallel (each waits for its own humanoid).
					task.spawn(function()
						-- One frame for replication before firing the client event.
						task.wait()

						local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
						if seat then
							print(string.format("[CraftingManager] Vehicle for %s spawned at %s | seat=%s",
								player.Name, tostring(primary and primary.Position), tostring(seat)))

							-- Wait for character + humanoid to be ready. RACING can
							-- start while the player is mid-respawn from the FARMING/
							-- CRAFTING transition; firing Sit before the humanoid
							-- exists silently fails and leaves the player standing
							-- on the spawn pad with the vehicle invisible underneath.
							local humanoid = nil
							local deadline = tick() + 2
							repeat
								humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
								if not humanoid then task.wait(0.05) end
							until humanoid or tick() > deadline

							if humanoid then
								seat:Sit(humanoid)
								task.wait(0.15)  -- let weld settle
								-- Verify the sit actually took. Humanoid.Sit becomes
								-- true once Roblox wires up the SeatWeld; if it's
								-- still false the seat:Sit silently failed (common
								-- if the humanoid was mid-Climb/Jump). Retry once.
								if not humanoid.Sit then
									seat:Sit(humanoid)
									task.wait(0.1)
								end
							else
								warn("[CraftingManager] Humanoid never ready for", player.Name)
							end

							Telemetry.record("vehicle_spawn", {
								userId = player.UserId,
								seated = humanoid ~= nil and humanoid.Sit or false,
								maxSpeed = seat.MaxSpeed, turnSpeed = seat.TurnSpeed, torque = seat.Torque,
								mass = primary and primary.AssemblyMass,
								at = primary and Telemetry.vec(primary.Position),
							})
							RemoteEvents.VehicleSpawned:FireClient(player, player.UserId, model)
						else
							warn("[CraftingManager] No VehicleSeat found in vehicle for", player.Name)
							RemoteEvents.VehicleSpawned:FireClient(player, player.UserId, model)
						end
					end)
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
