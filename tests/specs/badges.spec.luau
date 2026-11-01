--!nocheck
-- Roblox badges (Modules/Badges, BadgeManager): which moment earns which,
-- once per player, nothing with id 0, and a real race hands them out.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local CFrame = require("@lune/roblox").CFrame

R.describe("Badges", function()
	local env = Loader.boot()
	local B = env.requirePath("ServerScriptService.Modules.Badges")

	local function keys(list)
		local out = {}
		for _, b in ipairs(list) do table.insert(out, b.userId .. ":" .. b.key) end
		return table.concat(out, ", ")
	end

	R.it("a finish earns Finish Line, a win also Champion; bots earn nothing", function()
		R.expect(keys(B.forEvent("finish", { userId = 7, place = 2 }))).toBe("7:first_finish")
		R.expect(keys(B.forEvent("finish", { userId = 7, place = 1 }))).toBe("7:first_finish, 7:champion")
		R.expect(keys(B.forEvent("finish", { userId = -1, place = 1, bot = true }))).toBe("")
	end)

	R.it("a steal earns Sticky Fingers for the thief; level 5 from a reward", function()
		R.expect(keys(B.forEvent("steal", { thief = 3, victim = 4 }))).toBe("3:sticky")
		R.expect(keys(B.forEvent("steal", { thief = -2, victim = 4 }))).toBe("")
		R.expect(keys(B.forEvent("reward", { userId = 3, level = 4 }))).toBe("")
		R.expect(keys(B.forEvent("reward", { userId = 3, level = B.LEVEL }))).toBe("3:level5")
	end)

	R.it("every badge has a name, a description and a picture", function()
		local fs = require("@lune/fs")
		for _, b in ipairs(B.LIST) do
			R.expect(#b.name > 0 and #b.description > 0).toBe(true)
			R.expect(fs.isFile("assets/badges/" .. b.key .. ".png")).toBe(true)
		end
	end)

	R.it("awards once per player and skips badges without an id", function()
		local calls = {}
		B.sink = function(userId, key) table.insert(calls, userId .. ":" .. key) end
		local p = { UserId = 11 }
		B.award(p, "champion")            -- id 0: off
		B.get("champion").id = 123
		B.award(p, "champion")
		B.award(p, "champion")
		B.get("champion").id = 0
		B.sink = nil
		R.expect(table.concat(calls, ", ")).toBe("11:champion")
	end)

	R.it("is off in harness and Studio sessions", function()
		R.expect(B.enabled).toBe(false)
	end)

	R.it("a race hands out Welcome, Finish Line and Champion to the right players", function()
		local calls = {}
		local srv = Server.boot({
			players = 3,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.BadgeManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 3, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
			setup = function(e)
				local Bs = e.requirePath("ServerScriptService.Modules.Badges")
				for i, b in ipairs(Bs.LIST) do b.id = 1000 + i end
				Bs.sink = function(userId, key) table.insert(calls, { userId = userId, key = key }) end
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
		srv.advance(Consts.RACE_COUNTDOWN + 0.5)
		local function tagged(tag) return srv.mock.CollectionService:GetTagged(tag)[1] end
		for _, i in ipairs({ 2, 1 }) do   -- player 2 wins, 1 second, 3 never finishes
			for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
				tagged(tag).Touched:Fire(cars[i].PrimaryPart)
				srv.advance(0.1)
			end
		end
		srv.advance(Consts.FINISH_GRACE + 1.5)
		local function got(player, key)
			for _, c in ipairs(calls) do
				if c.userId == player.UserId and c.key == key then return true end
			end
			return false
		end
		local P = srv.players
		for _, p in ipairs(P) do R.expect(got(p, "welcome")).toBe(true) end
		R.expect(got(P[2], "first_finish") and got(P[2], "champion")).toBe(true)
		R.expect(got(P[1], "first_finish")).toBe(true)
		R.expect(got(P[1], "champion")).toBe(false)
		R.expect(got(P[3], "first_finish")).toBe(false)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)
