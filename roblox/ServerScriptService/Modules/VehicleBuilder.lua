-- VehicleBuilder.lua
-- Assembles a vehicle Model from stats + biome + slot assignments: a car
-- (FOREST), a boat (OCEAN) or a plane (SKY). The look is data in
-- Modules/VehicleDesign; this module turns it into parts, fits the crafted
-- items into their slot boxes and adds the drive movers.
--
-- Only the chassis (PrimaryPart) has mass and collision, and its size comes
-- from the stats exactly as before the 2026-10-20 redesign, so the look
-- never changes how a vehicle drives. Everything else is massless decoration.
-- Resolves: Issue #27

local ServerStorage = game:GetService("ServerStorage")

local Constants       = require(game.ReplicatedStorage.Shared.Constants)
local ItemConfig      = require(game.ServerScriptService.Modules.ItemConfig)
local VehicleDesign   = require(game.ServerScriptService.Modules.VehicleDesign)
local AbilitySlots    = require(game.ReplicatedStorage.Shared.AbilitySlots)

local VehicleBuilder = {}

local RARITY_COLOURS = {
	Common   = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(80,  200, 80),
	Rare     = Color3.fromRGB(80,  140, 255),
	Epic     = Color3.fromRGB(200, 80,  255),
}

-- Biomes with a vehicle layout. Seat values come from Constants.maxSpeedFor /
-- torqueFor / turnSpeedFor (the simulators use the same functions).
VehicleBuilder.SEAT = { FOREST = true, OCEAN = true, SKY = true }

-- How far a ridden item's seat may go below the (invisible) chassis top to
-- sit on the item's real surface (a treadmill's belt).
VehicleBuilder.SEAT_INTO_CHASSIS = 0.4

VehicleBuilder.SLOTS = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }

-- ─── Parts ────────────────────────────────────────────────────────────────────

local SHAPES = {
	block    = function() return Instance.new("Part") end,
	wedge    = function() return Instance.new("WedgePart") end,
	cylinder = function() local p = Instance.new("Part"); p.Shape = Enum.PartType.Cylinder; return p end,
	ball     = function() local p = Instance.new("Part"); p.Shape = Enum.PartType.Ball; return p end,
}

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0  = part0
	w.Part1  = part1
	w.Parent = part1
end

local function decoration(p)
	p.Anchored   = false
	p.CanCollide = false
	p.CanQuery   = false
	p.CanTouch   = false
	p.Massless   = true
end

-- ─── Items ────────────────────────────────────────────────────────────────────

--- World-space bounding box of a model's parts: centre and size.
local function bounds(model)
	local lo, hi
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local cf, half = p.CFrame, p.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local v = cf * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						lo = lo and Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
						hi = hi and Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
					end
				end
			end
		end
	end
	if not lo then return Vector3.zero, Vector3.zero end
	return (lo + hi) * 0.5, hi - lo
end
VehicleBuilder.bounds = bounds

--- Places a copy of the item's model in a mount (`mount.box`, studs in the
-- vehicle's axes, centred on `mountCF`), keeping its proportions; falls back
-- to a rarity-coloured block when the item has no model. Mount options:
--   align = "bottom"  sit on the box floor instead of its centre
--   stretch = k       an axis may grow up to k× past the proportional fit
--   orient = true     turn the item so its longer side runs along the vehicle
--   yaw = degrees     turn it this way instead (VehicleDesign.RIDE_LOOK)
--   tip = true        lay it on its side first (its height runs along the vehicle)
--   side = ±1         push it flush with the box's outer X side
--   front = true      push it against the box's front (-Z) side
--   flat = "X" | "Z"  turn it so its thinnest side runs along that axis (a
--                     wheel seen from the side, a propeller face-on)
-- `minTop` (mount space): raise the item until its top reaches it.
-- Returns the holder Model and the item's top and bottom in mount space.
local hatBaseCF, makeHat

