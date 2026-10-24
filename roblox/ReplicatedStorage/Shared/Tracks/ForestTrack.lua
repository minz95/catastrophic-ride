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
-- S1 start straight, S2 outcrop hairpin, S3 trestle climb (river bridge at
-- N10), S4 giant tree spiral (down 1½ turns), S4b run-out, S5 mud hook,
-- S6 pine switchbacks, S7 ridge chicane + final straight. Sections below.
ForestTrack.nodes = {
	-- S1
	{   0,   600 }, -- N1  start grid line
	{   0,   200 }, -- N2  end of S1 / S2 entry

	-- S2 right 90° around rock outcrop
	{   0,   100 }, -- N3  approach
	{  20,    60 }, -- N4  arc enter
	{  60,    30 }, -- N5  arc apex (outcrop sits at +X side, decor only)
	{ 120,    20 }, -- N6  arc exit
	{ 300,    20 }, -- N7  departure straight
	{ 450,     0 }, -- N8  end of S2

	-- S3 long left 120° sweeper, climbing on a wooden trestle from the
	-- ground (Y 1) to the treetops (Y 44, ~3.7% grade); bridge over the
	-- river at N10. A third number on a node is the road surface Y there.
	{ 550,  -120,  6.31 }, -- N9
	{ 580,  -300, 12.52 }, -- N10 river bridge
	{ 550,  -480, 18.73 }, -- N11
	{ 460,  -640, 24.97 }, -- N12
	{ 310,  -750, 31.3 }, -- N13
	{ 130,  -820, 37.87 }, -- N14 CP1 zone
	{ -50,  -830, 44 },    -- N15 end of S3, top of the climb
	{ -150, -830, 44 },    -- N16 flat crest, over the spiral's lower turn

	-- S4 Giant Tree Spiral (2026-10-22, replaces the flat farm U-bend): 1½
	-- turns (540°, left) around the giant tree, centre (-150, -920), R = 90,
	-- going down 43 studs (5.1% grade). Each turn passes 28.7 studs above the
	-- one below it. Nodes every 30°.
	{ -195,   -842.1, 41.61 }, -- N17
	{ -227.9, -875,   39.22 }, -- N18
	{ -240,   -920,   36.83 },  -- N19 west
	{ -227.9, -965,   34.44 }, -- N20
	{ -195,   -997.9, 32.06 }, -- N21
	{ -150,  -1010,   29.67 },    -- N22 south (over the exit)
	{ -105,   -997.9, 27.28 }, -- N23
	{ -72.1,  -965,   24.89 }, -- N24
	{ -60,    -920,   22.5 },  -- N25 east (drift corner)
	{ -72.1,  -875,   20.11 }, -- N26
	{ -105,   -842.1, 17.72 }, -- N27
	{ -150,   -830,   15.33 },    -- N28 north (under the crest)
	{ -195,   -842.1, 12.94 }, -- N29
	{ -227.9, -875,    10.56 }, -- N30
	{ -240,   -920,    8.17 },  -- N31
	{ -227.9, -965,    5.78 }, -- N32
	{ -195,   -997.9,  3.39 }, -- N33
	{ -150,  -1010,    1 },    -- N34 bottom, heading east (ground again)
	-- S4b back to S5: right turn (R=70), a straight south, left turn (R=80)
	{  -30,  -1010 }, -- N35
	{    5,  -1019.4 }, -- N36
	{ 30.6,  -1045 }, -- N37
	{   40,  -1080 }, -- N38 heading south
	{   40,  -1440 }, -- N39
	{ 50.7,  -1480 }, -- N40
	{   80,  -1509.3 }, -- N41
	{  120,  -1520 }, -- N42 heading east

	-- S5 (redesigned): left U-turn (R=55, 30° steps) then a right-hander
	-- (R=60) onto the finish straight. The old N24 (−105°) and N27 (+118°)
	-- single-node kinks let walls cut across the lane and trapped cars.
	{  150, -1520 }, -- N43  S5 entry, heading east
	{ 177.5, -1527.4 }, -- N44
	{ 197.6, -1547.5 }, -- N45
	{ 205, -1575 }, -- N46  U-turn apex (drift corner)
	{ 197.6, -1602.5 }, -- N47
	{ 177.5, -1622.6 }, -- N48
	{ 150, -1630 }, -- N49  heading west
	{   60, -1630 }, -- N50  start of the right-hander onto the finish straight
	{ 30, -1638 }, -- N51
	{ 8, -1660 }, -- N52
	{ 0, -1690 }, -- N53  onto the finish straight (X=0 from here)
	-- S6 (2026-10-20, races were ~47 s vs the 60-120 s target): pine
	-- switchbacks joined by long straights. 2026-10-22: each hairpin is two
	-- tight 90° corners (R=25) with a short straight between them (the old
	-- R=70 half circles were taken at full speed). With grip a car must
	-- brake to ~50 studs/s there; a drift carries ~66 (Constants.DRIVE).
	{ 0, -1960 }, -- N54  end of the finish-straight mud + ramp; S6 begins
	{ -10.7, -2000 }, -- N55
	{ -40, -2029.3 }, -- N56
	{ -80, -2040 }, -- N57  heading west
	{ -340, -2040 }, -- N58  hairpin 1 entry
	{ -385, -2040 }, -- N59  corner 1 (R=25)
	{ -397.5, -2043.35 }, -- N60
	{ -406.65, -2052.5 }, -- N61
	{ -410, -2065 }, -- N62  heading south
	{ -410, -2110 }, -- N63  hairpin 1 apex (drift corner)
	{ -410, -2155 }, -- N64  corner 2 (R=25)
	{ -406.65, -2167.5 }, -- N65
	{ -397.5, -2176.65 }, -- N66
	{ -385, -2180 }, -- N67  heading east
	{ 220, -2180 }, -- N68  hairpin 2 entry
	{ 265, -2180 }, -- N69  corner 3 (R=25)
	{ 277.5, -2183.35 }, -- N70
	{ 286.65, -2192.5 }, -- N71
	{ 290, -2205 }, -- N72  heading south
	{ 290, -2250 }, -- N73  hairpin 2 apex (drift corner)
	{ 290, -2295 }, -- N74  corner 4 (R=25)
	{ 286.65, -2307.5 }, -- N75
	{ 277.5, -2316.65 }, -- N76
	{ 265, -2320 }, -- N77  heading west
	{ -200, -2320 }, -- N78
	{ -245, -2332.1 }, -- N79
	{ -277.9, -2365 }, -- N80
	{ -290, -2410 }, -- N81  S6 end, heading -Z again
	-- S7: ridge chicane and the final straight
	{ -290, -2610 }, -- N82
	{ -273.9, -2670 }, -- N83
	{ -230, -2713.9 }, -- N84
	{ -170, -2730 }, -- N85  heading east
	{ 50, -2730 }, -- N86  ridge chicane
	{ 73, -2734.6 }, -- N87
	{ 92.4, -2747.6 }, -- N88
	{ 119.3, -2763.1 }, -- N89
	{ 150.4, -2763.1 }, -- N90
	{ 177.3, -2747.6 }, -- N91
	{ 196.7, -2734.6 }, -- N92
	{ 219.7, -2730 }, -- N93  chicane exit
	{ 339.7, -2730 }, -- N94
	{ 394.7, -2744.7 }, -- N95
	{ 435, -2785 }, -- N96
	{ 449.7, -2840 }, -- N97  onto the final straight
	{ 449.7, -3200 }, -- N98  runoff past the finish (150 studs, end wall; was 50)
}

