-- LobbyManager.server.lua
-- Junk Town, the lobby hub (Modules/Maps/LobbyHub, Shared/LobbyLayout):
-- built at boot; every player (re)spawns on it (Player.RespawnLocation),
-- so the LOBBY reload and anyone joining mid-round land there; the old TV
-- shows the next track, the countdown and who is in; the hall of fame
-- stage, the Legend Rides pads and the junk ride show follow what the
-- server has (ReplicatedStorage.HallOfFame / LegendRides / LobbyShowcase);
-- out of the west gate, Auto Street and Junk Motors' new cars
-- (ReplicatedStorage.NewCars, Modules/CarDealer).
-- In the hub place (Shared/Places) start pads stand where the junk rides
-- would (DepartureManager runs them) and the TV points at them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LegendRides = require(ReplicatedStorage.Shared.LegendRides)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
local GameManager = require(ServerScriptService.GameManager)
local LobbyHub = require(ServerScriptService.Modules.Maps.LobbyHub)

local hub = LobbyHub.build(workspace)
local spawnPad = hub:FindFirstChild("LobbySpawn")

-- ── Players land on the plaza ────────────────────────────────────────────────

-- on the plaza or out on Auto Street
local function onPlaza(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and LobbyLayout.inTown(root.Position)
end

--- Puts `player`'s character on the spawn (a little apart from others).
local _spread = 0
local function toPlaza(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	_spread += 1
	-- rings round the spawn, wider as more come (a hub of 100 lands at once)
	local a = _spread * 2.4
	local r = 2 + (_spread % 5) * 1.6
	local pos = LobbyLayout.SPAWN + Vector3.new(math.cos(a) * r, 4, math.sin(a) * r)
	pcall(function()
		character:PivotTo(CFrame.lookAt(pos, Vector3.new(LobbyLayout.ORIGIN.X, pos.Y, LobbyLayout.ORIGIN.Z)))
	end)
end

local function phase()
	return GameManager.getPhase()
end

-- In the lobby (and for anyone who joins while a race or the results run:
-- they watch from here) a new character lands on the plaza.
local HUB_PHASES = { [Constants.PHASES.LOBBY] = true, [Constants.PHASES.RACING] = true, [Constants.PHASES.RESULTS] = true }

local function hook(player)
	pcall(function() player.RespawnLocation = spawnPad end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		if HUB_PHASES[phase()] and not onPlaza(character) then
			-- RespawnLocation does it; a character that loaded elsewhere is moved
			task.defer(toPlaza, player)
		end
	end)
	-- a character already there when the script saw the player
	if player.Character and HUB_PHASES[phase()] and not onPlaza(player.Character) then
		toPlaza(player)
	end
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end

GameManager.onPhaseChanged(function(newPhase)
	if newPhase ~= Constants.PHASES.LOBBY then return end
	_spread = 0
	-- SessionManager reloads every character at LOBBY (they come back on
	-- the spawn); one still elsewhere after that is brought over
	task.delay(1.5, function()
		if phase() ~= Constants.PHASES.LOBBY then return end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character and not onPlaza(p.Character) then toPlaza(p) end
		end
	end)
end)

-- A safety net under the island: anyone who fell off it (or got flung over
-- the fence) while the plaza is where they should be goes back on the
-- spawn before the engine's fall height kills them.
local FALL_BELOW = 25    -- studs under the floor
local NEAR = 400         -- studs from the plaza's centre, sideways (Auto Street reaches ~310)
task.spawn(function()
	while true do
		task.wait(0.5)
		if HUB_PHASES[phase()] then
			for _, p in ipairs(Players:GetPlayers()) do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				local seated = hum and hum.SeatPart ~= nil
				if root and not seated then
					local o = LobbyLayout.ORIGIN
					local side = Vector3.new(root.Position.X - o.X, 0, root.Position.Z - o.Z).Magnitude
					local out = side > LobbyLayout.RADIUS + 4 and not LobbyLayout.onStreet(root.Position)
					if side < NEAR and (root.Position.Y < o.Y - FALL_BELOW or out) then
						toPlaza(p)
					end
				end
			end
		end
	end
end)

-- ── The TV board ─────────────────────────────────────────────────────────────

local TRACK_NAMES = { FOREST = "🌲 FOREST", OCEAN = "🌊 OCEAN", SKY = "☁ SKY" }
local _mode = nil   -- Shared/Places, once GameManager decided
local function updateBoard()
	if _mode == "hub" then
		LobbyHub.setBoard(hub, "🏁 RACE PADS", "step on a pad!", string.format("%d in town", #Players:GetPlayers()))
		return
	end
	local p = phase()
	local players = string.format("%d / %d players", #Players:GetPlayers(), Constants.MAX_PLAYERS)
	if p == Constants.PHASES.LOBBY then
		local ends = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		local left = ends and math.ceil(ends - workspace:GetServerTimeNow()) or nil
		LobbyHub.setBoard(hub, "? ? ?", left and left > 0 and string.format("starts in %d", left) or "starting soon", players)
	else
		local biome = GameManager.getBiome()
		local label = ({ FARMING = "grabbing junk", CRAFTING = "building rides", RACING = "racing now!",
			RESULTS = "results" })[p] or ""
		LobbyHub.setBoard(hub, TRACK_NAMES[biome or ""] or "…", label, players)
	end
end
task.spawn(function()
	while true do
		pcall(updateBoard)
		task.wait(0.5)
	end
end)

-- ── Hall of fame, Legend Rides, the junk ride show ───────────────────────────

local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
local LegendStore = require(ServerScriptService.Modules.LegendStore)

-- the showcase is built once at boot: wait for its folder, then fill
local function watch(folderName, fn)
	task.spawn(function()
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		while not folder do
			task.wait(1)
			folder = ReplicatedStorage:FindFirstChild(folderName)
		end
		pcall(fn, folder)
		folder.ChildAdded:Connect(function() task.defer(pcall, fn, folder) end)
	end)
end

HallOfFame.onChanged(function(model)
	LobbyHub.setWinner(hub, model)
end)
do   -- a winner built before this script started
	local f = ReplicatedStorage:FindFirstChild("HallOfFame")
	local w = f and f:FindFirstChild("Winner")
	if w then LobbyHub.setWinner(hub, w) end
end

local function onUsedPrompt(player, action, id)
	require(ServerScriptService.Modules.CarDealer).prompt(player, action, id, true)
end

local function legends()
	local folder = ReplicatedStorage:FindFirstChild("LegendRides")
	local nowT = os.time()
	local shown = {}
	-- every one on sale goes on the used-car lot; the newest SHOWN on the plaza's pads too
	for _, l in ipairs(LegendRides.active(LegendStore.list(), nowT, LobbyLayout.USED_SLOTS)) do
		table.insert(shown, { id = l.id, title = l.title, ownerName = l.ownerName, biome = l.biome, votes = l.votes,
			sold = l.sold or 0, limit = l.limit, daysLeft = math.max(0, math.ceil((l.endsAt - nowT) / 86400)) })
	end
	LobbyHub.setUsedCars(hub, shown, folder, Constants.LEGEND.COINS, onUsedPrompt)
	local pads = {}
	for i = 1, math.min(#shown, Constants.LEGEND.SHOWN) do pads[i] = shown[i] end
	LobbyHub.setLegends(hub, pads, folder)
end
-- the store says when listings or sold counts change (every POLL s it reads them)
LegendStore.onChanged(function() pcall(legends) end)
pcall(legends)

-- Junk Motors: the cars (built once at boot) on their plinths, the
-- plinths' prompts to the dealer
local CarDealer = require(ServerScriptService.Modules.CarDealer)
for _, d in ipairs(hub:GetDescendants()) do
	if d:IsA("ProximityPrompt") and d:GetAttribute("CarAction") then
		d.Triggered:Connect(function(player)
			CarDealer.prompt(player, d:GetAttribute("CarAction"), d:GetAttribute("Car"))
		end)
	end
end
watch(CarDealer.FOLDER, function(folder)
	LobbyHub.setNewCars(hub, folder)
end)
task.spawn(CarDealer.buildStills)

-- the hub place has start pads where a round server shows the junk rides
task.spawn(function()
	_mode = GameManager.placeMode()
	if _mode == "hub" then
		LobbyHub.departurePads(hub)
	else
		watch("LobbyShowcase", function(folder)
			LobbyHub.setShowcase(hub, folder)
		end)
	end
end)
