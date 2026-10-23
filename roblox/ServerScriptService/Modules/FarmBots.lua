-- FarmBots.lua
-- Server bots on the farm: on a live server with fewer than
-- Constants.BOTS.FILL_TO people (harness: `fillBots`), bots join at FARMING
-- as NPC characters ("🤖 Rusty"), walk to items and pick them up through the
-- same FarmingManager calls a player's client makes (pickup, contest
-- presses, punch, steal defence). They are SessionManager bot proxies, so
-- players can contest, punch and rob them like anyone else. Their bag
-- becomes their race car (RaceBots, CraftingRules.autoSlots); they stay
-- until LOBBY. Tuning: Constants.BOTS.FARM.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SessionManager = require(ServerScriptService.SessionManager)
local GameManager = require(ServerScriptService.GameManager)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local FarmBots = {}

FarmBots.ID_BASE = -100000   -- the same ids RaceBots uses: bot k is ID_BASE - k
FarmBots.list = {}           -- { proxy, model, root, hum, ... }
-- Offline tests have no physics: walk by moving the root (set by specs).
FarmBots.kinematic = false
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

-- A plain R15 avatar (a minimal rig where that cannot be made, e.g. offline).
local function makeCharacter(proxy, at)
	local colour = SHIRTS[((proxy.index - 1) % #SHIRTS) + 1]
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
	model:PivotTo(CFrame.new(at))
	model.Parent = workspace
	if root then pcall(function() root:SetNetworkOwner(nil) end) end
	return model, root, hum
end

-- A spot on the farm ground: next to a random free item.
local function farmSpot(items)
	local spots = {}
	for _, it in pairs(items) do
		if not it.taken and it.part and it.part.Parent then table.insert(spots, it.part.Position) end
	end
	if #spots == 0 then return Vector3.new(0, 6, 350) end
	local p = spots[_rng:NextInteger(1, #spots)]
	return p + Vector3.new(_rng:NextNumber(-4, 4), 3, _rng:NextNumber(-4, 4))
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

-- Nearest free item (not taken, not in a contest).
local function nearestItem(bot, items, contests)
	local best, bestD, bestId
	local pos = bot.root.Position
	for id, it in pairs(items) do
		if not it.taken and not contests[id] and it.part and it.part.Parent and not bot.skip[id] then
			local d = flat(it.part.Position - pos).Magnitude
			if not bestD or d < bestD then best, bestD, bestId = it, d, id end
		end
	end
	return bestId, best, bestD
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

local function think(bot, dt, now)
	local F = Constants.BOTS.FARM
	local data = SessionManager.getData(bot.proxy)
	if not data or not bot.root or not bot.root.Parent then return end
	local items, contests = _api.items()

	-- grabbed: tap to defend now and then
	if data._stealWindow and _rng:NextNumber() < F.DEFEND then
		_api.defend(bot.proxy)
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

	-- a swing at a player in reach, now and then
	if now >= bot.nextPunch then
		bot.nextPunch = now + F.PUNCH_EVERY * _rng:NextNumber(0.6, 1.4)
		local target = _rng:NextNumber() < F.PUNCH_CHANCE and nearestHuman(bot, Constants.FIGHT.RANGE)
		if target then
			face(bot, target.Position)
			local res = _api.punch(bot.proxy)
			Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "punch", result = res })
			return
		end
	end

	if #data.inventory >= Constants.INVENTORY_SIZE then
		-- full bag: stroll around
		if not bot.goal or flat(bot.goal - bot.root.Position).Magnitude < 2 then
			bot.goal = bot.root.Position + Vector3.new(_rng:NextNumber(-F.WANDER, F.WANDER), 0, _rng:NextNumber(-F.WANDER, F.WANDER))
		end
		walkTo(bot, bot.goal, dt)
		return
	end

	local id, item, d = nearestItem(bot, items, contests)
	if not id then return end
	if d <= Constants.PICKUP_RANGE - 2 then
		local res = _api.pickup(bot.proxy, id)
		Telemetry.record("bot_farm", { userId = bot.proxy.UserId, act = "pickup", item = item.itemName, result = res })
		if res == "contested" then
			bot.contest, bot.presses = id, 0
		elseif res ~= "ok" then
			bot.skip[id] = true   -- e.g. full of better items: look elsewhere
		end
	else
		walkTo(bot, item.part.Position, dt)
	end
end

--- FARMING start: bots for the empty places, on the farm, thinking.
-- api = { items = fn() → _items, _contests; pickup, contestPress, punch, defend }
function FarmBots.start(biome, api)
	FarmBots.stop()
	_api = api
	local n = FarmBots.wanted(#Players:GetPlayers(), GameManager.getHarness())
	-- bots from an earlier round that are no longer wanted leave
	for _, b in ipairs(SessionManager.bots()) do
		if (b.index or 0) > n then SessionManager.removeBot(b.UserId) end
	end
	if n == 0 then return {} end
	local items = api.items()
	for k = 1, n do
		local proxy = FarmBots.proxy(k)
		local data = SessionManager.getData(proxy)
		data.inventory = {}
		local model, root, hum = makeCharacter(proxy, farmSpot(items))
		proxy.Character = model
		table.insert(FarmBots.list, {
			proxy = proxy, model = model, root = root, hum = hum, contest = nil, presses = 0,
			nextPunch = os.clock() + Constants.BOTS.FARM.PUNCH_EVERY * _rng:NextNumber(0.5, 1.5),
			skip = {}, goal = nil, wait = _rng:NextNumber(0, Constants.BOTS.FARM.THINK),
		})
		Telemetry.record("farm_bot", { userId = proxy.UserId, name = proxy.Name, biome = biome })
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
