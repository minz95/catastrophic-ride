-- VehicleBuilder.lua
-- Procedurally assembles a vehicle Model from stats + biome + slot assignments.
-- Each biome gets a distinct base shape. Item visuals are colour-coded Parts
-- attached at mount points. Studio-imported MeshParts can replace them later.
-- Resolves: Issue #27

local ServerStorage = game:GetService("ServerStorage")

local Constants  = require(game.ReplicatedStorage.Shared.Constants)
local ItemConfig = require(game.ServerScriptService.Modules.ItemConfig)
local VehicleStats = require(game.ReplicatedStorage.Shared.VehicleStats)

local VehicleBuilder = {}

-- ─── Colour helpers ───────────────────────────────────────────────────────────

local RARITY_COLOURS = {
	Common   = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(80,  200, 80),
	Rare     = Color3.fromRGB(80,  140, 255),
	Epic     = Color3.fromRGB(200, 80,  255),
}

local BIOME_PALETTE = {
	FOREST = { body = Color3.fromRGB(90,  130, 70),  accent = Color3.fromRGB(160, 220, 90) },
	OCEAN  = { body = Color3.fromRGB(40,  100, 170), accent = Color3.fromRGB(80,  190, 220) },
	SKY    = { body = Color3.fromRGB(200, 190, 240), accent = Color3.fromRGB(160, 130, 255) },
}

-- ─── Part factory ─────────────────────────────────────────────────────────────

local function block(size, cframe, colour, material, parent)
	local p = Instance.new("Part")
	p.Size     = size
	p.CFrame   = cframe
	p.Color    = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.Parent   = parent
	return p
end

local function cylinder(radius, height, cframe, colour, parent)
	local p = Instance.new("Part")
	p.Shape  = Enum.PartType.Cylinder
	p.Size   = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = cframe
	p.Color  = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.Parent   = parent
	return p
end

local function sphere(radius, cframe, colour, parent)
	local p = Instance.new("Part")
	p.Shape  = Enum.PartType.Ball
	p.Size   = Vector3.new(radius*2, radius*2, radius*2)
	p.CFrame = cframe
	p.Color  = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false  -- decorative spheres shouldn't block
	p.Parent = parent
	return p
end

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0  = part0
	w.Part1  = part1
	w.Parent = part0
end

-- ─── Item visual (coloured block representing the item) ───────────────────────

local function itemVisual(itemName, attachCF, model)
	local cfg  = ItemConfig[itemName]
	if not cfg then return end

	local colour = RARITY_COLOURS[cfg.rarity] or Color3.fromRGB(180, 180, 180)

	-- Try to load a pre-made model from ServerStorage.
	-- ItemModelPreloader stores models as ServerStorage.ItemModels/<itemName>
	-- (flat, no slotType subfolder).
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local tmpl      = templates and templates:FindFirstChild(itemName)
	if tmpl and tmpl.PrimaryPart then
		local clone = tmpl:Clone()
		-- Manual delta translation — SetPrimaryPartCFrame/PivotTo don't move
		-- FBX-imported nested parts in this codebase's mesh structure.
		local primary = clone.PrimaryPart
		local delta   = attachCF * primary.CFrame:Inverse()
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CFrame     = delta * p.CFrame
				p.CanCollide = false
				-- Massless: items are decorations and must not contribute to the
				-- assembly's mass distribution. FBX items have asymmetric mass
				-- (e.g. Camera lens to one side); when weighted into the chassis
				-- they shifted COM laterally, so BodyVelocity along LookVector
				-- created torque around the offset COM and the vehicle spun in
				-- place instead of driving forward.
				p.Massless   = true
			end
		end
		clone.Parent = model
		return clone.PrimaryPart
	end

	-- Fallback: simple coloured block
	local size = Vector3.new(0.9, 0.9, 0.9)
	local part = block(size, attachCF, colour, Enum.Material.Neon, model)
	part.Name      = "Item_" .. itemName
	part.CanCollide = false
	part.Massless   = true

	-- Label billboard
	local bb = Instance.new("BillboardGui")
	bb.Size        = UDim2.new(0, 60, 0, 20)
	bb.StudsOffset = Vector3.new(0, 0.8, 0)
	bb.AlwaysOnTop = false
	bb.Adornee     = part
	bb.Parent      = part

	local lbl = Instance.new("TextLabel")
	lbl.Size               = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text               = (cfg.icon or "") .. " " .. itemName
	lbl.TextColor3         = colour
	lbl.TextScaled         = true
	lbl.Font               = Enum.Font.GothamBold
	lbl.Parent             = bb

	return part
