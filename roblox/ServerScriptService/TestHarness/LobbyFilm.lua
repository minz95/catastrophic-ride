-- LobbyFilm.lua
-- Server side of the lobby reel (2026-11-17: "film the hall of fame: the vote
-- winner in their achievement look, everyone else envying the limited ride
-- and buying it"). Harness arg `lobbyFilm` (scenario record-lobby): the
-- match stays in LOBBY (lobbyDelay) while this plays a timeline:
--   * the filmer (the bot client) wins the vote: Funniest Ride is done
--     (Junk Crown on, the achievement notice), their ride is the hall of
--     fame statue and goes on sale as a Legend Ride, the original round
--     their waist;
--   * a crowd of made-up players gathers at the stage and the Legend pad,
--     says envious things (chat bubbles through FarmAction "say", as farm
--     bots do), then buys copies one by one: each wears its numbered copy
--     and the filmer gets the royalty notice.
-- The client half (camera and walking) is BotDriver's lobby film, timed
-- from the same ReplicatedStorage attribute FilmT0 (server time).
-- Nothing is saved: LegendStore stays in memory (memoryOnly).
-- `lobbyFilm = { story = "toilet" }` plays TestHarness/ToiletAd instead.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local LobbyFilm = {}

LobbyFilm.LENGTH = 70   -- s of timeline

local C = Color3.fromRGB
-- made-up players; `group` = where they stand first
LobbyFilm.CROWD = {
	{ name = "sakura_chan",   shirt = C(255, 150, 190), hat = "hat_party",     group = "pad" },
	{ name = "xX_Turbo_Xx",   shirt = C(40, 40, 50),    hat = "hat_cat",       group = "pad" },
	{ name = "seojun_2013",   shirt = C(60, 120, 220),  hat = "hat_propeller", group = "pad" },
	{ name = "BaconHairPro",  shirt = C(120, 80, 50),   hat = nil,             group = "pad" },
	{ name = "doyun0412",     shirt = C(90, 190, 110),  hat = "hat_viking",    group = "stage" },
	{ name = "NoobMaster_K",  shirt = C(255, 210, 60),  hat = nil,             group = "stage" },
	{ name = "jiwoo_kitty",   shirt = C(180, 120, 230), hat = "hat_top",       group = "stage" },
}

-- { t, crowd index, line } (the timeline's chat)
LobbyFilm.LINES = {
	{ 6, 5, "WHO IS THAT ON THE STAGE" },
	{ 8, 6, "bro is HUGE 😭" },
	{ 10.5, 7, "is that a TOILET" },
	{ 15, 1, "WHERE DID U GET THAT" },
	{ 17, 2, "only 50 copies??" },
	{ 19, 3, "2500 coins 💀💀" },
	{ 21, 4, "i want it so bad" },
	{ 27, 1, "omg its the owner" },
	{ 29, 7, "the crown isnt even for sale" },
	{ 31, 3, "ORIGINAL?? no way" },
	{ 61, 2, "bro is getting rich 😭" },
	{ 63, 6, "can i ride it pls" },
}
-- { t, crowd index, line } the buyers
LobbyFilm.SALES = {
	{ 35, 1, "BOUGHT IT 🔥" },
	{ 39, 3, "GOT ONE LETS GOOO" },
	{ 43, 2, "mine now 😎" },
	{ 47, 5, "take my coins" },
	{ 51, 7, "#5 IS MINE" },
	{ 55, 4, "spent all my coins lol" },
}

local function rig(c, i)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = C(255, 220, 180)
	desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
	desc.TorsoColor = c.shirt
	local legs = ({ C(40, 50, 80), C(30, 30, 35), C(90, 70, 50) })[i % 3 + 1]
	desc.LeftLegColor, desc.RightLegColor = legs, legs
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then   -- offline tests: a root, a head and a Humanoid
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.Parent = model
		Instance.new("Humanoid").Parent = model
		model.PrimaryPart = root
	end
	model.Name = c.name
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = c.name
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 60
	model:SetAttribute("BotUserId", -200000 - i)   -- FarmFx finds a talker by this (tag FarmBot)
	CollectionService:AddTag(model, "FarmBot")
	return model
end

LobbyFilm._rig = rig

-- Where things stand (the client, LobbyFilmClient, uses the same): the
-- filmer in front of their pad (F), the crowd round F on SLOTS (degrees
-- from the way to the plaza's centre, RING studs out), the front open for
-- the camera; at the stage the crowd keeps to the sides of the statue.
LobbyFilm.SLOTS = { 42, -42, 66, -66, 92, -92, 118 }
LobbyFilm.RING = 5.5
LobbyFilm.STAGE_SPOTS = { Vector3.new(-8, 0, -30), Vector3.new(8, 0, -30), Vector3.new(11, 0, -26) }   -- from ORIGIN

function LobbyFilm.spots(LobbyLayout)
	local O = LobbyLayout.ORIGIN
	local pad = LobbyLayout.legendSpot(1)
	local toCentre = (Vector3.new(O.X, pad.Y, O.Z) - pad).Unit
	local F = pad + toCentre * 4
	local ring = {}
	for i, deg in ipairs(LobbyFilm.SLOTS) do
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(deg)) * toCentre
		ring[i] = F + dir * LobbyFilm.RING
	end
	return { pad = pad, toCentre = toCentre, F = F, ring = ring }
end

local function face(model, pos, look)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local y = (hum and hum.HipHeight or 2) + model.HumanoidRootPart.Size.Y / 2
	model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, y, 0), Vector3.new(look.X, pos.Y + y, look.Z)))
