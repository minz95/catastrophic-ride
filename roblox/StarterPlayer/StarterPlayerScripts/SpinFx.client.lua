-- SpinFx.client.lua
-- MOBILITY items that spin (Modules/VehicleDesign `spin`, built by
-- VehicleBuilder as hubs tagged "Spin" on a Motor6D named "Spin"): every
-- client turns every car's hubs. Wheels and paddle wheels roll with the
-- car's forward speed; propellers idle fast and speed up with it.
-- Only the joint's C0 changes, locally: the parts are massless decoration.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PROP_IDLE = 14       -- rad/s with the plane standing still
local PROP_PER_SPEED = 0.4 -- rad/s more per stud/s forward

local _state = {}   -- [hub] = { motor, base = C0, angle, turned, place, view, checkedAt }
-- The tagged hubs as a set kept by the tag's signals: GetTagged("Spin")
-- every frame built a list of hundreds (most in the shop's hidden copies).
local _hubs = {}
for _, hub in ipairs(CollectionService:GetTagged("Spin")) do _hubs[hub] = true end
CollectionService:GetInstanceAddedSignal("Spin"):Connect(function(hub) _hubs[hub] = true end)
CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(hub)
	_hubs[hub] = nil
	_state[hub] = nil
end)

-- Harness bots report how far their own car's spinners turned.
local _lastReport = 0
local function harnessReport()
	if not LocalPlayer:GetAttribute("HarnessBot") or os.clock() - _lastReport < 2 then return end
	_lastReport = os.clock()
	local ch = ReplicatedStorage:FindFirstChild("HarnessChannel")
	if not ch then return end
	local modes, turned, n = {}, 0, 0
	for hub, st in pairs(_state) do
		local model = hub.Parent
		if model and model:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			modes[hub:GetAttribute("SpinMode") or "?"] = true
			turned = math.max(turned, st.turned)
			n += 1
		end
	end
	if n > 0 then
		local list = {}
		for m in pairs(modes) do table.insert(list, m) end
		ch:FireServer("spin_fx", { hubs = n, modes = table.concat(list, ","), turns = math.floor(turned / (2 * math.pi)) })
	end
end

-- Only hubs someone can see: in the world near the camera, or in a shown
-- ViewportFrame (shop cards). The copies in ReplicatedStorage.ShopPreviews
-- and PlayerGui.CraftPreview are never drawn (the showroom turns its own),
-- and far cars are specks: every hub's C0 was written every frame.
local FAR = 250            -- studs from the camera
local RECHECK = 1          -- s between two looks at where a hub is

local function placeOf(hub)
	if hub:IsDescendantOf(workspace) then return "world", nil end
	local vf = hub:FindFirstAncestorWhichIsA("ViewportFrame")
	if vf then return "view", vf end
	return "none", nil
end

RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	local now = os.clock()
	for hub in pairs(_hubs) do
		local st = _state[hub]
		if not st then
			local m = hub:FindFirstChild("Spin")
			if m and m:IsA("Motor6D") then
				-- first looks spread over RECHECK so they do not all fall on one frame
				st = { motor = m, base = m.C0, angle = 0, turned = 0, checkedAt = now - math.random() * RECHECK }
				_state[hub] = st
			end
		end
		if st then
			if now - st.checkedAt > RECHECK then
				st.checkedAt = now
				st.place, st.view = placeOf(hub)
			end
			local m = st.motor
			local root = st.place ~= "none" and m.Parent and m.Part0
			local show = root and ((st.place == "world" and (not camPos or (root.Position - camPos).Magnitude <= FAR))
				or (st.place == "view" and st.view.Visible))
			if show then
				local forward = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
				local rate
				if hub:GetAttribute("SpinMode") == "prop" then
					rate = (PROP_IDLE + math.abs(forward) * PROP_PER_SPEED) * (hub:GetAttribute("SpinDir") or 1)
				else
					-- rolling forward (-Z): the top moves forward, a negative turn about X
					rate = -forward / math.max(hub:GetAttribute("SpinRadius") or 1, 0.1)
				end
				st.angle = (st.angle + rate * dt) % (2 * math.pi)
				st.turned += math.abs(rate * dt)
				local turn = hub:GetAttribute("SpinAxis") == "Z" and CFrame.Angles(0, 0, st.angle) or CFrame.Angles(st.angle, 0, 0)
				m.C0 = st.base * turn
			end
		end
	end
	harnessReport()
end)
