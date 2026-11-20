-- GpCars.lua
-- Junk Grand Prix cars: a player's owned ride (a new car or a Legend Ride,
-- LegendShop.worn's shape) built life size by the race's VehicleBuilder,
-- with its GP numbers (Shared/GpCar.spec): the build's RideRating bars and
-- its shape (visible width over height: tall narrow rides roll over first).
-- The car keeps VehicleBuilder's movers (DriveVelocity, DriveAngular,
-- UprightGyro, SuspensionHover); GpClient (players) and GpBots drive them.
-- Attributes on the model: GpCar = true, Driver (name), Title, Spec (JSON),
-- Box. Pure helpers (`shapeOf`) work on any model.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GpCar = require(ReplicatedStorage.Shared.GpCar)
local RideRating = require(ReplicatedStorage.Shared.RideRating)
local NewCars = require(ReplicatedStorage.Shared.NewCars)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)

local GpCars = {}

GpCars.BIOME = "FOREST"     -- every GP car runs on wheels
GpCars.MAX_FORCE = 3e4      -- the drive movers (a GP car is quicker than a round's)

--- The car a player brings: the ride they wear, else the first they own.
-- Returns ride ({ title, slots, look, … }), or nil when they own none.
function GpCars.rideOf(player, rec)
	if not rec then return nil end
	local LegendShop = require(ServerScriptService.Modules.LegendShop)
	local CarDealer = require(ServerScriptService.Modules.CarDealer)
	local trying = CarDealer.trying(player)
	local ride = nil
	if not trying then ride = LegendShop.worn(player, rec) end
	if ride and not ride.trying then return ride end
	-- not wearing one (or only trying one on): the first owned
	local ids = {}
	for id in pairs(rec.legend or {}) do table.insert(ids, id) end
	table.sort(ids)
	if ids[1] then return rec.legend[ids[1]] end
	local cars = NewCars.owned(rec)
	if cars[1] then return NewCars.ride(cars[1].item) end
	return nil
end

--- True when the player owns any car (a new car or a Legend Ride).
function GpCars.ownsAny(rec)
	if not rec then return false end
	if next(rec.legend or {}) then return true end
	return next(rec.cars or {}) ~= nil
end

--- Visible width over height of a built car (its parts that show).
function GpCars.shapeOf(model)
	local lo, hi
	local base = model:GetPivot()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local w = base:PointToObjectSpace((d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position)
						lo = lo and lo:Min(w) or w
						hi = hi and hi:Max(w) or w
					end
				end
			end
		end
	end
	if not lo then return 1, 0, 0 end
	local size = hi - lo
	return size.X / math.max(size.Y, 0.5), size.X, size.Y
end

--- The GP numbers of a ride (its build and the built model's shape).
function GpCars.specOf(ride, model)
	local bars = RideRating.rate(ride.slots or {}, GpCars.BIOME).bars
	local shape = model and GpCars.shapeOf(model) or 1
	return GpCar.spec(bars, shape), bars
end

--- Builds `ride` as a GP car at `cf` (anchored until the start). Returns
-- the model and its spec, or nil.
function GpCars.build(ride, cf, driverName)
	local ok, model = pcall(function()
		local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
		local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
		local sl = ride.slots or {}
		local stats = VehicleStats.calculate(sl.BODY and ItemConfig[sl.BODY], sl.ENGINE and ItemConfig[sl.ENGINE],
			sl.SPECIAL and ItemConfig[sl.SPECIAL], GpCars.BIOME)
		stats = VehicleStats.applyMobility(stats, sl.MOBILITY and ItemConfig[sl.MOBILITY], GpCars.BIOME)
		local equipped = {}
		for cat, id in pairs(ride.look or {}) do equipped[cat] = id end
		return VehicleBuilder.build(stats, GpCars.BIOME, cf, sl, Cosmetics.look(equipped))
	end)
	if not ok or not model then
		warn("[GpCars] build: " .. tostring(model))
		return nil
	end
	model.Name = "GpCar_" .. (driverName or "car")
	local spec = GpCars.specOf(ride, model)
	model:SetAttribute("GpCar", true)
	model:SetAttribute("Driver", driverName)
	model:SetAttribute("Title", ride.title)
	model:SetAttribute("Spec", HttpService:JSONEncode(spec))
	local chassis = model.PrimaryPart
	local bv = chassis:FindFirstChild("DriveVelocity")
	if bv then bv.MaxForce = Vector3.new(GpCars.MAX_FORCE, 0, GpCars.MAX_FORCE) end
	local bav = chassis:FindFirstChild("DriveAngular")
	if bav then bav.MaxTorque = Vector3.new(0, GpCars.MAX_FORCE, 0) end
	chassis.Anchored = true
	GpCars.passThrough(model, GpCars.GROUP)
	return model, spec
end

-- ── The helmet (every GP driver, players and bots) ──────────────────────────
GpCars.HELMET = "GpHelmet"

--- Puts a racing helmet on `character`'s head: a shell in `colour` with a
-- stripe and a dark visor, massless and without collision.
function GpCars.wearHelmet(character, colour)
	local head = character and character:FindFirstChild("Head")
	if not head or head:FindFirstChild(GpCars.HELMET) then return nil end
	local d = math.max(head.Size.X, head.Size.Y, head.Size.Z) * 1.32
	local model = Instance.new("Model")
	model.Name = GpCars.HELMET
	local function piece(name, size, cf, col, mat, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = head.CFrame * cf
		p.Color = col
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, p
		w.Parent = p
		return p
	end
	colour = colour or Color3.fromRGB(220, 40, 40)
	piece("Shell", Vector3.new(d, d, d), CFrame.new(0, d * 0.08, 0.05 * d), colour, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("Stripe", Vector3.new(d * 0.22, d * 0.06, d * 1.02), CFrame.new(0, d * 0.5, 0.05 * d), Color3.fromRGB(245, 245, 245))
	piece("Visor", Vector3.new(d * 0.82, d * 0.26, d * 0.2), CFrame.new(0, d * 0.06, -d * 0.4), Color3.fromRGB(20, 22, 30), Enum.Material.Glass)
	piece("Chin", Vector3.new(d * 0.7, d * 0.22, d * 0.3), CFrame.new(0, -d * 0.24, -d * 0.32), colour)
	model.Parent = character
	return model
end

--- True when `character` wears the helmet on its head (not left behind
-- on an old head).
function GpCars.hasHelmet(character)
	local h = character and character:FindFirstChild(GpCars.HELMET)
	local head = character and character:FindFirstChild("Head")
	local shell = h and h:FindFirstChild("Shell")
	if not (head and shell) then return false end
	return (shell.Position - head.Position).Magnitude < 3
end

function GpCars.takeOffHelmet(character)
	local h = character and character:FindFirstChild(GpCars.HELMET)
	if h then h:Destroy() end
end

--- Puts every colliding part of `model` in collision group `name`, which
-- passes through itself: cars of one track never touch physically, the
-- server resolves their touches (Shared/CarBump).
function GpCars.passThrough(model, name)
	pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
		PhysicsService:CollisionGroupSetCollidable(name, name, false)
	end)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			pcall(function() d.CollisionGroup = name end)
		end
	end
end
GpCars.GROUP = "GpCar"

--- Lets the car go (unanchored, its owner the driver; nil = the server).
function GpCars.release(model, player)
	local chassis = model and model.PrimaryPart
	if not chassis then return end
	chassis.Anchored = false
	pcall(function() chassis:SetNetworkOwner(player) end)
end

--- Puts a car down at `cf`, upright and still, movers back on (a reset).
function GpCars.place(model, cf)
	local chassis = model and model.PrimaryPart
	if not chassis then return end
	local owner
	pcall(function() owner = chassis:GetNetworkOwner() end)
	chassis.Anchored = true
	model:PivotTo(cf)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	local gyro = chassis:FindFirstChild("UprightGyro")
	if gyro then gyro.MaxTorque = Vector3.new(1e5, 0, 1e5) gyro.CFrame = cf.Rotation end
	local bv = chassis:FindFirstChild("DriveVelocity")
	if bv then bv.Velocity = Vector3.zero bv.MaxForce = Vector3.new(GpCars.MAX_FORCE, 0, GpCars.MAX_FORCE) end
	local bav = chassis:FindFirstChild("DriveAngular")
	if bav then bav.AngularVelocity = Vector3.zero bav.MaxTorque = Vector3.new(0, GpCars.MAX_FORCE, 0) end
	local susp = chassis:FindFirstChild("SuspensionHover")
	if susp then susp.Position = cf.Position susp.MaxForce = Vector3.new(0, 4e4, 0) end
	task.delay(0.3, function()
		if chassis.Parent then
			chassis.Anchored = false
			pcall(function() chassis:SetNetworkOwner(owner) end)
		end
	end)
end

return GpCars
