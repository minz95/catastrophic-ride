--!nocheck
-- Each round's weather (Shared/Weather): night forest, stormy sea, sunset
-- and thunder in the sky. Lighting, water, hazards and what clients draw.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

R.describe("Weather", function()
	local env = Loader.boot()
	local W = env.requirePath("ReplicatedStorage.Shared.Weather")
	local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
	local Presets = env.requirePath("ServerScriptService.Modules.LightingPresets")

	R.it("every biome draws clear most often and each of its weathers now and then", function()
		local st = 5
		local function rand() st = (st * 1103515245 + 12345) % 2147483648; return st / 2147483648 end
		for biome, choices in pairs(W.CHOICES) do
			local seen = {}
			for _ = 1, 4000 do local k = W.pick(biome, rand); seen[k] = (seen[k] or 0) + 1 end
			for k in pairs(choices) do
				R.expect((seen[k] or 0) > 400).toBe(true)
				if k ~= "clear" then R.expect(W.look(biome, k) ~= nil).toBe(true) end
			end
			R.expect(seen.clear > 1500).toBe(true)
		end
		R.expect(W.look("FOREST", "night").fx.headlights).toBe(true)
		R.expect(W.pick("NOWHERE", math.random)).toBe("clear")
	end)

	R.it("lighting is the biome preset with the weather over it; clear changes nothing", function()
		local clear = W.lighting(Presets.FOREST, "FOREST", "clear")
		R.expect(clear.ClockTime).toBe(Presets.FOREST.ClockTime)
		local night = W.lighting(Presets.FOREST, "FOREST", "night")
		R.expect(night.ClockTime).toBe(0)
		R.expect(night.FogEnd < Presets.FOREST.FogEnd).toBe(true)
		R.expect(Presets.FOREST.ClockTime).toBe(12)   -- the preset itself untouched
		-- every weather sets the same properties the presets set (a night never stays)
		for biome, looks in pairs(W.LOOK) do
			for key, look in pairs(looks) do
				for prop in pairs(look.lighting or {}) do
					R.expect(Presets[biome][prop] ~= nil).toBe(true, biome .. "/" .. key .. " sets " .. prop .. " the preset does not reset")
				end
			end
		end
	end)

	R.it("a storm at sea floods more and adds gusts; a thunder sky gusts more; BiomeConfig untouched", function()
		local sea = W.hazards(BiomeConfig.OCEAN.hazards, "OCEAN", "storm")
		local flood, gust
		for _, hz in ipairs(sea) do
			if hz.type == "waveFlood" then flood = hz end
			if hz.type == "gustZone" then gust = hz end
		end
		R.expect(flood.interval < 12 and flood.riseHeight > 3).toBe(true)
		R.expect(gust ~= nil).toBe(true)
		local base
		for _, hz in ipairs(BiomeConfig.OCEAN.hazards) do if hz.type == "waveFlood" then base = hz end end
		R.expect(base.interval).toBe(12)
		local sky = W.hazards(BiomeConfig.SKY.hazards, "SKY", "storm")
		for _, hz in ipairs(sky) do
			if hz.type == "gustZone" then R.expect(hz.interval < 10 and hz.force > 150).toBe(true) end
		end
		R.expect(#W.hazards(BiomeConfig.SKY.hazards, "SKY", "clear")).toBe(#BiomeConfig.SKY.hazards)
	end)

	R.it("a stormy-sea round: the server sets the weather, the lighting, the water and gusts at sea", function()
		local srv = Server.boot({
			players = 1, swallowErrors = true,
			scripts = {
				"ServerScriptService.MapBuilders.OceanMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.MapManager",
				"ServerScriptService.RacingManager",
				"ServerScriptService.HazardManager",
			},
			harness = { harness = "lune", biome = "OCEAN", weather = "storm", players = 1, lobbyDelay = 0,
				durations = { FARMING = 0.5, CRAFTING = 0.1, RACING = 600 } },
		})
		local e = srv.env
		srv.advance(0.3)
		R.expect(e.game.ReplicatedStorage:GetAttribute("Weather")).toBe("storm")
		R.expect(srv.GameManager.getWeather()).toBe("storm")
		local Lighting = e.game:GetService("Lighting")
		R.expect(Lighting.ClockTime).toBe(W.look("OCEAN", "storm").lighting.ClockTime)
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
		local stats = VehicleStats.calculate(nil, nil, nil, "OCEAN")
		local model = VehicleBuilder.build(stats, "OCEAN", CFrame.new(0, 3, 590), {})
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(srv.players[1], model, stats)
		srv.advance(14)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local gusts, floods = 0, 0
		for _, ev in ipairs(srv.Telemetry.events("hazard")) do
			if ev.type == "gustZone" then gusts += 1 end
			if ev.type == "waveFlood" then floods += 1 end
		end
		R.expect(gusts).toBeGreaterThan(0)
		R.expect(floods).toBeGreaterThan(0)
		local phases = srv.Telemetry.events("phase")
		R.expect(phases[#phases].weather).toBe("storm")
	end)

	R.it("a harness without a weather races in clear weather", function()
		local srv = Server.boot({
			players = 1, scripts = { "ServerScriptService.GameBootstrap" },
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, durations = { FARMING = 5 } },
		})
		srv.advance(0.3)
		R.expect(srv.GameManager.getWeather()).toBe("clear")
	end)

	R.it("clients draw it: WeatherFx, the farming toast names it", function()
		local fx = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/WeatherFx.client.lua")
		for _, s in ipairs({ "ParticleEmitter", "SpotLight", "ColorCorrectionEffect", 'GetAttribute("Weather")' }) do
			R.expect(fx:find(s, 1, true) ~= nil).toBe(true, s)
		end
		local tut = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
		R.expect(tut:find("Shared.Weather", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("Weather sky (Atmosphere, Clouds)", function()
	R.it("a storm adds haze and clouds where the place has none; clear weather takes them away", function()
		local env = Loader.boot()
		local W = env.requirePath("ReplicatedStorage.Shared.Weather")
		local Lighting = env.game:GetService("Lighting")
		local terrain = env.workspace:FindFirstChildOfClass("Terrain")
		W.applySky(Lighting, terrain, "OCEAN", "storm")
		local air = Lighting:FindFirstChildOfClass("Atmosphere")
		R.expect(air ~= nil).toBe(true)
		R.expect(air.Haze).toBe(W.look("OCEAN", "storm").atmosphere.Haze)
		if terrain then R.expect(terrain:FindFirstChildOfClass("Clouds") ~= nil).toBe(true) end
		W.applySky(Lighting, terrain, "OCEAN", "clear")
		R.expect(Lighting:FindFirstChildOfClass("Atmosphere")).toBe(nil)
		if terrain then R.expect(terrain:FindFirstChildOfClass("Clouds")).toBe(nil) end
	end)
end)
