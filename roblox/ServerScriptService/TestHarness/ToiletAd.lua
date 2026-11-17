-- ToiletAd.lua
-- Server side of the toilet ride reel (2026-11-17 storyboard: "my avatar in
-- some map, chatting with a friend by voice, wearing the toilet → 'what is
-- that, I want it' → 'my ride won the race vote, I built it, hard to get' →
-- 'what's that?' → the hall of fame → 'insane lol' → a dead-serious car ad:
-- limited, worn round the waist, the comfort of really riding, meet the new
-- collection → logo → both in toilets, dancing"). Harness arg
-- `lobbyFilm = { story = "toilet" }` (scenario record-toilet).
--
-- Sets far from the tracks and Junk Town: a plain hangout map (grey
-- baseplate, trees, benches) and a dark ad studio (turntable, runway, two
-- other Legend Rides on pedestals). The friend is an NPC; the filmer's
-- walk and camera are StarterPlayerScripts/Modules/ToiletAdClient, timed
-- from FilmT0 like the lobby reel. Positions go to the client as
-- ReplicatedStorage attributes FilmHangout / FilmStudio. Nothing is saved.
--
--   0  hangout: the friend waves (3), hops in surprise (11.5)
--   14 hall of fame (the statue of the filmer's ride)
--   22 the ad studio, lights down
--   38 hangout again, lights up: the friend wears a copy, both dance
--   48 done

local Lighting            = game:GetService("Lighting")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ToiletAd = {}

ToiletAd.LENGTH = 48
ToiletAd.HANGOUT = Vector3.new(-2600, 200, 0)
ToiletAd.STUDIO = Vector3.new(-2600, 200, 1500)
ToiletAd.FRIEND = { name = "doyun0412", shirt = Color3.fromRGB(60, 120, 220), hat = "hat_propeller" }
ToiletAd.SLOTS = { BODY = "Toilet", ENGINE = "Rocket" }
ToiletAd.ANIM = { wave = "rbxassetid://507770239", dance = "rbxassetid://507771019" }

local V, CF = Vector3.new, CFrame.new
local C = Color3.fromRGB

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function spot(parent, at, target, brightness, angle)
	local holder = part(parent, "Light", V(0.5, 0.5, 0.5), CFrame.lookAt(at, target), C(0, 0, 0))
	holder.Transparency = 1
	holder.CanCollide, holder.CanQuery = false, false
	local l = Instance.new("SpotLight")
	l.Face = Enum.NormalId.Front
	l.Angle = angle or 40
	l.Range = 60
	l.Brightness = brightness or 4
	l.Color = C(255, 245, 225)
	l.Parent = holder
end

-- a plain Roblox map: a grey baseplate, trees, benches, lamps, houses far off
local function hangout(folder)
	local LobbyHub = require(ServerScriptService.Modules.Maps.LobbyHub)
	local H = ToiletAd.HANGOUT
	local m = Instance.new("Model")
	m.Name = "Hangout"
	m.Parent = folder
	local base = part(m, "Baseplate", V(400, 2, 400), CF(H - V(0, 1, 0)), C(99, 95, 98), "Plastic")
	local tex = Instance.new("Texture")   -- Roblox's baseplate grid
	tex.Texture = "rbxassetid://6372755229"
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU, tex.StudsPerTileV = 8, 8
	tex.Transparency = 0.8
	tex.Parent = base
	local put = LobbyHub._storeModel
	local trees = { "tree_round", "tree_puff", "tree_tall" }
	for i, a in ipairs({ 20, 70, 115, 160, 205, 250, 300, 340 }) do
		local r = 26 + (i % 3) * 9
		local p = H + V(math.cos(math.rad(a)) * r, 0, math.sin(math.rad(a)) * r)
		put(m, trees[i % 3 + 1], CF(p) * CFrame.Angles(0, i, 0), 16 + (i % 3) * 4, true)
	end
	put(m, "bench", CFrame.lookAt(H + V(3, 0, 9), H + V(3, 0, 0)), 3.4, true)
	put(m, "lamp_plain", CF(H + V(-7, 0, 8)), 12, true)
	put(m, "lamp_fancy", CF(H + V(14, 0, -9)), 12, true)
	for i, a in ipairs({ 0, 60, 130, 200, 270 }) do
		local p = H + V(math.cos(math.rad(a)) * 90, 0, math.sin(math.rad(a)) * 90)
		put(m, ({ "house_small", "house_big", "house_garden" })[i % 3 + 1], CFrame.lookAt(p, H), 20, true)
	end
end

-- the ad studio: a black box, a turntable in a spotlight, a runway, two
-- other Legend Rides on pedestals either side
local function studio(folder, others)
	local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
	local ModelScale = require(ServerScriptService.Modules.ModelScale)
	local S = ToiletAd.STUDIO
	local m = Instance.new("Model")
	m.Name = "AdStudio"
	m.Parent = folder
	local black = C(8, 8, 12)
	local floor = part(m, "Floor", V(120, 2, 140), CF(S + V(0, -1, 10)), C(20, 20, 26), "SmoothPlastic")
	floor.Reflectance = 0.25
	part(m, "Ceiling", V(120, 2, 140), CF(S + V(0, 40, 10)), black)
	part(m, "WallN", V(120, 42, 2), CF(S + V(0, 20, -60)), black)
	part(m, "WallS", V(120, 42, 2), CF(S + V(0, 20, 80)), black)
	part(m, "WallW", V(2, 42, 140), CF(S + V(-60, 20, 10)), black)
	part(m, "WallE", V(2, 42, 140), CF(S + V(60, 20, 10)), black)
	-- the turntable (the client turns the avatar on it)
	local table_ = part(m, "Turntable", V(1, 9, 9), CF(S + V(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(235, 235, 240))
	table_.Shape = Enum.PartType.Cylinder
	local rim = part(m, "TurntableRim", V(0.3, 9.6, 9.6), CF(S + V(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(255, 214, 60), "Neon")
	rim.Shape = Enum.PartType.Cylinder
	spot(m, S + V(0, 22, -10), S + V(0, 2, 0), 5, 30)
	spot(m, S + V(-10, 14, 8), S + V(0, 2, 0), 2, 35)
	spot(m, S + V(10, 14, 8), S + V(0, 2, 0), 2, 35)
	-- the runway: little lights on the floor
	for z = 14, 46, 4 do
		for _, x in ipairs({ -3.5, 3.5 }) do
			part(m, "RunwayLight", V(0.6, 0.2, 0.6), CF(S + V(x, 0.1, z)), C(255, 240, 200), "Neon")
		end
	end
	for z = 18, 42, 12 do   -- light down the runway
		spot(m, S + V(0, 16, z - 6), S + V(0, 0, z), 4, 40)
	end
	-- the collection: two more rides on pedestals
	for i, l in ipairs(others) do
		local x = i == 1 and -12 or 12
		local at = S + V(x, 0, 0)
		local ped = part(m, "Pedestal", V(1.6, 7, 7), CF(at + V(0, 0.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(235, 235, 240))
		ped.Shape = Enum.PartType.Cylinder
		local ride = HallOfFame.buildStill(l)
		if ride then
			local _, size = ride:GetBoundingBox()
			local long = math.max(size.X, size.Z)
			if long > 0 then ModelScale.scale(ride, 6.5 / long) end
			ModelScale.standOn(ride, at, at.Y + 1.6, CFrame.Angles(0, math.rad(i == 1 and 200 or 160), 0))
			ride.Parent = m
		end
		spot(m, at + V(0, 18, -8), at + V(0, 2, 0), 3, 30)
	end
end

local function play(model, id, looped)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local track = animator:LoadAnimation(a)
	track.Looped = looped == true
	track:Play()
	return track
end

--- Plays the timeline once the lobby film found its filmer (`player`,
-- `rec`); `done()` when it is over.
function ToiletAd.run(player, rec, done)
	local HallOfFame  = require(ServerScriptService.Modules.HallOfFame)
	local LegendShop  = require(ServerScriptService.Modules.LegendShop)
	local LegendStore = require(ServerScriptService.Modules.LegendStore)
	local ShopHat     = require(ServerScriptService.Modules.ShopHat)
	local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
	local LobbyFilm   = require(script.Parent.LobbyFilm)

	ReplicatedStorage:SetAttribute("FilmStory", "toilet")
	ReplicatedStorage:SetAttribute("FilmHangout", ToiletAd.HANGOUT)
	ReplicatedStorage:SetAttribute("FilmStudio", ToiletAd.STUDIO)

	-- the filmer's ride won the vote: the statue, the original round the waist
	local e = HallOfFame.entry(player.UserId, player.DisplayName, "FOREST", ToiletAd.SLOTS, 7, rec.equipped)
	HallOfFame.record(e)
	local l = LegendRides.listing(e, os.time())
	LegendStore.add(l)
	LegendRides.give(rec, l, true)
	rec.legendOn = l.id
	LegendShop.refresh(player)
	local others = {}
	for i, sm in ipairs({ { "Bo", { BODY = "Rubber Duck", ENGINE = "Rocket" } }, { "Cy", { BODY = "Shopping Cart", SPECIAL = "Balloon Bunch" } } }) do
		others[i] = LegendRides.listing(HallOfFame.entry(10 + i, sm[1], "FOREST", sm[2], 3, {}), os.time() - 3600 * i)
	end

	local folder = Instance.new("Folder")
	folder.Name = "FilmSets"
	folder.Parent = workspace
	hangout(folder)
	studio(folder, others)

	-- the friend, facing the filmer's spot
	local H = ToiletAd.HANGOUT
	local friend = LobbyFilm._rig(ToiletAd.FRIEND, 1)
	local fHum = friend:FindFirstChildOfClass("Humanoid")
	local y = (fHum and fHum.HipHeight or 2) + friend.HumanoidRootPart.Size.Y / 2
	friend:PivotTo(CFrame.lookAt(H + V(6, y, 0), H + V(0, y, 0)))
	friend.Parent = folder
	pcall(ShopHat.wear, friend, ToiletAd.FRIEND.hat)
	pcall(function() friend.HumanoidRootPart:SetNetworkOwner(nil) end)

	task.wait(1)
	local T0 = workspace:GetServerTimeNow() + 2
	ReplicatedStorage:SetAttribute("FilmT0", T0)
	local function at(t, fn)
		task.delay(math.max(0, T0 + t - workspace:GetServerTimeNow()), function() pcall(fn) end)
	end

	at(3, function() play(friend, ToiletAd.ANIM.wave) end)
	at(11.5, function() if fHum then fHum.Jump = true end end)
	local saved = {}
	local NIGHT = { ClockTime = 0, Brightness = 0, Ambient = C(10, 10, 14), OutdoorAmbient = C(12, 12, 16),
		ExposureCompensation = 0.3, FogEnd = 100000 }
	at(22, function()
		for k, v in pairs(NIGHT) do
			saved[k] = Lighting[k]
			Lighting[k] = v
		end
	end)
	at(38, function()
		for k, v in pairs(saved) do Lighting[k] = v end
		-- the friend bought one
		LegendStore.take(l.id)
		local cur = LegendStore.find(l.id)
		pcall(LegendShop.wear, friend, { title = l.title, ownerName = l.ownerName, biome = l.biome, slots = l.slots,
			look = l.look, original = false, serial = cur and cur.sold or 1, limit = l.limit }, l.id)
	end)
	at(38.6, function() play(friend, ToiletAd.ANIM.dance, true) end)
	at(ToiletAd.LENGTH, function() done("toilet ad") end)
end

return ToiletAd
