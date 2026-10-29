--!nocheck
-- Server bots fill an empty grid (Modules/RaceBots, RacingManager).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local CFrame = require("@lune/roblox").CFrame

R.describe("how many bots", function()
	local env = Loader.boot()
	local RaceBots = env.requirePath("ServerScriptService.Modules.RaceBots")
	local C = env.requirePath("ReplicatedStorage.Shared.Constants")
	R.it("live: fill to this round's draw; none when the grid is full; harness only with fillBots", function()
		local BotFill = env.requirePath("ServerScriptService.Modules.BotFill")
		BotFill.current = 5
		R.expect(RaceBots.wanted(1, nil)).toBe(4)
		R.expect(RaceBots.wanted(5, nil)).toBe(0)
		R.expect(RaceBots.wanted(9, nil)).toBe(0)
		R.expect(RaceBots.wanted(1, { harness = "match" })).toBe(0)
		R.expect(RaceBots.wanted(2, { fillBots = 6 })).toBe(4)
		R.expect(RaceBots.wanted(9, { fillBots = 20 })).toBe(1)   -- never past MAX_PLAYERS
	end)
	R.it("each round draws between FILL.MIN and FILL.MAX (2026-10-30: always 3 bots for a lone player)", function()
		local BotFill = env.requirePath("ServerScriptService.Modules.BotFill")
		local seen = {}
		for _ = 1, 200 do
			local n = BotFill.roll()
			R.expect(n >= C.BOTS.FILL.MIN and n <= C.BOTS.FILL.MAX).toBe(true)
			seen[n] = true
		end
		for n = C.BOTS.FILL.MIN, C.BOTS.FILL.MAX do R.expect(seen[n]).toBe(true) end
		R.expect(C.BOTS.FILL.MIN).toBeGreaterThan(3)   -- a round always has at least four
		BotFill.current = nil
	end)
	R.it("random builds put core items in their own slots", function()
		local ItemConfig = env.requirePath("ServerScriptService.Modules.ItemConfig")
		local state = 3
		local rng = { NextInteger = function(_, a, b)
			state = (state * 1103515245 + 12345) % 2147483648
			return a + state % (b - a + 1)
		end }
		for _ = 1, 30 do
			local slots = RaceBots.randomSlots(rng)
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				if slots[slot] then R.expect(ItemConfig[slots[slot]].slotType).toBe(slot) end
			end
		end
	end)
end)

local function race(players, fillBots)
	local srv = Server.boot({
		players = players,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.ProgressionManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = players, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
	local cars = {}
	for i, p in ipairs(srv.players) do
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), {})
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
		cars[i] = model
	end
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	tick(0.5)
	assert(srv.GameManager.getPhase() == "RACING", "not racing")
	local RaceBots = e.requirePath("ServerScriptService.Modules.RaceBots")
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	local function cross(model)
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			local trig = srv.mock.CollectionService:GetTagged(tag)[1]
			if model:GetAttribute("BotRacer") then
				model:PivotTo(trig.CFrame)
				tick(0.1)
			else
				trig.Touched:Fire(model.PrimaryPart)
				tick(0.1)
			end
		end
	end
	return srv, cars, RaceBots, C, tick, cross
end

