--!nocheck
-- Every item in every slot it fits, on every biome, does what its data says:
--   * E abilities (BODY / ENGINE / SPECIAL, AbilityConfig with its biome
--     variant): the car lists it (VehicleBuilder attributes, what
--     RacingClient fires), the real AbilityManager takes it, something lands
--     (speed, turn, lift, shield, drop, shove, gauge, cleanse) where the
--     data says, and every effect drawn has a look the client can draw
--     (EffectLook.CAR style → a STYLES function in the EffectFx client).
--   * HEAD / TAIL passives (VehicleStats.HEAD_PASSIVES / TAIL_PASSIVES)
--     against a player and against a race bot.
-- The abilities spec fires each item once in its own slot on FOREST only.
local R = require("../lib/runner")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local BIOMES = { "FOREST", "OCEAN", "SKY" }
local BUILDERS = {
	FOREST = "ServerScriptService.MapBuilders.ForestMapBuilder",
	OCEAN = "ServerScriptService.MapBuilders.OceanMapBuilder",
	SKY = "ServerScriptService.MapBuilders.SkyMapBuilder",
}
local CORE = { "BODY", "ENGINE", "SPECIAL" }
local SLOT_PLAYER = { BODY = 1, ENGINE = 2, SPECIAL = 3 }   -- one activator per slot: no shared cooldowns

-- Client draw styles (StarterPlayerScripts/EffectFx: STYLES.<name> = function)
local CLIENT_STYLES = {}
do
	local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/EffectFx.client.lua")
	for name in src:gmatch("\nSTYLES%.(%w+)%s*=%s*function") do CLIENT_STYLES[name] = true end
end

-- Wraps module functions so the spec sees what lands.
local function spy(e, log)
	local function wrap(path, fname, rec)
		local M = e.requirePath(path)
		local orig = M[fname]
		M[fname] = function(...)
			table.insert(log, rec(...))
			return orig(...)
		end
	end
	wrap("ServerScriptService.Modules.VehicleTuning", "set", function(seat, prop, id, mult)
		return { kind = "tune", seat = seat, prop = prop, id = id, mult = mult }
	end)
	wrap("ServerScriptService.Modules.VehicleTuning", "cleanse", function(seat)
		return { kind = "cleanse", seat = seat }
	end)
	wrap("ServerScriptService.Modules.VehicleLift", "set", function(vehicle, id, studs)
		return { kind = "lift", vehicle = vehicle, studs = studs }
	end)
	wrap("ServerScriptService.Modules.RaceEffects", "grant", function(player, flag)
		return { kind = "flag", who = player, flag = flag }
	end)
	wrap("ServerScriptService.Modules.TrackDrops", "place", function(item)
		return { kind = "drop", item = item }
	end)
	wrap("ServerScriptService.Modules.BoostGauge", "fill", function(id)
		return { kind = "gauge", id = id }
	end)
	wrap("ServerScriptService.Modules.RaceBots", "knock", function(id)
		return { kind = "knock", id = id }
	end)
	wrap("ServerScriptService.Modules.EffectFx", "play", function(key, who)
		return { kind = "fx", key = key, who = who }
	end)
end

