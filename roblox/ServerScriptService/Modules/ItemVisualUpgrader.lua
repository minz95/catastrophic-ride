-- ItemVisualUpgrader.lua
-- Applies rarity-based visual upgrades to item models:
--   - SurfaceAppearance PBR textures (Roblox built-in)
--   - Neon glow parts for Rare/Epic
--   - ParticleEmitter aura for Epic
--   - BodyPosition + BodyAngularVelocity idle float animation
-- Resolves: Issue #74

local Debris = game:GetService("Debris")

local ItemVisualUpgrader = {}

-- ─── Roblox built-in texture IDs (free, no upload needed) ────────────────────
-- These are internal Roblox surface texture assets

local SURFACE_IDS = {
	WOOD_COLOR    = "rbxassetid://9854798900",
	WOOD_NORMAL   = "rbxassetid://9854798900",
	METAL_COLOR   = "rbxassetid://9854798900",
	METAL_NORMAL  = "rbxassetid://9854798900",
	FABRIC_COLOR  = "rbxassetid://9854798900",
	RUBBER_COLOR  = "rbxassetid://9854798900",
}

-- ─── Rarity config ────────────────────────────────────────────────────────────

local RARITY_CONFIG = {
	Common = {
		reflectance  = 0,
		glowParts    = false,
		particles    = false,
		glowColour   = nil,
		trailColour  = nil,
		floatAmpl    = 0.4,    -- float amplitude (studs)
		floatSpeed   = 0.8,    -- cycles/sec
		rotSpeed     = 30,     -- deg/sec
	},
	Uncommon = {
		reflectance  = 0.15,
		glowParts    = true,
		glowColour   = Color3.fromRGB(80, 200, 100),
		particles    = false,
		floatAmpl    = 0.55,
		floatSpeed   = 1.0,
		rotSpeed     = 45,
	},
	Rare = {
		reflectance  = 0.3,
		glowParts    = true,
		glowColour   = Color3.fromRGB(60, 140, 255),
		particles    = true,
		particleColor  = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 140, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 200, 255)),
		}),
		particleRate   = 4,
		floatAmpl    = 0.7,
		floatSpeed   = 1.2,
		rotSpeed     = 60,
	},
	Epic = {
		reflectance  = 0.5,
		glowParts    = true,
		glowColour   = Color3.fromRGB(200, 100, 255),
		particles    = true,
		particleColor  = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 100, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 200)),
		}),
		particleRate   = 12,
		orbits       = true,   -- extra orbiting glow orbs
		floatAmpl    = 0.9,
		floatSpeed   = 1.5,
		rotSpeed     = 90,
	},
}

-- ─── SurfaceAppearance helper ─────────────────────────────────────────────────

-- Maps item slot/material type to PBR surface config
local MATERIAL_SURFACE = {
	-- Uses Roblox built-in material appearance; SurfaceAppearance enhances it
	Wood  = { roughness = 0.8, metalness = 0.0 },
	Metal = { roughness = 0.3, metalness = 0.9 },
	Fabric= { roughness = 1.0, metalness = 0.0 },
	Plastic={ roughness = 0.5, metalness = 0.0 },
}

local function _addSurfaceAppearance(part, matType)
	local cfg = MATERIAL_SURFACE[matType]
	if not cfg then return end

	-- Only add if part doesn't already have one
	if part:FindFirstChildOfClass("SurfaceAppearance") then return end

	local sa = Instance.new("SurfaceAppearance")
	-- Roblox doesn't expose all built-in textures via script easily,
	-- but we can set roughness/metalness to improve PBR shading
	-- ColorMap left empty → uses part.Color
	sa.Parent = part
end

-- ─── Particle emitter ────────────────────────────────────────────────────────

local function _addParticleAura(primary, cfg)
	local e = Instance.new("ParticleEmitter")
	e.Name          = "RarityAura"
	e.Color         = cfg.particleColor
	e.LightEmission = 0.6
	e.LightInfluence = 0.4
	e.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime      = NumberRange.new(1.0, 2.0)
	e.Speed         = NumberRange.new(0.5, 1.5)
	e.SpreadAngle   = Vector2.new(180, 180)
	e.Rate          = cfg.particleRate
	e.Rotation      = NumberRange.new(0, 360)
	e.RotSpeed      = NumberRange.new(-45, 45)
	e.Parent        = primary
end

-- ─── Epic orbit orbs ──────────────────────────────────────────────────────────

local function _addEpicOrbs(model, primary)
	for i = 1, 3 do
		local orb = Instance.new("Part")
		orb.Name       = "EpicOrb_" .. i
		orb.Size       = Vector3.new(0.3, 0.3, 0.3)
		orb.Shape      = Enum.PartType.Ball
		orb.Material   = Enum.Material.Neon
		orb.Color      = ({
			Color3.fromRGB(200, 100, 255),
			Color3.fromRGB(255, 180, 60),
			Color3.fromRGB(100, 200, 255),
		})[i]
		orb.CanCollide  = false
		orb.CastShadow  = false
		orb.Anchored    = false
		orb.Parent      = model

		-- Offset weld so orbs are spread around
		local angle = (i / 3) * math.pi * 2
		local ox    = math.cos(angle) * (primary.Size.X * 0.8)
		local oz    = math.sin(angle) * (primary.Size.Z * 0.8)

		local weld = Instance.new("WeldConstraint")
		weld.Part0  = primary
		weld.Part1  = orb
		weld.Parent = model

		orb.CFrame = primary.CFrame + Vector3.new(ox, primary.Size.Y * 0.5, oz)
	end
