-- Promo.lua
-- Store-page pictures from the real game (Studio run mode): each scene shows
-- one map with its race lighting, places vehicles built by VehicleBuilder
-- (varied builds, paints, special rides) with seated avatars wearing their
-- HEAD item, some frozen mid-jump, and stops the camera on a composed shot.
-- Each stop prints "GALLERY_SHOT <token> <n> <name>" and holds `hold`
-- seconds; tools/studio/sim.py (kind "promo") takes the screenshot, crops
-- the Studio view and writes assets/store/ (1920 × 1080 thumbnails, the
-- 512 × 512 icon). Nothing drives; this is only about the look.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local RaceProgress = require(ReplicatedStorage.Shared.RaceProgress)
local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
local MapVisibility = require(ServerScriptService.Modules.MapVisibility)
local LightingPresets = require(ServerScriptService.Modules.LightingPresets)
local RaceGrid = require(ServerScriptService.Modules.RaceGrid)
local Gallery = require(ServerScriptService.TestHarness.Gallery)

local Promo = {}

local TRACKS = {
	FOREST = require(ReplicatedStorage.Shared.Tracks.ForestTrack),
	OCEAN = require(ReplicatedStorage.Shared.Tracks.OceanTrack),
	SKY = require(ReplicatedStorage.Shared.Tracks.SkyTrack),
}

-- How high a vehicle's chassis centre rides above the road / water.
local RIDE = { FOREST = 0.8, OCEAN = 1.0, SKY = 4.0 }

-- A colourful line-up: { slots, look, shirt colour }.
local BUILDS = {
	{ { BODY = "Bathtub", ENGINE = "Rocket", MOBILITY = "Rubber Duck", HEAD = "Propeller Hat" }, { paint = "paint_sunset" }, Color3.fromRGB(230, 60, 60) },
	{ { BODY = "Pizza", ENGINE = "Fan", MOBILITY = "Pizza", HEAD = "Trophy" }, {}, Color3.fromRGB(60, 140, 230) },
	{ { BODY = "Red Sofa", ENGINE = "Hair Dryer", MOBILITY = "Life Preserver", HEAD = "Cactus" }, { paint = "paint_lime" }, Color3.fromRGB(250, 200, 40) },
	{ { BODY = "Shopping Cart", ENGINE = "Kettle", MOBILITY = "Alarm Clock", HEAD = "Flower" }, { ride = "ride_neon" }, Color3.fromRGB(150, 70, 220) },
	{ { BODY = "Rocket", ENGINE = "Cup Noodle", MOBILITY = "Toilet Paper", HEAD = "Rubber Duck" }, { paint = "paint_galaxy" }, Color3.fromRGB(40, 190, 120) },
	{ { BODY = "Barrel", ENGINE = "Compass", MOBILITY = "Compass", HEAD = "Lantern" }, { ride = "ride_flame" }, Color3.fromRGB(240, 120, 30) },
	{ { BODY = "Skateboard", ENGINE = "Alarm Clock", MOBILITY = "Fan", HEAD = "Balloon Bunch" }, { paint = "paint_bubblegum" }, Color3.fromRGB(255, 130, 190) },
	{ { BODY = "Toilet Paper", ENGINE = "Treadmill", MOBILITY = "Barrel", HEAD = "Magic Wand" }, { ride = "ride_gold" }, Color3.fromRGB(30, 40, 90) },
}

-- Hero shots for the Korean reel (args.reel; never in the store pictures):
-- the Creator Store items ridden, close up on their own map.
local REEL_BUILDS = {
	piano = { { BODY = "Piano", ENGINE = "Electric Guitar", MOBILITY = "Alarm Clock", HEAD = "Propeller Hat" }, { paint = "paint_sunset" }, Color3.fromRGB(230, 60, 60) },
	toilet = { { BODY = "Toilet", ENGINE = "Boombox", MOBILITY = "Rubber Duck", HEAD = "Rubber Duck" }, {}, Color3.fromRGB(60, 140, 230) },
	bicycle = { { BODY = "Bicycle", ENGINE = "Lawn Mower", MOBILITY = "Fan", HEAD = "Trophy" }, { ride = "ride_neon" }, Color3.fromRGB(250, 200, 40) },
	hotdog = { { BODY = "Hot Dog", ENGINE = "Rocket", MOBILITY = "Pizza", HEAD = "Cactus" }, { ride = "ride_flame" }, Color3.fromRGB(150, 70, 220) },
}