-- Box of the `slot` item's parts in `cf`'s space (lo, hi corners).
local function boundsIn(model, cf, slot)
	local lo, hi
	for _, h in ipairs(model:GetChildren()) do
		if h:IsA("Model") and h:GetAttribute("Slot") == slot then
			for _, p in ipairs(h:GetDescendants()) do
				if p:IsA("BasePart") then
					local e = p.Size * 0.5
					for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
						local v = cf:PointToObjectSpace(p.CFrame * Vector3.new(sx * e.X, sy * e.Y, sz * e.Z))
						lo = lo and Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
						hi = hi and Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
					end end end
				end
			end
		end
	end
	return lo, hi
end
VehicleBuilder.boundsIn = boundsIn

local function placeItem(itemName, mountCF, mount, model, chassis, slot, minTop, weldTo)
	local cfg = ItemConfig[itemName]
	if not cfg then return nil end
	local box = mount.box
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local tmpl = templates and templates:FindFirstChild(itemName)
	local holder = Instance.new("Model")
	holder.Name = "Item_" .. slot .. "_" .. itemName
	holder:SetAttribute("Slot", slot)
	holder:SetAttribute("Item", itemName)
	local placed = {}   -- { part, cf in mount space }
	if tmpl then
		local clone = tmpl:Clone()
		local centre, size = bounds(clone)
		local function fitOf(sz)
			local b = math.huge
			for _, axis in ipairs({ "X", "Y", "Z" }) do
				if sz[axis] > 1e-3 then b = math.min(b, box[axis] / sz[axis]) end
			end
			return b == math.huge and 1 or b
		end
		-- orient: the way round that comes out biggest (upright unless lying
		-- down or turning gains a quarter): a kite becomes a flying carpet
		local turn = CFrame.new()
		if mount.tip then
			turn = CFrame.Angles(math.pi / 2, 0, 0)
			size = Vector3.new(size.X, size.Z, size.Y)
		end
		if mount.yaw then
			turn = CFrame.Angles(0, math.rad(mount.yaw), 0) * turn
			if math.abs(math.sin(math.rad(mount.yaw))) > 0.7 then size = Vector3.new(size.Z, size.Y, size.X) end
		end
		if mount.flat then
			-- candidate turns and which original axis each brings onto `flat`
			local turns = mount.flat == "X"
				and { { CFrame.new(), size.X, size }, { CFrame.Angles(0, math.pi / 2, 0), size.Z, Vector3.new(size.Z, size.Y, size.X) },
					{ CFrame.Angles(0, 0, math.pi / 2), size.Y, Vector3.new(size.Y, size.X, size.Z) } }
				or { { CFrame.new(), size.Z, size }, { CFrame.Angles(0, math.pi / 2, 0), size.X, Vector3.new(size.Z, size.Y, size.X) },
					{ CFrame.Angles(math.pi / 2, 0, 0), size.Y, Vector3.new(size.X, size.Z, size.Y) } }
			local best = turns[1]
			for _, t in ipairs(turns) do
				if t[2] < best[2] - 1e-3 then best = t end
			end
			turn, size = best[1] * turn, best[3]
		end
		local base = fitOf(size)
		if mount.orient then
			local options = {
				{ CFrame.Angles(0, math.pi / 2, 0), Vector3.new(size.Z, size.Y, size.X), 1.0 },
				{ CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(size.X, size.Z, size.Y), 1.25 },
				{ CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(size.Y, size.Z, size.X), 1.25 },
			}
			local best = base
			for i, o in ipairs(options) do
				local b = fitOf(o[2])
				-- a quarter turn wins when it fits at least as well and lays
				-- the long side along the vehicle
				local better = i == 1 and (b > best * 1.001 or (b >= best * 0.999 and o[2].Z > size.Z))
					or (i > 1 and b > best * o[3])
				if better then best, turn, size = b, o[1], o[2] end
			end
			base = best
		end
		local f = {}
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local fit = size[axis] > 1e-3 and box[axis] / size[axis] or base
			f[axis] = mount.stretch and math.min(fit, base * mount.stretch) or base
		end
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then
				local rel = turn * CFrame.new(centre):ToObjectSpace(p.CFrame)
				local rot = rel - rel.Position
				local function len(v) return Vector3.new(v.X * f.X, v.Y * f.Y, v.Z * f.Z).Magnitude end
				p.Size = Vector3.new(p.Size.X * len(rot.RightVector), p.Size.Y * len(rot.UpVector), p.Size.Z * len(rot.LookVector))
				local pos = rel.Position
				table.insert(placed, { part = p, cf = CFrame.new(pos.X * f.X, pos.Y * f.Y, pos.Z * f.Z) * rot })
			elseif p:IsA("WeldConstraint") or p:IsA("Weld") or p:IsA("Motor6D") then
				p:Destroy()
			end
		end
		for _, it in ipairs(placed) do it.part.Parent = holder end
		clone:Destroy()
	else
		local p = Instance.new("Part")
		p.Name = "ItemBlock"
		p.Size = box * 0.8
		p.Color = RARITY_COLOURS[cfg.rarity] or RARITY_COLOURS.Common
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = holder
		table.insert(placed, { part = p, cf = CFrame.new() })
	end
	-- where the item ended up in mount space: centre it, or stand it on the floor
	local lo, hi
	for _, it in ipairs(placed) do
		local h = it.part.Size * 0.5
		for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
			local v = it.cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
			lo = lo and Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
			hi = hi and Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
		end end end
	end
	-- stretching a turned sub-part is not exact: shrink the whole item back
	-- into its box if it came out a little over
	local ext = hi - lo
	local k = math.min(1, box.X / math.max(ext.X, 1e-3), box.Y / math.max(ext.Y, 1e-3), box.Z / math.max(ext.Z, 1e-3))
	if k < 0.999 then
		local c = (lo + hi) * 0.5
		for _, it in ipairs(placed) do
			it.part.Size *= k
			it.cf = CFrame.new(c + (it.cf.Position - c) * k) * (it.cf - it.cf.Position)
		end
		lo, hi = c + (lo - c) * k, c + (hi - c) * k
	end
	local mid = (lo + hi) * 0.5
	local shift = -mid
	if mount.align == "bottom" then shift = Vector3.new(-mid.X, -box.Y / 2 - lo.Y, -mid.Z) end
	-- side = ±1: flush with the box's outer side (a thin wheel outside the body)
	if mount.side then shift = Vector3.new(mount.side * box.X / 2 - (mount.side > 0 and hi.X or lo.X), shift.Y, shift.Z) end
	-- front = true: against the box's front (a boat's ENGINE item on the stern)
	if mount.front then shift = Vector3.new(shift.X, shift.Y, -box.Z / 2 - lo.Z) end
	local top = hi.Y + shift.Y
	if minTop and top < minTop then
		shift += Vector3.new(0, minTop - top, 0)
		top = minTop
	end
	local bottom = lo.Y + shift.Y
	for _, it in ipairs(placed) do
		it.part.CFrame = mountCF * CFrame.new(shift) * it.cf
		decoration(it.part)
		weld(weldTo or chassis, it.part)
	end
	holder.Parent = model
	return holder, top, bottom
