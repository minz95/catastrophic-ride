-- ForestTrack.lua
-- Pure data for the FOREST race track. No Roblox types, so the same table is
-- read by the map builder (Studio), the race simulators and the offline
-- geometry checks (Lune, see tests/).
--
-- Coordinates are world studs on the XZ plane. Race direction is node 1 → last.
-- Edit THIS file to change the track layout, then run the checks:
--   lune run tests/run.luau        (pass/fail)
--   lune run tools/track_report.luau FOREST   (SVG + JSON report)

local ForestTrack = {}

ForestTrack.biome = "FOREST"

-- ─── Corridor ─────────────────────────────────────────────────────────────────
ForestTrack.width     = 40     -- corridor width (spec §2 table)
ForestTrack.wallHeight = 8     -- wall height (cars hop ramps and clear 5)
ForestTrack.trackTop  = 1.0    -- Y of track surface (Part top)
ForestTrack.wallThickness = 2
ForestTrack.wallBaseY = 0      -- walls stand on the ground (top of Ground = 0)

-- Wall doorways: 2 × wallGapHalfWidth-stud openings every wallGapInterval
-- studs of track length. 0 = continuous walls (current design: the 8-stud
-- doorways read as broken walls in playtests).
ForestTrack.wallGapInterval  = 48
ForestTrack.wallGapHalfWidth = 0

-- Off-corridor slow pads, per side.
ForestTrack.slowZoneWidth  = 40
ForestTrack.slowZoneHeight = 4

