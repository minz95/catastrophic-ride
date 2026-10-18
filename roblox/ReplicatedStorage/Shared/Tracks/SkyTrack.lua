-- SkyTrack.lua
-- Pure data for the SKY race track centerline (XZ, race direction node 1 →
-- last). Read by SkyMapBuilder and by RaceProgress (live ranking and respawn
-- targets). No Roblox types.

local Track = {}

Track.biome = "SKY"

Track.width    = 50   -- corridor width (SkyMap CORRIDOR_W)
Track.trackTop = 80   -- floor top surface Y (SkyMap SKY_BASE_Y)

-- Height band (above trackTop) a flyer occupies. Flyers hold the spawn
-- altitude (BiomeConfig.SKY.raceStartY = 84), so the body sits ~82..88.
Track.obstacleBand = { 2, 8 }

-- ─── Edge fence ──────────────────────────────────────────────────────────────
-- Crystal pillars (wallThickness × wallThickness) packed edge to edge from
-- wallYLo to wallYHi; no doorways (a flyer that slips out falls to the kill
-- plane). Invisible ceiling above.
Track.wallThickness    = 2
Track.wallYLo          = 54
Track.wallYHi          = 114
Track.wallGapInterval  = 1000
Track.wallGapHalfWidth = 0
Track.ceilingY         = 120
Track.slowZoneWidth    = 0      -- no off-track slow zones in the sky

Track.nodes = {
	-- S1 Launch Tunnel (~700, Z 1500 → 800, straight)
	{   0, 1500 }, -- N1  start of corridor
	{   0, 1200 }, -- N2
	{   0,  950 }, -- N3
	{   0,  800 }, -- N4  entry to Loop A

	-- S2 Cloud Loop A (CW, ~1840, around center (-300, 800), R=300)
	{ -88,  588 }, -- N5
	{-300,  500 }, -- N6
	{-512,  588 }, -- N7
	{-600,  800 }, -- N8  CP1 (western extent — unreachable on straight-line path)
	{-512, 1012 }, -- N9
	{-300, 1100 }, -- N10 (Loop A apex / drift corner)
	{ -88, 1012 }, -- N11
	{   0,  800 }, -- N12 loop close (returns to N4 position)

	-- S3 Crossover Plaza (~400, Z 800 → 400, straight)
	{   0,  600 }, -- N13
	{   0,  400 }, -- N14 entry to Loop B

	-- S4 Cloud Loop B (CCW, ~1840, around center (300, 400), R=300)
	{  88,  188 }, -- N15
	{ 300,  100 }, -- N16 (Loop B apex / drift corner)
	{ 512,  188 }, -- N17
	{ 600,  400 }, -- N18 CP2 (eastern extent)
	{ 512,  612 }, -- N19
	{ 300,  700 }, -- N20
	{  88,  612 }, -- N21
	{   0,  400 }, -- N22 loop close

	-- S5 Crystal Canyon (~1800, zigzag Z 400 → -1000)
	{ -80,  220 }, -- N23
	{  80,   40 }, -- N24
	{ -80, -140 }, -- N25
	{  80, -320 }, -- N26
	{ -80, -500 }, -- N27
	{  80, -680 }, -- N28
	{ -80, -860 }, -- N29
	{   0,-1000 }, -- N30 end S5

	-- S6 Final Descent (~1000, straight Z -1000 → -2000)
	{   0,-1400 }, -- N31
	{   0,-1700 }, -- N32
	{   0,-2000 }, -- N33 FinishLine
}

-- Named sections for reports (inclusive node index ranges).
Track.sections = {
	{ name = "S1 launch tunnel",  from = 1,  to = 4 },
	{ name = "S2 cloud loop A",   from = 4,  to = 12 },
	{ name = "S3 crossover plaza", from = 12, to = 14 },
	{ name = "S4 cloud loop B",   from = 14, to = 22 },
	{ name = "S5 crystal canyon", from = 22, to = 30 },
	{ name = "S6 final descent",  from = 30, to = 33 },
}

-- Finish-line Z. Must match Constants.TRACK.SKY.zFinish.
Track.finishZ = -2000

-- Start grid: CraftingManager._buildSpawnGrid (x = (col-3)*7, rows 8 apart
-- from BiomeConfig.SKY.raceStartZ = 1490).
Track.startGrid = {
	cols = { -14, -7, 0, 7, 14 },
	rows = { 1490, 1498 },
}

-- ─── Props and triggers (SkyMap reads these) ─────────────────────────────────
-- Checkpoints, in order: { x, z }. Gates are turned to face the track.
Track.checkpoints = {
	{ -600, 800 },   -- CP1 at N8, Loop A western extent
	{  600, 400 },   -- CP2 at N18, Loop B eastern extent
}

-- Boost pads { x, z }, turned to the track direction (spec §4.3).
Track.boostPads = {
	{    0,  1300 },  -- S1 launch
	{ -300,   500 },  -- N6 Loop A south apex (rewards tight line)
	{    0,   600 },  -- S3 plaza
	{  300,   700 },  -- N20 Loop B north apex
	{    0, -1400 },  -- S6 mid descent
}

-- Drift corner centres { x, z } (spec §4.3: loop apexes + canyon entry).
Track.driftCorners = {
	{ -300, 1100 },   -- N10 Loop A north apex
	{  300,  100 },   -- N16 Loop B south apex
	{  -80, -140 },   -- N25 canyon zigzag mid-entry
}

-- Jump zones { x, z } (S5 XZ boost dressed as ramps).
Track.jumpRamps = {
	{  80,   40 },    -- N24 S5 entry
	{ -80, -500 },    -- N27 S5 mid
	{  80, -680 },    -- N28 S5 late
}

-- Trigger sizes: { across the track, height, along the track }.
Track.checkpointSize  = { Track.width + 4, 50, 10 }
Track.boostPadSize    = { 12, 0.4, 8 }
Track.driftCornerSize = { Track.width, 32, 50 }
Track.jumpZoneSize    = { Track.width - 6, 8, 12 }
Track.finishSize      = { Track.width, 12, 6 }

-- ─── Scenery (outside the fence; map_sky checks) ─────────────────────────────
-- Updraft hazard zones { x, z }: loop centres (off the lane) and one on the
-- final descent.
Track.updraftZones = {
	{ -300,   800 },   -- inside Loop A
	{  300,   400 },   -- inside Loop B
	{    0, -1200 },   -- mid descent recovery
}

-- Decorative crystal clusters { x, z } (spec §4.7), all off the corridor.
Track.crystalSeeds = {
	{  90, 1380 }, { -90, 1380 }, {  90, 1080 }, { -90, 1080 },            -- S1
	{ -700,  800 }, { -680,  500 }, { -680, 1100 }, { -560, 1240 }, { -560,  360 },  -- Loop A
	{  700,  400 }, {  680,  100 }, {  680,  700 }, {  560,  840 }, {  560,  -40 },  -- Loop B
	{ -160,  100 }, {  160, -100 }, { -160, -340 }, {  160, -560 },        -- S5 canyon
	{ -160, -800 }, {  160, -940 },
	{  90, -1500 }, { -90, -1500 }, {  90, -1800 }, { -90, -1800 },        -- S6 descent
}

-- Farming area (FarmArea model, hidden during RACING).
Track.farm = { cx = 0, cz = 1850, size = { 200, 240 } }

return Track
