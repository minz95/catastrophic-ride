--!nocheck
-- mock.luau
-- Minimal Roblox engine emulation for running game modules under Lune.
--
-- Math datatypes (Vector3, CFrame, Color3, Enum, ...) come from @lune/roblox,
-- which implements them faithfully. Instances, CollectionService, Random and
-- task are emulated here because Lune's own Instance layer does not derive
-- properties (e.g. Part.Position from Part.CFrame) and has no physics.
--
-- Scope: enough to build maps, assemble configs and run pure logic. There is
-- no physics, no rendering, no networking. Touched/Changed signals exist so
-- scripts can connect to them, but they only fire when a test fires them.

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local M = {}

-- ─── Signals ──────────────────────────────────────────────────────────────────

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn, connected = true }
	table.insert(self._handlers, entry)
	return {
		Connected = true,
		Disconnect = function(conn)
			entry.connected = false
			conn.Connected = false
		end,
	}
end
Signal.connect = Signal.Connect

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, h in ipairs(table.clone(self._handlers)) do
		if h.connected then
			h.fn(...)
		end
	end
end

function Signal:Wait()
	return nil
end

M.Signal = Signal

-- ─── Class hierarchy ──────────────────────────────────────────────────────────

local SUPER = {
	Part = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	MeshPart = "BasePart",
	UnionOperation = "BasePart",
	Seat = "Part",
	VehicleSeat = "BasePart",
	SpawnLocation = "Part",
	BasePart = "PVInstance",
	Model = "PVInstance",
	WorldModel = "Model",
	Workspace = "Model",
	PVInstance = "Instance",
	Folder = "Instance",
	Script = "BaseScript",
	LocalScript = "Script",
	BaseScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	StringValue = "ValueBase",
	NumberValue = "ValueBase",
	IntValue = "ValueBase",
	BoolValue = "ValueBase",
	ObjectValue = "ValueBase",
	ValueBase = "Instance",
	BillboardGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	ScreenGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	TextLabel = "GuiObject",
	Frame = "GuiObject",
	ImageLabel = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",
	WeldConstraint = "Instance",
	Weld = "JointInstance",
	JointInstance = "Instance",
	Attachment = "Instance",
	BodyVelocity = "BodyMover",
	BodyAngularVelocity = "BodyMover",
	BodyGyro = "BodyMover",
	BodyPosition = "BodyMover",
	BodyForce = "BodyMover",
	BodyMover = "Instance",
	ParticleEmitter = "Instance",
	PointLight = "Light",
	SurfaceLight = "Light",
	Light = "Instance",
	Sound = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	BindableEvent = "Instance",
	BindableFunction = "Instance",
	Highlight = "Instance",
	SelectionBox = "Instance",
	Decal = "FaceInstance",
	Texture = "Decal",
	FaceInstance = "Instance",
	UICorner = "Instance",
	UIStroke = "Instance",
}

local function isA(className, target)
	local c = className
	while c do
		if c == target then
			return true
		end
		c = SUPER[c]
	end
	return target == "Instance"
end

local function defaults(className)
	local d = {}
	if isA(className, "BasePart") then
		d.Size = Vector3.new(4, 1, 2)
		d.CFrame = CFrame.new()
		d.Anchored = false
		d.CanCollide = true
		d.CanTouch = true
		d.CanQuery = true
		d.Transparency = 0
		d.Massless = false
		d.CastShadow = true
		d.Color = roblox.Color3.fromRGB(163, 162, 165)
		d.Material = roblox.Enum.Material.Plastic
	end
	if className == "WedgePart" then
		d.Size = Vector3.new(4, 1, 2)
	end
	if className == "VehicleSeat" then
		d.MaxSpeed = 25
		d.Torque = 10
		d.TurnSpeed = 1
		d.Size = Vector3.new(4, 1, 2)
	end
	if isA(className, "LayerCollector") then
		d.Enabled = true
	end
	if className == "StringValue" then
		d.Value = ""
	end
	return d
end

-- ─── Instance ─────────────────────────────────────────────────────────────────

local Instance = {}
local InstanceMeta = {}
local methods = {}

local function rawProps(inst)
	return rawget(inst, "_props")
end

local function makeInstance(className, name)
	local inst = {
		_class = className,
		_props = defaults(className),
		_children = {},
		_attributes = {},
		_tags = {},
		_signals = {},
	}
	inst._props.Name = name or className
	setmetatable(inst, InstanceMeta)
	return inst
end

