--!nocheck
-- FARMING and CRAFTING with the real server scripts and bots.
local R = require("../lib/runner")
local Server = require("../lib/server")
local MatchSim = require("../lib/matchsim")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

R.describe("farming match (6 bots, real FarmingManager/CraftingManager)", function()
	local m = MatchSim.run({ players = 6, seed = 11 })

	R.it("runs without server script errors", function()
		R.expect(m.serverErrors).toBeEmpty("errors raised inside server scripts")
	end)

	R.it("every bot collects items and gets a car", function()
		local bad = {}
		for _, p in ipairs(m.results) do
			if #p.inventory == 0 then table.insert(bad, p.name .. " collected nothing") end
			if not p.maxSpeed then table.insert(bad, p.name .. " has no car") end
		end
		R.expect(bad).toBeEmpty("bots without items or cars")
	end)

	R.it("pickups never exceed the items spawned (start + waves) and put back (swaps)", function()
		local total = 0
		for _, p in ipairs(m.results) do total += p.farm.pickups end
		R.expect(m.spawned).toBeGreaterThan(0)
		R.expect(total).toBeAtMost(m.spawned + m.dropped)
	end)
end)

-- Small focused scenarios on a bare server.
local function farmServer(nPlayers)
	local srv = Server.boot({
		players = nPlayers,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = nPlayers, lobbyDelay = 0,
			durations = { FARMING = 60, CRAFTING = 5, RACING = 600 } },
	})
	srv.advance(0.5)
	return srv
end

R.describe("farming rules", function()
	R.it("two players at one item get a contest that resolves to one winner", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local item
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then item = d break end
		end
		local pos = item.Parent.Position
		a.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		b.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		local res = srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, item.Value)
		R.expect(res).toBe("contested")
		for i = 1, 30 do
			srv.advance(0.1)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, a, item.Value, i * 2)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, b, item.Value, i)
		end
		local results = srv.Telemetry.events("contest_result")
		R.expect(#results).toBe(1)
		R.expect(results[1].winner).toBe(a.UserId)
		R.expect(#srv.SessionManager.getData(a).inventory).toBe(1)
		R.expect(#srv.SessionManager.getData(b).inventory).toBe(0)
	end)

	R.it("a contest nobody presses in still ends when its time is up", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local item
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then item = d break end
		end
		local pos = item.Parent.Position
		a.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		b.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, item.Value)).toBe("contested")
		-- both players walk away without pressing
		srv.advance(5)
		R.expect(#srv.Telemetry.events("contest_result")).toBe(1)
		local got = #srv.SessionManager.getData(a).inventory + #srv.SessionManager.getData(b).inventory
		R.expect(got).toBe(1)
	end)

	R.it("a steal never pushes the thief past the 8-slot inventory",
		function()
			local srv = farmServer(2)
			local thief, victim = srv.players[1], srv.players[2]
			local td, vd = srv.SessionManager.getData(thief), srv.SessionManager.getData(victim)
			for i = 1, 8 do td.inventory[i] = "Pizza" end
			vd.inventory[1] = "Kettle"
			thief.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 850)
			victim.Character.HumanoidRootPart.Position = Vector3.new(2, 3, 850)
			srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, victim.UserId)
			srv.advance(1.5)
			R.expect(#td.inventory).toBeAtMost(8)
		end)

	R.it("auto-submit puts items in matching slots",
		function()
			local srv = farmServer(1)
			local p = srv.players[1]
			local data = srv.SessionManager.getData(p)
			srv.advance(60) -- FARMING ends → CRAFTING
			data.inventory = { "Kettle", "Trophy", "Log" } -- ENGINE, SPECIAL, BODY
			srv.advance(6) -- CRAFTING timer expires → auto-submit
			local slots = data.vehicleStats and data.vehicleStats.slotAssignments or {}
			local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
			local wrong = {}
			for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL" }) do
				local item = slots[slot]
				if item and ItemConfig[item].slotType ~= slot then
					table.insert(wrong, slot .. " ← " .. item .. " (" .. ItemConfig[item].slotType .. ")")
				end
			end
			R.expect(wrong).toBeEmpty("auto-assigned items in the wrong slot")
		end)
