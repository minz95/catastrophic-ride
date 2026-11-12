-- MysteryBoxes.lua
-- Item boxes on the race track (Constants.MYSTERY_BOX, rows from
-- Shared/BoxPlan: new spots every race). A car (player or race bot) that
-- drives through a box gets a random power with the odds of its place and
-- holds it until it uses it (T, RacingClient → AbilityManager UseRaceTrick;
-- race bots after BOT_USE s). One power at a time: a car holding one drives
-- through boxes without taking them. A taken box comes back after RESPAWN s.
--
-- The boxes are plain parts in workspace.MysteryBoxes (tag "MysteryBox",
-- attribute Taken); StarterPlayerScripts/MysteryBoxFx spins them on every
-- client (a server spin would replicate every frame).
-- Player attribute "BoxPower" = the held power (HUD, touch button).
--
--   MysteryBoxes.start(biome, seed)  -- RacingManager, RACING
--   MysteryBoxes.stop()              -- race over
--   MysteryBoxes.setUser(fn)         -- fn(actor, power) → "ok" | "denied: …" (AbilityManager)
--   MysteryBoxes.onChange(fn)        -- fn(actor) after the held power changed
--   MysteryBoxes.held(actor), use(actor), give(actor, power)

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local BoxPlan        = require(ReplicatedStorage.Shared.BoxPlan)
local RaceProgress   = require(ReplicatedStorage.Shared.RaceProgress)
local SessionManager = require(ServerScriptService.SessionManager)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)
local RaceStart      = require(ServerScriptService.Modules.RaceStart)
local RaceBots       = require(ServerScriptService.Modules.RaceBots)

local B = Constants.MYSTERY_BOX

local MysteryBoxes = {}
MysteryBoxes.FOLDER = "MysteryBoxes"
MysteryBoxes.TAG = "MysteryBox"

local _held = {}       -- [userId] = power
local _boxes = {}      -- { part, x, y, z, backAt }
local _gen = 0
local _user, _changed = nil, {}
local _rng = Random.new()

local TRACK_MODULES = { FOREST = "ForestTrack", OCEAN = "OceanTrack", SKY = "SkyTrack" }

function MysteryBoxes.setUser(fn) _user = fn end
function MysteryBoxes.onChange(fn) table.insert(_changed, fn) end

local function changed(actor)
	if not SessionManager.isBot(actor) then
		pcall(function() actor:SetAttribute("BoxPower", _held[actor.UserId]) end)
	end
	for _, fn in ipairs(_changed) do
		local ok, err = pcall(fn, actor)
		if not ok then warn("[MysteryBoxes] " .. tostring(err)) end
	end
end

function MysteryBoxes.held(actor)
	return actor and _held[actor.UserId]
end

--- Hands `actor` a power (a box, or a spec).
function MysteryBoxes.give(actor, power)
	_held[actor.UserId] = power
	changed(actor)
end

--- Uses the held power through the user (AbilityManager). Kept on a denial.
function MysteryBoxes.use(actor)
	local power = MysteryBoxes.held(actor)
	if not power then return "denied: no power" end
	if not _user then return "denied: no handler" end
	local ok, res = pcall(_user, actor, power)
	if not ok then
		warn("[MysteryBoxes] use: " .. tostring(res))
		res = "denied: error"
	end
	if res == "ok" then
		_held[actor.UserId] = nil
		changed(actor)
	end
	Telemetry.record("box_use", { userId = actor.UserId, power = power, result = res,
		bot = SessionManager.isBot(actor) or nil })
	return res
end

-- ─── Places ──────────────────────────────────────────────────────────────────

local function progressOf(actor)
	if SessionManager.isBot(actor) then
		for _, b in ipairs(RaceBots.list) do
			if b.id == actor.UserId then return b.s or 0, b end
		end
		return nil
	end
	local d = SessionManager.getData(actor)
	return d and d.vehicleModel and (d.raceProgress or 0) or nil
end
MysteryBoxes.progressOf = progressOf

--- Share of the field ahead of `actor` (0 = leader … 1 = last).
function MysteryBoxes.aheadOf(actor)
	local mine = progressOf(actor)
	if not mine then return 0.5 end
	local n, ahead = 0, 0
	for _, other in ipairs(SessionManager.actors()) do
		local s = progressOf(other)
		if s then
			n += 1
			if other ~= actor and s > mine then ahead += 1 end
		end
	end
	return BoxPlan.ahead(ahead + 1, n)
end

-- ─── Boxes ───────────────────────────────────────────────────────────────────