-- ─── Centerline ───────────────────────────────────────────────────────────────
-- S1 start straight, S2 outcrop corner, S3 trestle climb (river bridge at
-- N11), S4 giant tree spiral (down 1½ turns), S4b run-out, S5 mud hook,
-- S6 pine switchbacks, S7 ridge chicane + final straight. Sections below.
ForestTrack.nodes = {
	-- S1
	{   0,   600 }, -- N1  start grid line
	{   0,   200 }, -- N2  end of S1 / S2 entry

	-- S2 outcrop corner: left onto the east straight. 2026-10-29: every
	-- corner that is not on a raised road is R = 35 (was 60-120), turning
	-- round the same vertex as before (the straights did not move). A drift
	-- there slides long enough for a mini-turbo; the old wide arcs were taken
	-- flat out and drifting gained nothing (tools/drift_sim.luau).
	{   0,   100 }, -- N3  approach
	{   0,    55 }, -- N4  corner (R=35, vertex 0, 20)
	{ 4.7,  37.5 }, -- N5
	{ 17.5, 24.7 }, -- N6  apex (drift corner)
	{  35,    20 }, -- N7  heading east
	{ 300,    20 }, -- N8  departure straight
	{ 450,     0 }, -- N9  end of S2

	-- S3 long left 120° sweeper, climbing on a wooden trestle from the
	-- ground (Y 1) to the treetops (Y 44, ~3.7% grade); bridge over the
	-- river at N11. A third number on a node is the road surface Y there.
	{ 550,  -120,  6.31 }, -- N10
	{ 580,  -300, 12.52 }, -- N11 river bridge
	{ 550,  -480, 18.73 }, -- N12
	{ 460,  -640, 24.97 }, -- N13
	{ 310,  -750, 31.3 }, -- N14
	{ 130,  -820, 37.87 }, -- N15 CP1 zone
	{ -50,  -830, 44 },    -- N16 end of S3, top of the climb
	{ -150, -830, 44 },    -- N17 flat crest, over the spiral's lower turn

	-- S4 Giant Tree Spiral (2026-10-22, replaces the flat farm U-bend): 1½
	-- turns (540°, left) around the giant tree, centre (-150, -920), R = 90,
	-- going down 43 studs (5.1% grade). Each turn passes 28.7 studs above the
	-- one below it. Nodes every 30°.
	{ -195,   -842.1, 41.61 }, -- N18
	{ -227.9, -875,   39.22 }, -- N19
	{ -240,   -920,   36.83 },  -- N20 west
	{ -227.9, -965,   34.44 }, -- N21
	{ -195,   -997.9, 32.06 }, -- N22
	{ -150,  -1010,   29.67 },    -- N23 south (over the exit)
	{ -105,   -997.9, 27.28 }, -- N24
	{ -72.1,  -965,   24.89 }, -- N25
	{ -60,    -920,   22.5 },  -- N26 east (drift corner)
	{ -72.1,  -875,   20.11 }, -- N27
	{ -105,   -842.1, 17.72 }, -- N28
	{ -150,   -830,   15.33 },    -- N29 north (under the crest)
	{ -195,   -842.1, 12.94 }, -- N30
	{ -227.9, -875,    10.56 }, -- N31
	{ -240,   -920,    8.17 },  -- N32
	{ -227.9, -965,    5.78 }, -- N33
	{ -195,   -997.9,  3.39 }, -- N34
	{ -150,  -1010,    1 },    -- N35 bottom, heading east (ground again)
	-- S4b back to S5: right-angle turn south (R=35), a straight south,
	-- right-angle turn east (R=35)
	{    5,  -1010 },   -- N36 corner (vertex 40, -1010)
	{ 22.5,  -1014.7 }, -- N37 apex (drift corner)
	{ 35.3,  -1027.5 }, -- N38
	{   40,  -1045 },   -- N39 heading south
	{   40,  -1485 },   -- N40 corner (vertex 40, -1520)
	{ 44.7,  -1502.5 }, -- N41
	{ 57.5,  -1515.3 }, -- N42
	{   75,  -1520 },   -- N43 heading east

	-- S5: left U-turn as two right angles (R=35) with a short straight
	-- between (drift into both), then a right angle onto the S6 straight.
	-- (Before 2026-10-29 one R=55 half circle, taken flat out.)
	{  150, -1520 },    -- N44 S5 entry, heading east
	{  170, -1520 },    -- N45 corner (vertex 205, -1520)
	{ 187.5, -1524.7 }, -- N46
	{ 200.3, -1537.5 }, -- N47
	{  205, -1555 },    -- N48 heading south
	{  205, -1595 },    -- N49 corner (vertex 205, -1630)
	{ 200.3, -1612.5 }, -- N50
	{ 187.5, -1625.3 }, -- N51
	{  170, -1630 },    -- N52 heading west
	{   35, -1630 },    -- N53 corner (vertex 0, -1630)
	{ 17.5, -1634.7 },  -- N54 apex (drift corner)
	{  4.7, -1647.5 },  -- N55
	{    0, -1665 },    -- N56 onto the old finish straight (X=0 from here)
	-- S6 pine switchbacks (2026-10-20, races were ~47 s vs the 60-120 s
	-- target): long straights joined by hairpins of two right angles. 2026-10-29:
	-- corners R=35 (were R=25: a 39-stud arc, under the 0.6 s a drift needs
	-- for a mini-turbo), hairpins 80 / 140 studs further in (S6 was 2000
	-- studs of mostly straight).
	{    0, -1960 },    -- N57 end of the old finish-straight mud + ramp; S6 begins
	{    0, -2005 },    -- N58 corner (vertex 0, -2040)
	{ -4.7, -2022.5 },  -- N59
	{ -17.5, -2035.3 }, -- N60
	{  -35, -2040 },    -- N61 heading west
	{ -295, -2040 },    -- N62 hairpin 1, corner 1 (vertex -330, -2040)
	{ -312.5, -2044.7 }, -- N63
	{ -325.3, -2057.5 }, -- N64
	{ -330, -2075 },    -- N65 heading south
	{ -330, -2145 },    -- N66 hairpin 1, corner 2 (vertex -330, -2180)
	{ -325.3, -2162.5 }, -- N67
	{ -312.5, -2175.3 }, -- N68
	{ -295, -2180 },    -- N69 heading east
	{  115, -2180 },    -- N70 hairpin 2, corner 3 (vertex 150, -2180)
	{ 132.5, -2184.7 }, -- N71
	{ 145.3, -2197.5 }, -- N72
	{  150, -2215 },    -- N73 heading south
	{  150, -2285 },    -- N74 hairpin 2, corner 4 (vertex 150, -2320)
	{ 145.3, -2302.5 }, -- N75
	{ 132.5, -2315.3 }, -- N76
	{  115, -2320 },    -- N77 heading west
	{ -255, -2320 },    -- N78 corner (vertex -290, -2320)
	{ -272.5, -2324.7 }, -- N79 apex (drift corner)
	{ -285.3, -2337.5 }, -- N80
	{ -290, -2355 },    -- N81 S6 end, heading -Z again
	-- S7: corner east, the ridge chicane (2026-10-29: an 80-stud dip with
	-- four R=35 right angles, was a gentle 33-stud wiggle) and the final
	-- straight
	{ -290, -2695 },    -- N82 corner (vertex -290, -2730)
	{ -285.3, -2712.5 }, -- N83
	{ -272.5, -2725.3 }, -- N84
	{ -255, -2730 },    -- N85 heading east
	{ 25, -2730 },      -- N86 ridge chicane, down (vertex 60, -2730)
	{ 42.5, -2734.7 },  -- N87
	{ 55.3, -2747.5 },  -- N88
	{ 60, -2765 },      -- N89 heading south
	{ 60, -2775 },      -- N90 (vertex 60, -2810)
	{ 64.7, -2792.5 },  -- N91
	{ 77.5, -2805.3 },  -- N92
	{ 95, -2810 },      -- N93 heading east, chicane floor
	{ 175, -2810 },     -- N94 back up (vertex 210, -2810)
	{ 192.5, -2805.3 }, -- N95
	{ 205.3, -2792.5 }, -- N96
	{ 210, -2775 },     -- N97 heading north
	{ 210, -2765 },     -- N98 (vertex 210, -2730)
	{ 214.7, -2747.5 }, -- N99
	{ 227.5, -2734.7 }, -- N100
	{ 245, -2730 },     -- N101 chicane exit, heading east
	{ 414.7, -2730 },   -- N102 corner onto the final straight (vertex 449.7, -2730)
	{ 432.2, -2734.7 }, -- N103 apex (drift corner)
	{  445, -2747.5 },  -- N104
	{ 449.7, -2765 },   -- N105 onto the final straight
	{ 449.7, -3200 },   -- N106 runoff past the finish (150 studs, end wall; was 50)
}

