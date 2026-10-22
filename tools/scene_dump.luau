--!nocheck
-- scene_dump.luau
-- Builds a biome map with the real game code (mock engine) and writes the
-- parts near a camera as JSON for tools/scene_render.py, so the look of a
-- map, a car or a dropped item can be checked without Studio.
--
--   lune run tools/scene_dump.luau <BIOME> <node> [out.json] [radius] [extra]
--     node   : centerline node the camera looks along (chase view from behind)
--     extra  : "cars" adds four cars on the lane at the node
--
-- The render command is printed at the end.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local World = require("../tests/lib/world")
local Mock = require("../tests/lib/mock")

local biome = (process.args[1] or "SKY"):upper()
local node = tonumber(process.args[2] or "6")
local out = process.args[3] or ("reports/scenes/" .. biome:lower() .. "-n" .. node .. ".json")
local radius = tonumber(process.args[4] or "700")
local extra = process.args[5] or ""

local w = World.build(biome, { visibility = "shipped" })
local env, track, geo = w.env, w.track, w.geo

local seg = geo.segments[math.clamp(node, 1, #geo.segments)]
local y = track.trackTop or 0
if biome == "SKY" then y = 84 - 2 end
local fx, fz = seg.dx, seg.dz
local cam = {
	eye = { seg.ax - fx * 30, y + 12, seg.az - fz * 30 },
	target = { seg.ax + fx * 60, y + 2, seg.az + fz * 60 },
}

local roots = { w.map }

if extra:find("cars") then
	env.run(env.find("ServerScriptService.ItemModelPreloader"))
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local slots = { BODY = "Shopping Cart", ENGINE = "Rocket", SPECIAL = "Umbrella", HEAD = "Cactus", TAIL = "Balloon Bunch" }
	local s = VehicleStats.calculate(ItemConfig[slots.BODY], ItemConfig[slots.ENGINE], ItemConfig[slots.SPECIAL], biome)
	local folder = Mock.Instance.new("Folder")
	folder.Parent = env.workspace
	local yaw = math.atan2(-fx, -fz)
	for i, off in ipairs({ { -8, 10 }, { 8, 10 }, { -8, 30 }, { 8, 30 } }) do
		local px = seg.ax + fx * off[2] - fz * off[1]
		local pz = seg.az + fz * off[2] + fx * off[1]
		local m = VehicleBuilder.build(s, biome, CFrame.new(px, y + 2, pz) * CFrame.Angles(0, yaw, 0), slots)
		m.Name = "Car" .. i
		m.Parent = folder
	end
	table.insert(roots, folder)
end

if extra:find("drops") then
	-- every drop item, in a row ahead of the camera (Modules/TrackDrops)
	env.run(env.find("ServerScriptService.ItemModelPreloader"))
	local TrackDrops = env.requirePath("ServerScriptService.Modules.TrackDrops")
	local items = { "Pizza", "Gas Can", "Magnifying Glass", "Kettle", "Cactus", "Log" }
	local yaw = math.atan2(-fx, -fz)
	for i, item in ipairs(items) do
		local col = (i % 2 == 0) and 9 or -9
		local along = 30 + i * 12
		local px = seg.ax + fx * along - fz * col
		local pz = seg.az + fz * along + fx * col
		local holder = Mock.Instance.new("Model")
		local p = Mock.Instance.new("Part")
		p.Size = Vector3.new(2, 1.2, 4)
		p.CFrame = CFrame.new(px, y + 1, pz) * CFrame.Angles(0, yaw + math.pi, 0)   -- facing back: drop lands ahead
		p.Parent = holder
		holder.PrimaryPart = p
		holder.Parent = env.workspace
		TrackDrops.place(item, holder, { behind = 0, show = item == "Log" and 7 or (item == "Cactus" and 5 or 4),
			hazard = { kind = (item == "Cactus" or item == "Log") and "obstacle" or "slick", size = Vector3.new(8, 3, 8) } })
		holder:Destroy()
	end
	table.insert(roots, env.workspace:FindFirstChild("TrackDrops"))
end

if extra:find("logs") then
	-- falling logs as HazardManager drops them: two landed, one still a warning
	local HazardPlan = env.requirePath("ReplicatedStorage.Shared.HazardPlan")
	local HazardLook = env.requirePath("ServerScriptService.Modules.HazardLook")
	local H = env.requirePath("ReplicatedStorage.Shared.Constants").HAZARDS
	local folder = Mock.Instance.new("Folder")
	folder.Parent = env.workspace
	local s0 = geo:project(seg.ax, seg.az).s
	local st = 5
	local spots = HazardPlan.logSpots(geo, geo.width, s0 - H.LOG_AHEAD_MIN + 15, 3, function()
		st = (st * 1103515245 + 12345) % 2147483648
		return st / 2147483648
	end)
	for i, sp in ipairs(spots) do
		local ground = Vector3.new(sp.x, y, sp.z)
		if i == #spots then
			HazardLook.warnMarker(ground).Parent = folder
		else
			HazardLook.logModel(CFrame.new(ground + Vector3.new(0, H.LOG_SIZE[2] / 2, 0)) * CFrame.Angles(0, sp.yaw, 0)).Parent = folder
		end
	end
	table.insert(roots, folder)
end

-- Extra parts other tools put in workspace (e.g. drops) are dumped too.
local function shapeOf(p)
	if p.ClassName == "WedgePart" then return "wedge" end
	if p.ClassName == "CornerWedgePart" then return "wedge" end
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

local ex, ez = cam.eye[1], cam.eye[3]
local parts = {}
for _, root in ipairs(roots) do
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = Mock.props(d)
			local cf = p.CFrame
			local pos = cf.Position
			local size = p.Size
			local reach = math.max(size.X, size.Y, size.Z) / 2
			local dist = math.sqrt((pos.X - ex) ^ 2 + (pos.Z - ez) ^ 2) - reach
			if p.Transparency < 0.98 and dist < radius then
				local c = p.Color
				table.insert(parts, {
					n = d.Name, s = shapeOf(d),
					cf = { cf:GetComponents() },
					size = { size.X, size.Y, size.Z },
					col = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
					t = p.Transparency,
					mat = tostring(p.Material):gsub("Enum.Material.", ""),
				})
			end
		end
	end
end

local lighting = {}
local Lighting = env.game:GetService("Lighting")
for _, k in ipairs({ "FogColor", "FogEnd", "Ambient", "OutdoorAmbient" }) do
	local ok, v = pcall(function() return Lighting[k] end)
	if ok and v ~= nil then lighting[k] = tostring(v) end
end

local dir = out:match("(.*)/[^/]*$")
if dir and not fs.isDir(dir) then fs.writeDir(dir) end
fs.writeFile(out, serde.encode("json", { biome = biome, camera = cam, parts = parts }))
print(("%d parts → %s"):format(#parts, out))
print("render: python3 tools/scene_render.py " .. out)
