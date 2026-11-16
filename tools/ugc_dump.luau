--!nocheck
-- ugc_dump.luau
-- The achievement hats (Cosmetics items with `achievement`, parts from
-- Shared/HatDesigns) as JSON for tools/ugc_models.py, which builds the
-- Marketplace avatar items (docs/ugc.md) in Blender.
--
--   lune run tools/ugc_dump.luau [out.json]   (default assets/ugc/designs.json)

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/lib/loader")

local env = Loader.boot()
local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")
local HatDesigns = env.requirePath("ReplicatedStorage.Shared.HatDesigns")

local MATERIAL = { Foil = "metal", Metal = "metal", Wood = "wood" }

local out = { head = HatDesigns.HEAD, hats = {} }
for _, it in ipairs(Cosmetics.ITEMS.hat) do
	if it.achievement and it.hat then
		local parts = {}
		for _, p in ipairs(HatDesigns.get(it.hat)) do
			local r = p.rot or { X = 0, Y = 0, Z = 0 }
			table.insert(parts, {
				shape = p.shape,
				size = { p.size.X, p.size.Y, p.size.Z },
				pos = { p.pos.X, p.pos.Y, p.pos.Z },
				rot = { r.X, r.Y, r.Z },
				color = { math.floor(p.color.R * 255 + 0.5), math.floor(p.color.G * 255 + 0.5), math.floor(p.color.B * 255 + 0.5) },
				finish = p.neon and "glow" or MATERIAL[p.material or ""] or "plastic",
			})
		end
		table.insert(out.hats, { id = it.id, name = it.name, achievement = it.achievement, parts = parts })
	end
end
local path = process.args[1] or "assets/ugc/designs.json"
fs.writeFile(path, serde.encode("json", out, true))
print(#out.hats .. " hats → " .. path)
