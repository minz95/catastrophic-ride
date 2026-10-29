-- FarmBots.lua
-- Server bots on the farm: on a live server with fewer than
-- Constants.BOTS.FILL_TO people (harness: `fillBots`), bots join at FARMING
-- as NPC characters ("🤖 Rusty"), walk to items and pick them up through the
-- same FarmingManager calls a player's client makes (pickup, contest
-- presses, punch, guard, steal and steal defence). They are SessionManager bot proxies, so
-- players can contest, punch and rob them like anyone else. Their bag
-- becomes their race car (RaceBots, CraftingRules.autoSlots); they stay
-- until LOBBY. Tuning: Constants.BOTS.FARM.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local FarmBounds = require(ReplicatedStorage.Shared.FarmBounds)
local SessionManager = require(ServerScriptService.SessionManager)
local GameManager = require(ServerScriptService.GameManager)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local FarmBots = {}

FarmBots.ID_BASE = -100000   -- the same ids RaceBots uses: bot k is ID_BASE - k
FarmBots.list = {}           -- { proxy, model, root, hum, ... }
-- Offline tests have no physics: walk by moving the root (set by specs).
FarmBots.kinematic = false
FarmBots.GROUP = "FarmBot"   -- collision group: bots pass through each other
FarmBots.paused = false      -- specs: bots stand still

local _conn = nil
local _api = nil
local _rng = Random.new()

--- How many bots for `humans` players (harness: args.fillBots).
function FarmBots.wanted(humans, harness)
	local fillTo
	if harness then
		fillTo = harness.fillBots
		if type(fillTo) ~= "number" then return 0 end
	else
		fillTo = Constants.BOTS.FILL_TO
	end
	return math.max(0, math.min(fillTo, Constants.MAX_PLAYERS) - humans)
end