end

-- ─── Attachment helper ────────────────────────────────────────────────────────

local function attach(name, cf, parent)
	local a = Instance.new("Attachment")
	a.Name         = name
	a.CFrame       = cf
	a.Parent       = parent
	return a
end

-- ─── Stat-driven scale ────────────────────────────────────────────────────────
-- Maps normalised stat (0–STAT_BUDGET) to a scale multiplier

local function statScale(val, minS, maxS)
	local t = math.clamp(val / Constants.BALANCE.STAT_BUDGET, 0, 1)
	return minS + t * (maxS - minS)
end

-- ─── FOREST → Car ─────────────────────────────────────────────────────────────

local function buildCar(model, stats, palette, slots)
	-- Body size driven by stability + weight proxy
	local bodyL  = statScale(stats.stability, 3.0, 5.5)
	local bodyW  = statScale(stats.stability, 2.0, 3.2)
	local bodyH  = 1.2

	-- Chassis (PrimaryPart)
	local chassis = block(
		Vector3.new(bodyL, bodyH, bodyW),
		CFrame.new(0, bodyH / 2, 0),
		palette.body,
		Enum.Material.SmoothPlastic,
		model
	)
	chassis.Name = "Chassis"
	model.PrimaryPart = chassis

	-- Cabin
	block(
		Vector3.new(bodyL * 0.55, bodyH * 0.8, bodyW * 0.9),
		CFrame.new(0, bodyH + bodyH * 0.4, 0),
		palette.accent,
		Enum.Material.SmoothPlastic,
		model
	).Name = "Cabin"

	-- Wheels (scaled by stability → grip feel)
	local wheelR  = statScale(stats.stability, 0.38, 0.58)
	local wheelW  = 0.28
	local xOff    = bodyW / 2 + wheelW / 2 + 0.05
	local zOff    = bodyL / 2 - wheelR - 0.1
	local wheelColour = Color3.fromRGB(40, 40, 40)

	for _, sign in ipairs({ 1, -1 }) do          -- left / right
		for _, fwd in ipairs({ 1, -1 }) do        -- front / rear
			local w = cylinder(
				wheelR, wheelW,
				CFrame.new(sign * xOff, wheelR, fwd * zOff)
					* CFrame.Angles(0, 0, math.pi / 2),
				wheelColour,
				model
			)
			w.Name = "Wheel"
			weld(chassis, w)
		end
	end

	-- VehicleSeat (at top of chassis)
	local seat = Instance.new("VehicleSeat")
	seat.Size   = Vector3.new(1.4, 0.3, 1.4)
	seat.CFrame = CFrame.new(0, bodyH + 0.15, 0)
	seat.Color  = Color3.fromRGB(50, 50, 50)
	seat.MaxSpeed = math.clamp(stats.speed * 2.5, 20, 120)
	seat.Torque   = math.clamp(stats.acceleration * 4, 20, 200)
	seat.TurnSpeed = math.clamp(stats.stability * 0.3, 0.5, 3)
	seat.Parent = model
	weld(chassis, seat)

	-- Mount points
	attach("BodyMount",    CFrame.new(0,     bodyH * 1.5, 0),          chassis)
	attach("EngineMount",  CFrame.new(0,     bodyH * 0.5, -zOff),      chassis)
	attach("SpecialMount", CFrame.new(0,     bodyH * 1.5, bodyL * 0.3), chassis)
	attach("MobilityMount",CFrame.new(0,    -bodyH * 0.3, 0),           chassis)
	attach("HeadMount",    CFrame.new(0,     bodyH,       zOff + 0.4),  chassis)
	attach("TailMount",    CFrame.new(0,     bodyH,      -zOff - 0.4),  chassis)

	return chassis
