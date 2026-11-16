-- RideCard.lua (client)
-- A ride in a ViewportFrame: a copy of the vehicle `model` with a copy of
-- `char` seated on it (Shared/SeatedCopy) on a round plinth, framed to fill
-- the view. The ride show's cards and the snapshot card (Shared/Snapshot)
-- use it; the crafting showroom has its own turning copy.

local SeatedCopy = require(script.Parent.SeatedCopy)

local RideCard = {}

local function strip(copy)
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BodyMover") or d:IsA("Constraint")
			or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

--- A ViewportFrame in `parent` showing `model` (and `char` riding it, when
-- given), seen from the front left, over a gradient backdrop. Returns the
-- backdrop frame (the view is its child), or nil. The gradient sits on the
-- backdrop, never on the view: a UIGradient on a ViewportFrame tints what it
-- renders, and the rides came out nearly black (Studio take 2026-11-16).
function RideCard.view(parent, model, char)
	if not model then return nil end
	local was = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(function() return model:Clone() end)
	model.Archivable = was
	if not ok or not copy then return nil end
	strip(copy)
	local back = Instance.new("Frame")
	back.Name             = "RideBack"
	back.Size             = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	back.BorderSizePixel  = 0
	back.ClipsDescendants = true
	back.Parent           = parent
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(120, 140, 200), Color3.fromRGB(40, 40, 60))
	grad.Rotation = 90
	grad.Parent = back
	local view = Instance.new("ViewportFrame")
	view.Name                   = "Ride"
	view.Size                   = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.BorderSizePixel        = 0
	view.Ambient                = Color3.fromRGB(170, 170, 185)
	view.LightColor             = Color3.fromRGB(255, 250, 240)
	view.LightDirection         = Vector3.new(-0.6, -1, -0.4)
	view.Parent                 = back
	local world = Instance.new("WorldModel")
	world.Parent = view
	copy.Parent = world
	-- at the origin, nose along -Z (the chassis' LookVector is the nose)
	copy:PivotTo(CFrame.new())
	local seat = copy:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat and char then
		local okR, rider = pcall(SeatedCopy.rider, seat, world, char)
		if okR and rider then pcall(SeatedCopy.wearHat, copy, rider) end
	end
	local vcf, vsize = copy:GetBoundingBox()
	-- framed on the ride and its rider, not the plinth (the plinth framed
	-- the rides small in the ride show's cards, Studio take 2026-11-16)
	local cf, size = world:GetBoundingBox()
	local plinth = Instance.new("Part")
	plinth.Shape    = Enum.PartType.Cylinder
	plinth.Anchored = true
	local r = math.max(vsize.X, vsize.Z) * 0.62 + 1
	plinth.Size     = Vector3.new(0.4, r * 2, r * 2)
	plinth.CFrame   = CFrame.new(vcf.Position.X, vcf.Position.Y - vsize.Y / 2 - 0.25, vcf.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	plinth.Color    = Color3.fromRGB(60, 62, 80)
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Parent   = world
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = view
	view.CurrentCamera = cam
	local centre = cf.Position
	local radius = math.max(size.Magnitude / 2 * 0.8, 2.5)
	local function frame()
		local aspect = math.max(view.AbsoluteSize.X, 1) / math.max(view.AbsoluteSize.Y, 1)
		local half = math.atan(math.tan(math.rad(cam.FieldOfView / 2)) * math.min(aspect, 1))
		local dist = radius / math.tan(half) * 1.05
		-- front left, a little above (the nose is -Z)
		local dir = Vector3.new(-0.75, 0.45, -1).Unit
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
	frame()
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	return back
end

--- "Piano + Rocket + Pizza" from a slots table (BODY, ENGINE, SPECIAL first).
function RideCard.items(slots)
	local out = {}
	for _, slot in ipairs({ "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }) do
		if slots and slots[slot] then table.insert(out, slots[slot]) end
	end
	return #out > 0 and table.concat(out, " + ") or "Plain junk"
end

return RideCard
