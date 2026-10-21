--!nocheck
-- "Fun as numbers": Shared/RaceMetrics on hand-made races, and the live
-- playtest loop (RacingManager telemetry → PlaytestReporter → report) with the
-- real server scripts.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local env = Loader.boot()
local RaceMetrics = env.requirePath("ReplicatedStorage.Shared.RaceMetrics")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

-- Racer driving at a constant speed (studs/s) from t = 0, or with a speed
-- profile { {untilT, speed}, ... }.
local function racer(id, profile, length)
	local p, s, t = {}, 0, 0
	local finish
	while t < 300 do
		t += 0.5
		local v = profile
		if type(profile) == "table" then
			for _, seg in ipairs(profile) do
				if t <= seg[1] then v = seg[2] break end
			end
		end
		s = math.min(length, s + v * 0.5)
		table.insert(p, { t, s })
		if s >= length then finish = t break end
	end
	return { id = id, progress = p, finish = finish, respawns = {}, hits = {} }
end

local SECTIONS = { { name = "A", s0 = 0, s1 = 500 }, { name = "B", s0 = 500, s1 = 1000 } }

R.describe("RaceMetrics on hand-made races", function()
	R.it("a procession has no lead changes or overtakes", function()
		local m = RaceMetrics.compute({ length = 1000, sections = SECTIONS, racers = {
			racer(1, 20, 1000), racer(2, 18, 1000), racer(3, 16, 1000) } })
		R.expect(m.leadChanges).toBe(0)
		R.expect(m.overtakes).toBe(0)
		R.expect(m.finished).toBe(3)
		R.expect(m.winnerTime).toBeNear(50, 0.6)
		R.expect(m.finishSpread).toBeNear(1000 / 16 - 50, 0.6)
	end)

	R.it("a late charge counts one lead change and one overtake", function()
		-- 2 starts slow and finishes fast: passes 1 in section B
		local m = RaceMetrics.compute({ length = 1000, sections = SECTIONS, racers = {
			racer(1, 20, 1000), racer(2, { { 30, 15 }, { 300, 40 } }, 1000) } })
		R.expect(m.leadChanges).toBe(1)
		R.expect(m.overtakes).toBe(1)
		R.expect(m.decidingSection).toBe("B")
	end)

	R.it("close racing is measured while the leader is on track", function()
		local close = RaceMetrics.compute({ length = 1000, racers = { racer(1, 20, 1000), racer(2, 19.5, 1000) } })
		local far = RaceMetrics.compute({ length = 1000, racers = { racer(1, 30, 1000), racer(2, 10, 1000) } })
		R.expect(close.closeShare).toBeGreaterThan(0.9)
		R.expect(far.closeShare).toBeLessThan(0.3)
	end)

	R.it("respawns, hits and markers are counted per section", function()
		local a, b = racer(1, 20, 1000), racer(2, 20, 1000)
		a.respawns = { 600, 700 }
		b.hits = { 100 }
		local m = RaceMetrics.compute({ length = 1000, sections = SECTIONS, racers = { a, b },
			markers = { { s = 650, note = "bad" }, { s = 50, note = "fun" } } })
		R.expect(m.sections[1].hits).toBe(1)
		R.expect(m.sections[1].markers.fun).toBe(1)
		R.expect(m.sections[2].respawns).toBe(2)
		R.expect(m.sections[2].markers.bad).toBe(1)
	end)

	R.it("verdicts compare values with Constants.FUN_TARGETS and mark missing ones", function()
		local v = RaceMetrics.verdicts({ winnerTime = 200, leadChanges = 2 }, Constants.FUN_TARGETS)
		local byKey = {}
		for _, e in ipairs(v) do byKey[e.key] = e end
		R.expect(byKey.winnerTime.ok).toBe(false)
		R.expect(byKey.leadChanges.ok).toBe(true)
		R.expect(byKey.closeShare.ok).toBe(nil)
	end)
end)

