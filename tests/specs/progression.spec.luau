--!nocheck
-- Levels, coins and the daily bonus (Shared/Progression), the saved record
-- (Modules/PlayerStore over a mock DataStore) and paying racers at RESULTS
-- (ProgressionManager with the real RacingManager).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local CFrame = require("@lune/roblox").CFrame

local env = Loader.boot()
local P = env.requirePath("ReplicatedStorage.Shared.Progression")
local C = env.requirePath("ReplicatedStorage.Shared.Constants").PROGRESSION

R.describe("Progression rules", function()
	R.it("levels need XP_BASE + XP_STEP × (level − 1) and carry the rest over", function()
		local rec = P.newRecord()
		R.expect(P.addXp(rec, 99)).toBe(0)
		R.expect(rec.level).toBe(1)
		R.expect(P.addXp(rec, 1 + C.XP_BASE + C.XP_STEP + 5)).toBe(2)
		R.expect(rec.level).toBe(3)
		R.expect(rec.xp).toBe(99 + 1 + C.XP_BASE + C.XP_STEP + 5 - C.XP_BASE - (C.XP_BASE + C.XP_STEP))
	end)

	R.it("a round pays more for a better place, and something for a DNF", function()
		local last = math.huge
		for place = 1, 5 do
			local xp, coins = P.roundReward(place)
			R.expect(xp <= last).toBe(true)
			last = xp
			R.expect(coins).toBeGreaterThan(0)
		end
		local dnfXp, dnfCoins = P.roundReward(nil)
		R.expect(dnfXp).toBe(C.PLAY_XP)
		R.expect(dnfCoins).toBe(C.PLAY_COINS)
		R.expect(dnfXp < P.roundReward(5)).toBe(true)
	end)

	R.it("the daily bonus is paid once a day; the streak grows on consecutive days, resets after a gap, stops at the cap", function()
		local rec = P.newRecord()
		R.expect(P.daily(rec, 100)).toBe(C.DAILY_COINS)
		R.expect(P.daily(rec, 100)).toBe(0)
		R.expect(P.daily(rec, 101)).toBe(C.DAILY_COINS + C.DAILY_STREAK_COINS)
		R.expect(rec.streak).toBe(2)
		R.expect(P.daily(rec, 103)).toBe(C.DAILY_COINS)
		R.expect(rec.streak).toBe(1)
		for d = 104, 120 do P.daily(rec, d) end
		R.expect(rec.streak).toBe(C.DAILY_STREAK_MAX)
		R.expect(P.daily(rec, 121)).toBe(C.DAILY_COINS + C.DAILY_STREAK_COINS * (C.DAILY_STREAK_MAX - 1))
	end)

	R.it("migrate keeps saved fields and adds new ones", function()
		local rec = P.migrate({ xp = 40, level = 7, coins = 300 })
		R.expect(rec.level).toBe(7)
		R.expect(rec.coins).toBe(300)
		R.expect(type(rec.owned)).toBe("table")
		R.expect(rec.v).toBe(P.VERSION)
		R.expect(P.migrate(nil).level).toBe(1)
	end)

	R.it("level 2 takes about two average rounds, level 10 tens of rounds", function()
		local avg = 0
		for place = 1, 5 do avg += P.roundReward(place) end
		avg /= 5
		R.expect(P.xpToNext(1) / avg).toBeNear(1.5, 0.7)
		local total = 0
		for l = 1, 9 do total += P.xpToNext(l) end
		R.expect(total / avg).toBeGreaterThan(20)
	end)
end)

