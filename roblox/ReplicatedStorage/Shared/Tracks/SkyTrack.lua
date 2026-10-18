-- SkyTrack.lua
-- Pure data for the SKY race track centerline (XZ, race direction node 1 →
-- last). Read by SkyMapBuilder and by RaceProgress (live ranking and respawn
-- targets). No Roblox types.

local Track = {}

Track.width = 50  -- corridor width (SkyMapBuilder CORRIDOR_W)

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

return Track