end

-- ─── Seat on a ridden item ───────────────────────────────────────────────────

-- Highest point of the item's collision shape under the rider (rays down at
-- the seat and half a stud round it), in mount space; nil when nothing is
-- hit. The item goes into the workspace for the rays and straight back.
local function surfaceUnder(holder, spawnCF, seatLocal)
	if not holder then return nil end
	local parts, own = {}, {}
	for _, p in ipairs(holder:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, p); own[p] = true end
	end
	local parent = holder.Parent
	local best
	local ok = pcall(function()
		holder.Parent = workspace
		for _, p in ipairs(parts) do p.CanQuery = true end
		local params = RaycastParams.new()
		params.IgnoreWater = true   -- OCEAN's Terrain water is not ground (TerrainPlan.WATER)
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = parts
		for _, o in ipairs({ Vector3.zero, Vector3.new(0.5, 0, 0), Vector3.new(-0.5, 0, 0), Vector3.new(0, 0, 0.5),
			Vector3.new(0, 0, -0.5) }) do
			local from = spawnCF * (seatLocal * CFrame.new(o) * CFrame.new(0, 6, 0)).Position
			local hit = workspace:Raycast(from, spawnCF:VectorToWorldSpace(Vector3.new(0, -14, 0)), params)
			if hit and own[hit.Instance] then
				local y = spawnCF:PointToObjectSpace(hit.Position).Y
				best = best and math.max(best, y) or y
			end
		end
	end)
	for _, p in ipairs(parts) do p.CanQuery = false end
	holder.Parent = parent
	return ok and best or nil
