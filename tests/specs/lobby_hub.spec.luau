--!nocheck
-- Junk Town, the lobby hub (2026-11-17: "walk around the lobby, chat, see
-- the hall of fame, shop, like a Roblox room"; "talk to NPCs if bored").
-- Layout, the built plaza, and players in every situation: joining in each
-- phase, the LOBBY reload, a reset on the farm, many rounds.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local SCRIPTS = {
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
}

R.describe("Junk Town layout", function()
	local env = Loader.boot()
	local L = env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
	local Npcs = env.requirePath("ReplicatedStorage.Shared.LobbyNpcs")
	local O = L.ORIGIN

	R.it("floats far from every track, farm and scenery (> 1 000 studs in X from any track node)", function()
		for _, name in ipairs({ "ForestTrack", "OceanTrack", "SkyTrack" }) do
			local T = env.requirePath("ReplicatedStorage.Shared.Tracks." .. name)
			for _, n in ipairs(T.nodes) do
				local x, z = n[1] or n.x, n[2] or n.z
				R.expect((Vector3.new(x, 0, z) - Vector3.new(O.X, 0, O.Z)).Magnitude > 1000).toBe(true, name)
			end
		end
	end)

	R.it("every spot is on the plaza and nothing stands on top of anything else", function()
		local spots = {
			{ "spawn", L.SPAWN, 7 }, { "board", L.BOARD, 8 }, { "fountain", L.FOUNTAIN, 7 },
			{ "stage", L.STAGE.at, L.STAGE.radius + 2 }, { "shop", L.SHOP, 8 }, { "arch L", L.ARCH + Vector3.new(-9, 0, 0), 2.2 },
			{ "arch R", L.ARCH + Vector3.new(9, 0, 0), 2.2 },
		}
		for i, p in ipairs(L.SHOWCASE) do table.insert(spots, { "show" .. i, p, 5 }) end
		for i = 1, L.LEGEND_SLOTS do table.insert(spots, { "legend" .. i, L.legendSpot(i), 4.5 }) end
		for i = 1, L.TROPHY_SLOTS do table.insert(spots, { "trophy" .. i, L.trophySpot(i), 1.9 }) end
		for i, p in ipairs(L.TREES) do table.insert(spots, { "tree" .. i, p, 1 }) end
		for _, n in ipairs(Npcs.LIST) do table.insert(spots, { "npc " .. n.id, O + n.at, 1.5 }) end
		for i = 0, L.LAMPS - 1 do
			local a = (i + 0.5) / L.LAMPS * math.pi * 2
			table.insert(spots, { "lamp" .. i, O + Vector3.new(math.cos(a), 0, math.sin(a)) * L.LAMP_RADIUS, 1 })
		end
		for i, p in ipairs(L.BENCHES) do table.insert(spots, { "bench" .. i, p, 3 }) end
		table.insert(spots, { "stall", L.STALL, 6 })
		table.insert(spots, { "junk pile", L.JUNK_PILE, 8 })
		for i, p in ipairs(L.SCRAP_CARS) do table.insert(spots, { "scrap car" .. i, p, 7 }) end
		local bad = {}
		for i, a in ipairs(spots) do
			local d = Vector3.new(a[2].X - O.X, 0, a[2].Z - O.Z).Magnitude
			if d + a[3] > L.WALL_RADIUS then table.insert(bad, a[1] .. " past the wall") end
			for j = i + 1, #spots do
				local b = spots[j]
				local gap = Vector3.new(a[2].X - b[2].X, 0, a[2].Z - b[2].Z).Magnitude - a[3] - b[3]
				if gap < 1 then table.insert(bad, string.format("%s / %s (%.1f)", a[1], b[1], gap)) end
			end
		end
		R.expect(bad).toBeEmpty("crowded spots")
	end)

	R.it("the town stands round it: houses and trees on the island beyond the fence, clear of the stage, garage and teapot", function()
		local function around(angle, r) local a = math.rad(angle) return O + Vector3.new(math.cos(a), 0, math.sin(a)) * r end
		local big = {   -- things on the rim the houses must not stand in: { name, spot, radius }
			{ "stage backdrop", O + Vector3.new(0, 0, -L.STAGE.radius - 53), 17 },
			{ "garage wall", O + Vector3.new(-70, 0, 0), 24 },
			{ "teapot", O + Vector3.new(72, 0, -14), 12 },
		}
		local spots = {}
		for i, h in ipairs(L.HOUSES) do
			local r = h.height * 0.65   -- the widest model is about 1.3 × its height across
			table.insert(spots, { "house" .. i, around(h.angle, L.HOUSE_RADIUS), r })
			R.expect(L.HOUSE_RADIUS - r > L.WALL_RADIUS - 3).toBe(true, "house" .. i .. " in the plaza")
			R.expect(L.HOUSE_RADIUS + r < L.ISLAND_RADIUS + 6).toBe(true, "house" .. i .. " off the island")
		end
		for i, a in ipairs(L.OUTER_TREES) do table.insert(spots, { "tree" .. i, around(a, L.OUTER_TREE_RADIUS), 3 }) end
		local bad = {}
		for i, a in ipairs(spots) do
			for _, b in ipairs(big) do
				local gap = Vector3.new(a[2].X - b[2].X, 0, a[2].Z - b[2].Z).Magnitude - a[3] - b[3]
				if gap < 0 then table.insert(bad, string.format("%s / %s (%.1f)", a[1], b[1], gap)) end
			end
			for j = i + 1, #spots do
				local b = spots[j]
				local gap = Vector3.new(a[2].X - b[2].X, 0, a[2].Z - b[2].Z).Magnitude - a[3] - b[3]
				if gap < (a[1]:sub(1, 4) == "tree" and -2 or 0) then table.insert(bad, string.format("%s / %s (%.1f)", a[1], b[1], gap)) end
			end
		end
		R.expect(bad).toBeEmpty("crowded town")
	end)

	R.it("townsfolk: unique ids, a few lines each that fit the speech box, never the same line twice in a row", function()
		local seen = {}
		for _, n in ipairs(Npcs.LIST) do
			R.expect(seen[n.id]).toBe(nil)
			seen[n.id] = true
			R.expect(#n.lines >= 4).toBe(true, n.id)
			for _, line in ipairs(n.lines) do R.expect(#line <= 110).toBe(true, line) end
			local last = nil
			for _ = 1, 30 do
				local i = Npcs.pick(n, last, math.random)
				R.expect(i ~= last).toBe(true)
				last = i
			end
		end
	end)
end)

R.describe("Junk Town in a server", function()
	local function boot(opts)
		local srv = Server.boot({
			live = opts.live, players = opts.players or 1, scripts = SCRIPTS, setup = opts.setup,
			harness = not opts.live and { harness = "lune", biome = "FOREST", players = opts.players or 1, lobbyDelay = opts.lobbyDelay or 3,
				fillBots = 3, durations = opts.durations or { FARMING = 6, CRAFTING = 3, RESULTS = 4 } } or nil,
		})
		srv.advance(0.5)
		local L = srv.env.requirePath("ReplicatedStorage.Shared.LobbyLayout")
		local hub = srv.env.workspace:FindFirstChild("LobbyHub")
		return srv, L, hub
	end
	local function rootOf(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end

	R.it("is built: spawn, TV board, stage, six Legend pads, nine trophies, the shop prompt, six townsfolk who talk", function()
		local srv, L, hub = boot({})
		R.expect(hub ~= nil).toBe(true)
		local spawn = hub:FindFirstChild("LobbySpawn")
		R.expect(spawn and spawn.ClassName).toBe("SpawnLocation")
		R.expect(hub:FindFirstChild("Screen") ~= nil).toBe(true)
		R.expect(hub:FindFirstChild("WinnerSpot", true) ~= nil).toBe(true)
		for i = 1, L.LEGEND_SLOTS do R.expect(hub:FindFirstChild("LegendPad_" .. i, true) ~= nil).toBe(true) end
		local opens, talks, parts, loose = {}, {}, 0, {}
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				if d:GetAttribute("Opens") then opens[d:GetAttribute("Opens")] = true end
				if d:GetAttribute("Talk") then talks[d:GetAttribute("Talk")] = true end
			elseif d:IsA("BasePart") then
				parts += 1
				-- only townsfolk limbs hang on joints; everything else is fixed
				local npc = false
				local a = d.Parent
				while a and a ~= hub do
					if a:GetAttribute("Npc") then npc = true end
					a = a.Parent
				end
				if not d.Anchored and not npc then table.insert(loose, d.Name) end
			end
		end
		R.expect(opens.shop and opens.awards).toBe(true)
		local Npcs = srv.env.requirePath("ReplicatedStorage.Shared.LobbyNpcs")
		for _, n in ipairs(Npcs.LIST) do R.expect(talks[n.id]).toBe(true, n.id) end
		R.expect(parts < 1500).toBe(true, tostring(parts))
		R.expect(loose).toBeEmpty("loose parts")
		local trophies = 0
		for _, c in ipairs(hub:GetChildren()) do
			if c.Name:sub(1, 7) == "Trophy_" then trophies += 1 end
		end
		R.expect(trophies >= 5).toBe(true)   -- the hats; poses and the trail stand on plinths
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("with the Creator Store models baked in: the town is those models, at their spots and sizes, nothing on top of anything", function()
		-- stand-ins for ServerStorage.LobbyModels: each model's parts as plain blocks
		local function bake(env, Mock)
			local Instance = Mock.Instance
			local data = env.requirePath("ServerScriptService.Modules.LobbyModelData")
			local folder = Instance.new("Folder")
			folder.Name = "LobbyModels"
			for key, list in pairs(data) do
				local model = Instance.new("Model")
				model.Name = key
				for _, d in ipairs(list) do
					local p = Instance.new("Part")
					p.Size = Vector3.new(d.s[1], d.s[2], d.s[3])
					p.CFrame = CFrame.new(d.p[1], d.p[2], d.p[3])
					p.Parent = model
				end
				model.Parent = folder
			end
			folder.Parent = env.game:GetService("ServerStorage")
		end
		local srv, L, hub = boot({ setup = bake })
		local O = L.ORIGIN
		local placed, boxes = {}, {}
		-- each model's box in its own frame (all its parts turn together): centre, half sizes, yaw
		local function obb(model)
			local first = model:FindFirstChildWhichIsA("BasePart")
			local rot = first.CFrame.Rotation
			local lo, hi
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
						local c = rot:Inverse() * (d.CFrame * Vector3.new(sx * d.Size.X / 2, sy * d.Size.Y / 2, sz * d.Size.Z / 2))
						lo = lo and Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) or c
						hi = hi and Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) or c
					end end end
				end
			end
			local mid = rot * ((lo + hi) / 2)
			return { mid = mid, half = (hi - lo) / 2, ax = rot.RightVector, az = rot.LookVector,
				bottom = mid.Y - (hi.Y - lo.Y) / 2, top = mid.Y + (hi.Y - lo.Y) / 2 }
		end
		-- 2D separating axes: true when the two boxes overlap by more than `slack` on every axis
		local function overlaps(a, b, slack)
			if math.min(a.top, b.top) - math.max(a.bottom, b.bottom) <= slack then return false end   -- one on the other
			for _, axis in ipairs({ a.ax, a.az, b.ax, b.az }) do
				local n = Vector3.new(axis.X, 0, axis.Z).Unit
				local function reach(o) return math.abs(o.ax:Dot(n)) * o.half.X + math.abs(o.az:Dot(n)) * o.half.Z end
				local d = math.abs((a.mid - b.mid):Dot(n))
				if d > reach(a) + reach(b) - slack then return false end
			end
			return true
		end
		local function farthest(o)   -- the farthest footprint corner from the plaza's centre
			local best = 0
			for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local c = o.mid + o.ax * sx * o.half.X + o.az * sz * o.half.Z
				best = math.max(best, Vector3.new(c.X - O.X, 0, c.Z - O.Z).Magnitude)
			end end
			return best
		end
		local function nearest(o)    -- the nearest point of the footprint (corners and the centre's distance less its reach)
			local r = Vector3.new(o.mid.X - O.X, 0, o.mid.Z - O.Z)
			local n = r.Unit
			return r.Magnitude - (math.abs(o.ax:Dot(n)) * o.half.X + math.abs(o.az:Dot(n)) * o.half.Z)
		end
		for _, c in ipairs(hub:GetChildren()) do
			if c.Name:sub(1, 6) == "Store_" then
				local key = c.Name:sub(7)
				placed[key] = (placed[key] or 0) + 1
				local o = obb(c)
				o.key = key
				o.solid = c:FindFirstChildWhichIsA("BasePart").CanCollide
				table.insert(boxes, o)
			end
		end
		for _, key in ipairs({ "house_garden", "house_mushroom", "house_small", "house_big", "shop_awning", "fence",
			"lamp_plain", "lamp_fancy", "tree_round", "tree_puff", "tree_tall", "bench", "stall", "junk_pile",
			"scrap_car", "barrel_rusty", "barrel_metal", "pot_round", "crates", "crate" }) do
			R.expect((placed[key] or 0) > 0).toBe(true, key)
		end
		R.expect(placed.fence > 60).toBe(true, "fence pieces " .. tostring(placed.fence))
		-- no part-built stand-ins left where a model stands
		R.expect(hub:FindFirstChild("ShopBox")).toBe(nil)
		R.expect(hub:FindFirstChild("Plank")).toBe(nil)
		R.expect(hub:FindFirstChild("CanHouse")).toBe(nil)
		local bad = {}
		for _, b in ipairs(boxes) do
			-- on the ground, or stacked on another model (barrels, crates)
			local resting = math.abs(b.bottom - O.Y) < 0.05
			for _, o in ipairs(boxes) do
				if o ~= b and math.abs(b.bottom - o.top) < 0.05 and overlaps(
					{ mid = b.mid, half = b.half, ax = b.ax, az = b.az, bottom = 0, top = 1 },
					{ mid = o.mid, half = o.half, ax = o.ax, az = o.az, bottom = 0, top = 1 }, 0.5) then resting = true end
			end
			if not resting then table.insert(bad, b.key .. string.format(" floats or sinks (%.2f)", b.bottom - O.Y)) end
			if b.key:sub(1, 6) == "house_" then
				if nearest(b) < L.WALL_RADIUS - 2 then table.insert(bad, b.key .. string.format(" in the plaza (%.1f)", nearest(b))) end
				if farthest(b) > L.ISLAND_RADIUS + 4 then table.insert(bad, b.key .. string.format(" off the island (%.1f)", farthest(b))) end
				if b.half.Y * 2 > 26 then table.insert(bad, b.key .. " too tall") end
			elseif b.solid and farthest(b) > L.WALL_RADIUS then
				table.insert(bad, b.key .. string.format(" past the wall (%.1f)", farthest(b)))
			end
		end
		for i, a in ipairs(boxes) do
			for j = i + 1, #boxes do
				local b = boxes[j]
				if a.solid and b.solid and overlaps(a, b, 0.5) then table.insert(bad, string.format("%s / %s", a.key, b.key)) end
			end
		end
		R.expect(bad).toBeEmpty("misplaced models")
		local parts, opens = 0, {}
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("BasePart") then parts += 1 end
			if d:IsA("ProximityPrompt") and d:GetAttribute("Opens") then opens[d:GetAttribute("Opens")] = true end
		end
		R.expect(opens.shop).toBe(true)
		R.expect(parts < 2500).toBe(true, tostring(parts))
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("every player respawns on the plaza; one standing elsewhere in the lobby is brought over", function()
		local srv, L, hub = boot({ lobbyDelay = 30 })
		local p = srv.players[1]
		R.expect(p.RespawnLocation).toBe(hub:FindFirstChild("LobbySpawn"))
		-- a character that loaded somewhere else (the old place spawn)
		rootOf(p).CFrame = CFrame.new(0, 5, 0)
		local late = srv.mock.addPlayer("Late", 3003, Vector3.new(10, 5, 10))
		srv.advance(1)
		R.expect(late.RespawnLocation).toBe(hub:FindFirstChild("LobbySpawn"))
		R.expect(L.onPlaza(rootOf(late).Position)).toBe(true)
	end)

	-- race map labels seen from Junk Town (SKY's checkpoint labels are seen
	-- through walls from 1 500 studs: "CP 2" over the Legend pads, Studio)
	local function mapLabels(srv)
		local lit = {}
		for _, d in ipairs(srv.env.workspace:FindFirstChild("Maps"):GetDescendants()) do
			if d:IsA("BillboardGui") and d.Enabled and d.AlwaysOnTop then
				table.insert(lit, d.Parent and d.Parent.Name or "?")
			end
		end
		return lit
	end

	R.it("a whole round: plaza → farm at FARMING → back on the plaza at the next LOBBY; the board follows", function()
		local srv, L, hub = boot({ lobbyDelay = 4 })
		R.expect(mapLabels(srv)).toBeEmpty("map labels on in the first lobby")
		local p = srv.players[1]
		local screen = hub:FindFirstChild("Screen")
		local function line(name) return screen:FindFirstChild(name, true).Text end
		srv.advance(5)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
		srv.advance(2)
		-- FarmRescue takes anyone still on the plaza to the farm
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(false)
		R.expect(line("Track")).toBe("🌲 FOREST")
		R.expect(line("Count")).toBe("grabbing junk")
		-- the rest of the round (RESULTS ends in LOBBY)
		local t = 0
		while srv.GameManager.getPhase() ~= "LOBBY" and t < 400 do
			srv.advance(1)
			t += 1
		end
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		srv.advance(2)   -- the lobby lasts lobbyDelay (4 s): still in it
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(true)
		R.expect(mapLabels(srv)).toBeEmpty("map labels on in the next lobby")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("someone joining mid-race lands on the plaza and watches from there", function()
		local srv, L = boot({ lobbyDelay = 1, durations = { FARMING = 1, CRAFTING = 1, RESULTS = 30 } })
		local t = 0
		while srv.GameManager.getPhase() ~= "RACING" and t < 60 do
			srv.advance(0.5)
			t += 1
		end
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local late = srv.mock.addPlayer("Watcher", 4004, Vector3.new(0, 5, 0))
		late.Character.Parent = nil
		late.Character.Parent = srv.env.workspace
		srv.mock.fireCharacterAdded = srv.mock.fireCharacterAdded
		-- the character came in at the place's spawn: CharacterAdded moves it
		local char = late.Character
		srv.advance(0.1)
		if late.CharacterAdded then late.CharacterAdded:Fire(char) end
		srv.advance(1)
		R.expect(L.onPlaza(rootOf(late).Position)).toBe(true)
	end)

	R.it("a reset on the farm respawns on the plaza and is taken back to the farm", function()
		local srv, L = boot({ lobbyDelay = 1, durations = { FARMING = 60, CRAFTING = 3, RESULTS = 4 } })
		srv.advance(3)
		R.expect(srv.GameManager.getPhase()).toBe("FARMING")
		local p = srv.players[1]
		rootOf(p).CFrame = CFrame.new(L.SPAWN + Vector3.new(0, 4, 0))   -- as if respawned there
		local hb = srv.env.game:GetService("RunService").Heartbeat   -- FarmRescue runs on Heartbeat
		srv.advance(3, 1 / 30, function() hb:Fire(1 / 30) end)
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(false)
		local FB = srv.env.requirePath("ReplicatedStorage.Shared.FarmBounds")
		R.expect(FB.offFarm("FOREST", rootOf(p).Position)).toBe(nil)   -- on the farm
	end)

	R.it("falling off the island or over the fence in the lobby puts you back on the spawn", function()
		local srv, L = boot({ lobbyDelay = 60 })
		local p = srv.players[1]
		srv.advance(1)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		rootOf(p).CFrame = CFrame.new(L.ORIGIN + Vector3.new(30, -40, 10))   -- under the island
		srv.advance(1)
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(true)
		rootOf(p).CFrame = CFrame.new(L.ORIGIN + Vector3.new(L.RADIUS + 10, 5, 0))   -- past the fence, in the air
		srv.advance(1)
		R.expect(L.onPlaza(rootOf(p).Position)).toBe(true)
	end)

	R.it("players arriving together spread out on the spawn; someone leaving mid-lobby breaks nothing", function()
		local srv, L = boot({ lobbyDelay = 60, players = 1 })
		local a = srv.mock.addPlayer("A", 5001, Vector3.new(0, 5, 0))
		local b = srv.mock.addPlayer("B", 5002, Vector3.new(0, 5, 0))
		srv.advance(1)
		R.expect(L.onPlaza(rootOf(a).Position) and L.onPlaza(rootOf(b).Position)).toBe(true)
		R.expect((rootOf(a).Position - rootOf(b).Position).Magnitude > 1).toBe(true)
		srv.mock.removePlayer(a)
		srv.advance(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("someone joining during the results lands on the plaza", function()
		local srv, L = boot({ lobbyDelay = 1, durations = { FARMING = 1, CRAFTING = 1, RESULTS = 60 } })
		local t = 0
		while srv.GameManager.getPhase() ~= "RESULTS" and t < 400 do
			srv.advance(1)
			t += 1
		end
		R.expect(srv.GameManager.getPhase()).toBe("RESULTS")
		local late = srv.mock.addPlayer("Late", 6006, Vector3.new(0, 5, 0))
		srv.advance(1)
		R.expect(L.onPlaza(rootOf(late).Position)).toBe(true)
	end)

	R.it("the hall of fame stage and the Legend pads follow the vote's winner", function()
		local srv, L, hub = boot({ lobbyDelay = 60 })
		local e = srv.env
		local HallOfFame = e.requirePath("ServerScriptService.Modules.HallOfFame")
		local LegendShop = e.requirePath("ServerScriptService.Modules.LegendShop")
		local p = srv.players[1]
		local entry = HallOfFame.entry(p.UserId, "Ann", "FOREST", { BODY = "Shopping Cart", ENGINE = "Rocket" }, 3, {})
		HallOfFame.record(entry)
		LegendShop.listWinner(entry)
		srv.advance(3)   -- the folders appear, the lobby notices within a second or two
		local live = hub:FindFirstChild("Live")
		local winner = live:FindFirstChild("Winner")
		R.expect(winner ~= nil).toBe(true)
		local cf, size = winner:GetBoundingBox()
		R.expect(math.abs((cf.Position.Y - size.Y / 2) - (L.STAGE.at.Y + L.STAGE.height)) < 0.2).toBe(true,
			string.format("bottom %.2f stage %.2f", cf.Position.Y - size.Y / 2, L.STAGE.at.Y + L.STAGE.height))
		R.expect((Vector3.new(cf.Position.X, 0, cf.Position.Z) - Vector3.new(L.STAGE.at.X, 0, L.STAGE.at.Z)).Magnitude < 3).toBe(true)
		R.expect(hub:FindFirstChild("WinnerSpot", true):FindFirstChild("Name", true).Text).toBe("🏆 Ann")
		-- readable from the plaza (reel 2026-11-17: "can't even tell it's a
		-- toilet"): WINNER_LENGTH long, on the stage; the name and the sign
		-- over it, not behind it
		local long = math.max(size.X, size.Z)
		R.expect(math.abs(long - L.WINNER_LENGTH) < 0.5).toBe(true, string.format("length %.1f", long))
		R.expect(long <= L.STAGE.radius * 2).toBe(true)
		local top = cf.Position.Y + size.Y / 2
		R.expect(hub:FindFirstChild("WinnerSpot", true).Position.Y > top).toBe(true, "name over the statue")
		local header = hub:FindFirstChild("HallHeader", true)
		local hcf, hsize = header:GetBoundingBox()
		R.expect(hcf.Position.Y - hsize.Y / 2 > top).toBe(true, "the HALL OF FAME sign over the statue")
		R.expect(live:FindFirstChild("Legend_1") ~= nil).toBe(true)
		local pad = hub:FindFirstChild("LegendPad_1", true)
		R.expect(pad:FindFirstChildWhichIsA("ProximityPrompt"):GetAttribute("Opens")).toBe("legend")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the live lobby: the TV counts down to the round", function()
		local srv, _, hub = boot({ live = true, players = 1 })
		srv.advance(3)
		R.expect(srv.GameManager.getPhase()).toBe("LOBBY")
		local count = hub:FindFirstChild("Screen"):FindFirstChild("Count", true).Text
		R.expect(count:find("starts in", 1, true) ~= nil).toBe(true, count)
	end)
end)

R.describe("Junk Town on the client", function()
	R.it("the lobby screen no longer covers the world; prompts open the shop and townsfolk talk", function()
		local ui = fs.readFile("roblox/StarterGui/LobbyUI/init.client.lua")
		R.expect(ui:find('"Background"', 1, true)).toBe(nil)
		R.expect(ui:find("Shared.Invite).button(", 1, true) ~= nil).toBe(true)
		local client = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/LobbyHubClient.client.lua")
		for _, needle in ipairs({ 'GetAttribute("Talk")', 'GetAttribute("Opens")', "DisplayBubble", 'FindFirstChild("Open")' }) do
			R.expect(client:find(needle, 1, true) ~= nil).toBe(true, needle)
		end
	end)
end)

return R
