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
	{   0, -1590 }, -- N28 runoff; FinishLine at finishZ on this straight
}

-- Named sections for reports (inclusive node index ranges).
Track.sections = {
	{ name = "S1 harbor launch",  from = 1,  to = 2 },
	{ name = "S2 island arc",     from = 2,  to = 8 },
	{ name = "S3 open channel",   from = 8,  to = 13 },
	{ name = "S4 reef U-bend",    from = 13, to = 20 },
	{ name = "S5 return channel", from = 20, to = 28 },
}

-- Finish-line Z. Must match Constants.TRACK.OCEAN.zFinish.
-- On the straight after the last zigzag corner (N27), not on the corner
-- itself: there the finish poles stood inside the diagonal approach lane.
Track.finishZ = -1530

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
}

-- Drift corner trigger centres { x, z } (spec §3.3).
Track.driftCorners = {
	{ 180,    0 },   -- S2 island arc apex (N5)
	{ 380, -900 },   -- S4 reef U-bend apex (N17)
	{   0, -1220 },  -- S5 return channel mid-zigzag (N23)
}

-- Wave ramps / jump zones { x, z }.
Track.jumpRamps = {
	{ 0, -240 },     -- post-S2 wave swell (between N8 and N9)
	{ 0, -500 },     -- mid-S3 skill shot (N11)
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
