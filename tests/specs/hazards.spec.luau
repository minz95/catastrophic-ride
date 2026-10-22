--!nocheck
-- HazardManager with the real server scripts.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local function hazardServer(biome)
	local scripts = {
		"ServerScriptService.MapBuilders." .. biome:sub(1, 1) .. biome:sub(2):lower() .. "MapBuilder",
		"ServerScriptService.GameBootstrap",
		"ServerScriptService.RacingManager",
		"ServerScriptService.HazardManager",
	}
	local srv = Server.boot({
		players = 1, scripts = scripts, swallowErrors = true,
		harness = { harness = "lune", biome = biome, players = 1, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 600 } },
	})
	local env = srv.env
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
	local stats = VehicleStats.calculate(nil, nil, nil, biome)
	local model = VehicleBuilder.build(stats, biome, CFrame.new(0, BiomeConfig[biome].raceStartY, BiomeConfig[biome].raceStartZ), {})
	model.Parent = env.workspace
	srv.SessionManager.setVehicle(srv.players[1], model, stats)
	srv.advance(0.5)
	return srv, model
end

local HazardPlan, Constants, geo
do
	local env = require("../lib/loader").boot()
	HazardPlan = env.requirePath("ReplicatedStorage.Shared.HazardPlan")
	Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	geo = env.requirePath("ReplicatedStorage.Shared.RaceProgress").geometry("FOREST")
end

R.describe("falling logs always leave a way past (Shared/HazardPlan)", function()
	local H = Constants.HAZARDS
	local function rng(seed)
		local st = seed
		return function()
			st = (st * 1103515245 + 12345) % 2147483648
			return st / 2147483648
		end
	end
	R.it("every drop leaves an open stretch of lane wider than a car (2000 random drops)", function()
		local bad, worst = {}, math.huge
		local r = rng(7)
		for i = 1, 2000 do
			local lead = r() * geo.length
			local spots = HazardPlan.logSpots(geo, geo.width, lead, 3, r)
			for _, sp in ipairs(spots) do
				local gap = HazardPlan.widestGap(spots, sp.s, geo.width, H.LOG_SIZE[2] + 6)
				worst = math.min(worst, gap)
				if gap < H.LOG_MIN_GAP and #bad < 5 then
					table.insert(bad, string.format("drop %d at s=%d: widest gap %.1f studs", i, sp.s, gap))
				end
			end
		end
		R.expect(bad).toBeEmpty("drops that block the lane")
		R.expect(worst).toBeGreaterThan(H.LOG_MIN_GAP - 1e-6)
	end)
	R.it("logs of one drop are spread along the track and stay off the finish stretch, ramps, mud and pads", function()
		local r = rng(11)
		local bad = {}
		local track = require("../lib/loader").boot().requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
		local clear = HazardPlan.keepClear(geo, track)
		R.expect(#clear).toBeGreaterThan(10)
		for _ = 1, 500 do
			local spots = HazardPlan.logSpots(geo, geo.width, r() * geo.length, 3, r, clear)
			for _, sp in ipairs(spots) do
				for _, k in ipairs(clear) do
					if math.abs(sp.s - k) < H.LOG_KEEP_CLEAR then table.insert(bad, "on a ramp / mud / pad at s=" .. math.floor(sp.s)) end
				end
			end
			for a = 1, #spots do
				if spots[a].s > geo.length - H.LOG_FINISH_CLEAR then table.insert(bad, "near the finish") end
				for b = a + 1, #spots do
					if math.abs(spots[a].s - spots[b].s) < H.LOG_SPACING then table.insert(bad, "two logs side by side") end
				end
			end
		end
		R.expect(bad).toBeEmpty("bad spacing")
	end)
end)

R.describe("falling logs in a race (KineSim, the shared Autopilot)", function()
	local World = require("../lib/world")
	local KineSim = require("../lib/kinesim")
	local w = World.forest({ visibility = "intended" })
	local AP = w.env.requirePath("ReplicatedStorage.Shared.Autopilot")
	local car = { maxSpeed = 69, turnSpeed = 2.5, torque = 100, boostDuration = 2.2, radius = 1.9 }
	local function run(profile, avoid)
		return KineSim.run(w, { car = car, profile = AP.PROFILES[profile], seed = 1, respawn = "track", logs = true, avoid = avoid })
	end
	R.it("they lie on the racing line: a driver who ignores them hits many", function()
		local r = run("expert", false)
		R.expect(r.logHits).toBeGreaterThan(r.logsDropped * 0.3)
	end)
	R.it("a driver who looks ahead gets past almost all of them and finishes", function()
		for _, profile in ipairs({ "expert", "average" }) do
			local r = run(profile, true)
			R.expect(r.finished).toBe(true)
			R.expect(r.logHits).toBeAtMost(math.max(2, r.logsDropped * 0.05))
		end
		R.expect(run("novice", true).finished).toBe(true)
	end)
end)

R.describe("hazards", function()
	R.it("FOREST marks where a log will land, then drops logs inside the lane ahead, as obstacles, and clears them", function()
		local srv = hazardServer("FOREST")
		srv.advance(8.4)
		local function named(name)
			local out = {}
			for _, d in ipairs(srv.env.workspace.Hazards:GetDescendants()) do
				if d.Name == name then table.insert(out, d) end
			end
			return out
		end
		R.expect(#named("LogWarning")).toBeGreaterThan(0)
		R.expect(#named("FallingLog")).toBe(0)   -- the warning comes first
		srv.advance(2)
		local logs = named("FallingLog")
		R.expect(#logs).toBeGreaterThan(0)
		local RaceProgress = srv.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
		local geo = RaceProgress.geometry("FOREST")
		local bad = {}
		for _, log in ipairs(logs) do
			local p = geo:project(log.Position.X, log.Position.Z)
			if p.dist > 14 then table.insert(bad, log.Name .. " " .. p.dist .. " studs off centre") end
			if not log:HasTag("Obstacle") then table.insert(bad, log.Name .. " not tagged Obstacle") end
			if not log.Anchored then table.insert(bad, log.Name .. " not anchored: it rolls into the open side") end
			if log.Shape ~= roblox.Enum.PartType.Cylinder then table.insert(bad, log.Name .. " is not round") end
			if math.abs(log.Position.Y - (2 - 1 + log.Size.Y / 2)) > 0.2 then table.insert(bad, log.Name .. " not on the ground: Y " .. log.Position.Y) end
		end
		R.expect(bad).toBeEmpty("misplaced logs")
		srv.advance(7)
		R.expect(#named("FallingLog")).toBeLessThan(#logs + 4)
		R.expect(srv.mock.errors).toBeEmpty("errors")
	end)

	R.it("OCEAN floods: the water rises and falls back", function()
		local srv = hazardServer("OCEAN")
		srv.advance(12.6)
		R.expect(srv.env.workspace:GetAttribute("WaterLevelOffset")).toBeGreaterThan(1)
		srv.advance(6)
		R.expect(srv.env.workspace:GetAttribute("WaterLevelOffset")).toBeNear(0, 1e-6)
		R.expect(srv.mock.errors).toBeEmpty("errors")
	end)

	R.it("SKY gusts push racers sideways", function()
		local srv, model = hazardServer("SKY")
		srv.advance(10.1)
		R.expect(model.PrimaryPart:FindFirstChild("GustPush") ~= nil).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("errors")
	end)
end)
