--!nocheck
-- matchsim.luau
-- Offline match simulator: runs the REAL FarmingManager / CraftingManager /
-- GameManager scripts in the mock engine with bots, then races every
-- crafted car on the kinematic simulator.
--
--   local r = MatchSim.run({ players = 6, seed = 1 })
--
-- Modelled: item spawning and pickup rules, contests (button mash), steals and
-- defends, crafting validation and stats, race time per car+driver.
-- Not modelled: walking around obstacles in the farm (bots walk in straight
-- lines), car-to-car contact and abilities during the race.

local Server = require("./server")
local World = require("./world")
local KineSim = require("./kinesim")
local Vector3 = require("@lune/roblox").Vector3

local MatchSim = {}

MatchSim.STEP = 0.1

local function itemList(map)
	local out = {}
	for _, d in ipairs(map:GetDescendants()) do
		if d.Name == "ItemId" and d.ClassName == "StringValue" then
			local part = d.Parent
			local nameVal = part and part:FindFirstChild("ItemName")
			if part and part.Parent and nameVal then
				table.insert(out, { id = d.Value, name = nameVal.Value, x = part.Position.X, z = part.Position.Z, part = part })
			end
		end
	end
	return out
end

local function dist2(ax, az, bx, bz)
	local dx, dz = ax - bx, az - bz
	return dx * dx + dz * dz
end

