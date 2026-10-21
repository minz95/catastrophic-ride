-- CarImpact.lua
-- What a car-to-car hit does to each car, as numbers (pure, no Roblox types).
--
-- The drive model SETS each car's velocity every frame (VehicleController),
-- so Roblox's own collision response is overwritten the next frame and a hit
-- felt like touching a wall. The server (RacingManager) now resolves every
-- contact here and sends each driver a velocity change ("knock") and a spin;
-- VehicleController adds them to the drive command and lets them fade.
--
-- Model: an inelastic collision of two discs on the ground plane.
--   n         = unit vector from A to B
--   closing   = (vA - vB) · n            (> 0: moving into each other)
--   impulse   = (1 + e) × closing / (1/mA + 1/mB) × PUSH
--   dvA = -impulse / mA × n,  dvB = +impulse / mB × n   (each capped at MAX_DV)
-- A heavier car is pushed less. A hit on the side of a car (n across its
-- LookVector) near its nose or tail also spins it (spinFor).
--
--   local hit = CarImpact.resolve(a, b)
--     a, b = { x, z, vx, vz, mass, lx, lz }   (lx, lz = LookVector on XZ)
--   → nil (not closing fast enough) or
--     { strength, a = { dvx, dvz, spin }, b = { dvx, dvz, spin } }

local Constants = require(script.Parent.Constants)

local CarImpact = {}

local function unit(x, z)
	local d = math.sqrt(x * x + z * z)
	if d < 1e-6 then return 0, 0, 0 end
	return x / d, z / d, d
end

-- Spin (rad/s, + = yaw left, like VehicleController's yawRate) for a
-- velocity change (dvx, dvz) on a car facing (lx, lz), hit by a car in the
-- direction (tx, tz) from its centre. A push on the nose turns the nose
-- away from it; a push on the tail turns the nose towards it; a push square
-- on the middle of the side only slides the car.
local function spinFor(car, tx, tz, dvx, dvz)
	local I = Constants.IMPACT
	local lx, lz = unit(car.lx or 0, car.lz or -1)
	local rx, rz = -lz, lx                 -- RightVector on XZ
	local side = dvx * rx + dvz * rz       -- + = pushed to the right
	local lever = tx * lx + tz * lz        -- + = hit ahead of the centre
	local spin = -side * lever * I.SPIN_PER_DV
	return math.clamp(spin, -I.MAX_SPIN, I.MAX_SPIN)
end

function CarImpact.resolve(a, b)
	local I = Constants.IMPACT
	local nx, nz, dist = unit(b.x - a.x, b.z - a.z)
	if dist == 0 then
		-- same spot: push apart along A's facing
		nx, nz = unit(a.lx or 0, a.lz or -1)
	end
	local closing = ((a.vx or 0) - (b.vx or 0)) * nx + ((a.vz or 0) - (b.vz or 0)) * nz
	if closing < I.MIN_CLOSING then return nil end
	local ma, mb = math.max(a.mass or 1, 1e-3), math.max(b.mass or 1, 1e-3)
	local impulse = (1 + I.RESTITUTION) * closing / (1 / ma + 1 / mb) * I.PUSH
	local da = math.min(impulse / ma, I.MAX_DV)
	local db = math.min(impulse / mb, I.MAX_DV)
	local hit = {
		strength = closing,
		a = { dvx = -nx * da, dvz = -nz * da },
		b = { dvx = nx * db, dvz = nz * db },
	}
	hit.a.spin = spinFor(a, nx, nz, hit.a.dvx, hit.a.dvz)
	hit.b.spin = spinFor(b, -nx, -nz, hit.b.dvx, hit.b.dvz)
	return hit
end

--- Adds a velocity change along `(dirx, dirz)` of size `amount` to a side of
-- a resolved hit (passive pushes such as the Shopping Cart HEAD).
function CarImpact.addPush(side, dirx, dirz, amount)
	local ux, uz = unit(dirx, dirz)
	side.dvx += ux * amount
	side.dvz += uz * amount
	return side
end

--- Splits a velocity change into the part along the car's facing (changes
-- the drive speed) and the sideways rest (a slide that fades).
function CarImpact.split(lx, lz, dvx, dvz)
	local ux, uz = unit(lx, lz)
	local along = dvx * ux + dvz * uz
	return along, dvx - ux * along, dvz - uz * along
end

return CarImpact
