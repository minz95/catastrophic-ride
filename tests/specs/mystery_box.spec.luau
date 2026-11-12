--!nocheck
-- Item boxes on the race track (2026-11-12: "obstacles are too predictable",
-- "the agent still wins"): Shared/BoxPlan (new spots every race, odds by
-- place), Modules/MysteryBoxes (pickup, one power at a time, back after a
-- while) and the powers in AbilityManager (T uses the held one first).
local R = require("../lib/runner")
local Server = require("../lib/server")
local Loader = require("../lib/loader")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local function seq(seed)
	local x = seed
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

R.describe("item boxes: where they stand (BoxPlan)", function()
	local env = Loader.boot()
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local BoxPlan = env.requirePath("ReplicatedStorage.Shared.BoxPlan")
	local HazardPlan = env.requirePath("ReplicatedStorage.Shared.HazardPlan")
	local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
	local B = Constants.MYSTERY_BOX
	local TRACKS = { FOREST = "ForestTrack", OCEAN = "OceanTrack", SKY = "SkyTrack" }

	for biome, name in pairs(TRACKS) do
		R.it(biome .. ": every row on the lane, clear of the start, finish, ramps and pads", function()
			local geo = RaceProgress.geometry(biome)
			local track = env.requirePath("ReplicatedStorage.Shared.Tracks." .. name)
			local keep = HazardPlan.keepClear(geo, track)
			for _, c in ipairs(track.checkpoints) do table.insert(keep, geo:project(c[1], c[2], nil, nil, c[3]).s) end
			local finishS = track.finishZ and geo:project(track.finishX or 0, track.finishZ).s or geo.length
			for seed = 1, 20 do
				local rows = BoxPlan.rows(geo, track, biome, seq(seed))
				R.expect(#rows).toBe(B.ROWS)
				for _, row in ipairs(rows) do
					R.expect(row.s >= B.START_CLEAR and row.s <= finishS - B.FINISH_CLEAR).toBe(true)
					for _, k in ipairs(keep) do
						R.expect(math.abs(k - row.s) >= B.KEEP_CLEAR).toBe(true)
					end
					R.expect(#row.boxes).toBe(B.PER_ROW)
					for _, b in ipairs(row.boxes) do
						local p = geo:project(b.x, b.z, nil, nil, b.y)
						R.expect(p.dist <= geo.halfWidth - B.SIZE / 2).toBe(true)
						R.expect(b.y - geo:heightAt(row.s)).toBeNear(B.FLOAT[biome], 1e-6)
					end
				end
			end
		end)
	end

	R.it("another race, other spots", function()
		local geo = RaceProgress.geometry("FOREST")
		local track = env.requirePath("ReplicatedStorage.Shared.Tracks.ForestTrack")
		local a = BoxPlan.rows(geo, track, "FOREST", seq(1))
		local b = BoxPlan.rows(geo, track, "FOREST", seq(2))
		local moved = 0
		for i = 1, #a do
			if math.abs(a[i].s - b[i].s) > 20 then moved += 1 end
		end
		R.expect(moved >= 2).toBe(true)
	end)

	R.it("odds by place: the leader never gets Zap; the back of the field gets the strong ones", function()
		local function draw(ahead)
			local counts, rnd = {}, seq(7)
			for _ = 1, 2000 do
				local p = BoxPlan.power(ahead, rnd)
				counts[p] = (counts[p] or 0) + 1
			end
			return counts
		end
		local lead, last = draw(0), draw(1)
		R.expect(lead.zap).toBe(nil)
		R.expect(lead.bomb).toBe(nil)
		R.expect((lead.oil or 0) + (lead.shield or 0) > 1200).toBe(true)
		R.expect((last.rocket or 0) + (last.bomb or 0) + (last.zap or 0) > 1600).toBe(true)
		R.expect(BoxPlan.ahead(1, 6)).toBe(0)
		R.expect(BoxPlan.ahead(6, 6)).toBe(1)
		for _, p in pairs(B.POWERS) do R.expect(type(p.icon)).toBe("string") end
	end)
end)

local function boxServer()
	local srv = Server.boot({
		players = 2,
		swallowErrors = true,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
			"ServerScriptService.AbilityManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 900 } },
	})
	local env = srv.env
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local cars = {}
	for i, player in ipairs(srv.players) do
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		stats.slotAssignments = {}
		local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 520 - (i - 1) * 6), {})
		model.Parent = env.workspace
		srv.SessionManager.setVehicle(player, model, stats)
		cars[i] = { player = player, model = model, stats = stats, seat = model:FindFirstChildWhichIsA("VehicleSeat", true) }
	end
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	srv.advance(Constants.RACE_COUNTDOWN + 0.5)
	return srv, cars, Constants
end

