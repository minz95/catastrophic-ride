-- OceanTrack.lua
-- Pure data for the OCEAN race track centerline (XZ, race direction node 1 →
-- last). Read by OceanMapBuilder and by RaceProgress (live ranking and respawn
-- targets). No Roblox types.

local Track = {}

Track.width = 60  -- channel width (OceanMapBuilder LANE_W)

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
	{   0, -1500 }, -- N27 FinishLine sensor at zFinish
	{   0, -1560 }, -- N28 runoff past finish
}

return Track
