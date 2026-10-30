--!nocheck
-- A full server (Constants.MAX_PLAYERS = 10) for several rounds with every
-- server script: Studio's multiplayer test stops at 8 players, so the
-- 10-player case is checked here. Cars do not drive in the mock engine: each
-- round every car is sent through the checkpoints and the finish by hand.
local R = require("../lib/runner")
local Server = require("../lib/server")

local SCRIPTS = {
	"ServerScriptService.MapBuilders.ForestMapBuilder",
	"ServerScriptService.MapBuilders.OceanMapBuilder",
	"ServerScriptService.MapBuilders.SkyMapBuilder",
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.ItemModelPreloader",
	"ServerScriptService.CharacterManager",
	"ServerScriptService.FarmingManager",
	"ServerScriptService.CraftingManager",
	"ServerScriptService.RacingManager",
	"ServerScriptService.AbilityManager",
	"ServerScriptService.HazardManager",
	"ServerScriptService.ProgressionManager",
	"ServerScriptService.ShopManager",
	"ServerScriptService.AnalyticsManager",
}

local function run(n, biome, rounds, fillBots)
	local srv = Server.boot({
		players = n,
		scripts = SCRIPTS,
		quiet = true,
		harness = { harness = "lune", biome = biome, players = n, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 6, CRAFTING = 2, RACING = 120, RESULTS = 2 } },
	})
	local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
	local out = { rounds = {} }
	local function waitPhase(phase, limit)
		local t = 0
		while srv.GameManager.getPhase() ~= phase and t < (limit or 60) do
			srv.advance(0.25); t += 0.25
		end
		return srv.GameManager.getPhase() == phase
	end
	for r = 1, rounds do
		local info = {}
		info.raced = waitPhase("RACING", 60)
		srv.advance(C.RACE_COUNTDOWN + 0.5)
		-- every player's car, where it stands on the grid
		local cars, spots = {}, {}
		for _, p in ipairs(srv.players) do
			local d = srv.SessionManager.getData(p)
			local car = d and d.vehicleModel
			if car and car.PrimaryPart then
				table.insert(cars, car)
				table.insert(spots, car.PrimaryPart.Position)
			end
		end
		info.cars = #cars
		local closest = math.huge
		for i = 1, #spots do
			for j = i + 1, #spots do
				closest = math.min(closest, (spots[i] - spots[j]).Magnitude)
			end
		end
		info.closest = closest
		-- everyone drives through the checkpoints and the finish
		for _, car in ipairs(cars) do
			for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
				for _, part in ipairs(srv.mock.CollectionService:GetTagged(tag)) do
					if part:IsDescendantOf(srv.env.workspace.Maps:FindFirstChild(biome:sub(1, 1) .. biome:sub(2):lower() .. "Map")) then
						part.Touched:Fire(car.PrimaryPart)
					end
				end
				srv.advance(0.05)
			end
		end
		info.results = waitPhase("RESULTS", 90)
		info.round = srv.GameManager.getRound()
		out.rounds[r] = info
		waitPhase("LOBBY", 30)
	end
	out.errors = srv.mock.errors
	out.finishes = srv.Telemetry.events("finish")
	out.rewards = srv.Telemetry.events("reward")
	out.phaseErrors = srv.Telemetry.events("phase_error")
	out.srv = srv
	return out
end

R.describe("a full server: 10 players", function()
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": three rounds, ten cars on ten grid slots, ten finishers and rewards each round, no errors", function()
			local out = run(10, biome, 3)
			R.expect(out.errors).toBeEmpty("server errors")
			R.expect(#out.phaseErrors).toBe(0)
			for r, info in ipairs(out.rounds) do
				R.expect(info.raced).toBe(true)
				R.expect(info.cars).toBe(10)
				R.expect(info.closest > 5).toBe(true)   -- two cars on one slot would be inside each other
				R.expect(info.results).toBe(true)
				R.expect(info.round).toBe(r)
			end
			local players = 0
			for _, f in ipairs(out.finishes) do
				if (f.userId or 0) > 0 then players += 1 end
			end
			R.expect(players).toBe(30)
			R.expect(#out.rewards).toBe(30)
		end)
	end

	R.it("a full server gets no bots (the head count is drawn up to BOTS.FILL.MAX)", function()
		local out = run(10, "FOREST", 1, true)
		local bots = out.srv.SessionManager.bots and out.srv.SessionManager.bots() or {}
		R.expect(#bots).toBe(0)
		R.expect(out.errors).toBeEmpty("server errors")
	end)
end)
