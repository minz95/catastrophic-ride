--!nocheck
-- vehicle_gallery.luau
-- Draws the vehicles VehicleBuilder really assembles (game code in the mock
-- engine, procedural item models included) as orthographic side / top / front
-- views, so a change to the vehicle look can be reviewed without Studio.
--
--   lune run tools/vehicle_gallery.luau            -- every biome
--   lune run tools/vehicle_gallery.luau SKY        -- one biome
--
-- Writes reports/vehicles/<biome>.svg. Front (-Z, LookVector) is on the LEFT
-- in the side and top views.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local Loader = require("../tests/lib/loader")
local env = Loader.boot({ quiet = true })
env.run(env.find("ServerScriptService.ItemModelPreloader"))
local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local ItemTypes = env.requirePath("ReplicatedStorage.Shared.ItemTypes")

local Gallery = {}

-- Representative builds: no items, the RaceSim test cars, and full random sets.
local byType = { BODY = {}, ENGINE = {}, SPECIAL = {} }
for _, it in ipairs(ItemTypes.ALL) do table.insert(byType[it.slotType], it.name) end
local all = {}
for _, it in ipairs(ItemTypes.ALL) do table.insert(all, it.name) end

local seed = 7
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
local function pick(list) return list[rnd(#list)] end

Gallery.BUILDS = {
	{ label = "no items", slots = {} },
	{ label = "slowest", slots = { BODY = "Microwave", ENGINE = "Fan", SPECIAL = "Pizza" } },
	{ label = "p50", slots = { BODY = "Shopping Cart", ENGINE = "Magnifying Glass", SPECIAL = "Toilet Paper" } },
	{ label = "fastest", slots = { BODY = "Skateboard", ENGINE = "Kettle", SPECIAL = "Umbrella", MOBILITY = "Alarm Clock" } },
}
for i = 1, 4 do
	table.insert(Gallery.BUILDS, { label = "random " .. i, slots = {
		BODY = pick(byType.BODY), ENGINE = pick(byType.ENGINE), SPECIAL = pick(byType.SPECIAL),
		MOBILITY = pick(all), HEAD = pick(all), TAIL = pick(all),
	} })
end

function Gallery.build(biome, slots)
	local s = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	s = VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	return VehicleBuilder.build(s, biome, CFrame.new(), slots)
end

-- ─── Geometry: points on each part's surface, in world space ─────────────────

local function shapeOf(p)
	if p.ClassName == "WedgePart" then return "wedge" end
	if p.ClassName == "CornerWedgePart" then return "corner" end
	local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
	if mesh then
		local t = tostring(mesh.MeshType)
		if t:find("Sphere") then return "ball" end
		if t:find("Cylinder") then return "cylinder" end
	end
	local sh = tostring(p.Shape or "")
	if sh:find("Cylinder") then return "cylinder" end
	if sh:find("Ball") then return "ball" end
	return "block"
end

local function localPoints(shape, s)
	local x, y, z = s.X / 2, s.Y / 2, s.Z / 2
	local pts = {}
	if shape == "wedge" then
		-- WedgePart: full bottom, top edge at +Z; the slope faces -Z
		for _, a in ipairs({ -1, 1 }) do
			for _, c in ipairs({ -1, 1 }) do table.insert(pts, Vector3.new(a * x, -y, c * z)) end
			table.insert(pts, Vector3.new(a * x, y, z))
		end
	elseif shape == "corner" then
		for _, a in ipairs({ -1, 1 }) do
			for _, c in ipairs({ -1, 1 }) do table.insert(pts, Vector3.new(a * x, -y, c * z)) end
		end
		table.insert(pts, Vector3.new(x, y, -z))
	elseif shape == "cylinder" then
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			for _, e in ipairs({ -1, 1 }) do
				table.insert(pts, Vector3.new(e * x, math.cos(a) * y, math.sin(a) * z))
			end
		end
	elseif shape == "ball" then
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			table.insert(pts, Vector3.new(math.cos(a) * x, math.sin(a) * y, 0))
			table.insert(pts, Vector3.new(0, math.cos(a) * y, math.sin(a) * z))
			table.insert(pts, Vector3.new(math.cos(a) * x, 0, math.sin(a) * z))
		end
	else
		for _, a in ipairs({ -1, 1 }) do
			for _, b in ipairs({ -1, 1 }) do
				for _, c in ipairs({ -1, 1 }) do table.insert(pts, Vector3.new(a * x, b * y, c * z)) end
			end
		end
	end
	return pts
end

function Gallery.parts(model)
	local out = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			local world = {}
			for _, v in ipairs(localPoints(shapeOf(p), p.Size)) do
				table.insert(world, p.CFrame * v)
			end
			table.insert(out, { part = p, pts = world, color = p.Color, alpha = 1 - p.Transparency })
		end
	end
	return out
end

local function hull(points)
	table.sort(points, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
	local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
	local lower, upper = {}, {}
	for _, p in ipairs(points) do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
		table.insert(lower, p)
	end
	for i = #points, 1, -1 do
		local p = points[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
		table.insert(upper, p)
	end
	table.remove(lower); table.remove(upper)
	for _, p in ipairs(upper) do table.insert(lower, p) end
	return lower
end

-- view: function(v) -> u, w, depth  (u right, w up, depth toward the viewer)
local VIEWS = {
	side  = function(v) return v.Z, v.Y, v.X end,    -- seen from +X: front (-Z) on the left
	top   = function(v) return v.Z, -v.X, v.Y end,   -- seen from above, front on the left
	front = function(v) return v.X, v.Y, -v.Z end,   -- seen from the front
}

local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local SCALE = 22
local function drawView(buf, parts, view, ox, oy, w, h)
	local items = {}
	for _, it in ipairs(parts) do
		local pts, depth = {}, 0
		for _, v in ipairs(it.pts) do
			local u, ww, d = VIEWS[view](v)
			table.insert(pts, { u, ww })
			depth += d
		end
		table.insert(items, { poly = hull(pts), depth = depth / #it.pts, color = it.color, alpha = it.alpha })
	end
	table.sort(items, function(a, b) return a.depth < b.depth end)
	table.insert(buf, string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="#e9eef3" stroke="#bbb"/>', ox, oy, w, h))
	-- ground line (y = 0) in the side / front views
	local cx, cy = ox + w / 2, oy + h * (view == "top" and 0.5 or 0.72)
	if view ~= "top" then
		table.insert(buf, string.format('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="#8a7" stroke-width="1"/>', ox, cy, ox + w, cy))
	end
	for _, it in ipairs(items) do
		local s = {}
		for _, p in ipairs(it.poly) do
			table.insert(s, string.format("%.1f,%.1f", cx + p[1] * SCALE, cy - p[2] * SCALE))
		end
		table.insert(buf, string.format('<polygon points="%s" fill="%s" fill-opacity="%.2f" stroke="#222" stroke-opacity="0.35" stroke-width="0.6"/>',
			table.concat(s, " "), hex(it.color), it.alpha))
	end
	table.insert(buf, string.format('<text x="%d" y="%d" font-size="11" fill="#666">%s%s</text>', ox + 4, oy + 13, view,
		view == "front" and "" or " (front ←)"))
end

function Gallery.svg(biome)
	local VW, VH = 260, 200
	local rows = Gallery.BUILDS
	local buf = {}
	local W, H = 3 * VW + 260, #rows * (VH + 16) + 40
	table.insert(buf, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="Helvetica, Arial, sans-serif">', W, H))
	table.insert(buf, string.format('<rect width="%d" height="%d" fill="#fff"/>', W, H))
	table.insert(buf, string.format('<text x="10" y="26" font-size="18" font-weight="bold">%s vehicles (VehicleBuilder, 1 stud = %d px)</text>', biome, SCALE))
	for i, b in ipairs(rows) do
		local model = Gallery.build(biome, b.slots)
		local parts = Gallery.parts(model)
		local oy = 40 + (i - 1) * (VH + 16)
		drawView(buf, parts, "side", 10, oy, VW, VH)
		drawView(buf, parts, "top", 10 + VW, oy, VW, VH)
		drawView(buf, parts, "front", 10 + 2 * VW, oy, VW, VH)
		local tx = 20 + 3 * VW
		table.insert(buf, string.format('<text x="%d" y="%d" font-size="13" font-weight="bold">%s</text>', tx, oy + 18, b.label))
		local line = 0
		for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }) do
			if b.slots[slot] then
				line += 1
				table.insert(buf, string.format('<text x="%d" y="%d" font-size="11" fill="#444">%s: %s</text>', tx, oy + 22 + line * 15, slot, b.slots[slot]))
			end
		end
		model:Destroy()
	end
	table.insert(buf, "</svg>")
	return table.concat(buf, "\n")
end

local only = process.args[1]
pcall(fs.writeDir, "reports/vehicles")
for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	if not only or only == biome then
		fs.writeFile("reports/vehicles/" .. biome:lower() .. ".svg", Gallery.svg(biome))
		print("wrote reports/vehicles/" .. biome:lower() .. ".svg")
	end
end