function MatchSim.run(opts)
	opts = opts or {}
	local n = opts.players or 6
	local seed = opts.seed or 1
	math.randomseed(seed)
	local rng = (function()
		local state = seed * 48271 % 2147483647
		return function()
			state = state * 48271 % 2147483647
			return state / 2147483647
		end
	end)()

	local farmingTime = opts.farming or 90
	-- Build the race world FIRST: Loader.boot resets the shared mock engine,
	-- so the server must be the last thing booted.
	local world = opts.world or World.forest({ visibility = opts.visibility or "intended" })
	local srv = Server.boot({
		players = n,
		quiet = opts.quiet ~= false,
		swallowErrors = true,
		harness = {
			harness = "lune-match", biome = "FOREST", players = n, lobbyDelay = 0,
			durations = { FARMING = farmingTime, CRAFTING = opts.crafting or 5, RESULTS = 1 },
		},
	})
	local env, Mock = srv.env, srv.mock
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local BotBrain = env.requirePath("ReplicatedStorage.Shared.BotBrain")
	local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
	local map = env.workspace.Maps.ForestMap

	local farmProfiles = opts.farmProfiles or { "sweaty", "casual" }
	local driverProfiles = opts.driverProfiles or { "expert", "average", "novice" }
	local bots = {}
	for i, p in ipairs(srv.players) do
		local fp = farmProfiles[((i - 1) % #farmProfiles) + 1]
		local dp = driverProfiles[((i - 1) % #driverProfiles) + 1]
		-- Start on the farm edge, spread around
		local ang = (i / n) * 2 * math.pi
		local root = p.Character.HumanoidRootPart
		root.Position = Vector3.new(math.cos(ang) * 90, 3, 850 + math.sin(ang) * 140)
		bots[i] = {
			player = p, farm = fp, drive = dp, profile = BotBrain.PROFILES[fp],
			target = nil, nextTry = 0, contest = nil, walked = 0,
			stats = { pickups = 0, contestsWon = 0, contestsLost = 0, stealsDone = 0, stealsSuffered = 0, defended = 0, steps = 0 },
		}
	end

	local steal = env.requirePath("ReplicatedStorage.RemoteEvents").StealAttempt
	local craftedAt = nil
	local log = { pickupDenied = {}, contestStuck = 0 }

	local function farmingStep(clock)
		local phase = srv.GameManager.getPhase()
		if phase ~= "FARMING" then return end
		local items = itemList(map)
		local byId = {}
		for _, it in ipairs(items) do byId[it.id] = it end
		for _, b in ipairs(bots) do
			local data = srv.SessionManager.getData(b.player)
			local root = b.player.Character.HumanoidRootPart
			local pos = root.Position
			-- Contest: mash until the item is resolved
			if b.contest then
				if byId[b.contest.id] and clock < b.contest.giveUpAt then
					b.contest.presses += b.profile.mashRate * MatchSim.STEP
					Mock.invoke(srv.RemoteEvents.RequestContest, b.player, b.contest.id, math.floor(b.contest.presses))
					continue
				end
				if byId[b.contest.id] then log.contestStuck += 1 end
				b.contest = nil
				b.target = nil
			end
			-- Steal attempt
			if b.profile.stealChance > 0 and clock < farmingTime - Constants.STEAL_DISABLE_BEFORE then
				for _, other in ipairs(bots) do
					if other ~= b then
						local op = other.player.Character.HumanoidRootPart.Position
						local od = srv.SessionManager.getData(other.player)
						if od and #od.inventory > 0 and dist2(pos.X, pos.Z, op.X, op.Z) <= Constants.STEAL_RANGE ^ 2
							and BotBrain.wantsSteal(b.profile, MatchSim.STEP, rng) then
							local before = #(rawget(steal, "_calls") or {})
							local _, box = Mock.invoke(srv.RemoteEvents.RequestSteal, b.player, other.player.UserId)
							local calls = rawget(steal, "_calls") or {}
							if #calls > (before or 0) then
								if BotBrain.defends(other.profile, rng) then
									Mock.invoke(srv.RemoteEvents.DefendSteal, other.player)
								end
							end
							break
						end
					end
				end
			end
			-- Movement toward the chosen item
			if not b.target or not byId[b.target.id] then
				b.target = BotBrain.pickItem(b.profile, { x = pos.X, z = pos.Z }, items, data.inventory)
			end
			if b.target and b.profile.mashRate > 0 then
				local t = byId[b.target.id]
				local dx, dz = t.x - pos.X, t.z - pos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d > Constants.PICKUP_RANGE * 0.8 then
					local stepLen = math.min(16 * MatchSim.STEP, d)
					root.Position = Vector3.new(pos.X + dx / d * stepLen, pos.Y, pos.Z + dz / d * stepLen)
					b.walked += stepLen
				elseif clock >= b.nextTry then
					b.nextTry = clock + 0.3
					local result = Mock.invoke(srv.RemoteEvents.RequestPickup, b.player, t.id)
					if result == "contested" then
						b.contest = { id = t.id, presses = 0, giveUpAt = clock + Constants.CONTEST_DURATION + 1.5 }
					elseif result ~= "ok" then
						log.pickupDenied[result or "nil"] = (log.pickupDenied[result or "nil"] or 0) + 1
						b.target = nil
					end
				end
			end
		end
	end

	-- Run FARMING (+ lobby) on the virtual clock
	srv.advance(1)
	srv.advance(farmingTime + 0.5, MatchSim.STEP, farmingStep)

	-- CRAFTING: every bot submits through the real SubmitCraft handler
	local crafts = {}
	for _, b in ipairs(bots) do
		local data = srv.SessionManager.getData(b.player)
		local slots = BotBrain.chooseSlots(b.profile, data.inventory, "FOREST")
		crafts[b] = { inventory = table.clone(data.inventory), slots = slots }
		if b.profile.crafter ~= "none" then
			Mock.invoke(srv.RemoteEvents.SubmitCraft, b.player, table.clone(slots))
		end
	end
	srv.advance((opts.crafting or 5) + 0.5)
	-- Let vehicle spawning and other pending server threads finish before
	-- the next boot resets the shared mock engine.
	srv.advance(5)

	-- Telemetry from the real server
	for _, e in ipairs(srv.Telemetry.events()) do
		for _, b in ipairs(bots) do
			local uid = b.player.UserId
			if e.kind == "item_pickup" and e.userId == uid then b.stats.pickups += 1 end
			if e.kind == "contest_result" then
				if e.winner == uid then b.stats.contestsWon += 1 end
				if e.loser == uid then b.stats.contestsLost += 1 end
			end
			if e.kind == "steal" then
				if e.thief == uid then b.stats.stealsDone += 1 end
				if e.victim == uid then b.stats.stealsSuffered += 1 end
			end
		end
	end

	-- RACE: each car on the kinematic simulator
	local results = {}
	for i, b in ipairs(bots) do
		local data = srv.SessionManager.getData(b.player)
		local stats = data.vehicleStats
		local car = KineSim.carFromStats(stats, Constants)
		local race = KineSim.run(world, {
			car = car, profile = Autopilot.PROFILES[b.drive], profileName = b.drive,
			respawn = opts.respawn or "track", seed = seed * 31 + i, slot = i,
		})
		local inv = crafts[b].inventory
		local rarity = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0 }
		local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
		for _, name in ipairs(inv) do
			local cfg = ItemConfig[name]
			if cfg then rarity[cfg.rarity] += 1 end
		end
		table.insert(results, {
			name = b.player.Name, farmProfile = b.farm, driver = b.drive,
			inventory = inv, rarity = rarity, slots = crafts[b].slots,
			maxSpeed = car.maxSpeed, turnSpeed = car.turnSpeed, boostDuration = car.boostDuration,
			farm = b.stats, walked = math.floor(b.walked),
			race = {
				finished = race.finished, time = race.time, respawns = #race.respawns,
				impacts = #race.impacts, progress = math.floor(race.maxProgress),
			},
		})
	end
	table.sort(results, function(a, b)
		local at = a.race.finished and a.race.time or math.huge
		local bt = b.race.finished and b.race.time or math.huge
		if at ~= bt then return at < bt end
		return a.race.progress > b.race.progress
	end)
	for place, r in ipairs(results) do r.place = place end

	return {
		seed = seed, players = n, results = results,
		itemsLeft = #itemList(map), log = log,
		serverErrors = table.clone(Mock.errors or {}),
	}
end

return MatchSim
