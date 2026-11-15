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
-- given), seen from the front left. Returns the frame, or nil.
function RideCard.view(parent, model, char)
	if not model then return nil end
	local was = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(function() return model:Clone() end)
	model.Archivable = was
	if not ok or not copy then return nil end
	strip(copy)
	local view = Instance.new("ViewportFrame")
	view.Name             = "Ride"
	view.Size             = UDim2.fromScale(1, 1)
	view.BackgroundColor3 = Color3.fromRGB(40, 46, 70)
	view.BorderSizePixel  = 0
	view.Ambient          = Color3.fromRGB(150, 150, 165)
	view.LightColor       = Color3.fromRGB(255, 250, 240)
	view.LightDirection   = Vector3.new(-0.6, -1, -0.4)
	view.Parent           = parent
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(120, 140, 200), Color3.fromRGB(40, 40, 60))
	grad.Rotation = 90
	grad.Parent = view
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
	local plinth = Instance.new("Part")
	plinth.Shape    = Enum.PartType.Cylinder
	plinth.Anchored = true
	local r = math.max(vsize.X, vsize.Z) * 0.62 + 1
	plinth.Size     = Vector3.new(0.4, r * 2, r * 2)
	plinth.CFrame   = CFrame.new(vcf.Position.X, vcf.Position.Y - vsize.Y / 2 - 0.25, vcf.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	plinth.Color    = Color3.fromRGB(60, 62, 80)
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Parent   = world
	local cf, size = world:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = view
	view.CurrentCamera = cam
	local centre = cf.Position
	local radius = math.max(size.Magnitude / 2, 3)
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
	return view
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
