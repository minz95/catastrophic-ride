-- CarBump.lua
-- Car-to-car contact for drivers who do not touch physically: the Junk GP
-- and the Alpine Luge put their cars in a collision group that passes
-- through itself, and the server resolves every touch with this (pure, no
-- Roblox types). Before (Studio 2026-11-20): a player's car (owned by its
-- client) meeting a bot's (owned by the server) hit it as a wall; a big
-- enough stop read as a crash and threw the car over.
--
--   local hits = CarBump.find(cars, cfg)
--   -- cars: { { id, x, z, vx, vz, yaw, length, width } } (yaw: the nose,
--   --   LookVector = (-sin, 0, -cos))
--   -- hits: { { a, b, ax, az, bx, bz, power } }: velocity changes (studs/s)
--   --   for car a and car b, power = closing speed
--
-- Each car is a box (length × width) turned by its yaw. Two boxes overlap
-- when no axis of either separates them; they are pushed apart along the
-- axis of least overlap, sharing the closing speed (equal weights) with
-- RESTITUTION, at least MIN_PUSH even when barely moving (a touch parts
-- them), at most MAX_PUSH.

local CarBump = {}

CarBump.DEFAULTS = { RESTITUTION = 0.6, MIN_PUSH = 3, MAX_PUSH = 22 }

local function axes(c)
	local fx, fz = -math.sin(c.yaw or 0), -math.cos(c.yaw or 0)   -- forward
	return fx, fz, -fz, fx                                         -- forward, right
end

-- half extent of box c projected onto axis (ux, uz)
local function extent(c, ux, uz)
	local fx, fz, rx, rz = axes(c)
	return math.abs(fx * ux + fz * uz) * c.length / 2 + math.abs(rx * ux + rz * uz) * c.width / 2
end

--- The overlap of a and b: nil when apart, else the push axis from a to b
-- (nx, nz) and the depth.
function CarBump.overlap(a, b)
	local dx, dz = b.x - a.x, b.z - a.z
	local best, bx, bz
	local afx, afz, arx, arz = axes(a)
	local bfx, bfz, brx, brz = axes(b)
	for _, ax in ipairs({ { afx, afz }, { arx, arz }, { bfx, bfz }, { brx, brz } }) do
		local ux, uz = ax[1], ax[2]
		local d = dx * ux + dz * uz
		local depth = extent(a, ux, uz) + extent(b, ux, uz) - math.abs(d)
		if depth <= 0 then return nil end
		if not best or depth < best then
			best = depth
			local sgn = d >= 0 and 1 or -1
			bx, bz = ux * sgn, uz * sgn
		end
	end
	return bx, bz, best
end

--- Every touching pair in `cars` and the velocity change of each car.
function CarBump.find(cars, cfg)
	cfg = cfg or CarBump.DEFAULTS
	local e = cfg.RESTITUTION or CarBump.DEFAULTS.RESTITUTION
	local minPush = cfg.MIN_PUSH or CarBump.DEFAULTS.MIN_PUSH
	local maxPush = cfg.MAX_PUSH or CarBump.DEFAULTS.MAX_PUSH
	local out = {}
	for i = 1, #cars do
		for j = i + 1, #cars do
			local a, b = cars[i], cars[j]
			local nx, nz = CarBump.overlap(a, b)
			if nx then
				-- closing speed along the axis (b's velocity minus a's)
				local rel = ((b.vx or 0) - (a.vx or 0)) * nx + ((b.vz or 0) - (a.vz or 0)) * nz
				local push = rel < 0 and -(1 + e) * rel / 2 or 0
				push = math.clamp(math.max(push, minPush), 0, maxPush)
				table.insert(out, { a = a.id, b = b.id, ax = -nx * push, az = -nz * push, bx = nx * push, bz = nz * push,
					power = math.max(-rel, 0) })
			end
		end
	end
	return out
end

--- A velocity change (dx, dz) on a driving state that travels along
-- `travelYaw` at `speed` (GpCar / LugeCart): the new speed and travel
-- heading. The nose stays: a hit from the side opens a slide.
function CarBump.apply(speed, travelYaw, dx, dz)
	local vx = -math.sin(travelYaw) * speed + dx
	local vz = -math.cos(travelYaw) * speed + dz
	local v = math.sqrt(vx * vx + vz * vz)
	if v < 0.5 then return 0, travelYaw end
	-- (a car knocked backwards keeps its heading: it is slowed, not reversed)
	local fwd = -math.sin(travelYaw) * vx - math.cos(travelYaw) * vz
	if fwd < 0 then return 0, travelYaw end
	return v, math.atan2(-vx, -vz)
end

return CarBump