local function abilityRig(biome)
	local log = {}
	local srv = Server.boot({
		players = 4,
		swallowErrors = true,
		quiet = true,
		scripts = { BUILDERS[biome], "ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager", "ServerScriptService.AbilityManager" },
		harness = { harness = "lune", biome = biome, players = 4, lobbyDelay = 0,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 5000 } },
		setup = function(e) spy(e, log) end,
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local RaceGrid = e.requirePath("ServerScriptService.Modules.RaceGrid")
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	local grid = RaceGrid.cframes(biome)
	local front = grid[1]
	for _, cf in ipairs(grid) do if cf.Position.Z < front.Position.Z then front = cf end end
	local base = CFrame.new(0, front.Position.Y, front.Position.Z)
	-- activator in the middle, one car ahead, one behind, one beside
	local spots = {
		base,
		base * CFrame.new(0, 0, -14),
		base * CFrame.new(0, 0, 12),
		base * CFrame.new(8, 0, 0),
	}
	local cars = {}
	for i, p in ipairs(srv.players) do
		local stats = VehicleStats.calculate(nil, nil, nil, biome)
		stats.slotAssignments = {}
		local model = VehicleBuilder.build(stats, biome, spots[i], {})
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
		cars[i] = { player = p, model = model, stats = stats }
	end
	srv.advance(C.RACE_COUNTDOWN + 0.5)
	return srv, cars, spots, log
end

-- What one ability did: actions by target ("self" / "other"), from the log.
local function summarize(srv, cars, me, from, log)
	local out = { self = {}, other = {}, fx = {}, any = false }
	local function whoOfSeat(seat)
		for _, c in ipairs(cars) do
			if seat and seat:IsDescendantOf(c.model) then return c.player end
		end
	end
	local function whoOfVehicle(v)
		for _, c in ipairs(cars) do if c.model == v then return c.player end end
	end
	for i = from + 1, #log do
		local a = log[i]
		local who
		if a.kind == "tune" or a.kind == "cleanse" then who = whoOfSeat(a.seat)
		elseif a.kind == "lift" then who = whoOfVehicle(a.vehicle)
		elseif a.kind == "flag" or a.kind == "fx" then who = a.who
		elseif a.kind == "gauge" then who = (a.id == me.UserId) and me or nil
		end
		if a.kind == "fx" then
			table.insert(out.fx, a.key)
		else
			local tag = a.kind .. (a.prop and (":" .. a.prop) or "")
			local side = (who == me or a.kind == "drop") and out.self or out.other
			side[tag] = true
			out.any = true
		end
	end
	return out
end

for _, biome in ipairs(BIOMES) do
	R.describe(biome .. ": every item's ability from every slot it fits", function()
		local srv, cars, spots, log = abilityRig(biome)
		local e = srv.env
		local ItemConfig = e.requirePath("ReplicatedStorage.Shared.ItemConfig")
		local AbilityConfig = e.requirePath("ServerScriptService.Modules.AbilityConfig")
		local CraftingRules = e.requirePath("ReplicatedStorage.Shared.CraftingRules")
		local AbilitySlots = e.requirePath("ReplicatedStorage.Shared.AbilitySlots")
		local EffectLook = e.requirePath("ReplicatedStorage.Shared.EffectLook")
		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleTuning = e.requirePath("ServerScriptService.Modules.VehicleTuning")
		local RaceEffects = e.requirePath("ServerScriptService.Modules.RaceEffects")

		local cases = {}
		local names = {}
		for name, cfg in pairs(ItemConfig) do
			if type(cfg) == "table" and cfg.slotType then table.insert(names, name) end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			for _, slot in ipairs(CORE) do
				if CraftingRules.fits(slot, ItemConfig[name]) then table.insert(cases, { item = name, slot = slot }) end
			end
		end

		local results = {}
		local function clean()
			for i, c in ipairs(cars) do
				local seat = c.model:FindFirstChildWhichIsA("VehicleSeat", true)
				if seat then VehicleTuning.clear(seat) end
				RaceEffects.reset(c.player)
				c.model:PivotTo(spots[i])
				c.model:SetAttribute("LiftOffset", nil)
			end
		end
		local function errorsSince(n)
			local out = {}
			for i = n + 1, #srv.mock.errors do table.insert(out, srv.mock.errors[i]) end
			return out
		end
		for _, case in ipairs(cases) do
			clean()
			srv.advance(0.6)
			local me = cars[SLOT_PLAYER[case.slot]]
			-- activator in the middle, the others round it
			local order = { me }
			for _, c in ipairs(cars) do if c ~= me then table.insert(order, c) end end
			for i, c in ipairs(order) do c.model:PivotTo(spots[i]) end
			me.stats.slotAssignments = { [case.slot] = case.item }
			AbilitySlots.write(me.model, me.stats.slotAssignments)
			local errs0 = #srv.mock.errors
			local from = #log
			local res = srv.mock.invoke(srv.RemoteEvents.RequestAbility, me.player, case.item)
			srv.advance(0.6)
			local s = summarize(srv, cars, me.player, from, log)
			s.result, s.errors = res, errorsSince(errs0)
			s.cfg = AbilityConfig.get(case.item, biome)
			results[case.item .. " @" .. case.slot] = s
			srv.advance(0.4)
		end
		clean()

		R.it("the built car lists the item for E in that slot and carries its model", function()
			local bad = {}
			for _, case in ipairs(cases) do
				local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
				local slots = { [case.slot] = case.item }
				local model = VehicleBuilder.build(VehicleStats.calculate(nil, nil, nil, biome), biome, CFrame.new(0, 500, 0), slots)
				local listed = AbilitySlots.read(model)[case.slot] == case.item   -- what RacingClient fires with E
				if not listed then table.insert(bad, case.item .. " @" .. case.slot .. ": not listed for E") end
				if not model:FindFirstChild("Item_" .. case.slot .. "_" .. case.item, true) then
					table.insert(bad, case.item .. " @" .. case.slot .. ": no item model on the car")
				end
				model:Destroy()
			end
			R.expect(bad).toBeEmpty("cars")
		end)

		R.it("fires (\"ok\") with no server error", function()
			local bad = {}
			for k, s in pairs(results) do
				if s.result ~= "ok" then table.insert(bad, k .. ": " .. tostring(s.result)) end
				for _, err in ipairs(s.errors) do table.insert(bad, k .. ": " .. err:sub(1, 160)) end
			end
			table.sort(bad)
			R.expect(bad).toBeEmpty("abilities")
		end)

		R.it("lands: something changes on a car or the track, where the data says", function()
			local bad = {}
			for k, s in pairs(results) do
				local cfg = s.cfg or {}
				local function need(cond, what) if not cond then table.insert(bad, k .. " (" .. tostring(cfg.effectKey) .. "): " .. what) end end
				need(s.any, "nothing but a label")
				if cfg.selfSpeed and cfg.selfSpeed ~= 1 then need(s.self["tune:MaxSpeed"], "selfSpeed set but the user's speed never changed") end
				if cfg.selfTurn and cfg.selfTurn ~= 1 then need(s.self["tune:TurnSpeed"], "selfTurn set but the user's turning never changed") end
				if cfg.victimSpeed and cfg.victimSpeed ~= 1 and cfg.targetType ~= "track_drop" then
					need(s.other["tune:MaxSpeed"] or s.other["flag"], "victimSpeed set but no other car slowed")
				end
				if cfg.victimTurn and cfg.victimTurn ~= 1 then need(s.other["tune:TurnSpeed"], "victimTurn set but no other car's turning changed") end
				if cfg.targetType == "track_drop" then need(s.self.drop, "a drop item placed nothing on the track") end
			end
			table.sort(bad)
			R.expect(bad).toBeEmpty("abilities that did not do what their data says")
		end)

		R.it("every effect it shows has a look and the client can draw that style", function()
			local bad = {}
			for k, s in pairs(results) do
				if #s.fx == 0 then table.insert(bad, k .. ": draws nothing") end
				for _, key in ipairs(s.fx) do
					local look = EffectLook.CAR[key]
					if not look then
						table.insert(bad, k .. ": no EffectLook.CAR." .. key)
					elseif not CLIENT_STYLES[look.style] then
						table.insert(bad, k .. ": style " .. tostring(look.style) .. " has no client STYLES function")
					end
				end
			end
			table.sort(bad)
			R.expect(bad).toBeEmpty("effects")
		end)

		R.it("every effect wears off (no seat left changed)", function()
			srv.advance(30)
			local bad = {}
			for _, c in ipairs(cars) do
				local seat = c.model:FindFirstChildWhichIsA("VehicleSeat", true)
				for _, prop in ipairs({ "MaxSpeed", "TurnSpeed" }) do
					local b = VehicleTuning.base(seat, prop)
					if math.abs(seat[prop] - b) > 1e-6 then
						table.insert(bad, string.format("%s %s %.1f (base %.1f)", c.player.Name, prop, seat[prop], b))
					end
				end
			end
			R.expect(bad).toBeEmpty("seats")
		end)
	end)
end

-- ── HEAD / TAIL passives ─────────────────────────────────────────────────────

local function passiveRig(fillBots)
	local log = {}
	local srv = Server.boot({
		players = fillBots and 1 or 2,
		quiet = true,
		scripts = { BUILDERS.FOREST, "ServerScriptService.GameBootstrap", "ServerScriptService.RacingManager" },
		harness = { harness = "lune", biome = "FOREST", players = fillBots and 1 or 2, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 900 } },
		setup = function(e) spy(e, log) end,
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local C = e.requirePath("ReplicatedStorage.Shared.Constants")
	local RaceBots = e.requirePath("ServerScriptService.Modules.RaceBots")
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	local function car(p, slots, cf)
		local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
		stats.slotAssignments = slots
		local model = VehicleBuilder.build(stats, "FOREST", cf, slots)
		model.Parent = e.workspace
		srv.SessionManager.setVehicle(p, model, stats)
		return model
	end
	return srv, car, tick, C, RaceBots, log
end

-- `back` rear-ends `front` (both facing -Z, the race direction).
local function rearEnd(back, front, z)
	back:PivotTo(CFrame.new(0, 2, z + 6))
	front:PivotTo(CFrame.new(0, 2, z))
	back.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -60)
	front.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -20)
	back.PrimaryPart.Touched:Fire(front.PrimaryPart)
