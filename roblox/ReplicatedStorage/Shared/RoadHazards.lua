-- RoadHazards.lua
-- What a driver sees on the road ahead: falling-log markers and logs
-- (workspace.Hazards) and obstacle drops (workspace.TrackDrops), as
-- { x, z, half } for Autopilot (it steers to the open side). Used by the
-- harness bot clients (BotDriver) and the server race bots (RaceBots).

local Constants = require(script.Parent.Constants)

local RoadHazards = {}

RoadHazards.SEE_RANGE = 260

--- Every hazard part in the world now (scan once, filter per car with `near`).
function RoadHazards.all()
	local out = {}
	local hz = workspace:FindFirstChild("Hazards")
	if hz then
		for _, d in ipairs(hz:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "FallingLog" or d.Name == "LogWarning") then table.insert(out, d) end
		end
	end
	local drops = workspace:FindFirstChild("TrackDrops")
	if drops then
		for _, d in ipairs(drops:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "DropHazard" and d.CanCollide then table.insert(out, d) end
		end
	end
	return out
end

--- The parts of `parts` a driver at `pos` sees, as Autopilot hazards.
function RoadHazards.near(parts, pos)
	local out = {}
	for _, part in ipairs(parts) do
		if part.Parent and (part.Position - pos).Magnitude <= RoadHazards.SEE_RANGE
			and math.abs(part.Position.Y - pos.Y) <= 12 then   -- not another layer of the road
			local half = math.max(part.Size.X, part.Size.Z) / 2
			if part.Name == "LogWarning" then half = Constants.HAZARDS.LOG_SIZE[1] / 2 end
			table.insert(out, { x = part.Position.X, z = part.Position.Z, half = half })
		end
	end
	return out
end

function RoadHazards.visible(pos)
	return RoadHazards.near(RoadHazards.all(), pos)
end

return RoadHazards
