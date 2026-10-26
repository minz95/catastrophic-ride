-- LightingPresets.lua
-- Race lighting per biome (MapManager applies it when a map loads; the
-- Studio promo pictures use the same).

return {
	FOREST = {
		Ambient          = Color3.fromRGB(80, 100, 60),
		OutdoorAmbient   = Color3.fromRGB(100, 130, 80),
		Brightness       = 2.5,
		ClockTime        = 12,
		FogStart         = 0,
		FogEnd           = 800,
		FogColor         = Color3.fromRGB(180, 200, 150),
		ExposureCompensation = 0,
	},
	OCEAN = {
		Ambient          = Color3.fromRGB(60, 90, 130),
		OutdoorAmbient   = Color3.fromRGB(80, 130, 180),
		Brightness       = 3.0,
		ClockTime        = 14,
		FogStart         = 0,
		FogEnd           = 1200,
		FogColor         = Color3.fromRGB(160, 200, 230),
		ExposureCompensation = 0,
	},
	SKY = {
		-- clear daytime blue (the old purple haze read as dusk, not sky).
		-- Kept a step darker than the others: white clouds, a pale road and a
		-- pale haze filled half the screen with near-white (glaring).
		Ambient          = Color3.fromRGB(98, 118, 152),
		OutdoorAmbient   = Color3.fromRGB(118, 145, 185),
		Brightness       = 1.7,
		ClockTime        = 13,
		FogStart         = 400,
		FogEnd           = 2600,
		FogColor         = Color3.fromRGB(128, 174, 238),
		ExposureCompensation = -0.2,
	},
}
