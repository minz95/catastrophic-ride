-- RiderGhost.lua
-- A player seated in a race car rides like a bot's rider (SeatedRider):
-- the avatar's parts weigh nothing and collide with nothing, so only the
-- chassis meets the world. With a real avatar a bot plane that touched the
-- player's body (not the chassis) was no car hit (RacingManager listens on
-- the chassis) but a solid wall: the car stopped dead in the lane
-- (Studio bots-sky 2026-10-28). Undone when the player leaves the seat.

local PhysicsService = game:GetService("PhysicsService")

local RiderGhost = {}

RiderGhost.GROUP = "RaceRider"

local _ready = false
local function group()
	if _ready then return true end
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(RiderGhost.GROUP) then
			PhysicsService:RegisterCollisionGroup(RiderGhost.GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(RiderGhost.GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(RiderGhost.GROUP, RiderGhost.GROUP, false)
	end)
	_ready = ok
	return ok
end

--- `on` = true: `character`'s parts massless and in the non-colliding
-- group (their old values kept as attributes); false: back as they were.
function RiderGhost.set(character, on)
	if not character then return end
	local hasGroup = group()
	for _, p in ipairs(character:GetDescendants()) do
		if p:IsA("BasePart") then
			if on and p:GetAttribute("GhostMassless") == nil then
				p:SetAttribute("GhostMassless", p.Massless)
				p:SetAttribute("GhostGroup", p.CollisionGroup)
				p.Massless = true
				if hasGroup then p.CollisionGroup = RiderGhost.GROUP end
			elseif not on and p:GetAttribute("GhostMassless") ~= nil then
				p.Massless = p:GetAttribute("GhostMassless")
				p.CollisionGroup = p:GetAttribute("GhostGroup") or "Default"
				p:SetAttribute("GhostMassless", nil)
				p:SetAttribute("GhostGroup", nil)
			end
		end
	end
	character:SetAttribute("RaceGhost", on or nil)
end

--- Keeps whoever sits in `seat` a ghost while seated.
function RiderGhost.watch(seat)
	local current
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local char = hum and hum.Parent
		if current and current ~= char then RiderGhost.set(current, false) end
		current = char
		if char then RiderGhost.set(char, true) end
	end)
end

return RiderGhost
