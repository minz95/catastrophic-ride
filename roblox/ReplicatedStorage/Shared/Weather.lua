-- Weather.lua
-- Each round's weather (picked with the biome; GameManager sets the
-- ReplicatedStorage attribute "Weather"): night in the forest, a storm at
-- sea, a sunset or a thunderstorm in the sky. A weather changes:
--   lighting  Lighting properties over LightingPresets[biome] (MapManager)
--   water     Terrain water look over TerrainPlan.WATER (OCEAN)
--   hazards   BiomeConfig hazard numbers (HazardManager, via Weather.hazards)
--   fx        what every client draws (StarterPlayerScripts/WeatherFx):
--             rain, lightning flashes, headlights on every car, a lantern
-- Clear weather changes nothing. Harness sessions get "clear" unless the
-- harness asks for one (harness arg `weather`, "random" to draw).

local Weather = {}

Weather.CLEAR = "clear"

-- How often each comes up (weights) per biome.
Weather.CHOICES = {
	FOREST = { clear = 2, night = 1, rain = 1 },
	OCEAN  = { clear = 2, storm = 1, sunset = 1 },
	SKY    = { clear = 2, sunset = 1, storm = 1 },
}

local NIGHT_LIGHT = {
	ClockTime = 0, Brightness = 1.2,
	-- bright enough ambient that the road and items still read at night
	Ambient = Color3.fromRGB(88, 96, 140), OutdoorAmbient = Color3.fromRGB(96, 104, 150),
	FogStart = 60, FogEnd = 520, FogColor = Color3.fromRGB(22, 28, 52),
	ExposureCompensation = 0.35,
}

Weather.LOOK = {
	FOREST = {
		night = {
			name = "Night Forest", emoji = "⭐",
			tip = "Night falls: follow your headlights!",
			lighting = NIGHT_LIGHT,
			atmosphere = { Density = 0.35, Haze = 0, Glare = 0,
				Color = Color3.fromRGB(40, 50, 80), Decay = Color3.fromRGB(20, 25, 45) },
			clouds = { Cover = 0.45, Density = 0.4, Color = Color3.fromRGB(60, 70, 90) },
			fx = { headlights = true, lantern = true },
		},
		rain = {
			name = "Rainy Forest", emoji = "☂",
			tip = "Rain! Logs fall more often.",
			lighting = {
				ClockTime = 17.3, Brightness = 1.0, ExposureCompensation = -0.3,
				Ambient = Color3.fromRGB(80, 92, 88), OutdoorAmbient = Color3.fromRGB(100, 112, 108),
				FogStart = 20, FogEnd = 480, FogColor = Color3.fromRGB(120, 130, 128),
			},
			atmosphere = { Density = 0.45, Haze = 2.5, Glare = 0,
				Color = Color3.fromRGB(150, 160, 160), Decay = Color3.fromRGB(90, 100, 100) },
			clouds = { Cover = 0.9, Density = 0.75, Color = Color3.fromRGB(120, 125, 130) },
			fx = { rain = 1 },
			hazards = { fallingLog = { interval = 6 } },
		},
	},
	OCEAN = {
		storm = {
			name = "Stormy Sea", emoji = "⚡",
			tip = "A storm! Bigger floods and gusts of wind.",
			lighting = {
				ClockTime = 17.2, Brightness = 0.9,
				Ambient = Color3.fromRGB(70, 80, 96), OutdoorAmbient = Color3.fromRGB(84, 96, 114),
				FogStart = 30, FogEnd = 520, FogColor = Color3.fromRGB(78, 90, 104),
				ExposureCompensation = -0.35,
			},
			atmosphere = { Density = 0.5, Haze = 3, Glare = 0,
				Color = Color3.fromRGB(110, 120, 135), Decay = Color3.fromRGB(70, 80, 95) },
			clouds = { Cover = 0.95, Density = 0.9, Color = Color3.fromRGB(80, 85, 95) },
			water = {
				WaterColor = Color3.fromRGB(34, 74, 92), WaterWaveSize = 0.6, WaterWaveSpeed = 26,
				WaterReflectance = 0.35,
			},
			fx = { rain = 1.3, lightning = true },
			hazards = {
				waveFlood = { interval = 8, riseHeight = 4, duration = 5 },
				-- the storm adds gusts at sea (gentler than SKY's)
				extra = { { type = "gustZone", interval = 11, force = 110 } },
			},
		},
		sunset = {
			name = "Sunset Sea", emoji = "🌊",
			tip = "Race into the sunset!",
			lighting = {
				ClockTime = 17.7, Brightness = 2.2,
				Ambient = Color3.fromRGB(120, 90, 80), OutdoorAmbient = Color3.fromRGB(150, 110, 96),
				FogStart = 0, FogEnd = 1100, FogColor = Color3.fromRGB(240, 170, 120),
			},
			atmosphere = { Density = 0.32, Haze = 1.5, Glare = 0.4,
				Color = Color3.fromRGB(240, 170, 130), Decay = Color3.fromRGB(200, 110, 90) },
			water = { WaterColor = Color3.fromRGB(60, 100, 140) },
		},
	},
	SKY = {
		sunset = {
			name = "Sunset Sky", emoji = "☁",
			tip = "Fly into the sunset!",
			lighting = {
				ClockTime = 17.7, Brightness = 1.6,
				Ambient = Color3.fromRGB(130, 104, 112), OutdoorAmbient = Color3.fromRGB(160, 120, 120),
				FogStart = 300, FogEnd = 2400, FogColor = Color3.fromRGB(236, 160, 130),
			},
			atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0.3,
				Color = Color3.fromRGB(236, 165, 135), Decay = Color3.fromRGB(190, 110, 100) },
		},
		storm = {
			name = "Thunder Sky", emoji = "⚡",
			tip = "Thunderstorm! Stronger gusts, more often.",
			lighting = {
				ClockTime = 17.5, Brightness = 0.8,
				Ambient = Color3.fromRGB(86, 90, 110), OutdoorAmbient = Color3.fromRGB(100, 104, 128),
				FogStart = 150, FogEnd = 1400, FogColor = Color3.fromRGB(90, 96, 118),
				ExposureCompensation = -0.4,
			},
			atmosphere = { Density = 0.4, Haze = 2, Glare = 0,
				Color = Color3.fromRGB(120, 125, 145), Decay = Color3.fromRGB(80, 85, 105) },
			clouds = { Cover = 0.85, Density = 0.8, Color = Color3.fromRGB(95, 100, 115) },
			fx = { rain = 1, lightning = true },
			hazards = { gustZone = { interval = 6, force = 180 } },
		},
	},
}

