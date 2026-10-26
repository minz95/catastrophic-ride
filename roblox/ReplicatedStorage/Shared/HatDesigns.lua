-- HatDesigns.lua
-- The shop's hats (Cosmetics "hat") as plain parts: no meshes, no assets to
-- load. Units are studs on a 1.2-stud head; (0, 0, 0) is the middle of the
-- head's top, +Y up, -Z the face side. Modules/ShopHat scales them to the
-- real head and welds them on; Modules/ShopPreview puts them on a head for
-- the shop card.
--
-- Part fields: shape "block" | "ball" | "cyl" (a cylinder standing up:
-- size = diameter, height, diameter), size, pos, rot (degrees, X Y Z),
-- color, material (Enum.Material name), neon (true: Neon).

local HatDesigns = {}

local C = Color3.fromRGB
local V = Vector3.new

HatDesigns.HEAD = 1.2   -- the head height the designs are drawn for

local function ring(n, radius, y, size, color, material)
	local out = {}
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		table.insert(out, {
			shape = "block", size = size, pos = V(math.cos(a) * radius, y, math.sin(a) * radius),
			rot = V(0, -math.deg(a) + 90, 0), color = color, material = material,
		})
	end
	return out
end

local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, p in ipairs(list) do table.insert(out, p) end
	end
	return out
end

HatDesigns.party = {
	{ shape = "cyl", size = V(1.0, 0.25, 1.0), pos = V(0, 0.1, 0),  color = C(255, 90, 170) },
	{ shape = "cyl", size = V(0.8, 0.25, 0.8), pos = V(0, 0.35, 0), color = C(255, 220, 60) },
	{ shape = "cyl", size = V(0.6, 0.25, 0.6), pos = V(0, 0.6, 0),  color = C(255, 90, 170) },
	{ shape = "cyl", size = V(0.4, 0.25, 0.4), pos = V(0, 0.85, 0), color = C(255, 220, 60) },
	{ shape = "cyl", size = V(0.2, 0.22, 0.2), pos = V(0, 1.07, 0), color = C(255, 90, 170) },
	{ shape = "ball", size = V(0.32, 0.32, 0.32), pos = V(0, 1.27, 0), color = C(120, 220, 255) },
}

HatDesigns.cat = {
	{ shape = "block", size = V(0.42, 0.42, 0.12), pos = V(-0.36, 0.02, 0.05), rot = V(0, 0, 45), color = C(40, 36, 44) },
	{ shape = "block", size = V(0.42, 0.42, 0.12), pos = V(0.36, 0.02, 0.05),  rot = V(0, 0, 45), color = C(40, 36, 44) },
	{ shape = "block", size = V(0.24, 0.24, 0.04), pos = V(-0.36, 0.04, -0.03), rot = V(0, 0, 45), color = C(255, 150, 190) },
	{ shape = "block", size = V(0.24, 0.24, 0.04), pos = V(0.36, 0.04, -0.03),  rot = V(0, 0, 45), color = C(255, 150, 190) },
	{ shape = "block", size = V(1.0, 0.1, 0.16), pos = V(0, 0.0, 0.05), color = C(40, 36, 44) },
}

HatDesigns.propeller = {
	{ shape = "cyl", size = V(1.2, 0.3, 1.2), pos = V(0, 0.08, 0), color = C(230, 60, 60) },
	{ shape = "block", size = V(0.3, 0.31, 1.21), pos = V(0, 0.08, 0), color = C(60, 120, 230) },
	{ shape = "block", size = V(0.8, 0.06, 0.5), pos = V(0, 0.0, -0.75), color = C(230, 60, 60) },
	{ shape = "cyl", size = V(0.08, 0.3, 0.08), pos = V(0, 0.38, 0), color = C(60, 60, 70) },
	{ shape = "block", size = V(1.5, 0.05, 0.18), pos = V(0, 0.54, 0), rot = V(0, 20, 0), color = C(255, 220, 60) },
	{ shape = "block", size = V(1.5, 0.05, 0.18), pos = V(0, 0.54, 0), rot = V(0, 110, 0), color = C(60, 200, 120) },
	{ shape = "ball", size = V(0.14, 0.14, 0.14), pos = V(0, 0.58, 0), color = C(60, 60, 70) },
}

HatDesigns.viking = {
	{ shape = "cyl", size = V(1.26, 0.45, 1.26), pos = V(0, 0.12, 0), color = C(150, 155, 165), material = "Metal" },
	{ shape = "cyl", size = V(1.3, 0.12, 1.3), pos = V(0, -0.05, 0), color = C(150, 100, 50), material = "Wood" },
	{ shape = "block", size = V(0.12, 0.5, 1.28), pos = V(0, 0.2, 0), color = C(200, 170, 80), material = "Metal" },
	{ shape = "block", size = V(0.5, 0.2, 0.2), pos = V(-0.72, 0.28, 0), rot = V(0, 0, -35), color = C(245, 240, 225) },
	{ shape = "block", size = V(0.5, 0.2, 0.2), pos = V(0.72, 0.28, 0),  rot = V(0, 0, 35),  color = C(245, 240, 225) },
	{ shape = "block", size = V(0.34, 0.14, 0.14), pos = V(-0.93, 0.58, 0), rot = V(0, 0, -75), color = C(245, 240, 225) },
	{ shape = "block", size = V(0.34, 0.14, 0.14), pos = V(0.93, 0.58, 0),  rot = V(0, 0, 75),  color = C(245, 240, 225) },
}

HatDesigns.top = {
	{ shape = "cyl", size = V(1.65, 0.08, 1.65), pos = V(0, 0.04, 0), color = C(25, 25, 30) },
	{ shape = "cyl", size = V(1.05, 1.0, 1.05), pos = V(0, 0.56, 0), color = C(25, 25, 30) },
	{ shape = "cyl", size = V(1.07, 0.16, 1.07), pos = V(0, 0.2, 0), color = C(200, 40, 60) },
}

HatDesigns.crown = join({
	{ shape = "cyl", size = V(1.15, 0.32, 1.15), pos = V(0, 0.12, 0), color = C(255, 200, 40), material = "Foil" },
}, ring(5, 0.5, 0.42, V(0.2, 0.36, 0.12), C(255, 200, 40), "Foil"), {
	{ shape = "ball", size = V(0.18, 0.18, 0.18), pos = V(0, 0.15, -0.58), color = C(220, 30, 60), neon = true },
	{ shape = "ball", size = V(0.14, 0.14, 0.14), pos = V(0.5, 0.64, 0), color = C(60, 120, 255) },
	{ shape = "ball", size = V(0.14, 0.14, 0.14), pos = V(-0.4, 0.64, 0.29), color = C(60, 220, 120) },
})

HatDesigns.halo = ring(14, 0.55, 0.6, V(0.27, 0.07, 0.09), C(255, 240, 150), nil)
for _, p in ipairs(HatDesigns.halo) do p.neon = true end

--- The parts of hat `id` (Cosmetics item field `hat`), or nil.
function HatDesigns.get(id)
	local d = HatDesigns[id]
	return type(d) == "table" and d[1] ~= nil and d or nil
end

return HatDesigns