end

local function landed(log, from, kind, key)
	for i = from + 1, #log do
		local a = log[i]
		if a.kind == kind and (key == nil or a.key == key or a.id == key or a.flag == key) then return true end
	end
	return false
end

R.describe("HEAD / TAIL passives", function()
	for _, vsBot in ipairs({ false, true }) do
		local against = vsBot and "a race bot" or "a player"
		local function setup(mySlots, otherSlots)
			local srv, car, tick, C, RaceBots, log = passiveRig(vsBot and 2 or nil)
			tick(0.5)
			local me = car(srv.players[1], mySlots, CFrame.new(0, 2, 560))
			local other, otherWho
			if vsBot then
				local bot = RaceBots.list[1]
				-- give the bot the build under test
				local d = srv.SessionManager.getData(bot.proxy)
				d.vehicleStats.slotAssignments = otherSlots
				bot.slots = otherSlots
				other, otherWho = bot.model, bot.proxy
			else
				other, otherWho = car(srv.players[2], otherSlots, CFrame.new(0, 2, 540)), srv.players[2]
			end
			tick(C.RACE_COUNTDOWN + 0.5)
			return srv, tick, C, log, me, other, otherWho
		end

		R.it("vs " .. against .. ": Shopping Cart HEAD shoves the car it rear-ends harder (cartShove)", function()
			local srv, tick, C, log, me, other = setup({ HEAD = "Shopping Cart" }, {})
			local from = #log
			rearEnd(me, other, 500)
			tick(0.1)
			R.expect(landed(log, from, "fx", "cartShove")).toBe(true)
			R.expect(srv.mock.errors).toBeEmpty("server errors")
		end)

		R.it("vs " .. against .. ": Cactus HEAD slows the car it rear-ends", function()
			local _, tick, _, log, me, other, otherWho = setup({ HEAD = "Cactus" }, {})
			local from = #log
			rearEnd(me, other, 500)
			tick(0.1)
			local slowed = false
			for i = from + 1, #log do
				local a = log[i]
				if a.kind == "tune" and a.id == "cactusHead" and a.seat:IsDescendantOf(other) then slowed = true end
			end
			R.expect(slowed).toBe(true)
		end)

		R.it("vs " .. against .. ": Balloon Bunch TAIL takes a rear-end without a shove (bumperAbsorb)", function()
			local _, tick, _, log, me, other = setup({ HEAD = "Shopping Cart" }, { TAIL = "Balloon Bunch" })
			local from = #log
			rearEnd(me, other, 500)
			tick(0.1)
			R.expect(landed(log, from, "fx", "bumperAbsorb")).toBe(true)
			R.expect(landed(log, from, "fx", "cartShove")).toBe(false)
		end)

		R.it("vs " .. against .. ": Cactus TAIL slows whoever rear-ends it", function()
			local _, tick, _, log, me, other = setup({}, { TAIL = "Cactus" })
			local from = #log
			rearEnd(me, other, 500)
			tick(0.1)
			local slowed = false
			for i = from + 1, #log do
				local a = log[i]
				if a.kind == "tune" and a.id == "cactusTail" and a.seat:IsDescendantOf(me) then slowed = true end
			end
			R.expect(slowed).toBe(true)
		end)

		R.it("vs " .. against .. ": Toilet Paper TAIL slows the car right behind", function()
			local srv, tick, C, log, me, other = setup({ TAIL = "Toilet Paper" }, {})
			me:PivotTo(CFrame.new(0, 2, 450))
			other:PivotTo(CFrame.new(0, 2, 458))
			local from = #log
			tick(2)
			local slowed = false
			for i = from + 1, #log do
				local a = log[i]
				if a.kind == "tune" and tostring(a.id):match("^slipstream_") and a.seat:IsDescendantOf(other) then slowed = true end
			end
			R.expect(slowed).toBe(true)
		end)
	end

	R.it("Rubber Duck HEAD: the first hit of the race is ignored (player and race bot)", function()
		local srv, car, tick, C, RaceBots, log = passiveRig(2)
		tick(0.5)
		local RaceEffects = srv.env.requirePath("ServerScriptService.Modules.RaceEffects")
		local me = srv.players[1]
		car(me, { HEAD = "Rubber Duck" }, CFrame.new(0, 2, 560))
		tick(C.RACE_COUNTDOWN + 0.5)
		R.expect(RaceEffects.has(me, "absorb")).toBe(true)
		-- bots: absorb exactly when their HEAD is a Rubber Duck
		for _, bot in ipairs(RaceBots.list) do
			R.expect(RaceEffects.has(bot.proxy, "absorb") == (bot.slots.HEAD == "Rubber Duck")).toBe(true)
		end
	end)

	R.it("Rocket TAIL: a boost lasts a second longer (boostRocket)", function()
		local srv, car, tick, C, _, log = passiveRig(nil)
		tick(0.5)
		local me = srv.players[1]
		car(me, { TAIL = "Rocket" }, CFrame.new(0, 2, 560))
		car(srv.players[2], {}, CFrame.new(10, 2, 560))
		tick(C.RACE_COUNTDOWN + 0.5)
		local from = #log
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, me)).toBe("ok")
		R.expect(landed(log, from, "fx", "boostRocket")).toBe(true)
	end)

	R.it("Soda Bottle TAIL: boosting blinds the player right behind (steamed)", function()
		local srv, car, tick, C, _, log = passiveRig(nil)
		tick(0.5)
		local me = srv.players[1]
		local a = car(me, { TAIL = "Soda Bottle" }, CFrame.new(0, 2, 560))
		local b = car(srv.players[2], {}, CFrame.new(0, 2, 568))
		tick(C.RACE_COUNTDOWN + 0.5)
		a:PivotTo(CFrame.new(0, 2, 450)); b:PivotTo(CFrame.new(0, 2, 458))
		local from = #log
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestBoost, me)).toBe("ok")
		R.expect(landed(log, from, "fx", "steamed")).toBe(true)
	end)

	R.it("Racing Flag HEAD: the leader gets +5 % (leadFlag); Flower HEAD: speed builds without a hit (momentum)", function()
		local srv, car, tick, C, _, log = passiveRig(nil)
		tick(0.5)
		local P1, P2 = srv.players[1], srv.players[2]
		local a = car(P1, { HEAD = "Racing Flag" }, CFrame.new(0, 2, 560))
		local b = car(P2, { HEAD = "Flower" }, CFrame.new(10, 2, 560))
		tick(C.RACE_COUNTDOWN + 0.5)
		a:PivotTo(CFrame.new(0, 2, 300))   -- well ahead
		local from = #log
		tick(C.PASSIVES.MOMENTUM_STEP * 2 + 1)
		local lead, mom = false, false
		for i = from + 1, #log do
			local x = log[i]
			if x.kind == "tune" and x.id == "leadFlag" and x.seat:IsDescendantOf(a) then lead = true end
			if x.kind == "tune" and x.id == "momentum" and x.seat:IsDescendantOf(b) then mom = true end
		end
		R.expect(lead).toBe(true)
		R.expect(mom).toBe(true)
	end)