function Instance.new(className, parent)
	local inst = makeInstance(className)
	if parent then
		inst.Parent = parent
	end
	return inst
end

local SIGNAL_NAMES = {
	Touched = true,
	TouchEnded = true,
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	Event = true,
	OnServerEvent = true,
	OnClientEvent = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	Destroying = true,
	AncestryChanged = true,
	Click = true,
	InputBegan = true,
	InputEnded = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	Died = true,
	Seated = true,
	MoveToFinished = true,
	Triggered = true,
	Completed = true,
	OnClientInvoke_ = true,
	PromptTriggered = true,
	MouseButton1Click = true,
	Activated = true,
	Error = true,
	MessageOut = true,
}

-- Roblox callback members are write-only; reading one throws in the engine.
local CALLBACKS = { OnServerInvoke = true, OnClientInvoke = true, OnInvoke = true }

InstanceMeta.__index = function(inst, key)
	if CALLBACKS[key] then
		error(key .. " is a callback member of " .. rawget(inst, "_class") .. "; you can only set the callback value, get is not available", 2)
	end
	local m = methods[key]
	if m then
		return m
	end
	local props = rawProps(inst)
	if key == "ClassName" then
		return rawget(inst, "_class")
	end
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if key == "Orientation" and props.CFrame then
		local x, y, z = props.CFrame:ToOrientation()
		return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	end
	if key == "AssemblyLinearVelocity" or key == "AssemblyAngularVelocity" then
		return props[key] or Vector3.zero
	end
	if key == "AssemblyMass" and props.Size then
		return props.Size.X * props.Size.Y * props.Size.Z * 0.7
	end
	local v = props[key]
	if v ~= nil then
		return v
	end
	if SIGNAL_NAMES[key] then
		local sigs = rawget(inst, "_signals")
		sigs[key] = sigs[key] or Signal.new()
		return sigs[key]
	end
	-- Child lookup by name, mirroring Roblox's `inst.ChildName` sugar.
	for _, c in ipairs(rawget(inst, "_children")) do
		if rawProps(c).Name == key then
			return c
		end
	end
	return nil
end

local function detach(inst)
	local parent = rawProps(inst).Parent
	if parent then
		local kids = rawget(parent, "_children")
		local idx = table.find(kids, inst)
		if idx then
			table.remove(kids, idx)
		end
	end
end

InstanceMeta.__newindex = function(inst, key, value)
	local props = rawProps(inst)
	if key == "Parent" then
		if props.Parent == value then
			return
		end
		detach(inst)
		props.Parent = value
		if value then
			table.insert(rawget(value, "_children"), inst)
		end
		return
	end
	if key == "Position" then
		local cf = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(value) * cf.Rotation
		return
	end
	if key == "Orientation" then
		local pos = (props.CFrame or CFrame.new()).Position
		props.CFrame = CFrame.new(pos)
			* CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		return
	end
	props[key] = value
end

InstanceMeta.__tostring = function(inst)
	return rawProps(inst).Name
end

InstanceMeta.__type = "Instance"

-- Remote / bindable methods: no-ops that record calls for tests to inspect.
local function recordCall(name)
	return function(self, ...)
		local log = rawget(self, "_calls")
		if not log then
			log = {}
			rawset(self, "_calls", log)
		end
		table.insert(log, { method = name, args = table.pack(...) })
		local cb = rawProps(self)[name == "InvokeServer" and "OnServerInvoke" or "OnInvoke"]
		if name == "InvokeServer" and cb then
			return cb(M.localPlayer, ...)
		end
		return nil
	end
end
for _, name in ipairs({ "FireClient", "FireAllClients", "FireServer", "InvokeServer", "InvokeClient", "Fire", "Invoke" }) do
	methods[name] = recordCall(name)
end

function methods:IsA(className)
	return isA(rawget(self, "_class"), className)
end

function methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function methods:GetDescendants()
	local out = {}
	local function walk(node)
		for _, c in ipairs(rawget(node, "_children")) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(rawget(self, "_children")) do
		if rawProps(c).Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "_children")) do
			local hit = c:FindFirstChild(name, true)
			if hit then
				return hit
			end
		end
	end
	return nil
end

function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end

function methods:FindFirstChildWhichIsA(className, recursive)
	local list = recursive and self:GetDescendants() or rawget(self, "_children")
	for _, c in ipairs(list) do
		if c:IsA(className) then
			return c
		end
	end
	return nil
end

