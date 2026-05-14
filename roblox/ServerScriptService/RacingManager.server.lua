-- RacingManager.server.lua
-- Race state, position tracking, biome physics (mud/buoyancy/updraft/drift),
-- obstacle/boost-pad collision, finish detection, and result calculation.
-- Resolves: Issue #30, #31, #32, #33, #34, #35, #37, #66

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants         = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents      = require(ReplicatedStorage.RemoteEvents)
local GameManager       = require(ServerScriptService.GameManager)
local SessionManager    = require(ServerScriptService.SessionManager)
local BiomeConfig       = require(ServerScriptService.Modules.BiomeConfig)
local CheckpointService = require(ServerScriptService.Modules.CheckpointService)

-- ─── State ────────────────────────────────────────────────────────────────────

local _active      = false
local _biome       = nil
local _startTick   = 0
local _finishOrder = {}   -- { { userId, time } }
local _totalRacers = 0

-- Per-player physics state
-- _physState[userId] = {
--   inMud=false, inUpdraft=false, boostCooldownEnd=0,
--   obstaclePenaltyEnd=0, drifting=false,
--   vehicle=Model, seat=VehicleSeat
-- }
local _physState = {}

-- ─── Track axis ───────────────────────────────────────────────────────────────
-- Track runs along -Z. Per-biome zStart/zFinish live in Constants.TRACK and
-- are looked up at race start from the active _biome.

local function _trackProgress(vehicle)
	if not vehicle or not vehicle.PrimaryPart or not _biome then return 0 end
	local track = Constants.TRACK[_biome]
	if not track then return 0 end
	local z = vehicle.PrimaryPart.Position.Z
	return math.clamp(track.zStart - z, 0, track.zStart - track.zFinish)
end

-- ─── Position sync loop ───────────────────────────────────────────────────────

local function _startPositionSync()
	task.spawn(function()
		while _active do
			local data = {}
			local allData = SessionManager.getAllData()
			for userId, pdata in pairs(allData) do
				if pdata.vehicleModel then
					local progress = _trackProgress(pdata.vehicleModel)
					SessionManager.setRaceProgress(
						Players:GetPlayerByUserId(userId),
						progress,
						0   -- rank recalculated below
					)
					table.insert(data, { userId = userId, progress = progress, rank = 0 })
				end
			end
			-- Sort by progress desc → assign ranks
			table.sort(data, function(a, b) return a.progress > b.progress end)
			for rank, entry in ipairs(data) do entry.rank = rank end
			RemoteEvents.PlayerPositionSync:FireAllClients(data)
			task.wait(Constants.POSITION_SYNC_RATE)
		end
	end)
end

-- ─── Mud zones (FOREST) ───────────────────────────────────────────────────────

local function _setupMudZones()
	for _, part in ipairs(CollectionService:GetTagged("MudZone")) do
		part.Touched:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local ps = _physState[player.UserId]
					if ps and not ps.inMud then
						ps.inMud = true
						local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
						if seat then
							seat.MaxSpeed = seat.MaxSpeed * Constants.MUD_SPEED_MULT
						end
						RemoteEvents.ScreenEffect:FireClient(player, "mudWarning", {})
					end
					break
				end
			end
		end)

		part.TouchEnded:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local ps = _physState[player.UserId]
					if ps and ps.inMud then
						ps.inMud = false
						local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
						if seat then
							seat.MaxSpeed = seat.MaxSpeed / Constants.MUD_SPEED_MULT
						end
					end
					break
				end
			end
		end)
	end
end

-- ─── Buoyancy (OCEAN) ─────────────────────────────────────────────────────────

local WATER_Y = 0   -- set from BiomeConfig at race start

local function _buoyancyLoop()
	local cfg = BiomeConfig.get("OCEAN")
	WATER_Y = cfg.waterPlaneY or 0

	RunService.Heartbeat:Connect(function()
		if not _active or _biome ~= "OCEAN" then return end

		local allData = SessionManager.getAllData()
		for userId, pdata in pairs(allData) do
			local vehicle = pdata.vehicleModel
			if not vehicle or not vehicle.PrimaryPart then continue end

			local ps = _physState[userId]
			if not ps then continue end

			local partY   = vehicle.PrimaryPart.Position.Y
			local submerge = math.max(0, WATER_Y - partY)   -- how deep below surface
			local floatStat = (pdata.vehicleStats and pdata.vehicleStats.floatability) or 20

			if submerge > 0 or partY < WATER_Y + 1 then
				-- Apply upward buoyancy force
				local forceY = (submerge * 300 + floatStat * 15)
				local bf = vehicle.PrimaryPart:FindFirstChild("BuoyancyForce")
				if not bf then
					bf = Instance.new("BodyForce")
					bf.Name   = "BuoyancyForce"
					bf.Parent = vehicle.PrimaryPart
				end
				bf.Force = Vector3.new(0, forceY, 0)
			else
				local bf = vehicle.PrimaryPart:FindFirstChild("BuoyancyForce")
				if bf then bf:Destroy() end
			end
		end
	end)
