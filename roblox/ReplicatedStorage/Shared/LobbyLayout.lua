-- LobbyLayout.lua
-- The lobby hub (2026-11-17: "walk around the lobby, chat, see the hall of
-- fame, shop, like a Roblox room"): a round plaza floating far from every
-- track and farm, where players wait between rounds. Plain positions here;
-- Modules/Maps/LobbyHub builds it, LobbyManager fills it and puts players
-- on it. Y up, the spawn on the south (+Z) side looking north.
--
--   north   🏆 hall of fame stage (the vote winner's ride, life size)
--   centre  a bathtub fountain; the "next race" board (an old TV) north-east of it
--   west    🚗 Legend Rides on pedestals (buy in the shop)
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

-- Legend Rides: an arc on the west side, every pedestal facing the centre
LobbyLayout.LEGEND_SLOTS = 6
LobbyLayout.LEGEND_SCALE = 0.75
function LobbyLayout.legendSpot(i)
	local a = math.rad(150 + (i - 1) * 12)   -- angle from +X: 150° (south-west) … 210° (north-west)
	return O + V(math.cos(a) * 52, 0, math.sin(a) * 52)
end

-- the trophy room: a mirror arc on the east side
LobbyLayout.TROPHY_SLOTS = 9
function LobbyLayout.trophySpot(i)
	local a = math.rad(-48 + (i - 1) * 8)    -- -48° (north-east) … 16° (east, a little south)
	return O + V(math.cos(a) * 54, 0, math.sin(a) * 54)
end

LobbyLayout.SHOP = O + V(-26, 0, 34)
LobbyLayout.SHOWCASE = { O + V(20, 0, 44), O + V(32, 0, 37), O + V(42, 0, 27) }

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
