-- ShopHat.lua
-- The shop hat (Cosmetics "hat", parts from Shared/HatDesigns) on a
-- player's avatar: built on the head, welded, massless and without
-- collision, so it never changes how anyone moves. Worn in every phase;
-- hidden while the player wears a crafted HEAD item (VehicleBuilder.wearHat),
-- shown again when it comes off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local HatDesigns = require(ReplicatedStorage.Shared.HatDesigns)

local ShopHat = {}

ShopHat.NAME = "ShopHat"

local function part(p, scale)
	local inst = Instance.new("Part")
	inst.Name = "HatPart"
	local size = p.size * scale
	if p.shape == "cyl" then
		inst.Shape = Enum.PartType.Cylinder
		inst.Size = Vector3.new(size.Y, size.X, size.Z)   -- the cylinder's axis is X: stood up below
	elseif p.shape == "ball" then
		inst.Shape = Enum.PartType.Ball
		inst.Size = size
	else
		inst.Size = size
	end
	inst.Color = p.color
	if p.neon then
		inst.Material = Enum.Material.Neon
	elseif p.material then
		local ok, m = pcall(function() return Enum.Material[p.material] end)
		inst.Material = ok and m or Enum.Material.SmoothPlastic
	else
		inst.Material = Enum.Material.SmoothPlastic
	end
	if p.material == "Foil" then inst.Reflectance = 0.25 end
	inst.CanCollide, inst.CanQuery, inst.CanTouch, inst.Massless = false, false, false, true
	inst.CastShadow = false
	return inst
end

--- A model of hat `design` (HatDesigns.get) sitting on `top` (the CFrame
-- of the head's top centre), `scale` times the drawn size. Unanchored.
function ShopHat.build(design, top, scale)
	local model = Instance.new("Model")
	model.Name = ShopHat.NAME
	for _, p in ipairs(design) do
		local inst = part(p, scale)
		local r = p.rot or Vector3.zero
		local cf = top * CFrame.new(p.pos * scale)
			* CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		if p.shape == "cyl" then cf = cf * CFrame.Angles(0, 0, math.rad(90)) end
		inst.CFrame = cf
		inst.Parent = model
	end
	return model
end

-- The avatar's own hat accessories would poke through a shop hat: hidden
-- while one is worn (attribute ShopHatHid keeps what to give back).
local function ownHats(character)
	local out = {}
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local ok, t = pcall(function() return acc.AccessoryType end)
			local handle = acc:FindFirstChild("Handle")
			if ok and t == Enum.AccessoryType.Hat and handle and handle:IsA("BasePart") then
				table.insert(out, handle)
			end
		end
	end
	return out
end

local function hideOwnHats(character, hide)
	for _, handle in ipairs(ownHats(character)) do
		if hide and not handle:GetAttribute("ShopHatHid") then
			handle:SetAttribute("ShopHatHid", handle.Transparency)
			handle.Transparency = 1
		elseif not hide and handle:GetAttribute("ShopHatHid") ~= nil then
			handle.Transparency = handle:GetAttribute("ShopHatHid")
			handle:SetAttribute("ShopHatHid", nil)
		end
	end
end

local function headOf(character)
	local head = character and character:FindFirstChild("Head")
	return head and head:IsA("BasePart") and head or nil
end

--- Puts hat item `id` (nil / the default: none) on `character`'s head,
-- replacing the one there. Returns the model.
function ShopHat.wear(character, id)
	local head = headOf(character)
	if not head then return nil end
	local old = character:FindFirstChild(ShopHat.NAME)
	local hidden = old and old:GetAttribute("Hidden")   -- under a crafted HEAD item: stays hidden
	if old then old:Destroy() end
	local item = id and Cosmetics.get(id)
	local design = item and item.hat and HatDesigns.get(item.hat)
	hideOwnHats(character, design ~= nil)
	if not design then return nil end
	local scale = math.min(head.Size.X, head.Size.Y, head.Size.Z) / HatDesigns.HEAD
	local model = ShopHat.build(design, head.CFrame * CFrame.new(0, head.Size.Y / 2, 0), scale)
	for _, p in ipairs(model:GetChildren()) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, p
		w.Parent = p
	end
	model:SetAttribute("HatId", id)
	model.Parent = character
	if hidden then ShopHat.setHidden(character, true) end
	return model
end

--- `player`'s equipped hat on their current character. Also tells the
-- player's own client how their punch looks (attribute MoveStyle, shop
-- "move"), so FarmFx can swing it the moment F is pressed.
function ShopHat.refresh(player)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local rec = PlayerStore.get(player)
	local mv = rec and Cosmetics.equipped(rec.equipped, "move")
	pcall(function() player:SetAttribute("MoveStyle", mv and mv.style or nil) end)
	local item = rec and Cosmetics.equipped(rec.equipped, "hat")
	return ShopHat.wear(player.Character, item and item.id)
end

--- Hides (`hidden` = true) or shows the shop hat on `character`.
function ShopHat.setHidden(character, hidden)
	local model = character and character:FindFirstChild(ShopHat.NAME)
	if not model then return end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then p.Transparency = hidden and 1 or 0 end
	end
	model:SetAttribute("Hidden", hidden or nil)
end

--- Every player's hat on every character they get.
function ShopHat.start()
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			ShopHat.refresh(player)
		end)
		if player.Character then ShopHat.refresh(player) end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	-- a record that loads after the character appeared
	PlayerStore.onLoaded(function(player) ShopHat.refresh(player) end)
end

return ShopHat
