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

--- Places a copy of the item's model so it fits `box` (studs, in the
-- vehicle's axes) centred on `mountCF`, keeping its proportions. Falls back
-- to a rarity-coloured block when the item has no model.
local function placeItem(itemName, mountCF, box, model, chassis, slot)
	local cfg = ItemConfig[itemName]
	if not cfg then return nil end
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local tmpl = templates and templates:FindFirstChild(itemName)
	local holder = Instance.new("Model")
	holder.Name = "Item_" .. slot .. "_" .. itemName
	holder:SetAttribute("Slot", slot)
	holder:SetAttribute("Item", itemName)
	if tmpl then
		local clone = tmpl:Clone()
		local centre, size = bounds(clone)
		local factor = math.huge
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			if size[axis] > 1e-3 then factor = math.min(factor, box[axis] / size[axis]) end
		end
		if factor == math.huge then factor = 1 end
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then
				local rel = CFrame.new(centre):ToObjectSpace(p.CFrame)
				p.Size = p.Size * factor
				p.CFrame = mountCF * CFrame.new(rel.Position * factor) * (rel - rel.Position)
				decoration(p)
				p.Parent = holder
				weld(chassis, p)
			elseif p:IsA("WeldConstraint") or p:IsA("Weld") or p:IsA("Motor6D") then
				p:Destroy()
			end
		end
		clone:Destroy()
	else
		local p = Instance.new("Part")
		p.Name = "ItemBlock"
		p.Size = box * 0.8
		p.CFrame = mountCF
		p.Color = RARITY_COLOURS[cfg.rarity] or RARITY_COLOURS.Common
		p.Material = Enum.Material.SmoothPlastic
		decoration(p)
		p.Parent = holder
		weld(chassis, p)
	end
	holder.Parent = model
	return holder
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
function VehicleBuilder.addTrail(chassis, trail)
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
	t.LightEmission = trail.light or 0
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

--- look (optional, cosmetics from Shared/Cosmetics.look): { paint = { body, accent }, trail = {...} }.
function VehicleBuilder.build(stats, biome, spawnCFrame, slots, look)
	slots = slots or {}
	look = look or {}
	biome = VehicleBuilder.SEAT[biome] and biome or "FOREST"
	spawnCFrame = spawnCFrame or CFrame.new()

	local model = Instance.new("Model")
	model.Name  = "Vehicle_" .. biome

	local design = VehicleDesign.layout(biome, stats)
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

	for _, spec in ipairs(VehicleDesign.partsFor(design, slots)) do
		local p = SHAPES[spec.shape]()
		p.Name = spec.name
		p.Size = spec.size
		p.CFrame = spawnCFrame * spec.cf
		p.Color = VehicleDesign.color(design, spec.color)
		p.Material = spec.material or Enum.Material.SmoothPlastic
		p.Transparency = spec.transparency or 0
		decoration(p)
		p.Parent = model
		weld(chassis, p)
	end

	local seatSpec = design.seat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "VehicleSeat"
	seat.Size = seatSpec.size
	seat.CFrame = spawnCFrame * seatSpec.cf
	seat.Color = Color3.fromRGB(50, 50, 50)
	seat.Transparency = 1
	seat.MaxSpeed  = Constants.maxSpeedFor(biome, stats)
	seat.Torque    = Constants.torqueFor(biome, stats)
	seat.TurnSpeed = Constants.turnSpeedFor(biome, stats)
	seat.CanCollide = false
	seat.Parent = model
	weld(chassis, seat)

	-- Crafted items in their slot boxes
	for _, slot in ipairs(VehicleBuilder.SLOTS) do
		local itemName = slots[slot]
		if itemName then
			for _, mount in ipairs(design.mounts[slot] or {}) do
				placeItem(itemName, spawnCFrame * mount.cf, mount.box, model, chassis, slot)
			end
		end
	end

	_applyStatVisuals(model, stats)
	if look.trail then VehicleBuilder.addTrail(chassis, look.trail) end

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
