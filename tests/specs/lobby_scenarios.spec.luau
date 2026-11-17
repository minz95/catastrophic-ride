--!nocheck
-- Junk Town (lobby phase 1) and the two places (phase 2) in the situations
-- the first specs did not play (2026-11-17, "test phases 1 and 2
-- systematically, catch every bug before the release"): a worn Legend Ride
-- through a whole round, R6 avatars, the statue changing, a full server,
-- crowded start pads, people leaving or failing mid-departure, bad calls,
-- a hub running for hours, going back to the hub mid-race.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local RACE_ID, HUB_ID = 555, 74883519312765

local ROUND_SCRIPTS = {
	"ServerScriptService.MapBuilders.ForestMapBuilder",
	"ServerScriptService.MapBuilders.OceanMapBuilder",
	"ServerScriptService.MapBuilders.SkyMapBuilder",
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.CharacterManager",
	"ServerScriptService.FarmingManager",
	"ServerScriptService.CraftingManager",
	"ServerScriptService.RacingManager",
	"ServerScriptService.ProgressionManager",
	"ServerScriptService.RideShowManager",
	"ServerScriptService.ShopManager",
	"ServerScriptService.LegendManager",
	"ServerScriptService.LobbyManager",
	"ServerScriptService.DepartureManager",
}

local function rootOf(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end

-- the world box of a model's visible parts
local function box(model)
	local lo, hi
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local w = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
				lo = lo and lo:Min(w) or w
				hi = hi and hi:Max(w) or w
			end end end
		end
	end
	return lo, hi
end

-- a listing the player owns and wears
local function giveRide(srv, p, slots)
	local e = srv.env
	local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
	local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
	local LegendRides = e.requirePath("ReplicatedStorage.Shared.LegendRides")
	local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
	local l = LegendShop.listWinner(HallOfFame.entry(p.UserId, p.Name, "FOREST", slots or { BODY = "Toilet", ENGINE = "Rocket" }, 3, {}))
	local rec = PlayerStore.get(p)
	LegendRides.give(rec, l, true)
	rec.legendOn = l.id
	LegendShop.refresh(p)
	return l
end

local function phaseLoop(srv, want, limit)
	local t = 0
	while srv.GameManager.getPhase() ~= want and t < (limit or 400) do
		srv.advance(0.5)
		t += 0.5
	end
	return srv.GameManager.getPhase() == want
end

R.describe("Junk Town in every phase (lobby phase 1)", function()
	local function boot(opts)
		local srv = Server.boot({ players = opts.players or 1, scripts = ROUND_SCRIPTS, setup = opts.setup,
			harness = { harness = "lune", biome = "FOREST", players = opts.players or 1, lobbyDelay = opts.lobbyDelay or 3,
				durations = opts.durations or { FARMING = 6, CRAFTING = 3, RESULTS = 4 } } })
		srv.advance(1)
		return srv
	end

	R.it("a worn Legend Ride: on in the lobby, the farm and crafting; off for the race and the results; on again in the next lobby", function()
		local srv = boot({ lobbyDelay = 6 })
		local p = srv.players[1]
		local LegendShop = srv.env.requirePath("ServerScriptService.Modules.LegendShop")
		giveRide(srv, p)
		local function worn() return p.Character:FindFirstChild(LegendShop.WORN) ~= nil end
		R.expect(worn()).toBe(true, "LOBBY")
		R.expect(phaseLoop(srv, "FARMING")).toBe(true)
		srv.advance(1)
		R.expect(worn()).toBe(true, "FARMING")
		R.expect(phaseLoop(srv, "CRAFTING")).toBe(true)
		srv.advance(1)
		R.expect(worn()).toBe(true, "CRAFTING")
		R.expect(phaseLoop(srv, "RACING")).toBe(true)
		srv.advance(1)
		R.expect(worn()).toBe(false, "RACING: the avatar sits in the race car")
		R.expect(phaseLoop(srv, "RESULTS")).toBe(true)
		srv.advance(1)
		R.expect(worn()).toBe(false, "RESULTS: still in the parked car")
		R.expect(phaseLoop(srv, "LOBBY")).toBe(true)
		srv.advance(1)
		R.expect(worn()).toBe(true, "the next LOBBY")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("an R6 avatar (HipHeight 0) wears it round the waist with its bottom at the feet, not in the air", function()
		local srv = boot({ lobbyDelay = 60 })
		local p = srv.players[1]
		local hum = p.Character:FindFirstChildOfClass("Humanoid")
		hum.HipHeight = 0
		hum.RigType = Enum and Enum.HumanoidRigType and Enum.HumanoidRigType.R6 or roblox.Enum.HumanoidRigType.R6
		local root = rootOf(p)
		giveRide(srv, p)
		local worn = p.Character:FindFirstChild("LegendRide")
		local lo = box(worn)
		local waist = root.Position.Y - root.Size.Y / 2
		local feet = waist - 2   -- R6 legs are 2 studs below the torso
		R.expect(lo.Y < waist - 1).toBe(true, string.format("bottom %.2f, waist %.2f: floating", lo.Y, waist))
		R.expect(lo.Y >= feet - 0.01).toBe(true, string.format("bottom %.2f under the feet %.2f", lo.Y, feet))
	end)

	R.it("the statue changes with each winner: a big ride lifts the sign, a small one lets it down, none clears it", function()
		local srv = boot({ lobbyDelay = 60 })
		local e = srv.env
		local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
		local hub = e.workspace:FindFirstChild("LobbyHub")
		local header = hub:FindFirstChild("HallHeader", true)
		local function bottom() local cf, s = header:GetBoundingBox() return cf.Position.Y - s.Y / 2 end
		local base = bottom()
		local function top()
			local w = hub:FindFirstChild("Live"):FindFirstChild("Winner")
			local cf, s = w:GetBoundingBox()
			return cf.Position.Y + s.Y / 2
		end
		HallOfFame.record(HallOfFame.entry(1, "Tall", "FOREST", { BODY = "Toilet", ENGINE = "Rocket", SPECIAL = "Balloon Bunch" }, 4, {}))
		srv.advance(2)
		local t1 = top()
		R.expect(bottom() > t1).toBe(true, string.format("sign %.1f over the tall statue %.1f (base %.1f)", bottom(), t1, base))
		HallOfFame.record(HallOfFame.entry(2, "Flat", "FOREST", { BODY = "Shopping Cart" }, 2, {}))
		srv.advance(2)
		local t2 = top()
		R.expect(bottom() > t2).toBe(true, "sign over the flat statue")
		R.expect(bottom() <= math.max(base, t2 + 4) + 0.01).toBe(true, "the sign came back down")
		local LobbyHub = e.requirePath("ServerScriptService.Modules.Maps.LobbyHub")
		LobbyHub.setWinner(hub, nil)
		R.expect(hub:FindFirstChild("Live"):FindFirstChild("Winner")).toBe(nil)
		R.expect(math.abs(bottom() - base) < 0.01).toBe(true, "back where it was built")
		R.expect(hub:FindFirstChild("WinnerSpot", true):FindFirstChild("Name", true).Text).toBe("Win the vote to be here!")
	end)

	R.it("Legend pads: at most six rides, newest first; sold-out and ended ones are not shown", function()
		local srv = boot({ lobbyDelay = 60 })
		local e = srv.env
		local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
		local LegendRides = e.requirePath("ReplicatedStorage.Shared.LegendRides")
		local LegendStore = e.requirePath("ServerScriptService.Modules.LegendStore")
		local C = e.requirePath("ReplicatedStorage.Shared.Constants")
		local now = math.floor(e.mock.clock)   -- the scripts' os.time()
		for i = 1, 9 do
			local l = LegendRides.listing(HallOfFame.entry(100 + i, "O" .. i, "FOREST", { BODY = "Shopping Cart" }, 1, {}), now - i * 60)
			if i == 2 then l.sold = l.limit end                       -- sold out
			if i == 3 then l.endsAt = now - 1 end                     -- ended
			LegendStore.add(l)
		end
		srv.advance(3)
		local hub = e.workspace:FindFirstChild("LobbyHub")
		local live = hub:FindFirstChild("Live")
		local shown = 0
		for i = 1, 6 do
			if live:FindFirstChild("Legend_" .. i) then shown += 1 end
			local pad = hub:FindFirstChild("LegendPad_" .. i, true)
			local tag = pad:FindFirstChild("Tag")
			if tag then
				local title = tag:FindFirstChild("Line1", true) or tag:FindFirstChildWhichIsA("TextLabel", true)
				R.expect(title.Text:find("O2", 1, true) == nil and title.Text:find("O3", 1, true) == nil).toBe(true, title.Text)
			end
		end
		local open = {}
		for _, l in ipairs(LegendRides.active(LegendStore.list(), now)) do table.insert(open, l.ownerName or "?") end
		R.expect(shown).toBe(6, "open: " .. table.concat(open, ","))
		R.expect(C.LEGEND.SHOWN >= 6).toBe(true)
	end)

	R.it("townsfolk: bodies looked through, an invisible post each (a half-solid body trapped a walker for good)", function()
		local srv = boot({ lobbyDelay = 60 })
		local hub = srv.env.workspace:FindFirstChild("LobbyHub")
		local Npcs = srv.env.requirePath("ReplicatedStorage.Shared.LobbyNpcs")
		local posts = {}
		for _, d in ipairs(hub:GetDescendants()) do
			if d.Name == "NpcBlock" then posts[d:GetAttribute("Npc")] = d end
		end
		for _, n in ipairs(Npcs.LIST) do
			local rig = hub:FindFirstChild("Npc_" .. n.id)
			for _, p in ipairs(rig:GetDescendants()) do
				if p:IsA("BasePart") then R.expect(p.CanCollide).toBe(false, n.id .. " " .. p.Name) end
			end
			local post = posts[n.id]
			R.expect(post ~= nil and post.CanCollide and post.Transparency == 1).toBe(true, n.id)
			local root = rig:FindFirstChild("HumanoidRootPart")
			R.expect(Vector3.new(post.Position.X - root.Position.X, 0, post.Position.Z - root.Position.Z).Magnitude < 0.1).toBe(true)
		end
	end)

	R.it("a full server (10) and two late joiners: everyone on the plaza, nobody on top of anyone", function()
		local srv = boot({ players = 10, lobbyDelay = 60 })
		local L = srv.env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		local late1 = srv.mock.addPlayer("Late1", 7001, Vector3.new(0, 5, 0))
		local late2 = srv.mock.addPlayer("Late2", 7002, Vector3.new(0, 5, 0))
		srv.advance(2)
		local all = srv.env.game:GetService("Players"):GetPlayers()
		for _, p in ipairs(all) do
			-- the mock only moves characters the scripts move: SessionManager
			-- reloads at LOBBY (no-op here), LobbyManager brings the rest over
			if rootOf(p) and not L.onPlaza(rootOf(p).Position) then
				R.expect(p.Name).toBe("on the plaza")
			end
		end
		R.expect(L.onPlaza(rootOf(late1).Position) and L.onPlaza(rootOf(late2).Position)).toBe(true)
		R.expect((rootOf(late1).Position - rootOf(late2).Position).Magnitude > 1).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("the hub place in every situation (lobby phase 2)", function()
	local function boot(opts)
		local calls = {}
		local srv = Server.boot({ live = true, players = opts.players or 3, scripts = opts.scripts or ROUND_SCRIPTS, swallowErrors = true,
			setup = function(env, Mock)
				env.requirePath("ReplicatedStorage.Shared.Places").RACE = RACE_ID
				Mock.props(env.game).PlaceId = opts.placeId or HUB_ID
				local ts = env.game:GetService("TeleportService")
				rawset(ts, "TeleportAsync", function(_, placeId, players, options)
					table.insert(calls, { placeId = placeId, players = players, options = options })
					if opts.fail then error("teleport failed") end
					return {}
				end)
			end })
		srv.advance(1)
		return srv, srv.env.workspace:FindFirstChild("LobbyHub"), calls
	end
	local function standOn(p, pad, k)
		local a = (k or 0) * 0.7
		rootOf(p).CFrame = CFrame.new(pad.Position + Vector3.new(math.cos(a) * 2.5, 3, math.sin(a) * 2.5))
	end
	local function sentIds(calls)
		local ids = {}
		for _, c in ipairs(calls) do
			for _, p in ipairs(c.players) do table.insert(ids, p.UserId) end
		end
		return ids
	end

	R.it("twelve on a private pad: ten go together, the other two get their own server a clock later", function()
		local srv, hub, calls = boot({ players = 12 })
		local pad = hub:FindFirstChild("Depart_party1")
		for i, p in ipairs(srv.players) do
			standOn(p, pad, i)
			srv.advance(0.3)   -- one after another: the first ten on go first
		end
		srv.advance(6)
		R.expect(#calls).toBe(1)
		R.expect(#calls[1].players).toBe(10)
		for i = 1, 10 do R.expect(table.find(calls[1].players, srv.players[i]) ~= nil).toBe(true, "player " .. i) end
		srv.advance(9)
		R.expect(#calls).toBe(2)
		R.expect(#calls[2].players).toBe(2)
		R.expect(calls[2].options.ShouldReserveServer).toBe(true)
	end)

	R.it("someone leaving during the countdown, or after being sent, breaks nothing; the rest still go", function()
		local srv, hub, calls = boot({ players = 3 })
		local pad = hub:FindFirstChild("Depart_race")
		for i, p in ipairs(srv.players) do standOn(p, pad, i) end
		srv.advance(3)
		srv.mock.removePlayer(srv.players[2])
		srv.advance(7)
		R.expect(#calls).toBe(1)
		local ids = sentIds(calls)
		R.expect(#ids).toBe(2)
		R.expect(table.find(ids, srv.players[2].UserId)).toBe(nil)
		srv.mock.removePlayer(srv.players[1])   -- gone while the teleport loads
		srv.advance(20)   -- player 3 still loading (within DEPART.PENDING): not sent twice
		R.expect(#calls).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("walking from one pad to another: counted on the new one, the old one's clock stops", function()
		local srv, hub, calls = boot({ players = 1 })
		local p = srv.players[1]
		local a, b = hub:FindFirstChild("Depart_race"), hub:FindFirstChild("Depart_party2")
		standOn(p, a)
		srv.advance(5)
		standOn(p, b)
		srv.advance(5)
		R.expect(#calls).toBe(0)   -- 5 s on each: neither clock ran out
		R.expect(p:GetAttribute("DepartPad")).toBe("party2")
		R.expect(a:FindFirstChild("Status", true).Text).toBe("step on!")
		srv.advance(4)
		R.expect(#calls).toBe(1)
		R.expect(calls[1].options.ShouldReserveServer).toBe(true)
	end)

	R.it("one of a group fails on Roblox's side: only that one is told and may step on again", function()
		local srv, hub, calls = boot({ players = 2 })
		local pad = hub:FindFirstChild("Depart_party1")
		for i, p in ipairs(srv.players) do standOn(p, pad, i) end
		srv.advance(9)
		R.expect(#calls).toBe(1)
		local ts = srv.env.game:GetService("TeleportService")
		ts.TeleportInitFailed:Fire(srv.players[1], "Flooded", "too many")
		srv.advance(0.5)
		local told = {}
		for _, c in ipairs(rawget(srv.remote("TravelUpdate"), "_calls") or {}) do
			if c.method == "FireClient" and c.args[2].kind == "failed" then told[c.args[1]] = true end
		end
		R.expect(told[srv.players[1]]).toBe(true)
		R.expect(told[srv.players[2]]).toBe(nil)
		srv.advance(9)   -- player 1 is still on the pad: goes again alone; player 2 is loading
		R.expect(#calls).toBe(2)
		R.expect(#calls[2].players).toBe(1)
		R.expect(calls[2].players[1]).toBe(srv.players[1])
	end)

	R.it("bad or rushed PlaceAction calls are refused, never an error", function()
		local srv = boot({ players = 1 })
		local p = srv.players[1]
		local function act(...) local r = srv.mock.invoke(srv.remote("PlaceAction"), p, ...) srv.advance(2) return r end
		R.expect(act(nil)).toBe("denied: unknown")
		R.expect(act(5)).toBe("denied: unknown")
		R.expect(act({ "play" })).toBe("denied: unknown")
		R.expect(act("hub")).toBe("denied: not here")
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p, "play")).toBe("ok")
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p, "play")).toBe("denied: too fast")
		srv.advance(2)
		p.Character:FindFirstChild("HumanoidRootPart"):Destroy()
		srv.advance(2)
		R.expect(act("play")).toBe("denied: not ready")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a reset on a pad: the new character on the spawn is off the pad", function()
		local srv, hub, calls = boot({ players = 1 })
		local p = srv.players[1]
		standOn(p, hub:FindFirstChild("Depart_race"))
		srv.advance(4)
		local L = srv.env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		rootOf(p).CFrame = CFrame.new(L.SPAWN + Vector3.new(0, 4, 0))   -- respawned
		srv.advance(10)
		R.expect(#calls).toBe(0)
		R.expect(p:GetAttribute("DepartPad")).toBe(nil)
	end)

	R.it("runs for hours with people coming and going: never a round, no errors, the TV and pads keep up", function()
		local srv, hub, calls = boot({ players = 2 })
		local players = srv.env.game:GetService("Players")
		local n = 0
		for hour = 1, 2 do
			for k = 1, 12 do
				n += 1
				local p = srv.mock.addPlayer("Visitor" .. n, 9000 + n, Vector3.new(0, 5, 0))
				srv.advance(60)
				if k % 3 == 0 then standOn(p, hub:FindFirstChild("Depart_race")) end
				if k % 4 == 0 then srv.mock.removePlayer(players:GetPlayers()[1]) end
				srv.advance(240)
			end
		end
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		R.expect(srv.GameManager.getRound()).toBe(0)
		R.expect(#calls > 0).toBe(true)
		local count = hub:FindFirstChild("Screen"):FindFirstChild("Players", true).Text
		R.expect(count).toBe(string.format("%d in town", #players:GetPlayers()))
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("the hub with every server script (lobby phase 2)", function()
	local ALL = {
		"ServerScriptService.MapBuilders.ForestMapBuilder",
		"ServerScriptService.MapBuilders.OceanMapBuilder",
		"ServerScriptService.MapBuilders.SkyMapBuilder",
		"ServerScriptService.GameBootstrap",
		"ServerScriptService.MapManager",
		"ServerScriptService.ItemModelPreloader",
		"ServerScriptService.CharacterManager",
		"ServerScriptService.FarmingManager",
		"ServerScriptService.CraftingManager",
		"ServerScriptService.RacingManager",
		"ServerScriptService.AbilityManager",
		"ServerScriptService.HazardManager",
		"ServerScriptService.ProgressionManager",
		"ServerScriptService.ShopManager",
		"ServerScriptService.AnalyticsManager",
		"ServerScriptService.BadgeManager",
		"ServerScriptService.InviteManager",
		"ServerScriptService.RideShowManager",
		"ServerScriptService.ChallengeManager",
		"ServerScriptService.AchievementManager",
		"ServerScriptService.LegendManager",
		"ServerScriptService.LobbyManager",
		"ServerScriptService.DepartureManager",
	}

	R.it("an hour of shopping, Legend buys, invites, gadgets and pads in the hub: no round, no errors or warnings, coins add up", function()
		local calls, logged = {}, {}
		local srv = Server.boot({ live = true, players = 4, scripts = ALL, quiet = true,
			setup = function(env, Mock)
				env.requirePath("ReplicatedStorage.Shared.Places").RACE = RACE_ID
				Mock.props(env.game).PlaceId = HUB_ID
				rawset(env.game:GetService("TeleportService"), "TeleportAsync", function(_, placeId, players, options)
					table.insert(calls, { placeId = placeId, players = players })
				end)
				local Ref = env.requirePath("ServerScriptService.Modules.Referral")
				Ref.referrerOf = function(p) return p.UserId == 5001 and 1001 or nil end
				-- live servers log to AnalyticsService (the mock has none of it)
				local an = env.game:GetService("AnalyticsService")
				for _, m in ipairs({ "LogOnboardingFunnelStepEvent", "LogFunnelStepEvent", "LogEconomyEvent",
					"LogCustomEvent", "LogProgressionEvent", "LogProgressionCompleteEvent" }) do
					rawset(an, m, function(_, _, ...) table.insert(logged, m .. ":" .. tostring((...))) end)
				end
			end })
		srv.advance(2)
		local e = srv.env
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local a, b = srv.players[1], srv.players[2]
		for _, p in ipairs(srv.players) do PlayerStore.get(p).coins = 6000 end
		local l = LegendShop.listWinner(HallOfFame.entry(a.UserId, a.Name, "FOREST", { BODY = "Toilet" }, 3, {}))
		srv.advance(2)
		local function act(p, ...) local r = srv.mock.invoke(srv.remote("ShopAction"), p, ...) srv.advance(1) return r end
		R.expect(act(b, "buy", "hat_party").result).toBe("ok")
		R.expect(act(b, "equip", "hat_party").result).toBe("ok")
		R.expect(act(b, "legend_buy", l.id).result).toBe("ok")
		R.expect(b.Character:FindFirstChild(LegendShop.WORN) ~= nil).toBe(true, "the bought ride on in the hub")
		local aRec = PlayerStore.get(a)
		R.expect(aRec.coins).toBe(6000 + e.requirePath("ReplicatedStorage.Shared.Constants").LEGEND.ROYALTY)
		srv.mock.addPlayer("Friend", 5001, Vector3.new(0, 5, 0))   -- joined through a's invite
		srv.advance(5)
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), srv.players[3], "play")).toBe("ok")
		srv.advance(3600)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		R.expect(srv.GameManager.getRound()).toBe(0)
		R.expect(#calls >= 1).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
		R.expect(srv.mock.warnings or {}).toBeEmpty("server warnings")
		-- no Round funnel step in a place with no rounds
		for _, x in ipairs(logged) do
			R.expect(x:find("LogFunnelStepEvent", 1, true)).toBe(nil)
		end
	end)
end)

R.describe("the race place in every situation (lobby phase 2)", function()
	local function boot(opts)
		local calls = {}
		local srv = Server.boot({ live = true, players = opts.players or 1, scripts = ROUND_SCRIPTS, swallowErrors = true,
			setup = function(env, Mock)
				env.requirePath("ReplicatedStorage.Shared.Places").RACE = RACE_ID
				Mock.props(env.game).PlaceId = RACE_ID
				rawset(env.game:GetService("TeleportService"), "TeleportAsync", function(_, placeId, players, options)
					table.insert(calls, { placeId = placeId, players = players, options = options })
					return {}
				end)
			end })
		srv.advance(0.5)
		return srv, calls
	end

	R.it("a party arriving a few seconds apart starts a round; no start pads here", function()
		local srv = boot({ players = 1 })
		srv.advance(4)
		srv.mock.addPlayer("Friend", 8002, Vector3.new(0, 5, 0))
		srv.advance(4)
		srv.mock.addPlayer("Friend2", 8003, Vector3.new(0, 5, 0))
		R.expect(srv.env.workspace:FindFirstChild("LobbyHub"):FindFirstChild("Depart_race")).toBe(nil)
		R.expect(phaseLoop(srv, "FARMING", 40)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("← JUNK TOWN mid-race: that player goes, the race goes on for the rest, twice is refused", function()
		local srv, calls = boot({ players = 2 })
		R.expect(phaseLoop(srv, "RACING", 600)).toBe(true)
		local p = srv.players[1]
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p, "hub")).toBe("ok")
		srv.advance(2)
		R.expect(srv.mock.invoke(srv.remote("PlaceAction"), p, "hub")).toBe("denied: already going")
		R.expect(#calls).toBe(1)
		R.expect(calls[1].placeId).toBe(HUB_ID)
		srv.mock.removePlayer(p)   -- the teleport took them
		R.expect(phaseLoop(srv, "LOBBY", 400)).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

return R
