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

local _state = {}   -- [hub] = { base = C0, angle, turned }
CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(hub) _state[hub] = nil end)

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

RunService.RenderStepped:Connect(function(dt)
	for _, hub in ipairs(CollectionService:GetTagged("Spin")) do
		local m = hub:FindFirstChild("Spin")
		local root = m and m:IsA("Motor6D") and m.Part0
		if root then
			local st = _state[hub]
			if not st then
				st = { base = m.C0, angle = 0, turned = 0 }
				_state[hub] = st
			end
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
	harnessReport()
end)