function methods:FindFirstChildOfClass(className)
	for _, c in ipairs(rawget(self, "_children")) do
		if rawget(c, "_class") == className then
			return c
		end
	end
	return nil
end

function methods:FindFirstAncestorWhichIsA(className)
	local p = rawProps(self).Parent
	while p do
		if p:IsA(className) then
			return p
		end
		p = rawProps(p).Parent
	end
	return nil
end

function methods:FindFirstAncestor(name)
	local p = rawProps(self).Parent
	while p do
		if rawProps(p).Name == name then
			return p
		end
		p = rawProps(p).Parent
	end
	return nil
end

function methods:IsDescendantOf(other)
	local p = rawProps(self).Parent
	while p do
		if p == other then
			return true
		end
		p = rawProps(p).Parent
	end
	return false
end

function methods:GetFullName()
	local parts = {}
	local node = self
	while node and rawget(node, "_class") ~= "DataModel" do
		table.insert(parts, 1, rawProps(node).Name)
		node = rawProps(node).Parent
	end
	return table.concat(parts, ".")
end

function methods:Destroy()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	M.CollectionService:_untagAll(self)
	detach(self)
	rawProps(self).Parent = nil
end

function methods:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end

-- Clone remaps Instance-valued properties (PrimaryPart, Part0/Part1,
-- ObjectValue.Value, Adornee, ...) that point inside the cloned subtree to the
-- matching clone, like the engine does.
local function cloneTree(src, map)
	local copy = makeInstance(rawget(src, "_class"))
	map[src] = copy
	for k, v in pairs(rawget(src, "_attributes")) do
		rawget(copy, "_attributes")[k] = v
	end
	for tag in pairs(rawget(src, "_tags")) do
		M.CollectionService:AddTag(copy, tag)
	end
	for _, c in ipairs(rawget(src, "_children")) do
		local cc = cloneTree(c, map)
		rawProps(cc).Parent = copy
		table.insert(rawget(copy, "_children"), cc)
	end
	return copy
end

function methods:Clone()
	local map = {}
	local root = cloneTree(self, map)
	for src, copy in pairs(map) do
		for k, v in pairs(rawProps(src)) do
			if k ~= "Parent" then
				if type(v) == "table" and getmetatable(v) == InstanceMeta and map[v] then
					rawProps(copy)[k] = map[v]
				else
					rawProps(copy)[k] = v
				end
			end
		end
	end
	return root
end

function methods:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end

function methods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end

function methods:GetAttributes()
	return table.clone(rawget(self, "_attributes"))
end

function methods:GetAttributeChangedSignal()
	return Signal.new()
end

function methods:GetPropertyChangedSignal()
	return Signal.new()
end

function methods:AddTag(tag)
	M.CollectionService:AddTag(self, tag)
end

function methods:HasTag(tag)
	return rawget(self, "_tags")[tag] == true
end

function methods:RemoveTag(tag)
	M.CollectionService:RemoveTag(self, tag)
end

function methods:GetTags()
	local out = {}
	for t in pairs(rawget(self, "_tags")) do
		table.insert(out, t)
	end
	table.sort(out)
	return out
end

-- ─── Smoke physics ────────────────────────────────────────────────────────────
-- NOT a physics engine. Just enough for harness code that calls Roblox spatial
-- and stepping APIs to run end to end, so API misuse shows up offline:
--   StepPhysics moves an assembly by its DriveVelocity / DriveAngular targets.
--   Raycast downward hits a flat ground at Y = M.groundY; other rays miss.
--   GetPartsInPart returns Include-listed parts containing the part's centre.

M.groundY = 1

local function inside(part, point)
	local p = rawProps(part)
	local lp = p.CFrame:PointToObjectSpace(point)
	local h = p.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

function methods:StepPhysics(dt, parts)
	local roots = {}
	for _, part in ipairs(parts or {}) do
		local bv = part:FindFirstChild("DriveVelocity")
		if bv then roots[part] = bv end
	end
	for root, bv in pairs(roots) do
		local props = rawProps(root)
		local av = root:FindFirstChild("DriveAngular")
		local v = rawProps(bv).Velocity or Vector3.zero
		local w = av and rawProps(av).AngularVelocity or Vector3.zero
		local delta = CFrame.new(v * dt) * CFrame.new(props.CFrame.Position)
			* CFrame.Angles(0, w.Y * dt, 0) * CFrame.new(-props.CFrame.Position)
		local model = root.Parent
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				rawProps(d).CFrame = delta * rawProps(d).CFrame
			end
		end
		props.AssemblyLinearVelocity = v
		props.AssemblyAngularVelocity = w
	end
