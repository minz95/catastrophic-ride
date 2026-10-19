-- TerrainPlan.lua
-- Decorative terrain for one biome, as a list of fill operations computed
-- from the track data. Pure data (no Instances), so the offline tests check
-- that nothing lands in the lane. Modules/TerrainPainter applies the list.
--
-- Terrain is decoration only: every map builds its own driving surface from
-- parts. So every operation must stay either fully below the driving surface
-- or clear of the corridor (lane + walls + margin), checked by `clearOf`.
--
-- op = { kind = "box", material = "Grass", cx, cy, cz, sx, sy, sz }
--    | { kind = "ball", material = "Rock", cx, cy, cz, r }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local TrackGeometry = require(Shared.TrackGeometry)

local TerrainPlan = {}

TerrainPlan.TRACKS = {
	FOREST = Shared.Tracks.ForestTrack,
	OCEAN  = Shared.Tracks.OceanTrack,
	SKY    = Shared.Tracks.SkyTrack,
}

-- Horizontal gap kept between any decoration and the outside of the walls.
TerrainPlan.CORRIDOR_MARGIN = 12

local function bounds(track, margin)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, n in ipairs(track.nodes) do
		x0 = math.min(x0, n[1]); x1 = math.max(x1, n[1])
		z0 = math.min(z0, n[2]); z1 = math.max(z1, n[2])
	end
	if track.farm then
		local half = track.farm.size and track.farm.size[2] / 2 or 160
		z1 = math.max(z1, track.farm.cz + half)
	end
	return x0 - margin, x1 + margin, z0 - margin, z1 + margin
end

--- Half-width of the corridor that decorations must stay out of.
function TerrainPlan.corridorHalf(track)
	return track.width / 2 + (track.wallThickness or 2) + TerrainPlan.CORRIDOR_MARGIN
end

--- Lowest Y a decoration may reach inside the corridor. Below this it is
-- under the driving surface (or the sea floor walls stand on) and harmless.
function TerrainPlan.floorY(track)
	if track.biome == "OCEAN" then
		return (track.obstacleBand and track.obstacleBand[1] or 1.2) - 4
	elseif track.biome == "SKY" then
		return (track.wallYLo or track.trackTop - 26)
	end
	return -4   -- FOREST: under the 4-stud Ground part (top at 0)
end

local function inFarm(track, x, z, r)
	local f = track.farm
	if not f then return false end
	local w, d = (f.size and f.size[1] or 220) / 2, (f.size and f.size[2] or 320) / 2
	return math.abs(x - f.cx) < w + r and math.abs(z - f.cz) < d + r
end

--- True when the op cannot touch the corridor or the farm.
function TerrainPlan.clearOf(track, geo, op)
	local top, reach
	if op.kind == "ball" then
		top, reach = op.cy + op.r, op.r
	else
		top, reach = op.cy + op.sy / 2, math.max(op.sx, op.sz) / 2
	end
	if top <= TerrainPlan.floorY(track) then return true end
	if op.kind == "box" then return false end   -- boxes above the floor are never allowed
	local p = geo:project(op.cx, op.cz)
	if p.dist < TerrainPlan.corridorHalf(track) + reach then return false end
	if inFarm(track, op.cx, op.cz, reach) then return false end
	return true
end

local function scatter(out, track, geo, rng, count, make)
	local x0, x1, z0, z1 = bounds(track, 200)
	local tries = 0
	local placed = 0
	while placed < count and tries < count * 20 do
		tries += 1
		local op = make(rng:NextNumber(x0, x1), rng:NextNumber(z0, z1))
		if TerrainPlan.clearOf(track, geo, op) then
			table.insert(out, op)
			placed += 1
		end
	end
end

local PLANS = {}

function PLANS.FOREST(track, geo)
	local out = {}
	-- Hills between the track's loops and around it (grass, half buried).
	local rng = Random.new(12)
	scatter(out, track, geo, rng, 40, function(x, z)
		local r = rng:NextNumber(12, 30)
		return { kind = "ball", material = "Grass", cx = x, cy = -r * 0.5, cz = z, r = r }
	end)
	return out
end

function PLANS.OCEAN(track, geo)
	local out = {}
	-- OceanMap's opaque OceanFloor part hides anything under the water, so
	-- the terrain only adds sand bars outside the walls that break the surface.
	local rng = Random.new(55)
	scatter(out, track, geo, rng, 15, function(x, z)
		local r = rng:NextNumber(8, 16)
		return { kind = "ball", material = "Sand", cx = x, cy = -r + 3, cz = z, r = r }
	end)
	return out
end

function PLANS.SKY(track, geo)
	local out = {}
	-- Floating rock islands with grass caps, around (never over) the lane.
	local rng = Random.new(33)
	scatter(out, track, geo, rng, 18, function(x, z)
		local r = rng:NextNumber(8, 20)
		return { kind = "ball", material = "Rock", cx = x, cy = track.trackTop - rng:NextNumber(10, 60), cz = z, r = r }
	end)
	local n = #out
	for i = 1, n do
		local rock = out[i]
		local cap = { kind = "ball", material = "Grass", cx = rock.cx, cy = rock.cy + rock.r * 0.6, cz = rock.cz, r = rock.r * 0.5 }
		if TerrainPlan.clearOf(track, geo, cap) then table.insert(out, cap) end
	end
	return out
end

--- The fill operations for a biome (deterministic).
function TerrainPlan.build(biome)
	local mod = TerrainPlan.TRACKS[biome]
	assert(mod and PLANS[biome], "TerrainPlan: unknown biome " .. tostring(biome))
	local track = require(mod)
	local geo = TrackGeometry.new(track.nodes, track.width)
	return PLANS[biome](track, geo), track, geo
end

return TerrainPlan
