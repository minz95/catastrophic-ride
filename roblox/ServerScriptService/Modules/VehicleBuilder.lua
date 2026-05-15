-- VehicleBuilder.lua
-- Procedurally assembles a vehicle Model from stats + biome + slot assignments.
-- Each biome gets a distinct base shape. Item visuals are colour-coded Parts
-- attached at mount points. Studio-imported MeshParts can replace them later.
-- Resolves: Issue #27

local ServerStorage = game:GetService("ServerStorage")

local Constants       = require(game.ReplicatedStorage.Shared.Constants)
local ItemConfig      = require(game.ServerScriptService.Modules.ItemConfig)
local VehicleStats    = require(game.ReplicatedStorage.Shared.VehicleStats)
local SlotMountConfig = require(game.ReplicatedStorage.Shared.SlotMountConfig)

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

-- ─── Item model loader (for BODY chassis + slot mounts) ──────────────────────
-- Clones ServerStorage.ItemModels/<name>, rescales so the longest bbox axis
-- equals targetStud, and returns the clone + final bbox Vector3. Returns nil
-- if no template exists (caller falls back).

local function _computeBBox(model)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local p = part.Position
			local h = part.Size * 0.5
			minV = Vector3.new(
				math.min(minV.X, p.X - h.X),
				math.min(minV.Y, p.Y - h.Y),
				math.min(minV.Z, p.Z - h.Z))
			maxV = Vector3.new(
				math.max(maxV.X, p.X + h.X),
				math.max(maxV.Y, p.Y + h.Y),
				math.max(maxV.Z, p.Z + h.Z))
		end
	end
	return minV, maxV
end

local function _loadItemModel(itemName, targetStud)
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local tmpl      = templates and templates:FindFirstChild(itemName)
	if not tmpl then return nil end

	local clone = tmpl:Clone()

	local minV, maxV = _computeBBox(clone)
	if minV.X == math.huge then
		clone:Destroy()
		return nil
	end

	local extent = maxV - minV
	local maxDim = math.max(extent.X, extent.Y, extent.Z)
	local factor = (maxDim > 0) and (targetStud / maxDim) or 1
	local center = (minV + maxV) * 0.5

	-- Rescale around the bbox centroid so the model stays centred at origin.
	-- Mirrors ItemModelPreloader's TARGET_MAX rescale (L75–112) — Model:ScaleTo()
	-- breaks FBX-imported nested part positions in this codebase.
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Size = part.Size * factor
			local rot = part.CFrame - part.CFrame.Position
			local newPos = center + (part.Position - center) * factor
			part.CFrame = rot + newPos
		end
	end

	-- Re-centre clone so the bbox midpoint sits at (0,0,0) — anchors and mount
	-- offsets are expressed relative to anchor origin, so the BODY/decoration
	-- must start centred to avoid a constant offset bug.
	local recentre = -((minV + maxV) * 0.5 * factor)
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = part.CFrame + recentre
		end
	end

	local finalSize = extent * factor
	return clone, finalSize
end

-- ─── BODY-driven chassis ──────────────────────────────────────────────────────
-- Replaces the procedural box with the player's BODY item as the visible body.
-- A small hidden anchor stays as model.PrimaryPart so drive constraints,
-- LookVector math, and camera follow stay decoupled from arbitrary FBX
-- orientations (each item has a different "forward" axis).

