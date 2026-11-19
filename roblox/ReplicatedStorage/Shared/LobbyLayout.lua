-- LobbyLayout.lua
-- The lobby hub (2026-11-17: "walk around the lobby, chat, see the hall of
-- fame, shop, like a Roblox room"): a round plaza floating far from every
-- track and farm, where players wait between rounds. Plain positions here;
-- Modules/Maps/LobbyHub builds it, LobbyManager fills it and puts players
-- on it. Y up, the spawn on the south (+Z) side looking north.
--
--   north   🏆 hall of fame stage (the vote winner's ride, life size)
--   centre  a bathtub fountain; the "next race" board (an old TV) north-east of it
--   west    🚗 Legend Rides on pedestals (buy in the shop), split by the
--           gate to Auto Street: the road out west, Junk Motors (new cars)
--           on its north side
--   east    the trophy room: every achievement's reward on a pedestal
--   south   spawn; 🛒 shop booth (left) and the junk ride show (right)
--   round   a fence, and the town's houses and trees on the grass beyond it

local LobbyLayout = {}

local V = Vector3.new

LobbyLayout.ORIGIN = V(2600, 200, 0)   -- the plaza's floor top, centre (tracks: |x| < 900)
LobbyLayout.RADIUS = 78                -- the floor
LobbyLayout.WALL_RADIUS = 76           -- invisible wall keeping players on it
LobbyLayout.WALL_HEIGHT = 14

local O = LobbyLayout.ORIGIN

LobbyLayout.SPAWN = O + V(0, 0, 54)
LobbyLayout.BOARD = O + V(20, 0, -20)                -- an old TV turned to the spawn
LobbyLayout.FOUNTAIN = O + V(0, 0, 4)
LobbyLayout.ARCH = O + V(0, 0, 40)                   -- "WELCOME TO JUNK TOWN", walked through from the spawn
LobbyLayout.STAGE = { at = O + V(0, 0, -50), radius = 15, height = 2.5 }
LobbyLayout.WINNER_LENGTH = 22   -- studs: the vote winner's ride and rider on the stage, any ride (2× read as a toy)

-- Legend Rides: an arc on the west side, every pedestal facing the centre,
-- three either side of the way to the Auto Street gate (180°)
LobbyLayout.LEGEND_SLOTS = 6
LobbyLayout.LEGEND_SCALE = 0.75
local LEGEND_ANGLES = { 150, 160, 170, 190, 200, 210 }
function LobbyLayout.legendSpot(i)
	local a = math.rad(LEGEND_ANGLES[i])     -- angle from +X: 150° (south-west) … 210° (north-west)
	return O + V(math.cos(a) * 60, 0, math.sin(a) * 60)
end

-- the trophy room: a mirror arc on the east side
LobbyLayout.TROPHY_SLOTS = 9
function LobbyLayout.trophySpot(i)
	local a = math.rad(-48 + (i - 1) * 8)    -- -48° (north-east) … 16° (east, a little south)
	return O + V(math.cos(a) * 54, 0, math.sin(a) * 54)
end

LobbyLayout.SHOP = O + V(-26, 0, 34)
LobbyLayout.SHOWCASE = { O + V(20, 0, 44), O + V(32, 0, 37), O + V(42, 0, 27) }
-- the hub's "coming soon" pads (Shared/Departure.SOON), east of the start pads
LobbyLayout.SOON = { O + V(44, 0, 6), O + V(42, 0, -8) }

-- the town round the plaza: houses on the grass outside the fence (angle from
-- +X, degrees; `model` a Shared/LobbyModels key, `height` in studs), clear of
-- the stage backdrop (270°), the garage (180°) and the teapot (~350°).
-- `kind` is the part-built look used where the model is missing.
LobbyLayout.ISLAND_RADIUS = 112
LobbyLayout.HOUSE_RADIUS = 94
LobbyLayout.HOUSES = {
	{ model = "house_garden",   angle = 22,  height = 20, kind = "box" },
	{ model = "house_mushroom", angle = 50,  height = 18, kind = "can" },
	{ model = "house_small",    angle = 75,  height = 14, kind = "boot" },
	{ model = "house_big",      angle = 108, height = 18, kind = "box" },
	{ model = "house_mushroom", angle = 133, height = 18, kind = "can" },
	{ model = "house_small",    angle = 155, height = 14, kind = "boot" },
	{ model = "house_small",    angle = 207, height = 14, kind = "box" },
	{ model = "house_garden",   angle = 232, height = 20, kind = "can" },
	{ model = "house_big",      angle = 296, height = 18, kind = "boot" },
	{ model = "house_mushroom", angle = 320, height = 18, kind = "box" },
}
-- trees between the houses, outside the fence
LobbyLayout.OUTER_TREES = { 36, 63, 92, 121, 144, 220, 252, 284, 308, 333, 6 }
LobbyLayout.OUTER_TREE_RADIUS = 88
LobbyLayout.FENCE_RADIUS = 74.5   -- the fence models, just inside the invisible wall
LobbyLayout.LAMPS = 8          -- fork street lamps round the plaza, bunting between them
LobbyLayout.LAMP_RADIUS = 34
LobbyLayout.TREES = { O + V(-6, 0, 26), O + V(14, 0, 18), O + V(-36, 0, -30), O + V(30, 0, -44),
	O + V(-30, 0, 6), O + V(-20, 0, -40) }
-- benches round the fountain, facing it (east, west, north)
LobbyLayout.BENCHES = { O + V(15, 0, 4), O + V(-15, 0, 4), O + V(0, 0, -10) }
LobbyLayout.STALL = O + V(-38, 0, 52)          -- a snack stall by Sticky Sam
LobbyLayout.JUNK_PILE = O + V(-38, 0, -50)
LobbyLayout.SCRAP_CARS = { O + V(50, 0, 38), O + V(-20, 0, 60) }

-- ── Auto Street (2026-11-18) ────────────────────────────────────────────────
-- Out of the west gate (the fence open at 180°) a lane leads past the
-- island's edge onto a wide lot: the road runs west, Junk Motors' glass
-- showroom stands on its north side (new cars, Shared/NewCars), Junk Auto
-- Mart's used cars (the vote winners' Legend Rides) on its south side. Rectangles are { x0, x1, z0, z1 } offsets from
-- ORIGIN (x0 < x1, z0 < z1); invisible walls close everything but the gate.
LobbyLayout.GATE_ANGLE = 180
LobbyLayout.GATE_HALF = 7            -- studs: half the gap in the fence
LobbyLayout.STREET = {
	lane = { -116, -74, -12, 12 },   -- gate to the lot, between the houses
	lot = { -300, -114, -74, 64 },   -- the ground round the road and the showroom
	road = { -300, -74, -9, 9 },     -- the road itself (the lane is its first stretch)
	wallHeight = 14,
	-- the Junk GP grandstand (Shared/GpLayout.GRANDSTAND) and the walk behind
	-- it, through the gap in the lot's west wall at the road's end: anyone may
	-- watch; the track itself only through the gate's desk with a car
	stand = { -331, -300, -172, 182 },
	standGap = { -9, 9 },            -- z of the way through the west wall
}
LobbyLayout.SHOWROOM = {
	box = { -272, -128, -62, -20 },  -- walls; the glass front faces the road (z1)
	height = 16,
	doors = { -150, -250 },          -- x of the two doorways in the glass front
	doorWidth = 10,
	-- the cars: columns east (cheap, by the door) to west, three rows
	rows = { -30, -41, -52 },        -- z of each row's middle
	firstX = -140, stepX = -11, columns = 12,
	plinth = Vector3.new(8, 0.6, 5),
}

--- Where showroom car `i` stands (1 … columns × rows; column-major from
-- the east end, front row first): the plinth's centre on the floor.
function LobbyLayout.carSpot(i)
	local S = LobbyLayout.SHOWROOM
	local col = (i - 1) // #S.rows
	local row = (i - 1) % #S.rows + 1
	return O + V(S.firstX + col * S.stepX, 0, S.rows[row])
end
LobbyLayout.CAR_SLOTS = LobbyLayout.SHOWROOM.columns * #LobbyLayout.SHOWROOM.rows

-- Junk Auto Mart, the used-car lot on the road's south side (2026-11-18,
-- after Korean used-car markets: cars packed nose-out in rows, a price on
-- the roof, an inspection card at the front, dealers' container offices,
-- a parking tower with more upstairs, a directory kiosk at the entrance).
-- It sells the vote winners' Legend Rides; the newest stands first, by
-- the entrance ("JUST IN").
LobbyLayout.USED_LOT = {
	box = { -296, -118, 16, 62 },    -- the gravel lot (z0 on the road side)
	entranceX = -128,                -- the arch over the way in from the road
	rows = { 24, 34 },               -- back to back: the first faces the road (north), the second the offices
	firstX = -140, stepX = -8, columns = 12,
	offices = { -152, -184, -216 },  -- x of the dealers' container offices (z = officeZ), 4 columns each
	officeZ = 52,
	tower = { box = { -294, -262, 22, 58 }, deck = 9,     -- upstairs: a deck 9 studs up
		rows = { 30, 44 }, columns = { -270, -280, -290 },   -- the first row faces north, the second south
		ramp = { x0 = -262, x1 = -232, z0 = 52, z1 = 58 } }, -- up from the east (x1, ground) to the deck (x0)
}

