--!nocheck
-- Fair start and phase clocks.
--
-- 2026-10-21: CraftingManager seated players one after another and unanchored
-- each car right after its own seat (~0.4 s apart, no countdown), so in a
-- 6-player lobby the last car left 2-3 s after the first. And the top speed
-- of the fastest build was 1.8x the slowest: the field finished 50-60 s apart
-- and the build, not the race, decided the order.
local R = require("../lib/runner")
local Server = require("../lib/server")
local Loader = require("../lib/loader")
local Builds = require("../lib/builds")

local function bootRace(players)
	local srv = Server.boot({
		players = players,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.MapManager",
			"ServerScriptService.CraftingManager",
			"ServerScriptService.RacingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = players, lobbyDelay = 0,
			durations = { FARMING = 0.2, CRAFTING = 0.2, RACING = 600 } },
	})
	return srv, srv.env.requirePath("ReplicatedStorage.Shared.Constants")
end

local function primaries(srv)
	local out = {}
	for _, p in ipairs(srv.players) do
		local d = srv.SessionManager.getData(p)
		out[#out + 1] = d and d.vehicleModel and d.vehicleModel.PrimaryPart or false
	end
	return out
end

R.describe("race start", function()
	R.it("holds every car on the grid until GO, then releases all of them in the same frame", function()
		local srv, Constants = bootRace(6)
		srv.advance(0.6)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local cars = primaries(srv)
		for i, p in ipairs(cars) do
			R.expect(p ~= false).toBe(true)
			R.expect(p.Anchored).toBe(true)
		end
		local goAt = srv.env.game.ReplicatedStorage:GetAttribute("RaceGoAt")
		R.expect(type(goAt)).toBe("number")
		-- Step to just before GO: still all held. Then just after: all free.
		srv.advance(goAt - srv.mock.clock - 0.05, 0.05)
		for _, p in ipairs(cars) do R.expect(p.Anchored).toBe(true) end
		srv.advance(0.1, 0.05)
		for _, p in ipairs(cars) do R.expect(p.Anchored).toBe(false) end
	end)

	R.it("refuses boosts and respawns during the countdown", function()
		local srv = bootRace(1)
		srv.advance(0.6)
		local p = srv.players[1]
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, p)).toBe("denied: countdown")
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestRespawn, p)).toBe("denied: countdown")
	end)

	R.it("starts the race clock at GO", function()
		local srv, Constants = bootRace(1)
		srv.advance(0.6)
		local goAt = srv.env.game.ReplicatedStorage:GetAttribute("RaceGoAt")
		srv.advance(goAt - srv.mock.clock + 10, 0.25)
		local finish = srv.mock.CollectionService:GetTagged("FinishLine")[1]
		local car = primaries(srv)[1]
		-- Checkpoints first, or the finish is rejected.
		for k = 1, 2 do
			local cp = srv.mock.CollectionService:GetTagged("Checkpoint" .. k)[1]
			if cp then cp.Touched:Fire(car) end
		end
		finish.Touched:Fire(car)
		local fin = srv.Telemetry.events("finish")
		R.expect(#fin).toBe(1)
		R.expect(fin[1].time).toBeNear(10, 0.3)
	end)
end)

R.describe("top speed band", function()
	local env = Loader.boot()
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": the fastest build is at most 13% faster than the slowest", function()
			local lo, hi = math.huge, 0
			for _, b in ipairs(Builds.enumerate(env, biome)) do
				lo = math.min(lo, b.maxSpeed)
				hi = math.max(hi, b.maxSpeed)
			end
			local band = Constants.RACE_SPEED[biome]
			R.expect(hi / lo).toBeLessThan(1.13)
			R.expect(lo).toBeNear(band.center * (1 - band.spread), 1e-6)
			R.expect(hi).toBeNear(band.center * (1 + band.spread), 1e-6)
		end)
		R.it(biome .. ": a better speed stat is never slower", function()
			local list = Builds.enumerate(env, biome)
			table.sort(list, function(a, b) return a.stats.speed < b.stats.speed end)
			for i = 2, #list do
				R.expect(list[i].maxSpeed >= list[i - 1].maxSpeed - 1e-9).toBe(true)
			end
		end)
	end
end)

R.describe("phase clock", function()
	R.it("publishes the server's end time of each timed phase (harness lengths included)", function()
		local srv = Server.boot({
			players = 1,
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0,
				durations = { FARMING = 30, CRAFTING = 20, RACING = 600 } },
		})
		srv.advance(1)
		local RS = srv.env.game.ReplicatedStorage
		R.expect(RS:GetAttribute("Phase")).toBe("FARMING")
		R.expect(RS:GetAttribute("PhaseEndsAt") - srv.mock.clock).toBeNear(29, 0.6)
		srv.advance(30)
		R.expect(RS:GetAttribute("Phase")).toBe("CRAFTING")
		R.expect(RS:GetAttribute("PhaseEndsAt") - srv.mock.clock).toBeNear(19, 1.2)
		srv.advance(20)
		R.expect(RS:GetAttribute("Phase")).toBe("RACING")
		R.expect(RS:GetAttribute("PhaseEndsAt")).toBe(nil)
	end)
end)