end)

-- Steals with several players (Studio check 2026-10-20 found these by
-- reading FarmingManager; each case failed before the fix).
R.describe("steals with several players", function()
	local function setup(n)
		local srv = farmServer(n)
		for i, p in ipairs(srv.players) do
			p.Character.HumanoidRootPart.Position = Vector3.new(i, 3, 850)
			local d = srv.SessionManager.getData(p)
			d.inventory = { "Kettle", "Log" }
		end
		return srv
	end
	local function inv(srv, p) return #srv.SessionManager.getData(p).inventory end
	local function attempts(srv, result)
		local n = 0
		for _, e in ipairs(srv.Telemetry.events("steal_attempt")) do
			if result == nil or e.result == result then n += 1 end
		end
		return n
	end

	R.it("a DefendSteal sent before any attempt does not block the next steal", function()
		local srv = setup(2)
		local thief, victim = srv.players[1], srv.players[2]
		srv.mock.invoke(srv.RemoteEvents.DefendSteal, victim)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, victim.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, victim)).toBe(1)
		R.expect(inv(srv, thief)).toBe(3)
	end)

	R.it("one tap is not a defence; STEAL_DEFEND_PRESSES taps in the window are", function()
		local srv = setup(3)
		local thief, v1, v2 = srv.players[1], srv.players[2], srv.players[3]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, v1.UserId)
		srv.advance(0.2)
		srv.mock.invoke(srv.RemoteEvents.DefendSteal, v1)
		srv.advance(1.3)
		R.expect(inv(srv, v1)).toBe(1)

		srv.advance(10) -- thief cooldown
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, v2.UserId)
		srv.advance(0.2)
		for _ = 1, srv.env.requirePath("ReplicatedStorage.Shared.Constants").STEAL_DEFEND_PRESSES do
			srv.mock.invoke(srv.RemoteEvents.DefendSteal, v2)
		end
		srv.advance(1.3)
		R.expect(inv(srv, v2)).toBe(2)
		R.expect(attempts(srv, "defended")).toBe(1)
		R.expect(attempts(srv, "stolen")).toBe(1)
	end)

	R.it("a thief cannot run two steals at once", function()
		local srv = setup(3)
		local thief = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[2].UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[3].UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, thief, srv.players[3].UserId)
		srv.advance(1.5)
		R.expect(inv(srv, thief)).toBe(3)
		R.expect(inv(srv, srv.players[2]) + inv(srv, srv.players[3])).toBe(3)
	end)

	R.it("two thieves at one victim take one item; the victim is then protected", function()
		local srv = setup(3)
		local victim = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, srv.players[2], victim.UserId)
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, srv.players[3], victim.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, victim)).toBe(1)
		R.expect(attempts(srv, "stolen")).toBe(1)
	end)

	R.it("nobody can steal from themselves", function()
		local srv = setup(1)
		local p = srv.players[1]
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, p, p.UserId)
		srv.advance(1.5)
		R.expect(inv(srv, p)).toBe(2)
		R.expect(attempts(srv, "stolen")).toBe(0)
	end)

	R.it("items are conserved: a steal moves an item, never copies or loses one", function()
		local srv = setup(4)
		local before = 0
		for _, p in ipairs(srv.players) do before += inv(srv, p) end
		for round = 1, 6 do
			for i, p in ipairs(srv.players) do
				local target = srv.players[(i + round - 1) % #srv.players + 1]
				srv.mock.invoke(srv.RemoteEvents.RequestSteal, p, target.UserId)
			end
			srv.advance(0.5)
			srv.mock.invoke(srv.RemoteEvents.DefendSteal, srv.players[round % 4 + 1])
			srv.advance(4)
		end
		local after = 0
		for _, p in ipairs(srv.players) do after += inv(srv, p) end
		R.expect(after).toBe(before)
		R.expect(attempts(srv, "stolen")).toBeGreaterThan(0)
	end)
end)

