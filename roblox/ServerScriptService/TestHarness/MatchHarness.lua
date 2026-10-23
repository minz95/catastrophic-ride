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

--- FARMING / CRAFTING numbers for one round, from the telemetry since
-- `t0` and the inventories at the end of FARMING. Per player: pickups,
-- contests won / lost, steals done / suffered, steal attempts by result,
-- defences tried (bot notes), and the inventory ledger: the size expected
-- from the events vs the real one (a mismatch = an item copied or lost).
function MatchHarness.farmStats(t0, inventories)
	local per, attempts, punches = {}, {}, {}
	local function P(uid)
		local key = tostring(uid)
		per[key] = per[key] or { pickups = 0, contestsWon = 0, contestsLost = 0, stolen = 0, robbed = 0,
			attempts = {}, defencesTried = 0, ledger = 0 }
		return per[key]
	end
	for _, e in ipairs(Telemetry.events()) do
		if e.t >= t0 then
			if e.kind == "item_pickup" then
				local p = P(e.userId); p.pickups += 1; p.ledger = e.inventory
			elseif e.kind == "item_drop" then
				local p = P(e.userId); p.drops = (p.drops or 0) + 1; p.ledger = e.inventory
			elseif e.kind == "contest_result" then
				P(e.winner).contestsWon += 1; P(e.loser).contestsLost += 1
			elseif e.kind == "steal" then
				local t, v = P(e.thief), P(e.victim)
				t.stolen += 1; t.ledger = e.thiefInventory
				v.robbed += 1; v.ledger -= 1
			elseif e.kind == "steal_attempt" then
				local p = P(e.thief)
				p.attempts[e.result] = (p.attempts[e.result] or 0) + 1
				attempts[e.result] = (attempts[e.result] or 0) + 1
			elseif e.kind == "bot_defend" and e.data and e.data.tried then
				P(e.userId).defencesTried += 1
			elseif e.kind == "punch" then
				punches[e.result] = (punches[e.result] or 0) + 1
			end
		end
	end
	local mismatches = {}
	for uid, inv in pairs(inventories) do
		local p = P(uid)
		p.inventory = #inv
		if p.ledger ~= #inv then
			table.insert(mismatches, string.format("%s: events say %d items, has %d", uid, p.ledger, #inv))
		end
	end
	return { players = per, attempts = attempts, punches = punches, ledgerMismatches = mismatches }
end

--- CRAFTING numbers: every craft event since t0 (submitted or auto, slots,
-- slots the server rejected).
function MatchHarness.craftStats(t0)
	local out = {}
	for _, e in ipairs(Telemetry.events("craft")) do
		if e.t >= t0 then
			out[tostring(e.userId)] = { auto = e.auto, draft = e.draft, slots = e.slots, rejected = e.rejected, stats = e.stats }
		end
	end
	return out
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
		player:SetAttribute("BotIndex", joined)   -- loadouts[round][BotIndex]
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
			current = { round = GameManager.getRound(), biome = biome, startedAt = os.clock(), players = {},
				t0 = Telemetry.record("harness_round", { round = GameManager.getRound() }).t }
		elseif phase == "CRAFTING" and current then
			local inventories = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local d = SessionManager.getData(p)
				if d then inventories[tostring(p.UserId)] = table.clone(d.inventory) end
			end
			current.inventories = inventories
			current.farm = MatchHarness.farmStats(current.t0, inventories)
			current.craftT0 = Telemetry.record("harness_crafting", {}).t
		elseif phase == "RACING" and current then
			current.raceStartedAt = os.clock()
			local round = current
			-- CraftingManager auto-submits on this same phase change; read the
			-- crafts and the players' cars once it has.
			task.delay(1, function()
				round.craft = MatchHarness.craftStats(round.craftT0 or round.t0)
				for _, p in ipairs(Players:GetPlayers()) do
					local d = SessionManager.getData(p)
					local s = d and d.vehicleStats
					table.insert(round.players, {
						userId = p.UserId, name = p.Name,
						farm = p:GetAttribute("BotFarmProfile"), driver = p:GetAttribute("BotDriverProfile"),
						slots = s and s.slotAssignments, speed = s and s.speed, boostDuration = s and s.boostDuration,
					})
				end
				if args.stopAfter == "CRAFTING" and not ended then
					round.finishOrder = {}
					round.durationSeconds = os.clock() - round.startedAt
					table.insert(report.rounds, round)
					current = nil
					if #report.rounds >= wantRounds then finish("stopAfter CRAFTING") end
				end
			end)
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
				-- a moment for what happens at RESULTS (rewards) to be logged
				task.delay(1, function() finish("rounds complete") end)
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
		local f = r.farm
		if f then
			local att = {}
			for k, v in pairs(f.attempts or {}) do table.insert(att, k .. "=" .. v) end
			table.sort(att)
			table.insert(lines, "    steal attempts: " .. (#att > 0 and table.concat(att, ", ") or "none")
				.. (#f.ledgerMismatches > 0 and ("  LEDGER: " .. table.concat(f.ledgerMismatches, "; ")) or ""))
			for uid, p in pairs(f.players or {}) do
				local c = r.craft and r.craft[uid]
				table.insert(lines, string.format("    %s: picked %d, contests %d/%d, stole %d, robbed %d, defences %d, items %s%s",
					uid, p.pickups, p.contestsWon, p.contestsWon + p.contestsLost, p.stolen, p.robbed, p.defencesTried,
					tostring(p.inventory), c and string.format(" | craft %s, rejected %d", c.auto and "auto" or "submitted",
						#(c.rejected or {})) or ""))
			end
		end
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
