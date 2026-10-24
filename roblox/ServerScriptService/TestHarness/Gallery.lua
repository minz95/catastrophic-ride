-- Gallery.lua
-- A look at the vehicles with the real item meshes (Studio run mode): every
-- item you can ride (BODY items and ItemConfig `ride` items) is built as the
-- car, the boat and the plane (VehicleBuilder, the same call as a race),
-- parked anchored in rows with an avatar sitting in the seat (seat:Sit, the
-- legs bent like the sit pose) and the item's name above it. The camera stops
-- on a few vehicles at a time, seen from the front quarter. Each stop prints
-- "GALLERY_SHOT <token> <n> <name>" and holds `hold` seconds; tools/studio/
-- sim.py (kind "gallery") takes a screenshot then. Nothing drives; this is
-- only about the look. opts.only = { "Pizza", ... } limits the items.
--
-- The report lists, per vehicle, where the rider sits against the item:
-- `sink` = item top − seat top (> 0: sitting down inside the item, < 0: the
-- seat floats above it) and `over` = how far the rider's hips stick out past
-- the item's footprint.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.ItemTypes)
local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
local CraftingRules = require(ReplicatedStorage.Shared.CraftingRules)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)

local Gallery = {}

local BIOMES = { "FOREST", "OCEAN", "SKY" }
local SPACING = 32   -- between items (Z)
local SIDE = 12      -- between an item's car, boat and plane (X, nose to tail)
local ORIGIN = Vector3.new(0, 400, 3000)   -- far from every map

local function statsFor(slots, biome)
	local s = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	s = VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	return s
end

--- Every item the BODY slot takes, BODY items first.
function Gallery.rideable()
	local bodies, rides = {}, {}
	for _, it in ipairs(ItemTypes.ALL) do
		local cfg = ItemConfig[it.name]
		if it.slotType == "BODY" then table.insert(bodies, it.name)
		elseif CraftingRules.fits("BODY", cfg) then table.insert(rides, it.name) end
	end
	table.sort(bodies)
	table.sort(rides)
	for _, n in ipairs(rides) do table.insert(bodies, n) end
	return bodies
end