--- Where used car `i` stands: its floor spot and whether its nose points
-- north (-Z). 1 … columns × 2 outdoors (column-major from the entrance,
-- the road-side row first), then the tower deck.
function LobbyLayout.usedSpot(i)
	local U = LobbyLayout.USED_LOT
	local outdoor = U.columns * #U.rows
	if i <= outdoor then
		local col = (i - 1) // #U.rows
		local row = (i - 1) % #U.rows + 1
		return O + V(U.firstX + col * U.stepX, 0, U.rows[row]), row == 1
	end
	local T = U.tower
	local k = i - outdoor - 1
	local col = k // #T.rows
	local row = k % #T.rows + 1
	return O + V(T.columns[col + 1], T.deck, T.rows[row]), row == 1
end
LobbyLayout.USED_SLOTS = LobbyLayout.USED_LOT.columns * #LobbyLayout.USED_LOT.rows
	+ #LobbyLayout.USED_LOT.tower.columns * #LobbyLayout.USED_LOT.tower.rows

local function inRect(r, dx, dz)
	return dx >= r[1] and dx <= r[2] and dz >= r[3] and dz <= r[4]
end
LobbyLayout.inRect = inRect

--- True when `pos` is on Auto Street (the lane, the lot, the showroom or the
-- Junk GP grandstand).
function LobbyLayout.onStreet(pos)
	local dx, dz = pos.X - O.X, pos.Z - O.Z
	local S = LobbyLayout.STREET
	return (inRect(S.lane, dx, dz) or inRect(S.lot, dx, dz) or inRect(S.stand, dx, dz))
		and pos.Y > O.Y - 6 and pos.Y < O.Y + 40
end

--- True anywhere a player may walk in Junk Town: the plaza or Auto Street.
function LobbyLayout.inTown(pos)
	return LobbyLayout.onPlaza(pos) or LobbyLayout.onStreet(pos)
end

--- Turned to look at the plaza's centre from `at` (Y kept).
function LobbyLayout.facingCentre(at)
	local c = V(O.X, at.Y, O.Z)
	if (c - at).Magnitude < 1e-3 then return CFrame.new(at) end
	return CFrame.lookAt(at, c)
end

--- True when `pos` is on the plaza (inside the wall, near the floor).
function LobbyLayout.onPlaza(pos)
	local d = V(pos.X - O.X, 0, pos.Z - O.Z).Magnitude
	return d <= LobbyLayout.WALL_RADIUS and pos.Y > O.Y - 6 and pos.Y < O.Y + 40
end

return LobbyLayout