local function _buildChassisFromBody(model, biome, slots, palette, stats)
	local mount = SlotMountConfig.get("BODY", biome)
	if not mount then return nil end

	local bodyName = slots.BODY
	local bodyClone, bboxSize = _loadItemModel(bodyName, mount.scale)
	if not bodyClone then return nil end

	-- Hidden anchor at model origin. PrimaryPart for everyone (RacingClient,
	-- RacingManager, drive loop) — keeps the contract stable regardless of
	-- which item is BODY (each FBX has a different "forward" axis).
	local anchor = Instance.new("Part")
	anchor.Name           = "Chassis"
	anchor.Size           = Vector3.new(1.6, 0.4, 1.6)
	anchor.CFrame         = CFrame.new(0, 0, 0)
	anchor.Transparency   = 1
	anchor.CanCollide     = true
	anchor.CanQuery       = false
	anchor.TopSurface     = Enum.SurfaceType.Smooth
	anchor.BottomSurface  = Enum.SurfaceType.Smooth
	anchor.Anchored       = false
	anchor.Parent         = model
	model.PrimaryPart     = anchor

	-- bodyClone is bbox-centred at (0,0,0). Translate it by mount.offset so the
	-- BODY visual sits where SlotMountConfig says it should (typically slightly
	-- above the anchor so wheels/sail will dangle below).
	local bodyDelta = mount.offset
	for _, p in ipairs(bodyClone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame     = p.CFrame + bodyDelta
			p.CanCollide = false
			p.Anchored   = false
		end
	end
	-- Re-parent children directly under `model` so SetPrimaryPartCFrame moves
	-- them with the anchor. Then drop the now-empty wrapper.
	for _, c in ipairs(bodyClone:GetChildren()) do
		c.Parent = model
	end
	bodyClone:Destroy()

	-- Weld every loose BasePart to the anchor so the assembly moves as one.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= anchor then
			weld(anchor, p)
		end
	end

	-- VehicleSeat — top of BODY bbox + clearance.
	local seatY    = bodyDelta.Y + bboxSize.Y * 0.5 + 0.15
	local seat = Instance.new("VehicleSeat")
	seat.Size   = Vector3.new(1.4, 0.3, 1.4)
	seat.CFrame = CFrame.new(0, seatY, 0)
	seat.Color  = Color3.fromRGB(50, 50, 50)
	seat.MaxSpeed  = math.clamp(stats.speed * 2.5, 20, 120)
	seat.Torque    = math.clamp(stats.acceleration * 4, 20, 200)
	seat.TurnSpeed = math.clamp((stats.stability or stats.floatability or stats.flyability or 20) * 0.3, 0.5, 3)
	seat.Parent = model
	weld(anchor, seat)

	-- Mount Attachments — sized to bbox so HEAD/TAIL etc. land at silhouette edges.
	-- Conventions match the legacy procedural builders:
	--   FOREST/OCEAN: +Z = rear, -Z = front
	--   SKY:          -Z = forward (LookVector), +Z = rear (see buildFlyer L329)
	local hx = bboxSize.X * 0.5
	local hy = bboxSize.Y * 0.5
	local hz = bboxSize.Z * 0.5
	local function _att(name, lx, ly, lz)
		local a = Instance.new("Attachment")
		a.Name   = name
		a.CFrame = CFrame.new(lx, ly, lz)
		a.Parent = anchor
		return a
	end
	_att("BodyMount",     0,  bodyDelta.Y + hy + 0.2, 0)
	_att("EngineMount",   0,  bodyDelta.Y,            hz * 0.8)
	_att("SpecialMount",  0,  bodyDelta.Y + hy + 0.2, hz * 0.3)
	_att("MobilityMount", 0,  bodyDelta.Y - hy + 0.1, 0)
	_att("HeadMount",     0,  bodyDelta.Y + hy * 0.6, -hz * 1.1)
	_att("TailMount",     0,  bodyDelta.Y + hy * 0.6,  hz * 1.1)

	return anchor, bboxSize
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
			end
		end
		clone.Parent = model
		return clone.PrimaryPart
	end

	-- Fallback: simple coloured block
	local size = Vector3.new(0.9, 0.9, 0.9)
	local part = block(size, attachCF, colour, Enum.Material.Neon, model)
	part.Name  = "Item_" .. itemName

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

	-- Wheels (scaled by stability → grip feel). Skipped when MOBILITY filled —
	-- _attachSlotItem will mount the chosen item via the "wheels4" pattern at
	-- the four wheel positions instead, so we'd otherwise have duplicates.
	local wheelR  = statScale(stats.stability, 0.38, 0.58)
	local wheelW  = 0.28
	local xOff    = bodyW / 2 + wheelW / 2 + 0.05
	local zOff    = bodyL / 2 - wheelR - 0.1
	local wheelColour = Color3.fromRGB(40, 40, 40)

	if not (slots and slots.MOBILITY) then
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

	return chassis, Vector3.new(bodyW, bodyH, bodyL)
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

	-- Procedural mast + sail. Built only when MOBILITY is empty so the boat
	-- still has *something* up top. When MOBILITY is filled, _attachSlotItem
	-- with the "sail" pattern places the chosen item there instead.
	-- Pre-PR-C this condition was inverted (built only when MOBILITY filled,
	-- as a backdrop for the small decoration) — that decoration is gone now.
	if not (slots and slots.MOBILITY) then
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

	return hull, Vector3.new(hullW, hullH, hullL)
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

	-- Wings (sideways, slightly toward the rear). Skipped when MOBILITY filled —
	-- _attachSlotItem with the "wings2" pattern mounts the chosen item there.
	local wingH = fuseR * 0.3
	if not (slots and slots.MOBILITY) then
		for _, side in ipairs({ 1, -1 }) do
			local wing = Instance.new("WedgePart")
			wing.Size   = Vector3.new(wingSpan / 2, wingH, fuseR * 2.5)
			wing.CFrame = CFrame.new(side * (wingSpan / 4 + fuseR), 0, fuseL * 0.1)
			wing.Color  = palette.accent
			wing.Material = Enum.Material.SmoothPlastic
			wing.Parent = model
			weld(fuse, wing)
		end
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

	-- bbox proxy: width = wingSpan when wings exist, otherwise fuseR*2.
	-- _attachSlotItem reads X from this to spread wings/wheels — when wings
	-- are suppressed (MOBILITY filled), the chosen item should be placed at
	-- the wing extent, so report wingSpan unconditionally.
	return fuse, Vector3.new(wingSpan, fuseR * 2, fuseL)
end

-- ─── Slot mount pattern dispatch ─────────────────────────────────────────────
-- Each pattern returns a list of local CFrames (relative to anchor) for where
-- the cloned item should be placed. _attachSlotItem then clones one item per
-- transform, applies it, and welds to the anchor.

local function _rotCF(rot)
	return CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function _patternSingle(mount, bboxSize)
	return { CFrame.new(mount.offset) * _rotCF(mount.rot) }
end

local function _patternWheels4(mount, bboxSize)
	-- 4 wheels at corners of bbox X-Z plane, slightly below body bottom.
	local x = bboxSize.X * 0.55 + mount.scale * 0.1
	local z = bboxSize.Z * 0.40
	local y = -bboxSize.Y * 0.5 + mount.offset.Y
	local rotCF = _rotCF(mount.rot)
	return {
		CFrame.new( x, y,  z) * rotCF,
		CFrame.new( x, y, -z) * rotCF,
		CFrame.new(-x, y,  z) * rotCF,
		CFrame.new(-x, y, -z) * rotCF,
	}
end

local function _patternWings2(mount, bboxSize)
	-- 2 wings extending out on +X and -X. -X wing is mirrored 180° around Y so
	-- asymmetric wing meshes still point outward.
	local x = bboxSize.X * 0.5 + mount.scale * 0.5
	local rotR = _rotCF(mount.rot)
	local rotL = _rotCF(Vector3.new(mount.rot.X, mount.rot.Y + 180, mount.rot.Z))
	return {
		CFrame.new( x, mount.offset.Y, mount.offset.Z) * rotR,
		CFrame.new(-x, mount.offset.Y, mount.offset.Z) * rotL,
	}
end

local PATTERN_DISPATCH = {
	wheels4 = _patternWheels4,
	wings2  = _patternWings2,
	sail    = _patternSingle,  -- sail = single clone, just placed high; scale handles tall look
	single  = _patternSingle,
}

local SLOT_TO_MOUNT = {
	BODY     = "BodyMount",
	ENGINE   = "EngineMount",
	SPECIAL  = "SpecialMount",
	MOBILITY = "MobilityMount",
	HEAD     = "HeadMount",
	TAIL     = "TailMount",
}

local function _attachSlotItem(slotName, itemName, model, anchor, biome, bboxSize)
	local mount = SlotMountConfig.get(slotName, biome)
	if not mount or not anchor then return end

	local dispatch = PATTERN_DISPATCH[mount.pattern] or _patternSingle
	local transforms = dispatch(mount, bboxSize)

	for _, localCF in ipairs(transforms) do
		local clone = _loadItemModel(itemName, mount.scale)
		if clone then
			-- clone is bbox-centred at origin → multiplying each part's CFrame
			-- by localCF translates+rotates the whole assembly to the target
			-- local pose. anchor sits at world origin during build, so local
			-- CFrame == world CFrame here; SetPrimaryPartCFrame later moves
			-- the welded assembly together.
			for _, p in ipairs(clone:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CFrame     = localCF * p.CFrame
					p.CanCollide = false
					p.Anchored   = false
				end
			end
			for _, c in ipairs(clone:GetChildren()) do
				c.Parent = model
			end
			-- Weld every BasePart of the relocated clone to the anchor —
			-- _attachItems runs *after* the main weld loop in build(), so any
			-- parts we add here need their own welds.
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and p ~= anchor then
					local hasWeld = false
					for _, ch in ipairs(p:GetChildren()) do
						if ch:IsA("WeldConstraint") then hasWeld = true; break end
					end
					if not hasWeld then weld(anchor, p) end
				end
			end
			clone:Destroy()
		else
			-- No FBX template — fall back to a single coloured-block visual at
			-- the first transform so the slot is at least visually marked.
			local worldCF = anchor.CFrame * localCF
			local visPart = itemVisual(itemName, worldCF, model)
			if visPart then weld(anchor, visPart) end
			break
		end
	end
end

local function _attachItems(model, primaryPart, slots, biome, bboxSize)
	for slotName, _ in pairs(SLOT_TO_MOUNT) do
		local itemName = slots[slotName]
		if itemName then
			_attachSlotItem(slotName, itemName, model, primaryPart, biome, bboxSize)
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
	local bboxSize
	local bodyDriven = false

	-- BODY slot drives the chassis when filled and the item has a template.
	-- Falls through to procedural builders if either condition fails — preserves
	-- behaviour for empty crafts and item-template gaps.
	if slots.BODY then
		primaryPart, bboxSize = _buildChassisFromBody(model, biome, slots, palette, stats)
		bodyDriven  = primaryPart ~= nil
	end

	if not primaryPart then
		if biome == "FOREST" then
			primaryPart, bboxSize = buildCar(model, stats, palette, slots)
		elseif biome == "OCEAN" then
			primaryPart, bboxSize = buildBoat(model, stats, palette, slots)
		elseif biome == "SKY" then
			primaryPart, bboxSize = buildFlyer(model, stats, palette, slots)
		else
			primaryPart, bboxSize = buildCar(model, stats, palette, slots)
		end
	end

	bboxSize = bboxSize or Vector3.new(4, 1.5, 5)

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

	-- Attach item visuals at mount points. When the BODY drove the chassis, the
	-- BODY model is already mounted as the visible body — don't re-attach it as
	-- a decoration or it stacks a second copy on the BodyMount attachment.
	local visualSlots = slots
	if bodyDriven then
		visualSlots = {}
		for k, v in pairs(slots) do
			if k ~= "BODY" then visualSlots[k] = v end
		end
	end
	_attachItems(model, primaryPart, visualSlots, biome, bboxSize)

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
