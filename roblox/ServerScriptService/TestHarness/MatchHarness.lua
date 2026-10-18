-- MatchHarness.lua
-- Server side of the multiplayer bot match (StudioTestService
-- ExecuteMultiplayerTestAsync). Marks every joining player as a bot, records
-- telemetry and script errors, and ends the test with a report after the
-- requested number of rounds.
--
-- The game itself runs unmodified: GameManager reads the same harness args
-- (biome, players, phase durations) through HarnessConfig.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ScriptContext       = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local GameManager    = require(ServerScriptService.GameManager)
local SessionManager = require(ServerScriptService.SessionManager)

local MatchHarness = {}

MatchHarness.MAX_SAMPLES = 6000

local function summarizeRound(round)
	local finished = {}
	for _, p in ipairs(round.players) do
		if p.finishTime then table.insert(finished, p) end
	end
	table.sort(finished, function(a, b) return a.finishTime < b.finishTime end)
	return finished
end

function MatchHarness.start(args, endTest)
	local bots = args.bots or {}
	local farmProfiles = bots.farmProfiles or { "sweaty", "casual" }
	local driverProfiles = bots.driverProfiles or { "expert", "average", "novice" }
	local wantRounds = args.rounds or 1

	Telemetry.reset({ harness = "match", biome = args.biome, players = args.players, rounds = wantRounds })
	Telemetry.setDetailed(true)

	local report = {
		harness = "match", args = args, rounds = {}, errors = {}, clientErrors = {},
		botNotes = {}, timedOut = false,
	}
	local ended = false
	local function finish(reason)
		if ended then return end
		ended = true
		report.endReason = reason
		local events = Telemetry.events()
		local trimmed, samples = {}, 0
		for _, e in ipairs(events) do
			if e.kind == "race_sample" then
				samples += 1
				if samples <= MatchHarness.MAX_SAMPLES then table.insert(trimmed, e) end
			else
				table.insert(trimmed, e)
			end
		end
		report.telemetry = { events = trimmed, dropped = Telemetry.snapshot().dropped, samplesTotal = samples }
		report.summary = MatchHarness.summarize(report)
		print(report.summary)
		endTest(report)
	end

	-- Server script errors
	ScriptContext.Error:Connect(function(message, trace, scriptInst)
		table.insert(report.errors, {
			message = message, trace = trace,
			script = scriptInst and scriptInst:GetFullName() or "?",
		})
	end)

	-- Channel for bot clients: they report their own errors and notes.
	local channel = Instance.new("RemoteEvent")
	channel.Name = "HarnessChannel"
	channel.Parent = ReplicatedStorage
	channel.OnServerEvent:Connect(function(player, kind, payload)
		if type(kind) ~= "string" then return end
		if kind == "client_error" then
			table.insert(report.clientErrors, { userId = player.UserId, error = payload })
		else
			Telemetry.record("bot_" .. kind, { userId = player.UserId, data = payload })
		end
	end)

	-- Every player in a harness match is a bot.
	local joined = 0
	local function assign(player)
		joined += 1
		player:SetAttribute("BotFarmProfile", farmProfiles[((joined - 1) % #farmProfiles) + 1])
		player:SetAttribute("BotDriverProfile", driverProfiles[((joined - 1) % #driverProfiles) + 1])
		player:SetAttribute("HarnessBot", true)
		Telemetry.record("bot_joined", {
			userId = player.UserId, name = player.Name,
			farm = player:GetAttribute("BotFarmProfile"), driver = player:GetAttribute("BotDriverProfile"),
		})
	end
	Players.PlayerAdded:Connect(assign)
	for _, p in ipairs(Players:GetPlayers()) do assign(p) end

	-- Per-round bookkeeping
	local current
	GameManager.onPhaseChanged(function(phase, biome)
		if ended then return end
		if phase == "FARMING" then
			current = { round = GameManager.getRound(), biome = biome, startedAt = os.clock(), players = {} }
		elseif phase == "RACING" and current then
			current.raceStartedAt = os.clock()
			for _, p in ipairs(Players:GetPlayers()) do
				local d = SessionManager.getData(p)
				local s = d and d.vehicleStats
				table.insert(current.players, {
					userId = p.UserId, name = p.Name,
					farm = p:GetAttribute("BotFarmProfile"), driver = p:GetAttribute("BotDriverProfile"),
					slots = s and s.slotAssignments, speed = s and s.speed, boostDuration = s and s.boostDuration,
				})
			end
		elseif phase == "RESULTS" and current then
			for _, entry in ipairs(current.players) do
				local p = Players:GetPlayerByUserId(entry.userId)
				local d = p and SessionManager.getData(p)
				if d then
					entry.finishTime = d.finishTime
					entry.progress = d.raceProgress
				end
			end
			current.finishOrder = {}
			for i, p in ipairs(summarizeRound(current)) do
				table.insert(current.finishOrder, { place = i, name = p.name, time = p.finishTime })
			end
			current.durationSeconds = os.clock() - current.startedAt
			table.insert(report.rounds, current)
			current = nil
			if #report.rounds >= wantRounds then
				finish("rounds complete")
			end
		end
	end)

	task.delay(args.maxSeconds or 900, function()
		report.timedOut = true
		finish("timeout after " .. tostring(args.maxSeconds or 900) .. "s")
	end)
end

function MatchHarness.summarize(report)
	local lines = { string.format("Bot match: %d round(s), end: %s, server errors: %d, client errors: %d",
		#(report.rounds or {}), tostring(report.endReason), #(report.errors or {}), #(report.clientErrors or {})) }
	for _, r in ipairs(report.rounds or {}) do
		table.insert(lines, string.format("  round %s (%s): %d finished of %d", tostring(r.round), tostring(r.biome), #(r.finishOrder or {}), #(r.players or {})))
		for _, f in ipairs(r.finishOrder or {}) do
			table.insert(lines, string.format("    #%d %s %.1fs", f.place, f.name, f.time or -1))
		end
	end
	local counts = {}
	for _, e in ipairs((report.telemetry and report.telemetry.events) or {}) do
		counts[e.kind] = (counts[e.kind] or 0) + 1
	end
	local keys = {}
	for k in pairs(counts) do table.insert(keys, k) end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do table.insert(parts, k .. "=" .. counts[k]) end
	table.insert(lines, "  events: " .. table.concat(parts, " "))
	for i, e in ipairs(report.errors or {}) do
		if i > 5 then break end
		table.insert(lines, "  ERROR " .. tostring(e.script) .. ": " .. tostring(e.message))
	end
	return table.concat(lines, "\n")
end

return MatchHarness
