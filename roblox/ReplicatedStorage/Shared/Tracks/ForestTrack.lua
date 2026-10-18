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

-- ─── Centerline (spec §2.1, figure-3 + U-bend) ────────────────────────────────
-- S1 (Starting Straight)         : N1  → N2
-- S2 (Outcrop Hairpin, right 90°): N2  → N8
-- S3 (River Sweeper, left 120°)  : N8  → N15, bridge at N10
-- S4 (Farm U-Bend, 180° around)  : N15 → N23
-- S5 (Mud U-turn hook + finish)  : N23 → N36
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

	-- S5 (redesigned): left U-turn (R=55, 30° steps) then a right-hander
	-- (R=60) onto the finish straight. The old N24 (−105°) and N27 (+118°)
	-- single-node kinks let walls cut across the lane and trapped cars.
	{  150, -1520 }, -- N24  S5 entry, heading east
	{ 177.5, -1527.4 }, -- N25
	{ 197.6, -1547.5 }, -- N26
	{ 205, -1575 }, -- N27  U-turn apex (drift corner)
	{ 197.6, -1602.5 }, -- N28
	{ 177.5, -1622.6 }, -- N29
	{ 150, -1630 }, -- N30  heading west
	{   60, -1630 }, -- N31  start of the right-hander onto the finish straight
	{ 30, -1638 }, -- N32
	{ 8, -1660 }, -- N33
	{ 0, -1690 }, -- N34  onto the finish straight (X=0 from here)
	{    0, -2000 }, -- N35 FinishLine sensor (Constants.TRACK.FOREST.zFinish)
	{    0, -2050 }, -- N36 runoff past finish
}

-- Named sections for reports (inclusive node index ranges).
ForestTrack.sections = {
	{ name = "S1 start straight",  from = 1,  to = 2 },
	{ name = "S2 outcrop hairpin", from = 2,  to = 8 },
	{ name = "S3 river sweeper",   from = 8,  to = 15 },
	{ name = "S4 farm U-bend",     from = 15, to = 23 },
	{ name = "S5 mud hook",        from = 23, to = 36 },
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
	{ 217, -1575 },   -- outer half of the U-turn apex (rewards the inside line)
	{   9, -1639 },   -- outer half of the right-hander
	{   0, -1810 },   -- centerline mud on the finish straight (skill check)
	{  26, -1656 },   -- inner half of the right-hander
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
	{  505, -560, math.atan2(90, 160) },  -- mid-S3: middle of the N11 → N12 straight
	{    0, -1850, 0 },                   -- finish straight
}
ForestTrack.jumpRampSize = { ForestTrack.width - 4, 4, 14 }

ForestTrack.boostPads = {
	{   0,  400 },    -- S1 launch
	{ 560, -380 },    -- S3 mid-sweep (rewards apex)
	{ -368, -1480 },  -- S4 U exit (on the N20 → N21 centerline; was 24 studs off, behind the wall)
	{   0, -1920 },   -- S5 onto finish straight
}
ForestTrack.boostPadSize = { 10, 0.3, 8 }

-- Drift corner trigger centres (spec §2.3). Trigger boxes are axis-aligned.
ForestTrack.driftCorners = {
	{  60,   30 },   -- S2 outcrop apex
	{ 580, -300 },   -- S3 river bridge entry
	{ -470, -1310 }, -- S4 U peak
	{ 205, -1575 },  -- S5 U-turn apex
}
ForestTrack.driftCornerSize = { ForestTrack.width, 5, 40 }  -- { across, height, along the track }
ForestTrack.jumpZoneSize = { ForestTrack.width, 10, 14 }

-- Checkpoints, in order. Trigger boxes are axis-aligned: { x, z }.
ForestTrack.checkpoints = {
	{ 130, -820 },   -- CP1 at N14, inside S3 sweeper apex
	{ -470, -1310 }, -- CP2 at N19, inside U-bend peak
}
ForestTrack.checkpointSize = { ForestTrack.width + 4, 12, 10 }  -- { across, height, depth }
ForestTrack.finishSize = { ForestTrack.width, 10, 6 }

-- River crossing S3 (decorative water under the corridor).
ForestTrack.river = { z = -300, bridgeX = 580 }

-- Tree scatter zones { xMin, xMax, zMin, zMax, count }. Trees closer than
-- width / 2 + 10 to the centerline are rejected, so zones may overlap the track.
ForestTrack.treeZones = {
	{ -550, -100,   100,   700, 30 },  -- left of S1 / farm
	{  100,  550,   100,   700, 30 },  -- right of S1 / farm
	{ -550,    0,  -700,     0, 35 },  -- inside the S2/S3 sweeper (left)
	{  650, 1100,  -500,   100, 25 },  -- outside the S3 sweep
	{ -800, -550, -1700,  -700, 35 },  -- outside the U-bend, west
	{  100,  700, -1700,  -700, 30 },  -- inside the U-bend, east
	{ -500,  500, -2200, -1700, 30 },  -- around the finish approach
}

-- Farming area behind the start grid.
ForestTrack.farm = { cx = 0, cz = 850 }

return ForestTrack