local function makeBox(parent, i, k, pos)
	local p = Instance.new("Part")
	p.Name = string.format("Box_%d_%d", i, k)
	p.Size = Vector3.new(B.SIZE, B.SIZE, B.SIZE)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(20), math.rad(45), 0)
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Glass
	p.Color = Color3.fromHSV(((i * 3 + k) % 7) / 7, 0.7, 1)
	p.Transparency = 0.25
	p:SetAttribute("Taken", false)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left,
		Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local g = Instance.new("SurfaceGui")
		g.Name = "Mark"
		g.Face = face
		g.LightInfluence = 0
		g.CanvasSize = Vector2.new(100, 100)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "?"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0
		t.Parent = g
		g.Parent = p
	end
	local light = Instance.new("PointLight")
	light.Range, light.Brightness = 10, 1.5
	light.Color = p.Color
	light.Parent = p
	p.Parent = parent
	CollectionService:AddTag(p, MysteryBoxes.TAG)
	return p
end

local function setTaken(box, taken)
	local p = box.part
	if not p or not p.Parent then return end
	p:SetAttribute("Taken", taken)
	p.Transparency = taken and 1 or 0.25
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("SurfaceGui") or d:IsA("PointLight") then d.Enabled = not taken end
	end
end

local function carOf(actor)
	local d = SessionManager.getData(actor)
	if not d or d.finishTime then return nil end
	if SessionManager.isBot(actor) then
		local _, bot = progressOf(actor)
		if bot and bot.finished then return nil end
	end
	local v = d.vehicleModel
	return v and v.PrimaryPart
end

local function botUse(actor, gen)
	local wait = _rng:NextNumber(B.BOT_USE[1], B.BOT_USE[2])
	task.delay(wait, function()
		for _ = 1, 6 do
			if gen ~= _gen or not MysteryBoxes.held(actor) then return end
			if MysteryBoxes.use(actor) == "ok" then return end
			task.wait(1)
		end
		-- nothing to hit for a while (a bomb with nobody ahead): let it go
		if gen == _gen and MysteryBoxes.held(actor) then MysteryBoxes.give(actor, nil) end
	end)
end

local function pick(actor, box, gen)
	local power = BoxPlan.power(MysteryBoxes.aheadOf(actor), function() return _rng:NextNumber() end)
	box.backAt = os.clock() + B.RESPAWN
	setTaken(box, true)
	MysteryBoxes.give(actor, power)
	Telemetry.record("box_pick", { userId = actor.UserId, power = power,
		ahead = math.floor(MysteryBoxes.aheadOf(actor) * 100) / 100, bot = SessionManager.isBot(actor) or nil })
	if SessionManager.isBot(actor) then botUse(actor, gen) end
end

local function step(gen)
	local now = os.clock()
	for _, box in ipairs(_boxes) do
		if box.backAt and now >= box.backAt then
			box.backAt = nil
			setTaken(box, false)
		end
	end
	if not RaceStart.isGo() then return end
	for _, actor in ipairs(SessionManager.actors()) do
		if not _held[actor.UserId] then
			local primary = carOf(actor)
			if primary then
				local pos = primary.Position
				for _, box in ipairs(_boxes) do
					if not box.backAt then
						local dx, dz = pos.X - box.x, pos.Z - box.z
						if dx * dx + dz * dz <= B.REACH * B.REACH and math.abs(pos.Y - box.y) <= B.REACH_Y then
							pick(actor, box, gen)
							break
						end
					end
				end
			end
		end
	end
end

--- Lays out this race's boxes and starts the pickup check.
function MysteryBoxes.start(biome, seed)
	MysteryBoxes.stop()
	_gen += 1
	local gen = _gen
	local geo = RaceProgress.geometry(biome)
	local folder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Tracks")
	local mod = folder and TRACK_MODULES[biome] and folder:FindFirstChild(TRACK_MODULES[biome])
	if not geo or not mod then return {} end
	local rng = Random.new(seed or os.time())
	_rng = Random.new((seed or os.time()) + 7)
	local rows = BoxPlan.rows(geo, require(mod), biome, function() return rng:NextNumber() end)
	local parent = Instance.new("Folder")
	parent.Name = MysteryBoxes.FOLDER
	parent.Parent = workspace
	for i, row in ipairs(rows) do
		for k, b in ipairs(row.boxes) do
			local part = makeBox(parent, i, k, Vector3.new(b.x, b.y, b.z))
			table.insert(_boxes, { part = part, x = b.x, y = b.y, z = b.z, s = row.s })
		end
	end
	Telemetry.record("box_rows", { biome = biome, rows = #rows, boxes = #_boxes })
	task.spawn(function()
		while gen == _gen do
			local ok, err = pcall(step, gen)
			if not ok then warn("[MysteryBoxes] " .. tostring(err)) end
			task.wait(B.CHECK)
		end
	end)
	return rows
end

--- Removes the boxes and every held power.
function MysteryBoxes.stop()
	_gen += 1
	_boxes = {}
	local old = workspace:FindFirstChild(MysteryBoxes.FOLDER)
	if old then old:Destroy() end
	local held = _held
	_held = {}
	for uid in pairs(held) do
		local actor = SessionManager.actorById and SessionManager.actorById(uid)
		if actor then changed(actor) end
	end
end

--- This race's boxes (specs).
function MysteryBoxes.boxes() return _boxes end

return MysteryBoxes