-- Named sections for reports (inclusive node index ranges).
ForestTrack.sections = {
	{ name = "S1 start straight",   from = 1,  to = 2 },
	{ name = "S2 outcrop corner",   from = 2,  to = 9 },
	{ name = "S3 trestle climb",    from = 9,  to = 17 },
	{ name = "S4 giant tree spiral", from = 17, to = 35 },
	{ name = "S4b tree run-out",    from = 35, to = 43 },
	{ name = "S5 mud hook",         from = 43, to = 57 },
	{ name = "S6 pine switchbacks", from = 57, to = 81 },
	{ name = "S7 ridge chicane",    from = 81, to = 106 },
}

-- Finish-line Z. Must match Constants.TRACK.FOREST.zFinish.
ForestTrack.finishZ = -3050
ForestTrack.finishX = 449.7   -- on the N105 → N106 final straight

-- ─── Start grid (matches BiomeConfig.FOREST.raceStartZ = 590) ────────────────
ForestTrack.startGrid = {
	cols = { -14, -7, 0, 7, 14 },
	rows = { 590, 598 },
}

-- ─── Hazards & props ─────────────────────────────────────────────────────────
-- Mud patches in the S-chicane apex sides (rewards apex cutting).
ForestTrack.mudZones = {
	{ 217, -1575 },   -- outer half of the U-turn apex (rewards the inside line)
	{   9, -1639 },   -- outer half of the right-hander
	{   0, -1810 },   -- centerline mud on the finish straight (skill check)
	{  21, -1651 },   -- inner half of the right-hander
	{  -60, -2310 },  -- S6 west straight, left half ...
	{ -160, -2330 },  -- ... then right half: weave or slow down
	{  135, -2802 },  -- S7 chicane floor, north half
}
ForestTrack.mudZoneSize = { 20, 0.4, 16 }

-- One landmark rock pile per hairpin apex, intended to sit OUTSIDE the corridor.
ForestTrack.rockPiles = {
	{ 110, -10 },      -- S2 outcrop (outer of right hairpin)
	{ 620, -300 },     -- S3 outer bend at river mouth
	{ -540, -1310 },   -- S4 U peak outer
	{ 245, -1575 },    -- S5 U-turn outer
	{ -30,  100 },     -- S2 inner (left of corridor)
}

-- Jump ramps: { x, z, yaw (radians) }. Floor-only wedges, centred on the
-- lane; yaw uses TrackGeometry:yawAt so the slope faces the direction of travel.
ForestTrack.jumpRamps = {
	{   40, -1260, 0 },                   -- S4b straight after the spiral (was mid-S3, now a raised trestle)
	{    0, -1850, 0 },                   -- old finish straight (now mid-race)
	{ -100, -2180, -math.pi / 2 },        -- S6 east straight, between the hairpins
	{ 449.7, -2950, 0 },                  -- S7 final straight
}
-- Full corridor width: a narrower wedge left a 4-stud vertical side face at
-- each edge that a car driving near the wall snagged on (Studio bots-forest
-- 2026-10-24: a novice bot stuck twice at the S6 ramp, 20 s lost).
ForestTrack.jumpRampSize = { ForestTrack.width, 4, 14 }