end

-- ─── Spinning MOBILITY items ─────────────────────────────────────────────────

-- An invisible hub at `cf` joined to the chassis by a Motor6D named "Spin";
-- SpinFx (every client) turns the joint. Attributes say how.
local function spinHub(model, chassis, cf, spin, name)
	local hub = Instance.new("Part")
	hub.Name = name
	hub.Size = Vector3.new(0.1, 0.1, 0.1)
	hub.Transparency = 1
	hub.CFrame = cf
	decoration(hub)
	hub.Parent = model
	local m = Instance.new("Motor6D")
	m.Name = "Spin"
	m.Part0 = chassis
	m.Part1 = hub
	m.C0 = chassis.CFrame:ToObjectSpace(cf)
	m.C1 = CFrame.new()
	m.Parent = hub
	hub:SetAttribute("SpinAxis", spin.axis)
	hub:SetAttribute("SpinMode", spin.mode)
	hub:SetAttribute("SpinRadius", spin.radius or 1)
	hub:SetAttribute("SpinDir", spin.dir or 1)
	pcall(function() game:GetService("CollectionService"):AddTag(hub, "Spin") end)
	return hub
end

-- ─── Hat (HEAD item) ─────────────────────────────────────────────────────────

-- Where the hat's bottom sits with nobody in the seat: about a seated
-- avatar's head top (VehicleDesign.HAT).
hatBaseCF = function(seat)
	local hat = VehicleDesign.HAT
	return seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + hat.headTop - hat.sink, 0)
end

-- An invisible part standing on the middle of the hat's bottom is its pivot.
local HAT_BASE = 0.05
makeHat = function(holder, seat, chassis)
	local base = Instance.new("Part")
	base.Name = "HatBase"
	base.Size = Vector3.new(HAT_BASE, HAT_BASE, HAT_BASE)
	base.Transparency = 1
	base.CFrame = hatBaseCF(seat) * CFrame.new(0, HAT_BASE / 2, 0)
	decoration(base)
	base.Parent = holder
	weld(chassis, base)
	holder.PrimaryPart = base
	holder:SetAttribute("Hat", true)
	holder:SetAttribute("HatSink", VehicleDesign.HAT.sink)
end

local function hatOf(model)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Hat") and c.PrimaryPart then return c end
	end
	return nil
end

-- Unweld the hat, set it down at `cf` (its bottom) and weld it to `part`.
local function moveHat(hat, cf, part)
	for _, d in ipairs(hat:GetDescendants()) do
		if d:IsA("WeldConstraint") then d:Destroy() end
	end
	hat:PivotTo(cf * CFrame.new(0, HAT_BASE / 2, 0))
	for _, d in ipairs(hat:GetDescendants()) do
		-- anchored like what it rides on, or it stays behind when that moves
		if d:IsA("BasePart") then d.Anchored = part.Anchored; weld(part, d) end
	end
end

--- Puts the vehicle's HEAD item on `character`'s head (it rides on the
-- head from then on). Returns true when there was a hat and a head.
function VehicleBuilder.wearHat(model, character)
	local hat = model and hatOf(model)
	local head = character and character:FindFirstChild("Head")
	if not hat or not head or not head:IsA("BasePart") then return false end
	moveHat(hat, head.CFrame * CFrame.new(0, head.Size.Y / 2 - VehicleDesign.HAT.sink, 0), head)
	hat:SetAttribute("WornBy", character.Name)
	return true
end

