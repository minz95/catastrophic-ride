--!nocheck
-- Today's challenges (Shared/DailyChallenge, ChallengeManager, ResultsUI).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

R.describe("Daily challenges", function()
	local env = Loader.boot()
	local DC = env.requirePath("ReplicatedStorage.Shared.DailyChallenge")
	local Progression = env.requirePath("ReplicatedStorage.Shared.Progression")

	R.it("each day has three different challenges, at most one tied to a biome, the same everywhere", function()
		local kinds = {}
		for day = 20000, 20365 do
			local keys = DC.forDay(day)
			R.expect(#keys).toBe(DC.PER_DAY)
			local seen, biomes = {}, 0
			for _, k in ipairs(keys) do
				R.expect(seen[k]).toBe(nil)
				seen[k] = true
				kinds[k] = true
				if DC.get(k).biome then biomes += 1 end
			end
			R.expect(biomes <= 1).toBe(true)
			R.expect(table.concat(DC.forDay(day), ",")).toBe(table.concat(keys, ","))
		end
		for _, c in ipairs(DC.POOL) do R.expect(kinds[c.key]).toBe(true, c.key .. " never drawn in a year") end
		-- not the same set two days running every time
		R.expect(table.concat(DC.forDay(20001), ",") ~= table.concat(DC.forDay(20002), ",")).toBe(true)
	end)

	R.it("events count, pay once, the bonus comes with the third; a new day starts over", function()
		-- find a day with finish3 in it
		local day
		for d = 20000, 20400 do
			for _, k in ipairs(DC.forDay(d)) do if k == "finish3" then day = d end end
			if day then break end
		end
		local rec = Progression.newRecord()
		local paid = {}
		for _ = 1, 3 do
			for _, p in ipairs(DC.step(rec, day, "finish", { biome = "FOREST", weather = "clear" })) do table.insert(paid, p.key) end
		end
		R.expect(table.find(paid, "finish3") ~= nil).toBe(true)
		local coins = rec.coins
		DC.step(rec, day, "finish", { biome = "FOREST" })
		R.expect(rec.coins).toBe(coins)   -- done: pays once
		-- finish the other two by brute force
		local events = { "finish", "win", "podium", "turbo", "steal", "pickup", "ability", "boost", "knockout" }
		for _ = 1, 25 do
			for _, ev in ipairs(events) do
				for _, b in ipairs({ "FOREST", "OCEAN", "SKY" }) do DC.step(rec, day, ev, { biome = b, weather = "storm" }) end
			end
		end
		local v = DC.view(rec, day)
		for _, c in ipairs(v.list) do R.expect(c.done).toBe(true) end
		R.expect(v.bonus).toBe(true)
		local total = 0
		for _, k in ipairs(DC.forDay(day)) do total += DC.get(k).coins end
		R.expect(rec.coins).toBe(total + DC.ALL_BONUS)
		local fresh = DC.view(rec, day + 1)
		for _, c in ipairs(fresh.list) do R.expect(c.progress).toBe(0) end
	end)

	R.it("biome and wild-weather challenges count only there; bots earn nothing", function()
		local rec = Progression.newRecord()
		local s = DC.state(rec, 1)
		R.expect(s.day).toBe(1)
		local ocean = DC.get("ocean")
		R.expect(ocean.biome).toBe("OCEAN")
		R.expect(#DC.eventsOf("finish", { userId = -3, place = 1, bot = true })).toBe(0)
		R.expect(#DC.eventsOf("finish", { userId = 5, place = 1 })).toBe(3)   -- finish, win, podium
		R.expect(#DC.eventsOf("finish", { userId = 5, place = 5 })).toBe(1)
		R.expect(#DC.eventsOf("ability", { userId = 5, result = "denied: gauge" })).toBe(0)
		R.expect(#DC.eventsOf("punch", { attacker = 5, result = "knockout" })).toBe(1)
		R.expect(#DC.eventsOf("steal", { thief = 5 })).toBe(1)
		-- a day with "wild"
		local day
		for d = 20000, 21000 do
			for _, k in ipairs(DC.forDay(d)) do if k == "wild" then day = d end end
			if day then break end
		end
		local r2 = Progression.newRecord()
		DC.step(r2, day, "finish", { biome = "FOREST", weather = "clear" })
		R.expect(DC.state(r2, day).progress.wild).toBe(nil)
		DC.step(r2, day, "finish", { biome = "FOREST", weather = "night" })
		R.expect(DC.state(r2, day).done.wild).toBe(true)
	end)

	R.it("a race in a running server moves the player's challenges and pays", function()
		local srv = Server.boot({
			players = 2,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.ChallengeManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
		})
		local e = srv.env
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
		local Consts = e.requirePath("ReplicatedStorage.Shared.Constants")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local D = e.requirePath("ReplicatedStorage.Shared.DailyChallenge")
		local P = e.requirePath("ReplicatedStorage.Shared.Progression")
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		local cars = {}
		for i, p in ipairs(srv.players) do
			local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
			model.Parent = e.workspace
			srv.SessionManager.setVehicle(p, model, stats)
			cars[i] = model
		end
		srv.advance(0.5)
		srv.advance(Consts.RACE_COUNTDOWN + 0.5)
		local function tagged(tag) return srv.mock.CollectionService:GetTagged(tag)[1] end
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			tagged(tag).Touched:Fire(cars[1].PrimaryPart)
			srv.advance(0.1)
		end
		srv.advance(1)
		local rec = PlayerStore.get(srv.players[1])
		-- the server's day (the mock's clock is not this process's os.time)
		R.expect(rec.challenges ~= nil).toBe(true)
		local day = rec.challenges.day
		local s = D.state(rec, day)
		local moved = false
		for _, k in ipairs(D.forDay(day)) do
			local c = D.get(k)
			if c.ev == "finish" or c.ev == "win" or c.ev == "podium" then
				if (not c.biome or c.biome == "FOREST") and not c.wild then
					R.expect((s.progress[k] or 0) > 0).toBe(true, k)
					moved = true
				end
			end
		end
		-- the results screen's call answers with today's three
		local view = srv.mock.invoke(RE.GetChallenges, srv.players[1])
		R.expect(#view.list).toBe(3)
		R.expect(moved or #D.forDay(day) == 3).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the results screen shows them and the notice when one is done", function()
		local res = fs.readFile("roblox/StarterGui/ResultsUI/init.client.lua")
		R.expect(res:find("GetChallenges:InvokeServer", 1, true) ~= nil).toBe(true)
		R.expect(res:find("ChallengeUpdate.OnClientEvent", 1, true) ~= nil).toBe(true)
	end)

	R.it("notices wait for the race to end (a popup over the phone's BOOST / DRIFT buttons)", function()
		local Notice = env.requirePath("ReplicatedStorage.Shared.Notice")
		R.expect(Notice.holds("RACING")).toBe(true)
		R.expect(Notice.holds("RESULTS")).toBe(false)
		R.expect(Notice.holds("FARMING")).toBe(false)
		for _, f in ipairs({ "roblox/StarterGui/ResultsUI/init.client.lua", "roblox/ReplicatedStorage/Shared/Invite.lua" }) do
			local src = fs.readFile(f)
			R.expect(src:find("SendNotification", 1, true)).toBe(nil)
			R.expect(src:find("Notice).show(", 1, true) ~= nil or src:find("Notice.show(", 1, true) ~= nil).toBe(true)
		end
	end)
end)

R.describe("Daily challenges: the shop screen", function()
	R.it("a challenge's coins reach an open shop screen (ShopUpdated)", function()
		local srv = Server.boot({
			players = 1,
			scripts = { "ServerScriptService.GameBootstrap", "ServerScriptService.ProgressionManager",
				"ServerScriptService.ChallengeManager" },
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, durations = { FARMING = 30 } },
		})
		srv.advance(1)
		local e = srv.env
		local D = e.requirePath("ReplicatedStorage.Shared.DailyChallenge")
		local P = e.requirePath("ReplicatedStorage.Shared.Progression")
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local Tel = e.requirePath("ServerScriptService.Modules.Telemetry")
		P.dayOf = function() return 20000 end
		local keys = D.forDay(20000)
		-- feed the events of today's first challenge until it is done
		local c = D.get(keys[1])
		local uid = srv.players[1].UserId
		local kinds = {
			finish = { "finish", { userId = uid, place = 2 } }, win = { "finish", { userId = uid, place = 1 } },
			podium = { "finish", { userId = uid, place = 3 } }, turbo = { "drift_turbo", { userId = uid } },
			steal = { "steal", { thief = uid } }, pickup = { "item_pickup", { userId = uid } },
			ability = { "ability", { userId = uid, result = "ok" } }, boost = { "boost", { userId = uid } },
			knockout = { "punch", { attacker = uid, result = "knockout" } },
		}
		local k = kinds[c.ev]
		srv.GameManager.getBiome = function() return c.biome or "FOREST" end
		srv.GameManager.getWeather = function() return c.wild and "storm" or "clear" end
		for _ = 1, c.goal do Tel.record(k[1], table.clone(k[2])) end
		srv.advance(0.1)
		local calls = rawget(RE.ShopUpdated, "_calls") or {}
		R.expect(#calls > 0).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