end

function methods:Raycast(origin, direction)
	if direction.Y < 0 and origin.Y > M.groundY and origin.Y + direction.Y <= M.groundY then
		return { Position = Vector3.new(origin.X, M.groundY, origin.Z), Instance = self, Normal = Vector3.new(0, 1, 0), Distance = origin.Y - M.groundY }
	end
	return nil
end

function methods:GetPartsInPart(part, params)
	local out = {}
	local centre = rawProps(part).CFrame.Position
	for _, cand in ipairs((params and params.FilterDescendantsInstances) or {}) do
		if cand ~= part and inside(cand, centre) then
			table.insert(out, cand)
		end
	end
	return out
end

-- VehicleSeat / Seat
function methods:Sit(humanoid)
	if humanoid then
		rawProps(humanoid).Sit = true
		rawProps(self).Occupant = humanoid
	end
end

-- Humanoid
function methods:MoveTo(pos)
	rawProps(self).MoveTarget = pos
end

-- PVInstance / Model helpers.
function methods:GetPivot()
	local props = rawProps(self)
	if props.CFrame then
		return props.CFrame
	end
	local pp = props.PrimaryPart
	if pp then
		return rawProps(pp).CFrame
	end
	return CFrame.new()
end

function methods:PivotTo(target)
	if rawProps(self).CFrame then
		rawProps(self).CFrame = target
		return
	end
	local pivot = self:GetPivot()
	local delta = target * pivot:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			rawProps(d).CFrame = delta * rawProps(d).CFrame
		end
	end
end
methods.SetPrimaryPartCFrame = methods.PivotTo

function methods:GetBoundingBox()
	local lo, hi
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, size = rawProps(d).CFrame, rawProps(d).Size
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = cf * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
						lo = lo and Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) or c
						hi = hi and Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) or c
					end
				end
			end
		end
	end
	if not lo then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end

function methods:GetService(name)
	local existing = self:FindFirstChild(name)
	if existing then
		return existing
	end
	local svc = M.services[name]
	if svc then
		return svc
	end
	local s = makeInstance(name)
	s.Parent = self
	return s
end

-- ─── CollectionService ────────────────────────────────────────────────────────

local function newCollectionService()
	local cs = makeInstance("CollectionService")
	local byTag = {}
	rawset(cs, "_byTag", byTag)
	-- Instance methods are looked up through `methods`, so attach service
	-- methods directly on the raw table.
	rawset(cs, "AddTag", function(_, inst, tag)
		if rawget(inst, "_tags")[tag] then
			return
		end
		rawget(inst, "_tags")[tag] = true
		byTag[tag] = byTag[tag] or {}
		table.insert(byTag[tag], inst)
	end)
	rawset(cs, "RemoveTag", function(_, inst, tag)
		rawget(inst, "_tags")[tag] = nil
		local list = byTag[tag]
		if list then
			local idx = table.find(list, inst)
			if idx then
				table.remove(list, idx)
			end
		end
	end)
	rawset(cs, "HasTag", function(_, inst, tag)
		return rawget(inst, "_tags")[tag] == true
	end)
	rawset(cs, "GetTagged", function(_, tag)
		return table.clone(byTag[tag] or {})
	end)
	rawset(cs, "GetTags", function(_, inst)
		return inst:GetTags()
	end)
	rawset(cs, "GetInstanceAddedSignal", function()
		return Signal.new()
	end)
	rawset(cs, "GetInstanceRemovedSignal", function()
		return Signal.new()
	end)
	rawset(cs, "_untagAll", function(self, inst)
		for tag in pairs(rawget(inst, "_tags")) do
			self:RemoveTag(inst, tag)
		end
	end)
	return cs
end

-- ─── Random (deterministic PCG32) ─────────────────────────────────────────────
-- Not bit-identical to Roblox's Random; only determinism matters here.

local Random = {}
Random.__index = Random

function Random.new(seed)
	local self = setmetatable({}, Random)
	self._state = (math.floor(seed or os.time()) * 2654435761 + 1013904223) % 4294967296
	return self
end

function Random:_next()
	-- xorshift32
	local x = self._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	if x == 0 then
		x = 0x9E3779B9
	end
	self._state = x
	return x / 4294967296
end

function Random:NextNumber(lo, hi)
	lo = lo or 0
	hi = hi or 1
	return lo + (hi - lo) * self:_next()
end