end

-- ─── Updraft zones (SKY) ──────────────────────────────────────────────────────

local function _setupUpdraftZones()
	for _, part in ipairs(CollectionService:GetTagged("UpdraftZone")) do
		part.Touched:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local ps = _physState[player.UserId]
					if ps and not ps.inUpdraft then
						ps.inUpdraft = true
						local flyStat = (pdata.vehicleStats and pdata.vehicleStats.flyability) or 10
						local bf = vehicle.PrimaryPart:FindFirstChild("UpdraftForce")
						if not bf then
							bf = Instance.new("BodyForce")
							bf.Name   = "UpdraftForce"
							bf.Parent = vehicle.PrimaryPart
						end
						bf.Force = Vector3.new(0, Constants.UPDRAFT_BASE_FORCE * (flyStat / 20), 0)
						RemoteEvents.ScreenEffect:FireClient(player, "updraftWarning", {})
					end
					break
				end
			end
		end)

		part.TouchEnded:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local ps = _physState[player.UserId]
					if ps then
						ps.inUpdraft = false
						local bf = vehicle.PrimaryPart:FindFirstChild("UpdraftForce")
						if bf then bf:Destroy() end
					end
					break
				end
			end
		end)
	end
end

-- ─── Respawn helper ───────────────────────────────────────────────────────────

-- Returns the spawn Y for the current biome (vehicle rests at this height).
local function _spawnY()
	local cfg = _biome and BiomeConfig[_biome]
	return (cfg and cfg.raceStartY) or 2
end

-- Teleports the vehicle back onto the track at its current progress, with a
-- screen flash. Safe to call from server Heartbeat or a RemoteFunction.
local function _respawnVehicle(player)
	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle or not vehicle.PrimaryPart then return end

	local primary = vehicle.PrimaryPart
	local progress = _trackProgress(vehicle)
	-- Step back 30 studs so the player has room to regain speed.
	local track = _biome and Constants.TRACK[_biome]
	local zStart = track and track.zStart or 600
	local safeZ = zStart - math.max(progress - 30, 0)
	local y     = _spawnY() + 3   -- a little above surface to avoid clipping

	-- Briefly anchor so the vehicle doesn't fall while being moved.
	primary.Anchored = true
	vehicle:SetPrimaryPartCFrame(CFrame.new(0, y, safeZ))
	-- Zero out any lingering velocity.
	primary.AssemblyLinearVelocity  = Vector3.zero
	primary.AssemblyAngularVelocity = Vector3.zero
	task.wait(0.1)
	primary.Anchored = false

	RemoteEvents.ScreenEffect:FireClient(player, "respawn", {})
end

-- ─── Kill plane (all biomes) ──────────────────────────────────────────────────

local function _setupKillPlane()
	local cfg   = _biome and BiomeConfig[_biome]
	-- SKY has an explicit killPlaneY; for ground/ocean use a generous floor.
	local killY = (cfg and cfg.killPlaneY) or -50

	local _respawnCooldown = {}   -- { [userId] = expireTick } prevents rapid re-triggers

	RunService.Heartbeat:Connect(function()
		if not _active then return end
		for _, player in ipairs(Players:GetPlayers()) do
			local pdata = SessionManager.getData(player)
			local vehicle = pdata and pdata.vehicleModel
			if not vehicle or not vehicle.PrimaryPart then continue end
			if vehicle.PrimaryPart.Position.Y < killY then
				local now = tick()
				if (_respawnCooldown[player.UserId] or 0) > now then continue end
				_respawnCooldown[player.UserId] = now + 3   -- 3s cooldown
				_respawnVehicle(player)
			end
		end
	end)
end

-- ─── Manual respawn (R key from client) ───────────────────────────────────────

local _manualRespawnCooldown = {}   -- { [userId] = expireTick }