end

-- ─── OCEAN → Boat ─────────────────────────────────────────────────────────────

local function buildBoat(model, stats, palette, slots)
	local hullL = statScale(stats.floatability, 4.0, 7.0)
	local hullW = statScale(stats.floatability, 2.0, 3.4)
	local hullH = 0.9

	-- Hull
	local hull = block(
		Vector3.new(hullL, hullH, hullW),
		CFrame.new(0, hullH / 2, 0),
		palette.body,
		Enum.Material.SmoothPlastic,
		model
	)
	hull.Name = "Chassis"
	model.PrimaryPart = hull

	-- Bow (wedge shape at front)
	local bow = Instance.new("WedgePart")
	bow.Size   = Vector3.new(1.2, hullH, hullW)
	bow.CFrame = CFrame.new(0, hullH / 2, hullL / 2 + 0.6)
				* CFrame.Angles(0, math.pi, 0)
	bow.Color  = palette.body
	bow.Material = Enum.Material.SmoothPlastic
	bow.Parent = model
	weld(hull, bow)

	-- Deck
	block(
		Vector3.new(hullL * 0.7, 0.15, hullW * 0.8),
		CFrame.new(-hullL * 0.05, hullH + 0.07, 0),
		palette.accent,
		Enum.Material.SmoothPlastic,
		model
	).Name = "Deck"

	-- Mast (if sail slot filled)
	if slots and slots.MOBILITY then
		local mastH = statScale(stats.floatability, 3.0, 5.5)
		local mast  = cylinder(
			0.12, mastH,
			CFrame.new(0, hullH + mastH / 2, hullL * 0.1)
				* CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(150, 110, 70),
			model
		)
		mast.Name = "Mast"
		weld(hull, mast)

		-- Sail (flat part)
		local sail = block(
			Vector3.new(0.08, mastH * 0.75, hullW * 0.85),
			CFrame.new(0, hullH + mastH * 0.5, hullL * 0.1),
			Color3.fromRGB(240, 240, 200),
			Enum.Material.Fabric,
			model
		)
		sail.Name = "Sail"
		weld(hull, sail)
	end

	-- VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Size   = Vector3.new(1.4, 0.3, 1.4)
	seat.CFrame = CFrame.new(-hullL * 0.2, hullH + 0.15, 0)
	seat.Color  = Color3.fromRGB(60, 40, 30)
	seat.MaxSpeed  = math.clamp(stats.speed * 2.0, 15, 80)
	seat.Torque    = math.clamp(stats.acceleration * 3, 15, 120)
	seat.TurnSpeed = math.clamp(stats.floatability * 0.25, 0.4, 2)
	seat.Parent = model
	weld(hull, seat)

	attach("BodyMount",    CFrame.new(0,    hullH + 0.3, 0),            hull)
	attach("EngineMount",  CFrame.new(0,    hullH * 0.5, -hullL * 0.4), hull)
	attach("SpecialMount", CFrame.new(0,    hullH + 0.3,  hullL * 0.3), hull)
	attach("MobilityMount",CFrame.new(0,    hullH,        hullL * 0.1), hull)
	attach("HeadMount",    CFrame.new(0,    hullH + 0.3,  hullL * 0.5 + 0.2), hull)
	attach("TailMount",    CFrame.new(0,    hullH * 0.5, -hullL * 0.5 - 0.2), hull)

	return hull
end