--- The rider left: the hat goes back over the seat.
function VehicleBuilder.takeOffHat(model)
	local hat = model and hatOf(model)
	local seat = model and model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not hat or not seat or not hat:GetAttribute("WornBy") then return false end
	moveHat(hat, hatBaseCF(seat), model.PrimaryPart)
	hat:SetAttribute("WornBy", nil)
	return true
end

local function _applyStatVisuals(model, stats)
	-- Long boost → purple sparkles above the vehicle
	if stats.boostDuration and stats.boostDuration > 5 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color      = ColorSequence.new(Color3.fromRGB(200, 80, 255))
		emitter.Rate       = 8
		emitter.Lifetime   = NumberRange.new(1, 2)
		emitter.Speed      = NumberRange.new(2, 5)
		emitter.LightEmission = 0.8
		emitter.Parent     = model.PrimaryPart
	end
end

-- ─── Public: build ────────────────────────────────────────────────────────────

--- Assembles a complete vehicle Model at spawnCFrame (the chassis centre).
-- @param stats       table from VehicleStats.calculate()
-- @param biome       "FOREST" | "OCEAN" | "SKY"
-- @param spawnCFrame CFrame of the chassis centre; -Z is the front
-- @param slots       table { BODY, ENGINE, SPECIAL, MOBILITY, HEAD, TAIL } (item names)
-- @returns Model
--- A trail behind the chassis (cosmetic): a flat ribbon between two rear
-- attachments. Trails and attachments have no mass or collision.
function VehicleBuilder.addTrail(chassis, trail, biome)
	local pale = VehicleBuilder.RIDE_PALE_ROAD[biome or ""]
	local half = chassis.Size.X * 0.4
	local rear = chassis.Size.Z * 0.5
	local y = -chassis.Size.Y * 0.3
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailLeft"
	a0.Position = Vector3.new(-half, y, rear)
	a0.Parent = chassis
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailRight"
	a1.Position = Vector3.new(half, y, rear)
	a1.Parent = chassis
	local t = Instance.new("Trail")
	t.Name = "CosmeticTrail"
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.7
	t.MinLength = 0.1
	t.LightEmission = (trail.light or 0) * (pale and pale.emission or 1)
	t.Transparency = NumberSequence.new(0.15, 1)
	t.WidthScale = NumberSequence.new(1, 0.3)
	if trail.rainbow then
		t.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 220, 90)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 150, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
		})
	else
		local c = trail.colors or { Color3.new(1, 1, 1) }
		t.Color = ColorSequence.new(c[1], c[2] or c[1])
	end
	t.Parent = chassis
	return t
end

local RIDE_FX = {
	-- texture, colours, size start→end, lifetime, speed, spread, BaseRate (at full speed)
	flame   = { tex = "rbxasset://textures/particles/fire_main.dds", colors = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 60, 10) },
		size = { 1.6, 0.2 }, life = { 0.25, 0.5 }, speed = { 8, 14 }, spread = 14, rate = 90, light = 1 },
	sparks  = { tex = "rbxasset://textures/particles/sparkles_main.dds", colors = { Color3.fromRGB(40, 255, 230), Color3.fromRGB(255, 40, 200) },
		size = { 0.6, 0.1 }, life = { 0.3, 0.6 }, speed = { 12, 20 }, spread = 45, rate = 70, light = 1 },
	rainbow = { tex = "rbxasset://textures/particles/sparkles_main.dds", rainbow = true,
		size = { 1.1, 0.3 }, life = { 0.8, 1.3 }, speed = { 4, 9 }, spread = 30, rate = 140, light = 0.8 },
	gold    = { tex = "rbxasset://textures/particles/sparkles_main.dds", colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 180, 20) },
		size = { 0.9, 0.2 }, life = { 0.6, 1.0 }, speed = { 3, 7 }, spread = 60, rate = 80, light = 0.9 },
}
VehicleBuilder.RIDE_FX = RIDE_FX

local function rainbowSequence()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 220, 90)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
	})
end