R.describe("item boxes in a race (MysteryBoxes + AbilityManager)", function()
	R.it("a race lays out its rows; driving through a box gives a power; one at a time; the box comes back", function()
		local srv, cars, Constants = boxServer()
		local B = Constants.MYSTERY_BOX
		local MysteryBoxes = srv.env.requirePath("ServerScriptService.Modules.MysteryBoxes")
		local folder = srv.env.workspace:FindFirstChild("MysteryBoxes")
		R.expect(folder ~= nil).toBe(true)
		local boxes = MysteryBoxes.boxes()
		R.expect(#boxes).toBe(B.ROWS * B.PER_ROW)
		R.expect(#folder:GetChildren()).toBe(B.ROWS * B.PER_ROW)
		local box = boxes[1]
		cars[1].model:PivotTo(CFrame.new(box.x, box.y - 1, box.z))
		srv.advance(0.3)
		local power = cars[1].player:GetAttribute("BoxPower")
		R.expect(B.POWERS[power] ~= nil).toBe(true)
		R.expect(cars[1].player:GetAttribute("TKey")).toBe(B.POWERS[power].icon)
		R.expect(box.part:GetAttribute("Taken")).toBe(true)
		-- holding one: the next box stays
		local other = boxes[2]
		cars[1].model:PivotTo(CFrame.new(other.x, other.y - 1, other.z))
		srv.advance(0.3)
		R.expect(other.part:GetAttribute("Taken")).toBe(false)
		R.expect(cars[1].player:GetAttribute("BoxPower")).toBe(power)
		srv.advance(B.RESPAWN)
		R.expect(box.part:GetAttribute("Taken")).toBe(false)
		R.expect(#srv.mock.errors).toBe(0)
	end)

	R.it("Rocket speeds you up; T uses the box power before the shop trick", function()
		local srv, cars, Constants = boxServer()
		local P = Constants.MYSTERY_BOX.POWERS
		local MysteryBoxes = srv.env.requirePath("ServerScriptService.Modules.MysteryBoxes")
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		MysteryBoxes.give(cars[1].player, "rocket")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("ok")
		R.expect(cars[1].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[1].seat, "MaxSpeed") * P.rocket.speed, 1e-6)
		R.expect(cars[1].player:GetAttribute("BoxPower")).toBe(nil)
		R.expect(cars[1].player:GetAttribute("TKey")).toBe(nil)
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("denied: no trick")
	end)

	R.it("Bomb hits the car ahead (kept when nobody is ahead); a Shield blocks it", function()
		local srv, cars, Constants = boxServer()
		local P = Constants.MYSTERY_BOX.POWERS
		local MysteryBoxes = srv.env.requirePath("ServerScriptService.Modules.MysteryBoxes")
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		-- car 2 is 6 studs in front of car 1 (cars face -Z)
		MysteryBoxes.give(cars[2].player, "bomb")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[2].player)).toBe("denied: no car ahead")
		R.expect(cars[2].player:GetAttribute("BoxPower")).toBe("bomb")
		-- a shield on car 2 first: car 1's bomb is blocked
		MysteryBoxes.give(cars[2].player, "shield")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[2].player)).toBe("ok")
		MysteryBoxes.give(cars[1].player, "bomb")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("ok")
		srv.advance(0.05)
		R.expect(cars[2].model.PrimaryPart:GetAttribute("LiftOffset")).toBe(nil)
		MysteryBoxes.give(cars[1].player, "bomb")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("ok")
		srv.advance(0.05)
		R.expect(cars[2].model.PrimaryPart:GetAttribute("LiftOffset")).toBe(P.bomb.lift)
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed") * P.bomb.slow, 1e-6)
	end)

	R.it("Zap slows every car ahead, not the ones behind; Oil leaves a slick behind you", function()
		local srv, cars, Constants = boxServer()
		local P = Constants.MYSTERY_BOX.POWERS
		local MysteryBoxes = srv.env.requirePath("ServerScriptService.Modules.MysteryBoxes")
		local VehicleTuning = srv.env.requirePath("ServerScriptService.Modules.VehicleTuning")
		srv.SessionManager.setRaceProgress(cars[1].player, 100, 2)
		srv.SessionManager.setRaceProgress(cars[2].player, 300, 1)
		MysteryBoxes.give(cars[2].player, "zap")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[2].player)).toBe("ok")
		R.expect(cars[1].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[1].seat, "MaxSpeed"), 1e-6)
		MysteryBoxes.give(cars[1].player, "zap")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("ok")
		R.expect(cars[2].seat.MaxSpeed).toBeNear(VehicleTuning.base(cars[2].seat, "MaxSpeed") * P.zap.slow, 1e-6)
		R.expect(MysteryBoxes.aheadOf(cars[1].player)).toBe(1)
		R.expect(MysteryBoxes.aheadOf(cars[2].player)).toBe(0)
		local drops = srv.env.workspace:FindFirstChild("TrackDrops")
		local before = drops and #drops:GetChildren() or 0
		MysteryBoxes.give(cars[1].player, "oil")
		R.expect(srv.mock.invoke(srv.RemoteEvents.UseRaceTrick, cars[1].player)).toBe("ok")
		srv.advance(0.05)
		drops = srv.env.workspace:FindFirstChild("TrackDrops")
		R.expect(drops and #drops:GetChildren() or 0).toBe(before + 1)
		R.expect(#srv.mock.errors).toBe(0)
	end)

	R.it("the race ends: boxes and held powers go", function()
		local srv, cars = boxServer()
		local MysteryBoxes = srv.env.requirePath("ServerScriptService.Modules.MysteryBoxes")
		MysteryBoxes.give(cars[1].player, "rocket")
		srv.GameManager.shortenPhase("RACING", 0)
		srv.advance(1)
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		R.expect(srv.env.workspace:FindFirstChild("MysteryBoxes")).toBe(nil)
		R.expect(cars[1].player:GetAttribute("BoxPower")).toBe(nil)
	end)

	R.it("the client side: HUD slot, T key, touch label and the box spinner are wired", function()
		local fs = require("@lune/fs")
		local hud = fs.readFile("roblox/StarterGui/HUD/init.client.lua")
		R.expect(hud:find('GetAttributeChangedSignal("BoxPower")', 1, true) ~= nil).toBe(true)
		local rc = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		R.expect(rc:find('GetAttribute("TKey")', 1, true) ~= nil).toBe(true)
		local touch = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua")
		R.expect(touch:find("b.textAttr", 1, true) ~= nil).toBe(true)
		local fx = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/MysteryBoxFx.client.lua")
		R.expect(fx:find('"MysteryBox"', 1, true) ~= nil).toBe(true)
	end)
end)