-- Gap jumps: the road is cut for `length` studs centred on { x, z } (on a
-- straight, raised stretch: falling in means a respawn), with a spring pad
-- (`padLength` studs) right before the lip. The pad launches at `vy`
-- studs/s up and holds at least `minSpeed` forward in the air, so any car
-- that drives over it clears the gap (VehicleController, Constants.DRIVE.
-- JUMP). A respawn near it goes back before the pad (RaceProgress).
ForestTrack.gapJumps = {
	{ x = 385, z = -695, length = 24, padLength = 12, vy = 26, minSpeed = 60 },   -- S3 climb, N12 → N13 (~28 up)
}

ForestTrack.boostPads = {
	{   0,  400 },    -- S1 launch
	{ 560, -380 },    -- S3 mid-sweep (rewards apex)
	{   40, -1180 },  -- S4b straight out of the spiral
	{   0, -1920 },   -- S5 end of the old finish straight
	{  100, -2180 },  -- S6 east straight, after the ramp
	{  449.7, -2880 }, -- S7 final straight
}
ForestTrack.boostPadSize = { 10, 0.3, 8 }

-- Drift corner trigger centres (spec §2.3). Trigger boxes are axis-aligned.
-- One per corner worth a drift (an orange strip on the road; each fills
-- the boost gauge by Constants.DRIFT_CHARGE_PER_CORNER).
ForestTrack.driftCorners = {
	{ 10.3, 30.3 },  -- S2 outcrop corner apex
	{ 580, -300 },   -- S3 river bridge entry
	{ -60, -920, 22.5 }, -- S4 spiral, east side (one layer only here; the third number picks it)
	{ 29.7, -1020.3 }, -- S4b first corner apex
	{ 205, -1575 },  -- S5 U-turn, between its two corners
	{ 10.3, -1640.3 }, -- S5 corner onto the old finish straight
	{ -330, -2110 }, -- S6 hairpin 1, between its corners
	{ 150, -2250 },  -- S6 hairpin 2, between its corners
	{ -279.7, -2330.3 }, -- S6 exit corner apex
	{ 135, -2810 },  -- S7 chicane floor
	{ 439.4, -2740.3 }, -- S7 corner onto the final straight
}
ForestTrack.driftCornerSize = { ForestTrack.width, 5, 40 }  -- { across, height, along the track }
ForestTrack.jumpZoneSize = { ForestTrack.width, 10, 14 }

-- Checkpoints, in order. Trigger boxes are axis-aligned: { x, z }.
ForestTrack.checkpoints = {
	{ 130, -820 },   -- CP1 at N14, inside S3 sweeper apex
	{   40, -1340 }, -- CP2 on the S4b straight, after the spiral
}
ForestTrack.checkpointSize = { ForestTrack.width + 4, 12, 10 }  -- { across, height, depth }
ForestTrack.finishSize = { ForestTrack.width, 10, 6 }

-- River crossing S3 (decorative water under the corridor).
ForestTrack.river = { z = -300, bridgeX = 580 }

-- The giant tree the S4 spiral winds around (decoration, inside the inner
-- wall: R 90 - 20 lane - 2 wall leaves room for a trunk of radius 38).
ForestTrack.giantTree = { x = -150, z = -920, r = 38, height = 120 }

-- Trestle posts under a raised road: every `spacing` studs along both wall
-- lines, from the ground to the road. Never inside a lane below.
ForestTrack.trestle = { spacing = 24, size = 2.4, minRise = 3 }

-- Tree scatter zones { xMin, xMax, zMin, zMax, count }. Trees closer than
-- width / 2 + 10 to the centerline are rejected, so zones may overlap the track.
ForestTrack.treeZones = {
	{ -550, -100,   100,   700, 30 },  -- left of S1 / farm
	{  100,  550,   100,   700, 30 },  -- right of S1 / farm
	{ -550,    0,  -700,     0, 35 },  -- inside the S2/S3 sweeper (left)
	{  650, 1100,  -500,   100, 25 },  -- outside the S3 sweep
	{ -800, -550, -1700,  -700, 35 },  -- outside the U-bend, west
	{  100,  700, -1700,  -700, 30 },  -- inside the U-bend, east
	{ -500,  500, -2200, -1700, 30 },  -- around the old finish approach
	{ -600,  650, -2800, -2000, 50 },  -- S6 switchbacks (inside the hairpins too)
	{  -50,  700, -3200, -2750, 25 },  -- S7 final straight
}

-- Farming area behind the start grid.
ForestTrack.farm = { cx = 0, cz = 850 }

return ForestTrack
