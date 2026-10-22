-- HazardLook.lua
-- How track hazards look (HazardManager builds them; tools/scene_dump.luau
-- renders them without Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local HazardLook = {}

-- What a falling log looks like: a bark-brown trunk lying across part of the
-- lane, pale cut ends with rings, a stub branch and a bit of moss. Only the
-- trunk ("FallingLog", tagged Obstacle) collides; it is the hitbox the
-- player sees. (It used to be a plain brown 7×2.2×2.2 block that bounced and
-- rolled anywhere after landing, with no warning before it fell.)
local LOG_LOOK = {
	BARK = Color3.fromRGB(92, 60, 34),
	BARK_DARK = Color3.fromRGB(64, 41, 24),
	CUT = Color3.fromRGB(214, 176, 122),
	RING = Color3.fromRGB(160, 116, 70),
	MOSS = Color3.fromRGB(86, 130, 52),
	WARN = Color3.fromRGB(255, 70, 40),
}

local function _deco(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Wood
	if shape then p.Shape = shape end
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Parent = parent
	return p
end

-- A log model at `cf` (long axis = cf X); returns the model and its trunk.
function HazardLook.logModel(cf)
	local H = Constants.HAZARDS
	local L, D = H.LOG_SIZE[1], H.LOG_SIZE[2]
	local model = Instance.new("Model")
	model.Name = "FallingLogModel"
	local trunk = Instance.new("Part")
	trunk.Name = "FallingLog"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(L, D, D)
	trunk.CFrame = cf
	trunk.Color = LOG_LOOK.BARK
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.CanCollide = true
	trunk.Parent = model
	for _, side in ipairs({ -1, 1 }) do
		_deco(model, "LogEnd", Vector3.new(0.12, D * 0.9, D * 0.9), cf * CFrame.new(side * L / 2, 0, 0),
			LOG_LOOK.CUT, Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
		_deco(model, "LogRing", Vector3.new(0.14, D * 0.5, D * 0.5), cf * CFrame.new(side * (L / 2 + 0.01), 0, 0),
			LOG_LOOK.RING, Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	-- bark stripes, a stub branch and moss on top
	for k = -1, 1 do
		_deco(model, "Bark", Vector3.new(0.35, D * 1.02, D * 1.02), cf * CFrame.new(k * L * 0.28, 0, 0),
			LOG_LOOK.BARK_DARK, Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	_deco(model, "Branch", Vector3.new(0.5, 1.6, 0.5), cf * CFrame.new(L * 0.15, D * 0.55, 0) * CFrame.Angles(0, 0, -0.5), LOG_LOOK.BARK)
	_deco(model, "Moss", Vector3.new(L * 0.35, 0.25, D * 0.55), cf * CFrame.new(-L * 0.12, D * 0.46, 0), LOG_LOOK.MOSS, Enum.Material.Grass)
	model.PrimaryPart = trunk
	return model, trunk
end

-- Red ring + ⚠ where a log is about to land (LOG_WARN s ahead of it).
-- Unparented; the caller parents it and removes it.
function HazardLook.warnMarker(pos)
	local H = Constants.HAZARDS
	local ring = Instance.new("Part")
	ring.Name = "LogWarning"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, H.LOG_SIZE[1] + 2, H.LOG_SIZE[1] + 2)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = LOG_LOOK.WARN
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.45
	ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 60, 0, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.MaxDistance = 300
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Text = "⚠🪵"
	t.TextColor3 = Color3.fromRGB(255, 220, 80)
	t.TextStrokeTransparency = 0.2
	t.Parent = gui
	gui.Parent = ring
	return ring
end

return HazardLook
