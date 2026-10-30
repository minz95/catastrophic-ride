--!nocheck
-- Second launch check (2026-10-30): a long-running server, phones, and the
-- work every phase change does.
local R = require("../lib/runner")
local Server = require("../lib/server")
local Loader = require("../lib/loader")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local function raceServer(n, racing)
	local srv = Server.boot({
		players = n,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = n, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 2, RACING = racing } },
		swallowErrors = true,
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
	srv.advance(0.5)
	assert(srv.GameManager.getPhase() == "RACING")
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	srv.advance(C.RACE_COUNTDOWN + 0.5)
	local function finish(i)
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			srv.mock.CollectionService:GetTagged(tag)[1].Touched:Fire(cars[i].PrimaryPart)
			srv.advance(0.1)
		end
	end
	return srv, cars, finish, C
end

R.describe("a round that never reaches RESULTS", function()
	R.it("an error at the race's end goes back to the lobby, and the race is over there (no race left running)", function()
		local srv, _, finish = raceServer(1)
		-- the RESULTS start fails once (its phase telemetry errors)
		local record = srv.Telemetry.record
		local failed = false
		srv.Telemetry.record = function(kind, fields)
			if kind == "phase" and fields and fields.phase == "RESULTS" and not failed then
				failed = true
				error("boom")
			end
			return record(kind, fields)
		end
		finish(1)
		R.expect(failed).toBe(true)
		local errs = srv.Telemetry.events("phase_error")
		R.expect(#errs).toBe(1)   -- the race end used to be unguarded: stuck in RACING for good
		-- back to the lobby after 3 s, then the next round's race
		local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
		srv.advance(3.4)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local e = srv.env
		local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
		local car = e.requirePath("ServerScriptService.Modules.VehicleBuilder").build(stats, "FOREST", CFrame.new(7, 2, 590), {})
		car.Parent = e.workspace
		srv.SessionManager.setVehicle(srv.players[1], car, stats)
		srv.advance(C.RACE_COUNTDOWN + 0.5)
		R.expect(srv.GameManager.getRound()).toBe(2)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		-- one progress loop, not the dead race's as well (1 sample a second)
		local before = #srv.Telemetry.events("race_progress")
		srv.advance(5)
		local samples = #srv.Telemetry.events("race_progress") - before
		R.expect(samples <= 6).toBe(true)
		R.expect(samples >= 4).toBe(true)
	end)
end)

R.describe("a race that times out into an error", function()
	R.it("the race is over at the lobby (its loops ran on into the next race)", function()
		local srv = raceServer(1, 3)   -- a 3 s race nobody finishes
		local record = srv.Telemetry.record
		local failed = false
		srv.Telemetry.record = function(kind, fields)
			if kind == "phase" and fields and fields.phase == "RESULTS" and not failed then
				failed = true
				error("boom")
			end
			return record(kind, fields)
		end
		local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
		-- at the lobby the race must be over (RacingManager's handler runs first)
		local atLobby = nil
		srv.GameManager.onPhaseChanged(function(phase)
			if phase == "LOBBY" and failed and atLobby == nil then
				atLobby = srv.invoke("RequestRespawn", srv.players[1])
			end
		end)
		-- time out, 3 s to the lobby, then the next round's race
		local t = 0
		while not (failed and srv.GameManager.getPhase() == "RACING") and t < 30 do
			srv.advance(0.1); t += 0.1
		end
		R.expect(failed).toBe(true)
		R.expect(srv.GameManager.getRound()).toBe(2)
		R.expect(atLobby).toBe("denied: not racing")   -- the dead race kept running into the next one
		local e = srv.env
		local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
		local car = e.requirePath("ServerScriptService.Modules.VehicleBuilder").build(stats, "FOREST", CFrame.new(7, 2, 590), {})
		car.Parent = e.workspace
		srv.SessionManager.setVehicle(srv.players[1], car, stats)
		srv.advance(C.RACE_COUNTDOWN + 0.5)
		local before = #srv.Telemetry.events("race_progress")
		srv.advance(2)
		local samples = #srv.Telemetry.events("race_progress") - before
		R.expect(samples <= 3).toBe(true)
	end)
end)

R.describe("map visibility in one pass (MapVisibility.applyPhase)", function()
	local function maps()
		local env = Loader.boot()
		local maps = {}
		for _, b in ipairs({ "ForestMap", "OceanMap" }) do
			maps[b] = env.requirePath("ServerScriptService.Modules.Maps." .. b).build()
		end
		local MV = env.requirePath("ServerScriptService.Modules.MapVisibility")
		return env, maps, MV
	end

	R.it("a hidden map's labels go off; the live map's race-track labels follow the phase", function()
		local env, m, MV = maps()
		local function labels(map, sub)
			local on, n = 0, 0
			local root = sub and map:FindFirstChild(sub) or map
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
					n += 1
					if d.Enabled then on += 1 end
				end
			end
			return on, n
		end
		MV.applyPhase(env.workspace.Maps, m.OceanMap, "RaceTrack")   -- an OCEAN race
		MV.applyPhase(env.workspace.Maps, m.ForestMap, "FarmArea")   -- then a FOREST round
		local onO, nO = labels(m.OceanMap, "RaceTrack")
		R.expect(nO > 0).toBe(true)
		R.expect(onO).toBe(0)   -- OCEAN's checkpoint labels floated over FOREST
		local onF = labels(m.ForestMap, "RaceTrack")
		R.expect(onF).toBe(0)   -- farming: the race track's labels are off
		MV.applyPhase(env.workspace.Maps, m.ForestMap, "RaceTrack")
		local onF2, nF2 = labels(m.ForestMap, "RaceTrack")
		R.expect(onF2).toBe(nF2)
	end)

	R.it("a second pass in the same state writes nothing", function()
		local env, m, MV = maps()
		MV.applyPhase(env.workspace.Maps, m.ForestMap, "FarmArea")
		local writes = 0
		local conns = {}
		for _, d in ipairs(env.workspace.Maps:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(conns, d.Changed:Connect(function() writes += 1 end))
			end
		end
		MV.applyPhase(env.workspace.Maps, m.ForestMap, "FarmArea")
		for _, c in ipairs(conns) do c:Disconnect() end
		R.expect(writes).toBe(0)
	end)
end)

R.describe("work per frame", function()
	R.it("farm items have no Heartbeat of their own (anchored: the bob wrote a replicated value every frame)", function()
		local src = fs.readFile("roblox/ServerScriptService/Modules/ItemVisualUpgrader.lua")
		R.expect(src:find("Heartbeat:Connect", 1, true)).toBe(nil)
	end)

	R.it("SKY's fence and the slow zones are a few hundred parts, not thousands", function()
		local env = Loader.boot()
		local sky = env.requirePath("ServerScriptService.Modules.Maps.SkyMap").build()
		local fence, total = 0, 0
		for _, d in ipairs(sky:GetDescendants()) do
			if d:IsA("BasePart") then
				total += 1
				if d.Name:sub(1, 11) == "SkyBarrier_" then fence += 1 end
			end
		end
		R.expect(fence < 1500).toBe(true)   -- 7 969 two-stud pillars before
		R.expect(total < 4000).toBe(true)
	end)

	R.it("live servers keep a short event log", function()
		local srv = Server.boot({ live = true, scripts = {} })
		R.expect(srv.Telemetry.CAPACITY).toBe(srv.Telemetry.LIVE_CAPACITY)
	end)
end)

R.describe("phones (source checks; the layout itself: phone_layout)", function()
	R.it("the scaled shop panel is anchored at its centre (a UIScale shrinks about the AnchorPoint)", function()
		local src = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		R.expect(src:find('panel.AnchorPoint      = Vector2.new(0.5, 0.5)', 1, true) ~= nil).toBe(true)
	end)
	R.it("the help panel scrolls and the results sit on one scaled stage", function()
		local tut = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
		R.expect(tut:find('Instance.new("ScrollingFrame")', 1, true) ~= nil).toBe(true)
		local res = fs.readFile("roblox/StarterGui/ResultsUI/init.client.lua")
		R.expect(res:find("Parent            = bg", 1, true)).toBe(nil)
	end)
	R.it("the game is landscape only", function()
		local proj = fs.readFile("roblox/default.project.json")
		R.expect(proj:find('"ScreenOrientation": "LandscapeSensor"', 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("track drops stay on the road", function()
	R.it("a drop past the lane edge is pulled back inside (a Gas Can landed 21 studs off the FOREST centre line)", function()
		local env = Loader.boot()
		env.game:GetService("ReplicatedStorage"):SetAttribute("Biome", "FOREST")
		local TrackDrops = env.requirePath("ServerScriptService.Modules.TrackDrops")
		local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
		local geo = RaceProgress.geometry("FOREST")
		local V = roblox.Vector3
		local p = TrackDrops.clampToLane(V.new(76, 1, -2827))
		local q = geo:project(p.X, p.Z, nil, nil, p.Y)
		R.expect(math.abs(q.lateral) <= geo.halfWidth - TrackDrops.LANE_INSET + 0.01).toBe(true)
		local inLane = V.new(q.cx, 1, q.cz)
		local same = TrackDrops.clampToLane(inLane)
		R.expect((same - inLane).Magnitude < 1e-6).toBe(true)
	end)
end)
