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

-- Wall doorways: 8-stud openings every 48 studs of arc length.
ForestTrack.wallGapInterval  = 48
ForestTrack.wallGapHalfWidth = 4

-- Off-corridor slow pads, per side.
ForestTrack.slowZoneWidth  = 40
ForestTrack.slowZoneHeight = 4

-- ─── Centerline (spec §2.1, figure-3 + U-bend) ────────────────────────────────
-- S1 (Starting Straight)         : N1  → N2
-- S2 (Outcrop Hairpin, right 90°): N2  → N8
-- S3 (River Sweeper, left 120°)  : N8  → N15, bridge at N10
-- S4 (Farm U-Bend, 180° around)  : N15 → N23
-- S5 (Mud S-Chicane + finish)    : N23 → N31
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

	-- S3 long left 120° sweeper, bridge at N10
	{ 550,  -120 }, -- N9
	{ 580,  -300 }, -- N10 bridge crosses centerline here
	{ 550,  -480 }, -- N11
	{ 460,  -640 }, -- N12
	{ 310,  -750 }, -- N13
	{ 130,  -820 }, -- N14 CP1 zone
	{ -50,  -830 }, -- N15 end of S3

	-- S4 U-bend around farm island (peak at N19)
	{ -220, -870  }, -- N16
	{ -360, -970  }, -- N17
	{ -450, -1130 }, -- N18
	{ -470, -1310 }, -- N19 U peak (CP2 zone)
	{ -420, -1450 }, -- N20
	{ -280, -1530 }, -- N21
	{ -100, -1530 }, -- N22
	{   50, -1500 }, -- N23 end of S4

	-- S5 S-chicane (right→left), then 230-stud finish straight at X=0
	{  180, -1550 }, -- N24 chicane right curve
	{  130, -1620 }, -- N25 return
	{    0, -1640 }, -- N26 crossover
	{ -100, -1670 }, -- N27 chicane left peak
	{  -30, -1740 }, -- N28 return
	{    0, -1770 }, -- N29 onto finish straight (X=0 from here)
	{    0, -2000 }, -- N30 FinishLine sensor (Constants.TRACK.FOREST.zFinish)
	{    0, -2050 }, -- N31 runoff past finish
}

-- Named sections for reports (inclusive node index ranges).
ForestTrack.sections = {
	{ name = "S1 start straight",  from = 1,  to = 2 },
	{ name = "S2 outcrop hairpin", from = 2,  to = 8 },
	{ name = "S3 river sweeper",   from = 8,  to = 15 },
	{ name = "S4 farm U-bend",     from = 15, to = 23 },
	{ name = "S5 mud chicane",     from = 23, to = 31 },
}

-- Finish-line Z. Must match Constants.TRACK.FOREST.zFinish.
ForestTrack.finishZ = -2000

-- ─── Start grid (matches BiomeConfig.FOREST.raceStartZ = 590) ────────────────
ForestTrack.startGrid = {
	cols = { -14, -7, 0, 7, 14 },
	rows = { 590, 598 },
}

-- ─── Hazards & props ─────────────────────────────────────────────────────────
-- Mud patches in the S-chicane apex sides (rewards apex cutting).
ForestTrack.mudZones = {
	{ 230, -1560 },   -- outer of right chicane peak
	{ -150, -1660 },  -- outer of left chicane peak
	{   0, -1810 },   -- centerline mud just before finish straight (skill check)
	{  50, -1700 },   -- inside chicane
}
ForestTrack.mudZoneSize = { 20, 0.4, 16 }

-- One landmark rock pile per hairpin apex, intended to sit OUTSIDE the corridor.
ForestTrack.rockPiles = {
	{ 110, -10 },      -- S2 outcrop (outer of right hairpin)
	{ 620, -300 },     -- S3 outer bend at river mouth
	{ -540, -1310 },   -- S4 U peak outer
	{ 230, -1570 },    -- S5 chicane outer
	{ -30,  100 },     -- S2 inner (left of corridor)
}

-- Jump ramps: { x, z, yaw (radians) }. Floor-only wedges.
ForestTrack.jumpRamps = {
	{  490, -550, math.rad(35) },   -- mid-S3 over creek tributary
	{    0, -1850, math.rad(0)  },  -- pre-finish straight (after chicane)
}
ForestTrack.jumpRampSize = { ForestTrack.width - 4, 4, 14 }

ForestTrack.boostPads = {
	{   0,  400 },    -- S1 launch
	{ 560, -380 },    -- S3 mid-sweep (rewards apex)
	{ -380, -1500 },  -- S4 U exit
	{   0, -1920 },   -- S5 onto finish straight
}
ForestTrack.boostPadSize = { 10, 0.3, 8 }

-- Drift corner trigger centres (spec §2.3). Trigger boxes are axis-aligned.
ForestTrack.driftCorners = {
	{  60,   30 },   -- S2 outcrop apex
	{ 580, -300 },   -- S3 river bridge entry
	{ -470, -1310 }, -- S4 U peak
	{ 180, -1550 },  -- S5 chicane entry
}
ForestTrack.driftCornerSize = { ForestTrack.width, 5, 40 }

-- Checkpoints, in order. Trigger boxes are axis-aligned: { x, z }.
ForestTrack.checkpoints = {
	{ 130, -820 },   -- CP1 at N14, inside S3 sweeper apex
	{ -470, -1310 }, -- CP2 at N19, inside U-bend peak
}
ForestTrack.checkpointSize = { ForestTrack.width, 12, 6 }

-- River crossing S3 (decorative water under the corridor).
ForestTrack.river = { z = -300, bridgeX = 580 }

-- Farming area behind the start grid.
ForestTrack.farm = { cx = 0, cz = 850 }

return ForestTrack
