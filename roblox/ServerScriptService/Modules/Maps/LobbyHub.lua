-- LobbyHub.lua
-- Junk Town (2026-11-17): the lobby hub where players walk, chat and look
-- around between rounds, at Shared/LobbyLayout's spots: a plaza with
-- bottle-cap tiles on a floating island, a bathtub fountain, an old TV as
-- the "next race" board, the hall of fame stage on stacked tyres, a crate
-- garage for Legend Rides and a teapot trophy room, all from parts; the
-- town round it (houses and trees beyond a wooden fence, street lamps with
-- bunting, benches, the shop, barrels, crates, a junk pile, scrap cars) is
-- free Creator Store models (Shared/LobbyModels, approved 2026-11-17: "it is
-- all rectangles"), baked into ServerStorage.LobbyModels (StoreModelBake)
-- or, in Studio, built from Modules/LobbyModelData. Where a model is
-- missing the part-built look stands in. LobbyManager fills the live parts:
--   setBoard, setWinner (hall of fame), setLegends, setShowcase.
-- Prompts carry the attribute "Opens" ("shop" | "legend" | "awards"); the
-- client (LobbyHubClient) opens the shop on that tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local HatDesigns = require(ReplicatedStorage.Shared.HatDesigns)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local LobbyNpcs = require(ReplicatedStorage.Shared.LobbyNpcs)

local LobbyHub = {}
LobbyHub.NAME = "LobbyHub"

local V, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local C = Color3.fromRGB
local O = LobbyLayout.ORIGIN
local PASTEL = { C(255, 150, 150), C(255, 200, 120), C(255, 235, 130), C(150, 220, 150), C(140, 200, 255), C(200, 160, 255) }

-- ── Part helpers ─────────────────────────────────────────────────────────────

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new(shape == "wedge" and "WedgePart" or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "ball" then p.Shape = Enum.PartType.Ball
	elseif shape == "cyl" then p.Shape = Enum.PartType.Cylinder end
	p.Parent = parent
	return p
end

-- a cylinder standing up (Roblox's cylinders lie along X)
local function cyl(parent, name, d, h, cf, color, material)
	return part(parent, name, V(h, d, d), cf * A(0, 0, math.pi / 2), color, material, "cyl")
end

local function ball(parent, name, d, cf, color, material)
	return part(parent, name, V(d, d, d), cf, color, material, "ball")
end

local function deco(p)   -- something to look at, not to stand on
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Text on a part's front face (-Z), one line per entry: { text, size, colour }.
-- Lines stack through a UIListLayout (no Position: one layout for all).
local function sign(p, lines, bg, face)
	local g = Instance.new("SurfaceGui")
	g.Name = "Sign"
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.LightInfluence = 0.3
	g.Parent = p
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or C(250, 240, 210)
	frame.BackgroundTransparency = bg and 0 or 1
	frame.Parent = g
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = frame
	for i, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.Name = l.name or ("Line" .. i)
		t.LayoutOrder = i
		t.Size = UDim2.fromScale(1, l.share or (1 / #lines))
		t.BackgroundTransparency = 1
		t.Text = l.text
		t.TextScaled = true
		t.Font = l.font or Enum.Font.GothamBlack
		t.TextColor3 = l.color or C(60, 40, 30)
		t.Parent = frame
	end
	return g
end

-- A floating label over `p`, `width` studs wide (sized in studs, not
-- pixels: far labels shrink instead of piling up over each other; Studio
-- 2026-11-17, the Legend and trophy rows were a wall of text).
local function tag(p, lines, offset, maxDistance, width)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	width = width or 7
	bb.Size = UDim2.new(width, 0, width * 0.16 * #lines, 0)
	bb.StudsOffset = V(0, offset or 4, 0)
	bb.MaxDistance = maxDistance or 60
	bb.LightInfluence = 0
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bb
	for i, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.Name = l.name or ("Line" .. i)
		t.LayoutOrder = i
		t.Size = UDim2.new(1, 0, 1 / #lines, 0)
		t.BackgroundTransparency = 1
		t.Text = l.text
		t.TextScaled = true
		t.Font = l.font or Enum.Font.GothamBold
		t.TextColor3 = l.color or C(255, 255, 255)
		t.TextStrokeTransparency = 0.35
		t.Parent = bb
	end
	bb.Parent = p
	return bb
end

local function prompt(p, action, object, opens)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	if opens then pp:SetAttribute("Opens", opens) end
	pp.Parent = p
	return pp
end

local function at(pos, yawDeg)
	return CF(pos) * A(0, math.rad(yawDeg or 0), 0)
end

-- the spot on the rim at `angle` (degrees from +X), turned to face the centre
local function rim(angle, radius, y)
	local a = math.rad(angle)
	local pos = O + V(math.cos(a) * radius, y or 0, math.sin(a) * radius)
	return LobbyLayout.facingCentre(pos)
end

-- ── Creator Store models (Shared/LobbyModels) ────────────────────────────────

-- yaw (degrees) that turns a model's front to its -Z, where the town's
-- helpers expect it (each creator modelled their own way round)
LobbyHub.MODEL_YAW = {}

local _sources = {}
local function source(key)
	if _sources[key] ~= nil then return _sources[key] or nil end
	local folder = ServerStorage:FindFirstChild("LobbyModels")
	local found = folder and folder:FindFirstChild(key)
	if not found then
		-- Studio: built from data (live servers cannot load other creators' meshes this way)
		local okStudio, studio = pcall(function() return RunService:IsStudio() end)
		if okStudio and studio then
			local ok, model = pcall(function()
				local data = require(ServerScriptService.Modules.LobbyModelData)
				return require(ServerScriptService.Modules.ItemDataModel).build(key, data[key])
			end)
			found = ok and model or nil
		end
	end
	_sources[key] = found or false
	return found
end

--- A copy of model `key` standing at `cf` (position on the floor, turned like
-- `cf`; the model's front to cf's -Z), `height` studs tall. `solid` keeps
-- collision; otherwise it is looked through and walked through. nil when the
-- model is not in this place.
local function storeModel(m, key, cf, height, solid)
	local src = source(key)
	if not src then return nil end
	local copy = src:Clone()
	copy.Name = "Store_" .. key
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = solid == true
			if not solid then d.CanQuery = false end
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	local _, size = copy:GetBoundingBox()
	if size.Y > 0 then ModelScale.scale(copy, height / size.Y) end
	ModelScale.standOn(copy, cf.Position, cf.Position.Y,
		(cf - cf.Position) * A(0, math.rad(LobbyHub.MODEL_YAW[key] or 0), 0))
	copy.Parent = m
	return copy
end
LobbyHub._storeModel = storeModel

-- ── Ground ───────────────────────────────────────────────────────────────────

local function ground(m)
	local R = LobbyLayout.RADIUS
	local I = LobbyLayout.ISLAND_RADIUS
	cyl(m, "Grass", I * 2, 4, CF(O - V(0, 2, 0)), C(130, 200, 110), "Grass")
	cyl(m, "Plaza", R * 1.55, 4.04, CF(O - V(0, 2, 0)), C(240, 222, 190), "Cobblestone")
	cyl(m, "Centre", 30, 4.08, CF(O - V(0, 2, 0)), C(250, 235, 210), "CeramicTiles")
	-- bottle caps set in the paving, all colours
	local rnd = Random.new(7)
	for i = 1, 40 do
		local a = rnd:NextNumber(0, math.pi * 2)
		local r = rnd:NextNumber(17, R * 0.75)
		local p = O + V(math.cos(a) * r, 0.02, math.sin(a) * r)
		deco(cyl(m, "BottleCap", 2.4, 0.2, CF(p), PASTEL[i % #PASTEL + 1], "Metal"))
	end
	-- the island under it
	cyl(m, "Rock1", I * 1.9, 10, CF(O - V(0, 9, 0)), C(130, 115, 100), "Slate")
	cyl(m, "Rock2", I * 1.4, 12, CF(O - V(0, 20, 0)), C(115, 100, 88), "Slate")
	cyl(m, "Rock3", I * 0.8, 12, CF(O - V(0, 31, 0)), C(100, 88, 78), "Slate")
end

-- ── Fence: an invisible wall and colourful planks on it ──────────────────────

-- true when a piece at `angle` (degrees) on a circle of `radius`, `half`
-- studs either side, would stand in the gate to Auto Street
local function inGate(angle, radius, half)
	local d = math.abs((angle - LobbyLayout.GATE_ANGLE + 180) % 360 - 180)
	return math.rad(d) * radius < LobbyLayout.GATE_HALF + half
end

local function fence(m)
	local n = 36
	for i = 0, n - 1 do
		local a = i / n * 360
		if inGate(a, LobbyLayout.WALL_RADIUS, 0) then continue end   -- the way to Auto Street
		local cf = rim(a, LobbyLayout.WALL_RADIUS, LobbyLayout.WALL_HEIGHT / 2)
		local wall = part(m, "Wall", V(14, LobbyLayout.WALL_HEIGHT, 2), cf, C(255, 255, 255), "SmoothPlastic")
		wall.Transparency = 1
		wall.CanQuery = false
		if source("fence") then continue end
		local plank = rim(a, LobbyLayout.WALL_RADIUS - 1.5, 1.8)
		part(m, "Plank", V(1.6, 3.6 + (i % 3) * 0.4, 0.4), plank * A(0, 0, math.rad((i % 2 == 0) and 4 or -3)),
			PASTEL[i % #PASTEL + 1], "Wood")
		local rail = rim(a + 5, LobbyLayout.WALL_RADIUS - 1.5, 2.6)
		part(m, "Rail", V(13.4, 0.35, 0.3), rail, C(150, 105, 70), "Wood")
	end
end

-- the wooden fence models all round, on the invisible wall
local function fenceModels(m)
	if not source("fence") then return end
	local r = LobbyLayout.FENCE_RADIUS
	local piece = 6.2                         -- studs each piece covers
	local n = math.floor(2 * math.pi * r / piece)
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 360
		if not inGate(a, r, piece / 2) then
			storeModel(m, "fence", rim(a, r), 3.6, false)   -- its length (X) runs along the rim
		end
	end
end

-- ── Welcome arch ─────────────────────────────────────────────────────────────

local function tyre(m, cf, d)
	local t = cyl(m, "Tyre", d or 4, 1.3, cf, C(35, 35, 40), "Rubber")
	deco(cyl(m, "Hub", (d or 4) * 0.45, 1.34, cf, C(190, 195, 205), "Metal"))
	return t
end

local function arch(m)
	local base = LobbyLayout.ARCH
	for _, x in ipairs({ -9, 9 }) do
		-- pillars of old oil drums (tyres where the models are missing)
		if storeModel(m, "barrel_rusty", CF(base + V(x, 0, 0)) * A(0, x, 0), 3.9, true) then
			storeModel(m, "barrel_metal", CF(base + V(x, 3.9, 0)) * A(0, -x, 0), 3.8, true)
		else
			for k = 0, 5 do tyre(m, CF(base + V(x, 0.65 + k * 1.3, 0))) end
		end
	end
	local board = part(m, "WelcomeSign", V(22, 3.2, 0.6), at(base + V(0, 9.2, 0), 180), C(205, 160, 105), "WoodPlanks")
	sign(board, { { text = "WELCOME TO JUNK TOWN", color = C(90, 50, 30) } })
	sign(board, { { text = "WELCOME TO JUNK TOWN", color = C(90, 50, 30) } }, nil, Enum.NormalId.Back)
	for i = 0, 6 do   -- little light bulbs along the top
		deco(ball(m, "Bulb", 0.6, CF(base + V(-9 + i * 3, 11, 0)), PASTEL[i % #PASTEL + 1], "Neon"))
	end
end

-- ── Spawn: a big red bottle cap ──────────────────────────────────────────────

local function spawnPad(m)
	local s = Instance.new("SpawnLocation")
	s.Name = "LobbySpawn"
	s.Anchored = true
	s.Size = V(12, 1, 12)
	s.CFrame = CF(LobbyLayout.SPAWN + V(0, 0.5, 0))
	s.Color = C(225, 50, 55)
	s.Material = Enum.Material.Metal
	s.Neutral = true
	s.Duration = 0
	s.TopSurface = Enum.SurfaceType.Smooth
	s.Parent = m
	for i = 0, 15 do   -- the cap's crimped edge
		local a = i / 16 * math.pi * 2
		deco(part(m, "Crimp", V(1.4, 1.2, 0.5), CF(LobbyLayout.SPAWN + V(math.cos(a) * 6.6, 0.6, math.sin(a) * 6.6))
			* A(0, -a + math.pi / 2, 0), C(200, 40, 45), "Metal"))
	end
	return s
end

-- ── The bathtub fountain ─────────────────────────────────────────────────────

local function fountain(m)
	local p = LobbyLayout.FOUNTAIN
	part(m, "Tub", V(12, 3, 6), CF(p + V(0, 2.3, 0)), C(250, 250, 252), "Marble")
	local water = part(m, "Water", V(11, 0.4, 5), CF(p + V(0, 3.7, 0)), C(110, 190, 255), "Glass")
	water.Transparency = 0.25
	for _, x in ipairs({ -5, 5 }) do
		for _, z in ipairs({ -2.4, 2.4 }) do
			ball(m, "ClawFoot", 1.4, CF(p + V(x, 0.7, z)), C(230, 180, 50), "Foil")
		end
	end
	-- the tap at one end, the duck afloat
	cyl(m, "Tap", 0.5, 3, CF(p + V(-5.4, 5, 0)), C(200, 205, 215), "Metal")
	part(m, "Spout", V(1.6, 0.5, 0.5), CF(p + V(-4.8, 6.4, 0)), C(200, 205, 215), "Metal")
	deco(ball(m, "Duck", 1.4, CF(p + V(1.5, 4.4, 0.5)), C(255, 214, 30), "Rubber"))
	deco(ball(m, "DuckHead", 0.9, CF(p + V(1.1, 5.3, 0.5)), C(255, 214, 30), "Rubber"))
	deco(part(m, "Beak", V(0.5, 0.25, 0.4), CF(p + V(0.55, 5.25, 0.5)), C(255, 130, 20)))
end

-- ── The old TV board ─────────────────────────────────────────────────────────

local function board(m)
	local p = LobbyLayout.BOARD
	local face = LobbyLayout.facingCentre(p)   -- turned to the plaza's middle and the spawn beyond
	local yaw = face - face.Position
	for k = 0, 1 do tyre(m, CF(p + V(0, 0.65 + k * 1.3, 0)) , 6) end
	local tvAt = CF(p + V(0, 2.6 + 5, 0)) * yaw
	part(m, "TV", V(15, 10, 8), tvAt, C(150, 100, 60), "WoodPlanks")
	local screen = part(m, "Screen", V(12, 7.6, 0.4), tvAt * CF(-1, 0.4, -4.05), C(30, 40, 45), "SmoothPlastic")
	sign(screen, {
		{ name = "Title", text = "NEXT RACE", color = C(255, 214, 60), share = 0.22 },
		{ name = "Track", text = "?", color = C(255, 255, 255), share = 0.32 },
		{ name = "Count", text = "", color = C(150, 255, 160), share = 0.26 },
		{ name = "Players", text = "", color = C(200, 210, 230), share = 0.2, font = Enum.Font.GothamBold },
	}, C(20, 30, 35))
	for k = 0, 1 do   -- knobs
		deco(cyl(m, "Knob", 1.1, 0.4, tvAt * CF(6, 2 - k * 2.6, -4.1) * A(math.pi / 2, 0, 0), C(60, 50, 45), "Rubber"))
	end
	for _, s in ipairs({ -1, 1 }) do   -- rabbit-ear antennas
		deco(part(m, "Antenna", V(0.2, 6, 0.2), tvAt * CF(s * 1.6, 7.4, 0) * A(0, 0, math.rad(-s * 28)), C(190, 195, 205), "Metal"))
		deco(ball(m, "AntennaTip", 0.5, tvAt * CF(s * 3, 10.1, 0), C(190, 195, 205), "Metal"))
	end
	return screen
end

-- ── Hall of fame stage ───────────────────────────────────────────────────────

local function stage(m)
	local st = LobbyLayout.STAGE
	local p = st.at
	cyl(m, "Stage", st.radius * 2, st.height, CF(p + V(0, st.height / 2, 0)), C(165, 30, 45), "Carpet")
	cyl(m, "StageRim", st.radius * 2 + 0.6, 0.5, CF(p + V(0, st.height - 0.2, 0)), C(255, 200, 40), "Foil")
	for i = 0, 11 do   -- tyres round its foot
		local a = i / 12 * math.pi * 2
		tyre(m, CF(p + V(math.cos(a) * (st.radius + 1.6), 0.65, math.sin(a) * (st.radius + 1.6))), 3.2)
	end
	-- the backdrop: planks; the sign and three giant forks as a crown on a
	-- header board that setWinner lifts over whatever statue stands there
	part(m, "Backdrop", V(32, 14, 1), CF(p + V(0, 7, -st.radius - 3)), C(205, 160, 105), "WoodPlanks")
	local header = Instance.new("Model")
	header.Name = "HallHeader"
	local board = part(header, "HallSign", V(34, 7, 1), CF(p + V(0, 17.5, -st.radius - 3)), C(150, 30, 45), "WoodPlanks")
	sign(board, {
		{ text = "🏆 HALL OF FAME", color = C(255, 214, 60), share = 0.6 },
		{ text = "THE FUNNIEST RIDE OF THE LAST VOTE", color = C(255, 245, 225), share = 0.3, font = Enum.Font.GothamBold },
	}, C(150, 30, 45), Enum.NormalId.Back)
	for k = -1, 1 do
		local fx = p + V(k * 11, 21, -st.radius - 3)
		part(header, "ForkHandle", V(0.8, 6, 0.5), CF(fx + V(0, 3, 0)), C(205, 210, 220), "Metal")
		part(header, "ForkHead", V(3, 0.8, 0.5), CF(fx + V(0, 6.2, 0)), C(205, 210, 220), "Metal")
		for t = -1, 1 do
			part(header, "Tine", V(0.4, 2.6, 0.4), CF(fx + V(t * 1.1, 7.8, 0)), C(205, 210, 220), "Metal")
		end
	end
	header.PrimaryPart = board
	do
		local hcf, hsize = header:GetBoundingBox()
		header:SetAttribute("BaseBottom", hcf.Position.Y - hsize.Y / 2)
	end
	header.Parent = m
	-- lights on the statue from the front corners
	for _, x in ipairs({ -1, 1 }) do
		local lamp = deco(part(m, "StageLight", V(1, 1, 1), CF(p + V(x * 14, 18, st.radius + 2)), C(255, 255, 255)))
		lamp.Transparency = 1
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Front
		l.Angle = 50
		l.Range = 40
		l.Brightness = 3
		l.Color = C(255, 240, 210)
		l.Parent = lamp
		lamp.CFrame = CFrame.lookAt(lamp.Position, p + V(0, 6, 0))
	end
	local spot = deco(part(m, "WinnerSpot", V(1, 1, 1), CF(p + V(0, st.height + 9, 0)), C(255, 255, 255)))
	spot.Transparency = 1
	tag(spot, { { name = "Name", text = "Win the vote to be here!", color = C(255, 214, 60) },
		{ name = "Votes", text = "", font = Enum.Font.Gotham } }, 0, 120, 14)
	return spot
end

-- ── Legend Rides garage ──────────────────────────────────────────────────────

local function garage(m)
	local pads = {}
	-- a wall of wooden crates behind the arc, the sign on it
	local wallAt = O + V(-70, 0, 0)
	-- (two stacks, the way to the Auto Street gate open between them)
	if source("crate") then   -- shipping crates, stacked a little crooked
		for k, z in ipairs({ -23, -13, 13, 23 }) do
			storeModel(m, "crate", CF(wallAt + V(3, 0, z)) * A(0, math.rad(k % 2 == 0 and 3 or -2), 0), 5.4, true)
		end
		for k, z in ipairs({ -18, 18 }) do
			storeModel(m, "crate", CF(wallAt + V(3.3, 5.4, z)) * A(0, math.rad(k == 1 and -4 or 2), 0), 5, true)
		end
	else
		for _, z in ipairs({ -22.5, -13.5, 13.5, 22.5 }) do
			part(m, "Crate", V(5, 5, 9), CF(wallAt + V(0, 2.5, z)), C(190, 140, 85), "WoodPlanks")
		end
		for _, z in ipairs({ -18, 18 }) do
			part(m, "Crate", V(5, 5, 9), CF(wallAt + V(0, 7.5, z)), C(175, 125, 75), "WoodPlanks")
		end
	end
	-- loose crates in front of the wall
	storeModel(m, "crates", CF(wallAt + V(7, 0, -33)) * A(0, math.rad(80), 0), 5, true)
	storeModel(m, "crate", CF(wallAt + V(7, 0, 31)) * A(0, math.rad(20), 0), 4, true)
	-- low over the way to the gate, so the AUTO STREET sign shows over it
	local s = part(m, "LegendSign", V(26, 4, 0.6), CF(wallAt + V(2.8, 9.2, 0)) * A(0, math.rad(90), 0), C(40, 35, 60), "Fabric")
	sign(s, { { text = "🚗 LEGEND RIDES", color = C(255, 214, 60), share = 0.6 },
		{ text = "vote winners' rides · few copies · few days", color = C(230, 230, 245), share = 0.4, font = Enum.Font.GothamBold } },
		C(40, 35, 60), Enum.NormalId.Back)
	for i = 1, LobbyLayout.LEGEND_SLOTS do
		local p = LobbyLayout.legendSpot(i)
		local pad = part(m, "LegendPad_" .. i, V(9, 2, 9), LobbyLayout.facingCentre(p + V(0, 1, 0)), C(185, 135, 80), "WoodPlanks")
		pad:SetAttribute("Slot", i)
		pads[i] = pad
	end
	return pads
end

-- ── Trophy room: a teapot house and the rewards on stools ────────────────────

local REWARD_ICON = { pose = "🙌", trail = "✨" }

local function trophyRoom(m)
	local house = O + V(72, 0, -14)
	ball(m, "Teapot", 22, CF(house + V(0, 10, 0)), C(110, 200, 190), "CeramicTiles")
	cyl(m, "TeapotLid", 10, 2, CF(house + V(0, 20.5, 0)), C(110, 200, 190), "CeramicTiles")
	ball(m, "TeapotKnob", 2.4, CF(house + V(0, 22.5, 0)), C(255, 200, 40), "Foil")
	part(m, "Spout", V(10, 3, 3), CF(house + V(-4, 9, -12)) * A(0, math.rad(60), math.rad(30)), C(110, 200, 190), "CeramicTiles")
	local door = part(m, "Door", V(0.4, 7, 5), CF(house + V(-10.6, 3.5, 0)), C(150, 100, 60), "Wood")
	door.CanCollide = false
	local s = part(m, "TrophySign", V(24, 4, 0.6), CF(house + V(-12, 24, 0)) * A(0, math.rad(90), 0), C(255, 245, 225), "Plaster")
	sign(s, { { text = "🏆 TROPHY ROOM", color = C(30, 120, 110), share = 0.6 },
		{ text = "earn them · nobody can buy them", color = C(90, 70, 50), share = 0.4, font = Enum.Font.GothamBold } },
		C(255, 245, 225))   -- the front (-Z, turned to -X): towards the plaza
	local ShopHat = require(ServerScriptService.Modules.ShopHat)
	for i, a in ipairs(Achievements.LIST) do
		if i > LobbyLayout.TROPHY_SLOTS then break end
		local p = LobbyLayout.trophySpot(i)
		cyl(m, "Stool", 3.6, 3, CF(p + V(0, 1.5, 0)), C(230, 175, 50), "Metal")
		local it = Cosmetics.get(a.reward)
		local design = it and it.hat and HatDesigns.get(it.hat)
		local headAt = p + V(0, 4.1, 0)
		local holder
		if design then
			holder = ball(m, "Head", 2, LobbyLayout.facingCentre(headAt), C(240, 225, 205), "Plaster")
			local hat = ShopHat.build(design, LobbyLayout.facingCentre(headAt + V(0, 1, 0)), 2 / HatDesigns.HEAD)
			for _, hp in ipairs(hat:GetChildren()) do
				if hp:IsA("BasePart") then hp.Anchored = true end
			end
			hat.Name = "Trophy_" .. a.key
			hat.Parent = m
		else
			holder = deco(part(m, "Plinth", V(2, 2, 2), CF(headAt), C(255, 245, 225)))
			tag(holder, { { text = REWARD_ICON[it and it.category or ""] or "🏆" } }, 1.4, 40, 2.4).Size = UDim2.new(2.4, 0, 2.4, 0)
		end
		local label = deco(part(m, "TrophyLabel", V(1, 1, 1), CF(p + V(0, 8, 0)), C(255, 255, 255)))
		label.Transparency = 1
		tag(label, { { text = it and it.name or a.name, color = C(255, 214, 60) }, { text = a.text, font = Enum.Font.Gotham } }, 0, 14, 4.5)
		local pp = prompt(holder, "See awards", a.name, "awards")
		pp.MaxActivationDistance = 9
	end
end

-- ── The cardboard-box shop ───────────────────────────────────────────────────

local function shop(m)
	local p = LobbyLayout.SHOP
	local face = LobbyLayout.facingCentre(p)
	local yaw = face - face.Position
	local cf = CF(p) * yaw
	if storeModel(m, "shop_awning", cf * CF(0, 0, 2), 13, true) then
		local counter = part(m, "Counter", V(10, 3.4, 1.6), cf * CF(0, 1.7, -7.4), C(150, 100, 60), "WoodPlanks")
		local s = part(m, "ShopSign", V(8, 2, 0.4), cf * CF(0, 4.4, -8.3), C(255, 245, 225), "Plaster")
		sign(s, { { text = "🛒 SHOP", color = C(200, 60, 60) } })
		prompt(counter, "Open shop", "Junk Town Shop", "shop")
		return
	end
	part(m, "ShopBox", V(14, 10, 12), cf * CF(0, 5, 2), C(200, 155, 100), "Cardboard")
	part(m, "Tape", V(14.1, 1.2, 12.1), cf * CF(0, 9.3, 2), C(225, 200, 150), "SmoothPlastic")
	for _, s in ipairs({ -1, 1 }) do   -- open flaps
		part(m, "Flap", V(14, 0.3, 5), cf * CF(0, 10.6, 2 + s * 7.5) * A(math.rad(s * 35), 0, 0), C(195, 150, 95), "Cardboard")
	end
	for i = 0, 6 do   -- a striped awning over the counter
		part(m, "Awning", V(2, 0.3, 4), cf * CF(-6 + i * 2, 8.4, -5.5) * A(math.rad(-20), 0, 0),
			i % 2 == 0 and C(230, 70, 70) or C(255, 250, 245))
	end
	local counter = part(m, "Counter", V(12, 3.4, 2), cf * CF(0, 1.7, -4.6), C(150, 100, 60), "Wood")
	local s = part(m, "ShopSign", V(10, 2.6, 0.4), cf * CF(0, 6.6, -4.3), C(255, 245, 225), "SmoothPlastic")
	sign(s, { { text = "🛒 SHOP", color = C(200, 60, 60) } })
	prompt(counter, "Open shop", "Junk Town Shop", "shop")
end

-- ── Junk houses, lamps, bunting, trees, props ────────────────────────────────

local function house(m, kind, cf, colour)
	if kind == "can" then
		cyl(m, "CanHouse", 9, 11, cf * CF(0, 5.5, 0), C(200, 205, 215), "Metal")
		cyl(m, "CanLabel", 9.1, 4, cf * CF(0, 5, 0), colour, "SmoothPlastic")
		cyl(m, "CanLid", 9.4, 0.6, cf * CF(0, 11.2, 0), C(180, 185, 195), "Metal")
		part(m, "Door", V(2.6, 4.4, 0.3), cf * CF(0, 2.2, -4.45), C(120, 80, 50), "Wood")
		part(m, "Window", V(2, 2, 0.3), cf * CF(0, 8.6, -4.4), C(255, 240, 160), "Neon")
	elseif kind == "boot" then
		part(m, "BootLeg", V(6, 11, 6), cf * CF(0, 5.5, 2), colour, "Fabric")
		part(m, "BootToe", V(6, 4, 6), cf * CF(0, 2, -3.5), colour, "Fabric")
		ball(m, "ToeCap", 6, cf * CF(0, 2.2, -6), colour, "Fabric")
		part(m, "Sole", V(6.6, 0.8, 13), cf * CF(0, 0.4, -1.2), C(60, 45, 35))
		part(m, "Window", V(2, 2, 0.3), cf * CF(0, 7.5, -1.1), C(255, 240, 160), "Neon")
		for k = 0, 3 do part(m, "Lace", V(4, 0.25, 0.3), cf * CF(0, 4 + k * 1.6, -1.05), C(250, 250, 250)) end
	else
		part(m, "BoxHouse", V(9, 8, 9), cf * CF(0, 4, 0), C(200, 155, 100), "Cardboard")
		part(m, "Roof", V(10, 0.4, 7), cf * CF(0, 9.4, -2.3) * A(math.rad(-30), 0, 0), colour, "Cardboard")
		part(m, "Roof", V(10, 0.4, 7), cf * CF(0, 9.4, 2.3) * A(math.rad(30), 0, 0), colour, "Cardboard")
		part(m, "Door", V(2.6, 4.4, 0.3), cf * CF(0, 2.2, -4.55), C(120, 80, 50), "Wood")
		part(m, "Window", V(2.4, 2, 0.3), cf * CF(2.5, 5.6, -4.55), C(255, 240, 160), "Neon")
		part(m, "Arrow", V(0.3, 2, 0.3), cf * CF(-2.5, 5.6, -4.55), C(60, 40, 30))   -- "this way up"
	end
end

local function lamps(m)
	local tops = {}
	local n = LobbyLayout.LAMPS
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local p = O + V(math.cos(a) * LobbyLayout.LAMP_RADIUS, 0, math.sin(a) * LobbyLayout.LAMP_RADIUS)
		local lamp = storeModel(m, i % 2 == 0 and "lamp_fancy" or "lamp_plain",
			LobbyLayout.facingCentre(p) * A(0, math.rad(90), 0), 13, false)
		local light = Instance.new("PointLight")
		light.Color = C(255, 220, 160)
		light.Range = 18
		light.Brightness = 0.8
		if lamp then
			local anchor = deco(part(m, "LampLight", V(0.4, 0.4, 0.4), CF(p + V(0, 11.5, 0)), C(255, 230, 150)))
			anchor.Transparency = 1
			light.Parent = anchor
			tops[i + 1] = p + V(0, 10.6, 0)
		else
			cyl(m, "LampPole", 0.6, 11, CF(p + V(0, 5.5, 0)), C(205, 210, 220), "Metal")
			part(m, "ForkHead", V(2.2, 0.6, 0.4), CF(p + V(0, 11.2, 0)), C(205, 210, 220), "Metal")
			for t = -1, 1 do part(m, "Tine", V(0.3, 1.6, 0.3), CF(p + V(t * 0.8, 12.3, 0)), C(205, 210, 220), "Metal") end
			local bulb = deco(ball(m, "Lantern", 1.6, CF(p + V(0, 13.5, 0)), C(255, 230, 150), "Neon"))
			light.Parent = bulb
			tops[i + 1] = p + V(0, 12.8, 0)
		end
	end
	-- bunting: little flags hung from a sagging string, lamp to lamp
	for i = 1, n do
		local a, b = tops[i], tops[i % n + 1]
		local pts = {}
		for k = 0, 6 do
			local t = k / 6
			pts[k] = a + (b - a) * t - V(0, math.sin(t * math.pi) * 1.6, 0)
		end
		for k = 1, 6 do
			local p0, p1 = pts[k - 1], pts[k]
			local mid = (p0 + p1) / 2
			deco(part(m, "String", V(0.08, 0.08, (p1 - p0).Magnitude), CFrame.lookAt(mid, p1), C(250, 250, 250)))
		end
		for k = 1, 5 do
			local along = (pts[k + 1] - pts[k - 1]).Unit
			local q = pts[k] - V(0, 0.55, 0)
			deco(part(m, "Flag", V(0.9, 0.9, 0.06), CFrame.lookAt(q, q + along) * A(0, math.pi / 2, math.rad(45)),
				PASTEL[(i + k) % #PASTEL + 1]))
		end
	end
end

local TREE_KINDS = { "tree_round", "tree_puff", "tree_tall" }

local function trees(m)
	for i, a in ipairs(LobbyLayout.OUTER_TREES) do
		local h = 18 + (i * 7 % 3) * 4
		storeModel(m, TREE_KINDS[i % 3 + 1], rim(a, LobbyLayout.OUTER_TREE_RADIUS) * A(0, math.rad(i * 47), 0), h, false)
	end
	for i, p in ipairs(LobbyLayout.TREES) do
		if storeModel(m, TREE_KINDS[i % 3 + 1], CF(p) * A(0, math.rad(i * 61), 0), 14, false) then continue end
		cyl(m, "Handle", 0.5, 8, CF(p + V(0, 4, 0)), C(80, 60, 50), "Wood")
		deco(cyl(m, "Canopy", 9, 0.6, CF(p + V(0, 8.2, 0)), PASTEL[i % #PASTEL + 1], "SmoothPlastic"))
		deco(cyl(m, "Canopy2", 5, 0.8, CF(p + V(0, 8.8, 0)), PASTEL[(i + 2) % #PASTEL + 1], "SmoothPlastic"))
		deco(ball(m, "Tip", 0.7, CF(p + V(0, 9.5, 0)), C(60, 60, 70)))
		part(m, "Crook", V(0.5, 0.5, 1.6), CF(p + V(0, 0.25, -0.6)), C(80, 60, 50), "Wood")
	end
end

local function props(m)
	local rnd = Random.new(11)
	for _, p in ipairs(LobbyLayout.BENCHES) do
		storeModel(m, "bench", LobbyLayout.facingCentre(p) * A(0, math.rad(180), 0), 3.4, true)
	end
	storeModel(m, "stall", LobbyLayout.facingCentre(LobbyLayout.STALL), 11, true)
	storeModel(m, "junk_pile", LobbyLayout.facingCentre(LobbyLayout.JUNK_PILE), 5, true)
	for i, p in ipairs(LobbyLayout.SCRAP_CARS) do
		storeModel(m, "scrap_car", LobbyLayout.facingCentre(p) * A(0, math.rad(i == 1 and 70 or 110), 0), 4.8, true)
	end
	local spots = { V(-20, 0, 12), V(22, 0, 10), V(-46, 0, 34), V(38, 0, 14), V(-6, 0, -26), V(8, 0, 28), V(-30, 0, -12) }
	for i, s in ipairs(spots) do
		local p = O + s
		local kind = i % 3
		if kind == 0 and source("barrel_rusty") then   -- two barrels
			storeModel(m, "barrel_rusty", CF(p + V(-1.2, 0, 0)), 3.6, true)
			storeModel(m, "barrel_metal", CF(p + V(1.4, 0, 0.6)) * A(0, 1, 0), 3.2, true)
		elseif kind == 2 and source("pot_round") then   -- flowers
			storeModel(m, "pot_round", CF(p) * A(0, i, 0), 3.4, true)
		elseif kind == 0 then   -- a traffic cone
			part(m, "ConeBase", V(2.4, 0.3, 2.4), CF(p + V(0, 0.15, 0)), C(255, 120, 30))
			cyl(m, "Cone", 1.4, 2.4, CF(p + V(0, 1.4, 0)), C(255, 120, 30))
			cyl(m, "Stripe", 1.45, 0.4, CF(p + V(0, 1.6, 0)), C(250, 250, 250))
		elseif kind == 1 then   -- a stack of tyres
			for k = 0, rnd:NextInteger(1, 3) do tyre(m, CF(p + V(0, 0.65 + k * 1.3, 0)), 3.4) end
		else   -- a rubber duck
			deco(ball(m, "Duck", 2, CF(p + V(0, 1, 0)), C(255, 214, 30)))
			deco(ball(m, "DuckHead", 1.2, CF(p + V(-0.6, 2.3, 0)), C(255, 214, 30)))
			deco(part(m, "Beak", V(0.7, 0.3, 0.5), CF(p + V(-1.3, 2.2, 0)), C(255, 130, 20)))
		end
	end
end

-- ── Townsfolk (Shared/LobbyNpcs) ─────────────────────────────────────────────

-- Root + head + torso, where an R15 avatar cannot be made (offline tests).
local function plainRig(shirt)
	local char = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V(2, 2, 1)
	root.Color = shirt
	root.Parent = char
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = V(1.2, 1.2, 1.2)
	head.Color = C(255, 220, 180)
	head.CFrame = root.CFrame * CF(0, 1.6, 0)
	head.Parent = char
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, head
	w.Parent = root
	Instance.new("Humanoid").Parent = char
	char.PrimaryPart = root
	return char
end

LobbyHub.NPC_BLOCK = V(2.6, 6, 0)   -- the post round a townsperson: width (X = Z), height

local function npcs(m)
	local Players = game:GetService("Players")
	local ShopHat = require(ServerScriptService.Modules.ShopHat)
	for _, n in ipairs(LobbyNpcs.LIST) do
		local ok, rig = pcall(function()
			local desc = Instance.new("HumanoidDescription")
			desc.HeadColor = C(255, 220, 180)
			desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
			desc.TorsoColor = n.shirt
			desc.LeftLegColor, desc.RightLegColor = C(60, 60, 80), C(60, 60, 80)
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or not rig then rig = plainRig(n.shirt) end
		rig.Name = "Npc_" .. n.id
		local animate = rig:FindFirstChild("Animate")
		if animate then animate:Destroy() end
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
		end
		local root = rig:FindFirstChild("HumanoidRootPart")
		local feet = O + n.at
		local hip = hum and hum.HipHeight or 2
		local standAt = feet + V(0, hip + (root and root.Size.Y / 2 or 1), 0)
		local look = n.face and O + n.face + V(0, standAt.Y - O.Y, 0)
		rig:PivotTo(look and CFrame.lookAt(standAt, look) or LobbyLayout.facingCentre(standAt))
		-- the body is looked through; an invisible post blocks the way (a body
		-- whose torso collided and limbs did not let a walker into it, stuck
		-- for good: Studio lobby-tour 2026-11-17, at Tom)
		for _, p in ipairs(rig:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = p == root
				p.CanCollide = false
			end
		end
		local post = part(m, "NpcBlock", V(LobbyHub.NPC_BLOCK.X, LobbyHub.NPC_BLOCK.Y, LobbyHub.NPC_BLOCK.X),
			CF(feet + V(0, LobbyHub.NPC_BLOCK.Y / 2, 0)), C(255, 255, 255), "SmoothPlastic")
		post.Transparency = 1
		post.CanQuery = false
		post.CanTouch = false
		post:SetAttribute("Npc", n.id)
		rig.Parent = m
		pcall(ShopHat.wear, rig, n.hat)
		if root then
			local pp = prompt(root, "Talk", n.name, nil)
			pp:SetAttribute("Talk", n.id)
			pp.MaxActivationDistance = 10
			tag(root, { { text = n.name, color = C(255, 214, 60) }, { text = n.title, font = Enum.Font.Gotham } }, 3.6, 20, 4)
		end
		rig:SetAttribute("Npc", n.id)
	end
end

-- ── Auto Street (Shared/LobbyLayout.STREET, 2026-11-18) ──────────────────────

local RARITY_COLOUR = {
	Common = C(200, 200, 200), Uncommon = C(80, 200, 80), Rare = C(100, 160, 255), Epic = C(200, 100, 255),
}
LobbyHub.RARITY_COLOUR = RARITY_COLOUR

-- a block over rectangle `r` ({ x0, x1, z0, z1 } off ORIGIN), `h` thick, its
-- top `top` studs over the plaza floor
local function slab(m, name, r, top, h, colour, material)
	return part(m, name, V(r[2] - r[1], h, r[4] - r[3]),
		CF(O + V((r[1] + r[2]) / 2, top - h / 2, (r[3] + r[4]) / 2)), colour, material)
end

-- an invisible wall from `a` to `b` (offsets off ORIGIN on the floor) with a
-- low wooden rail along it
local function wallLine(m, a, b, rail)
	local H = LobbyLayout.STREET.wallHeight
	local len = (b - a).Magnitude
	local mid = O + (a + b) / 2
	local look = CFrame.lookAt(mid, O + b)
	local w = part(m, "StreetWall", V(2, H, len), look + V(0, H / 2, 0), C(255, 255, 255))
	w.Transparency = 1
	w.CanQuery = false
	if rail ~= false then
		for _, y in ipairs({ 1.4, 2.6 }) do
			deco(part(m, "Rail", V(0.3, 0.35, len), look + V(0, y, 0), C(150, 105, 70), "Wood"))
		end
		for k = 0, math.floor(len / 16) do
			local at = a + (b - a).Unit * math.min(k * 16, len)
			deco(part(m, "Post", V(0.6, 3.2, 0.6), CF(O + at + V(0, 1.6, 0)), C(130, 90, 60), "Wood"))
		end
	end
	return w
end

local function street(m)
	local S = LobbyLayout.STREET
	local L, T, R = S.lane, S.lot, S.road
	-- ground: the lane over the island's edge and the lot past it, rock under
	slab(m, "StreetGrass", { L[1], -90, L[3], L[4] }, -0.03, 4, C(130, 200, 110), "Grass")
	slab(m, "StreetGrass", T, -0.03, 4, C(130, 200, 110), "Grass")
	slab(m, "StreetRock", { T[1] + 6, T[2] - 6, T[3] + 6, T[4] - 6 }, -4, 14, C(115, 100, 88), "Slate")
	slab(m, "Road", R, 0.06, 0.2, C(70, 70, 78), "Asphalt")
	for x = R[2] - 14, R[1] + 8, -14 do   -- the dashed middle line
		deco(part(m, "RoadLine", V(6, 0.02, 0.5), CF(O + V(x, 0.07, 0)), C(250, 210, 60), "SmoothPlastic"))
	end
	-- walls round it all; only the gate opens onto the plaza
	wallLine(m, V(-70, 0, -L[4]), V(L[1] + 2, 0, -L[4]))
	wallLine(m, V(-70, 0, L[4]), V(L[1] + 2, 0, L[4]))
	wallLine(m, V(T[2], 0, L[4]), V(T[2], 0, T[4]))
	wallLine(m, V(T[2], 0, T[3]), V(T[2], 0, -L[4]))
	wallLine(m, V(T[2], 0, T[4]), V(T[1], 0, T[4]))
	wallLine(m, V(T[2], 0, T[3]), V(T[1], 0, T[3]))
	-- the west wall, open at the road's end onto the Junk GP grandstand's walk
	local gap = S.standGap
	wallLine(m, V(T[1], 0, T[3]), V(T[1], 0, gap[1]))
	wallLine(m, V(T[1], 0, gap[2]), V(T[1], 0, T[4]))
	-- the gate: two posts and a sign over the way out of the fence
	local gx = -LobbyLayout.WALL_RADIUS - 1
	for _, z in ipairs({ -LobbyLayout.GATE_HALF - 1.5, LobbyLayout.GATE_HALF + 1.5 }) do
		cyl(m, "GatePost", 1.2, 19, CF(O + V(gx, 9.5, z)), C(205, 210, 220), "Metal")
	end
	-- Junk Motors red, over the dark Legend Rides sign in front of it
	local red = C(200, 40, 50)
	local board = part(m, "StreetSign", V(19, 3.6, 0.6), at(O + V(gx, 17, 0), -90), red, "Metal")
	sign(board, { { text = "🚗 AUTO STREET", color = C(255, 255, 255), share = 0.62 },
		{ text = "JUNK MOTORS · NEW CARS", color = C(255, 225, 150), share = 0.38, font = Enum.Font.GothamBold } }, red)
	sign(board, { { text = "JUNK TOWN PLAZA", color = C(255, 255, 255) } }, red, Enum.NormalId.Back)
	-- street lamps along the road, benches on the showroom's side, a few trees
	for k, x in ipairs({ -128, -168, -208, -248, -288 }) do
		storeModel(m, "lamp_plain", CF(O + V(x, 0, k % 2 == 0 and 12 or -13)) * A(0, math.rad(90), 0), 13, false)
	end
	for _, x in ipairs({ -188, -228 }) do
		storeModel(m, "bench", CF(O + V(x, 0, -15.5)), 3.4, true)
	end
	for i, p in ipairs({ V(-122, 0, -40), V(-122, 0, -66), V(-286, 0, -68) }) do
		storeModel(m, TREE_KINDS[i % 3 + 1], CF(O + p) * A(0, math.rad(i * 53), 0), 16 + (i % 2) * 4, false)
	end
end

-- Junk Auto Mart: the used-car lot (LobbyLayout.USED_LOT). The cars come
-- and go with the listings (LobbyHub.setUsedCars); built here is the lot:
-- gravel and parking lines, the arch, a guard booth and the directory
-- kiosk, the dealers' container offices, a car wash, bunting, and the
-- parking tower (a deck up a ramp, a garage under it).
LobbyHub.DEALERS = { "HONEST HANK'S", "LUCKY LOT", "RUSTY & SONS" }

local function usedLot(m)
	local U = LobbyLayout.USED_LOT
	local b = U.box
	slab(m, "LotGravel", b, 0.05, 0.3, C(150, 145, 140), "Pebble")
	-- parking lines either side of every outdoor bay
	for col = 0, U.columns do
		local x = U.firstX + (col - 0.5) * U.stepX
		for row, z in ipairs(U.rows) do
			deco(part(m, "BayLine", V(0.3, 0.02, 7), CF(O + V(x, 0.06, z)), C(245, 245, 245), "SmoothPlastic"))
		end
	end
	-- the way in: an arch, the guard's booth, the directory kiosk
	local ex = U.entranceX
	for _, dx in ipairs({ -6, 6 }) do
		cyl(m, "ArchPost", 1, 13, CF(O + V(ex + dx, 6.5, b[3] + 1)), C(250, 190, 40), "Metal")
	end
	local arch = part(m, "MartSign", V(14, 3, 0.5), CF(O + V(ex, 12, b[3] + 1)), C(250, 190, 40), "Metal")
	sign(arch, { { text = "JUNK AUTO MART", color = C(40, 30, 20), share = 0.6 },
		{ text = "USED LEGEND RIDES", color = C(120, 40, 20), share = 0.4, font = Enum.Font.GothamBold } }, C(250, 190, 40))
	sign(arch, { { text = "THANK YOU, COME AGAIN", color = C(40, 30, 20) } }, C(250, 190, 40), Enum.NormalId.Back)
	part(m, "GuardBooth", V(4, 7, 4), CF(O + V(ex + 9, 3.5, b[3] + 6)), C(235, 235, 240), "SmoothPlastic")
	local gw = part(m, "GuardWindow", V(3, 2, 0.2), CF(O + V(ex + 9, 4.6, b[3] + 3.9)), C(150, 200, 230), "Glass")
	gw.Transparency = 0.3
	part(m, "Barrier", V(0.4, 0.4, 7), CF(O + V(ex + 6.5, 3, b[3] + 5)) * A(math.rad(-60), 0, 0), C(230, 60, 50), "SmoothPlastic")
	-- the directory stands by the guard's booth, clear of the first car's stand
	local kiosk = part(m, "Kiosk", V(3.4, 6, 0.8), CF(O + V(ex + 6, 3, b[3] + 14)), C(40, 45, 55), "Metal")
	local dirLines = { { text = "LOT DIRECTORY", color = C(255, 214, 60), share = 0.2 } }
	for i, d in ipairs(LobbyHub.DEALERS) do
		table.insert(dirLines, { text = d, color = C(255, 255, 255), share = 0.18, font = Enum.Font.GothamBold })
	end
	table.insert(dirLines, { text = "TOWER: UP THE RAMP", color = C(150, 220, 255), share = 0.18, font = Enum.Font.GothamBold })
	sign(kiosk, dirLines, C(40, 45, 55))
	-- the dealers' container offices, each with its row of cars in front
	local tones = { C(60, 120, 190), C(200, 80, 60), C(70, 150, 90) }
	for i, x in ipairs(U.offices) do
		local cf = CF(O + V(x, 0, U.officeZ))
		part(m, "Office", V(12, 7, 6), cf * CF(0, 3.5, 0), tones[i], "CorrodedMetal")
		part(m, "OfficeDoor", V(2.4, 5, 0.2), cf * CF(-3, 2.5, -3.05), C(60, 60, 70), "Metal")
		local w = part(m, "OfficeWindow", V(4, 2.4, 0.2), cf * CF(2.2, 4, -3.05), C(170, 210, 235), "Glass")
		w.Transparency = 0.25
		local plate = part(m, "OfficeSign", V(10, 1.6, 0.3), cf * CF(0, 8, -2.6), C(255, 250, 235), "SmoothPlastic")
		sign(plate, { { text = LobbyHub.DEALERS[i], color = tones[i] } }, C(255, 250, 235))
	end
	-- a car wash by the entrance
	local wx, wz = ex + 2, U.officeZ
	for _, dz in ipairs({ -4, 4 }) do
		part(m, "WashFrame", V(10, 0.8, 0.8), CF(O + V(wx, 9, wz + dz)), C(60, 140, 220), "Metal")
		for _, dx in ipairs({ -4.6, 4.6 }) do
			part(m, "WashPost", V(0.8, 9, 0.8), CF(O + V(wx + dx, 4.5, wz + dz)), C(60, 140, 220), "Metal")
		end
	end
	for _, dx in ipairs({ -3, 3 }) do
		deco(cyl(m, "WashBrush", 2.4, 7, CF(O + V(wx + dx, 4.3, wz)), C(80, 170, 255), "Fabric"))
	end
	local wash = part(m, "WashSign", V(9, 1.6, 0.3), CF(O + V(wx, 10.4, wz - 4.4)), C(255, 255, 255), "SmoothPlastic")
	sign(wash, { { text = "CAR WASH", color = C(60, 140, 220) } }, C(255, 255, 255))
	-- bunting over the front of the lot, pole to pole
	local poles = { O + V(b[2] - 3, 0, b[3] + 1), O + V(U.firstX + U.columns * U.stepX, 0, b[3] + 1) }
	for _, p in ipairs(poles) do cyl(m, "FlagPole", 0.5, 12, CF(p + V(0, 6, 0)), C(220, 220, 225), "Metal") end
	local a0, a1 = poles[1] + V(0, 11.5, 0), poles[2] + V(0, 11.5, 0)
	local n = 22
	for k = 1, n - 1 do
		local t = k / n
		local q = a0 + (a1 - a0) * t - V(0, math.sin(t * math.pi) * 2.5, 0)
		deco(part(m, "Pennant", V(0.06, 1.2, 1.2), CF(q - V(0, 0.6, 0)) * A(math.rad(45), 0, 0), PASTEL[k % #PASTEL + 1]))
	end
	deco(part(m, "PennantString", V((a1 - a0).Magnitude, 0.08, 0.08), CF((a0 + a1) / 2 - V(0, 1.6, 0)), C(250, 250, 250)))
	-- the parking tower: a deck up a ramp, rails round it, a garage under it
	local T = U.tower
	local tb = T.box
	local deck = part(m, "TowerDeck", V(tb[2] - tb[1], 1, tb[4] - tb[3]),
		CF(O + V((tb[1] + tb[2]) / 2, T.deck - 0.5, (tb[3] + tb[4]) / 2)), C(170, 170, 175), "Concrete")
	for _, x in ipairs({ tb[1] + 1, (tb[1] + tb[2]) / 2, tb[2] - 1 }) do
		for _, z in ipairs({ tb[3] + 1, tb[4] - 1 }) do
			part(m, "TowerPillar", V(1.6, T.deck - 1, 1.6), CF(O + V(x, (T.deck - 1) / 2, z)), C(160, 160, 165), "Concrete")
		end
	end
	local R = T.ramp
	local rampLen = math.sqrt((R.x1 - R.x0) ^ 2 + T.deck ^ 2)
	part(m, "TowerRamp", V(R.z1 - R.z0, 1, rampLen),
		CF(O + V((R.x0 + R.x1) / 2, T.deck / 2 - 0.5, (R.z0 + R.z1) / 2))
			* A(0, math.rad(-90), 0) * A(-math.atan2(T.deck, R.x1 - R.x0), 0, 0), C(170, 170, 175), "Concrete")
	local function rail(a, c)
		local len = (c - a).Magnitude
		part(m, "TowerRail", V(0.4, 3, len), CFrame.lookAt(O + (a + c) / 2, O + c) + V(0, T.deck + 1.5, 0),
			C(250, 190, 40), "Metal")
	end
	rail(V(tb[1], 0, tb[3]), V(tb[2], 0, tb[3]))           -- north
	rail(V(tb[1], 0, tb[3]), V(tb[1], 0, tb[4]))           -- west
	rail(V(tb[1], 0, tb[4]), V(tb[2], 0, tb[4]))           -- south
	rail(V(tb[2], 0, tb[3]), V(tb[2], 0, R.z0))            -- east, open where the ramp comes up
	local towerSign = part(m, "TowerSign", V(20, 2.4, 0.4), CF(O + V((tb[1] + tb[2]) / 2, T.deck + 4.6, tb[3])), C(40, 45, 55), "Metal")
	sign(towerSign, { { text = "MORE UPSTAIRS", color = C(255, 214, 60) } }, C(40, 45, 55))
	-- under the deck: a garage with a car lift
	for _, dx in ipairs({ -4, 4 }) do
		part(m, "LiftPost", V(0.8, 6, 0.8), CF(O + V(-278 + dx, 3, 34)), C(220, 60, 50), "Metal")
	end
	part(m, "LiftArm", V(9, 0.5, 4), CF(O + V(-278, 3.2, 34)), C(80, 80, 90), "Metal")
	local garageSign = part(m, "GarageSign", V(9, 1.8, 0.3), CF(O + V(-278, T.deck - 2.2, tb[3] + 0.4)), C(255, 255, 255))
	sign(garageSign, { { text = "GARAGE", color = C(220, 60, 50) } }, C(255, 255, 255), Enum.NormalId.Back)
	sign(garageSign, { { text = "GARAGE", color = C(220, 60, 50) } }, C(255, 255, 255))
	-- before any ride is on sale, the lot says how one gets here
	local empty = part(m, "LotEmptySign", V(10, 3, 0.3), CF(O + V(U.firstX - 30, 3.5, b[3] + 2.5)), C(255, 250, 235))
	sign(empty, { { text = "WIN THE RIDE SHOW VOTE", color = C(120, 40, 20), share = 0.55 },
		{ text = "and your ride parks right here", color = C(60, 50, 40), share = 0.45, font = Enum.Font.GothamBold } },
		C(255, 250, 235))
	deco(empty)
end

-- Junk Motors: a glass showroom on the road's north side, every new car
-- (Shared/NewCars) on a white plinth with its name, price, and the prompts
-- "Try on" (E) and "Buy" (F, held); LobbyManager wires them to CarDealer.
local function showroom(m)
	local NewCars = require(ReplicatedStorage.Shared.NewCars)
	local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
	local S = LobbyLayout.SHOWROOM
	local x0, x1, z0, z1 = S.box[1], S.box[2], S.box[3], S.box[4]
	local H = S.height
	local white, glassC = C(238, 238, 244), C(190, 225, 255)
	local floor = slab(m, "ShowroomFloor", S.box, 0.2, 0.6, C(245, 245, 250), "Marble")
	floor.Reflectance = 0.12
	part(m, "ShowroomWall", V(x1 - x0, H, 1), CF(O + V((x0 + x1) / 2, H / 2, z0 - 0.5)), white, "SmoothPlastic")
	for _, x in ipairs({ x0 - 0.5, x1 + 0.5 }) do
		part(m, "ShowroomWall", V(1, H, z1 - z0 + 2), CF(O + V(x, H / 2, (z0 + z1) / 2)), white, "SmoothPlastic")
	end
	-- the glass front, open at the doors
	local function glass(xa, xb, ya, yb)
		local g = part(m, "ShowroomGlass", V(xb - xa, yb - ya, 0.4), CF(O + V((xa + xb) / 2, (ya + yb) / 2, z1 + 0.2)),
			glassC, "Glass")
		g.Transparency = 0.65
		g.CastShadow = false
		return g
	end
	local doors = table.clone(S.doors)
	table.sort(doors)
	local from, w = x0, S.doorWidth
	for _, d in ipairs(doors) do
		glass(from, d - w / 2, 0, H)
		glass(d - w / 2, d + w / 2, 10, H)   -- over the doorway
		for _, s2 in ipairs({ -1, 1 }) do
			part(m, "DoorFrame", V(0.6, H, 0.8), CF(O + V(d + s2 * w / 2, H / 2, z1 + 0.2)), C(60, 60, 70), "Metal")
		end
		from = d + w / 2
	end
	glass(from, x1, 0, H)
	part(m, "ShowroomRoof", V(x1 - x0 + 2, 1, z1 - z0 + 3), CF(O + V((x0 + x1) / 2, H + 0.5, (z0 + z1) / 2 + 0.5)),
		white, "SmoothPlastic")
	local fascia = part(m, "MotorsSign", V(70, 5, 0.6), CF(O + V((x0 + x1) / 2, H + 3.5, z1 + 0.6)), C(200, 40, 50), "SmoothPlastic")
	sign(fascia, { { text = "JUNK MOTORS", color = C(255, 255, 255), share = 0.66 },
		{ text = "NEW CARS · FIXED PRICES", color = C(255, 225, 150), share = 0.34, font = Enum.Font.GothamBold } },
		C(200, 40, 50), Enum.NormalId.Back)
	-- light strips under the roof over each walkway
	for _, z in ipairs({ (z1 + S.rows[1]) / 2 - 1.5, (S.rows[1] + S.rows[2]) / 2, (S.rows[2] + S.rows[3]) / 2, (S.rows[3] + z0) / 2 }) do
		local strip = deco(part(m, "LightStrip", V(x1 - x0 - 6, 0.3, 1), CF(O + V((x0 + x1) / 2, H - 0.2, z)), C(255, 255, 250), "Neon"))
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 18
		light.Angle = 120
		light.Brightness = 1.2
		light.Parent = strip
	end
	-- the cars' plinths, cheapest by the door; a banner over each rarity
	local catalog = NewCars.catalog(ItemConfig)
	local spans = {}
	for i, c in ipairs(catalog) do
		if i > LobbyLayout.CAR_SLOTS then break end
		local spot = LobbyLayout.carSpot(i)
		local colour = RARITY_COLOUR[c.rarity] or C(255, 255, 255)
		local plinth = part(m, "CarPad_" .. i, S.plinth, CF(spot + V(0, 0.2 + S.plinth.Y / 2, 0)), C(250, 250, 252), "Marble")
		plinth.Reflectance = 0.2
		plinth:SetAttribute("Car", c.item)
		deco(part(m, "PlinthGlow", V(S.plinth.X + 0.4, 0.15, S.plinth.Z + 0.4), CF(spot + V(0, 0.27, 0)), colour, "Neon"))
		tag(plinth, { { text = c.item, color = colour }, { text = string.format("%d coins", c.price), font = Enum.Font.GothamBold } },
			5.5, 26, 5)
		local try = prompt(plinth, "Try on", c.item, nil)
		try:SetAttribute("CarAction", "try")
		try:SetAttribute("Car", c.item)
		try.MaxActivationDistance = 7
		local buy = prompt(plinth, string.format("Buy · %d coins", c.price), c.item, nil)
		buy:SetAttribute("CarAction", "buy")
		buy:SetAttribute("Car", c.item)
		buy.MaxActivationDistance = 7
		buy.HoldDuration = 0.8
		buy.KeyboardKeyCode = Enum.KeyCode.F
		buy.GamepadKeyCode = Enum.KeyCode.ButtonY
		local sp = spans[c.rarity] or { lo = spot.X, hi = spot.X, price = c.price }
		sp.lo, sp.hi = math.min(sp.lo, spot.X), math.max(sp.hi, spot.X)
		spans[c.rarity] = sp
	end
	for rarity, sp in pairs(spans) do
		local banner = deco(part(m, "TierBanner", V(sp.hi - sp.lo + 8, 2.4, 0.3),
			CF(O + V((sp.lo + sp.hi) / 2 - O.X, H - 2.2, z1 - 1.2)), RARITY_COLOUR[rarity] or white, "SmoothPlastic"))
		sign(banner, { { text = string.format("%s · %d COINS", rarity:upper(), sp.price), color = C(30, 30, 40) } },
			RARITY_COLOUR[rarity], Enum.NormalId.Back)
		sign(banner, { { text = string.format("%s · %d COINS", rarity:upper(), sp.price), color = C(30, 30, 40) } },
			RARITY_COLOUR[rarity])
	end
end

-- ── Build ────────────────────────────────────────────────────────────────────

--- Builds Junk Town into `parent` (workspace). Returns the model; its
-- attribute-less children hold the parts LobbyManager fills.
function LobbyHub.build(parent)
	local old = parent:FindFirstChild(LobbyHub.NAME)
	if old then old:Destroy() end
	local m = Instance.new("Model")
	m.Name = LobbyHub.NAME
	ground(m)
	fence(m)
	fenceModels(m)
	arch(m)
	spawnPad(m)
	fountain(m)
	board(m)
	stage(m)
	garage(m)
	trophyRoom(m)
	shop(m)
	street(m)
	showroom(m)
	usedLot(m)
	for i, h in ipairs(LobbyLayout.HOUSES) do
		local cf = rim(h.angle, LobbyLayout.HOUSE_RADIUS)
		if not storeModel(m, h.model, cf, h.height, true) then
			house(m, h.kind, cf, PASTEL[i % #PASTEL + 1])
		end
	end
	lamps(m)
	trees(m)
	props(m)
	npcs(m)
	for _, p in ipairs({ "Live" }) do
		local f = Instance.new("Folder")
		f.Name = p
		f.Parent = m
	end
	m.Parent = parent
	return m
end

-- ── Live parts ───────────────────────────────────────────────────────────────

local function line(hub, partName, lineName)
	local p = hub:FindFirstChild(partName, true)
	local g = p and p:FindFirstChildWhichIsA("SurfaceGui")
	return g and g:FindFirstChild(lineName, true)
end

--- The TV: track, countdown, players.
function LobbyHub.setBoard(hub, track, count, players)
	local t = line(hub, "Screen", "Track")
	if t then t.Text = track end
	local c = line(hub, "Screen", "Count")
	if c then c.Text = count end
	local p = line(hub, "Screen", "Players")
	if p then p.Text = players end
end

local function still(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if d:IsA("VehicleSeat") or d:IsA("Seat") then d.Disabled = true end
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	return model
end

--- The hall of fame: a copy of `src` (ReplicatedStorage.HallOfFame.Winner)
-- on the stage, turned to the plaza; nil clears it.
function LobbyHub.setWinner(hub, src)
	local live = hub:FindFirstChild("Live")
	local old = live and live:FindFirstChild("Winner")
	if old then old:Destroy() end
	local spot = hub:FindFirstChild("WinnerSpot", true)
	local nameLbl = spot and spot:FindFirstChild("Name", true)
	local votesLbl = spot and spot:FindFirstChild("Votes", true)
	if not src or not live then
		-- the sign back where it was built
		local header = hub:FindFirstChild("HallHeader", true)
		local base = header and header:GetAttribute("BaseBottom")
		if base then
			local hcf, hsize = header:GetBoundingBox()
			header:PivotTo(header:GetPivot() + V(0, base - (hcf.Position.Y - hsize.Y / 2), 0))
		end
		if spot then spot.CFrame = CF(LobbyLayout.STAGE.at + V(0, LobbyLayout.STAGE.height + 9, 0)) end
		if nameLbl then nameLbl.Text = "Win the vote to be here!" end
		if votesLbl then votesLbl.Text = "" end
		return nil
	end
	local copy = still(src:Clone())
	copy.Name = "Winner"
	local st = LobbyLayout.STAGE
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	-- a statue: WINNER_LENGTH long whatever the ride, on the stage, nose to the spawn
	local _, size0 = copy:GetBoundingBox()
	local long = math.max(size0.X, size0.Z)
	if long > 0 then ModelScale.scale(copy, LobbyLayout.WINNER_LENGTH / long) end
	ModelScale.standOn(copy, st.at, st.at.Y + st.height, A(0, math.rad(180), 0))
	copy.Parent = live
	-- the name just over it, the sign over that
	local cf, size = copy:GetBoundingBox()
	local top = cf.Position.Y + size.Y / 2
	if spot then spot.CFrame = CF(st.at.X, top + 3, st.at.Z) end
	local header = hub:FindFirstChild("HallHeader", true)
	if header then
		local hcf, hsize = header:GetBoundingBox()
		local bottom = hcf.Position.Y - hsize.Y / 2
		local want = math.max(header:GetAttribute("BaseBottom") or bottom, top + 4)
		header:PivotTo(header:GetPivot() + V(0, want - bottom, 0))
	end
	if nameLbl then nameLbl.Text = "🏆 " .. tostring(src:GetAttribute("Name") or "?") end
	if votesLbl then
		local v = tonumber(src:GetAttribute("Votes")) or 0
		votesLbl.Text = string.format("%d vote%s", v, v == 1 and "" or "s")
	end
	return copy
end

--- Legend Rides on the pads: `list` = the open listings (newest first),
-- `folder` = ReplicatedStorage.LegendRides (their pictures).
function LobbyHub.setLegends(hub, list, folder)
	local live = hub:FindFirstChild("Live")
	if not live then return end
	for _, c in ipairs(live:GetChildren()) do
		if c.Name:sub(1, 7) == "Legend_" then c:Destroy() end
	end
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	for i = 1, LobbyLayout.LEGEND_SLOTS do
		local pad = hub:FindFirstChild("LegendPad_" .. i, true)
		if pad then
			local oldTag = pad:FindFirstChild("Tag")
			if oldTag then oldTag:Destroy() end
			local oldPrompt = pad:FindFirstChildWhichIsA("ProximityPrompt")
			if oldPrompt then oldPrompt:Destroy() end
			local l = list[i]
			local src = l and folder and folder:FindFirstChild(l.id)
			if l and src then
				local copy = still(src:Clone())
				copy.Name = "Legend_" .. i
				ModelScale.scale(copy, LobbyLayout.LEGEND_SCALE)
				local face = pad.CFrame - pad.Position
				ModelScale.standOn(copy, pad.Position, pad.Position.Y + pad.Size.Y / 2, face * A(0, math.pi, 0))
				copy.Parent = live
				tag(pad, { { text = l.title, color = C(255, 214, 60) },
					{ text = string.format("%d/%d sold · %dd left", l.sold or 0, l.limit or 0, l.daysLeft or 0), font = Enum.Font.Gotham } },
					6, 20, 6)
				prompt(pad, "Buy", l.title, "legend")
			end   -- an empty pad says nothing: the garage's sign does
		end
	end
end

--- Junk Motors' cars on their plinths: `folder` = ReplicatedStorage.NewCars
-- (a still per item, Modules/CarDealer), each SHOW_LENGTH long, side on
-- to the walkway, nose into the shop.
function LobbyHub.setNewCars(hub, folder)
	local live = hub:FindFirstChild("Live")
	if not live or not folder then return end
	for _, c in ipairs(live:GetChildren()) do
		if c.Name:sub(1, 7) == "NewCar_" then c:Destroy() end
	end
	local Constants = require(ReplicatedStorage.Shared.Constants)
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	for _, pad in ipairs(hub:GetChildren()) do
		local item = pad:IsA("BasePart") and pad:GetAttribute("Car")
		local src = item and folder:FindFirstChild(item)
		if src then
			local copy = still(src:Clone())
			copy.Name = "NewCar_" .. item
			local _, size = copy:GetBoundingBox()
			local long = math.max(size.X, size.Z)
			if long > 0 then ModelScale.scale(copy, Constants.NEW_CARS.SHOW_LENGTH / long) end
			ModelScale.standOn(copy, pad.Position, pad.Position.Y + pad.Size.Y / 2, A(0, math.rad(90), 0))
			copy.Parent = live
		end
	end
end

--- Junk Auto Mart's cars: `list` = the open Legend Ride listings, newest
-- first ({ id, title, ownerName, biome, votes, sold, limit, daysLeft }),
-- `folder` = ReplicatedStorage.LegendRides (their pictures), `price` in
-- coins, `onPrompt(player, action, id)` for the "try" / "buy" prompts.
-- Each car stands nose out with its price on the roof and an inspection
-- card in front; the newest is "JUST IN" by the entrance.
local BIOME_WORD = { FOREST = "FOREST", OCEAN = "OCEAN", SKY = "SKY" }
function LobbyHub.setUsedCars(hub, list, folder, price, onPrompt)
	local live = hub:FindFirstChild("Live")
	if not live then return end
	for _, c in ipairs(live:GetChildren()) do
		if c.Name:sub(1, 5) == "Used_" then c:Destroy() end
	end
	local Constants = require(ReplicatedStorage.Shared.Constants)
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	local shown = 0
	for i, l in ipairs(list) do
		if i > LobbyLayout.USED_SLOTS then break end
		local src = folder and folder:FindFirstChild(l.id)
		if src then
			shown += 1
			local spot, north = LobbyLayout.usedSpot(i)
			local face = north and CF() or A(0, math.pi, 0)   -- the nose (-Z) out to the walkway
			local holder = Instance.new("Model")
			holder.Name = "Used_" .. i
			local copy = still(src:Clone())
			copy.Name = "Car"
			local _, size0 = copy:GetBoundingBox()
			local long = math.max(size0.X, size0.Z)
			if long > 0 then ModelScale.scale(copy, Constants.NEW_CARS.SHOW_LENGTH / long) end
			-- the long side across the bay (front to back)
			local _, s1 = copy:GetBoundingBox()
			local turn = s1.X > s1.Z and A(0, math.rad(90), 0) or CF()
			ModelScale.standOn(copy, spot, spot.Y + 0.06, face * turn)
			copy.Parent = holder
			local _, size = copy:GetBoundingBox()
			local out = north and V(0, 0, -1) or V(0, 0, 1)
			local half = math.max(size.X, size.Z) / 2
			-- a stand in front of the nose: the price written by hand on a
			-- yellow card on top (on the roof it floated over tall engines),
			-- the inspection card under it
			local standAt = spot + out * (half + 1.4)
			deco(part(holder, "CardPost", V(0.25, 5.2, 0.25), CF(standAt + V(0, 2.6, 0)), C(60, 60, 70), "Metal"))
			local card = part(holder, "PriceCard", V(3, 1.4, 0.15), CF(standAt + V(0, 5, 0)) * face * A(0, math.pi, 0),
				C(255, 220, 40), "SmoothPlastic")
			deco(card)
			local priceText = tostring(price):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
			sign(card, { { text = priceText, color = C(220, 30, 30), font = Enum.Font.PermanentMarker } }, C(255, 220, 40),
				Enum.NormalId.Back)
			local board = part(holder, "RecordCard", V(2.6, 2, 0.15),
				CF(standAt + V(0, 3, 0)) * face * A(0, math.pi, 0) * A(math.rad(-20), 0, 0), C(250, 250, 245), "SmoothPlastic")
			board.CanCollide = false
			sign(board, {
				{ text = "INSPECTION RECORD", color = C(30, 60, 140), share = 0.2 },
				{ text = "Built by " .. tostring(l.ownerName), color = C(40, 40, 50), share = 0.16, font = Enum.Font.GothamBold },
				{ text = string.format("Won the vote · %s · %d votes", BIOME_WORD[l.biome or ""] or "?", l.votes or 0),
					color = C(40, 40, 50), share = 0.16, font = Enum.Font.Gotham },
				{ text = string.format("Sold %d/%d · %d days left", l.sold or 0, l.limit or 0, l.daysLeft or 0),
					color = C(40, 40, 50), share = 0.16, font = Enum.Font.Gotham },
				{ text = string.format("TOTAL %s coins", priceText), color = C(200, 30, 30), share = 0.2 },
			}, C(250, 250, 245), Enum.NormalId.Back)
			local lines = { { text = tostring(l.title), color = C(255, 214, 60) },
				{ text = string.format("%s coins · %d/%d sold", priceText, l.sold or 0, l.limit or 0), font = Enum.Font.Gotham } }
			if i == 1 then table.insert(lines, 1, { text = "JUST IN!", color = C(255, 140, 40) }) end
			tag(board, lines, 5.5, 30, 6)
			for _, a in ipairs({ { "try", "Try on" }, { "buy", string.format("Buy · %s coins", priceText) } }) do
				local pp = prompt(board, a[2], tostring(l.title), nil)
				pp:SetAttribute("CarAction", a[1])
				pp:SetAttribute("Legend", l.id)
				pp.MaxActivationDistance = 7
				if a[1] == "buy" then
					pp.HoldDuration = 0.8
					pp.KeyboardKeyCode = Enum.KeyCode.F
					pp.GamepadKeyCode = Enum.KeyCode.ButtonY
				end
				if onPrompt then
					pp.Triggered:Connect(function(player) onPrompt(player, a[1], l.id) end)
				end
			end
			holder:SetAttribute("Legend", l.id)
			holder.Parent = live
		end
	end
	-- the "win the vote" sign only on an empty lot
	local empty = hub:FindFirstChild("LotEmptySign")
	if empty then
		empty.Transparency = shown == 0 and 0 or 1
		local g = empty:FindFirstChildWhichIsA("SurfaceGui")
		if g then g.Enabled = shown == 0 end
	end
	return shown
end

--- The hub place's start pads (Shared/Departure) where the junk ride show
-- stands in a round server: a pad each, its name and a status line over it.
function LobbyHub.departurePads(hub)
	local Departure = require(ReplicatedStorage.Shared.Departure)
	local Constants = require(ReplicatedStorage.Shared.Constants)
	local pads = {}
	for i, d in ipairs(Departure.PADS) do
		local spot = LobbyLayout.SHOWCASE[i]
		if not spot then break end
		local public = d.kind == "public"
		local pad = cyl(hub, "Depart_" .. d.id, Constants.DEPART.RADIUS * 2, 0.6, CF(spot + V(0, 0.3, 0)),
			public and C(70, 200, 100) or C(120, 140, 255), "SmoothPlastic")
		pad:SetAttribute("Pad", d.id)
		deco(cyl(hub, "DepartRim", Constants.DEPART.RADIUS * 2 + 0.6, 0.4, CF(spot + V(0, 0.25, 0)),
			C(255, 255, 255), "Neon"))
		tag(pad, { { name = "Title", text = d.title, color = C(255, 255, 255) },
			{ name = "Sub", text = d.sub, font = Enum.Font.Gotham },
			{ name = "Status", text = "step on!", color = C(255, 214, 60) } }, 7, 60, 8)
		pads[d.id] = pad
	end
	-- the series' next games: grey pads that send nobody yet
	for i, d in ipairs(Departure.SOON) do
		local spot = LobbyLayout.SOON[i]
		if not spot then break end
		local pad = cyl(hub, "Soon_" .. d.id, Constants.DEPART.RADIUS * 2, 0.6, CF(spot + V(0, 0.3, 0)), C(150, 150, 160), "SmoothPlastic")
		pad:SetAttribute("Soon", d.id)
		for k = 0, 11 do   -- a dashed rim
			local a = k / 12 * math.pi * 2
			deco(part(hub, "SoonDash", V(1.6, 0.35, 0.4),
				CFrame.lookAt(spot + V(math.cos(a), 0, math.sin(a)) * Constants.DEPART.RADIUS + V(0, 0.65, 0),
					spot + V(math.cos(a + 0.1), 0, math.sin(a + 0.1)) * Constants.DEPART.RADIUS + V(0, 0.65, 0)) * A(0, math.pi / 2, 0),
				C(255, 214, 60), "Neon"))
		end
		tag(pad, { { name = "Title", text = d.title, color = C(255, 255, 255) },
			{ name = "Sub", text = d.sub, color = C(255, 214, 60), font = Enum.Font.GothamBold } }, 7, 60, 8)
		pads[d.id] = pad
	end
	return pads
end

--- A start pad's status line ("step on!", "3 on pad · leaving in 5").
function LobbyHub.setPad(hub, id, text)
	local pad = hub:FindFirstChild("Depart_" .. id)
	local status = pad and pad:FindFirstChild("Status", true)
	if status then status.Text = text end
end

--- The three junk rides of the old 2D lobby (ReplicatedStorage.LobbyShowcase).
function LobbyHub.setShowcase(hub, folder)
	local live = hub:FindFirstChild("Live")
	if not live or not folder then return end
	for _, c in ipairs(live:GetChildren()) do
		if c.Name:sub(1, 9) == "Showcase_" then c:Destroy() end
	end
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	local names = { "1_FOREST", "2_OCEAN", "3_SKY" }
	for i, spot in ipairs(LobbyLayout.SHOWCASE) do
		local src = folder:FindFirstChild(names[i])
		if src then
			local copy = still(src:Clone())
			copy.Name = "Showcase_" .. i
			local face = LobbyLayout.facingCentre(spot)
			ModelScale.standOn(copy, spot, spot.Y + 0.6, (face - face.Position) * A(0, math.pi, 0))
			copy.Parent = live
		end
		local pad = hub:FindFirstChild("ShowPad_" .. i, true)
		if not pad then
			pad = cyl(hub, "ShowPad_" .. i, 10, 0.6, CF(spot + V(0, 0.3, 0)), PASTEL[i * 2 % #PASTEL + 1])
			tag(pad, { { text = ({ "FOREST", "OCEAN", "SKY" })[i] .. " ride", color = C(255, 255, 255) } }, 8, 18, 4)
		end
	end
end

return LobbyHub