-- ─── SKY → Flying Vehicle ─────────────────────────────────────────────────────

local function buildFlyer(model, stats, palette, slots)
	local fuseL  = statScale(stats.flyability, 3.5, 6.0)
	local fuseR  = statScale(stats.flyability, 0.45, 0.75)
	local wingSpan = statScale(stats.flyability, 4.0, 8.0)

	-- Fuselage: Block long along Z (LookVector axis), default orientation.
	-- Roblox's Cylinder Shape locks its long axis to local +X. A previous
	-- attempt rotated the cylinder 90° around Y to make the body extend
	-- along Z visually, but that rotation also tilted PrimaryPart.LookVector
	-- to world -X — and RacingClient pushes the vehicle along LookVector,
	-- so the airplane slid sideways relative to where the visible body
	-- pointed. A Block has no shape-axis lock, so default orientation +
	-- Size.Z=fuseL gives a fuselage that visually extends in the LookVector
	-- (-Z) direction and matches the motion direction.
	local fuse = block(
		Vector3.new(fuseR * 2, fuseR * 2, fuseL),
		CFrame.new(0, 0, 0),
		palette.body,
		Enum.Material.SmoothPlastic,
		model
	)
	fuse.Name = "Chassis"
	model.PrimaryPart = fuse

	-- Nose cone — at front (-Z, where LookVector points). Original code
	-- placed the nose at +Z; with the cylinder rotation removed, that put
	-- the visible nose at the back of the LookVector direction (vehicle
	-- would have flown tail-first). The extra Y180° flip below mirrors the
	-- wedge so its tip points forward.
	local nosePart = Instance.new("WedgePart")
	nosePart.Size   = Vector3.new(fuseR * 2, fuseR * 2, fuseR * 3)
	nosePart.CFrame = CFrame.new(0, 0, -(fuseL / 2 + fuseR * 1.5))
				* CFrame.Angles(math.pi / 2, math.pi, 0)
	nosePart.Color  = palette.accent
	nosePart.Material = Enum.Material.SmoothPlastic
	nosePart.Parent = model
	weld(fuse, nosePart)

	-- Wings (sideways, slightly toward the rear)
	local wingH = fuseR * 0.3
	for _, side in ipairs({ 1, -1 }) do
		local wing = Instance.new("WedgePart")
		wing.Size   = Vector3.new(wingSpan / 2, wingH, fuseR * 2.5)
		wing.CFrame = CFrame.new(side * (wingSpan / 4 + fuseR), 0, fuseL * 0.1)
		wing.Color  = palette.accent
		wing.Material = Enum.Material.SmoothPlastic
		wing.Parent = model
		weld(fuse, wing)
	end

	-- Tail fins (rear, +Z)
	for _, side in ipairs({ 1, -1 }) do
		local fin = Instance.new("WedgePart")
		fin.Size   = Vector3.new(fuseR * 0.2, fuseR * 2.5, fuseR * 2)
		fin.CFrame = CFrame.new(side * fuseR * 0.6, fuseR * 1.0, fuseL * 0.4)
		fin.Color  = palette.body
		fin.Parent = model
		weld(fuse, fin)
	end

	-- VehicleSeat (top of fuselage)
	local seat = Instance.new("VehicleSeat")
	seat.Size   = Vector3.new(1.2, 0.3, 1.2)
	seat.CFrame = CFrame.new(0, fuseR + 0.15, 0)
	seat.Color  = Color3.fromRGB(30, 30, 50)
	seat.MaxSpeed  = math.clamp(stats.speed * 3.0, 30, 160)
	seat.Torque    = math.clamp(stats.acceleration * 5, 30, 250)
	seat.TurnSpeed = math.clamp(stats.flyability * 0.4, 0.5, 4)
	seat.Parent = model
	weld(fuse, seat)

	-- Mounts: -Z is front (nose end), +Z is rear (tail end).
	attach("BodyMount",    CFrame.new(0,    fuseR,    0),                                       fuse)
	attach("EngineMount",  CFrame.new(0,    0,         fuseL * 0.3),                            fuse)
	attach("SpecialMount", CFrame.new(0,    fuseR,    -fuseL * 0.2),                            fuse)
	attach("MobilityMount",CFrame.new(0,   -fuseR * 0.5, 0),                                    fuse)
	attach("HeadMount",    CFrame.new(0,    fuseR * 0.5, -(fuseL * 0.5 + fuseR * 1.5)),         fuse)
	attach("TailMount",    CFrame.new(0,    0,          fuseL * 0.5),                           fuse)

	return fuse
