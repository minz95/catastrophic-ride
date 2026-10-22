-- PlaytestReport.lua
-- Turns the server Telemetry of the last race into fun numbers
-- (Shared/RaceMetrics) plus the playtest markers players dropped with M / N.
-- PlaytestReporter.server.lua prints it when a Studio playtest reaches
-- RESULTS; an AI can also read it over the Studio MCP server:
--
--   local PR = require(game.ServerScriptService.Modules.PlaytestReport)
--   return PR.format(PR.last), PR.json(PR.last)
--
-- Only active in Studio or on a server whose ReplicatedStorage has the
-- attribute PlaytestMarkers = true (private test servers). Live games skip it.

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants     = require(ReplicatedStorage.Shared.Constants)
local RaceMetrics   = require(ReplicatedStorage.Shared.RaceMetrics)
local TrackGeometry = require(ReplicatedStorage.Shared.TrackGeometry)

local PlaytestReport = {}

PlaytestReport.last = nil

local TRACKS = { FOREST = "ForestTrack", OCEAN = "OceanTrack", SKY = "SkyTrack" }

function PlaytestReport.enabled()
	return RunService:IsStudio() or ReplicatedStorage:GetAttribute("PlaytestMarkers") == true
end

local _geo = {}
--- Track data, geometry and sections for a biome (cached).
function PlaytestReport.trackInfo(biome)
	if not _geo[biome] then
		local name = TRACKS[biome]
		if not name then return nil end
		local track = require(ReplicatedStorage.Shared.Tracks[name])
		local geo = TrackGeometry.new(track.nodes, track.width, track.trackTop)
		_geo[biome] = { track = track, geo = geo, sections = RaceMetrics.sections(track, geo) }
	end
	return _geo[biome]
end

--- Report for the last race in `events` (Telemetry.events()).
function PlaytestReport.build(events, biome)
	local info = PlaytestReport.trackInfo(biome)
	if not info then return nil end
	local race = RaceMetrics.fromTelemetry(events, info.sections, info.geo.length)
	if not race then return nil end
	local m = RaceMetrics.compute(race)
	local values = {
		winnerTime = m.winnerTime, finishRate = m.finishRate, finishSpread = m.finishSpread,
		leadChanges = m.leadChanges, closeShare = m.closeShare,
		racingShare = RaceMetrics.racingShare(m.lastTime or race.timeout, Constants.PHASE_DURATION),
	}
	local markers = {}
	for _, e in ipairs(events) do
		if e.kind == "feedback" then
			table.insert(markers, { note = e.note, phase = e.phase, section = e.section, s = e.s, x = e.x, z = e.z, userId = e.userId })
		end
	end
	return {
		biome = biome,
		metrics = m,
		verdicts = RaceMetrics.verdicts(values, Constants.FUN_TARGETS),
		markers = markers,
	}
end

local function fmt(v, d)
	if v == nil then return "n/a" end
	return string.format("%." .. (d or 1) .. "f", v)
end

--- Human-readable summary (Output window / MCP console).
function PlaytestReport.format(r)
	if not r then return "[PlaytestReport] no race in the telemetry log" end
	local m = r.metrics
	local lines = {
		string.format("[PlaytestReport] %s: %d/%d finished, winner %s s, spread %s s, lead changes %d, overtakes %d, top two close %d%% of the time",
			r.biome, m.finished, m.racers, fmt(m.winnerTime), fmt(m.finishSpread), m.leadChanges, m.overtakes, math.floor(m.closeShare * 100 + 0.5)),
	}
	for _, v in ipairs(r.verdicts) do
		local range = (v.min and fmt(v.min, 2) or "") .. ".." .. (v.max and fmt(v.max, 2) or "")
		table.insert(lines, string.format("  %s %-14s %s (target %s) %s",
			v.ok == nil and "·" or (v.ok and "✓" or "✗"), v.key, fmt(v.value, 2), range, v.why or ""))
	end
	for _, sec in ipairs(m.sections) do
		table.insert(lines, string.format("  section %-22s mean %s s, spread %s s, respawns %d, hits %d, markers bad %d / fun %d%s",
			sec.name, fmt(sec.meanTime), fmt(sec.spread), sec.respawns, sec.hits, sec.markers.bad, sec.markers.fun,
			sec.name == m.decidingSection and "  ← races decided here" or ""))
	end
	for _, mk in ipairs(r.markers) do
		table.insert(lines, string.format("  marker %s during %s at s=%s (%s) x=%s z=%s",
			mk.note, tostring(mk.phase), mk.s and tostring(mk.s) or "-", tostring(mk.section or "-"), tostring(mk.x), tostring(mk.z)))
	end
	return table.concat(lines, "\n")
end

function PlaytestReport.json(r)
	local ok, s = pcall(function() return HttpService:JSONEncode(r) end)
	return ok and s or "{}"
end

return PlaytestReport