function Random:NextInteger(lo, hi)
	return lo + math.floor(self:_next() * (hi - lo + 1))
end

function Random:Clone()
	local c = setmetatable({}, Random)
	c._state = self._state
	return c
end

M.Random = Random

-- ─── task (virtual clock scheduler) ──────────────────────────────────────────
-- Time only moves when a test calls M.advance(seconds). task.wait() yields the
-- calling thread when it was started by task.spawn/defer/delay (a "managed"
-- thread); at top level it returns immediately. tick()/time()/os.clock() seen
-- by game code read the virtual clock.

M.clock = 0
M._timers = {}
M._managed = setmetatable({}, { __mode = "k" })

M.epoch = 0
M._threadEpoch = setmetatable({}, { __mode = "k" })

local function resumeManaged(co, ...)
	local born = M._threadEpoch[co]
	if born == nil then
		M._threadEpoch[co] = M.epoch
	elseif born ~= M.epoch then
		-- A thread from an earlier boot: never resume it into a new world.
		return
	end
	M._managed[co] = true
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		M.errors = M.errors or {}
		table.insert(M.errors, tostring(err))
		if not M.swallowErrors then
			error(debug.traceback(co, tostring(err)), 0)
		end
	end
end

local function schedule(at, job)
	job.at = at
	job.seq = (M._seq or 0) + 1
	M._seq = job.seq
	table.insert(M._timers, job)
	return job
end

