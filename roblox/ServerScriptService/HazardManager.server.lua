-- HazardManager.server.lua
-- Periodic track hazards configured in BiomeConfig[biome].hazards:
--   fallingLog (FOREST) – logs drop onto the lane ahead of the leader
--   waveFlood  (OCEAN)  – the water level rises for a few seconds
--   gustZone   (SKY)    – a sideways gust shoves every racer
-- Runs only during RACING. Each race gets a new id; loops from an older race
-- stop on their next tick.

local Players             = game:GetService("Players")
local CollectionService   = game:GetService("CollectionService")
local Debris              = game:GetService("Debris")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RaceProgress   = require(ReplicatedStorage.Shared.RaceProgress)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local BiomeConfig    = require(ServerScriptService.Modules.BiomeConfig)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)

local H = Constants.HAZARDS

local _raceId = 0

local function _folder()
	local f = workspace:FindFirstChild("Hazards")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Hazards"
		f.Parent = workspace
	end
	return f
end

local function _alive(id)
	return _raceId == id and GameManager.getPhase() == Constants.PHASES.RACING
end

-- ─── fallingLog ───────────────────────────────────────────────────────────────

local function _leaderProgress()
	local best = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local d = SessionManager.getData(player)
		if d and d.raceProgress and d.raceProgress > best then best = d.raceProgress end
	end
	return best
end

local function _dropLogs(hz, biome)
	local geo = RaceProgress.geometry(biome)
	if not geo then return end
	local cfg = BiomeConfig[biome]
	local groundY = (cfg and cfg.raceStartY) or 2
	local lead = _leaderProgress()
	for _ = 1, hz.count or 3 do
		local s = lead + H.LOG_AHEAD_MIN + math.random() * (H.LOG_AHEAD_MAX - H.LOG_AHEAD_MIN)
		if s > geo.length - 60 then continue end   -- keep the finish clear
		local lateral = (math.random() * 2 - 1) * H.LOG_LATERAL
		local x, z = geo:offsetPoint(s, lateral)
		local yaw = geo:yawAt(s) + (math.random() - 0.5) * 0.6
		local log = Instance.new("Part")
		log.Name = "FallingLog"
		log.Size = Vector3.new(H.LOG_SIZE[1], H.LOG_SIZE[2], H.LOG_SIZE[3])
		-- long axis across the lane
		log.CFrame = CFrame.new(x, groundY + H.LOG_DROP_HEIGHT, z) * CFrame.Angles(0, yaw, 0)
		log.Color = Color3.fromRGB(100, 65, 35)
		log.Material = Enum.Material.Wood
		log.Anchored = false
		log.CanCollide = true
		log.Parent = _folder()
		CollectionService:AddTag(log, "Obstacle")   -- RacingManager connects it
		Debris:AddItem(log, H.LOG_LIFETIME)
		Telemetry.record("hazard", { type = "fallingLog", s = math.floor(s), x = math.floor(x), z = math.floor(z) })
	end
end

-- ─── waveFlood ────────────────────────────────────────────────────────────────

local function _waterParts()
	local maps = workspace:FindFirstChild("Maps")
	local ocean = maps and maps:FindFirstChild("OceanMap")
	local out = {}
	if not ocean then return out end
	for _, name in ipairs({ "WaterPlane", "WaterShimmer" }) do
		local p = ocean:FindFirstChild(name, true)
		if p then table.insert(out, p) end
	end
	return out
end

-- Moves the water level to `target` (studs above normal) in FLOOD_STEPS steps.
local function _setWater(target, id)
	local parts = _waterParts()
	local from = workspace:GetAttribute("WaterLevelOffset") or 0
	for i = 1, H.FLOOD_STEPS do
		if not _alive(id) then break end
		local level = from + (target - from) * (i / H.FLOOD_STEPS)
		local delta = level - (workspace:GetAttribute("WaterLevelOffset") or 0)
		for _, p in ipairs(parts) do p.CFrame = p.CFrame + Vector3.new(0, delta, 0) end
		workspace:SetAttribute("WaterLevelOffset", level)
		task.wait(1 / H.FLOOD_STEPS)
	end
end

local function _resetWater()
	local level = workspace:GetAttribute("WaterLevelOffset") or 0
	if level ~= 0 then
		for _, p in ipairs(_waterParts()) do p.CFrame = p.CFrame - Vector3.new(0, level, 0) end
	end
	workspace:SetAttribute("WaterLevelOffset", 0)
end

local function _flood(hz, _, id)
	RemoteEvents.ScreenEffect:FireAllClients("waveFlood", { duration = hz.duration })
	Telemetry.record("hazard", { type = "waveFlood", rise = hz.riseHeight })
	_setWater(hz.riseHeight or 3, id)
	task.wait(hz.duration or 4)
	_setWater(0, id)
end

-- ─── gustZone ─────────────────────────────────────────────────────────────────

local function _gust(hz, _, id)
	local angle = math.random() * math.pi * 2
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local push = (hz.force or 150) * H.GUST_PUSH_PER_FORCE
	RemoteEvents.ScreenEffect:FireAllClients("gust", { duration = H.GUST_DURATION })
	Telemetry.record("hazard", { type = "gustZone", angle = math.floor(math.deg(angle)) })
	local t = 0
	while t < H.GUST_DURATION and _alive(id) do
		for _, player in ipairs(Players:GetPlayers()) do
			local d = SessionManager.getData(player)
			local primary = d and d.vehicleModel and d.vehicleModel.PrimaryPart
			if primary then
				local bv = Instance.new("BodyVelocity")
				bv.Name = "GustPush"
				bv.Velocity = primary.AssemblyLinearVelocity + dir * push
				bv.MaxForce = Vector3.new(1e4, 0, 1e4)
				bv.Parent = primary
				Debris:AddItem(bv, H.GUST_PULSE * 0.8)
			end
		end
		task.wait(H.GUST_PULSE)
		t += H.GUST_PULSE
	end
end

-- ─── Scheduler ────────────────────────────────────────────────────────────────

local RUNNERS = {
	fallingLog = function(hz, biome) _dropLogs(hz, biome) end,
	waveFlood  = _flood,
	gustZone   = _gust,
}

local function _loop(hz, biome, id)
	while true do
		task.wait(hz.interval or 10)
		if not _alive(id) then break end
		local ok, err = pcall(RUNNERS[hz.type], hz, biome, id)
		if not ok then warn("[HazardManager] " .. hz.type .. " failed: " .. tostring(err)) end
	end
end

GameManager.onPhaseChanged(function(phase, biome)
	_raceId += 1
	local id = _raceId
	if phase == Constants.PHASES.RACING then
		local cfg = biome and BiomeConfig[biome]
		for _, hz in ipairs((cfg and cfg.hazards) or {}) do
			if RUNNERS[hz.type] then
				task.spawn(_loop, hz, biome, id)
			end
		end
	else
		_resetWater()
		local f = workspace:FindFirstChild("Hazards")
		if f then f:ClearAllChildren() end
	end
end)
