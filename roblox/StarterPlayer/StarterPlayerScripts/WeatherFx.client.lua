-- WeatherFx.client.lua
-- Draws this round's weather (Shared/Weather, ReplicatedStorage attribute
-- "Weather") on this client: rain round the camera, lightning flashes,
-- headlights on every race car, a lantern on your avatar at night. The
-- server sets the lighting and the hazards; nothing here touches gameplay.
-- Off in the lobby.

local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Weather    = require(ReplicatedStorage.Shared.Weather)
local InputHints = require(ReplicatedStorage.Shared.InputHints)

local LocalPlayer = Players.LocalPlayer

local RAIN_RATE   = 420     -- drops a second at rain = 1 (phones: × PHONE)
local PHONE       = 0.5
local RAIN_BOX    = 150     -- studs square over the camera
local RAIN_HEIGHT = 45
local FLASH_EVERY = { 7, 15 }   -- s between lightning flashes
local LIGHT_NAME  = "WeatherLight"

local _fx = nil          -- current look.fx (nil = none)
local _rainPart = nil
local _carConn = nil
local _flashGen = 0

local function lookNow()
	local phase = ReplicatedStorage:GetAttribute("Phase")
	if phase == nil or phase == "LOBBY" then return nil end
	return Weather.look(ReplicatedStorage:GetAttribute("Biome"), ReplicatedStorage:GetAttribute("Weather"))
end

-- ── Rain ─────────────────────────────────────────────────────────────────────
local function stopRain()
	if _rainPart then _rainPart:Destroy(); _rainPart = nil end
end

local function startRain(amount)
	stopRain()
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = "WeatherRain", true, false, false, false
	p.Transparency, p.Size = 1, Vector3.new(RAIN_BOX, 1, RAIN_BOX)
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Speed = NumberRange.new(95, 120)
	e.Lifetime = NumberRange.new(0.7, 0.9)
	e.Rate = RAIN_RATE * amount * (InputHints.touchUI() and PHONE or 1)
	e.Size = NumberSequence.new(0.09)
	e.Squash = NumberSequence.new(-2.5)   -- thin streaks
	e.Transparency = NumberSequence.new(0.35)
	e.Color = ColorSequence.new(Color3.fromRGB(205, 218, 235))
	e.LightEmission = 0.2
	e.Parent = p
	p.Parent = workspace.CurrentCamera
	_rainPart = p
end

RunService.RenderStepped:Connect(function()
	if not _rainPart then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local at = cam.CFrame.Position + cam.CFrame.LookVector * 20
	_rainPart.CFrame = CFrame.new(at.X, cam.CFrame.Position.Y + RAIN_HEIGHT, at.Z)
end)

-- ── Lightning ────────────────────────────────────────────────────────────────
local function flash()
	local cc = Lighting:FindFirstChild("WeatherFlash")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "WeatherFlash"
		cc.Parent = Lighting
	end
	for _, step in ipairs({ { 0.55, 0.07 }, { 0, 0.09 }, { 0.35, 0.06 }, { 0, 0 } }) do
		cc.Brightness = step[1]
		if step[2] > 0 then task.wait(step[2]) end
	end
end

local function startLightning()
	_flashGen += 1
	local gen = _flashGen
	task.spawn(function()
		while gen == _flashGen do
			task.wait(FLASH_EVERY[1] + math.random() * (FLASH_EVERY[2] - FLASH_EVERY[1]))
			if gen ~= _flashGen then break end
			flash()
		end
	end)
end

-- ── Headlights ───────────────────────────────────────────────────────────────
local function isChassis(d)
	return d:IsA("BasePart") and d.Name == "Chassis" and d.Parent and d.Parent.Name:match("^Vehicle_") ~= nil
end

local function addHeadlights(chassis)
	if chassis:FindFirstChild(LIGHT_NAME) then return end
	local spot = Instance.new("SpotLight")
	spot.Name, spot.Face = LIGHT_NAME, Enum.NormalId.Front
	spot.Range, spot.Angle, spot.Brightness = 60, 70, 2.2
	spot.Color = Color3.fromRGB(255, 240, 200)
	spot.Shadows = false
	spot.Parent = chassis
	local glow = Instance.new("PointLight")
	glow.Name, glow.Range, glow.Brightness = LIGHT_NAME, 10, 0.5
	glow.Color = Color3.fromRGB(255, 230, 190)
	glow.Parent = chassis
end

local function clearLights()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == LIGHT_NAME and d:IsA("Light") then d:Destroy() end
	end
end

local function startHeadlights()
	if _carConn then return end
	for _, d in ipairs(workspace:GetDescendants()) do
		if isChassis(d) then addHeadlights(d) end
	end
	_carConn = workspace.DescendantAdded:Connect(function(d)
		if isChassis(d) then task.defer(addHeadlights, d) end
	end)
end

local function stopHeadlights()
	if _carConn then _carConn:Disconnect(); _carConn = nil end
end

-- ── Lantern (your avatar, at night) ─────────────────────────────────────────
local function setLantern(on)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local l = root:FindFirstChild(LIGHT_NAME)
	if on and not l then
		l = Instance.new("PointLight")
		l.Name, l.Range, l.Brightness = LIGHT_NAME, 28, 1.3
		l.Color = Color3.fromRGB(255, 225, 170)
		l.Parent = root
	elseif not on and l then
		l:Destroy()
	end
end

-- ── Apply ────────────────────────────────────────────────────────────────────
local function apply()
	local look = lookNow()
	local fx = look and look.fx or nil
	if fx == _fx then
		setLantern(fx ~= nil and fx.lantern == true)
		return
	end
	_fx = fx
	stopRain(); stopHeadlights(); clearLights()
	_flashGen += 1
	local cc = Lighting:FindFirstChild("WeatherFlash")
	if cc then cc.Brightness = 0 end
	if not fx then setLantern(false); return end
	if fx.rain then startRain(fx.rain) end
	if fx.lightning then startLightning() end
	if fx.headlights then startHeadlights() end
	setLantern(fx.lantern == true)
end

for _, attr in ipairs({ "Phase", "Weather", "Biome" }) do
	ReplicatedStorage:GetAttributeChangedSignal(attr):Connect(apply)
end
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	setLantern(_fx ~= nil and _fx.lantern == true)
end)
apply()
