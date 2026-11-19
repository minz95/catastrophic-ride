--!nocheck
-- tools/gp_layout.luau — the Junk GP circuit as numbers and a JSON for
-- tools/gp_layout.py (top view PNG): lap length, tightest bends, pit boxes.
--   lune run tools/gp_layout.luau && python3 tools/gp_layout.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("../tests/lib/loader")
local env = Loader.boot()
local L = env.requirePath("ReplicatedStorage.Shared.GpLayout")
local N = L.nodes()
local geo = L.geometry()
print(string.format("nodes %d, lap %.0f studs", #N, geo.length))
local bends = {}
for i = 1, #N - 1 do
	local r = L.radiusAt(i)
	if math.abs(r) < 200 then table.insert(bends, { i = i, r = r, x = N[i][1], z = N[i][2] }) end
end
table.sort(bends, function(a, b) return math.abs(a.r) < math.abs(b.r) end)
for k = 1, math.min(12, #bends) do
	local b = bends[k]
	print(string.format("  bend r %6.1f at (%5.0f, %5.0f) node %d", b.r, b.x, b.z, b.i))
end
local boxes = {}
for k = 1, L.PIT.boxes do
	local p = L.box(k)
	table.insert(boxes, { p.X, p.Z })
end
local pit = {}
for _, p in ipairs(L.pitPath()) do table.insert(pit, { p.X, p.Z }) end
fs.writeFile("reports/gp/layout.json", serde.encode("json", {
	nodes = N, width = L.WIDTH, boxes = boxes, pit = pit, ground = L.GROUND,
	line = L.LINE_Z, sectors = L.SECTORS, grandstand = L.GRANDSTAND,
}))