end

--- Plays the timeline; `done()` when it is over.
function LobbyFilm.run(args, done)
	local HallOfFame  = require(ServerScriptService.Modules.HallOfFame)
	local LegendShop  = require(ServerScriptService.Modules.LegendShop)
	local LegendStore = require(ServerScriptService.Modules.LegendStore)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local ShopHat     = require(ServerScriptService.Modules.ShopHat)
	local Achievements = require(ReplicatedStorage.Shared.Achievements)
	local Cosmetics   = require(ReplicatedStorage.Shared.Cosmetics)
	local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
	local opts = type(args.lobbyFilm) == "table" and args.lobbyFilm or {}
	LegendStore.memoryOnly = true

	-- the filmer, loaded
	local player, rec
	local t0 = os.clock()
	repeat
		task.wait(0.5)
		player = Players:GetPlayers()[1]
		rec = player and PlayerStore.get(player)
	until (rec and player.Character and player.Character:FindFirstChild("HumanoidRootPart")) or os.clock() - t0 > 60
	if not rec then done("no filmer") return end
	player:SetAttribute("LobbyFilm", true)
	task.wait(opts.settle or 4)   -- the hub and the models built, the camera on the client
	if opts.story == "toilet" then   -- the toilet ride reel (TestHarness/ToiletAd)
		require(script.Parent.ToiletAd).run(player, rec, done)
		return
	end

	-- some other Legend Rides on the pads (older, selling)
	for i, sm in ipairs({ { "Bo", { BODY = "Rubber Duck", ENGINE = "Rocket" } }, { "Cy", { BODY = "Shopping Cart", SPECIAL = "Balloon Bunch" } } }) do
		local l = LegendRides.listing(HallOfFame.entry(10 + i, sm[1], "FOREST", sm[2], 3, {}), os.time() - 3600 * i)
		l.sold = ({ 41, 27 })[i]
		LegendStore.add(l)
	end

	-- the vote's winner: the filmer
	local slots = opts.slots or { BODY = "Toilet", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" }
	local a
	for _, x in ipairs(Achievements.LIST) do if x.key == "funniest" then a = x end end
	Achievements.grant(rec, a)
	rec.equipped.pose = "pose_handsup"
	ShopHat.refresh(player)
	local e = HallOfFame.entry(player.UserId, player.DisplayName, "FOREST", slots, 7, rec.equipped)
	HallOfFame.record(e)
	local l = LegendRides.listing(e, os.time())
	LegendStore.add(l)
	LegendRides.give(rec, l, true)
	rec.legendOn = l.id
	LegendShop.refresh(player)

	-- the crowd
	local folder = Instance.new("Folder")
	folder.Name = "FilmCrowd"
	folder.Parent = workspace
	local sp = LobbyFilm.spots(LobbyLayout)
	local pad = sp.pad
	local statue = LobbyLayout.STAGE.at + Vector3.new(0, 10, 0)
	local crowd, nStage = {}, 0
	for i, c in ipairs(LobbyFilm.CROWD) do
		local m = rig(c, i)
		local at, look
		if c.group == "pad" then
			at, look = sp.ring[i], pad   -- round the filmer's spot, looking at the ride
		else
			nStage += 1
			at, look = LobbyLayout.ORIGIN + LobbyFilm.STAGE_SPOTS[nStage], statue
		end
		face(m, at, look)
		m.Parent = folder
		if c.hat then pcall(ShopHat.wear, m, c.hat) end
		pcall(function() m.HumanoidRootPart:SetNetworkOwner(nil) end)
		crowd[i] = { model = m, data = c, home = at }
	end

	local function say(i, text)
		local who = crowd[i]
		if not who then return end
		pcall(function()
			RemoteEvents.FarmAction:FireAllClients("say", who.model:GetAttribute("BotUserId"), nil, { text = text })
		end)
	end

	local T0 = workspace:GetServerTimeNow() + 1
	ReplicatedStorage:SetAttribute("FilmT0", T0)
	local function at(t, fn)
		task.delay(math.max(0, T0 + t - workspace:GetServerTimeNow()), fn)
	end

	-- the crown on the live avatar, again in case the character was rebuilt,
	-- and what is on the head (report: film_hat)
	local Telemetry = require(ServerScriptService.Modules.Telemetry)
	for _, t in ipairs({ 0, 12, 20 }) do
		at(t, function()
			pcall(ShopHat.refresh, player)
			local c = player.Character
			local head = c and c:FindFirstChild("Head")
			local hat = c and c:FindFirstChild(ShopHat.NAME)
			local info = { t = t, hat = hat ~= nil, id = hat and hat:GetAttribute("HatId"), equipped = rec.equipped.hat }
			if hat and head then
				local n, y = 0, -math.huge
				for _, p in ipairs(hat:GetDescendants()) do
					if p:IsA("BasePart") then
						n += 1
						y = math.max(y, p.Position.Y - head.Position.Y)
						info.transparency = p.Transparency
					end
				end
				info.parts, info.topOverHead, info.headSize = n, y, { head.Size.X, head.Size.Y, head.Size.Z }
				info.lift = ShopHat._hairLift(c, head)
			end
			Telemetry.record("film_hat", info)
		end)
	end
	at(1, function()   -- the achievement, as AchievementManager tells it
		local it = Cosmetics.get(a.reward)
		pcall(function()
			RemoteEvents.AchievementUpdate:FireClient(player, { key = a.key, name = a.name, text = a.text, reward = it and it.name })
		end)
	end)
	at(3, function()
		pcall(function()
			RemoteEvents.LegendUpdate:FireClient(player, { kind = "listed", title = l.title, limit = l.limit, days = 7 })
		end)
	end)
	for _, ln in ipairs(LobbyFilm.LINES) do
		at(ln[1], function() say(ln[2], ln[3]) end)
	end
	-- the stage group follows the filmer to the pad; everyone turns to the owner
	at(16, function()
		for i, who in ipairs(crowd) do
			if who.data.group == "stage" then
				local hum = who.model:FindFirstChildOfClass("Humanoid")
				if hum then hum:MoveTo(sp.ring[i]) end
			end
		end
	end)
	at(21, function()
		for i, who in ipairs(crowd) do
			if who.data.group == "pad" then face(who.model, sp.ring[i], sp.F) end
		end
	end)
	at(25, function()
		for i, who in ipairs(crowd) do
			if who.data.group == "stage" then face(who.model, sp.ring[i], sp.F) end
		end
	end)
	for _, s in ipairs(LobbyFilm.SALES) do
		at(s[1], function()
			local who = crowd[s[2]]
			if LegendStore.take(l.id) ~= "ok" then return end
			local cur = LegendStore.find(l.id)
			local copy = { title = l.title, ownerName = l.ownerName, biome = l.biome, slots = l.slots, look = l.look,
				original = false, serial = cur and cur.sold or nil, limit = l.limit }
			pcall(LegendShop.wear, who.model, copy, l.id)
			say(s[2], s[3])
			LegendShop.payOwner(l, who.data.name)
		end)
	end
	at(LobbyFilm.LENGTH, function()
		done("lobby film")
	end)
end

return LobbyFilm