R.describe("bots in a race", function()
	R.it("one player: three bots on the next grid slots, name-tagged, held until GO", function()
		local srv, _, RaceBots, C, tick = race(1, 4)
		R.expect(#RaceBots.list).toBe(3)
		for _, b in ipairs(RaceBots.list) do
			R.expect(b.model.Parent ~= nil).toBe(true)
			R.expect(b.primary:FindFirstChild("BotName") ~= nil).toBe(true)
			R.expect(b.primary.Anchored).toBe(true)
		end
		R.expect(#srv.Telemetry.events("race_bot")).toBe(3)
		tick(C.RACE_COUNTDOWN + 0.5)
		for _, b in ipairs(RaceBots.list) do R.expect(b.primary.Anchored).toBe(false) end
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a bot that wins pushes the player to 2nd; the player is paid for 2nd, bots for nothing", function()
		local srv, cars, RaceBots, C, tick, cross = race(1, 2)
		tick(C.RACE_COUNTDOWN + 0.5)
		cross(RaceBots.list[1].model)
		R.expect(#srv.Telemetry.events("finish")).toBe(1)
		cross(cars[1])
		tick(0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local calls = rawget(srv.RemoteEvents.RaceFinished, "_calls")
		local order = calls[#calls].args[1]
		R.expect(order[1].bot).toBe(true)
		R.expect(order[2].userId).toBe(srv.players[1].UserId)
		local rewards = srv.Telemetry.events("reward")
		R.expect(#rewards).toBe(1)
		R.expect(rewards[1].place).toBe(2)
	end)

	R.it("bots that do not finish are DNF in the standings, and leave with the next round", function()
		local srv, cars, RaceBots, C, tick, cross = race(1, 3)
		tick(C.RACE_COUNTDOWN + 0.5)
		cross(cars[1])
		local grace = srv.env.requirePath("ReplicatedStorage.Shared.CatchUp").graceFor(1)
		tick(grace + 1)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local calls = rawget(srv.RemoteEvents.RaceFinished, "_calls")
		local order = calls[#calls].args[1]
		local dnfBots = 0
		for _, entry in ipairs(order) do if entry.bot and entry.dnf then dnfBots += 1 end end
		R.expect(dnfBots).toBe(2)
		local model = RaceBots.list[1].model
		tick(31)   -- RESULTS → LOBBY → the next round (its own bots)
		R.expect(model.Parent).toBe(nil)
		R.expect(srv.GameManager.getRound()).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

-- History (2026-10-26): the boost gauge lived only on the client; the server
-- granted a boost on cooldown alone. The harness player called RequestBoost
-- every 5 s and server bots never boosted: the harness player won all six
-- Studio matches with bots. Now the server keeps the gauge (Modules/
-- BoostGauge) for players and bots alike.
R.describe("boost gauge on the server", function()
	R.it("a player boosts once on the full start gauge, then needs three drift corners", function()
		local srv, cars, _, C, tick = race(1, 0)
		local p = srv.players[1]
		tick(C.RACE_COUNTDOWN + 0.5)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("ok")
		tick(C.BOOST_COOLDOWN + 0.5)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("denied: gauge")
		local corners = srv.mock.CollectionService:GetTagged("DriftCorner")
		R.expect(#corners >= 3).toBe(true)
		corners[1].Touched:Fire(cars[1].PrimaryPart)
		corners[1].Touched:Fire(cars[1].PrimaryPart)   -- the same zone again: no charge
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("denied: gauge")
		corners[2].Touched:Fire(cars[1].PrimaryPart)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("denied: gauge")
		corners[3].Touched:Fire(cars[1].PrimaryPart)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("ok")
		R.expect(#srv.Telemetry.events("boost")).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a race bot boosts on a full gauge going straight, then after three drift corners", function()
		local srv, _, RaceBots, C, tick = race(1, 2)
		tick(C.RACE_COUNTDOWN + 0.5)
		local bot = RaceBots.list[1]
		local seat = bot.seat
		local base = seat.MaxSpeed
		RaceBots.tryBoost(bot, 40, { err = 0.5 })   -- turning: no
		R.expect(#srv.Telemetry.events("boost")).toBe(0)
		-- a corner within the boost's reach: no (FOREST's first bend)
		local RaceProgress = srv.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
		local geo = RaceProgress.geometry("FOREST")
		local bend
		for s = 0, 2000, 10 do
			local _, _, dx0, dz0 = geo:pointAt(s)
			local _, _, dx1, dz1 = geo:pointAt(s + 150)
			if math.abs(math.atan2(dx1, dz1) - math.atan2(dx0, dz0)) > 0.8 then bend = s break end
		end
		RaceBots.tryBoost(bot, 40, { err = 0, s = bend }, "FOREST")
		R.expect(#srv.Telemetry.events("boost")).toBe(0)
		RaceBots.tryBoost(bot, 40, { err = 0 })
		R.expect(#srv.Telemetry.events("boost")).toBe(1)
		R.expect(seat.MaxSpeed).toBeNear(base * C.BOOST_MULTIPLIER, 1e-3)
		bot.t += C.BOOST_COOLDOWN + 1
		RaceBots.tryBoost(bot, 40, { err = 0 })     -- gauge empty
		R.expect(#srv.Telemetry.events("boost")).toBe(1)
		local BoostGauge = srv.env.requirePath("ServerScriptService.Modules.BoostGauge")
		local corners = srv.mock.CollectionService:GetTagged("DriftCorner")
		BoostGauge.corner(bot.id, corners[1], os.clock())
		BoostGauge.corner(bot.id, corners[2], os.clock())
		RaceBots.tryBoost(bot, 40, { err = 0 })     -- two corners: not yet
		R.expect(#srv.Telemetry.events("boost")).toBe(1)
		BoostGauge.corner(bot.id, corners[3], os.clock())
		RaceBots.tryBoost(bot, 40, { err = 0 })
		R.expect(#srv.Telemetry.events("boost")).toBe(2)
		R.expect(srv.Telemetry.events("boost")[2].bot).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

-- History (playtest 2026-10-28): only player-player contacts were resolved
-- as hits. A player who met a bot's car pushed into it like into a wall and
-- stopped dead, side-on, juddering (Studio record-sky: 0 km/h behind a bot).
R.describe("a player's car meeting a bot's", function()
	R.it("is a hit for both: the player gets CarImpact, the bot's drive state a knock", function()
		local srv, cars, RaceBots, C, tick = race(1, 2)
		tick(C.RACE_COUNTDOWN + 0.5)
		local bot = RaceBots.list[1]
		local mine = cars[1].PrimaryPart
		local Vector3 = require("@lune/roblox").Vector3
		mine.CFrame = CFrame.new(0, 2, 400)
		bot.model:PivotTo(CFrame.new(0, 2, 394))
		mine.AssemblyLinearVelocity = Vector3.new(0, 0, -70)
		bot.primary.AssemblyLinearVelocity = Vector3.new(0, 0, -10)
		local before = bot.drive.speed or 0
		mine.Touched:Fire(bot.primary)
		local calls = rawget(srv.RemoteEvents.CarImpact, "_calls") or {}
		local toPlayer = 0
		for _, c in ipairs(calls) do
			if c.method == "FireClient" and c.args[1] == srv.players[1] then toPlayer += 1 end
		end
		R.expect(toPlayer).toBe(1)
		R.expect((bot.drive.speed or 0) > before).toBe(true)   -- pushed forward by the car behind
		local hits = srv.Telemetry.events("impact")
		R.expect(#hits).toBe(1)
		R.expect(hits[1].bot).toBe(true)
		mine.Touched:Fire(bot.primary)   -- the same pair again within PAIR_COOLDOWN: once
		R.expect(#srv.Telemetry.events("impact")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