end

-- ─── Attach item visuals ──────────────────────────────────────────────────────

local function _attachItems(model, primaryPart, slots)
	local mountNames = {
		BODY     = "BodyMount",
		ENGINE   = "EngineMount",
		SPECIAL  = "SpecialMount",
		MOBILITY = "MobilityMount",
		HEAD     = "HeadMount",
		TAIL     = "TailMount",
	}

	for slotName, mountName in pairs(mountNames) do
		local itemName = slots[slotName]
		if not itemName then continue end

		local att = primaryPart:FindFirstChild(mountName)
		if not att then continue end

		local worldCF = primaryPart.CFrame * att.CFrame
		local visPart = itemVisual(itemName, worldCF, model)
		if visPart then
			weld(primaryPart, visPart)
		end
	end
end

-- ─── Colour customisation from stats ─────────────────────────────────────────

local function _applyStatVisuals(model, stats, palette)
	-- Fast vehicle → neon accent tint
	if stats.speed > Constants.BALANCE.STAT_BUDGET * 0.6 then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Cabin" or p.Name == "Deck" or p.Name == "Sail" then
				p.Material = Enum.Material.Neon
			end
		end
	end

	-- Epic-tier special → purple particle above vehicle
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

--- Assembles a complete vehicle Model.
-- @param stats       table from VehicleStats.calculate()
-- @param biome       "FOREST" | "OCEAN" | "SKY"
-- @param spawnCFrame CFrame where the vehicle should be placed
-- @param slots       table { BODY, ENGINE, SPECIAL, MOBILITY, HEAD, TAIL } (itemNames)
-- @returns Model

function VehicleBuilder.build(stats, biome, spawnCFrame, slots)
	slots = slots or {}

	local model = Instance.new("Model")
	model.Name  = "Vehicle_" .. biome

	local palette = BIOME_PALETTE[biome] or BIOME_PALETTE.FOREST
	local primaryPart

	if biome == "FOREST" then
		primaryPart = buildCar(model, stats, palette, slots)
	elseif biome == "OCEAN" then
		primaryPart = buildBoat(model, stats, palette, slots)
	elseif biome == "SKY" then
		primaryPart = buildFlyer(model, stats, palette, slots)
	else
		primaryPart = buildCar(model, stats, palette, slots)
	end

	-- Weld all loose parts to chassis; only chassis keeps CanCollide=true.
	-- Cabin, decorations, and VehicleSeat must be non-collidable so the
	-- player character can sit without being trapped inside geometry.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if part ~= primaryPart then
				part.CanCollide = false
				local hasWeld = false
				for _, c in ipairs(part:GetChildren()) do
					if c:IsA("WeldConstraint") then hasWeld = true; break end
				end
				if not hasWeld then weld(primaryPart, part) end
			end
		end
	end

	-- Attach item visuals at mount points
	_attachItems(model, primaryPart, slots)

	-- Visual flair from stats
	_applyStatVisuals(model, stats, palette)

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

	-- Place in world
	model:SetPrimaryPartCFrame(spawnCFrame)

	-- Tag for RacingManager
	local ownerTag = Instance.new("StringValue")
	ownerTag.Name  = "BiomeTag"
	ownerTag.Value = biome
	ownerTag.Parent = model

	return model
end

return VehicleBuilder
