--!nocheck
-- tools/luge_layout.luau — the Alpine Luge's layout as JSON for
-- tools/luge_layout.py (top view and the trough's height profile).
--   lune run tools/luge_layout.luau && python3 tools/luge_layout.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("../tests/lib/loader")
local env = Loader.boot()
local LL = env.requirePath("ReplicatedStorage.Shared.LugeLayout")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
local N = LL.nodes()
local ground = {}
for _, n in ipairs(N) do table.insert(ground, LL.ground(n[2])) end
fs.writeFile("reports/luge/layout.json", serde.encode("json", {
	nodes = N, ground = ground, region = LL.REGION, width = Constants.LUGE.WIDTH, curves = LL.curves(),
	lift = { LL.LIFT.bottom.X, LL.LIFT.bottom.Z, LL.LIFT.top.X, LL.LIFT.top.Z },
	bottom = LL.BOTTOM_STATION, top = LL.TOP_STATION, desk = { LL.DESK.X, LL.DESK.Z }, finishS = LL.finishS(),
	length = LL.length(), hill = LL.HILL,
}))
print("reports/luge/layout.json")
