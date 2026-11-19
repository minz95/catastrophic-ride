-- GpCircuit.lua
-- Builds the Junk Grand Prix circuit (Shared/GpLayout) west of Auto Street:
-- grass, the road with white edges, red-and-white kerbs and gravel traps
-- where it bends, armco barriers, the pit lane with its wall and twelve
-- garages, the start / finish gantry and chequered line, a grandstand by the
-- town with a crowd, sponsor boards, and the gate at the end of Auto Street
-- (prompt GpAction = "enter", the TOP LAPS board). Everything is data from
-- GpLayout; this file only turns it into parts.
--
-- Surfaces are found by name (GpClient's ground rays): GpRoad, GpKerb,
-- GpGrass, GpGravel, GpPit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GpLayout = require(ReplicatedStorage.Shared.GpLayout)
local GpDriver = require(ReplicatedStorage.Shared.GpDriver)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)

local GpCircuit = {}
GpCircuit.NAME = "JunkGP"
GpCircuit.BARRIER = 30        -- studs from the centerline
GpCircuit.ROAD_TOP = 0.3      -- the road's top over the ground (ORIGIN.Y)

local V, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local C = Color3.fromRGB
local O = LobbyLayout.ORIGIN

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function deco(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function sign(p, lines, bg, face)
	local g = Instance.new("SurfaceGui")
	g.Name = "Sign"
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	g.LightInfluence = 0.2
	g.Parent = p
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or C(20, 20, 24)
	frame.BackgroundTransparency = bg and 0 or 1
	frame.Parent = g
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = frame
	for i, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.Name = l.name or ("Line" .. i)
		t.LayoutOrder = i
		t.Size = UDim2.fromScale(1, l.share or (1 / #lines))
		t.BackgroundTransparency = 1
		t.Text = l.text
		t.TextScaled = true
		t.Font = l.font or Enum.Font.GothamBlack
		t.TextColor3 = l.color or C(255, 255, 255)
		t.Parent = frame
	end
	return g
end

-- world CFrame of a flat piece from offset a to offset b (Y = height over ORIGIN)
local function between(ax, az, bx, bz, y)
	local a, b = O + V(ax, y, az), O + V(bx, y, bz)
	return CFrame.lookAt((a + b) / 2, b), (b - a).Magnitude
end

-- the centerline cut into runs: consecutive segments that keep their
-- heading merge into one piece (a straight is one part, a bend many)
local function runs(nodes, lateral)
	local out = {}
	local n = #nodes - 1
	local function off(i)
		local a = nodes[(i - 1) % n + 1]
		local b = nodes[i % n + 1]
		local p = nodes[(i - 2) % n + 1]
		-- the bisector normal at node i (right of travel = (-dz, dx))
		local d1x, d1z = a[1] - p[1], a[2] - p[2]
		local d2x, d2z = b[1] - a[1], b[2] - a[2]
		local l1, l2 = math.sqrt(d1x * d1x + d1z * d1z), math.sqrt(d2x * d2x + d2z * d2z)
		local tx, tz = d1x / l1 + d2x / l2, d1z / l1 + d2z / l2
		local lt = math.sqrt(tx * tx + tz * tz)
		tx, tz = tx / lt, tz / lt
		local rx, rz = -tz, tx
		-- keep the offset's width through the bend
		local cosHalf = math.max(0.5, (d1x * d2x + d1z * d2z) / (l1 * l2) * 0.5 + 0.5) ^ 0.5
		local k = lateral / cosHalf
		return a[1] + rx * k, a[2] + rz * k
	end
	local i = 1
	while i <= n do
		local j = i + 1
		local ax, az = nodes[i][1], nodes[i][2]
		local hx, hz = nodes[i + 1][1] - ax, nodes[i + 1][2] - az
		local h0 = math.atan2(hz, hx)
		while j <= n do
			local cx, cz = nodes[j + 1][1] - nodes[j][1], nodes[j + 1][2] - nodes[j][2]
			local h = math.atan2(cz, cx)
			if math.abs((h - h0 + math.pi) % (2 * math.pi) - math.pi) > 0.004 then break end
			j += 1
		end
		local x0, z0 = off(i)
		local x1, z1 = off(j)
		table.insert(out, { i = i, j = j, x0 = x0, z0 = z0, x1 = x1, z1 = z1 })
		i = j
	end
	return out
end

local function ground(m)
	local G = GpLayout.GROUND
	local w, d = G[2] - G[1], G[4] - G[3]
	local mid = O + V((G[1] + G[2]) / 2, 0, (G[3] + G[4]) / 2)
	part(m, "GpGrass", V(w, 2, d), CF(mid - V(0, 1, 0)), C(96, 160, 72), "Grass")
	deco(part(m, "GpRock", V(w - 12, 18, d - 12), CF(mid - V(0, 11, 0)), C(110, 96, 84), "Slate"))
	-- an invisible fence round the grounds: a car flung off is caught
	local H = 40
	for _, e in ipairs({ { w, G[3] }, { w, G[4] } }) do
		local p = part(m, "GpFence", V(e[1], H, 2), CF(O + V((G[1] + G[2]) / 2, H / 2, e[2])), C(255, 255, 255))
		p.Transparency = 1
	end
	local p = part(m, "GpFence", V(2, H, d), CF(O + V(G[1], H / 2, (G[3] + G[4]) / 2)), C(255, 255, 255))
	p.Transparency = 1
	-- the town side: open where the grandstand's walk is (it has its own walls)
	local S = LobbyLayout.STREET.stand
	for _, r in ipairs({ { G[3], S[3] }, { S[4], G[4] } }) do
		local f = part(m, "GpFence", V(2, H, r[2] - r[1]), CF(O + V(G[2], H / 2, (r[1] + r[2]) / 2)), C(255, 255, 255))
		f.Transparency = 1
	end
end

local function road(m)
	local nodes = GpLayout.nodes()
	local W = GpLayout.WIDTH
	local y = GpCircuit.ROAD_TOP - 0.2
	for _, r in ipairs(runs(nodes, 0)) do
		local cf, len = between(r.x0, r.z0, r.x1, r.z1, y)
		local p = part(m, "GpRoad", V(W, 0.4, len + 0.4), cf, C(58, 58, 64), "Asphalt")
		p.CastShadow = false
		-- white lines along both edges
		for _, side in ipairs({ -1, 1 }) do
			deco(part(m, "GpLine", V(0.7, 0.05, len + 0.4), cf * CF(side * (W / 2 - 0.6), 0.22, 0), C(240, 240, 240)))
		end
	end
	-- round joints at every node of a bend (no gaps between the pieces)
	local n = #nodes - 1
	local R = GpDriver.radii()
	for i = 1, n do
		if R[i] < 400 then
			local c = part(m, "GpRoad", V(0.4, W, W), CF(O + V(nodes[i][1], y, nodes[i][2])) * A(0, 0, math.pi / 2),
				C(58, 58, 64), "Asphalt")
			c.Shape = Enum.PartType.Cylinder
			c.CastShadow = false
		end
	end
end

local function kerbsAndGravel(m)
	local nodes = GpLayout.nodes()
	local n = #nodes - 1
	local R = GpDriver.radii()
	local half = GpLayout.WIDTH / 2
	local K = GpLayout.KERB
	for i = 1, n do
		local a, b = nodes[i], nodes[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local rx, rz = -dz / len, dx / len
		local r = R[i]
		if r < GpLayout.KERB_RADIUS then
			for _, side in ipairs({ -1, 1 }) do
				for k = 0, 1 do
					local f0, f1 = k / 2, (k + 1) / 2
					local lat = side * (half + K / 2)
					local ax, az = a[1] + dx * f0 + rx * lat, a[2] + dz * f0 + rz * lat
					local bx, bz = a[1] + dx * f1 + rx * lat, a[2] + dz * f1 + rz * lat
					local cf, l = between(ax, az, bx, bz, GpCircuit.ROAD_TOP - 0.1)
					local white = (i * 2 + k) % 2 == 0
					part(m, "GpKerb", V(K, 0.5, l + 0.1), cf, white and C(245, 245, 245) or C(210, 30, 35), "SmoothPlastic")
				end
			end
		end
		if r < GpLayout.GRAVEL_RADIUS then
			-- the outside of the bend: the side away from its centre
			local p = nodes[(i - 2) % n + 1]
			local cross = (a[1] - p[1]) * dz - (a[2] - p[2]) * dx
			local outside = cross < 0 and 1 or -1   -- a left bend throws you right
			local lat = outside * (half + K + (GpCircuit.BARRIER - 2 - half - K) / 2)
			local ax, az = a[1] + rx * lat, a[2] + rz * lat
			local bx, bz = b[1] + rx * lat, b[2] + rz * lat
			local cf, l = between(ax, az, bx, bz, 0.05)
			local g = part(m, "GpGravel", V(GpCircuit.BARRIER - 2 - half - K, 0.1, l + 2), cf, C(214, 190, 140), "Sand")
			g.CastShadow = false
		end
	end
end

-- true when an offset point is this close to the centerline anywhere (an
-- inner barrier over another stretch of road, or in a tight bend's inside)
local function nearRoad(x, z, d)
	local geo = GpLayout.geometry()
	return geo:project(x, z).dist < d
end

local function inPitArea(x, z)
	local P = GpLayout.PIT
	return x < -370 and x > P.garageX[2] - 4 and z > P.exitZ - 30 and z < P.entryZ + 30
end

--- The barrier pieces (offsets): { ax, az, bx, bz, k } along both sides at
-- BARRIER studs, judged along the whole piece: an end near the road is an
-- inside apex (left open, grass) or another stretch (Studio: cars cutting
-- an apex stuck on the old pieces there); none in the pit lane.
function GpCircuit.barrierPieces()
	local nodes = GpLayout.nodes()
	local D = GpCircuit.BARRIER
	local out = {}
	for _, side in ipairs({ -1, 1 }) do
		for _, r in ipairs(runs(nodes, side * D)) do
			local dx, dz = r.x1 - r.x0, r.z1 - r.z0
			local len = math.sqrt(dx * dx + dz * dz)
			local pieces = math.max(1, math.ceil(len / 24))
			for k = 0, pieces - 1 do
				local ax, az = r.x0 + dx * k / pieces, r.z0 + dz * k / pieces
				local bx, bz = r.x0 + dx * (k + 1) / pieces, r.z0 + dz * (k + 1) / pieces
				local mx, mz = (ax + bx) / 2, (az + bz) / 2
				local near = nearRoad(ax, az, D - 2) or nearRoad(bx, bz, D - 2) or nearRoad(mx, mz, D - 2)
				if not near and not inPitArea(mx, mz) and not GpLayout.inPit(mx, mz) then
					table.insert(out, { ax, az, bx, bz, k })
				end
			end
		end
	end
	return out
end

local function barriers(m)
	for _, b in ipairs(GpCircuit.barrierPieces()) do
		local cf, l = between(b[1], b[2], b[3], b[4], 1.75)
		local w = part(m, "GpBarrier", V(1.6, 3.5, l + 0.8), cf, C(190, 196, 204), "DiamondPlate")
		deco(part(m, "GpBarrierStripe", V(1.7, 0.7, l + 0.8), cf * CF(0, 0.6, 0),
			(b[5] % 2 == 0) and C(30, 80, 200) or C(240, 240, 240)))
		w.CastShadow = false
	end
end

local function pits(m)
	local P = GpLayout.PIT
	local path = GpLayout.pitPath()
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local cf, l = between(a.X, a.Z, b.X, b.Z, GpCircuit.ROAD_TOP - 0.25)
		local w = (i == 1 or i == #path - 1) and 13 or P.width
		local p = part(m, "GpPit", V(w, 0.4, l + 8), cf, C(78, 78, 86), "Asphalt")
		p.CastShadow = false
	end
	-- the lane's dividing line and limiter boards
	local zc = (P.z0 + P.z1) / 2
	deco(part(m, "GpLine", V(0.5, 0.05, P.z1 - P.z0), CF(O + V(P.x + 1, GpCircuit.ROAD_TOP + 0.02, zc)), C(240, 240, 240)))
	for _, z in ipairs({ P.z1 + 6, P.z0 - 6 }) do
		local board = part(m, "GpPitBoard", V(8, 4, 0.4), CF(O + V(P.x + 8, 7, z)) * A(0, z > 0 and 0 or math.pi, 0),
			C(255, 255, 255))
		deco(board)
		sign(board, { { text = z > 0 and "PIT LIMIT " .. math.floor(P.limit * 2.1) or "END LIMIT", color = C(200, 20, 20) } }, C(255, 255, 255))
		sign(board, { { text = z > 0 and "PIT LIMIT " .. math.floor(P.limit * 2.1) or "END LIMIT", color = C(200, 20, 20) } }, C(255, 255, 255), Enum.NormalId.Back)
	end
	-- the pit wall (with a crew stand on it)
	local wz = P.wallZ
	part(m, "GpPitWall", V(1.4, 3.2, wz[2] - wz[1]), CF(O + V(P.wallX, 1.6, (wz[1] + wz[2]) / 2)), C(225, 225, 225), "Concrete")
	deco(part(m, "GpPitStand", V(4, 6, 40), CF(O + V(P.wallX - 3, 3, 10)), C(40, 40, 46), "Metal"))
	-- the garages
	local TEAM = { C(220, 40, 40), C(40, 90, 220), C(250, 160, 30), C(30, 170, 90), C(150, 60, 200), C(30, 180, 200),
		C(240, 240, 240), C(250, 120, 170), C(120, 120, 120), C(230, 210, 40), C(20, 30, 70), C(160, 90, 40) }
	local gx = P.garageX
	local depth = math.abs(gx[2] - gx[1])
	local cx = (gx[1] + gx[2]) / 2
	for k = 1, P.boxes do
		local stop, garage = GpLayout.box(k)
		local z = garage.Z
		local team = TEAM[(k - 1) % #TEAM + 1]
		local box = Instance.new("Model")
		box.Name = "GpGarage_" .. k
		box:SetAttribute("Box", k)
		part(box, "Floor", V(depth, 0.4, 20), CF(O + V(cx, 0.1, z)), C(70, 72, 80), "SmoothPlastic")
		part(box, "Back", V(1, 12, 21), CF(O + V(gx[2], 6, z)), C(235, 235, 240), "SmoothPlastic")
		for _, sz in ipairs({ -10.5, 10.5 }) do
			part(box, "Side", V(depth, 12, 1), CF(O + V(cx, 6, z + sz)), team, "SmoothPlastic")
		end
		part(box, "Roof", V(depth + 2, 1, 22), CF(O + V(cx + 1, 12.5, z)), C(50, 50, 56), "Metal")
		local header = part(box, "Header", V(1, 3, 20), CF(O + V(gx[1] + 0.5, 10.5, z)) * A(0, math.rad(-90), 0), team, "SmoothPlastic")
		sign(header, { { text = "BOX " .. k, color = C(255, 255, 255) } }, team)
		-- tyre stacks and a tool cart
		for j = 0, 2 do
			local t = part(box, "Tyres", V(2.2, 2.4, 2.2), CF(O + V(gx[2] + 2, 1.3 + j * 0.01, z - 7 + j * 3)), C(25, 25, 28), "SmoothPlastic")
			deco(t)
		end
		deco(part(box, "Cart", V(2, 2.4, 3), CF(O + V(gx[2] + 3, 1.2, z + 7)), team, "Metal"))
		-- the stop mark on the lane
		deco(part(box, "Mark", V(6, 0.05, 9), CF(stop + O + V(0, GpCircuit.ROAD_TOP + 0.02, 0)), C(240, 210, 40), "SmoothPlastic")).Transparency = 0.35
		box.Parent = m
	end
end

local function gantry(m)
	local z = GpLayout.LINE_Z
	local half = GpLayout.WIDTH / 2
	-- the chequered line
	local tiles = 14
	for k = 0, tiles - 1 do
		for row = 0, 1 do
			local x = -360 - half + (k + 0.5) * (GpLayout.WIDTH / tiles)
			deco(part(m, "GpChequer", V(GpLayout.WIDTH / tiles, 0.05, 1.5),
				CF(O + V(x, GpCircuit.ROAD_TOP + 0.03, z + (row - 0.5) * 1.5)),
				((k + row) % 2 == 0) and C(250, 250, 250) or C(15, 15, 15)))
		end
	end
	for _, x in ipairs({ -360 - half - 4, -360 + half + 4 }) do
		part(m, "GpGantryPost", V(1.6, 18, 1.6), CF(O + V(x, 9, z)), C(30, 30, 34), "Metal")
	end
	local beam = part(m, "GpGantry", V(GpLayout.WIDTH + 10, 3.5, 2), CF(O + V(-360, 16.5, z)), C(25, 25, 30), "Metal")
	sign(beam, { { text = "JUNK GRAND PRIX", color = C(255, 255, 255) } }, C(25, 25, 30), Enum.NormalId.Back)
	sign(beam, { { text = "JUNK GRAND PRIX", color = C(255, 255, 255) } }, C(25, 25, 30), Enum.NormalId.Front)
	-- the five start lights, facing the cars coming up the straight (from +Z)
	for k = 1, 5 do
		local pod = part(m, "GpLightPod", V(2.2, 3, 1), CF(O + V(-360 - 8 + (k - 1) * 4, 13.2, z + 1.4)), C(15, 15, 15), "Metal")
		deco(pod)
		local lamp = part(m, "GpLight" .. k, V(1.4, 1.4, 0.3), CF(O + V(-360 - 8 + (k - 1) * 4, 13.2, z + 1.95)), C(60, 10, 10), "Neon")
		deco(lamp)
	end
end

-- the grandstand: tiers rising from the catch fence towards the town, seats
-- anyone may sit in (and a painted crowd between them), a roof with the
-- name; behind it a walk from the gap in the lot's west wall. Invisible
-- walls close the walk; the catch fence keeps walkers off the track.
GpCircuit.SEAT_STEP = 6
local function grandstand(m)
	local G = GpLayout.GRANDSTAND
	local x0, x1 = G.x[1], G.x[2]
	local z0, z1 = G.z[1], G.z[2]
	local len = z1 - z0
	local tiers = 6
	local step = (x1 - x0) / tiers
	local CROWD = { C(230, 60, 60), C(250, 200, 60), C(60, 120, 230), C(240, 240, 240), C(60, 180, 90), C(250, 140, 40), C(170, 80, 200) }
	local seed = 7
	local stand = Instance.new("Model")
	stand.Name = "GpGrandstand"
	for t = 0, tiers - 1 do
		local x = x0 + (t + 0.5) * step
		local h = 1 + t * 1.1
		part(stand, "GpStand", V(step, h, len), CF(O + V(x, h / 2, (z0 + z1) / 2)), C(200, 200, 205), "Concrete")
		for k = 0, math.floor(len / GpCircuit.SEAT_STEP) - 1 do
			local z = z0 + GpCircuit.SEAT_STEP * (k + 0.5)
			seed = (seed * 1103515245 + 12345) % 2147483648
			if (k + t) % 3 == 0 then
				local col = CROWD[seed % #CROWD + 1]
				deco(part(stand, "GpCrowd", V(1.6, 3, 4.5), CF(O + V(x, h + 1.5, z)), col, "SmoothPlastic"))
			else
				local seat = Instance.new("Seat")
				seat.Name = "GpSeat"
				seat.Anchored = true
				seat.Size = V(2, 0.6, 2)
				seat.CFrame = CFrame.lookAt(O + V(x, h + 0.3, z), O + V(x - 10, h + 0.3, z))
				seat.Color = (t % 2 == 0) and C(200, 30, 40) or C(30, 30, 36)
				seat.Material = Enum.Material.SmoothPlastic
				seat.TopSurface = Enum.SurfaceType.Smooth
				seat.Parent = stand
			end
		end
	end
	-- the roof, and the name over it facing the track and the town
	local hTop = 1 + tiers * 1.1 + 10
	for _, z in ipairs({ z0 + 2, z1 - 2, (z0 + z1) / 2 }) do
		deco(part(stand, "GpStandPost", V(1, hTop, 1), CF(O + V(x1 - 1, hTop / 2, z)), C(60, 60, 66), "Metal"))
	end
	deco(part(stand, "GpStandRoof", V(x1 - x0 + 4, 0.8, len + 4), CF(O + V((x0 + x1) / 2, hTop, (z0 + z1) / 2)), C(30, 30, 36), "Metal"))
	local banner = deco(part(stand, "GpStandSign", V(1, 6, 90), CF(O + V(x0 - 0.5, hTop + 3.5, (z0 + z1) / 2)), C(200, 20, 30), "SmoothPlastic"))
	sign(banner, { { text = "🏁 JUNK GRAND PRIX", color = C(255, 255, 255) } }, C(200, 20, 30), Enum.NormalId.Left)
	sign(banner, { { text = "🏁 JUNK GRAND PRIX", color = C(255, 255, 255) } }, C(200, 20, 30), Enum.NormalId.Right)
	-- the walk behind it (floor) and the walls round the walk
	local S = LobbyLayout.STREET.stand
	part(stand, "GpWalk", V(S[2] - x1, 0.2, S[4] - S[3]), CF(O + V((x1 + S[2]) / 2, 0.1, (S[3] + S[4]) / 2)), C(150, 150, 156), "Concrete")
	local function wall(ax, az, bx, bz, h, visible)
		local cf, l = between(ax, az, bx, bz, h / 2)
		local w = part(stand, "GpStandWall", V(1.2, h, l), cf, C(255, 255, 255))
		w.Transparency = visible and 0.85 or 1
		w.CanQuery = false
		return w
	end
	local lot = LobbyLayout.STREET.lot
	wall(S[2] + 0.6, S[3], S[2] + 0.6, lot[3], 14)
	wall(S[2] + 0.6, lot[4], S[2] + 0.6, S[4], 14)
	wall(S[1], S[3], S[2], S[3], 14)
	wall(S[1], S[4], S[2], S[4], 14)
	-- the catch fence: tall, see-through, posts every 12 studs
	local F = GpLayout.CATCH_FENCE
	wall(F, S[3], F, S[4], 30, true)
	for z = S[3], S[4], 12 do
		deco(part(stand, "GpFencePost", V(0.5, 12, 0.5), CF(O + V(F, 6, z)), C(90, 90, 96), "Metal"))
	end
	stand.Parent = m
end

-- sponsor boards on the outside of the straights (town names)
GpCircuit.SPONSORS = { "JUNK MOTORS", "HONEST HANK'S", "BOX BOX", "TURBO TOM'S TYRES", "PENNY'S PAINTS",
	"LUCKY LOT", "GREASE GRAN", "RUSTY & SONS" }
local function boards(m)
	local spots = {   -- offset, facing yaw (deg)
		{ -470, -296, 0 }, { -960, -296, 0 }, { -1162, 0, 90 }, { -1162, 160, 90 },
		{ -620, 316, 180 }, { -440, 320, 180 }, { -1000, 316, 180 }, { -760, -60, 0 },
	}
	for i, s in ipairs(spots) do
		local b = deco(part(m, "GpBoard", V(26, 4, 0.5), CF(O + V(s[1], 4.5, s[2])) * A(0, math.rad(s[3]), 0), C(255, 255, 255)))
		local name = GpCircuit.SPONSORS[(i - 1) % #GpCircuit.SPONSORS + 1]
		local bg = (i % 2 == 0) and C(20, 20, 26) or C(200, 30, 40)
		sign(b, { { text = name, color = C(255, 255, 255) } }, bg, Enum.NormalId.Front)
		sign(b, { { text = name, color = C(255, 255, 255) } }, bg, Enum.NormalId.Back)
	end
end

-- the gate at the end of Auto Street: an arch, the prompt, the TOP LAPS board
local function gate(m)
	local E = GpLayout.ENTRANCE
	local base = O + E
	for _, z in ipairs({ -10, 10 }) do
		part(m, "GpGatePost", V(2, 16, 2), CF(base + V(0, 8, z)), C(30, 30, 34), "Metal")
	end
	local top = part(m, "GpGateSign", V(1.5, 4.5, 24), CF(base + V(0, 17, 0)), C(200, 20, 30), "SmoothPlastic")
	sign(top, { { text = "🏁 JUNK GRAND PRIX", color = C(255, 255, 255), share = 0.62 },
		{ text = "RACING EXPERIENCE · OWN A CAR? RACE IT", color = C(255, 230, 160), share = 0.38, font = Enum.Font.GothamBold } },
		C(200, 20, 30), Enum.NormalId.Right)
	-- chequered flags on the posts
	for _, z in ipairs({ -10, 10 }) do
		deco(part(m, "GpFlag", V(0.2, 3, 4), CF(base + V(0, 13, z + (z > 0 and -3 or 3))), C(15, 15, 15)))
	end
	-- the desk with the prompt
	-- (beside the way through: the walk to the grandstand passes between the posts)
	local desk = part(m, "GpDesk", V(8, 3.4, 3), CF(base + V(-2, 1.7, -14)), C(30, 30, 34), "Metal")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "GpPrompt"
	pp.ActionText = "Race your car"
	pp.ObjectText = "Junk Grand Prix"
	pp.HoldDuration = 0.3
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("GpAction", "enter")
	pp.Parent = desk
	-- TOP LAPS board (GpManager fills it: GpCircuit.setBoard)
	local board = part(m, "GpTopLaps", V(1, 12, 10), CF(base + V(-6, 7, -26)), C(15, 15, 20), "SmoothPlastic")
	local g = Instance.new("SurfaceGui")
	g.Name = "Board"
	g.Face = Enum.NormalId.Right
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.LightInfluence = 0
	g.Parent = board
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = g
	local head = Instance.new("TextLabel")
	head.Name = "Head"
	head.LayoutOrder = 0
	head.Size = UDim2.fromScale(1, 0.14)
	head.BackgroundColor3 = C(200, 20, 30)
	head.Text = "TOP LAPS"
	head.TextScaled = true
	head.Font = Enum.Font.GothamBlack
	head.TextColor3 = C(255, 255, 255)
	head.Parent = g
	for k = 1, 8 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. k
		row.LayoutOrder = k
		row.Size = UDim2.fromScale(1, 0.1)
		row.BackgroundTransparency = 1
		row.Text = ""
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = C(255, 255, 255)
		row.Parent = g
	end
end

--- Writes the board's rows: list of { name, time, car } (GpTiming.ranked).
function GpCircuit.setBoard(circuit, list, format)
	local board = circuit and circuit:FindFirstChild("GpTopLaps", true)
	local g = board and board:FindFirstChild("Board")
	if not g then return end
	for k = 1, 8 do
		local row = g:FindFirstChild("Row" .. k)
		local e = list[k]
		if row then
			row.Text = e and string.format("  %d. %s  %s  (%s)", k, format(e.time), e.name, e.car or "") or ""
		end
	end
end

function GpCircuit.build(parent)
	local old = parent:FindFirstChild(GpCircuit.NAME)
	if old then old:Destroy() end
	local m = Instance.new("Model")
	m.Name = GpCircuit.NAME
	ground(m)
	road(m)
	kerbsAndGravel(m)
	barriers(m)
	pits(m)
	gantry(m)
	grandstand(m)
	boards(m)
	gate(m)
	local cars = Instance.new("Folder")
	cars.Name = "Cars"
	cars.Parent = m
	m.Parent = parent
	return m
end

return GpCircuit