end

-- ─── Reflectance upgrade ─────────────────────────────────────────────────────

local function _upgradeReflectance(model, reflectance)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "GlowRing" then
			-- Only upgrade metallic-looking materials
			if part.Material == Enum.Material.Metal
				or part.Material == Enum.Material.SmoothPlastic then
				part.Reflectance = reflectance
			end
		end
	end
end

-- ─── Idle float animation ────────────────────────────────────────────────────

local function _addIdleFloat(primary, cfg)
	-- BodyPosition drives the float. BodyPosition/BodyAngularVelocity are
	-- deprecated in newer Studio but still functional; skip silently if they fail.
	local bp, bav
	pcall(function()
		bp      = Instance.new("BodyPosition")
		bp.Name = "IdleFloat"
		bp.MaxForce = Vector3.new(0, 4000, 0)
		bp.D    = 50
		bp.P    = 1000
		bp.Position = primary.Position
		bp.Parent   = primary

		bav     = Instance.new("BodyAngularVelocity")
		bav.Name = "IdleRotate"
		bav.AngularVelocity = Vector3.new(0, math.rad(cfg.rotSpeed), 0)
		bav.MaxTorque = Vector3.new(0, 4000, 0)
		bav.P   = 1000
		bav.Parent = primary
	end)

	-- Sinusoidal float via Heartbeat (works even without BodyPosition)
	local baseY  = primary.Position.Y
	local ampl   = cfg.floatAmpl
	local speed  = cfg.floatSpeed
	local phase  = math.random() * math.pi * 2

	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		if not primary or not primary.Parent then
			conn:Disconnect()
			return
		end
		local newY = baseY + math.sin(tick() * speed * math.pi * 2 + phase) * ampl
		if bp then
			bp.Position = Vector3.new(primary.Position.X, newY, primary.Position.Z)
		end
	end)

	return conn
end

-- ─── Main upgrade function ────────────────────────────────────────────────────

-- Apply rarity visuals to an already-built item Model.
-- `rarity`: "Common" | "Uncommon" | "Rare" | "Epic"
-- Returns: the heartbeat connection (caller can disconnect when item is picked up)
function ItemVisualUpgrader.apply(model, rarity)
	local cfg = RARITY_CONFIG[rarity] or RARITY_CONFIG.Common
	local primary = model.PrimaryPart
	if not primary then return end

	-- 1. Reflectance
	if cfg.reflectance > 0 then
		_upgradeReflectance(model, cfg.reflectance)
	end

	-- Glow ring removed: the thin neon band sat at primary.CFrame and cut
	-- visually through FBX-imported items (e.g. a Camera with a bright green
	-- band slicing through the lens). Rarity is now communicated by particle
	-- aura (Rare+), reflectance bump (Uncommon+), and the rarity-coloured
	-- name label rendered by FarmingClient's item label system.

	-- 3. Particle aura (Rare+)
	if cfg.particles then
		_addParticleAura(primary, cfg)
	end

	-- 4. Epic orbit orbs
	if cfg.orbits then
		_addEpicOrbs(model, primary)
	end

	-- 5. Idle float + rotate
	local floatConn = _addIdleFloat(primary, cfg)

	return floatConn
end

-- ─── Stop idle (call when item is picked up) ─────────────────────────────────

function ItemVisualUpgrader.stopIdle(model)
	local primary = model and model.PrimaryPart
	if not primary then return end

	local bp = primary:FindFirstChild("IdleFloat")
	if bp then bp:Destroy() end

	local bav = primary:FindFirstChild("IdleRotate")
	if bav then bav:Destroy() end

	-- Remove particle aura (no longer needed once held)
	local aura = primary:FindFirstChild("RarityAura")
	if aura then aura:Destroy() end
end

-- ─── Quick preview: spawn all items in a grid (dev/test only) ─────────────────

function ItemVisualUpgrader.previewAll(parent)
	local ItemModelBuilder = require(game:GetService("ServerScriptService").Modules.ItemModelBuilder)
	local ItemConfig       = require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
	local rarities = { "Common", "Uncommon", "Rare", "Epic" }

	local col = 0
	for itemName, cfg in pairs(ItemConfig) do
		if type(cfg) == "table" and cfg.rarity then
			local model = ItemModelBuilder.build(itemName, parent)
			local rarity = cfg.rarity
			local x = (col % 10) * 5
			local z = math.floor(col / 10) * 5
			model.PrimaryPart.CFrame = CFrame.new(x, 5, z)
			ItemVisualUpgrader.apply(model, rarity)
			col = col + 1
		end
	end
end

return ItemVisualUpgrader