--- The proxy for bot k (registered with SessionManager), made once a round.
function FarmBots.proxy(k)
	local id = FarmBots.ID_BASE - k
	for _, b in ipairs(SessionManager.bots()) do
		if b.UserId == id then return b end
	end
	local B = Constants.BOTS
	local name = B.NAMES[((k - 1) % #B.NAMES) + 1]
	local proxy = {
		UserId = id, Name = name, DisplayName = "🤖 " .. name, isBot = true, Character = nil,
		profile = B.PROFILES[((k - 1) % #B.PROFILES) + 1], index = k,
	}
	SessionManager.addBot(proxy)
	return proxy
end

local SHIRTS = {
	Color3.fromRGB(230, 90, 60), Color3.fromRGB(60, 140, 230), Color3.fromRGB(250, 200, 60), Color3.fromRGB(120, 200, 90),
	Color3.fromRGB(190, 100, 220), Color3.fromRGB(240, 140, 190), Color3.fromRGB(80, 200, 200), Color3.fromRGB(160, 120, 80),
}

--- The shirt colour of bot `index` (its farm avatar and its race driver).
function FarmBots.shirt(index)
	return SHIRTS[(((index or 1) - 1) % #SHIRTS) + 1]
end

-- A plain R15 avatar (a minimal rig where that cannot be made, e.g. offline).
local function makeCharacter(proxy, at)
	local colour = FarmBots.shirt(proxy.index)
	local model
	local ok = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = Color3.fromRGB(255, 220, 180)
		desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
		desc.TorsoColor = colour
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(60, 60, 80), Color3.fromRGB(60, 60, 80)
		model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Color = colour
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
		head.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, head
		w.Parent = root
		local hum = Instance.new("Humanoid")
		hum.HipHeight = 2
		hum.Parent = model
		model.PrimaryPart = root
	end
	model.Name = proxy.DisplayName
	model:SetAttribute("BotUserId", proxy.UserId)
	model:SetAttribute("BotName", proxy.Name)
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
	CollectionService:AddTag(model, "FarmBot")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Constants.BOTS.FARM.WALK
		hum.DisplayName = proxy.DisplayName
		pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	-- Bots do not collide with each other (they still meet players and the
	-- world). Studio 2026-10-29 (bots-ocean, record-sky): two bots that
	-- robbed each other walked into each other, one stood on the other and
	-- physics threw both ~30 studs up ("bots shoot into the sky").
	local grouped = pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		if not PhysicsService:IsCollisionGroupRegistered(FarmBots.GROUP) then
			PhysicsService:RegisterCollisionGroup(FarmBots.GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(FarmBots.GROUP, FarmBots.GROUP, false)
	end)
	if grouped then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then p.CollisionGroup = FarmBots.GROUP end
		end
	end
	-- no climbing: two bots face to face (a mutual steal) climbed each
	-- other like a ladder and rose together (playtest 2026-10-30: "both
	-- float up", after they no longer collided); the climb check does not
	-- care about collision groups
	if hum then pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false) end) end
	model:SetAttribute("NoCollideGroup", grouped)
	model:PivotTo(CFrame.new(at))
	model.Parent = workspace
	if root then pcall(function() root:SetNetworkOwner(nil) end) end
	return model, root, hum
end

-- Where a bot appears: on the farm floor (FarmBounds) next to a random free
-- item, at least BOT_GAP from anyone already there.
-- History (playtest 2026-10-29: "bots suddenly shoot up into the sky"):
-- this took the item's own height + 3 (items float and bob over the floor)
-- and let several bots appear on the same item, inside each other or a
-- player; with no free item it used (0, 6, 350), a spot off every farm
-- (they are at Z 850 / 1850). Overlapping characters are pushed apart by
-- the physics, upwards too. FarmRescue now also puts back anyone flung.
local function farmSpot(biome, items, taken)
	local b = FarmBounds.get(biome)
	local y = b.floorY + FarmBounds.SPAWN_LIFT
	local spots = {}
	for _, it in pairs(items) do
		if not it.taken and it.part and it.part.Parent then table.insert(spots, it.part.Position) end
	end
	if #spots == 0 then table.insert(spots, Vector3.new(b.cx, b.floorY, b.cz)) end
	local function clear(at)
		for _, o in ipairs(taken) do
			if Vector3.new(o.X - at.X, 0, o.Z - at.Z).Magnitude < FarmBounds.BOT_GAP then return false end
		end
		return true
	end
	for _ = 1, 40 do
		local p = spots[_rng:NextInteger(1, #spots)]
		local x, z = FarmBounds.clamp(biome, p.X + _rng:NextNumber(-4, 4), p.Z + _rng:NextNumber(-4, 4))
		local at = Vector3.new(x, y, z)
		if clear(at) and FarmBounds.itemSpotOk(biome, x, z) then return at end
	end
	local p = FarmBounds.randomItemSpot(biome, function() return _rng:NextNumber() end)
	return Vector3.new(p.X, y, p.Z)
end

-- Spots taken: everyone standing around, and the spawn markers (players are
-- put on those just after the bots appear: CharacterManager).
local function occupied(biome)
	local out = FarmBounds.spawnPoints(biome)
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then table.insert(out, r.Position) end
	end
	return out
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function walkTo(bot, target, dt)
	bot.goal = target
	if FarmBots.kinematic then
		local root = bot.root
		local to = flat(target - root.Position)
		local step = Constants.BOTS.FARM.WALK * dt
		if to.Magnitude > 1e-3 then
			local move = to.Magnitude <= step and to or to.Unit * step
			root.CFrame = CFrame.lookAt(root.Position + move, root.Position + move + to.Unit)
		end
	elseif bot.hum then
		bot.hum:MoveTo(target)
	end
end

local function face(bot, pos)
	local root = bot.root
	local to = flat(pos - root.Position)
	if to.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
	end
end

local RARITY_VALUE = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8 }

-- The free item (not taken, not in a contest, not given up on) worth the
-- walk: rarer ones are worth GREED studs more per rarity point, and one
-- another bot is already heading for and nearer to is left to it (bots
-- used to file after the same nearest item and fight over it).
local function nearestItem(bot, items, contests, now)
	local best, bestD, bestId, bestScore
	local pos = bot.root.Position
	local greed = Constants.BOTS.FARM.GREED
	for id, it in pairs(items) do
		if not it.taken and not contests[id] and it.part and it.part.Parent and now >= (bot.skip[id] or 0) then
			local d = flat(it.part.Position - pos).Magnitude
			local claimed = false
			for _, other in ipairs(FarmBots.list) do
				if other ~= bot and other.targetId == id and other.root
					and flat(it.part.Position - other.root.Position).Magnitude < d then
					claimed = true
				end
			end
			local score = (RARITY_VALUE[it.rarity] or 1) * greed - d - (claimed and 1000 or 0)
			if not bestScore or score > bestScore then best, bestD, bestId, bestScore = it, d, id, score end
		end
	end
	return bestId, best, bestD
end

-- The root part (and the proxy) of player or bot `id`.
local function rootOf(id)
	local a = id and SessionManager.actorById(id)
	return a and a.Character and a.Character:FindFirstChild("HumanoidRootPart"), a
end

-- Face `r` and throw a punch at it (the server checks reach and facing).
local function swingAt(bot, r, targetId, why)
	face(bot, r.Position)
	-- one swing per punch cooldown (it thinks 4 times a second)
	local t = os.clock()
	if t < (bot.nextSwing or 0) then return "wait" end
	bot.nextSwing = t + Constants.FIGHT.COOLDOWN + 0.1
	local res = _api.punch(bot.proxy, targetId)
	Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "punch", why = why, result = res })
	return res
end

local function nearestHuman(bot, range)
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local d = flat(r.Position - bot.root.Position).Magnitude
			if d <= range and (not bestD or d < bestD) then best, bestD = r, d end
		end
	end
	return best
end

-- Someone (not the bot) with items to rob within `range`, nearest first.
local function stealTarget(bot, range)
	local best, bestD
	local now = tick()
	for _, other in ipairs(SessionManager.actors()) do
		local od = other ~= bot.proxy and SessionManager.getData(other)
		local r = od and #od.inventory > 0 and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r and now >= (od.stealInvincibleEnd or 0) and now >= (od._hiddenUntil or 0) and not od._stealWindow then
			local d = flat(r.Position - bot.root.Position).Magnitude
			if d <= range and (not bestD or d < bestD) then best, bestD = other, d end
		end
	end
	return best, bestD
end

-- A player in reach who faces the bot (about to swing).
local function threatened(bot)
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local to = flat(bot.root.Position - r.Position)
			if to.Magnitude <= Constants.FIGHT.RANGE + 1 and to.Magnitude > 1e-3
				and flat(r.CFrame.LookVector).Unit:Dot(to.Unit) >= Constants.FIGHT.ARC then
				return r
			end
		end
	end
	return nil
end

local function guard(bot, on, now)
	bot.guardUntil = on and now + Constants.BOTS.FARM.GUARD_HOLD or nil
	_api.guard(bot.proxy, on)
	if on then Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "guard" }) end
end

local function think(bot, dt, now)
	local F = Constants.BOTS.FARM
	local data = SessionManager.getData(bot.proxy)
	if not data or not bot.root or not bot.root.Parent then return end
	local items, contests = _api.items()

	-- off the floor: log what it was doing (FarmRescue puts it back once flung)
	local over = bot.root.Position.Y - FarmBounds.get(bot.biome).floorY
	if over > F.HIGH_LOG and now >= (bot.highLogAt or 0) then
		bot.highLogAt = now + 1
		local nearest
		for _, other in ipairs(FarmBots.list) do
			if other ~= bot and other.root then
				local d = flat(other.root.Position - bot.root.Position).Magnitude
				if not nearest or d < nearest then nearest = d end
			end
		end
		Telemetry.record("farm_bot_high", {
			userId = bot.proxy.UserId, over = math.floor(over * 10) / 10,
			state = bot.hum and tostring(bot.hum:GetState()) or nil,
			vy = math.floor(bot.root.AssemblyLinearVelocity.Y), nearestBot = nearest and math.floor(nearest * 10) / 10,
			stealing = data._stealing ~= nil, grabbed = data._stealWindow ~= nil, chasing = bot.chase ~= nil,
		})
	end

	-- grabbed: punch the thief off (FIGHT.BREAKS_GRAB) or tap to defend
	if data._stealWindow then
		local r = rootOf(data._stealWindow.thief)
		if r and _api.punch and flat(r.Position - bot.root.Position).Magnitude <= Constants.FIGHT.RANGE
			and _rng:NextNumber() < F.BREAK_GRAB then
			swingAt(bot, r, data._stealWindow.thief, "grab")
			return
		elseif _rng:NextNumber() < F.DEFEND then
			_api.defend(bot.proxy)
		end
	end

	-- a contest someone started with us
	if not bot.contest then
		for id, c in pairs(contests) do
			if c.players[1] == bot.proxy or c.players[2] == bot.proxy then bot.contest, bot.presses = id, 0 end
		end
	end
	-- in a contest: mash at MASH presses a second
	if bot.contest then
		if contests[bot.contest] then
			bot.presses += F.MASH * dt
			_api.contestPress(bot.proxy, bot.contest, math.floor(bot.presses))
			return
		end
		bot.contest = nil
	end

	-- guarding: hold still until the guard is down
	if bot.guardUntil then
		if now < bot.guardUntil and (data._guardUntil or 0) > tick() then return end
		if (data._guardUntil or 0) > tick() then guard(bot, false, now) end
		bot.guardUntil = nil
		bot.nextGuard = now + F.GUARD_REST
	end
	local lastHit = bot.seenHit
	bot.seenHit = data._lastHitAt
	local hitNow = data._lastHitAt ~= nil and data._lastHitAt ~= lastHit   -- a new hit since the last think
	-- hit by a player, or robbed by anyone: go after them for a while. A
	-- bot hit by a bot only swings back in reach (Studio 2026-10-30: bots
	-- chasing each other for revenge threw 211 punches in a minute and
	-- picked up 9 items)
	if hitNow and data._lastHitBy and not SessionManager.isBot(SessionManager.actorById(data._lastHitBy)) then
		bot.revenge = { id = data._lastHitBy, untilT = now + F.REVENGE_FOR }
	end
	if data._robbedAt and data._robbedAt ~= bot.seenRobbed then
		bot.seenRobbed = data._robbedAt
		bot.revenge = { id = data._robbedBy, untilT = now + F.REVENGE_FOR }
		bot.chase = nil
	end
	-- just hit, or a player squares up: raise the guard now and then
	if now >= (bot.nextGuard or 0) and _api.guard then
		local chance = hitNow and F.GUARD_HIT or (threatened(bot) and F.GUARD_NEAR) or 0
		if chance > 0 and _rng:NextNumber() < chance * (hitNow and 1 or dt) then
			local r = threatened(bot)
			if r then face(bot, r.Position) end
			guard(bot, true, now)
			return
		end
	end

	-- just hit by someone in reach: swing back at once, when it did not guard
	if hitNow and _api.punch and _rng:NextNumber() < F.HIT_BACK then
		local r = rootOf(data._lastHitBy)
		if r and flat(r.Position - bot.root.Position).Magnitude <= Constants.FIGHT.RANGE then
			swingAt(bot, r, data._lastHitBy, "hit back")
			return
		end
	end

	-- revenge: walk up to whoever hit or robbed it and punch (a knock-out
	-- drops one of their items: maybe the stolen one)
	if bot.revenge then
		local rv = bot.revenge
		local r = rootOf(rv.id)
		if not r or now > rv.untilT or not _api.punch then
			bot.revenge = nil
		elseif flat(r.Position - bot.root.Position).Magnitude <= Constants.FIGHT.RANGE - 0.5 then
			swingAt(bot, r, rv.id, "revenge")
			return
		else
			walkTo(bot, r.Position, dt)
			return
		end
	end

	-- a chase: walk up to the victim and grab
	if bot.chase then
		local c = bot.chase
		local r = c.victim.Character and c.victim.Character:FindFirstChild("HumanoidRootPart")
		local vd = SessionManager.getData(c.victim)
		if not r or not vd or #vd.inventory == 0 or now > c.untilT or #data.inventory >= Constants.INVENTORY_SIZE then
			bot.chase = nil
		elseif flat(r.Position - bot.root.Position).Magnitude <= Constants.STEAL_RANGE - 0.5 then
			bot.chase = nil
			face(bot, r.Position)
			local victimId = c.victim.UserId
			task.spawn(function()
				local res = _api.steal(bot.proxy, victimId)
				Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "steal", victim = victimId, result = res })
			end)
			return
		else
			walkTo(bot, r.Position, dt)
			return
		end
	end
	if _api.steal and now >= bot.nextSteal and not data._stealing and #data.inventory < Constants.INVENTORY_SIZE then
		bot.nextSteal = now + F.STEAL_EVERY * _rng:NextNumber(0.6, 1.4)
		local victim = _rng:NextNumber() < F.STEAL_CHANCE and stealTarget(bot, F.STEAL_CHASE)
		if victim then
			bot.chase = { victim = victim, untilT = now + F.CHASE_FOR }
			return
		end
	end

	-- a swing at a player in reach, now and then
	if now >= bot.nextPunch then
		bot.nextPunch = now + F.PUNCH_EVERY * _rng:NextNumber(0.6, 1.4)
		local target = _rng:NextNumber() < F.PUNCH_CHANCE and nearestHuman(bot, Constants.FIGHT.RANGE)
		if target then
			swingAt(bot, target, nil, "random")
			return
		end
	end

	if #data.inventory >= Constants.INVENTORY_SIZE - F.KEEP_FREE then
		-- bag full (one slot kept for a steal): prowl near someone with
		-- items, or stroll around
		if not bot.goal or flat(bot.goal - bot.root.Position).Magnitude < 2 then
			local victim = _rng:NextNumber() < F.PROWL and stealTarget(bot, F.PROWL_RANGE)
			local r = victim and victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			local around = r and r.Position or bot.root.Position
			local spread = r and 6 or F.WANDER
			local g = around + Vector3.new(_rng:NextNumber(-spread, spread), 0, _rng:NextNumber(-spread, spread))
			local gx, gz = FarmBounds.clamp(bot.biome, g.X, g.Z)   -- not into a wall
			bot.goal = Vector3.new(gx, g.Y, gz)
		end
		walkTo(bot, bot.goal, dt)
		return
	end

	local id, item, d = nearestItem(bot, items, contests, now)
	if not id then bot.targetId = nil return end
	if id ~= bot.targetId then
		bot.targetId, bot.closest, bot.closerAt = id, d, now
	elseif d < bot.closest - 1 then
		bot.closest, bot.closerAt = d, now
	end
	if d <= Constants.PICKUP_RANGE - 2 then
		local res = _api.pickup(bot.proxy, id)
		Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "pickup", item = item.itemName, result = res })
		if res == "contested" then
			bot.contest, bot.presses = id, 0
		elseif res ~= "ok" then
			bot.skip[id] = math.huge   -- e.g. full of better items: look elsewhere
		end
		bot.targetId = nil
	elseif now - bot.closerAt > F.GIVE_UP then
		-- not getting any closer (a crate, a wall, someone in the way): another item
		bot.skip[id] = now + F.SKIP_FOR
		bot.targetId = nil
		Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "give_up", item = item.itemName })
	else
		if now - bot.closerAt > F.STUCK_AFTER and bot.hum then bot.hum.Jump = true end
		walkTo(bot, item.part.Position, dt)
	end