--- The look of `weather` in `biome` (nil for clear or unknown).
function Weather.look(biome, weather)
	local b = Weather.LOOK[biome]
	return b and b[weather] or nil
end

--- Draws a weather for `biome`; `rand()` in [0, 1). Pure.
function Weather.pick(biome, rand)
	local choices = Weather.CHOICES[biome]
	if not choices then return Weather.CLEAR end
	local keys, total = {}, 0
	for k, w in pairs(choices) do table.insert(keys, k); total += w end
	table.sort(keys)   -- pairs order is not fixed
	local r = rand() * total
	for _, k in ipairs(keys) do
		r -= choices[k]
		if r < 0 then return k end
	end
	return keys[#keys]
end

--- Lighting for a round: the biome preset with the weather's changes.
function Weather.lighting(preset, biome, weather)
	local out = table.clone(preset or {})
	local look = Weather.look(biome, weather)
	for k, v in pairs(look and look.lighting or {}) do out[k] = v end
	return out
end

--- The biome's hazards (BiomeConfig list) with the weather's changes, as
-- new tables (BiomeConfig is never changed).
function Weather.hazards(list, biome, weather)
	local look = Weather.look(biome, weather)
	local mods = look and look.hazards or {}
	local out = {}
	for _, hz in ipairs(list or {}) do
		local copy = table.clone(hz)
		for k, v in pairs(mods[hz.type] or {}) do copy[k] = v end
		table.insert(out, copy)
	end
	for _, hz in ipairs(mods.extra or {}) do table.insert(out, table.clone(hz)) end
	return out
end

-- The place's own Atmosphere (Lighting) and Clouds (Terrain) as they were
-- before any weather touched them: clear weather puts these back.
local _orig = {}
local AIR = { "Density", "Haze", "Glare", "Color", "Decay", "Offset" }
local CLOUD = { "Cover", "Density", "Color" }

local function setAll(inst, props, values)
	if not _orig[inst] then
		local o = {}
		for _, p in ipairs(props) do
			local ok, v = pcall(function() return inst[p] end)
			if ok then o[p] = v end
		end
		_orig[inst] = o
	end
	for _, p in ipairs(props) do
		local v = values and values[p]
		if v == nil then v = _orig[inst][p] end
		if v ~= nil then pcall(function() inst[p] = v end) end
	end
end

-- One sky object (Atmosphere / Clouds): the place's own gets the weather's
-- values and its own back on clear weather; when the place has none, the
-- weather adds one (attribute WeatherMade) and takes it away again after.
local function skyPart(parent, class, props, values)
	if not parent then return end
	local inst = parent:FindFirstChildOfClass(class)
	if inst and inst:GetAttribute("WeatherMade") then
		if values then setAll(inst, props, values) else inst:Destroy() end
		return
	end
	if inst then
		setAll(inst, props, values)
	elseif values then
		inst = Instance.new(class)
		inst:SetAttribute("WeatherMade", true)
		for _, p in ipairs(props) do
			if values[p] ~= nil then pcall(function() inst[p] = values[p] end) end
		end
		inst.Parent = parent
	end
end

--- Sets the sky's haze and clouds for a weather (server; MapManager and
-- the promo harness). The skybox ignores fog: without clouds and haze a
-- rainy or stormy round still showed a clear blue sky (Studio promo-weather
-- 2026-11-02). Clear weather leaves the place as it was.
function Weather.applySky(lighting, terrain, biome, weather)
	local look = Weather.look(biome, weather)
	skyPart(lighting, "Atmosphere", AIR, look and look.atmosphere)
	skyPart(terrain, "Clouds", CLOUD, look and look.clouds)
end

--- "⚡ Stormy Sea" or nil for clear weather.
function Weather.title(biome, weather)
	local look = Weather.look(biome, weather)
	return look and (look.emoji .. " " .. look.name) or nil
end

return Weather
