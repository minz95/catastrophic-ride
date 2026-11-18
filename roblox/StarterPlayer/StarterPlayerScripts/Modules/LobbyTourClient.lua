-- LobbyTourClient.lua
-- The walker of TestHarness/LobbyTour: walks to every stop of Junk Town
-- with the Humanoid (real physics, the worn ride-on round the waist) and
-- reports each one (tour_stop); in the hub it then presses ▶ PLAY and
-- reports what the lobby screen shows while the pad counts down and the
-- teleport fails in Studio (tour_hub); tour_done ends the match.

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyTourClient = {}

function LobbyTourClient.run(report)
	local LocalPlayer = Players.LocalPlayer
	local cfg = HttpService:JSONDecode(LocalPlayer:GetAttribute("LobbyTour"))
	local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

	local function parts(wait)
		local c = LocalPlayer.Character
		if wait then   -- a character being (re)loaded: wait for it
			local t0 = os.clock()
			while (not c or not c:FindFirstChild("HumanoidRootPart") or not c:FindFirstChildOfClass("Humanoid"))
				and os.clock() - t0 < 15 do
				task.wait(0.2)
				c = LocalPlayer.Character
			end
		end
		return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
	end
	parts(true)
	task.wait(2)

	local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end

	-- like a player: round things (PathfindingService), jumping where the path says
	local PathfindingService = game:GetService("PathfindingService")
	local function walkTo(hum, target, deadline)
		local _, root = parts()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
		local ok = pcall(function() path:ComputeAsync(root.Position, target) end)
		local status = ok and path.Status.Name or "error"
		local points = (ok and path.Status == Enum.PathStatus.Success) and path:GetWaypoints() or { { Position = target } }
		for _, w in ipairs(points) do
			if os.clock() > deadline then break end
			if w.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
			hum:MoveTo(w.Position)
			local t0 = os.clock()
			while os.clock() - t0 < 3 and os.clock() < deadline do
				task.wait(0.1)
				_, root = parts()
				if not root or flat(root.Position, w.Position) < 2 then break end
			end
		end
		return status
	end

	for i, s in ipairs(cfg.stops) do
		local target = Vector3.new(s.x, s.y or cfg.y, s.z)
		local hum, root = parts(true)
		local t0 = os.clock()
		local deadline = t0 + cfg.timeout
		local minY = math.huge
		local reached, tries, status = false, 0, nil
		local watch = task.spawn(function()
			while true do
				local _, r = parts()
				if r then minY = math.min(minY, r.Position.Y) end
				task.wait(0.2)
			end
		end)
		while hum and os.clock() < deadline do
			tries += 1
			status = walkTo(hum, target, deadline)
			hum, root = parts()
			if root and flat(root.Position, target) < 3 then reached = true break end
		end
		task.cancel(watch)
		hum, root = parts()
		-- not there: what holds the walker (a seat, a part it is inside)
		local near = nil
		if not reached and root then
			near = {}
			local op = OverlapParams.new()
			op.FilterDescendantsInstances = { LocalPlayer.Character }
			op.FilterType = Enum.RaycastFilterType.Exclude
			for _, p in ipairs(workspace:GetPartBoundsInRadius(root.Position, 3.5, op)) do
				if p.CanCollide and #near < 8 then
					local m = p:FindFirstAncestorWhichIsA("Model")
					table.insert(near, p.Name .. "@" .. (m and m.Name or "?"))
				end
			end
			near.sit = hum and hum.Sit or nil
			near.seat = hum and hum.SeatPart and hum.SeatPart:GetFullName() or nil
			near.state = hum and hum:GetState().Name or nil
		end
		report("tour_stop", { i = i, name = s.name, reached = reached, secs = math.floor((os.clock() - t0) * 10) / 10,
			left = root and math.floor(flat(root.Position, target) * 10) / 10 or -1, path = status,
			at = root and { math.floor(root.Position.X), math.floor(root.Position.Y), math.floor(root.Position.Z) } or nil,
			minY = minY < math.huge and math.floor((minY - cfg.y) * 10) / 10 or nil, jumps = tries - 1, near = near })
	end

	if cfg.hub then
		local travel = {}
		RemoteEvents.TravelUpdate.OnClientEvent:Connect(function(m)
			table.insert(travel, type(m) == "table" and { kind = m.kind, text = m.text } or tostring(m))
		end)
		local res = RemoteEvents.PlaceAction:InvokeServer("play")
		local seen = {}
		local ui = nil   -- the ScreenGui, not the LocalScript of the same name
		for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
			if g.Name == "LobbyUI" and g:IsA("ScreenGui") then ui = g end
		end
		for k = 1, 14 do
			task.wait(1)
			local status = ui and ui:FindFirstChild("Status", true)
			local btn = ui and ui:FindFirstChild("Travel", true)
			local pill = ui and ui:FindFirstChild("BiomePill", true)
			table.insert(seen, { t = k, pad = LocalPlayer:GetAttribute("DepartPad"), status = status and status.Text,
				button = btn and btn.Visible and btn.Text or nil, pill = pill and pill.Visible,
				buttonBox = btn and { btn.AbsolutePosition.X, btn.AbsolutePosition.Y, btn.AbsoluteSize.X, btn.AbsoluteSize.Y } })
		end
		report("tour_hub", { play = res, travel = travel, seen = seen, mode = ReplicatedStorage:GetAttribute("PlaceMode") })
	end
	report("tour_done", {})
end

return LobbyTourClient
