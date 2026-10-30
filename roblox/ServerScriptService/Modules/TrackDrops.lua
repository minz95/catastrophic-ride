-- TrackDrops.lua
-- Items an ability leaves on the track (Pizza / Gas Can slick, Magnifying
-- Glass puddle, Kettle steam, Cactus, Log). The drop shows THE ITEM that made
-- it (a copy of ServerStorage.ItemModels, the model the crafted car wears),
-- standing on the track surface, with a warning ring and a floating label so
-- racers see it coming. The effect volume (`hazard`) is a separate part:
-- invisible for slicks and steam, a hitbox the size of the model for
-- obstacles ("what you see is what collides").
--
-- History (2026-10-22): drops were a 1.5×3 green block (Cactus), a 4×1 brown
-- cylinder (Log) or a flat disc, placed at car height − 1.5 instead of on
-- the ground, so they floated or sank and were easy to miss.
--
--   local drop = TrackDrops.place(itemName, vehicle, {
--     behind  = 6,        -- studs behind the car
--     show    = 4.5,      -- studs: largest side of the item model
--     hazard  = { size = Vector3, kind = "slick" | "cloud" | "obstacle", color },
--     lifetime = 12,
--   })
--   → { folder: Model, hazard: BasePart, position: Vector3, surfaceY: number? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Debris            = game:GetService("Debris")

local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
local RaceProgress = require(ReplicatedStorage.Shared.RaceProgress)
local BiomeConfig = require(game:GetService("ServerScriptService").Modules.BiomeConfig)

local TrackDrops = {}

TrackDrops.FOLDER = "TrackDrops"
TrackDrops.RING_COLOR = Color3.fromRGB(255, 190, 40)
TrackDrops.LABEL_DISTANCE = 220   -- studs the label stays visible

local function folder()
	local f = workspace:FindFirstChild(TrackDrops.FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = TrackDrops.FOLDER
		f.Parent = workspace
	end
	return f
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Ground under a point, ignoring cars and other drops. Returns Y or nil.
-- OCEAN: the rays skip the Terrain water (TerrainPlan.WATER), so out at sea
-- they found the seabed 13 studs down or nothing (2026-10-25: drops sank or
-- hung in the air); a drop floats on the surface unless something higher
-- (a dock, the flume) is under it.
local function groundY(pos, ignore)
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	local y = hit and hit.Position.Y or nil
	local biome = ReplicatedStorage:GetAttribute("Biome")
	local water = biome and BiomeConfig[biome] and BiomeConfig[biome].waterPlaneY
	if water then water += workspace:GetAttribute("WaterLevelOffset") or 0 end   -- waveFlood raises it
	if water and (y == nil or y < water) then y = water end
	return y
end

local function bounds(parts)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(parts) do
		local h = p.Size * 0.5
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local c = p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
					lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
					hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
				end
			end
		end
	end
	return (lo + hi) * 0.5, hi - lo
end

-- A copy of the item's model, `show` studs on its largest side, standing on
-- `base` (its bottom at base.Y), turned by `yaw`. Falls back to a coloured
-- block when the item has no model. Returns the parts and their size.
local function itemModel(itemName, parent, base, yaw, show)
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local tmpl = templates and templates:FindFirstChild(itemName)
	local parts = {}
	if tmpl then
		local clone = tmpl:Clone()
		local src = {}
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(src, d) end
		end
		if #src > 0 then
			local centre, size = bounds(src)
			local factor = show / math.max(size.X, size.Y, size.Z, 1e-3)
			local place = CFrame.new(base + Vector3.new(0, size.Y * factor * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
			for _, p in ipairs(src) do
				local rel = CFrame.new(centre):ToObjectSpace(p.CFrame)
				p.Size = p.Size * factor
				p.CFrame = place * CFrame.new(rel.Position * factor) * (rel - rel.Position)
				p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
				p.Parent = parent
				table.insert(parts, p)
			end
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then d:Destroy() end
			end
			clone:Destroy()
			return parts, size * factor
		end
		clone:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = "ItemBlock"
	p.Size = Vector3.new(show, show * 0.7, show)
	p.CFrame = CFrame.new(base + Vector3.new(0, p.Size.Y * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Color = Color3.fromRGB(230, 150, 60)
	p.Parent = parent
	return { p }, p.Size
end

local function label(parent, adornee, itemName, height)
	local cfg = ItemConfig[itemName]
	local gui = Instance.new("BillboardGui")
	gui.Name = "DropLabel"
	gui.Size = UDim2.new(0, 70, 0, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 2.5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = TrackDrops.LABEL_DISTANCE
	gui.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Text = "⚠️" .. ((cfg and cfg.icon) or "")
	t.TextColor3 = Color3.fromRGB(255, 220, 80)
	t.TextStrokeTransparency = 0.2
	t.Parent = gui
	gui.Parent = parent
end

--- Places `itemName`'s drop behind `vehicle`. See the header for opts.
TrackDrops.LANE_INSET = 2   -- studs inside the lane edge

--- `pos` moved sideways onto this round's lane when it lies past the edge.
function TrackDrops.clampToLane(pos)
	local biome = ReplicatedStorage:GetAttribute("Biome")
	local ok, geo = pcall(function() return RaceProgress.geometry(biome) end)
	if not ok or not geo then return pos end
	local p = geo:project(pos.X, pos.Z, nil, nil, pos.Y)
	if not p or not p.lateral then return pos end
	local maxOff = geo.halfWidth - TrackDrops.LANE_INSET
	if math.abs(p.lateral) <= maxOff then return pos end
	local off = Vector3.new(pos.X - p.cx, 0, pos.Z - p.cz)
	if off.Magnitude < 1e-3 then return pos end
	local inside = off.Unit * maxOff
	return Vector3.new(p.cx + inside.X, pos.Y, p.cz + inside.Z)
end

function TrackDrops.place(itemName, vehicle, opts)
	local primary = vehicle and vehicle.PrimaryPart
	if not primary then return nil end
	opts = opts or {}
	local look = flat(primary.CFrame.LookVector)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local behind = opts.behind or 6
	local pos = primary.Position - look * behind
	-- inside the lane: a car hugging the wall dropped its puddle past the
	-- road's edge, over nothing (Studio match-forest 2026-10-30: a Gas Can
	-- 21 studs off the centre line, OnGround false)
	pos = TrackDrops.clampToLane(pos)
	local f = folder()
	local surface = groundY(pos, { vehicle, f })
	local baseY = surface or (primary.Position.Y - primary.Size.Y * 0.5 - 0.2)
	local base = Vector3.new(pos.X, baseY, pos.Z)

	local model = Instance.new("Model")
	model.Name = "Drop_" .. itemName
	model:SetAttribute("Item", itemName)
	model:SetAttribute("OnGround", surface ~= nil)
	model.Parent = f

	local yaw = math.random() * math.pi * 2
	local _, size = itemModel(itemName, model, base, yaw, opts.show or 4.5)

	-- warning ring on the ground
	local hz = opts.hazard or {}
	local ringR = math.max(size.X, size.Z) * 0.5 + 2
	if hz.size then ringR = math.max(ringR, math.max(hz.size.X, hz.size.Z) * 0.5 + 0.5) end
	local ring = Instance.new("Part")
	ring.Name = "DropRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, ringR * 2, ringR * 2)
	ring.CFrame = CFrame.new(base + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = hz.color or TrackDrops.RING_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
	ring.Parent = model
	label(model, ring, itemName, size.Y)

	-- the effect volume
	local hazard = Instance.new("Part")
	hazard.Name = "DropHazard"
	hazard.Anchored = true
	hazard.CastShadow = false
	hazard.Transparency = 1
	if hz.kind == "obstacle" then
		hazard.Size = Vector3.new(math.max(size.X, 1), math.max(size.Y, 1), math.max(size.Z, 1))
		hazard.CFrame = CFrame.new(base + Vector3.new(0, hazard.Size.Y * 0.5, 0)) * CFrame.Angles(0, yaw, 0)
		hazard.CanCollide = true
	else
		local s = hz.size or Vector3.new(8, 3, 8)
		hazard.Size = s
		hazard.CFrame = CFrame.new(base + Vector3.new(0, s.Y * 0.5, 0))
		hazard.CanCollide = false
	end
	hazard.Parent = model

	Debris:AddItem(model, opts.lifetime or 12)
	return { folder = model, hazard = hazard, position = base, surfaceY = surface, size = size }
end

return TrackDrops
