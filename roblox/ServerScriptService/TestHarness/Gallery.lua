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
local VehicleDesign = require(ServerScriptService.Modules.VehicleDesign)
local SeatedRider = require(ServerScriptService.Modules.SeatedRider)

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
	gui.StudsOffset = Vector3.new(0, 7, 0)   -- over a hat
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

-- An avatar sitting in the vehicle's seat (Modules/SeatedRider).
local function seatRider(model, folder, shirt)
	return SeatedRider.seat(model, folder, shirt)
end

Gallery.seatRider = seatRider

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
	-- `gap`: how far the seat's bottom floats above the item's real surface
	-- right under the rider (rays down onto the item's collision shape at the
	-- seat and a hand's width around it; the box top is not the surface of a
	-- duck's back or a treadmill's belt). > 0.1: the rider looks to float.
	local holder
	for _, h in ipairs(model:GetChildren()) do
		if h:IsA("Model") and h:GetAttribute("Slot") == "BODY" then holder = h end
	end
	local gap
	if holder then
		local parts = {}
		for _, p in ipairs(holder:GetDescendants()) do
			if p:IsA("BasePart") then p.CanQuery = true; table.insert(parts, p) end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = parts
		local seatBottom = seat.Position.Y - seat.Size.Y / 2
		local hits = {}
		for _, o in ipairs({ Vector3.zero, Vector3.new(0.5, 0, 0), Vector3.new(-0.5, 0, 0), Vector3.new(0, 0, 0.5), Vector3.new(0, 0, -0.5) }) do
			local from = (seat.CFrame * CFrame.new(o)).Position + Vector3.new(0, 6, 0)
			local hit = workspace:Raycast(from, Vector3.new(0, -14, 0), params)
			table.insert(hits, hit and hit.Position.Y or -math.huge)
		end
		table.sort(hits)
		-- the highest surface under the rider holds them up
		gap = hits[#hits] > -math.huge and r(seatBottom - hits[#hits]) or nil
		for _, p in ipairs(parts) do p.CanQuery = false end
	end
	return { sink = r(hi.Y - seatTop), over = r(math.max(overX, overZ)), itemH = r(hi.Y - lo.Y),
		itemL = r(hi.Z - lo.Z), itemW = r(hi.X - lo.X), gap = gap }
end

-- Wheels, paddle wheels and propellers that do not touch what carries them
-- (the body or ridden item, an axle / post, a hub, a nacelle), with the
-- real meshes. Same rule as tests/specs/vehicle_design.
local function boxOf(x)
	local list = x:IsA("BasePart") and { x } or x:GetDescendants()
	local a, b
	for _, p in ipairs(list) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local e = p.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local v = p.CFrame * Vector3.new(sx * e.X, sy * e.Y, sz * e.Z)
				a = a and Vector3.new(math.min(a.X, v.X), math.min(a.Y, v.Y), math.min(a.Z, v.Z)) or v
				b = b and Vector3.new(math.max(b.X, v.X), math.max(b.Y, v.Y), math.max(b.Z, v.Z)) or v
			end end end
		end
	end
	return a, b
end
local function touch(x, y)
	if not x or not y then return false end
	local a1, b1 = boxOf(x)
	local a2, b2 = boxOf(y)
	if not a1 or not a2 then return false end
	local t = 0.08
	return a1.X <= b2.X + t and a2.X <= b1.X + t and a1.Y <= b2.Y + t and a2.Y <= b1.Y + t and a1.Z <= b2.Z + t and a2.Z <= b1.Z + t
end
function Gallery.looseParts(model, biome)
	local holders = {}
	for _, h in ipairs(model:GetChildren()) do
		local s = h:IsA("Model") and h:GetAttribute("Slot")
		if s then holders[s] = holders[s] or {}; table.insert(holders[s], h) end
	end
	local function part(n) return model:FindFirstChild(n) end
	local base = holders.BODY and holders.BODY[1] or model.PrimaryPart
	local out = {}
	if biome == "FOREST" then
		local wheels = holders.MOBILITY or {}
		if #wheels == 0 then
			for _, n in ipairs({ "WheelFrontL", "WheelFrontR", "WheelRearL", "WheelRearR" }) do table.insert(wheels, part(n)) end
		end
		for i, w in ipairs(wheels) do
			local ok = touch(w, base)
			for _, tag in ipairs({ "Front", "Rear" }) do
				local axle, post = part("Axle" .. tag), part("Post" .. tag)
				if axle and touch(w, axle) and (touch(axle, base) or (post and touch(axle, post) and touch(post, base))) then ok = true end
			end
			if not ok then table.insert(out, "wheel " .. i) end
		end
	elseif biome == "OCEAN" and holders.MOBILITY then
		for _, n in ipairs({ "PaddleHubL", "PaddleHubR" }) do
			if not (touch(part(n), base) or touch(part(n), part("Float"))) then table.insert(out, n) end
		end
		for i, h in ipairs(holders.MOBILITY) do
			if not (touch(h, part("PaddleHubL")) or touch(h, part("PaddleHubR"))) then table.insert(out, "paddle " .. i) end
		end
	end
	if biome == "OCEAN" then
		-- the outboard motor (or ENGINE item) and the flag hold on to the boat
		local function onHull(x)
			for _, h in pairs({ base, part("Float"), part("Transom"), part("TransomSkirt"), part("Keel") }) do
				if touch(x, h) then return true end
			end
			return false
		end
		local motor = holders.ENGINE and holders.ENGINE[1] or part("Motor")
		if motor and not onHull(motor) then table.insert(out, "motor") end
		if part("MotorLeg") and motor and not touch(part("MotorLeg"), motor) then table.insert(out, "motor leg") end
		if part("FlagPole") and not onHull(part("FlagPole")) then table.insert(out, "flag pole") end
	end
	if biome == "SKY" and holders.MOBILITY then
		for _, n in ipairs({ "NacelleL", "NacelleR" }) do
			if not touch(part(n), part("Wing")) then table.insert(out, n) end
		end
		for i, h in ipairs(holders.MOBILITY) do
			if not (touch(h, part("NacelleL")) or touch(h, part("NacelleR"))) then table.insert(out, "propeller " .. i) end
		end
	end
	return out
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

	local report = { items = {}, shots = {}, loose = {} }
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
				if biome == "OCEAN" then
					-- the water as in a race (VehicleDesign.WATERLINE), to see the boat sit in it
					local water = Instance.new("Part")
					water.Anchored, water.CanCollide = true, false
					water.Size = Vector3.new(9, 0.1, 9)
					water.CFrame = cf * CFrame.new(0, VehicleDesign.WATERLINE - 0.05, 0)
					water.Color = Color3.fromRGB(40, 120, 200)
					water.Transparency = 0.35
					water.Material = Enum.Material.Glass
					water.Parent = folder
				end
				label(model, (slots.BODY or "-") .. (slots.MOBILITY and (" + " .. slots.MOBILITY .. " "
					.. ({ FOREST = "wheels", OCEAN = "paddles", SKY = "props" })[biome]) or "")
					.. (slots.HEAD and (" + " .. slots.HEAD .. " hat") or "") .. " · "
					.. ({ FOREST = "car", OCEAN = "boat", SKY = "plane" })[biome])
				local char, seat = seatRider(model, folder)
				if char then riders += 1 end
				local _, size = VehicleBuilder.bounds(model)
				local entry = { biome = biome, body = slots.BODY, riding = model:GetAttribute("Riding"),
					size = { math.floor(size.X * 10) / 10, math.floor(size.Y * 10) / 10, math.floor(size.Z * 10) / 10 } }
				if seat then entry.fit = fitOf(model, seat) end
				for _, what in ipairs(Gallery.looseParts(model, biome)) do
					table.insert(report.loose, string.format("%s %s %s", biome, slots.BODY or "-", what))
				end
				table.insert(report.items, entry)
			else
				table.insert(report.items, { biome = biome, body = slots.BODY, error = tostring(model) })
			end
		end
	end
	task.wait(1)   -- let the riders settle into their seats
	local seated, hats = 0, 0
	for _, c in ipairs(folder:GetChildren()) do
		local hum = c:IsA("Model") and c:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			seated += 1
			-- the HEAD item onto the rider's head, as in a race
			local vehicle = hum.SeatPart:FindFirstAncestorWhichIsA("Model")
			if vehicle and VehicleBuilder.wearHat(vehicle, c) then hats += 1 end
		end
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
	-- opts.closeUps: one more stop per vehicle, from close behind and to the side
	local CLOSE = { { "car", 0 }, { "boat", 1 }, { "plane", 2 } }
	for i, slots in ipairs(list) do
		local centre = ORIGIN + Vector3.new(SIDE, 0.8, (i - 1) * SPACING)
		local views = table.clone(VIEWS)
		if args.closeUps then
			for _, c in ipairs(CLOSE) do
				local at = ORIGIN + Vector3.new(c[2] * SIDE, 0.8, (i - 1) * SPACING)
				table.insert(views, { c[1], at + Vector3.new(-6, 3.2, -4.5) - centre, at + Vector3.new(0, 0.6, 0) - centre })
			end
		end
		for _, v in ipairs(views) do
			target = CFrame.lookAt(centre + v[2], centre + v[3])
			task.wait(0.5)
			n += 1
			local item = ((slots.BODY or "none") .. (i > #names and (" " .. (slots.MOBILITY or slots.HEAD or "build")) or "")):lower():gsub("%W", "")
			local name = string.format("%02d_%s_%s", i, item, v[1])
			print(string.format("GALLERY_SHOT %s %d %s", token, n, name))
			table.insert(report.shots, name)
			task.wait(hold)
		end
	end
	conn:Disconnect()
	-- where each worn hat ended up against its rider's head (after the shots)
	report.hats = {}
	for _, c in ipairs(folder:GetChildren()) do
		local hum = c:IsA("Model") and c:FindFirstChildOfClass("Humanoid")
		local head = c:FindFirstChild("Head")
		local vehicle = hum and hum.SeatPart and hum.SeatPart:FindFirstAncestorWhichIsA("Model")
		if vehicle and head then
			for _, h in ipairs(vehicle:GetChildren()) do
				if h:IsA("Model") and h:GetAttribute("Hat") and h.PrimaryPart then
					local off = head.CFrame:PointToObjectSpace(h.PrimaryPart.Position)
					local r = function(x) return math.floor(x * 100 + 0.5) / 100 end
					local seat = hum.SeatPart
					table.insert(report.hats, { item = h:GetAttribute("Item"), worn = h:GetAttribute("WornBy") ~= nil,
						offset = { r(off.X), r(off.Y - head.Size.Y / 2), r(off.Z) },
						headAboveSeat = r(seat.CFrame:PointToObjectSpace(head.Position).Y + head.Size.Y / 2 - seat.Size.Y / 2) })
				end
			end
		end
	end
	folder:Destroy()
	local riding = 0
	for _, it in ipairs(report.items) do if it.riding then riding += 1 end end
	report.summary = string.format("gallery: %d vehicles, %d shots, %d riding their BODY item, %d riders made, %d seated, %d hats worn, %d loose wheels / paddles / propellers",
		#report.items, #report.shots, riding, riders, seated, hats, #report.loose)
	return report
end

return Gallery
