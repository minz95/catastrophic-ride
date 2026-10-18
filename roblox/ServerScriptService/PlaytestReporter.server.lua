-- PlaytestReporter.server.lua
-- Playtest feedback loop (Studio or servers with the PlaytestMarkers attribute):
--   * players press M ("this is frustrating") or N ("this is fun") anywhere;
--     the server logs a `feedback` telemetry event with the track position;
--   * when the round reaches RESULTS, the race is scored with RaceMetrics and
--     printed as a summary plus `[PlaytestReport] {json}` (Modules/PlaytestReport).
-- Does nothing in live games.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RaceMetrics    = require(ReplicatedStorage.Shared.RaceMetrics)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local PlaytestReport = require(ServerScriptService.Modules.PlaytestReport)

if not PlaytestReport.enabled() then
	return
end

local NOTES = { bad = true, fun = true }
local _lastMark = {}

RemoteEvents.PlaytestMark.OnServerEvent:Connect(function(player, note)
	if not NOTES[note] then return end
	local now = os.clock()
	if (_lastMark[player.UserId] or -math.huge) + Constants.FUN.MARK_COOLDOWN > now then return end
	_lastMark[player.UserId] = now

	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	local part = (vehicle and vehicle.PrimaryPart)
		or (player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
	if not part then return end
	local pos = part.Position
	local fields = {
		userId = player.UserId, note = note, phase = GameManager.getPhase(),
		x = math.floor(pos.X), z = math.floor(pos.Z),
	}
	local biome = GameManager.getBiome()
	local info = biome and PlaytestReport.trackInfo(biome)
	if info and fields.phase == Constants.PHASES.RACING then
		local p = info.geo:project(pos.X, pos.Z)
		fields.s = math.floor(p.s)
		local sec = info.sections[RaceMetrics.sectionOf(info.sections, p.s)]
		fields.section = sec and sec.name
	end
	Telemetry.record("feedback", fields)
	print(string.format("[Playtest] %s marked '%s' during %s%s", player.Name, note, fields.phase,
		fields.section and (" in " .. fields.section) or ""))
end)

GameManager.onPhaseChanged(function(phase, biome)
	if phase ~= Constants.PHASES.RESULTS then return end
	local report = PlaytestReport.build(Telemetry.events(), biome)
	PlaytestReport.last = report
	print(PlaytestReport.format(report))
	print("[PlaytestReport] " .. PlaytestReport.json(report))
end)

Players.PlayerRemoving:Connect(function(player)
	_lastMark[player.UserId] = nil
end)
