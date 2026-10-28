-- FarmBounds.lua
-- The FARMING area of each biome as data: where its walls stand, where its
-- floor is, where items may land and where people (players and FarmBots) are
-- put. The map builders (Maps/*Map), FarmingManager (item spawns, drops),
-- CharacterManager (spawn markers), FarmBots and FarmRescue all read it, so
-- the farm, its walls and its items can never disagree again.
--
-- History (playtest 2026-10-29): "the farm could be smaller and nobody should
-- fall off". The farms were 220×320 (FOREST), 180×260 (OCEAN) and 200×240
-- (SKY); the SKY platform had no rail (walk off the edge: gone), the OCEAN
-- island ended in the sea (no way back up its side) and FOREST's fence did
-- not collide. Items were spread over the FarmArea model's bounding box
-- (its decoration included) with a fixed ground Y per biome in an old,
-- stale table (farm centres at Z 350–390; the farms are at 850 / 1850).
-- Now each farm is about two thirds of that span, closed by invisible walls
-- WALL_HEIGHT tall, and FarmRescue puts back anyone who still ends up off it.

local FarmBounds = {}

FarmBounds.WALL_HEIGHT = 40    -- studs over the floor (a jump is ~7, a punch knock-up 14 studs/s)
FarmBounds.WALL_THICK  = 4
FarmBounds.ITEM_MARGIN = 8     -- items land at least this far inside the walls
FarmBounds.SPAWN_LIFT  = 3     -- a person is put this far over a spawn marker
-- FarmRescue: off the farm =
FarmBounds.FALL_BELOW  = 10    -- this far under the floor
FarmBounds.FLUNG_ABOVE = 30    -- this far over it (no jump or knock goes that high)
FarmBounds.OUT_MARGIN  = 4     -- this far past a wall
FarmBounds.CHECK_EVERY = 0.5   -- s between two rescue checks
FarmBounds.GRACE       = 1.5   -- s after FARMING starts (CharacterManager teleports first)
FarmBounds.BOT_GAP     = 5     -- studs between a bot's spawn spot and anyone else

local TRACKS = { FOREST = "ForestTrack", OCEAN = "OceanTrack", SKY = "SkyTrack" }

-- half = wall to wall / 2 (X, Z); floorY = what people stand on;
-- itemHalf = where items land (on the floor, clear of the walls);
-- keepOut = solid scenery items must not land in ({ x0, x1, z0, z1 }
-- relative to the centre); spawn = marker grid (X offsets, Z offsets).
local SPEC = {
	-- was 220 × 320 (FarmGround), items over 160 × 288
	FOREST = { half = { 75, 105 }, floorY = 1, itemHalf = { 66, 96 },
		keepOut = { { -73, -44, 68, 92 } },                  -- the barn (BarnWall + roof)
		spawn = { { -52, -26, 0, 26, 52 }, { -40, 30 } } },
	-- was a 180 × 260 island (grass 160 × 230); the walls stand on the beach
	OCEAN  = { half = { 60, 85 }, floorY = 5, itemHalf = { 46, 66 }, grass = { 50, 70 },
		keepOut = {},
		spawn = { { -36, -18, 0, 18, 36 }, { -35, 35 } } },
	-- was a 200 × 240 platform with no rail
	SKY    = { half = { 65, 80 }, floorY = 80, itemHalf = { 57, 72 },
		keepOut = {},
		spawn = { { -48, -24, 0, 24, 48 }, { -35, 35 } } },
}

local _cache = {}

--- The farm of `biome`: { cx, cz, halfX, halfZ, floorY, itemHalfX, itemHalfZ,
-- keepOut, grassHalfX, grassHalfZ }. Unknown biomes get FOREST's.
function FarmBounds.get(biome)
	biome = SPEC[biome] and biome or "FOREST"
	if _cache[biome] then return _cache[biome] end
	local spec = SPEC[biome]
	local tracks = script.Parent:FindFirstChild("Tracks")
	local mod = tracks and tracks:FindFirstChild(TRACKS[biome])
	local farm = mod and require(mod).farm or { cx = 0, cz = 850 }
	local b = {
		biome = biome, cx = farm.cx, cz = farm.cz,
		halfX = spec.half[1], halfZ = spec.half[2], floorY = spec.floorY,
		itemHalfX = spec.itemHalf[1], itemHalfZ = spec.itemHalf[2],
		grassHalfX = spec.grass and spec.grass[1], grassHalfZ = spec.grass and spec.grass[2],
		keepOut = spec.keepOut, spawnCols = spec.spawn[1], spawnRows = spec.spawn[2],
	}
	_cache[biome] = b
	return b
end

--- Spawn marker positions (Vector3, on the floor + 0.5) of `biome`'s farm.
function FarmBounds.spawnPoints(biome)
	local b = FarmBounds.get(biome)
	local out = {}
	for _, oz in ipairs(b.spawnRows) do
		for _, ox in ipairs(b.spawnCols) do
			table.insert(out, Vector3.new(b.cx + ox, b.floorY + 0.5, b.cz + oz))
		end
	end
	return out
end

--- The four wall boxes: { { size = Vector3, position = Vector3 }, ... }.
-- They overlap at the corners (no gap), from 2 under the floor to WALL_HEIGHT.
function FarmBounds.walls(biome)
	local b = FarmBounds.get(biome)
	local t, h = FarmBounds.WALL_THICK, FarmBounds.WALL_HEIGHT + 2
	local y = b.floorY - 2 + h / 2
	local lenX, lenZ = 2 * b.halfX + 2 * t, 2 * b.halfZ + 2 * t
	return {
		{ name = "FarmWall_N", size = Vector3.new(lenX, h, t), position = Vector3.new(b.cx, y, b.cz - b.halfZ - t / 2) },
		{ name = "FarmWall_S", size = Vector3.new(lenX, h, t), position = Vector3.new(b.cx, y, b.cz + b.halfZ + t / 2) },
		{ name = "FarmWall_W", size = Vector3.new(t, h, lenZ), position = Vector3.new(b.cx - b.halfX - t / 2, y, b.cz) },
		{ name = "FarmWall_E", size = Vector3.new(t, h, lenZ), position = Vector3.new(b.cx + b.halfX + t / 2, y, b.cz) },
	}
end

--- Can an item land at (x, z)? Inside the item area and clear of keepOut.
function FarmBounds.itemSpotOk(biome, x, z)
	local b = FarmBounds.get(biome)
	local dx, dz = x - b.cx, z - b.cz
	if math.abs(dx) > b.itemHalfX or math.abs(dz) > b.itemHalfZ then return false end
	for _, r in ipairs(b.keepOut) do
		if dx >= r[1] and dx <= r[2] and dz >= r[3] and dz <= r[4] then return false end
	end
	return true
end

--- (x, z) moved into the item area (a drop next to a wall, a stroll goal).
function FarmBounds.clamp(biome, x, z)
	local b = FarmBounds.get(biome)
	return math.clamp(x, b.cx - b.itemHalfX, b.cx + b.itemHalfX),
		math.clamp(z, b.cz - b.itemHalfZ, b.cz + b.itemHalfZ)
end

--- A random item spot (x, floorY, z) as a Vector3; `rand()` returns [0, 1).
-- Tries a few times to stay clear of keepOut, else the centre.
function FarmBounds.randomItemSpot(biome, rand)
	local b = FarmBounds.get(biome)
	rand = rand or math.random
	for _ = 1, 30 do
		local x = b.cx + (rand() * 2 - 1) * b.itemHalfX
		local z = b.cz + (rand() * 2 - 1) * b.itemHalfZ
		if FarmBounds.itemSpotOk(biome, x, z) then return Vector3.new(x, b.floorY, z) end
	end
	return Vector3.new(b.cx, b.floorY, b.cz)
end

--- Why the point `pos` (a character's root) is off the farm, or nil:
-- "fell" (under the floor), "flung" (high over it), "out" (past a wall).
function FarmBounds.offFarm(biome, pos)
	local b = FarmBounds.get(biome)
	if pos.Y < b.floorY - FarmBounds.FALL_BELOW then return "fell" end
	if pos.Y > b.floorY + FarmBounds.FLUNG_ABOVE then return "flung" end
	if math.abs(pos.X - b.cx) > b.halfX + FarmBounds.OUT_MARGIN
		or math.abs(pos.Z - b.cz) > b.halfZ + FarmBounds.OUT_MARGIN then
		return "out"
	end
	return nil
end

return FarmBounds
