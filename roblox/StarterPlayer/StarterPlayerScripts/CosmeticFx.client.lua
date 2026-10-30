-- CosmeticFx.client.lua
-- Special rides (Shared/Cosmetics "ride", built by VehicleBuilder.applyRide)
-- come alive on every client: their particles pour out while the vehicle
-- drives forward (Rate = BaseRate × forward speed / FULL_SPEED) and a
-- rainbow ride's body cycles through the colours.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local FULL_SPEED = 45   -- studs/s forward for the full rate
local STEP = 0.1

local _lastReport = 0
local function harnessReport(model, rate, forward)
	if not LocalPlayer:GetAttribute("HarnessBot") then return end
	if model:GetAttribute("OwnerUserId") ~= LocalPlayer.UserId then return end
	if os.clock() - _lastReport < 2 then return end
	_lastReport = os.clock()
	local ch = ReplicatedStorage:FindFirstChild("HarnessChannel")
	if ch then
		ch:FireServer("ride_fx", { ride = model:GetAttribute("Ride"), rate = math.floor(rate), forward = math.floor(forward) })
	end
end

task.spawn(function()
	local t = 0
	while true do
		task.wait(STEP)
		t += STEP
		for _, model in ipairs(CollectionService:GetTagged("RideFx")) do
			local pp = model.PrimaryPart
			-- the shop's copies in ReplicatedStorage.ShopPreviews are never drawn
			-- (cards show clones in ViewportFrames): ~90 models walked 10× a second
			if pp and model.Parent and not model:IsDescendantOf(ReplicatedStorage) then
				local v = pp.AssemblyLinearVelocity
				local forward = v:Dot(pp.CFrame.LookVector)
				local f = math.clamp(forward / FULL_SPEED, 0, 1)
				local total = 0
				for _, e in ipairs(model:GetDescendants()) do
					if e:IsA("ParticleEmitter") and e:GetAttribute("BaseRate") then
						local rate = e:GetAttribute("BaseRate") * f
						if math.abs(e.Rate - rate) > 0.05 then e.Rate = rate end
						total += rate
					elseif model:GetAttribute("RideHue") and e:IsA("BasePart") and e:GetAttribute("RideBody") then
						e.Color = Color3.fromHSV((t * 0.3) % 1, 0.7, 1)
					end
				end
				harnessReport(model, total, forward)
			end
		end
	end
end)