R.describe("live playtest loop (real RacingManager + PlaytestReporter)", function()
	local srv = Server.boot({
		players = 2,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.PlaytestReporter",
		},
		setup = function(e) e.game.ReplicatedStorage:SetAttribute("PlaytestMarkers", true) end,
		harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 600, RESULTS = 1 } },
	})
	local senv, Mock = srv.env, srv.mock
	local VehicleBuilder = senv.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = senv.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local Track = senv.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
	local TrackGeometry = senv.requirePath("ReplicatedStorage.Shared.TrackGeometry")
	local PlaytestReport = senv.requirePath("ServerScriptService.Modules.PlaytestReport")
	local RemoteEvents = senv.requirePath("ReplicatedStorage.RemoteEvents")
	local geo = TrackGeometry.new(Track.nodes, Track.width)

	local cars = {}
	for i, player in ipairs(srv.players) do
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new((i - 1.5) * 8, 2, 590), {})
		model.Parent = senv.workspace
		srv.SessionManager.setVehicle(player, model, stats)
		cars[i] = model
	end
	-- RACING, then the 3-2-1 countdown (Modules/RaceStart) before anyone drives.
	srv.advance(0.5 + senv.requirePath("ReplicatedStorage.Shared.Constants").RACE_COUNTDOWN)
	R.it("reaches RACING", function()
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
	end)

	-- Drive both cars along the centerline: car 2 is faster but starts behind
	-- and overtakes; car 2's player drops a "bad" marker halfway.
	local speeds = { 140, 160 }
	local s = { 30, 0 }
	local finishPart = Mock.CollectionService:GetTagged("FinishLine")[1]
	local cp1 = Mock.CollectionService:GetTagged("Checkpoint1")[1]
	local cp2 = Mock.CollectionService:GetTagged("Checkpoint2")[1]
	local done, marked = {}, false
	local cpS = { geo:project(cp1.Position.X, cp1.Position.Z).s, geo:project(cp2.Position.X, cp2.Position.Z).s }
	local passed = { {}, {} }
	srv.advance(60, 0.25, function()
		for i, model in ipairs(cars) do
			if not done[i] then
				s[i] = math.min(geo.length - 1, s[i] + speeds[i] * 0.25)
				local x, z = geo:pointAt(s[i])
				model:PivotTo(CFrame.new(x, 2, z))
				for k = 1, 2 do
					if not passed[i][k] and s[i] >= cpS[k] then
						passed[i][k] = true
						;(k == 1 and cp1 or cp2).Touched:Fire(model.PrimaryPart)
					end
				end
				if s[i] >= Track.finishZ and math.abs(z - Track.finishZ) < 3 or s[i] >= geo.length - 60 then
					finishPart.Touched:Fire(model.PrimaryPart)
					done[i] = true
				end
				if i == 2 and not marked and s[i] > geo.length / 2 then
					marked = true
					RemoteEvents.PlaytestMark.OnServerEvent:Fire(srv.players[2], "bad")
				end
			end
		end
	end)
	srv.advance(3)

	R.it("records race_start, one progress sample per racer per second and the marker", function()
		local Telemetry = srv.Telemetry
		R.expect(#Telemetry.events("race_start")).toBeGreaterThan(0)  -- RESULTS = 1 s, so a second round may start
		R.expect(#Telemetry.events("race_progress")).toBeGreaterThan(40)
		local fb = Telemetry.events("feedback")
		R.expect(#fb).toBe(1)
		R.expect(fb[1].note).toBe("bad")
		R.expect(fb[1].section ~= nil).toBe(true)
	end)

	R.it("prints a fun report at RESULTS with finishers, the overtake and the marker", function()
		local r = PlaytestReport.last
		R.expect(r ~= nil).toBe(true)
		R.expect(r.metrics.finished).toBe(2)
		R.expect(r.metrics.leadChanges).toBe(1)
		R.expect(#r.markers).toBe(1)
		R.expect(PlaytestReport.format(r):find("lead changes 1") ~= nil).toBe(true)
	end)
end)
