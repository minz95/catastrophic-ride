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

	-- S4 Reef U-bend east around reef formation (~900)
	{  40,  -730 }, -- N14
	{ 180,  -730 }, -- N15
	{ 330,  -800 }, -- N16
	{ 380,  -900 }, -- N17  CP2 zone (apex south-east)
	{ 330, -1000 }, -- N18
	{ 180, -1010 }, -- N19
	{  40, -1000 }, -- N20

	-- S5 Return Channel + Finish Lagoon (~720)
	{   0, -1080 }, -- N21
	{  80, -1150 }, -- N22
	{   0, -1220 }, -- N23
	{ -80, -1290 }, -- N24
	{   0, -1360 }, -- N25
	{  80, -1430 }, -- N26
	{   0, -1500 }, -- N27 end of the zigzag
	-- S6 (2026-10-20, races were ~43 s vs the 60-120 s target): reef
	-- hairpin (R=110) and a buoy slalom.
	{ 0, -1650 }, -- N28  S6 begins
	{ 16.1, -1710 }, -- N29
	{ 60, -1753.9 }, -- N30
	{ 120, -1770 }, -- N31  heading east
	{ 370, -1770 }, -- N32  reef hairpin entry
	{ 425, -1784.7 }, -- N33
	{ 465.3, -1825 }, -- N34
	{ 480, -1880 }, -- N35  hairpin apex (drift corner)
	{ 465.3, -1935 }, -- N36
	{ 425, -1975.3 }, -- N37
	{ 370, -1990 }, -- N38  heading west
	{ 190, -1990 }, -- N39  buoy slalom
	{ 151.7, -1982.4 }, -- N40
	{ 119.3, -1960.7 }, -- N41
	{ 74.5, -1934.8 }, -- N42
	{ 22.7, -1934.8 }, -- N43
	{ -22.1, -1960.7 }, -- N44
	{ -54.6, -1982.4 }, -- N45  slalom exit
	-- S7: kelp channel and the final straight
	{ -92.8, -1990 }, -- N46  S6 end
	{ -192.8, -1990 }, -- N47
	{ -252.8, -2006.1 }, -- N48
	{ -296.8, -2050 }, -- N49
	{ -312.8, -2110 }, -- N50  kelp channel, heading north
	{ -312.8, -2330 }, -- N51
	{ -296.8, -2390 }, -- N52
	{ -252.8, -2433.9 }, -- N53
	{ -192.8, -2450 }, -- N54  heading east
	{ 67.2, -2450 }, -- N55
	{ 127.2, -2466.1 }, -- N56
	{ 171.1, -2510 }, -- N57
	{ 187.2, -2570 }, -- N58  onto the final straight
	{ 187.2, -2950 }, -- N59  runoff past the finish (150 studs, end wall; was 70)
}

-- Named sections for reports (inclusive node index ranges).
Track.sections = {
	{ name = "S1 harbor launch",  from = 1,  to = 2 },
	{ name = "S2 island arc",     from = 2,  to = 8 },
	{ name = "S3 open channel",   from = 8,  to = 13 },
	{ name = "S4 reef U-bend",    from = 13, to = 20 },
	{ name = "S5 return channel", from = 20, to = 28 },
	{ name = "S6 reef hairpin",   from = 28, to = 46 },
	{ name = "S7 kelp channel",   from = 46, to = 59 },
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
	{ 380, -900 },   -- CP2 at N17, reef U-bend apex
}

-- Boost pads { x, z }, turned to the track direction.
Track.boostPads = {
	{   0,  500 },   -- S1 launch
	{ 160,    0 },   -- S2 inner apex (rewards the tight line; fully on the lane)
	{   0, -550 },   -- S3 mid-channel
	{   0, -1080 },  -- post-S4 U-bend exit (N21)
	{ 250, -1770 },  -- S6 east channel, into the hairpin
	{ -60, -2450 },  -- S7 east channel
}

-- Drift corner trigger centres { x, z } (spec §3.3).
Track.driftCorners = {
	{ 180,    0 },   -- S2 island arc apex (N5)
	{ 380, -900 },   -- S4 reef U-bend apex (N17)
	{   0, -1220 },  -- S5 return channel mid-zigzag (N23)
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
-- Reef formation inside the S4 U-bend.
Track.reef = { cx = 220, cz = -870, size = { 80, 140 }, spires = 5 }
-- Start dock under the grid (boats ride over it: obstacleBand starts at 1.2).
Track.startDock = { z = 595, length = 24 }

-- Farming area (FarmArea model, hidden during RACING).
Track.farm = { cx = 0, cz = 850, size = { 180, 260 }, palms = 8, seed = 7 }

return Track