-- Named sections for reports (inclusive node index ranges).
ForestTrack.sections = {
	{ name = "S1 start straight",   from = 1,  to = 2 },
	{ name = "S2 outcrop hairpin",  from = 2,  to = 8 },
	{ name = "S3 trestle climb",    from = 8,  to = 16 },
	{ name = "S4 giant tree spiral", from = 16, to = 34 },
	{ name = "S4b tree run-out",    from = 34, to = 42 },
	{ name = "S5 mud hook",         from = 42, to = 54 },
	{ name = "S6 pine switchbacks", from = 54, to = 81 },
	{ name = "S7 ridge chicane",    from = 81, to = 98 },
}

-- Finish-line Z. Must match Constants.TRACK.FOREST.zFinish.
ForestTrack.finishZ = -3050
ForestTrack.finishX = 449.7   -- on the N72 → N73 final straight

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
	{  26, -1656 },   -- inner half of the right-hander
	{  -60, -2310 },  -- S6 west straight, left half ...
	{ -160, -2330 },  -- ... then right half: weave or slow down
	{  135, -2772 },  -- S7 chicane crest, outer half
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
ForestTrack.driftCorners = {
	{  60,   30 },   -- S2 outcrop apex
	{ 580, -300 },   -- S3 river bridge entry
	{ -60, -920, 22.5 }, -- S4 spiral, east side (one layer only here; the third number picks it)
	{ 205, -1575 },  -- S5 U-turn apex
	{ -410, -2110 }, -- S6 hairpin 1 apex
	{ 290, -2250 },  -- S6 hairpin 2 apex
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