R.describe("crafting input from clients", function()
	local function craftServer()
		local srv = farmServer(2)
		srv.advance(60) -- FARMING → CRAFTING
		return srv
	end

	R.it("a malformed submission is refused without a server error", function()
		local srv = craftServer()
		local p = srv.players[1]
		local res = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, nil)
		srv.advance(0.1)
		R.expect(res).toBe("denied: bad slots")
		local res2 = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, "BODY")
		R.expect(res2).toBe("denied: bad slots")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("core slots only take items of their type; unknown slots are dropped", function()
		local srv = craftServer()
		local p = srv.players[1]
		local data = srv.SessionManager.getData(p)
		data.inventory = { "Kettle", "Log", "Trophy" } -- ENGINE, BODY, SPECIAL
		local res = srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p,
			{ BODY = "Kettle", ENGINE = "Log", SPECIAL = "Trophy", WINGS = "Log" })
		R.expect(res).toBe("ok")
		local slots = data.vehicleStats.slotAssignments
		R.expect(slots.BODY).toBe(nil)
		R.expect(slots.ENGINE).toBe(nil)
		R.expect(slots.SPECIAL).toBe("Trophy")
		R.expect(slots.WINGS).toBe(nil)
		local craft = srv.Telemetry.events("craft")
		R.expect(#craft[#craft].rejected).toBe(3)
	end)

	R.it("one item cannot fill two slots", function()
		local srv = craftServer()
		local p = srv.players[1]
		local data = srv.SessionManager.getData(p)
		data.inventory = { "Log" }
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, p, { BODY = "Log", MOBILITY = "Log" })
		local slots = data.vehicleStats.slotAssignments
		local n = 0
		for _, v in pairs(slots) do if v == "Log" then n += 1 end end
		R.expect(n).toBe(1)
	end)

	R.it("players who do not submit get an auto craft, marked as such", function()
		local srv = craftServer()
		local a, b = srv.players[1], srv.players[2]
		srv.SessionManager.getData(a).inventory = { "Log" }
		srv.SessionManager.getData(b).inventory = { "Kettle" }
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, a, { BODY = "Log" })
		srv.advance(6) -- CRAFTING timer → RACING → auto submit
		local byUser = {}
		for _, e in ipairs(srv.Telemetry.events("craft")) do byUser[e.userId] = e end
		R.expect(byUser[a.UserId].auto).toBe(false)
		R.expect(byUser[b.UserId].auto).toBe(true)
		R.expect(byUser[b.UserId].slots.ENGINE).toBe("Kettle")
	end)

	-- Estimated 2026-10-23: a first-timer needs 60–90 s, the hurry rule cut
	-- them off around 65 s and the auto craft threw away what they had placed.
	R.it("when the timer runs out, a player's placed items stay where they put them", function()
		local srv = craftServer()
		local a = srv.players[1]
		local data = srv.SessionManager.getData(a)
		-- two BODY items: the auto craft alone would take the first (Log)
		data.inventory = { "Log", "Barrel", "Kettle", "Trophy", "Pizza" }
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, { BODY = "Barrel", HEAD = "Pizza" })
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, { BODY = "Barrel", HEAD = "Trophy", ENGINE = "Log" })
		srv.advance(6) -- CRAFTING timer → RACING → auto submit
		local craft
		for _, e in ipairs(srv.Telemetry.events("craft")) do if e.userId == a.UserId then craft = e end end
		R.expect(craft.auto).toBe(true)
		R.expect(craft.slots.BODY).toBe("Barrel")      -- the player's pick, not the first BODY
		R.expect(craft.slots.HEAD).toBe("Trophy")      -- the latest draft wins
		R.expect(craft.slots.ENGINE).toBe("Kettle")    -- a wrong-type pick is dropped and the slot filled
		R.expect(craft.slots.SPECIAL).toBe("Pizza")    -- empty slots are filled from what is left
		R.expect(craft.draft.BODY).toBe("Barrel")
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the showroom: every slot change builds the vehicle into the player's PlayerGui", function()
		local srv = craftServer()
		local a = srv.players[1]
		local gui = srv.mock.Instance.new("Folder")
		gui.Name = "PlayerGui"
		gui.Parent = a
		srv.SessionManager.getData(a).inventory = { "Pizza", "Kettle", "Log", "Rubber Duck" }
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, { BODY = "Log" })
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, { BODY = "Pizza", ENGINE = "Kettle", MOBILITY = "Rubber Duck" })   -- a burst: the latest wins
		srv.advance(0.5)
		local folder = gui:FindFirstChild("CraftPreview")
		R.expect(folder ~= nil).toBe(true)
		local models = folder:GetChildren()
		R.expect(#models).toBe(1)
		R.expect(models[1]:GetAttribute("Riding")).toBe("Pizza")
		local hubs, tagged = {}, 0
		for _, d in ipairs(models[1]:GetDescendants()) do
			R.expect(d:IsA("BodyMover") or d:IsA("BodyGyro") or d:IsA("BodyPosition")).toBe(false)
			if d:IsA("BasePart") and d.Name:sub(1, 8) == "SpinHub_" then hubs[d.Name] = true end
		end
		-- the duck wheels' parts know their hub, so the showroom can turn them
		for _, d in ipairs(models[1]:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("SpinHub") then
				R.expect(hubs[d:GetAttribute("SpinHub")]).toBe(true)
				tagged += 1
			end
		end
		R.expect(tagged >= 4).toBe(true)
		srv.advance(6)   -- RACING: the showroom closes
		R.expect(#folder:GetChildren()).toBe(0)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a draft naming items the player does not hold is ignored", function()
		local srv = craftServer()
		local a = srv.players[1]
		srv.SessionManager.getData(a).inventory = { "Log" }
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, { BODY = "Microwave", HEAD = "Log", TAIL = "Log" })
		srv.RemoteEvents.CraftDraft.OnServerEvent:Fire(a, "junk")
		srv.advance(6)
		local slots = srv.SessionManager.getData(a).vehicleStats.slotAssignments
		R.expect(slots.BODY).toBe(nil)
		R.expect(slots.HEAD).toBe("Log")
		R.expect(slots.TAIL).toBe(nil)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("CraftingRules.autoSlots (Auto fill button and timeout craft)", function()
	local CraftingRules, ItemConfig
	local function load()
		local env = require("../lib/loader").boot()
		CraftingRules = env.requirePath("ReplicatedStorage.Shared.CraftingRules")
		ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	end

	R.it("puts every core slot's own type there, whatever the inventory order", function()
		load()
		local slots = CraftingRules.autoSlots({ "Pizza", "Kettle", "Trophy", "Log", "Fan", "Barrel" }, ItemConfig)
		R.expect(slots.BODY).toBe("Log")
		R.expect(slots.ENGINE).toBe("Kettle")
		R.expect(slots.SPECIAL).toBe("Pizza")
		local clean, rejected = CraftingRules.validate(slots, { "Pizza", "Kettle", "Trophy", "Log", "Fan", "Barrel" }, ItemConfig)
		R.expect(#rejected).toBe(0)
		local n = 0
		for _ in pairs(clean) do n += 1 end
		R.expect(n).toBe(6)
	end)

	R.it("keeps the given slots and uses each held item once", function()
		load()
		local slots = CraftingRules.autoSlots({ "Log", "Log", "Kettle" }, ItemConfig, { TAIL = "Log" })
		R.expect(slots.TAIL).toBe("Log")
		R.expect(slots.BODY).toBe("Log")
		R.expect(slots.ENGINE).toBe("Kettle")
		R.expect(slots.MOBILITY).toBe(nil)
	end)

	R.it("BODY takes an item you can ride (Pizza), not any other non-BODY item", function()
		load()
		R.expect(CraftingRules.fits("BODY", ItemConfig["Pizza"])).toBe(true)
		R.expect(CraftingRules.fits("BODY", ItemConfig["Rubber Duck"])).toBe(true)
		R.expect(CraftingRules.fits("BODY", ItemConfig["Magnet"])).toBe(false)
		R.expect(CraftingRules.fits("SPECIAL", ItemConfig["Pizza"])).toBe(true)
		R.expect(CraftingRules.fits("ENGINE", ItemConfig["Pizza"])).toBe(false)
		local clean, rejected = CraftingRules.validate({ BODY = "Pizza", SPECIAL = "Magnet" }, { "Pizza", "Magnet" }, ItemConfig)
		R.expect(clean.BODY).toBe("Pizza")
		R.expect(#rejected).toBe(0)
		local _, bad = CraftingRules.validate({ BODY = "Magnet" }, { "Magnet" }, ItemConfig)
		R.expect(#bad).toBe(1)
	end)

	R.it("no BODY item: the auto craft rides a rideable leftover, a BODY item still wins", function()
		load()
		local slots = CraftingRules.autoSlots({ "Magnet", "Pizza", "Kettle", "Rubber Duck" }, ItemConfig)
		R.expect(slots.SPECIAL).toBe("Magnet")
		R.expect(slots.BODY).toBe("Pizza")
		local with = CraftingRules.autoSlots({ "Pizza", "Rubber Duck", "Log" }, ItemConfig)
		R.expect(with.BODY).toBe("Log")
		R.expect(with.SPECIAL).toBe("Pizza")
	end)

	R.it("a ridden item counts with its ride weight and grip, below the BODY items", function()
		local env = require("../lib/loader").boot()
		local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
		load()
		for _, name in ipairs({ "Pizza", "Rubber Duck", "Rocket", "Toilet Paper" }) do
			local cfg = ItemConfig[name]
			local ridden = VehicleStats.calculate(cfg, nil, nil, "FOREST")
			local same = VehicleStats.calculate({ weight = cfg.ride.weight, grip = cfg.ride.grip, rarity = cfg.rarity }, nil, nil, "FOREST")
			R.expect(math.abs(ridden.stability - same.stability) < 1e-6).toBe(true)
		end
	end)
end)

-- Studio steal-crowd-6p (2026-10-20): a player's inventory shrank with no
-- event. With a full inventory, RequestPickup dropped the weakest item BEFORE
-- the distance and contest checks, so a refused pickup or a lost contest cost
-- an item for nothing.
R.describe("full inventory and a rarer item", function()
	local function setup(n)
		local srv = farmServer(n)
		local ItemConfig = srv.env.requirePath("ReplicatedStorage.Shared.ItemConfig")
		local common
		for name, cfg in pairs(ItemConfig) do
			if type(cfg) == "table" and cfg.rarity == "Common" then common = name break end
		end
		local rare
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" then
				local name = d.Parent:FindFirstChild("ItemName")
				local cfg = name and ItemConfig[name.Value]
				if cfg and cfg.rarity ~= "Common" then rare = d break end
			end
		end
		for _, p in ipairs(srv.players) do
			local data = srv.SessionManager.getData(p)
			data.inventory = {}
			for i = 1, 8 do data.inventory[i] = common end
		end
		return srv, rare
	end

	R.it("a pickup refused for distance keeps the inventory", function()
		local srv, rare = setup(1)
		local p = srv.players[1]
		p.Character.HumanoidRootPart.Position = rare.Parent.Position + Vector3.new(40, 2, 0)
		local res = srv.mock.invoke(srv.RemoteEvents.RequestPickup, p, rare.Value)
		R.expect(tostring(res):find("too far") ~= nil).toBe(true)
		R.expect(#srv.SessionManager.getData(p).inventory).toBe(8)
	end)

	R.it("losing the contest for it keeps the inventory; winning swaps the weakest", function()
		local srv, rare = setup(2)
		local a, b = srv.players[1], srv.players[2]
		local pos = rare.Parent.Position
		local name = rare.Parent.ItemName.Value
		a.Character.HumanoidRootPart.Position = pos + Vector3.new(2, 2, 0)
		b.Character.HumanoidRootPart.Position = pos + Vector3.new(-2, 2, 0)
		srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, rare.Value)
		for i = 1, 30 do
			srv.advance(0.1)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, a, rare.Value, i)
			srv.mock.invoke(srv.RemoteEvents.RequestContest, b, rare.Value, i * 2)
		end
		local ad, bd = srv.SessionManager.getData(a), srv.SessionManager.getData(b)
		R.expect(#ad.inventory).toBe(8)
		R.expect(#bd.inventory).toBe(8)
		R.expect(table.find(bd.inventory, name) ~= nil).toBe(true)
		R.expect(table.find(ad.inventory, name) == nil).toBe(true)
		-- the swapped-out item is logged
		local drops = srv.Telemetry.events("item_drop")
		R.expect(#drops).toBe(1)
		R.expect(drops[1].userId).toBe(b.UserId)
	end)
end)

R.describe("late client scripts", function()
	-- Studio steal-crowd-6p: bot clients that loaded after the FARMING event
	-- never farmed. The phase is also an attribute they can read on start.
	R.it("ReplicatedStorage carries the current phase and biome", function()
		local srv = farmServer(1)
		local RS = srv.env.game.ReplicatedStorage
		R.expect(RS:GetAttribute("Phase")).toBe("FARMING")
		R.expect(RS:GetAttribute("Biome")).toBe("FOREST")
		srv.advance(60)
		R.expect(RS:GetAttribute("Phase")).toBe("CRAFTING")
	end)
end)

-- Fights (2026-10-22): F punches the player you face; HITS_TO_DROP landed
-- hits knock a random item onto the ground; G guards.
R.describe("fights: punches pile up and knock an item loose", function()
	local function setup()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		-- A faces -Z (default), B stands 4 studs in front of A
		a.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 3, 850)
		b.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 3, 846)
		srv.SessionManager.getData(b).inventory = { "Kettle", "Log", "Pizza" }
		local F = srv.env.requirePath("ReplicatedStorage.Shared.Constants").FIGHT
		local function punch() local r = srv.mock.invoke(srv.RemoteEvents.RequestPunch, a); srv.advance(F.COOLDOWN + 0.05); return r end
		return srv, a, b, F, punch
	end

	R.it("HITS_TO_DROP landed punches drop one item on the ground", function()
		local srv, _, b, F, punch = setup()
		for i = 1, F.HITS_TO_DROP - 1 do R.expect(punch()).toBe("hit") end
		R.expect(#srv.SessionManager.getData(b).inventory).toBe(3)
		R.expect(punch()).toBe("knockout")
		R.expect(#srv.SessionManager.getData(b).inventory).toBe(2)
		local drops = srv.Telemetry.events("item_drop")
		R.expect(drops[#drops].reason).toBe("knocked_out")
	end)

	R.it("right after a knock-out the victim is immune", function()
		local srv, _, _, F, punch = setup()
		for _ = 1, F.HITS_TO_DROP do punch() end
		R.expect(punch()).toBe("immune")
		srv.advance(F.DROP_IMMUNE)
		R.expect(punch()).toBe("hit")
	end)

	R.it("a guarding victim blocks; hits are forgotten after HIT_MEMORY", function()
		local srv, _, b, F, punch = setup()
		R.expect(punch()).toBe("hit")
		srv.RemoteEvents.SetGuard.OnServerEvent:Fire(b, true)
		R.expect(punch()).toBe("blocked")
		srv.RemoteEvents.SetGuard.OnServerEvent:Fire(b, false)
		srv.advance(F.HIT_MEMORY + 0.5)
		for _ = 1, F.HITS_TO_DROP - 1 do R.expect(punch()).toBe("hit") end   -- the first hit was forgotten
	end)

	R.it("a guard cannot be held forever", function()
		local srv, _, b, F, punch = setup()
		srv.RemoteEvents.SetGuard.OnServerEvent:Fire(b, true)
		srv.advance(F.GUARD_MAX + 0.2)
		R.expect(punch()).toBe("hit")
	end)

	R.it("a punch needs reach, facing, and the cooldown", function()
		local srv, a, b, F = setup()
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPunch, a)).toBe("hit")
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPunch, a)).toBe("denied: cooldown")
		srv.advance(F.COOLDOWN + 0.05)
		b.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 3, 854)   -- behind A
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPunch, a)).toBe("miss")
		srv.advance(F.COOLDOWN + 0.05)
		b.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 3, 850 - F.RANGE - 2)   -- too far
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPunch, a)).toBe("miss")
	end)

	R.it("every punch is logged with its result", function()
		local srv, _, _, _, punch = setup()
		punch()
		local ev = srv.Telemetry.events("punch")
		R.expect(ev[#ev].result).toBe("hit")
	end)
end)

-- Idle time (Studio match reports, 2026-10-22): with 100 items for 4 players
-- every inventory was full 15–50 s into the 90 s FARMING phase; ready
-- crafters waited up to 2 minutes for the slowest one.
R.describe("idle time", function()
	local function itemCount(srv)
		local n = 0
		for _, d in ipairs(srv.env.workspace:GetDescendants()) do
			if d.Name == "ItemId" and d.ClassName == "StringValue" and d.Parent and d.Parent.Parent then n += 1 end
		end
		return n
	end
	local function screenCalls(srv, name)
		local n = 0
		for _, c in ipairs(rawget(srv.RemoteEvents.ScreenEffect, "_calls") or {}) do
			if c.args[1] == name or c.args[2] == name then n += 1 end
		end
		return n
	end

	R.it("FARMING starts with items for the players there, and waves of rarer items land later", function()
		local C = Server.boot({ players = 1, scripts = {} }).env.requirePath("ReplicatedStorage.Shared.Constants")
		local srv = farmServer(4)
		local start = itemCount(srv)
		R.expect(start).toBe(C.farmSupply(4))
		srv.advance(60 * C.FARM_SUPPLY.WAVES[1].at + 0.5)
		R.expect(itemCount(srv)).toBe(start + math.ceil(4 * C.FARM_SUPPLY.WAVES[1].perPlayer))
		R.expect(screenCalls(srv, "itemWave")).toBe(1)
		srv.advance(60 * (C.FARM_SUPPLY.WAVES[2].at - C.FARM_SUPPLY.WAVES[1].at))
		R.expect(screenCalls(srv, "itemWave")).toBe(2)
		local waves = srv.Telemetry.events("item_wave")
		R.expect(#waves).toBe(3)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("once half the players have crafted, the rest get CRAFT_HURRY seconds, not the whole phase", function()
		local srv = Server.boot({
			players = 4,
			scripts = { "ServerScriptService.MapBuilders.ForestMapBuilder", "ServerScriptService.GameBootstrap",
				"ServerScriptService.FarmingManager", "ServerScriptService.CraftingManager" },
			harness = { harness = "lune", biome = "FOREST", players = 4, lobbyDelay = 0,
				durations = { FARMING = 1, CRAFTING = 120, RACING = 600 } },
		})
		srv.advance(2)
		local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
		R.expect(srv.GameManager.getPhase()).toBe("CRAFTING")
		local RS = srv.env.game:GetService("ReplicatedStorage")
		local now = srv.env.workspace:GetServerTimeNow()
		R.expect(RS:GetAttribute("PhaseEndsAt") - now).toBeGreaterThan(100)
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, srv.players[1], {})
		R.expect(RS:GetAttribute("PhaseEndsAt") - now).toBeGreaterThan(100)   -- one of four: no hurry yet
		srv.mock.invoke(srv.RemoteEvents.SubmitCraft, srv.players[2], {})
		R.expect(RS:GetAttribute("PhaseEndsAt") - now).toBeNear(C.CRAFT_HURRY.SECONDS, 0.5)
		R.expect(screenCalls(srv, "craftHurry")).toBe(2)   -- told to the two still crafting
		srv.advance(C.CRAFT_HURRY.SECONDS + 0.5)
		R.expect(srv.GameManager.getPhase()).toBe("RACING")
		local auto = 0
		for _, e in ipairs(srv.Telemetry.events("craft")) do if e.auto then auto += 1 end end
		R.expect(auto).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("dropping an item (Q, swap, knock-out)", function()
	local function farmActions(srv, kind)
		local out = {}
		for _, c in ipairs(rawget(srv.RemoteEvents.FarmAction, "_calls") or {}) do
			if c.method == "FireAllClients" and c.args[1] == kind then table.insert(out, c.args) end
		end
		return out
	end

	R.it("puts the item back on the map, ahead of the player, where anyone can pick it up", function()
		local srv = farmServer(2)
		local a, b = srv.players[1], srv.players[2]
		local C = srv.env.requirePath("ReplicatedStorage.Shared.Constants")
		a.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(10, 3, 850)   -- faces -Z (on the farm: drops stay inside its walls)
		srv.SessionManager.getData(a).inventory = { "Kettle", "Pizza" }
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestDrop, a, 2)).toBe("ok")
		R.expect(table.concat(srv.SessionManager.getData(a).inventory, ",")).toBe("Kettle")
		local placed = srv.Telemetry.events("item_dropped_world")
		R.expect(#placed).toBe(1)
		R.expect(placed[1].item).toBe("Pizza")
		R.expect(placed[1].parts).toBeGreaterThan(0)
		-- landed ahead (-Z) of the dropper, about DROP_TOSS studs away
		R.expect(placed[1].z).toBeLessThan(850 - C.DROP_TOSS + 2)
		R.expect(placed[1].z).toBeGreaterThan(850 - C.DROP_TOSS - 3)
		-- the dropped Pizza is a pickable item again, for the other player
		local tag
		for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
			if d.Name == "ItemId" and d.Value == tostring(placed[1].itemId) then tag = d end
		end
		R.expect(tag ~= nil).toBe(true)
		b.Character.HumanoidRootPart.Position = tag.Parent.Position + Vector3.new(1, 2, 0)
		a.Character.HumanoidRootPart.Position = Vector3.new(200, 3, 900)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, b, tag.Value)).toBe("ok")
		R.expect(table.concat(srv.SessionManager.getData(b).inventory, ",")).toBe("Pizza")
	end)

	R.it("tells every client to draw the throw, from the dropper to the landing spot", function()
		local srv = farmServer(2)
		local a = srv.players[1]
		a.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 3, 850)
		srv.SessionManager.getData(a).inventory = { "Log" }
		srv.mock.invoke(srv.RemoteEvents.RequestDrop, a, 1)
		local drops = farmActions(srv, "drop")
		R.expect(#drops).toBe(1)
		local _, who, _, info = table.unpack(drops[1], 1, 4)
		R.expect(who).toBe(a.UserId)
		R.expect(info.item).toBe("Log")
		R.expect(info.model ~= nil and info.model.Parent ~= nil).toBe(true)
		R.expect(info.to ~= nil and info.from ~= nil).toBe(true)
	end)
end)
