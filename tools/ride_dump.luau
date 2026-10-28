--!nocheck
-- ride_dump.luau
-- Vehicles ridden on BODY items (VehicleBuilder.build with slots.BODY, the
-- race's call) side by side as a scene for tools/scene_render.py, so how
-- much of the item still shows on a car / boat / plane can be checked
-- without Studio. Item meshes are boxes of the mesh's size offline.
--
--   lune run tools/ride_dump.luau <BIOME> [item,item,…] [out.json] [full]
-- "full" also fills ENGINE / SPECIAL / MOBILITY / TAIL / HEAD (how much of
-- every crafted part shows); "-" as an item = no BODY.
--   python3 tools/scene_render.py <out.json> <out.png>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local Loader = require("../tests/lib/loader")
local Mock = require("../tests/lib/mock")

local biome = (process.args[1] or "SKY"):upper()
local env = Loader.boot({ quiet = true })
env.run(env.find("ServerScriptService.ItemModelPreloader"))
local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")

local items = {}
local list = process.args[2]
if not list or list == "" then list = "Red Sofa,Bathtub,Pizza,Treadmill,Rubber Duck,Rocket,Kite,Suitcase" end
for it in string.gmatch(list, "[^,]+") do
	table.insert(items, it)
end
local out = process.args[3] or ("reports/scenes/ride-" .. biome:lower() .. ".json")

local COLS, GAP = 4, 14
local parts = {}
for i, item in ipairs(items) do
	local stats = VehicleStats.calculate(nil, nil, nil, biome)
	local slots = { BODY = item ~= "-" and item or nil }
	if process.args[4] == "full" then
		slots.ENGINE, slots.SPECIAL, slots.MOBILITY, slots.TAIL, slots.HEAD = "Rocket", "Cactus", "Alarm Clock", "Racing Flag", "Fan"
	end
	local m = VehicleBuilder.build(stats, biome, CFrame.new(), slots)
	local col, row = (i - 1) % COLS, (i - 1) // COLS
	local shift = CFrame.new(col * GAP, 0, row * GAP * 1.3) * CFrame.Angles(0, math.rad(-35), 0)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = Mock.props(d)
			if p.Transparency < 0.98 then
				local c = p.Color
				table.insert(parts, {
					n = d.Name, s = (tostring(p.Shape or ""):find("Cylinder") and "cylinder")
						or (tostring(p.Shape or ""):find("Ball") and "ball") or (d.ClassName == "WedgePart" and "wedge") or "block",
					cf = { (shift * p.CFrame):GetComponents() },
					size = { p.Size.X, p.Size.Y, p.Size.Z },
					col = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
					t = p.Transparency,
					mat = tostring(p.Material):gsub("Enum.Material.", ""),
				})
			end
		end
	end
end
local w = (math.min(#items, COLS) - 1) * GAP
local rows = (#items - 1) // COLS
local cam = { eye = { w / 2, 26 + rows * 6, -22 }, target = { w / 2, 0, rows * GAP * 0.65 } }
local dir = out:match("(.*)/[^/]*$")
if dir and not fs.isDir(dir) then fs.writeDir(dir) end
fs.writeFile(out, serde.encode("json", { biome = biome, camera = cam, parts = parts }))
print(("%d rides, %d parts → %s"):format(#items, #parts, out))
