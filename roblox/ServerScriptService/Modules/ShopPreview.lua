-- ShopPreview.lua
-- The shop's pictures: every vehicle look (special ride, paint, trail) built
-- on a real vehicle of each biome (VehicleBuilder.build, the race's call,
-- empty slots) as a still model in ReplicatedStorage.ShopPreviews.<BIOME>,
-- one model per item id. The shop screen (ShopUI) turns them in
-- ViewportFrames. A trail cannot show on a still car (and particles do not
-- draw in a ViewportFrame), so a trail look gets a ribbon of glowing parts
-- behind the vehicle in its colours (TrailRibbon_<i>).
--
-- History (2026-10-27): the cards were colour swatches; nobody wants to
-- buy a swatch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)

local ShopPreview = {}

ShopPreview.FOLDER = "ShopPreviews"
ShopPreview.CATEGORIES = { "ride", "paint", "trail", "hat" }   -- vehicle looks; hats on a head
ShopPreview.RIBBON = { SEGMENTS = 5, LENGTH = 1.1, WIDTH = 0.6, HEIGHT = 0.3 }

local RAINBOW = {
	Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 40), Color3.fromRGB(60, 220, 90),
	Color3.fromRGB(60, 150, 255), Color3.fromRGB(180, 80, 255),
}

-- Physics movers and scripts have no place in a picture.
local STRIP = { "BodyMover", "BodyGyro", "BodyPosition", "BodyVelocity", "BodyAngularVelocity", "BodyForce",
	"Constraint", "BaseScript", "ParticleEmitter", "Trail", "Light", "Attachment" }

--- The ribbon colour of segment `i` of `n` for a trail look.
function ShopPreview.ribbonColor(trail, i, n)
	if trail.rainbow then return RAINBOW[((i - 1) % #RAINBOW) + 1] end
	local a = trail.colors and trail.colors[1] or Color3.new(1, 1, 1)
	local b = trail.colors and (trail.colors[2] or trail.colors[1]) or a
	return a:Lerp(b, n > 1 and (i - 1) / (n - 1) or 0)
end

local function ribbon(model, chassis, trail)
	local R = ShopPreview.RIBBON
	local back = chassis.CFrame * CFrame.new(0, -chassis.Size.Y * 0.25, chassis.Size.Z * 0.5)
	for i = 1, R.SEGMENTS do
		local p = Instance.new("Part")
		p.Name = "TrailRibbon_" .. i
		local shrink = 1 - (i - 1) / (R.SEGMENTS * 1.4)
		p.Size = Vector3.new(chassis.Size.X * R.WIDTH * shrink, R.HEIGHT * shrink, R.LENGTH)
		p.CFrame = back * CFrame.new(0, 0, (i - 0.5) * R.LENGTH)
		p.Color = ShopPreview.ribbonColor(trail, i, R.SEGMENTS)
		p.Material = Enum.Material.Neon
		p.Transparency = 0.15 + 0.6 * (i - 1) / R.SEGMENTS
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = model
	end
end

-- A hat on a classic yellow head (with a face, so the front shows).
local function hatOnHead(item)
	local HatDesigns = require(ReplicatedStorage.Shared.HatDesigns)
	local ShopHat = require(ServerScriptService.Modules.ShopHat)
	local model = Instance.new("Model")
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Shape = Enum.PartType.Ball
	head.Color = Color3.fromRGB(255, 205, 80)
	head.Anchored = true
	head.Parent = model
	for _, x in ipairs({ -0.22, 0.22 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.12, 0.2, 0.05)
		eye.CFrame = CFrame.new(x, 0.1, -0.57)
		eye.Color = Color3.fromRGB(30, 30, 30)
		eye.Anchored = true
		eye.Parent = model
	end
	local design = item.hat and HatDesigns.get(item.hat)
	if design then
		local hat = ShopHat.build(design, CFrame.new(0, 0.6, 0), 1)
		for _, p in ipairs(hat:GetChildren()) do
			p.Anchored = true
			p.Parent = model
		end
	end
	return model
end

--- The still model of `item` on `biome`'s vehicle (a hat: on a head).
function ShopPreview.buildOne(item, biome)
	if item.category == "hat" then
		local model = hatOnHead(item)
		model.Name = item.id
		return model
	end
	local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
	local stats = VehicleStats.calculate(nil, nil, nil, biome)
	local look = Cosmetics.look({ [item.category] = item.id })
	local model = VehicleBuilder.build(stats, biome, CFrame.new(), {}, look)
	if not model then return nil end
	local chassis = model:FindFirstChild("Chassis")
	for _, d in ipairs(model:GetDescendants()) do
		local strip = false
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then strip = true break end
		end
		if strip then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local trail = look.trail or (look.ride and look.ride.trail)
	if trail and chassis then ribbon(model, chassis, trail) end
	model.Name = item.id
	model:SetAttribute("Biome", biome)
	return model
end

--- Builds every vehicle look for `biome` into ShopPreviews.<biome>
-- (replacing an older set). `pause`: seconds between two builds.
function ShopPreview.build(biome, pause)
	local root = ReplicatedStorage:FindFirstChild(ShopPreview.FOLDER)
	if not root then
		root = Instance.new("Folder")
		root.Name = ShopPreview.FOLDER
		root.Parent = ReplicatedStorage
	end
	local folder = Instance.new("Folder")
	folder.Name = biome .. "_building"
	for _, cat in ipairs(ShopPreview.CATEGORIES) do
		for _, item in ipairs(Cosmetics.ITEMS[cat]) do
			local ok, model = pcall(ShopPreview.buildOne, item, biome)
			if ok and model then
				model.Parent = folder
			elseif not ok then
				warn("[ShopPreview] " .. item.id .. ": " .. tostring(model))
			end
			if pause then task.wait(pause) end
		end
	end
	local old = root:FindFirstChild(biome)
	if old then old:Destroy() end
	folder.Name = biome
	folder.Parent = root
	return folder
end

--- All biomes, one after the other, without a hitch (ShopManager at boot).
function ShopPreview.buildAll()
	for _, biome in ipairs(Constants.BIOMES) do
		ShopPreview.build(biome, 0.05)
	end
end

return ShopPreview
