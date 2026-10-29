--!nocheck
-- The farms (playtest 2026-10-29: "the farm could be smaller and nobody
-- should fall off"): each one is Shared/FarmBounds' box, closed by invisible
-- walls, items and spawn markers on its floor inside them, and FarmRescue
-- puts back whoever still gets off it.
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local BUILDERS = { FOREST = "Forest", OCEAN = "Ocean", SKY = "Sky" }
-- the part people stand on, per biome (its top is the floor)
local FLOOR = { FOREST = "FarmGround", OCEAN = "FarmGrass", SKY = "FarmPlatform" }
-- spans before the change (wall to wall)
local OLD = { FOREST = { 220, 320 }, OCEAN = { 180, 260 }, SKY = { 200, 240 } }

local function farm(biome, opts)
	opts = opts or {}
	local name = BUILDERS[biome]
	local srv = Server.boot({
		players = opts.players or 1,
		scripts = {
			"ServerScriptService.MapBuilders." .. name .. "MapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = biome, players = opts.players or 1, lobbyDelay = 0, fillBots = opts.fillBots,
			durations = { FARMING = 90, CRAFTING = 5, RACING = 600 } },
	})
	local e = srv.env
	local FarmBots = e.requirePath("ServerScriptService.Modules.FarmBots")
	FarmBots.kinematic = true
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	tick(0.5)
	local FB = e.requirePath("ReplicatedStorage.Shared.FarmBounds")
	local map = e.workspace.Maps[name .. "Map"]
	return srv, FB, FB.get(biome), map, tick, FarmBots
end

local function top(p) return p.Position.Y + p.Size.Y / 2 end

R.describe("farm bounds (Shared/FarmBounds, Maps/FarmKit, FarmRescue)", function()
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": the farm is under half its old span (playtest 2026-10-30: smaller still)", function()
			local _, _, b = farm(biome)
			local sx, sz = 2 * b.halfX / OLD[biome][1], 2 * b.halfZ / OLD[biome][2]
			R.expect(sx).toBeGreaterThan(0.38); R.expect(sx).toBeLessThan(0.5)
			R.expect(sz).toBeGreaterThan(0.38); R.expect(sz).toBeLessThan(0.5)
		end)

		R.it(biome .. ": four solid, invisible walls close the farm, tall enough to never clear", function()
			local _, FB, b, map = farm(biome)
			local area = map.FarmArea
			local walls = {}
			for _, d in ipairs(area:GetDescendants()) do
				if d:GetAttribute("FarmWall") then walls[d.Name] = d end
			end
			for _, n in ipairs({ "FarmWall_N", "FarmWall_S", "FarmWall_W", "FarmWall_E" }) do
				local w = walls[n]
				R.expect(w ~= nil).toBe(true)
				R.expect(w.CanCollide).toBe(true)
				R.expect(w.Transparency).toBe(1)
				R.expect(w.Position.Y - w.Size.Y / 2).toBeLessThan(b.floorY + 1e-6)
				R.expect(top(w)).toBeGreaterThan(b.floorY + 30)
			end
			-- each side covers the whole edge, corners included: no gap
			local n, s, wv, ev = walls.FarmWall_N, walls.FarmWall_S, walls.FarmWall_W, walls.FarmWall_E
			for _, w in ipairs({ n, s }) do
				R.expect(w.Position.X - w.Size.X / 2).toBeLessThan(b.cx - b.halfX - FB.WALL_THICK + 1e-6)
				R.expect(w.Position.X + w.Size.X / 2).toBeGreaterThan(b.cx + b.halfX + FB.WALL_THICK - 1e-6)
			end
			for _, w in ipairs({ wv, ev }) do
				R.expect(w.Position.Z - w.Size.Z / 2).toBeLessThan(b.cz - b.halfZ - FB.WALL_THICK + 1e-6)
				R.expect(w.Position.Z + w.Size.Z / 2).toBeGreaterThan(b.cz + b.halfZ + FB.WALL_THICK - 1e-6)
			end
			R.expect(n.Position.Z + n.Size.Z / 2).toBeLessThan(b.cz - b.halfZ + 1e-6)
			R.expect(s.Position.Z - s.Size.Z / 2).toBeGreaterThan(b.cz + b.halfZ - 1e-6)
			R.expect(wv.Position.X + wv.Size.X / 2).toBeLessThan(b.cx - b.halfX + 1e-6)
			R.expect(ev.Position.X - ev.Size.X / 2).toBeGreaterThan(b.cx + b.halfX - 1e-6)
		end)

		R.it(biome .. ": the floor reaches the walls; spawn markers and items are on it, inside them", function()
			local srv, FB, b, map = farm(biome, { fillBots = 4 })
			local floor = map.FarmArea:FindFirstChild(FLOOR[biome], true)
			R.expect(math.abs(top(floor) - b.floorY)).toBeLessThan(1e-3)
			R.expect(floor.Size.X / 2).toBeGreaterThan(b.itemHalfX)
			R.expect(floor.Size.Z / 2).toBeGreaterThan(b.itemHalfZ)
			-- what people walk on reaches the walls (no gap to step into)
			local ground = biome == "OCEAN" and map.FarmArea:FindFirstChild("FarmIsland", true) or floor
			R.expect(ground.Size.X / 2).toBeGreaterThan(b.halfX - 1e-6)
			R.expect(ground.Size.Z / 2).toBeGreaterThan(b.halfZ - 1e-6)
			local markers = 0
			for _, d in ipairs(map.FarmArea:GetDescendants()) do
				if d.Name == "FarmSpawnPoint" then
					markers += 1
					R.expect(FB.itemSpotOk(biome, d.Position.X, d.Position.Z)).toBe(true)
					R.expect(math.abs(d.Position.Y - (b.floorY + 0.5))).toBeLessThan(1e-3)
				end
			end
			R.expect(markers).toBeGreaterThan(7)
			local items = 0
			for _, d in ipairs(map:GetDescendants()) do
				if d.Name == "ItemId" then
					items += 1
					local p = d.Parent.Position
					local dx, dz = math.abs(p.X - b.cx), math.abs(p.Z - b.cz)
					if dx > b.itemHalfX + 4 or dz > b.itemHalfZ + 4 then
						error(("item at %.0f, %.0f is outside the farm"):format(p.X, p.Z))
					end
					R.expect(p.Y).toBeGreaterThan(b.floorY - 1)
					R.expect(p.Y).toBeLessThan(b.floorY + 12)
				end
			end
			R.expect(items).toBeGreaterThan(5)
			-- bots appear on the floor, inside the walls, apart from each other
			local roots = {}
			for _, bot in ipairs(srv.SessionManager.bots()) do
				local r = bot.Character.HumanoidRootPart
				R.expect(FB.offFarm(biome, r.Position)).toBe(nil)
				R.expect(math.abs(r.Position.Y - (b.floorY + FB.SPAWN_LIFT))).toBeLessThan(0.5)
				for _, o in ipairs(roots) do
					R.expect((Vector3.new(o.X, 0, o.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude)
						.toBeGreaterThan(FB.BOT_GAP - 1e-6)
				end
				table.insert(roots, r.Position)
			end
			R.expect(#roots).toBe(3)
			R.expect(srv.mock.errors).toBeEmpty("server errors")
		end)

		R.it(biome .. ": whoever falls, is flung or gets out is put back on the farm", function()
			local srv, FB, b, _, tick, FarmBots = farm(biome, { fillBots = 2 })
			FarmBots.paused = true
			local player = srv.players[1]
			local bot = srv.SessionManager.bots()[1]
			tick(FB.GRACE + FB.CHECK_EVERY)
			local before = #srv.Telemetry.events("farm_rescue")   -- the start (no CharacterManager here)
			local pr, br = player.Character.HumanoidRootPart, bot.Character.HumanoidRootPart
			pr.CFrame = CFrame.new(b.cx + 10, b.floorY - 40, b.cz)        -- fell
			br.CFrame = CFrame.new(b.cx - 10, b.floorY + 120, b.cz + 5)   -- flung
			tick(FB.CHECK_EVERY + 0.1)
			R.expect(FB.offFarm(biome, pr.Position)).toBe(nil)
			R.expect(FB.offFarm(biome, br.Position)).toBe(nil)
			pr.CFrame = CFrame.new(b.cx + b.halfX + 30, b.floorY + 3, b.cz)  -- out (a respawn in the lobby)
			tick(FB.CHECK_EVERY + 0.1)
			R.expect(FB.offFarm(biome, pr.Position)).toBe(nil)
			local why = {}
			local evs = srv.Telemetry.events("farm_rescue")
			for i = before + 1, #evs do why[evs[i].reason] = (why[evs[i].reason] or 0) + 1 end
			R.expect(why.fell).toBe(1)
			R.expect(why.flung).toBe(1)
			R.expect(why.out).toBe(1)
		end)
	end

	R.it("items never land inside the FOREST barn; drops stay inside the walls", function()
		local srv, FB, b = farm("FOREST")
		math.randomseed(3)
		for _ = 1, 3000 do
			local p = FB.randomItemSpot("FOREST", math.random)
			R.expect(FB.itemSpotOk("FOREST", p.X, p.Z)).toBe(true)
		end
		local x, z = FB.clamp("FOREST", b.cx + 500, b.cz - 500)
		R.expect(FB.itemSpotOk("FOREST", x, z)).toBe(true)
		-- a player at the wall drops an item: it lands inside
		local player = srv.players[1]
		srv.SessionManager.getData(player).inventory = { "Kettle" }
		player.Character.HumanoidRootPart.CFrame = CFrame.new(b.cx + b.halfX - 1, b.floorY + 3, b.cz)
			* CFrame.Angles(0, -math.pi / 2, 0)   -- facing +X, into the wall
		srv.mock.invoke(srv.RemoteEvents.RequestDrop, player, 1)
		local ev = srv.Telemetry.events("item_dropped_world")
		R.expect(#ev).toBe(1)
		R.expect(ev[1].x).toBeLessThan(b.cx + b.itemHalfX + 1)
	end)

	R.it("rescue is off outside FARMING (walls and rescue belong to the farm)", function()
		local srv, FB, b, map, tick = farm("SKY")
		srv.GameManager.shortenPhase("FARMING", 0.1)
		tick(FB.GRACE + 1)
		R.expect(srv.GameManager.getPhase()).toBe("CRAFTING")
		local pr = srv.players[1].Character.HumanoidRootPart
		pr.CFrame = CFrame.new(b.cx, b.floorY - 40, b.cz)
		tick(1)
		R.expect(#srv.Telemetry.events("farm_rescue")).toBe(0)
	end)
end)