RemoteEvents.RequestRespawn.OnServerInvoke = function(player)
	if not _active then return "denied: not racing" end
	local now = tick()
	if (_manualRespawnCooldown[player.UserId] or 0) > now then
		return "denied: cooldown"
	end
	_manualRespawnCooldown[player.UserId] = now + 5   -- 5s between manual resets
	_respawnVehicle(player)
	return "ok"
end

-- ─── Obstacle collision (all biomes) ─────────────────────────────────────────

local function _setupObstacles()
	for _, part in ipairs(CollectionService:GetTagged("Obstacle")) do
		part.Touched:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end

			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local ps = _physState[player.UserId]
					if not ps or tick() < (ps.obstaclePenaltyEnd or 0) then break end

					ps.obstaclePenaltyEnd = tick() + Constants.OBSTACLE_BOUNCE_PENALTY_DURATION

					-- Apply bounce impulse
					local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
					if seat then
						local oldMax = seat.MaxSpeed
						seat.MaxSpeed = oldMax * Constants.OBSTACLE_BOUNCE_SPEED_MULT
						task.delay(Constants.OBSTACLE_BOUNCE_PENALTY_DURATION, function()
							if seat and seat.Parent then
								seat.MaxSpeed = oldMax
							end
						end)
					end

					-- Impulse away from obstacle
					local primary = vehicle.PrimaryPart
					if primary then
						local dir = (primary.Position - part.Position).Unit
						local bv = Instance.new("BodyVelocity")
						bv.Velocity     = dir * 30
						bv.MaxForce     = Vector3.new(1e5, 1e4, 1e5)
						bv.Parent       = primary
						game:GetService("Debris"):AddItem(bv, 0.25)
					end

					RemoteEvents.ScreenEffect:FireClient(player, "collision", {})
					break
				end
			end
		end)
	end
end

-- ─── Boost pads ───────────────────────────────────────────────────────────────

local _boostPadCooldowns = {}   -- { [partRef] = { [userId] = expireTick } }

local function _setupBoostPads()
	for _, part in ipairs(CollectionService:GetTagged("BoostPad")) do
		_boostPadCooldowns[part] = {}
		part.Touched:Connect(function(hit)
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local cds = _boostPadCooldowns[part]
					if cds[player.UserId] and tick() < cds[player.UserId] then break end
					cds[player.UserId] = tick() + 5   -- 5s pad cooldown

					local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
					if seat then
						local old = seat.MaxSpeed
						seat.MaxSpeed = old * 1.4
						task.delay(2, function()
							if seat and seat.Parent then seat.MaxSpeed = old end
						end)
					end
					RemoteEvents.ScreenEffect:FireClient(player, "boostPad", {})
					break
				end
			end
		end)
	end
end

-- ─── Drift corner zones (all biomes) ─────────────────────────────────────────
-- Parts tagged "DriftCorner" charge the player's boost gauge (F key) when touched.
-- Per-zone per-player cooldown prevents farming the same corner.

local function _setupDriftCorners()
	local _cornerCooldowns = {}   -- { [partRef] = { [userId] = expireTick } }
	for _, part in ipairs(CollectionService:GetTagged("DriftCorner")) do
		_cornerCooldowns[part] = {}
		part.Touched:Connect(function(hit)
			if not _active then return end
			local vehicle = hit:FindFirstAncestorWhichIsA("Model")
			if not vehicle then return end
			for _, player in ipairs(Players:GetPlayers()) do
				local pdata = SessionManager.getData(player)
				if pdata and pdata.vehicleModel == vehicle then
					local cds = _cornerCooldowns[part]
					local now = tick()
					if cds[player.UserId] and now < cds[player.UserId] then break end
					cds[player.UserId] = now + Constants.DRIFT_CORNER_COOLDOWN
					RemoteEvents.DriftCharge:FireClient(player, Constants.DRIFT_CHARGE_PER_CORNER)
					break
				end
			end
		end)
	end
end

-- ─── Manual boost activation (F key) ─────────────────────────────────────────
-- Client invokes RequestBoost when boost gauge is full; server applies the speed burst.