local function geometry(biome)
	return RaceProgress.geometry(biome)
end

-- Road point at arc length s, `lateral` studs to the left, `up` studs over
-- the road; the frame faces down the track.
local function frameAt(biome, s, lateral, up)
	local geo = geometry(biome)
	local x, z, dx, dz = geo:pointAt(s)
	local y = geo.hasHeights and geo:heightAt(s) or TRACKS[biome].trackTop
	if biome == "OCEAN" then y = 2 end   -- the water
	local left = Vector3.new(dz, 0, -dx)
	local p = Vector3.new(x, y, z) + left * (lateral or 0) + Vector3.new(0, up or 0, 0)
	return CFrame.lookAt(p, p + Vector3.new(dx, 0, dz))
end

local function statsFor(slots, biome)
	local s = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	return VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
end

-- A parked vehicle with its rider: build k of BUILDS at `cf` (the chassis).
local function place(folder, biome, k, cf)
	local b = type(k) == "string" and REEL_BUILDS[k] or BUILDS[((k - 1) % #BUILDS) + 1]
	local equipped = {}
	for cat, id in pairs(b[2]) do equipped[cat] = id end
	local ok, model = pcall(VehicleBuilder.build, statsFor(b[1], biome), biome, cf, b[1], Cosmetics.look(equipped))
	if not ok or not model then warn("[Promo] build failed: " .. tostring(model)) return nil end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	model.Parent = folder
	local char = Gallery.seatRider(model, folder, b[3])
	return model, char
end

-- The scenes: what is on screen and where the camera stands.
local function scenes()
	local list = {}
	local F = TRACKS.FOREST
	local geoF = geometry("FOREST")

	-- 1. The start grid: eight builds side by side, seen from just ahead.
	table.insert(list, { name = "1_grid", biome = "FOREST", setup = function(folder)
		local cfs = RaceGrid.cframes("FOREST")
		local sum = Vector3.zero
		for k = 1, math.min(8, #cfs) do
			local cf = cfs[k] * CFrame.new(0, RIDE.FOREST - 0.8, 0)
			place(folder, "FOREST", k, cf)
			sum += cf.Position
		end
		local centre = sum / math.min(8, #cfs)
		local look = cfs[1].LookVector
		local eye = centre + look * 17 + Vector3.new(5, 3.2, 0)
		return CFrame.lookAt(eye, centre + Vector3.new(0, 1.5, 0))
	end })

	-- 2. Off a jump ramp: one car high in the air, two more coming.
	table.insert(list, { name = "2_ramp_jump", biome = "FOREST", setup = function(folder)
		local r = F.jumpRamps[#F.jumpRamps]
		local s = geoF:progressAt(r[1], r[2]) + F.jumpRampSize[3] / 2
		place(folder, "FOREST", 1, frameAt("FOREST", s + 10, 1, RIDE.FOREST + 6.5) * CFrame.Angles(math.rad(8), 0, 0))
		place(folder, "FOREST", 3, frameAt("FOREST", s - 7, -6, RIDE.FOREST + 3.6) * CFrame.Angles(math.rad(14), 0, 0))
		place(folder, "FOREST", 5, frameAt("FOREST", s - 22, 5, RIDE.FOREST))
		local target = frameAt("FOREST", s + 3, -1, 4.5).Position
		return CFrame.lookAt(frameAt("FOREST", s + 24, -11, 4).Position, target)
	end })

	-- 3. The gap jump: a car over the gap, another on the spring pad.
	table.insert(list, { name = "3_gap_jump", biome = "FOREST", setup = function(folder)
		local g = geoF.gaps and geoF.gaps[1]
		if not g then return nil end
		local mid = (g.s0 + g.s1) / 2
		place(folder, "FOREST", 2, frameAt("FOREST", mid + 2, -2, RIDE.FOREST + 4) * CFrame.Angles(math.rad(5), 0, 0))
		place(folder, "FOREST", 7, frameAt("FOREST", g.pad0 + 5, 5, RIDE.FOREST))
		-- from above the far lip, looking back down into the gap
		local target = frameAt("FOREST", mid - 3, 0, -1).Position
		return CFrame.lookAt(frameAt("FOREST", g.s1 + 9, -9, 11).Position, target)
	end })

	-- 4. Boats on the water, sails up, paddle wheels in.
	table.insert(list, { name = "4_ocean", biome = "OCEAN", setup = function(folder)
		local s = 160
		local spots = { { 0, 2 }, { -9, -7 }, { -18, 8 }, { -28, -3 } }
		for k, sp in ipairs(spots) do
			place(folder, "OCEAN", k + 1, frameAt("OCEAN", s + sp[1], sp[2], RIDE.OCEAN))
		end
		return CFrame.lookAt(frameAt("OCEAN", s + 13, -7, 4).Position, frameAt("OCEAN", s - 10, 1, 1.5).Position)
	end })

	-- 5. Planes round the sky corkscrew and its tower.
	table.insert(list, { name = "5_sky", biome = "SKY", setup = function(folder)
		local geo = geometry("SKY")
		local nodes = TRACKS.SKY.nodes
		local s0 = geo:progressAt(nodes[26][1], nodes[26][2], nil, nil, nodes[26][3])
		place(folder, "SKY", 4, frameAt("SKY", s0, 0, RIDE.SKY + 2))
		place(folder, "SKY", 1, frameAt("SKY", s0 - 12, 7, RIDE.SKY))
		place(folder, "SKY", 6, frameAt("SKY", s0 - 24, -6, RIDE.SKY + 3))
		local target = frameAt("SKY", s0 - 10, 0, 4).Position
		return CFrame.lookAt(frameAt("SKY", s0 + 15, -9, 9).Position, target)
	end })

	-- 6. The icon: the bathtub-rocket-duck car mid-jump with only sky behind
	-- it (far from every map, seen from below)
	table.insert(list, { name = "icon", biome = "FOREST", icon = true, setup = function(folder)
		local cf = CFrame.new(0, 600, 3000) * CFrame.Angles(math.rad(14), math.rad(200), math.rad(-8))
		place(folder, "FOREST", 1, cf)
		local eye = cf * CFrame.new(-5.5, 2.2, -8.5)   -- front quarter, a little above: the rider's face
		return CFrame.lookAt(eye.Position, (cf * CFrame.new(0, 1.3, 0.5)).Position)
	end })

	-- Reel close-ups (args.reel): the ridden item from the front quarter, a
	-- second car behind for depth.
	local function hero(name, biome, s, build, other, up, tilt)
		table.insert(list, { name = name, biome = biome, reel = true, setup = function(folder)
			local ride = RIDE[biome] + (up or 0)
			place(folder, biome, build, frameAt(biome, s, 0, ride) * CFrame.Angles(math.rad(tilt or 0), 0, 0))
			place(folder, biome, other, frameAt(biome, s - 16, 6, RIDE[biome]))
			local target = frameAt(biome, s, 0, ride + 1.2).Position
			return CFrame.lookAt(frameAt(biome, s + 9, -6.5, ride + 2.2).Position, target)
		end })
	end
	local sky = geometry("SKY")
	local n26 = TRACKS.SKY.nodes[26]
	local r = F.jumpRamps[#F.jumpRamps]
	hero("reel_piano", "FOREST", 150, "piano", 3)
	hero("reel_toilet", "OCEAN", 160, "toilet", 2)
	hero("reel_bicycle", "SKY", sky:progressAt(n26[1], n26[2], nil, nil, n26[3]), "bicycle", 4)
	hero("reel_hotdog", "FOREST", geoF:progressAt(r[1], r[2]) + F.jumpRampSize[3] / 2 + 10, "hotdog", 5, 6, 8)
	return list
end

local Weather = require(ReplicatedStorage.Shared.Weather)

local function showBiome(biome, weather)
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild(MapVisibility.mapName(biome))
	if map then MapVisibility.applyRacingState(maps, map) end
	for prop, value in pairs(Weather.lighting(LightingPresets[biome], biome, weather or Weather.CLEAR)) do
		pcall(function() Lighting[prop] = value end)
	end
	pcall(function() require(ServerScriptService.Modules.TerrainPainter).paint(biome) end)
	pcall(function()
		require(ServerScriptService.Modules.TerrainPainter).waterLook(biome, Weather.look(biome, weather))
	end)
	Weather.applySky(Lighting, workspace:FindFirstChildOfClass("Terrain"), biome, weather)
	-- floating labels (checkpoints) stay off the pictures
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then d.Enabled = false end
		end
	end
end

function Promo.run(args)
	args = args or {}
	local token = args.token or "-"
	local hold = args.hold or 2
	local models = ServerStorage:WaitForChild("ItemModels", 30)
	local t0 = os.clock()
	while models and not models:GetAttribute("Ready") and os.clock() - t0 < 60 do task.wait(0.25) end
	local maps = workspace:WaitForChild("Maps", 60)
	while maps and #maps:GetChildren() < 3 and os.clock() - t0 < 90 do task.wait(0.5) end
	if maps then MapVisibility.cacheOriginals(maps) end

	local cam = workspace.CurrentCamera
	local target
	local conn = RunService.Heartbeat:Connect(function()
		if target then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = 55
			cam.CFrame = target
		end
	end)
	local report = { shots = {}, errors = {} }
	local n = 0
	-- args.weather: every scene again under each of its biome's weathers
	-- (shot "weather_<scene>_<weather>"; WeatherFx's headlights added here,
	-- as no client runs)
	local list = {}
	for _, sc in ipairs(scenes()) do
		if (not args.only or table.find(args.only, sc.name)) and (sc.reel or false) == (args.reel or false) then
			if args.weather then
				for w in pairs(Weather.CHOICES[sc.biome] or {}) do
					if w ~= Weather.CLEAR then
						table.insert(list, setmetatable({ name = "weather_" .. sc.name .. "_" .. w, weather = w,
							headlights = (Weather.look(sc.biome, w).fx or {}).headlights }, { __index = sc }))
					end
				end
			else
				table.insert(list, sc)
			end
		end
	end
	for _, sc in ipairs(list) do
		do
			showBiome(sc.biome, sc.weather)
			local folder = Instance.new("Folder")
			folder.Name = "Promo_" .. sc.name
			folder.Parent = workspace
			local ok, camCF = pcall(sc.setup, folder)
			if ok and camCF and sc.headlights then
				for _, d in ipairs(folder:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Chassis" then
						local spot = Instance.new("SpotLight")
						spot.Face, spot.Range, spot.Angle, spot.Brightness = Enum.NormalId.Front, 60, 70, 2.2
						spot.Color, spot.Shadows = Color3.fromRGB(255, 240, 200), false
						spot.Parent = d
						local glow = Instance.new("PointLight")
						glow.Range, glow.Brightness, glow.Color = 10, 0.5, Color3.fromRGB(255, 230, 190)
						glow.Parent = d
					end
				end
			end
			if ok and camCF then
				task.wait(1.2)   -- riders settle into their seats
				for _, c in ipairs(folder:GetChildren()) do
					local hum = c:IsA("Model") and c:FindFirstChildOfClass("Humanoid")
					local vehicle = hum and hum.SeatPart and hum.SeatPart:FindFirstAncestorWhichIsA("Model")
					if vehicle then VehicleBuilder.wearHat(vehicle, c) end
				end
				target = camCF
				task.wait(0.8)
				n += 1
				print(string.format("GALLERY_SHOT %s %d %s", token, n, sc.name))
				table.insert(report.shots, { name = sc.name, icon = sc.icon or nil })
				task.wait(hold)
			else
				table.insert(report.errors, sc.name .. ": " .. tostring(camCF))
			end
			folder:Destroy()
		end
	end
	conn:Disconnect()
	report.summary = string.format("promo: %d shots, %d errors%s", #report.shots, #report.errors,
		#report.errors > 0 and (" (" .. table.concat(report.errors, "; ") .. ")") or "")
	return report
end

return Promo
