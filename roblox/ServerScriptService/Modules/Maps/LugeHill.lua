-- LugeHill.lua
-- Builds the Alpine Luge (Shared/LugeLayout) north of Junk Motors: a grassy
-- hill, the concrete trough with its lips (high, red and white banked walls
-- outside the hairpins), embankments where it crosses the slope and wooden
-- trestles where it stands off the ground, the chairlift (towers, cable,
-- chairs the clients swing round: LiftChairs), the top station with the
-- start gate and its bell, the finish arch and hay bales, the bottom
-- station, pines, flowers and lanterns, and the ticket booth in town
-- (prompt LugeAction = "enter"). Everything is data from LugeLayout.
--
-- Surfaces by name (LugeClient's ground rays): LugeTrough (the floor and
-- its joints), LugeGrass (the hill, the embankments).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LugeLayout = require(ReplicatedStorage.Shared.LugeLayout)
local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)

local LugeHill = {}
LugeHill.NAME = "AlpineLuge"
LugeHill.LIP = { LOW = 0.8, HIGH = 2.4, THICK = 0.6 }
LugeHill.CHAIRS = 18

local V, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local C = Color3.fromRGB
local O = LobbyLayout.ORIGIN
local W = Constants.LUGE.WIDTH

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new(shape == "wedge" and "WedgePart" or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material[material or "SmoothPlastic"]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "ball" then p.Shape = Enum.PartType.Ball end
	if shape == "cyl" then p.Shape = Enum.PartType.Cylinder end
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
	g.PixelsPerStud = 24
	g.LightInfluence = 0.2
	g.Parent = p
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or C(30, 30, 34)
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

local function storeModel(m, key, cf, height, solid)
	local ok, LobbyHub = pcall(function() return require(ServerScriptService.Modules.Maps.LobbyHub) end)
	if not ok or not LobbyHub._storeModel then return nil end
	local ok2, model = pcall(LobbyHub._storeModel, m, key, cf, height, solid)
	return ok2 and model or nil
end

local function world(x, y, z) return O + V(x, y, z) end

-- ── The ground ───────────────────────────────────────────────────────────────

local GRASS = C(104, 168, 76)

local function ground(m)
	local R = LugeLayout.REGION
	local H = LugeLayout.HILL
	local w, d = R[2] - R[1], R[4] - R[3]
	local cx, cz = (R[1] + R[2]) / 2, (R[3] + R[4]) / 2
	part(m, "LugeGrass", V(w, 2, d), CF(world(cx, -1, cz)), GRASS, "Grass")
	deco(part(m, "LugeRock", V(w - 10, 16, d - 10), CF(world(cx, -10, cz)), C(112, 98, 86), "Slate"))
	-- the slope: a wedge rising north (its tall face at the back, +Z local:
	-- turned so the back is north)
	local depth = H.zBottom - H.zTop
	local mid = world(cx, H.top / 2, (H.zBottom + H.zTop) / 2)
	part(m, "LugeGrass", V(w, H.top, depth), CFrame.lookAt(mid, mid + V(0, 0, 1)), GRASS, "Grass", "wedge")
	-- the top: a plateau north of the slope
	local pd = H.zTop - R[3]
	part(m, "LugeGrass", V(w, H.top, pd), CF(world(cx, H.top / 2, R[3] + pd / 2)), GRASS, "Grass")
	-- rock on the hill's west and east faces (the wedge's sides would be grass cliffs)
	for _, x in ipairs({ R[1] - 0.6, R[2] + 0.6 }) do
		deco(part(m, "LugeCliff", V(1, H.top, depth), CFrame.lookAt(world(x, H.top / 2, (H.zBottom + H.zTop) / 2),
			world(x, H.top / 2, (H.zBottom + H.zTop) / 2 + 1)), C(128, 116, 102), "Slate", "wedge"))
		deco(part(m, "LugeCliff", V(1, H.top, pd), CF(world(x, H.top / 2, R[3] + pd / 2)), C(128, 116, 102), "Slate"))
	end
	deco(part(m, "LugeCliff", V(w + 2, H.top, 1), CF(world(cx, H.top / 2, R[3] - 0.6)), C(128, 116, 102), "Slate"))
	-- invisible walls round the grounds: a cart over a lip stays on the hill
	local HT = H.top + 60
	for _, e in ipairs({ { V(w, HT, 2), world(cx, HT / 2, R[3]) }, { V(w, HT, 2), world(cx, HT / 2, R[4]) },
		{ V(2, HT, d), world(R[1], HT / 2, cz) }, { V(2, HT, d), world(R[2], HT / 2, cz) } }) do
		local p = part(m, "LugeFence", e[1], CF(e[2]), C(255, 255, 255))
		p.Transparency = 1
		p.CanQuery = false
	end