M.task = {
	wait = function(d)
		local co = coroutine.running()
		if M._managed[co] then
			local start = M.clock
			schedule(M.clock + (d or 0), { thread = co })
			coroutine.yield()
			return M.clock - start
		end
		return 0
	end,
	spawn = function(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		resumeManaged(co, ...)
		return co
	end,
	defer = function(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		schedule(M.clock, { thread = co, args = table.pack(...) })
		return co
	end,
	delay = function(d, fn, ...)
		local co = coroutine.create(fn)
		local job = schedule(M.clock + (d or 0), { thread = co, args = table.pack(...) })
		return job
	end,
	cancel = function(handle)
		if type(handle) == "table" then
			handle.cancelled = true
		elseif type(handle) == "thread" then
			for _, j in ipairs(M._timers) do
				if j.thread == handle then j.cancelled = true end
			end
		end
	end,
}

--- Runs every timer due within `seconds` of virtual time, in order.
-- `onStep(clock)` (optional) is called each `stepSize` seconds, e.g. to fire
-- RunService.Heartbeat.
function M.advance(seconds, stepSize, onStep)
	local target = M.clock + seconds
	local nextStep = stepSize and (M.clock + stepSize) or math.huge
	while true do
		local idx, best
		for i, j in ipairs(M._timers) do
			if not j.cancelled and j.at <= target and (not best or j.at < best.at or (j.at == best.at and j.seq < best.seq)) then
				idx, best = i, j
			end
		end
		if onStep and nextStep <= target and (not best or nextStep <= best.at) then
			M.clock = nextStep
			onStep(M.clock)
			nextStep += stepSize
			continue
		end
		if not best then break end
		table.remove(M._timers, idx)
		M.clock = math.max(M.clock, best.at)
		if best.args then
			resumeManaged(best.thread, table.unpack(best.args, 1, best.args.n))
		else
			resumeManaged(best.thread)
		end
	end
	-- Drop cancelled timers
	for i = #M._timers, 1, -1 do
		if M._timers[i].cancelled then table.remove(M._timers, i) end
	end
	M.clock = target
end

-- Back-compat helper
function M.flushTasks()
	M.advance(0)
end

-- ─── World ────────────────────────────────────────────────────────────────────

function M.reset()
	M.services = {}
	M.epoch = (M.epoch or 0) + 1
	M.clock = 0
	M._timers = {}
	M.errors = {}
	local game = makeInstance("DataModel", "Game")
	M.CollectionService = newCollectionService()
	M.CollectionService.Parent = game
	M.services.CollectionService = M.CollectionService
	local ws = makeInstance("Workspace", "Workspace")
	ws.Parent = game
	M.services.Workspace = ws
	for _, name in ipairs({
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPlayer",
		"Lighting",
		"Players",
		"RunService",
		"TweenService",
		"Debris",
		"HttpService",
		"UserInputService",
		"SoundService",
	}) do
		local s = makeInstance(name, name)
		s.Parent = game
		M.services[name] = s
	end
	local rs = M.services.RunService
	rawset(rs, "IsStudio", function()
		return false
	end)
	rawset(rs, "IsServer", function()
		return true
	end)
	rawset(rs, "IsClient", function()
		return false
	end)
	local players = M.services.Players
	M.playerList = {}
	rawset(players, "GetPlayers", function()
		return table.clone(M.playerList)
	end)
	rawset(players, "GetPlayerByUserId", function(_, id)
		for _, p in ipairs(M.playerList) do
			if p.UserId == id then return p end
		end
		return nil
	end)
	rawset(players, "GetPlayerFromCharacter", function(_, char)
		for _, p in ipairs(M.playerList) do
			if p.Character == char then return p end
		end
		return nil
	end)
	rawset(M.services.Debris, "AddItem", function(_, inst, life)
		M.task.delay(life or 10, function()
			if inst and inst.Parent then inst:Destroy() end
		end)
	end)
	local http = M.services.HttpService
	local serde = require("@lune/serde")
	rawset(http, "JSONEncode", function(_, v)
		return serde.encode("json", v)
	end)
	rawset(http, "JSONDecode", function(_, s)
		return serde.decode("json", s)
	end)
	M.game = game
	M.workspace = ws
	return game
end

-- ─── Script environment ───────────────────────────────────────────────────────

function M.environment(scriptInstance, requireFn)
	local env = {
		game = M.game,
		workspace = M.workspace,
		Workspace = M.workspace,
		script = scriptInstance,
		require = requireFn,
		Instance = Instance,
		Random = Random,
		task = M.task,
		warn = function(...)
			if M.quiet then
				return
			end
			print("[warn]", ...)
		end,
		print = function(...)
			if M.quiet then
				return
			end
			print(...)
		end,
		tick = function() return M.clock end,
		time = function() return M.clock end,
		os = setmetatable({ clock = function() return M.clock end, time = function() return math.floor(M.clock) end }, { __index = os }),
		wait = function(d) return M.task.wait(d) end,
		delay = M.task.delay,
		spawn = M.task.spawn,
		typeof = function(v)
			if type(v) == "table" and getmetatable(v) == InstanceMeta then
				return "Instance"
			end
			return typeof(v)
		end,
		-- Datatypes
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		PhysicalProperties = roblox.PhysicalProperties,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Font = roblox.Font,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		TweenInfo = { new = function(...)
			return { ... }
		end },
		RaycastParams = { new = function()
			return { FilterDescendantsInstances = {} }
		end },
		OverlapParams = { new = function()
			return { FilterDescendantsInstances = {} }
		end },
	}
	return setmetatable(env, { __index = _G })
end

--- Adds a fake player with a character standing at `position` (Vector3).
-- The character has a HumanoidRootPart and a Humanoid (WalkSpeed 16).
function M.addPlayer(name, userId, position)
	local player = makeInstance("Player", name)
	rawProps(player).UserId = userId
	rawProps(player).DisplayName = name
	local char = makeInstance("Model", name)
	local root = makeInstance("Part", "HumanoidRootPart")
	rawProps(root).Size = Vector3.new(2, 2, 1)
	rawProps(root).CFrame = CFrame.new(position or Vector3.new(0, 3, 0))
	root.Parent = char
	local hum = makeInstance("Humanoid", "Humanoid")
	rawProps(hum).WalkSpeed = 16
	rawProps(hum).JumpHeight = 7.2
	rawProps(hum).Sit = false
	hum.Parent = char
	char.PrimaryPart = root
	char.Parent = M.workspace
	rawProps(player).Character = char
	rawset(player, "LoadCharacter", function() end)
	rawset(player, "Kick", function() end)
	player.Parent = M.services.Players
	table.insert(M.playerList, player)
	M.services.Players.PlayerAdded:Fire(player)
	return player
end

--- Calls a RemoteFunction's server handler as `player` would, inside a
-- managed thread (so handlers may task.wait). Returns the handler's result
-- once the thread finishes, or nil if it is still waiting.
function M.invoke(remote, player, ...)
	local handler = rawProps(remote).OnServerInvoke
	if not handler then
		error("no OnServerInvoke on " .. remote:GetFullName())
	end
	local box = { done = false }
	local args = table.pack(...)
	M.task.spawn(function()
		box.result = handler(player, table.unpack(args, 1, args.n))
		box.done = true
	end)
	return box.result, box
end

M.Instance = Instance
M.isInstance = function(v)
	return type(v) == "table" and getmetatable(v) == InstanceMeta
end
M.props = rawProps

return M
