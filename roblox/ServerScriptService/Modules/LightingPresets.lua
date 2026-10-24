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
	},
	OCEAN = {
		Ambient          = Color3.fromRGB(60, 90, 130),
		OutdoorAmbient   = Color3.fromRGB(80, 130, 180),
		Brightness       = 3.0,
		ClockTime        = 14,
		FogStart         = 0,
		FogEnd           = 1200,
		FogColor         = Color3.fromRGB(160, 200, 230),
	},
	SKY = {
		-- clear daytime blue (the old purple haze read as dusk, not sky)
		Ambient          = Color3.fromRGB(110, 125, 150),
		OutdoorAmbient   = Color3.fromRGB(150, 170, 200),
		Brightness       = 2.2,
		ClockTime        = 13,
		FogStart         = 300,
		FogEnd           = 2400,
		FogColor         = Color3.fromRGB(185, 212, 245),
	},
}