end

-- ── The trough ───────────────────────────────────────────────────────────────

-- the centerline cut into runs: consecutive segments of one heading and
-- one grade are one piece
local function runs()
	local N = LugeLayout.nodes()
	local out = {}
	local i = 1
	local function dir(k)
		local a, b = N[k], N[k + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		return math.atan2(dz, dx), (b[3] - a[3]) / math.max(len, 1e-6)
	end
	while i < #N do
		local h0, g0 = dir(i)
		local j = i + 1
		while j < #N do
			local h, g = dir(j)
			if math.abs((h - h0 + math.pi) % (2 * math.pi) - math.pi) > 0.004 or math.abs(g - g0) > 0.003 then break end
			j += 1
		end
		table.insert(out, { i = i, j = j })
		i = j
	end
	return out
end

local function trough(m)
	local N = LugeLayout.nodes()
	local K = LugeLayout.curves()
	local L = LugeHill.LIP
	local floorC, lipC = C(200, 205, 212), C(232, 232, 236)
	local stripe = { C(220, 40, 40), C(245, 245, 245) }
	for k, r in ipairs(runs()) do
		local a, b = N[r.i], N[r.j]
		local pa, pb = world(a[1], a[3], a[2]), world(b[1], b[3], b[2])
		local len = (pb - pa).Magnitude
		local cf = CFrame.lookAt((pa + pb) / 2, pb)
		-- the floor (its top on the line between the nodes)
		local f = part(m, "LugeTrough", V(W, 0.6, len + 0.3), cf * CF(0, -0.3, 0), floorC, "Concrete")
		f.CastShadow = false
		-- a blue line down the middle
		deco(part(m, "LugeLine", V(0.35, 0.05, len + 0.3), cf * CF(0, 0.02, 0), C(70, 130, 220)))
		-- the lips: high and striped outside a hairpin
		local mid = (r.i + r.j) // 2
		local curve = K[mid] or 0
		local stretch = 1 + (W / 2) * math.abs(curve)
		for _, side in ipairs({ -1, 1 }) do
			local high = LugeLayout.highLip(side, curve)
			local h = high and L.HIGH or L.LOW
			local lip = part(m, high and "LugeWall" or "LugeLip", V(L.THICK, h, len * stretch + 0.4),
				cf * CF(side * (W / 2 + L.THICK / 2), h / 2 - 0.3, 0), high and stripe[k % 2 + 1] or lipC, high and "SmoothPlastic" or "Concrete")
			deco(lip)
			lip.CastShadow = true
		end
	end
	-- round joints at the bends (no gaps between the pieces)
	for i = 2, #N - 1 do
		if math.abs(K[i] or 0) > 0.01 then
			local a, b = N[i - 1], N[i + 1]
			local p = world(N[i][1], N[i][3], N[i][2])
			local dir = world(b[1], b[3], b[2]) - world(a[1], a[3], a[2])
			local cf = CFrame.lookAt(p, p + dir) * CF(0, -0.3, 0) * A(0, 0, math.pi / 2)
			local j = part(m, "LugeTrough", V(0.6, W, W), cf, floorC, "Concrete", "cyl")
			j.CastShadow = false
		end
	end
end

-- embankments where the trough crosses the slope (its lower side), wooden
-- trestles where it stands off the ground
local function supports(m)
	local N = LugeLayout.nodes()
	local reach = W / 2 + LugeHill.LIP.THICK
	for k, r in ipairs(runs()) do
		local a, b = N[r.i], N[r.j]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 then continue end
		local ux, uz = dx / len, dz / len
		local rx, rz = -uz, ux                       -- right of travel
		local mx, mz, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
		local gl = LugeLayout.ground(mz - rz * reach)
		local gr = LugeLayout.ground(mz + rz * reach)
		local gc = LugeLayout.ground(mz)
		local low = math.min(gl, gr)
		local side = gl < gr and -1 or 1
		local drop = my - low
		if drop > 0.6 and drop <= 5 and math.abs(gl - gr) > 0.4 then
			-- an embankment on the low side: a wedge from the lip down to the grass
			local D = math.max(4, drop * 2)
			local out = V(rx * side, 0, rz * side)
			local base = world(mx, 0, mz) + out * (reach + D / 2)
			local h = drop + 1.5
			local pos = V(base.X, O.Y + my - h / 2, base.Z)
			local xv = (world(b[1], b[3], b[2]) - world(a[1], a[3], a[2])).Unit
			local zv = -out
			local yv = zv:Cross(xv)
			if yv.Y < 0 then xv = -xv yv = zv:Cross(xv) end
			local wedge = part(m, "LugeGrass", V(len + 0.6, h, D), CFrame.fromMatrix(pos, xv, yv, zv), GRASS, "Grass", "wedge")
			wedge.CastShadow = false
		elseif my - gc > 1.2 then
			-- trestles: posts every few studs, a beam across under the floor
			local steps = math.max(1, math.floor(len / 6))
			for s = 0, steps do
				local f = s / steps
				local x, z = a[1] + dx * f, a[2] + dz * f
				local y = a[3] + (b[3] - a[3]) * f
				for _, sd in ipairs({ -1, 1 }) do
					local px, pz = x + rx * sd * (W / 2 - 0.5), z + rz * sd * (W / 2 - 0.5)
					local g = LugeLayout.ground(pz) - 1
					local h = y - 0.6 - g
					if h > 0.5 then
						part(m, "LugePost", V(0.8, h, 0.8), CF(world(px, g + h / 2, pz)), C(120, 84, 52), "WoodPlanks")
					end
				end
				deco(part(m, "LugeBeam", V(W, 0.6, 0.8), CFrame.lookAt(world(x, y - 0.9, z), world(x + ux, y - 0.9, z + uz)),
					C(110, 76, 46), "WoodPlanks"))
			end
		end
	end
end

-- ── Start, finish, stations ──────────────────────────────────────────────────

local function stations(m)
	local geo = LugeLayout.geometry()
	-- the start gate: two posts, a red and white bar over the trough, the bell
	local s0 = 7
	local x, z, dx, dz = geo:pointAt(s0)
	local y = geo:heightAt(s0)
	local rx, rz = -dz, dx
	for _, sd in ipairs({ -1, 1 }) do
		part(m, "LugeGatePost", V(0.8, 9, 0.8), CF(world(x + rx * sd * (W / 2 + 1.2), y + 4.5, z + rz * sd * (W / 2 + 1.2))),
			C(70, 70, 76), "Metal")
	end
	local bar = deco(part(m, "LugeStartBar", V(W + 3.6, 0.6, 0.6), CFrame.lookAt(world(x, y + 8.6, z), world(x + rx, y + 8.6, z + rz))
		* A(0, math.pi / 2, 0), C(220, 40, 40)))
	local banner = deco(part(m, "LugeStartBanner", V(W + 2, 2.4, 0.3), CFrame.lookAt(world(x, y + 10.4, z), world(x - dx, y + 10.4, z - dz)),
		C(250, 245, 230)))
	sign(banner, { { text = "🛷 START", color = C(200, 30, 30) } }, C(250, 245, 230), Enum.NormalId.Front)
	local bx, bz = x + rx * (W / 2 + 3.2), z + rz * (W / 2 + 3.2)
	part(m, "LugeBellPost", V(0.5, 7, 0.5), CF(world(bx, y + 3.5, bz)), C(120, 84, 52), "Wood")
	part(m, "LugeBell", V(1.6, 1.6, 1.6), CF(world(bx, y + 6.4, bz)), C(230, 190, 60), "Metal", "ball")
	-- the top station: a cabin by the lift, its deck to the gate
	local T = LugeLayout.TOP_STATION
	local H = LugeLayout.HILL.top
	local tcx, tcz = (T[1] + T[2]) / 2, (T[3] + T[4]) / 2
	part(m, "LugeDeck", V(T[2] - T[1], 1, T[4] - T[3]), CF(world(tcx, H + 0.5, tcz)), C(150, 110, 70), "WoodPlanks")
	local cabin = part(m, "LugeCabin", V(14, 9, 10), CF(world(T[2] - 9, H + 5.5, T[3] + 7)), C(170, 110, 70), "WoodPlanks")
	part(m, "LugeRoof", V(16, 1, 13), CF(world(T[2] - 9, H + 10.5, T[3] + 7)) * A(0, 0, math.rad(6)), C(160, 50, 40), "Slate")
	sign(cabin, { { text = "ALPINE LUGE", color = C(255, 245, 220), share = 0.6 }, { text = "TOP STATION · 1,400 FT", color = C(255, 220, 150),
		share = 0.4, font = Enum.Font.GothamBold } }, C(120, 70, 40), Enum.NormalId.Back)
	-- the finish: an arch over the trough, then hay bales at the run-out's end
	local fs = LugeLayout.finishS()
	local fx, fz, fdx, fdz = geo:pointAt(fs)
	local fy = geo:heightAt(fs)
	local frx, frz = -fdz, fdx
	for _, sd in ipairs({ -1, 1 }) do
		part(m, "LugeArchPost", V(1, 10, 1), CF(world(fx + frx * sd * (W / 2 + 1.5), fy + 5, fz + frz * sd * (W / 2 + 1.5))),
			C(40, 40, 46), "Metal")
	end
	local arch = deco(part(m, "LugeFinish", V(W + 4, 2.6, 0.4), CFrame.lookAt(world(fx, fy + 10.5, fz), world(fx - fdx, fy + 10.5, fz - fdz)),
		C(20, 20, 24)))
	sign(arch, { { text = "🏁 FINISH", color = C(255, 255, 255) } }, C(20, 20, 24), Enum.NormalId.Front)
	-- chequered strip on the floor
	for k = 0, 5 do
		local off = -W / 2 + W / 12 + k * W / 6
		deco(part(m, "LugeChequer", V(W / 6, 0.05, 1.2), CFrame.lookAt(world(fx + frx * off, fy + 0.03, fz + frz * off),
			world(fx + frx * off + fdx, fy + 0.03, fz + frz * off + fdz)), k % 2 == 0 and C(20, 20, 20) or C(245, 245, 245)))
	end
	local ex, ez, edx, edz = geo:pointAt(geo.length - 0.5)
	local ey = geo:heightAt(geo.length)
	for k = -1, 1 do
		local p = world(ex + edx * 3 - edz * k * 3.4, ey + 1.2, ez + edz * 3 + edx * k * 3.4)
		part(m, "LugeHay", V(3.2, 2.4, 2.2), CFrame.lookAt(p, p + V(edx, 0, edz)), C(220, 190, 100), "Grass")
	end
	-- the bottom station
	local B = LugeLayout.BOTTOM_STATION
	local bcx, bcz = (B[1] + B[2]) / 2, (B[3] + B[4]) / 2
	part(m, "LugeDeck", V(B[2] - B[1], 0.6, B[4] - B[3]), CF(world(bcx, 0.3, bcz)), C(150, 110, 70), "WoodPlanks")
	local hut = part(m, "LugeCabin", V(10, 8, 6), CF(world(B[2] - 6, 4, B[4] - 4)), C(170, 110, 70), "WoodPlanks")
	part(m, "LugeRoof", V(12, 1, 8.5), CF(world(B[2] - 6, 8.5, B[4] - 4)) * A(math.rad(-8), 0, 0), C(160, 50, 40), "Slate")
	sign(hut, { { text = "🛷 ALPINE LUGE", color = C(255, 245, 220), share = 0.6 }, { text = "RIDE YOUR CAR DOWN THE HILL", color = C(255, 220, 150),
		share = 0.4, font = Enum.Font.GothamBold } }, C(120, 70, 40), Enum.NormalId.Front)
end

-- ── The chairlift ────────────────────────────────────────────────────────────

local function lift(m)
	local Lf = LugeLayout.LIFT
	local len = LugeLayout.liftLength()
	local lineA, lineB = O + Lf.bottom + V(0, Lf.hang, 0), O + Lf.top + V(0, Lf.hang, 0)
	-- two cables (up on the west side, down on the east)
	for _, dxo in ipairs({ -2.6, 2.6 }) do
		local a, b = lineA + V(dxo, 0, 0), lineB + V(dxo, 0, 0)
		deco(part(m, "LugeCable", V(0.25, 0.25, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), C(40, 40, 44), "Metal"))
	end
	-- towers
	local n = math.floor(len / Lf.towerStep)
	for k = 1, n - 1 do
		local f = k / n
		local top = lineA:Lerp(lineB, f)
		local g = O.Y + LugeLayout.ground(top.Z - O.Z)
		local h = top.Y + 1 - g
		part(m, "LugeTower", V(1.2, h, 1.2), CF(V(top.X, g + h / 2, top.Z)), C(110, 110, 118), "Metal")
		deco(part(m, "LugeArm", V(7, 0.6, 0.8), CF(top + V(0, 0.9, 0)), C(110, 110, 118), "Metal"))
	end
	-- bull wheels at both ends
	for _, p in ipairs({ lineA, lineB }) do
		deco(part(m, "LugeWheel", V(0.5, 6, 6), CF(p) * A(0, 0, math.pi / 2), C(60, 60, 66), "Metal", "cyl"))
		local g = O.Y + LugeLayout.ground(p.Z - O.Z)
		part(m, "LugeTower", V(2, p.Y - g, 2), CF(V(p.X, (p.Y + g) / 2, p.Z)), C(110, 110, 118), "Metal")
	end
	-- the chairs: the clients swing them round the loop (LugeClient)
	local chairs = Instance.new("Folder")
	chairs.Name = "LiftChairs"
	chairs.Parent = m
	for k = 1, LugeHill.CHAIRS do
		local c = Instance.new("Model")
		c.Name = "Chair" .. k
		local hanger = deco(part(c, "Hanger", V(0.2, 5, 0.2), CF(lineA - V(0, 2.5, 0)), C(60, 60, 66), "Metal"))
		local seat = deco(part(c, "Seat", V(3.4, 0.4, 1.6), CF(lineA - V(0, 5, 0)), C(70, 120, 200)))
		local back = deco(part(c, "Back", V(3.4, 1.8, 0.3), CF(lineA - V(0, 4.1, -0.8)), C(70, 120, 200)))
		local bar = deco(part(c, "Bar", V(3.4, 0.15, 0.15), CF(lineA - V(0, 3.4, 1)), C(200, 200, 205), "Metal"))
		c.PrimaryPart = hanger
		local _ = seat, back, bar
		c.Parent = chairs
	end
end

-- ── Scenery ──────────────────────────────────────────────────────────────────

local TREES = { "tree_tall", "tree_round", "tree_tall", "tree_puff" }
local FLOWERS = { C(255, 120, 160), C(255, 220, 80), C(180, 130, 255), C(255, 255, 255), C(255, 150, 60) }

local function inRect(r, x, z) return x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] end

