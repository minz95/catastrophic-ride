-- OceanTrack.lua
-- Pure data for the OCEAN race track centerline (XZ, race direction node 1 →
-- last). Read by OceanMapBuilder and by RaceProgress (live ranking and respawn
-- targets). No Roblox types.

local Track = {}

Track.biome = "OCEAN"

Track.width    = 60   -- channel width (OceanMap LANE_W)
Track.trackTop = 2    -- water surface Y (BiomeConfig.OCEAN.waterPlaneY)

-- Height band (above trackTop) a boat hull occupies. Boats ride a suspension
-- raycast, so anything lower than 1.2 studs (the 1-stud start dock) is ridden
-- over, not hit. Used by the offline checks and the kinematic sim.
Track.obstacleBand = { 1.2, 4 }

-- ─── Reef walls ───────────────────────────────────────────────────────────────
-- From the sea floor (-12) to 12 above the water, so no seam shows at the
-- waterline (the water is see-through) and waveFlood never lifts boats over.
Track.wallThickness = 3
Track.wallBaseY     = -12
Track.wallHeight    = 26
-- Doorways (2 × half-width every interval studs); 0 = continuous walls.
Track.wallGapInterval  = 48
Track.wallGapHalfWidth = 0

-- Rough water beside the walls (SlowZone), per side.
Track.slowZoneWidth  = 50
Track.slowZoneHeight = 4