-- Roads so pale that a ride's glow and glowing particles add up to a white
-- blob under the car (SKY's cloud road): both are toned down there.
VehicleBuilder.RIDE_PALE_ROAD = { SKY = { light = 0.35, emission = 0.25 } }

--- A special ride (Shared/Cosmetics "ride"): body material, a glow and
-- particles at the back. The particles' Rate follows the forward speed on
-- every client (CosmeticFx, attribute BaseRate); tagged "RideFx".
function VehicleBuilder.applyRide(model, chassis, ride, biome)
	local pale = VehicleBuilder.RIDE_PALE_ROAD[biome or ""]
	model:SetAttribute("Ride", ride.id)
	if ride.hue then model:SetAttribute("RideHue", true) end
	local ok, mat = pcall(function() return Enum.Material[ride.material or "SmoothPlastic"] end)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and not p:IsA("VehicleSeat") and p.Transparency < 1 then
			if p.Color == ride.body or p.Color == ride.accent then
				if ok and mat then p.Material = mat end
				if ride.material == "Foil" then p.Reflectance = 0.3 end
				if p.Color == ride.body then p:SetAttribute("RideBody", true) end
			end
		end
	end
	if ride.light then
		local light = Instance.new("PointLight")
		light.Name = "RideGlow"
		light.Color = ride.light
		light.Brightness = 2 * (pale and pale.light or 1)
		light.Range = 16
		light.Parent = chassis
	end
	local fx = ride.fx and RIDE_FX[ride.fx]
	if fx then
		local at = Instance.new("Attachment")
		at.Name = "RideFxAt"
		at.Position = Vector3.new(0, 0, chassis.Size.Z * 0.5)
		at.Parent = chassis
		local e = Instance.new("ParticleEmitter")
		e.Name = "RideFx"
		e.Texture = fx.tex
		e.Color = fx.rainbow and rainbowSequence() or ColorSequence.new(fx.colors[1], fx.colors[2])
		e.Size = NumberSequence.new(fx.size[1], fx.size[2])
		e.Lifetime = NumberRange.new(fx.life[1], fx.life[2])
		e.Speed = NumberRange.new(fx.speed[1], fx.speed[2])
		e.SpreadAngle = Vector2.new(fx.spread, fx.spread)
		e.EmissionDirection = Enum.NormalId.Back
		e.LightEmission = (fx.light or 0) * (pale and pale.emission or 1)
		e.Transparency = NumberSequence.new(0, 1)
		e.Rate = 0   -- CosmeticFx sets it from the speed
		e:SetAttribute("BaseRate", fx.rate)
		e.Parent = at
	end
	pcall(function() game:GetService("CollectionService"):AddTag(model, "RideFx") end)
end

--- look (optional, cosmetics from Shared/Cosmetics.look): { paint = { body, accent }, trail = {...}, ride = item }.
function VehicleBuilder.build(stats, biome, spawnCFrame, slots, look)
	slots = slots or {}
	look = look or {}
	biome = VehicleBuilder.SEAT[biome] and biome or "FOREST"
	spawnCFrame = spawnCFrame or CFrame.new()

	local model = Instance.new("Model")
	model.Name  = "Vehicle_" .. biome
	-- with streaming on, a car must arrive whole (not part by part)
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)

	local design = VehicleDesign.layout(biome, stats, slots)
	if look.paint and look.paint.body then
		design.palette = { body = look.paint.body, accent = look.paint.accent or design.palette.accent }
	end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = design.chassis.size
	chassis.CFrame = spawnCFrame
	chassis.Color = VehicleDesign.color(design, design.chassis.color)
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = false
	chassis.CanCollide = true
	chassis.Parent = model
	model.PrimaryPart = chassis
	local primaryPart = chassis

	-- Riding the BODY item: it goes first, the rest sits on its real top
	local rideTop, rideSink, rideHolder = nil, 0, nil
	if design.riding then
		chassis.Transparency = 1
		local mount = design.mounts.BODY[1]
		local chassisTop = design.chassis.size.Y / 2
		local holder, top, bottom = placeItem(slots.BODY, spawnCFrame * mount.cf, mount, model, chassis, "BODY",
			chassisTop - mount.cf.Position.Y)
		rideHolder = holder
		rideTop = mount.cf.Position.Y + (top or 0)
		rideSink = (mount.sink and top and bottom) and mount.sink * (top - bottom) or 0
		model:SetAttribute("Riding", slots.BODY)
		-- wheels / paddle wheels / propellers against the item's real size
		local lo, hi = boundsIn(model, spawnCFrame, "BODY")
		if lo then VehicleDesign.fitRide(design, lo, hi) end
	end
	local ride = design.ride
	local hubs = {}   -- spin hubs by group (plain wheels and propeller, MOBILITY copies)

	for _, spec in ipairs(VehicleDesign.partsFor(design, slots)) do
		local p = SHAPES[spec.shape]()
		p.Name = spec.name
		p.Size = spec.size
		local cf = spec.cf
		if spec.lift and rideTop then cf = CFrame.new(0, rideTop - ride.liftFrom, 0) * cf end
		p.CFrame = spawnCFrame * cf
		p.Color = VehicleDesign.color(design, spec.color)
		p.Material = spec.material or Enum.Material.SmoothPlastic
		p.Transparency = spec.transparency or 0
		decoration(p)
		p.Parent = model
		local to = chassis
		if spec.spin then
			-- a wheel and its hubcap turn round the wheel's centre
			local key = spec.spin.group
			if not hubs[key] then
				hubs[key] = spinHub(model, chassis, spawnCFrame * CFrame.new(cf.Position), spec.spin, "SpinHub_" .. key)
			end
			to = hubs[key]
		end
		weld(to, p)
	end

	local seatSpec = design.seat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "VehicleSeat"
	seat.Size = seatSpec.size
	seat.CFrame = spawnCFrame * seatSpec.cf
	if rideTop then
		-- on the item, no higher than its box allows
		-- (RIDE_LOOK sink: down into a tub or onto the cushions)
		local y = math.min(rideTop, design.mounts.BODY[1].cf.Position.Y + ride.box.Y / 2) - rideSink + seatSpec.size.Y / 2
		-- down onto the item's real surface when its box top is higher than
		-- what is under the rider (a treadmill's handle, a rocket's fins, a
		-- duck's head): no rider floating over it. Not for RIDE_LOOK sinks.
		if not design.mounts.BODY[1].sink then
			local surf = surfaceUnder(rideHolder, spawnCFrame, CFrame.new(0, y, ride.seatZ))
			if surf and surf < y - seatSpec.size.Y / 2 - 0.05 then
				-- (into the invisible chassis a little: the rider is part of the car)
				y = math.max(surf + seatSpec.size.Y / 2, design.chassis.size.Y / 2 - VehicleBuilder.SEAT_INTO_CHASSIS)
				model:SetAttribute("SeatDrop", math.floor((rideTop - surf) * 100 + 0.5) / 100)
			end
		end
		seat.CFrame = spawnCFrame * CFrame.new(0, y, ride.seatZ)
	end
	seat.Color = Color3.fromRGB(50, 50, 50)
	seat.Transparency = 1
	seat.MaxSpeed  = Constants.maxSpeedFor(biome, stats)
	seat.Torque    = Constants.torqueFor(biome, stats)
	seat.TurnSpeed = Constants.turnSpeedFor(biome, stats)
	seat.CanCollide = false
	seat.Parent = model
	weld(chassis, seat)

	-- Crafted items in their slot boxes (the ridden BODY item is already in)
	for _, slot in ipairs(VehicleBuilder.SLOTS) do
		local itemName = slots[slot]
		if itemName and not (slot == "BODY" and design.riding) then
			for i, mount in ipairs(design.mounts[slot] or {}) do
				local cf = mount.cf
				if mount.onRide and rideTop then cf = CFrame.new(0, rideTop, 0) * cf end
				if mount.hat then cf = spawnCFrame:ToObjectSpace(hatBaseCF(seat)) * CFrame.new(0, mount.box.Y / 2, 0) end
				-- spinning copies hang on a hub (one per group: a paddle wheel)
				local hub
				if mount.spin then
					local key = mount.spin.group or (slot .. i)
					hub = hubs[key]
					if not hub then
						hub = spinHub(model, chassis, spawnCFrame * (mount.spin.hub or cf), mount.spin, "SpinHub_" .. key)
						hubs[key] = hub
					end
				end
				local holder = placeItem(itemName, spawnCFrame * cf, mount, model, chassis, slot, nil, hub)
				if holder and mount.hat then makeHat(holder, seat, chassis) end
			end
		end
	end

	-- the HEAD item goes onto whoever sits down, back over the seat when they leave
	if slots.HEAD then
		pcall(function()
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				local hum = seat.Occupant
				if hum and hum.Parent then VehicleBuilder.wearHat(model, hum.Parent)
				else VehicleBuilder.takeOffHat(model) end
			end)
		end)
	end

	_applyStatVisuals(model, stats)
	if look.trail then VehicleBuilder.addTrail(chassis, look.trail, biome) end
	if look.ride then VehicleBuilder.applyRide(model, chassis, look.ride, biome) end

	-- ── Physics drive constraints ─────────────────────────────────────────────
	-- VehicleSeat's built-in Torque/TurnSpeed require Motor6D wheel joints to
	-- actually propel the vehicle. Without them, ThrottleFloat/SteerFloat are
	-- set by Roblox from WASD but no force is applied automatically.
	-- RacingClient reads those values and drives BodyVelocity/BodyAngularVelocity
	-- every Heartbeat for all biomes.

	local driveVel = Instance.new("BodyVelocity")
	driveVel.Name     = "DriveVelocity"
	driveVel.Velocity = Vector3.zero
	driveVel.MaxForce = Vector3.new(1e4, 0, 1e4)   -- no Y so gravity still acts
	driveVel.P        = 1e4
	driveVel.Parent   = primaryPart

	local driveAng = Instance.new("BodyAngularVelocity")
	driveAng.Name            = "DriveAngular"
	driveAng.AngularVelocity = Vector3.zero
	driveAng.MaxTorque       = Vector3.new(0, 1e4, 0)
	driveAng.P               = 1e4
	driveAng.Parent          = primaryPart

	-- BodyGyro: resists X/Z tilting so the vehicle stays upright.
	-- MaxTorque Y=0 so DriveAngular still steers freely.
	local gyro = Instance.new("BodyGyro")
	gyro.Name      = "UprightGyro"
	gyro.CFrame    = CFrame.new()
	gyro.MaxTorque = Vector3.new(1e5, 0, 1e5)
	gyro.D         = 200
	gyro.P         = 1e4
	gyro.Parent    = primaryPart

	-- SKY: fixed altitude hold at spawn height (updated by CraftingManager after parenting).
	if biome == "SKY" then
		local hover = Instance.new("BodyPosition")
		hover.Name     = "HoverPosition"
		hover.Position = spawnCFrame.Position
		hover.MaxForce = Vector3.new(0, 1e6, 0)
		hover.D        = 500
		hover.P        = 5e4
		hover.Parent   = primaryPart

	-- FOREST/OCEAN: suspension spring — target Y is updated every frame by
	-- RacingClient via a downward raycast so the vehicle rides over bumps and
	-- curbs instead of stopping against them.
	else
		local susp = Instance.new("BodyPosition")
		susp.Name     = "SuspensionHover"
		susp.Position = spawnCFrame.Position
		susp.MaxForce = Vector3.new(0, 4e4, 0)   -- Y-only; horizontal unchanged
		susp.P        = 1.2e4
		susp.D        = 600                        -- high damping → no bounce
		susp.Parent   = primaryPart
	end


	-- Tag for RacingManager
	local ownerTag = Instance.new("StringValue")
	ownerTag.Name  = "BiomeTag"
	ownerTag.Value = biome
	ownerTag.Parent = model

	-- Items E can fire (RacingClient and the HUD read them from the model)
	AbilitySlots.write(model, slots)

	return model
end

return VehicleBuilder