local function clearOf(x, z, room)
	local geo = LugeLayout.geometry()
	local p = geo:project(x, z)
	if p.dist < W / 2 + room then return false end
	if math.abs(x - LugeLayout.LIFT.x) < 9 then return false end
	if inRect(LugeLayout.BOTTOM_STATION, x, z) or inRect(LugeLayout.TOP_STATION, x, z) then return false end
	local R = LugeLayout.REGION
	return x > R[1] + 4 and x < R[2] - 4 and z > R[3] + 4 and z < R[4] - 4
end

local function scenery(m)
	local rnd = Random.new(23)
	local R = LugeLayout.REGION
	local trees = 0
	for gx = R[1] + 8, R[2] - 8, 15 do
		for gz = R[3] + 8, R[4] - 8, 15 do
			local x, z = gx + rnd:NextNumber(-5, 5), gz + rnd:NextNumber(-5, 5)
			if clearOf(x, z, 8) and rnd:NextNumber() < 0.55 then
				local y = LugeLayout.ground(z)
				local h = rnd:NextNumber(13, 22)
				local cf = CF(world(x, y, z)) * A(0, rnd:NextNumber(0, math.pi * 2), 0)
				trees += 1
				if not storeModel(m, TREES[trees % #TREES + 1], cf, h, false) then
					-- a part-built pine
					deco(part(m, "Trunk", V(1, h * 0.35, 1), CF(world(x, y + h * 0.17, z)), C(100, 70, 45), "Wood"))
					for t = 0, 2 do
						local r = (3 - t) * 2.2
						deco(part(m, "Pine", V(r, h * 0.3, r), CF(world(x, y + h * (0.32 + t * 0.2), z)) * A(0, t * 0.6, 0),
							C(40 + t * 12, 110 + t * 10, 60), "Grass"))
					end
				end
			elseif clearOf(x, z, 3) and rnd:NextNumber() < 0.5 then
				-- a patch of flowers
				local y = LugeLayout.ground(z)
				for f = 1, 5 do
					local px, pz = x + rnd:NextNumber(-3, 3), z + rnd:NextNumber(-3, 3)
					deco(part(m, "Flower", V(0.8, 0.8, 0.8), CF(world(px, LugeLayout.ground(pz) + 0.4, pz)), FLOWERS[(f + gx) % #FLOWERS + 1],
						"SmoothPlastic", "ball"))
				end
				local _ = y
			end
		end
	end
	-- lanterns along the trough, every so often, on its right
	local geo = LugeLayout.geometry()
	for s = 30, geo.length - 20, 55 do
		local x, z = geo:offsetPoint(s, W / 2 + 3.5)
		if clearOf(x, z, 1.5) or true then
			local y = math.max(LugeLayout.ground(z), geo:heightAt(s) - 3)
			if not storeModel(m, "lamp_plain", CF(world(x, y, z)), 8, false) then
				deco(part(m, "LampPost", V(0.4, 7, 0.4), CF(world(x, y + 3.5, z)), C(50, 50, 56), "Metal"))
				local lamp = deco(part(m, "Lamp", V(1.2, 1.2, 1.2), CF(world(x, y + 7.4, z)), C(255, 225, 150), "Neon", "ball"))
				local light = Instance.new("PointLight")
				light.Range = 14
				light.Brightness = 0.8
				light.Color = C(255, 220, 160)
				light.Parent = lamp
			end
		end
	end
end

-- ── The ticket booth in town ─────────────────────────────────────────────────

local function booth(m)
	local base = O + LugeLayout.DESK
	local counter = part(m, "LugeDesk", V(5, 3.4, 2.6), CF(base + V(0, 1.7, 0)), C(150, 100, 60), "WoodPlanks")
	for _, x in ipairs({ -2.2, 2.2 }) do
		part(m, "LugeBoothPost", V(0.5, 8, 0.5), CF(base + V(x, 4, -1)), C(120, 84, 52), "Wood")
	end
	part(m, "LugeBoothRoof", V(6.4, 0.6, 4), CF(base + V(0, 8.2, -0.4)), C(200, 50, 50), "SmoothPlastic")
	local board = part(m, "LugeBoothSign", V(6, 2.4, 0.3), CF(base + V(0, 9.8, -0.6)), C(250, 245, 230))
	sign(board, { { text = "🛷 ALPINE LUGE", color = C(200, 40, 40), share = 0.6 }, { text = "Own a car? Ride it down the hill!", color = C(60, 60, 70),
		share = 0.4, font = Enum.Font.GothamBold } }, C(250, 245, 230), Enum.NormalId.Back)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "LugePrompt"
	pp.ActionText = "Ride the luge"
	pp.ObjectText = "Alpine Luge"
	pp.HoldDuration = 0.3
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("LugeAction", "enter")
	pp.Parent = counter
end

function LugeHill.build(parent)
	local old = parent:FindFirstChild(LugeHill.NAME)
	if old then old:Destroy() end
	local m = Instance.new("Model")
	m.Name = LugeHill.NAME
	ground(m)
	trough(m)
	supports(m)
	stations(m)
	lift(m)
	scenery(m)
	booth(m)
	local carts = Instance.new("Folder")
	carts.Name = "Carts"
	carts.Parent = m
	m.Parent = parent
	return m
end

return LugeHill