RemoteEvents.RequestBoost.OnServerInvoke = function(player)
	if not _active then return "denied: not racing" end
	local ps = _physState[player.UserId]
	if not ps then return "denied: no state" end

	local now = tick()
	if now < (ps.boostCooldownEnd or 0) then
		return "denied: cooldown"
	end

	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	if not vehicle then return "denied: no vehicle" end

	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then return "denied: no seat" end

	-- Apply boost
	local boostDuration = (pdata.vehicleStats and pdata.vehicleStats.boostDuration)
		or Constants.BOOST_DURATION

	ps.boostCooldownEnd = now + Constants.BOOST_COOLDOWN
	local oldMax = seat.MaxSpeed
	seat.MaxSpeed = oldMax * Constants.BOOST_MULTIPLIER

	task.delay(boostDuration, function()
		if seat and seat.Parent then seat.MaxSpeed = oldMax end
	end)

	return "ok"
end

-- ─── Finish line ──────────────────────────────────────────────────────────────

local function _setupFinishLine()
	-- Search in the active biome's map first to avoid picking up another biome's sensor.
	local finishPart
	if _biome then
		local mapName   = _biome:sub(1,1):upper() .. _biome:sub(2):lower() .. "Map"
		local mapsModel = workspace:FindFirstChild("Maps")
		local biomeMap  = mapsModel and mapsModel:FindFirstChild(mapName)
		finishPart = biomeMap and biomeMap:FindFirstChild("FinishLine", true)
	end
	if not finishPart then
		finishPart = workspace:FindFirstChild("FinishLine", true)
	end
	if not finishPart then
		warn("[RacingManager] No FinishLine Part found in Workspace")
		return
	end

	finishPart.Touched:Connect(function(hit)
		if not _active then return end
		local vehicle = hit:FindFirstAncestorWhichIsA("Model")
		if not vehicle then return end

		for _, player in ipairs(Players:GetPlayers()) do
			local pdata = SessionManager.getData(player)
			if pdata and pdata.vehicleModel == vehicle then
				-- Check not already finished
				for _, entry in ipairs(_finishOrder) do
					if entry.userId == player.UserId then return end
				end

				-- Gate finish on checkpoint completion. If the active map has
				-- no checkpoints tagged (legacy maps not yet rebuilt), the gate
				-- is inactive and the finish counts as before.
				if CheckpointService.isActive()
					and not CheckpointService.hasCompleted(player) then
					print(string.format(
						"[RacingManager] %s touched FinishLine but checkpoints incomplete — ignored",
						player.Name))
					return
				end

				local elapsed = tick() - _startTick
				table.insert(_finishOrder, { userId = player.UserId, time = elapsed })
				SessionManager.setFinished(player, elapsed)

				RemoteEvents.RaceFinished:FireAllClients(_finishOrder)
				print(string.format("[RacingManager] %s finished #%d (%.1fs)",
					player.Name, #_finishOrder, elapsed))

				-- All racers done?
				if #_finishOrder >= math.max(1, _totalRacers) then
					_active = false
					GameManager.raceComplete(_finishOrder)
				end
				break
			end
		end
	end)
end

-- ─── Phase listener ───────────────────────────────────────────────────────────

GameManager.onPhaseChanged(function(phase, biome)
	if phase == Constants.PHASES.RACING then
		_active      = true
		_biome       = biome
		_startTick   = tick()
		_finishOrder = {}
		_physState   = {}
		_totalRacers = #Players:GetPlayers()

		-- Init physics state per player
		for _, player in ipairs(Players:GetPlayers()) do
			local pdata = SessionManager.getData(player)
			_physState[player.UserId] = {
				inMud             = false,
				inUpdraft         = false,
				boostCooldownEnd  = 0,
				obstaclePenaltyEnd = 0,
				drifting          = false,
				vehicle           = pdata and pdata.vehicleModel,
			}
		end

		-- Setup collision systems
		_setupObstacles()
		_setupBoostPads()
		_setupDriftCorners()   -- all biomes: charges boost gauge (F key)

		if biome == "FOREST" then
			_setupMudZones()
		elseif biome == "OCEAN" then
			_buoyancyLoop()
		elseif biome == "SKY" then
			_setupUpdraftZones()
		end

		_setupKillPlane()   -- applies to all biomes

		CheckpointService.resetAll()
		CheckpointService.setup()

		_setupFinishLine()
		_startPositionSync()

	elseif phase == Constants.PHASES.RESULTS then
		_active = false
		_physState = {}
	end
end)

-- Handle player leaving mid-race
Players.PlayerRemoving:Connect(function(player)
	if not _active then return end
	_physState[player.UserId] = nil
	_totalRacers = math.max(1, _totalRacers - 1)
	if #_finishOrder >= _totalRacers then
		_active = false
		GameManager.raceComplete(_finishOrder)
	end
end)
