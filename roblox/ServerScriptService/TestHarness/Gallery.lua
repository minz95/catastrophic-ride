-- Gallery.lua
-- A look at the vehicles with the real item meshes (Studio run mode): every
-- BODY item is built as the car, the boat and the plane (VehicleBuilder, the
-- same call as a race), parked anchored in rows, and the camera stops on
-- each row. Each stop prints "GALLERY_SHOT <token> <n> <name>" and holds
-- `hold` seconds; tools/studio/sim.py (kind "gallery") takes a screenshot
-- then. Nothing drives; this is only about the look.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.ItemTypes)
local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)

local Gallery = {}

local BIOMES = { "FOREST", "OCEAN", "SKY" }
local SPACING = 9
local ORIGIN = Vector3.new(0, 400, 3000)   -- far from every map

local function statsFor(slots, biome)
	local s = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	s = VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	return s
end

function Gallery.run(args)
	args = args or {}
	local token = args.token or "-"
	local hold = args.hold or 3
	local models = ServerStorage:WaitForChild("ItemModels", 30)
	local t0 = os.clock()
	while models and not models:GetAttribute("Ready") and os.clock() - t0 < 60 do task.wait(0.25) end

	local bodies = {}
	for _, it in ipairs(ItemTypes.ALL) do
		if it.slotType == "BODY" then table.insert(bodies, it.name) end
	end
	table.sort(bodies)
	local extra = args.extra or {}   -- { { BODY = ..., ENGINE = ..., ... }, ... } full builds

	local folder = Instance.new("Folder")
	folder.Name = "VehicleGallery"
	folder.Parent = workspace
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(220, 1, 140)
	floor.Color = Color3.fromRGB(110, 160, 90)
	floor.CFrame = CFrame.new(ORIGIN + Vector3.new(70, -1.5, 40))
	floor.Parent = folder

	local report = { items = {}, shots = {} }
	local rows = {}
	for b, biome in ipairs(BIOMES) do
		local list = {}
		for _, name in ipairs(bodies) do table.insert(list, { BODY = name }) end
		for _, sl in ipairs(extra) do table.insert(list, sl) end
		for i, slots in ipairs(list) do
			local at = ORIGIN + Vector3.new((i - 1) * SPACING, 0, (b - 1) * 40)
			-- facing the camera's right (+X), so we see the side
			local cf = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
			local ok, model = pcall(VehicleBuilder.build, statsFor(slots, biome), biome, cf, slots)
			if ok and model then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = true end
				end
				model.Parent = folder
				local _, size = VehicleBuilder.bounds(model)
				table.insert(report.items, { biome = biome, body = slots.BODY, riding = model:GetAttribute("Riding"),
					size = { math.floor(size.X * 10) / 10, math.floor(size.Y * 10) / 10, math.floor(size.Z * 10) / 10 } })
			else
				table.insert(report.items, { biome = biome, body = slots.BODY, error = tostring(model) })
			end
		end
		rows[b] = #list
	end

	-- camera stops: each biome row in two halves, seen from the side and above
	local cam = workspace.CurrentCamera
	local target
	local conn = RunService.Heartbeat:Connect(function()
		if target then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = target
		end
	end)
	local n = 0
	for b, biome in ipairs(BIOMES) do
		local count = rows[b]
		local per = math.ceil(count / 3)
		for half = 0, 2 do
			local first, last = half * per + 1, math.min(count, (half + 1) * per)
			if first > last then continue end
			local midX = ((first + last) / 2 - 1) * SPACING
			local look = ORIGIN + Vector3.new(midX, 0.5, (b - 1) * 40)
			target = CFrame.lookAt(look + Vector3.new(0, 5.5, -17), look)
			task.wait(1)
			n += 1
			local name = string.format("%s_%d", biome:lower(), half + 1)
			print(string.format("GALLERY_SHOT %s %d %s", token, n, name))
			table.insert(report.shots, name)
			task.wait(hold)
		end
	end
	conn:Disconnect()
	folder:Destroy()
	report.summary = string.format("gallery: %d vehicles, %d shots, %d riding their BODY item",
		#report.items, #report.shots, (function()
			local k = 0
			for _, it in ipairs(report.items) do if it.riding then k += 1 end end
			return k
		end)())
	return report
end

return Gallery