R.describe("PlayerStore (mock DataStore)", function()
	local function boot()
		local e = Loader.boot()
		local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
		return e, Store, e.mock
	end

	R.it("loads a saved record, saves changes and creates new players", function()
		local e, Store, Mock = boot()
		Mock.dataStores[Store.STORE_NAME] = { u501 = { xp = 10, level = 4, coins = 77 } }
		local p = Mock.addPlayer("Saved", 501)
		local rec = Store.load(p)
		R.expect(rec.level).toBe(4)
		R.expect(Store.isSaved(p)).toBe(true)
		rec.coins = 90
		R.expect(Store.save(p)).toBe(true)
		R.expect(Mock.dataStores[Store.STORE_NAME].u501.coins).toBe(90)
		local fresh = Store.load(Mock.addPlayer("New", 502))
		R.expect(fresh.level).toBe(1)
	end)

	R.it("a failed load is never saved over the real record", function()
		local e, Store, Mock = boot()
		Mock.dataStores[Store.STORE_NAME] = { u601 = { xp = 0, level = 12, coins = 999 } }
		Mock.dataStoreFail = "get"
		local p = Mock.addPlayer("Unlucky", 601)
		local rec
		e.mock.task.spawn(function() rec = Store.load(p) end)
		e.mock.advance(10)
		R.expect(rec.level).toBe(1)
		R.expect(Store.isSaved(p)).toBe(false)
		Mock.dataStoreFail = nil
		rec.coins = 5
		R.expect(Store.save(p)).toBe(false)
		Store.release(p)
		R.expect(Mock.dataStores[Store.STORE_NAME].u601.level).toBe(12)
		R.expect(Mock.dataStores[Store.STORE_NAME].u601.coins).toBe(999)
	end)

	R.it("bots (UserId <= 0) and memory-only sessions never touch the DataStore", function()
		local e, Store, Mock = boot()
		Mock.dataStoreFail = "all"
		local bot = Mock.addPlayer("Bot", -3)
		R.expect(Store.load(bot).level).toBe(1)
		R.expect(Store.save(bot)).toBe(false)
		Store.setMemoryOnly(true)
		local p = Mock.addPlayer("Harness", 700)
		Store.load(p)
		R.expect(Store.isSaved(p)).toBe(false)
	end)

	R.it("saves when the player leaves and on shutdown", function()
		local e, Store, Mock = boot()
		Store.start()
		local a = Mock.addPlayer("A", 801)
		local b = Mock.addPlayer("B", 802)
		e.mock.advance(0.1)
		Store.get(a).coins = 11
		Store.get(b).coins = 22
		Mock.removePlayer(a)
		R.expect(Mock.dataStores[Store.STORE_NAME].u801.coins).toBe(11)
		R.expect(#Mock.closeHandlers).toBe(1)
		e.mock.task.spawn(Mock.closeHandlers[1])
		e.mock.advance(1)
		R.expect(Mock.dataStores[Store.STORE_NAME].u802.coins).toBe(22)
	end)
end)

-- A 3-player race to RESULTS: player 2 wins, player 1 second, player 3 does
-- not finish. Returns the server and the AnalyticsService calls (Analytics.sink).
local function threeCarRace()
	local calls = {}
	local srv = Server.boot({
		players = 3,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.ProgressionManager",
			"ServerScriptService.AnalyticsManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 3, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
		setup = function(e)
			e.requirePath("ServerScriptService.Modules.Analytics").sink = function(method, args)
				table.insert(calls, { method = method, args = args })
			end
		end,
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local Consts = e.requirePath("ReplicatedStorage.Shared.Constants")
	local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
	local cars = {}
	for i, p in ipairs(srv.players) do
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
		cars[i] = model
	end
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RACING", "not racing")
	srv.advance(Consts.RACE_COUNTDOWN + 0.5)
	local function tagged(tag) return srv.mock.CollectionService:GetTagged(tag)[1] end
	for _, i in ipairs({ 2, 1 }) do
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			tagged(tag).Touched:Fire(cars[i].PrimaryPart)
			srv.advance(0.1)
		end
	end
	srv.advance(Consts.FINISH_GRACE + 1)
	assert(srv.GameManager.getPhase() == "RESULTS", "no RESULTS")
	srv.advance(0.5)
	return srv, calls
end

R.describe("ProgressionManager pays every racer at RESULTS", function()
	R.it("finishers by place, DNFs the play reward; leaderstats and RewardGranted follow", function()
		local srv = threeCarRace()
		local rewards = srv.Telemetry.events("reward")
		R.expect(#rewards).toBe(3)
		local byUser = {}
		for _, r in ipairs(rewards) do byUser[r.userId] = r end
		local first, second, dnf = byUser[srv.players[2].UserId], byUser[srv.players[1].UserId], byUser[srv.players[3].UserId]
		R.expect(first.place).toBe(1)
		R.expect(second.place).toBe(2)
		R.expect(dnf.place).toBe(nil)
		R.expect(first.xp > second.xp and second.xp > dnf.xp).toBe(true)
		R.expect(first.daily).toBe(C.DAILY_COINS)   -- first round today
		R.expect(first.returnDay).toBe(0)
		R.expect(first.saved).toBe(false)           -- harness: memory only

		local ls = srv.players[2]:FindFirstChild("leaderstats")
		R.expect(ls.Coins.Value).toBe(first.coins + first.daily)
		local calls = rawget(srv.RemoteEvents.RewardGranted, "_calls")
		R.expect(#calls).toBe(3)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("AnalyticsManager (Roblox AnalyticsService events)", function()
	local function steps(calls, method, player, nameAt)
		local out = {}
		for _, c in ipairs(calls) do
			if c.method == method and c.args[1] == player then table.insert(out, c.args[nameAt]) end
		end
		return out
	end

	R.it("new players walk the onboarding funnel in order; a DNF stops before 'Finished a race'", function()
		local srv, calls = threeCarRace()
		local winner, dnf = srv.players[2], srv.players[3]
		R.expect(table.concat(steps(calls, "LogOnboardingFunnelStepEvent", winner, 3), ", "))
			.toBe("Joined, Raced, Finished a race, Got a reward")   -- cars are given here: no pickup, no craft
		R.expect(table.concat(steps(calls, "LogOnboardingFunnelStepEvent", dnf, 3), ", "))
			.toBe("Joined, Raced, Got a reward")
	end)

	R.it("every round logs the Round funnel, coins earned (gameplay and daily) and the return day", function()
		local srv, calls = threeCarRace()
		local winner = srv.players[2]
		R.expect(table.concat(steps(calls, "LogFunnelStepEvent", winner, 5), ", "))
			.toBe("Farming, Crafting, Racing, Finished, Results")
		local earned = {}
		for _, c in ipairs(calls) do
			if c.method == "LogEconomyEvent" and c.args[1] == winner then
				table.insert(earned, string.format("%s %d → %d", c.args[6], c.args[4], c.args[5]))
			end
		end
		local r = srv.Telemetry.events("reward")
		local w
		for _, e in ipairs(r) do if e.userId == winner.UserId then w = e end end
		R.expect(table.concat(earned, "; ")).toBe(string.format("Gameplay %d → %d; TimedReward %d → %d",
			w.coins, w.coins, w.daily, w.coins + w.daily))
		local custom = steps(calls, "LogCustomEvent", winner, 2)
		R.expect(table.concat(custom, ", ")).toBe("ReturnDay, RoundPlace")
	end)

	R.it("is off in harness and Studio sessions (no sink: nothing is sent)", function()
		local A = Loader.boot().requirePath("ServerScriptService.Modules.Analytics")
		R.expect(A.enabled).toBe(false)
	end)
end)