Track.nodes = {
	-- S1 Harbor Launch (~350)
	{   0,  600 }, -- N1  start dock
	{   0,  250 }, -- N2  enter S2

	-- S2 Island Arc east around enlarged palm island (~600)
	{  60,  200 }, -- N3
	{ 140,  100 }, -- N4
	{ 180,    0 }, -- N5  CP1 zone (apex east)
	{ 160, -100 }, -- N6
	{  80, -180 }, -- N7
	{   0, -200 }, -- N8  exit S2

	-- S3 Open Channel (chicane + jump skill-shot) (~520)
	{   0, -300 }, -- N9
	{  40, -400 }, -- N10
	{   0, -500 }, -- N11
	{ -40, -600 }, -- N12
	{   0, -700 }, -- N13

	-- S4 Lighthouse Spiral (2026-10-22, replaces the flat reef U-bend): a
	-- water flume winds UP 1¼ turns (450°, left) around the lighthouse,
	-- centre (110, -800), R = 110, from the sea (Y 2) to Y 40 (4.4%). Each
	-- turn passes 30.4 studs over the one below; the top turn also passes
	-- over the end of S3. A third number on a node is the water surface Y.
	{   0,   -800,  2 },    -- N14 enter the spiral (west), heading south
	{ 14.7,  -855,  4.53 },  -- N15
	{   55, -895.3, 7.07 },  -- N16
	{  110,  -910,  9.6 },  -- N17 south (under the slide's start)
	{  165, -895.3, 12.13 }, -- N18
	{ 205.3, -855, 14.67 },    -- N19
	{  220,  -800, 17.2 },  -- N20 east (drift corner)
	{ 205.3, -745, 19.73 },  -- N21
	{  165, -704.7, 22.27 }, -- N22
	{  110,  -690, 24.8 },  -- N23 north
	{   55, -704.7, 27.33 },   -- N24
	{ 14.7,  -745, 29.87 },  -- N25 over the S3 exit
	{    0,  -800, 32.4 },  -- N26 over the spiral's entry
	{ 14.7,  -855, 34.93 },  -- N27
	{   55, -895.3, 37.47 }, -- N28
	{  110,  -910, 40 },    -- N29 top, heading east
	-- S5 Water Slide: down to the sea again (6.2%), then the lagoon run
	{  300,  -910, 39 },    -- N30 (nearly level: passes 25+ studs over the spiral)
	{  350, -923.4, 35.78 }, -- N31
	{ 386.6, -960, 32.57 },  -- N32
	{  400, -1010, 29.35 }, -- N33 heading south
	{  400, -1450, 2 },     -- N34 splash-down
	{ 386.6, -1500 }, -- N35
	{  350, -1536.6 }, -- N36
	{  300, -1550 }, -- N37 heading west
	{  100, -1550 }, -- N38
	{   50, -1563.4 }, -- N39
	{ 13.4, -1600 }, -- N40
	{ 0, -1650 }, -- N41  S6 begins
	{ 16.1, -1710 }, -- N42
	{ 60, -1753.9 }, -- N43
	{ 120, -1770 }, -- N44  heading east
	{ 370, -1770 }, -- N45  reef hairpin entry
	{ 425, -1784.7 }, -- N46
	{ 465.3, -1825 }, -- N47
	{ 480, -1880 }, -- N48  hairpin apex (drift corner)
	{ 465.3, -1935 }, -- N49
	{ 425, -1975.3 }, -- N50
	{ 370, -1990 }, -- N51  heading west
	{ 190, -1990 }, -- N52  buoy slalom
	{ 151.7, -1982.4 }, -- N53
	{ 119.3, -1960.7 }, -- N54
	{ 74.5, -1934.8 }, -- N55
	{ 22.7, -1934.8 }, -- N56
	{ -22.1, -1960.7 }, -- N57
	{ -54.6, -1982.4 }, -- N58  slalom exit
	-- S7: kelp channel and the final straight
	{ -92.8, -1990 }, -- N59  S6 end
	{ -192.8, -1990 }, -- N60
	{ -252.8, -2006.1 }, -- N61
	{ -296.8, -2050 }, -- N62
	{ -312.8, -2110 }, -- N63  kelp channel, heading north
	{ -312.8, -2330 }, -- N64
	{ -296.8, -2390 }, -- N65
	{ -252.8, -2433.9 }, -- N66
	{ -192.8, -2450 }, -- N67  heading east
	{ 67.2, -2450 }, -- N68
	{ 127.2, -2466.1 }, -- N69
	{ 171.1, -2510 }, -- N70
	{ 187.2, -2570 }, -- N71  onto the final straight
	{ 187.2, -2950 }, -- N72  runoff past the finish (150 studs, end wall; was 70)
}

-- Named sections for reports (inclusive node index ranges).
Track.sections = {
	{ name = "S1 harbor launch",  from = 1,  to = 2 },
	{ name = "S2 island arc",     from = 2,  to = 8 },
	{ name = "S3 open channel",   from = 8,  to = 13 },
	{ name = "S3b to the lighthouse", from = 13, to = 14 },
	{ name = "S4 lighthouse spiral", from = 14, to = 29 },
	{ name = "S5 water slide",    from = 29, to = 41 },
	{ name = "S6 reef hairpin",   from = 41, to = 59 },
	{ name = "S7 kelp channel",   from = 59, to = 72 },
}

-- Finish-line Z. Must match Constants.TRACK.OCEAN.zFinish.
Track.finishZ = -2800
Track.finishX = 187.2   -- on the N58 → N59 final straight

-- Start grid: CraftingManager._buildSpawnGrid (x = (col-3)*7, rows 8 apart
-- from BiomeConfig.OCEAN.raceStartZ = 590).
Track.startGrid = {
	cols = { -14, -7, 0, 7, 14 },
	rows = { 590, 598 },
}

-- ─── Props and triggers (OceanMap reads these) ───────────────────────────────
-- Checkpoints, in order: { x, z }. Gates are turned to face the track.
Track.checkpoints = {
	{ 180,    0 },   -- CP1 at N5, island arc apex
	{ 400, -1150, 20.65 }, -- CP2 on the water slide (N33 → N34)
}

-- Boost pads { x, z }, turned to the track direction.
Track.boostPads = {
	{   0,  500 },   -- S1 launch
	{ 160,    0 },   -- S2 inner apex (rewards the tight line; fully on the lane)
	{   0, -550 },   -- S3 mid-channel
	{  400, -1300 }, -- S5 water slide, before the splash-down
	{ 250, -1770 },  -- S6 east channel, into the hairpin
	{ -60, -2450 },  -- S7 east channel
}

-- Drift corner trigger centres { x, z } (spec §3.3).
Track.driftCorners = {
	{ 180,    0 },   -- S2 island arc apex (N5)
	{ 220, -800, 17.2 }, -- S4 spiral, east side (one layer here; the third number picks it)
	{ 370.7, -1520.7 },  -- S5 lagoon turn (N35/N36)
	{ 480, -1880 },  -- S6 reef hairpin apex (N35)
	{ 0, -1935 },    -- S6 buoy slalom crest (N42/N43)
}

-- Wave ramps / jump zones { x, z }.
Track.jumpRamps = {
	{ 0, -240 },     -- post-S2 wave swell (between N8 and N9)
	{ 0, -500 },     -- mid-S3 skill shot (N11)
	{ -312.8, -2220 }, -- S7 kelp channel swell
	{ 187.2, -2700 },  -- S7 final straight swell
}

-- Trigger sizes: { across the track, height, along the track }.
Track.checkpointSize  = { Track.width + 4, 12, 10 }
Track.boostPadSize    = { 12, 0.4, 8 }
Track.driftCornerSize = { Track.width + 20, 8, 46 }
Track.jumpZoneSize    = { Track.width - 6, 8, 12 }
Track.finishSize      = { Track.width, 10, 6 }

-- ─── Scenery (inside the turns, never on the lane; map_ocean checks) ────────
-- Palm island inside the S2 arc: blocks the straight-line cut to CP1.
Track.palmIsland = { cx = 40, cz = 0, size = { 110, 220 }, palms = 8, seed = 99 }
-- Reef formation inside the S5 water slide's bend (was inside the S4 U-bend).
Track.reef = { cx = 290, cz = -1290, size = { 80, 140 }, spires = 5 }
-- Lighthouse inside the S4 spiral (decoration; inner wall at R 110 - 30 - 1.5).
Track.lighthouse = { x = 110, z = -800, r = 26, height = 110 }
-- Posts under the raised flume (TrackKit:buildSupports).
Track.supports = { spacing = 28, size = 3, minRise = 3, groundY = -12 }
-- Start dock under the grid (boats ride over it: obstacleBand starts at 1.2).
Track.startDock = { z = 595, length = 24 }

-- Farming area (FarmArea model, hidden during RACING).
Track.farm = { cx = 0, cz = 850, size = { 180, 260 }, palms = 8, seed = 7 }

return Track
