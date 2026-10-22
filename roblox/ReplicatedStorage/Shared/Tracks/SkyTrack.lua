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
-- Air barrier: touching see-through pillars (wallThickness square) from
-- wallYLo to wallYHi, with a cloud rail (decoration) at flyer height; no
-- doorways (a flyer that slips out falls to the kill plane). wallBaseY /
-- wallHeight size the start apron's walls. Invisible ceiling above.
Track.wallThickness    = 2
Track.wallYLo          = 54
Track.wallYHi          = 114
Track.wallBaseY        = Track.wallYLo
Track.wallHeight       = Track.wallYHi - Track.wallYLo
Track.wallRailY        = 0      -- rail from trackTop + wallRailY ...
Track.wallRailHeight   = 3      -- ... this tall (decoration; the pillars collide)
Track.wallGapInterval  = 1000
Track.wallGapHalfWidth = 0
Track.ceilingY         = 120
Track.slowZoneWidth    = 0      -- no off-track slow zones in the sky

Track.nodes = {
	-- S1 Launch Tunnel (Z 1500 → 1360, then a left bend west)
	{    0, 1500 }, -- N1  start of corridor
	{    0, 1360 }, -- N2
	{ -110, 1280 }, -- N3
	-- S2 Cloud Bend A: 270° of a circle around (-440, 830), R = 440,
	-- north → west → south. Open on the east side, so the lane never
	-- crosses itself (it used to be a full 360° loop that met its own entry:
	-- a fork in the road, and a gap in the fence where a flyer slipped out).
	{ -440, 1270 }, -- N4  north apex (drift corner)
	{ -751, 1141 }, -- N5
	{ -880,  830 }, -- N6  CP1 (western extent)
	{ -751,  519 }, -- N7
	{ -440,  390 }, -- N8  south apex (boost pad)
	-- S3 Crossover (east, into bend B)
	{ -100,  400 }, -- N9
	-- S4 Cloud Bend B: 225° around (440, 330), R = 440, north-west → north →
	-- east → south (clockwise); open on the south-west side.
	{  129,  641 }, -- N10
	{  440,  770 }, -- N11 north apex (boost pad)
	{  751,  641 }, -- N12
	{  880,  330 }, -- N13 CP2 (eastern extent)
	{  751,   19 }, -- N14
	{  440, -110 }, -- N15 south apex (drift corner)
	-- S5 Crystal Canyon (zigzag Z -60 → -1040)
	{  120,  -60 }, -- N16
	{  -80, -200 }, -- N17
	{   80, -380 }, -- N18
	{  -80, -560 }, -- N19
	{   80, -740 }, -- N20
	{  -80, -900 }, -- N21
	{    0,-1040 }, -- N22 end S5
	-- S6 Final Descent (straight Z -1040 → -2000)
	{    0,-1400 }, -- N23
	{    0,-1700 }, -- N24
	{    0,-2000 }, -- N25 FinishLine
	{    0,-2220 }, -- N26 runoff past the finish (220 studs: flyers are fast; end wall)
}

-- Named sections for reports (inclusive node index ranges).
Track.sections = {
	{ name = "S1 launch tunnel",   from = 1,  to = 4 },
	{ name = "S2 cloud bend A",    from = 4,  to = 8 },
	{ name = "S3 crossover",       from = 8,  to = 10 },
	{ name = "S4 cloud bend B",    from = 10, to = 15 },
	{ name = "S5 crystal canyon",  from = 15, to = 22 },
	{ name = "S6 final descent",   from = 22, to = 26 },
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
	{ -880, 830 },   -- CP1 at N6, bend A western extent
	{  880, 330 },   -- CP2 at N13, bend B eastern extent
}

-- Boost pads { x, z }, turned to the track direction (spec §4.3).
Track.boostPads = {
	{    0,  1430 },  -- S1 launch
	{ -440,   390 },  -- N8 bend A south apex (rewards tight line)
	{ -270,   395 },  -- S3 crossover
	{  440,   770 },  -- N11 bend B north apex
	{    0, -1400 },  -- S6 mid descent
}

-- Drift corner centres { x, z } (spec §4.3: loop apexes + canyon entry).
Track.driftCorners = {
	{ -440, 1270 },   -- N4 bend A north apex
	{  440, -110 },   -- N15 bend B south apex
	{  -80, -200 },   -- N17 canyon zigzag entry
}

-- Jump zones { x, z } (S5 XZ boost dressed as ramps).
Track.jumpRamps = {
	{  80, -380 },    -- N18 S5 entry
	{ -80, -560 },    -- N19 S5 mid
	{  80, -740 },    -- N20 S5 late
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
	{ -440,   830 },   -- inside bend A
	{  440,   330 },   -- inside bend B
	{    0, -1200 },   -- mid descent recovery
}

-- Decorative crystal clusters { x, z } (spec §4.7), all off the corridor.
Track.crystalSeeds = {
	{  90, 1430 }, { -90, 1430 }, {  90, 1200 }, { 160, 1000 },            -- S1
	{ -990,  830 }, { -829, 1219 }, { -829,  441 }, { -440, 1380 }, { -440,  280 },  -- bend A
	{  990,  330 }, {  829,  719 }, {  829,  -59 }, {  440,  880 }, {  440, -220 },  -- bend B
	{ -170,  -60 }, {  170, -260 }, { -170, -420 }, {  170, -620 },        -- S5 canyon
	{ -170, -820 }, {  170, -960 },
	{  90, -1500 }, { -90, -1500 }, {  90, -1800 }, { -90, -1800 },        -- S6 descent
}

-- Farming area (FarmArea model, hidden during RACING).
Track.farm = { cx = 0, cz = 1850, size = { 200, 240 } }

return Track
