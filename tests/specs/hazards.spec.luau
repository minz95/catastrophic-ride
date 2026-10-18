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

R.describe("hazards", function()
	R.it("FOREST drops falling logs inside the lane ahead, as obstacles, and clears them", function()
		local srv = hazardServer("FOREST")
		srv.advance(8.6)
		local logs = srv.env.workspace.Hazards:GetChildren()
		R.expect(#logs).toBeGreaterThan(0)
		local RaceProgress = srv.env.requirePath("ReplicatedStorage.Shared.RaceProgress")
		local geo = RaceProgress.geometry("FOREST")
		local bad = {}
		for _, log in ipairs(logs) do
			local p = geo:project(log.Position.X, log.Position.Z)
			if p.dist > 14 then table.insert(bad, log.Name .. " " .. p.dist .. " studs off centre") end
			if not log:HasTag("Obstacle") then table.insert(bad, log.Name .. " not tagged Obstacle") end
		end
		R.expect(bad).toBeEmpty("misplaced logs")
		srv.advance(7)
		R.expect(#srv.env.workspace.Hazards:GetChildren()).toBeLessThan(#logs + 4)
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