end)

R.describe("MOBILITY slot", function()
	local Loader = require("../lib/loader")
	local env = Loader.boot()
	local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	local MAIN = { FOREST = "stability", OCEAN = "floatability", SKY = "flyability" }
	for _, biome in ipairs(BIOMES) do
		R.it(biome .. ": every item beats an empty slot on " .. MAIN[biome] .. "; a biome-affinity item beats a plain one of its rarity", function()
			local base = VehicleStats.calculate(nil, nil, nil, biome)
			local empty = VehicleStats.applyMobility(base, nil, biome)[MAIN[biome]]
			local bad = {}
			local plainBest = {}
			for name, cfg in pairs(ItemConfig) do
				if type(cfg) == "table" and cfg.slotType then
					local v = VehicleStats.applyMobility(base, cfg, biome)[MAIN[biome]]
					if not (v > empty) then table.insert(bad, string.format("%s: %.3f vs empty %.3f", name, v, empty)) end
					if not (cfg.mobilityAffinity and cfg.mobilityAffinity[biome]) then
						plainBest[cfg.rarity] = math.max(plainBest[cfg.rarity] or 0, v)
					end
				end
			end
			for name, cfg in pairs(ItemConfig) do
				if type(cfg) == "table" and cfg.slotType and cfg.mobilityAffinity and cfg.mobilityAffinity[biome] then
					local v = VehicleStats.applyMobility(base, cfg, biome)[MAIN[biome]]
					if plainBest[cfg.rarity] and not (v > plainBest[cfg.rarity]) then
						table.insert(bad, name .. ": affinity gives no edge")
					end
				end
			end
			table.sort(bad)
			R.expect(bad).toBeEmpty("MOBILITY items")
		end)
	end
end)