local function label(model, text)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 160, 0, 26)
	gui.StudsOffset = Vector3.new(0, 5.5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 32   -- only the row in front of the camera
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 0.4
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.Text = text
	l.Parent = gui
	gui.Parent = model.PrimaryPart
end

-- Bends a joint by `rot` around the joint, in its parent part's axes. Avatars
-- may have AnimationConstraint joints instead of Motor6D (see FarmFx).
local function bend(char, jointName, rot)
	local j = char:FindFirstChild(jointName, true)
	local obj, prop
	if j and j:IsA("Motor6D") then obj, prop = j, "C0"
	elseif j and j:IsA("AnimationConstraint") and j.Attachment0 then obj, prop = j.Attachment0, "CFrame"
	else return false end
	local c0 = obj[prop]
	local p = c0.Position
	obj[prop] = CFrame.new(p) * rot * (c0 - p)
	return true
end

-- An avatar sitting in the vehicle's seat, legs bent like the sit pose.
local function seatRider(model, folder)
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then return nil end
	local ok, char = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = Color3.fromRGB(255, 220, 180)
		desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
		desc.TorsoColor = Color3.fromRGB(60, 140, 230)
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(60, 60, 80), Color3.fromRGB(60, 60, 80)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not char then return nil end
	char.Name = "Rider"
	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local animate = char:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	char.Parent = folder
	seat:Sit(hum)
	-- the pose: thighs forward, shins down, hands on the knees
	local q = math.pi / 2
	bend(char, "LeftHip", CFrame.Angles(q, 0, 0))
	bend(char, "RightHip", CFrame.Angles(q, 0, 0))
	bend(char, "LeftKnee", CFrame.Angles(-q, 0, 0))
	bend(char, "RightKnee", CFrame.Angles(-q, 0, 0))
	bend(char, "LeftShoulder", CFrame.Angles(q * 0.6, 0, 0))
	bend(char, "RightShoulder", CFrame.Angles(q * 0.6, 0, 0))
	return char, seat
end

-- Where the rider sits against the ridden item (mount space = the chassis).
local function fitOf(model, seat)
	local chassis = model.PrimaryPart
	local lo, hi
	for _, h in ipairs(model:GetChildren()) do
		if h:IsA("Model") and h:GetAttribute("Slot") == "BODY" then
			for _, p in ipairs(h:GetDescendants()) do
				if p:IsA("BasePart") then
					local e = p.Size * 0.5
					for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
						local v = chassis.CFrame:PointToObjectSpace(p.CFrame * Vector3.new(sx * e.X, sy * e.Y, sz * e.Z))
						lo = lo and Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
						hi = hi and Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
					end end end
				end
			end
		end
	end
	if not lo then return nil end
	local s = chassis.CFrame:PointToObjectSpace(seat.Position)
	local seatTop = s.Y + seat.Size.Y / 2
	local overX = math.max(0, math.abs(s.X) - (hi.X - lo.X) / 2)
	local overZ = math.max(0, s.Z - hi.Z, lo.Z - s.Z)
	local r = function(x) return math.floor(x * 100 + 0.5) / 100 end
	return { sink = r(hi.Y - seatTop), over = r(math.max(overX, overZ)), itemH = r(hi.Y - lo.Y),
		itemL = r(hi.Z - lo.Z), itemW = r(hi.X - lo.X) }
end

function Gallery.run(args)
	args = args or {}
	local token = args.token or "-"
	local hold = args.hold or 3
	local models = ServerStorage:WaitForChild("ItemModels", 30)
	local t0 = os.clock()
	while models and not models:GetAttribute("Ready") and os.clock() - t0 < 60 do task.wait(0.25) end

	local names = Gallery.rideable()
	if args.only then names = args.only end
	local list = {}
	for _, name in ipairs(names) do table.insert(list, { BODY = name }) end
	for _, sl in ipairs(args.extra or {}) do table.insert(list, sl) end

	local folder = Instance.new("Folder")
	folder.Name = "VehicleGallery"
	folder.Parent = workspace
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(120, 1, #list * SPACING + 60)
	floor.Color = Color3.fromRGB(110, 160, 90)
	floor.CFrame = CFrame.new(ORIGIN + Vector3.new(SIDE, -2.5, #list * SPACING / 2 - 30))
	floor.Parent = folder

	local report = { items = {}, shots = {} }
	local riders = 0
	for i, slots in ipairs(list) do
		for b, biome in ipairs(BIOMES) do
			local at = ORIGIN + Vector3.new((b - 1) * SIDE, 0, (i - 1) * SPACING)
			-- facing +X: car, boat, plane nose to tail, seen from the side
			local cf = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
			local ok, model = pcall(VehicleBuilder.build, statsFor(slots, biome), biome, cf, slots)
			if ok and model then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = true end
				end
				model.Parent = folder
				label(model, (slots.BODY or "-") .. " · " .. ({ FOREST = "car", OCEAN = "boat", SKY = "plane" })[biome])
				local char, seat = seatRider(model, folder)
				if char then riders += 1 end
				local _, size = VehicleBuilder.bounds(model)
				local entry = { biome = biome, body = slots.BODY, riding = model:GetAttribute("Riding"),
					size = { math.floor(size.X * 10) / 10, math.floor(size.Y * 10) / 10, math.floor(size.Z * 10) / 10 } }
				if seat then entry.fit = fitOf(model, seat) end
				table.insert(report.items, entry)
			else
				table.insert(report.items, { biome = biome, body = slots.BODY, error = tostring(model) })
			end
		end
	end
	task.wait(1)   -- let the riders settle into their seats
	local seated = 0
	for _, c in ipairs(folder:GetChildren()) do
		local hum = c:IsA("Model") and c:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then seated += 1 end
	end

	-- camera stops: one item at a time (its car, boat and plane), from the side
	-- and from a raised rear quarter (about where a chasing racer sees it)
	local cam = workspace.CurrentCamera
	local target
	local conn = RunService.Heartbeat:Connect(function()
		if target then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = target
		end
	end)
	local n = 0
	local VIEWS = {
		{ "side", Vector3.new(0, 3, -21), Vector3.new(0, 0.5, 0) },
		{ "rear", Vector3.new(-17, 10, -13), Vector3.new(2, -0.5, 0) },
	}
	for i, slots in ipairs(list) do
		local centre = ORIGIN + Vector3.new(SIDE, 0.8, (i - 1) * SPACING)
		for _, v in ipairs(VIEWS) do
			target = CFrame.lookAt(centre + v[2], centre + v[3])
			task.wait(0.5)
			n += 1
			local item = ((slots.BODY or "none") .. (i > #names and " build" or "")):lower():gsub("%W", "")
			local name = string.format("%02d_%s_%s", i, item, v[1])
			print(string.format("GALLERY_SHOT %s %d %s", token, n, name))
			table.insert(report.shots, name)
			task.wait(hold)
		end
	end
	conn:Disconnect()
	folder:Destroy()
	local riding = 0
	for _, it in ipairs(report.items) do if it.riding then riding += 1 end end
	report.summary = string.format("gallery: %d vehicles, %d shots, %d riding their BODY item, %d riders made, %d seated",
		#report.items, #report.shots, riding, riders, seated)
	return report
end

return Gallery