end

--- FARMING start: bots for the empty places, on the farm, thinking.
-- api = { items = fn() → _items, _contests; pickup, contestPress, punch, defend,
--         steal(thief, victimUserId), guard(player, on) }
function FarmBots.start(biome, api)
	FarmBots.stop()
	_api = api
	local n = FarmBots.wanted(#Players:GetPlayers(), GameManager.getHarness())
	-- bots from an earlier round that are no longer wanted leave
	for _, b in ipairs(SessionManager.bots()) do
		if (b.index or 0) > n then SessionManager.removeBot(b.UserId) end
	end
	if n == 0 then return {} end
	-- harness: { farmBots = { STEAL_EVERY = 2, ... } } overrides BOTS.FARM
	local h = GameManager.getHarness()
	if h and type(h.farmBots) == "table" then
		for key, v in pairs(h.farmBots) do Constants.BOTS.FARM[key] = v end
	end
	local items = api.items()
	local taken = occupied(biome)
	for k = 1, n do
		local proxy = FarmBots.proxy(k)
		local data = SessionManager.getData(proxy)
		data.inventory = {}
		local at = farmSpot(biome, items, taken)
		table.insert(taken, at)
		local model, root, hum = makeCharacter(proxy, at)
		proxy.Character = model
		table.insert(FarmBots.list, {
			proxy = proxy, model = model, root = root, hum = hum, contest = nil, presses = 0, biome = biome,
			nextPunch = os.clock() + Constants.BOTS.FARM.PUNCH_EVERY * _rng:NextNumber(0.5, 1.5),
			skip = {}, goal = nil, wait = _rng:NextNumber(0, Constants.BOTS.FARM.THINK),
			nextSteal = os.clock() + Constants.BOTS.FARM.STEAL_EVERY * _rng:NextNumber(0.5, 1.5),
			nextGuard = 0, guardUntil = nil, chase = nil,
		})
		Telemetry.record("farm_bot", { userId = proxy.UserId, name = proxy.Name, biome = biome,
			noCollideGroup = model:GetAttribute("NoCollideGroup"),
			climb = hum and pcall(function() return hum:GetStateEnabled(Enum.HumanoidStateType.Climbing) end)
				and hum:GetStateEnabled(Enum.HumanoidStateType.Climbing) or false })
	end
	local acc = 0
	_conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		local think_dt = Constants.BOTS.FARM.THINK
		if acc < think_dt then return end
		local step = acc
		acc = 0
		local now = os.clock()
		if FarmBots.paused then return end
		for _, bot in ipairs(FarmBots.list) do
			local ok, err = pcall(think, bot, step, now)
			if not ok then warn("[FarmBots] " .. tostring(err)) end
		end
	end)
	return FarmBots.list
end

--- FARMING over: the bots leave the farm (their data, the bag, stays).
function FarmBots.stop()
	if _conn then _conn:Disconnect(); _conn = nil end
	for _, bot in ipairs(FarmBots.list) do
		if bot.model and bot.model.Parent then bot.model:Destroy() end
		if bot.proxy then bot.proxy.Character = nil end
	end
	FarmBots.list = {}
end

--- LOBBY: bots are gone until the next FARMING.
function FarmBots.clear()
	FarmBots.stop()
	for _, b in ipairs(SessionManager.bots()) do SessionManager.removeBot(b.UserId) end
end

return FarmBots
