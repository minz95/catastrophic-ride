--!nocheck
-- shop_preview_dump.luau
-- The shop's pictures (Modules/ShopPreview) without Studio: builds the given
-- looks on a biome's vehicle side by side and writes them as a scene for
-- tools/scene_render.py.
--
--   lune run tools/shop_preview_dump.luau <BIOME> [id,id,…] [out.json]
--   python3 tools/scene_render.py <out.json> <out.png>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local Loader = require("../tests/lib/loader")
local Mock = require("../tests/lib/mock")

local biome = (process.args[1] or "FOREST"):upper()
local env = Loader.boot()
local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")
local ShopPreview = env.requirePath("ServerScriptService.Modules.ShopPreview")

local ids = {}
if process.args[2] and process.args[2] ~= "" then
	for id in string.gmatch(process.args[2], "[^,]+") do table.insert(ids, id) end
else
	for _, cat in ipairs(ShopPreview.CATEGORIES) do
		for _, it in ipairs(Cosmetics.ITEMS[cat]) do
			if cat == "ride" or not Cosmetics.isDefault(it.id) then table.insert(ids, it.id) end
		end
	end
end
local out = process.args[3] or ("reports/scenes/shop-" .. biome:lower() .. ".json")

local COLS, GAP = 4, 18
local parts = {}
for i, id in ipairs(ids) do
	local m = ShopPreview.buildOne(Cosmetics.get(id), biome)
	local col, row = (i - 1) % COLS, (i - 1) // COLS
	local shift = CFrame.new(col * GAP, 0, row * GAP * 1.3) * CFrame.Angles(0, math.rad(-35), 0)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = Mock.props(d)
			if p.Transparency < 0.98 then
				local c = p.Color
				local cf = shift * p.CFrame
				table.insert(parts, {
					n = d.Name, s = (tostring(p.Shape or ""):find("Cylinder") and "cylinder")
						or (tostring(p.Shape or ""):find("Ball") and "ball") or (d.ClassName == "WedgePart" and "wedge") or "block",
					cf = { cf:GetComponents() },
					size = { p.Size.X, p.Size.Y, p.Size.Z },
					col = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
					t = p.Transparency,
					mat = tostring(p.Material):gsub("Enum.Material.", ""),
				})
			end
		end
	end
end
local w = (math.min(#ids, COLS) - 1) * GAP
local rows = (#ids - 1) // COLS
local cam = { eye = { w / 2, 34 + rows * 8, -26 }, target = { w / 2, 0, rows * GAP * 0.65 } }
local dir = out:match("(.*)/[^/]*$")
if dir and not fs.isDir(dir) then fs.writeDir(dir) end
fs.writeFile(out, serde.encode("json", { biome = biome, camera = cam, parts = parts }))
print(("%d looks, %d parts → %s"):format(#ids, #parts, out))
