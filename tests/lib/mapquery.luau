--!nocheck
-- mapquery.luau
-- Turns a built map (mock Instances) into 2D collision/trigger shapes for the
-- kinematic simulator and the geometry checks.

local Mock = require("./mock")
local Vector3 = require("@lune/roblox").Vector3

local MapQuery = {}

--- World-space shape of a BasePart: vertical span + XZ footprint.
-- Footprint is an oriented box when the part is upright (yaw-only), else the
-- XZ bounding box of its 8 corners.
function MapQuery.shape(part)
	local p = Mock.props(part)
	local cf, size = p.CFrame, p.Size
	local yMin, yMax = math.huge, -math.huge
	local xMin, xMax, zMin, zMax = math.huge, -math.huge, math.huge, -math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local c = cf * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
				yMin = math.min(yMin, c.Y); yMax = math.max(yMax, c.Y)
				xMin = math.min(xMin, c.X); xMax = math.max(xMax, c.X)
				zMin = math.min(zMin, c.Z); zMax = math.max(zMax, c.Z)
			end
		end
	end
	local shape = {
		part = part,
		name = p.Name,
		class = part.ClassName,
		tags = part:GetTags(),
		yMin = yMin, yMax = yMax,
		aabb = { xMin, zMin, xMax, zMax },
		canCollide = p.CanCollide,
	}
	local up = cf.UpVector
	if math.abs(up.Y) > 0.999 then
		local r, l = cf.RightVector, cf.LookVector
		local rl = math.sqrt(r.X * r.X + r.Z * r.Z)
		local ll = math.sqrt(l.X * l.X + l.Z * l.Z)
		shape.cx, shape.cz = cf.Position.X, cf.Position.Z
		shape.ux, shape.uz, shape.hu = r.X / rl, r.Z / rl, size.X / 2
		shape.vx, shape.vz, shape.hv = l.X / ll, l.Z / ll, size.Z / 2
	else
		shape.cx, shape.cz = (xMin + xMax) / 2, (zMin + zMax) / 2
		shape.ux, shape.uz, shape.hu = 1, 0, (xMax - xMin) / 2
		shape.vx, shape.vz, shape.hv = 0, 1, (zMax - zMin) / 2
	end
	return shape
end

--- Closest point on a shape's footprint to (x, z); also whether (x,z) is inside.
function MapQuery.closest(shape, x, z)
	local dx, dz = x - shape.cx, z - shape.cz
	local u = dx * shape.ux + dz * shape.uz
	local v = dx * shape.vx + dz * shape.vz
	local inside = math.abs(u) <= shape.hu and math.abs(v) <= shape.hv
	local cu = math.clamp(u, -shape.hu, shape.hu)
	local cv = math.clamp(v, -shape.hv, shape.hv)
	return shape.cx + cu * shape.ux + cv * shape.vx,
		shape.cz + cu * shape.uz + cv * shape.vz,
		inside, u, v
end

function MapQuery.contains(shape, x, z)
	local _, _, inside = MapQuery.closest(shape, x, z)
	return inside
end

--- Footprint corners (for SVG drawing).
function MapQuery.corners(shape)
	local out = {}
	for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local u, v = s[1] * shape.hu, s[2] * shape.hv
		table.insert(out, { shape.cx + u * shape.ux + v * shape.vx, shape.cz + u * shape.uz + v * shape.vz })
	end
	return out
end

--- Uniform grid for fast neighbourhood queries.
function MapQuery.grid(shapes, cell)
	cell = cell or 32
	local g = { cell = cell, cells = {} }
	for _, sh in ipairs(shapes) do
		local a = sh.aabb
		for gx = math.floor(a[1] / cell), math.floor(a[3] / cell) do
			for gz = math.floor(a[2] / cell), math.floor(a[4] / cell) do
				local key = gx .. ":" .. gz
				g.cells[key] = g.cells[key] or {}
				table.insert(g.cells[key], sh)
			end
		end
	end
	function g.near(x, z, r)
		local seen, out = {}, {}
		for gx = math.floor((x - r) / cell), math.floor((x + r) / cell) do
			for gz = math.floor((z - r) / cell), math.floor((z + r) / cell) do
				local list = g.cells[gx .. ":" .. gz]
				if list then
					for _, sh in ipairs(list) do
						if not seen[sh] then
							seen[sh] = true
							table.insert(out, sh)
						end
					end
				end
			end
		end
		return out
	end
	return g
end

--- All BaseParts under `root` as shapes.
function MapQuery.shapes(root, filter)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local sh = MapQuery.shape(d)
			if not filter or filter(sh) then
				table.insert(out, sh)
			end
		end
	end
	return out
end

local TRIGGER_TAGS = {
	"Checkpoint1", "Checkpoint2", "FinishLine", "BoostPad", "DriftCorner",
	"MudZone", "SlowZone", "JumpZone", "Obstacle", "KillPlane", "UpdraftZone",
}
MapQuery.TRIGGER_TAGS = TRIGGER_TAGS

function MapQuery.isTrigger(shape)
	for _, t in ipairs(shape.tags) do
		if table.find(TRIGGER_TAGS, t) then
			return true, t
		end
	end
	return false
end

--- Obstacles a car body can hit: collidable, rising into the body band, and
-- not a ramp (WedgeParts are driven over).
function MapQuery.obstacles(root, trackTop, band)
	band = band or { 0.6, 3.0 }
	local lo, hi = trackTop + band[1], trackTop + band[2]
	return MapQuery.shapes(root, function(sh)
		if not sh.canCollide then return false end
		if sh.class == "WedgePart" then return false end
		return sh.yMax > lo and sh.yMin < hi
	end)
end

return MapQuery
