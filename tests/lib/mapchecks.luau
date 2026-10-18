--!nocheck
-- mapchecks.luau
-- Geometry checks shared by the per-biome map specs. Each check takes a world
-- from World.build and returns a list of human-readable problems (empty = ok).
--
--   local MapChecks = require("../lib/mapchecks")
--   R.expect(MapChecks.wallIntrusions(w, isWall)).toBeEmpty("...")

local MapQuery = require("./mapquery")

local MapChecks = {}

local function round(n) return math.floor(n + 0.5) end

function MapChecks.tagged(w, tag)
	local out = {}
	for _, sh in ipairs(w.allShapes) do
		if table.find(sh.tags, tag) then table.insert(out, sh) end
	end
	return out
end

--- Calls fn(x, z, s, lat, seg) for points across the driving lane.
function MapChecks.eachLanePoint(w, step, margin, latStep, fn)
	local geo, half = w.geo, w.track.width / 2
	for s = 0, geo.length, step do
		for lat = -(half - margin), half - margin, latStep do
			local x, z, _, _, seg = geo:offsetPoint(s, lat)
			fn(x, z, s, lat, seg)
		end
	end
end

--- Points on the arc around each interior node at radius `r`, between the two
-- segment normals on `side` (-1 left, +1 right). offsetPoint jumps across this
-- wedge at a kink, so the outer corner of a turn is only sampled here.
-- Calls fn(x, z, node). side = "outer" picks the outside of each turn.
function MapChecks.eachCornerPoint(w, r, side, step, fn)
	local nodes = w.track.nodes
	for i = 2, #nodes - 1 do
		local a, b, c = nodes[i - 1], nodes[i], nodes[i + 1]
		local d1x, d1z = b[1] - a[1], b[2] - a[2]
		local d2x, d2z = c[1] - b[1], c[2] - b[2]
		local l1, l2 = math.sqrt(d1x * d1x + d1z * d1z), math.sqrt(d2x * d2x + d2z * d2z)
		if l1 > 0.1 and l2 > 0.1 then
			d1x, d1z, d2x, d2z = d1x / l1, d1z / l1, d2x / l2, d2z / l2
			local cross = d1x * d2z - d1z * d2x
			local sides = {}
			if side == "outer" then
				-- right of travel = (-dz, dx); cross > 0 turns right, so the
				-- outside is the left
				if math.abs(cross) > 1e-6 then sides = { cross > 0 and -1 or 1 } end
			else
				sides = { -1, 1 }
			end
			for _, sd in ipairs(sides) do
				-- normal on side sd is sd * (-dz, dx); as an angle atan2(nz, nx)
				local a1 = math.atan2(sd * d1x, -sd * d1z)
				local a2 = math.atan2(sd * d2x, -sd * d2z)
				local da = math.atan2(math.sin(a2 - a1), math.cos(a2 - a1))
				local n = math.max(1, math.ceil(math.abs(da) * r / step))
				for k = 0, n do
					local ang = a1 + da * k / n
					fn(b[1] + r * math.cos(ang), b[2] + r * math.sin(ang), i)
				end
			end
		end
	end
end

function MapChecks.tagCounts(w, want)
	local bad = {}
	for tag, n in pairs(want) do
		local got = #MapChecks.tagged(w, tag)
		if got ~= n then table.insert(bad, tag .. ": " .. got .. " (want " .. n .. ")") end
	end
	table.sort(bad)
	return bad
end

function MapChecks.startGrid(w)
	local bad, half = {}, w.track.width / 2
	for _, z in ipairs(w.track.startGrid.rows) do
		for _, x in ipairs(w.track.startGrid.cols) do
			local p = w.geo:project(x, z)
			if p.dist > half - 3 then table.insert(bad, x .. "," .. z) end
		end
	end
	return bad
end

local SOLID_OK = { SlowZone = true, BoostPad = true, MudZone = true }

--- Trigger volumes that are collidable (invisible walls) in this world.
function MapChecks.solidTriggers(w)
	local solid = {}
	for _, sh in ipairs(w.allShapes) do
		local isTrig, tag = MapQuery.isTrigger(sh)
		if isTrig and sh.canCollide and not SOLID_OK[tag] then
			table.insert(solid, sh.name .. " (" .. tag .. ")")
		end
	end
	table.sort(solid)
	return solid
end

--- Collidable parts other than walls that stand in the lane.
function MapChecks.laneObstacles(w, isWall)
	local hits, seen = {}, {}
	MapChecks.eachLanePoint(w, 1, 3, 1.5, function(x, z, s, lat)
		for _, ob in ipairs(w.obstacleGrid.near(x, z, 1)) do
			if not isWall(ob.name) and not seen[ob] and MapQuery.contains(ob, x, z) then
				seen[ob] = true
				table.insert(hits, string.format("%s at s=%d lateral=%d", ob.name, s, lat))
			end
		end
	end)
	return hits
end

--- Walls that reach deeper than `margin` studs into the lane, worst per node.
function MapChecks.wallIntrusions(w, isWall, margin)
	margin = margin or 6
	local half = w.track.width / 2
	local worst = {}
	MapChecks.eachLanePoint(w, 2, margin, 2, function(x, z, s, lat, seg)
		for _, ob in ipairs(w.obstacleGrid.near(x, z, 1)) do
			if isWall(ob.name) and MapQuery.contains(ob, x, z) then
				local node = seg + 1
				local depth = half - math.abs(lat)
				if not worst[node] or depth > worst[node].depth then
					worst[node] = { depth = depth, s = s, part = ob.name }
				end
			end
		end
	end)
	local defl = {}
	for _, d in ipairs(w.geo:deflections()) do defl[d.node] = d.angle end
	local list = {}
	for node, it in pairs(worst) do
		table.insert(list, { node = node, depth = it.depth, s = it.s, part = it.part })
	end
	table.sort(list, function(a, b) return a.node < b.node end)
	local lines = {}
	for _, it in ipairs(list) do
		table.insert(lines, string.format("near N%d (%+.0f° turn): %s %d studs into the lane at s=%d",
			it.node, defl[it.node] or defl[it.node - 1] or 0, it.part, round(it.depth), it.s))
	end
	return lines
end

--- Off-track slow zones that cover part of the lane.
function MapChecks.slowZonesInLane(w)
	local zones = MapChecks.tagged(w, "SlowZone")
	local grid = MapQuery.grid(zones, 32)
	local hit = {}
	MapChecks.eachLanePoint(w, 4, 3, 3, function(x, z, s, _, seg)
		for _, zsh in ipairs(grid.near(x, z, 1)) do
			if MapQuery.contains(zsh, x, z) then
				hit[zsh.name] = hit[zsh.name] or { s = s, seg = seg }
			end
		end
	end)
	local lines = {}
	for name, h in pairs(hit) do
		table.insert(lines, string.format("%s covers the lane near N%d (s=%d)", name, h.seg + 1, h.s))
	end
	table.sort(lines)
	return lines
end

local crosses = MapQuery.crosses

--- A gate trigger (checkpoint / finish) must be crossed by a car driving
-- along the lane at ANY lateral offset: for each offset, follow the offset
-- path through the gate's neighbourhood and require one point inside the box.
function MapChecks.gateSpan(w, tag, label)
	local gaps, half = {}, w.track.width / 2
	for _, box in ipairs(MapChecks.tagged(w, tag)) do
		local p = w.geo:project(box.cx, box.cz)
		local missed, total, worst = 0, 0, nil
		for lat = -(half - 2), half - 2, 1 do
			total += 1
			-- consecutive offset points are joined by straight moves, so the
			-- jump across the outside of a kink still counts as passing
			local hit = false
			local px, pz = w.geo:offsetPoint(p.s - 40, lat)
			for s = p.s - 39.5, p.s + 40, 0.5 do
				local x, z = w.geo:offsetPoint(s, lat)
				if crosses(box, px, pz, x, z) then hit = true break end
				px, pz = x, z
			end
			if not hit then
				missed += 1
				if not worst or math.abs(lat) < math.abs(worst) then worst = lat end
			end
		end
		if missed > 0 then
			table.insert(gaps, string.format("%s: a car %d studs off centre drives past it (%d/%d lateral positions miss)",
				label or box.name, math.abs(worst), missed, total))
		end
	end
	return gaps
end

--- Holes in the boundary (sampled `offset` studs from the centerline, where
-- the wall stands) longer than `maxGap` studs. Samples that fall inside some
-- other part of the lane (inner corners, crossings) are not boundary and are
-- skipped; the outside of every turn is sampled on an arc around the node.
function MapChecks.wallGaps(w, isWall, offset, maxGap)
	local walls = {}
	for _, sh in ipairs(w.obstacles) do
		if isWall(sh.name) then table.insert(walls, sh) end
	end
	local grid = MapQuery.grid(walls, 32)
	local geo, half = w.geo, w.track.width / 2
	local function covered(x, z)
		for _, wl in ipairs(grid.near(x, z, 1)) do
			if MapQuery.contains(wl, x, z) then return true end
		end
		return false
	end
	local function inLane(x, z)
		return geo:project(x, z).dist < half
	end
	local gaps = {}
	for _, side in ipairs({ -1, 1 }) do
		local runStart, runEnd = nil, nil
		local function flush()
			if runStart and runEnd - runStart > maxGap then
				local _, _, _, _, seg = geo:pointAt(runStart)
				table.insert(gaps, string.format("%s side: %d-stud gap at s=%d (near N%d)",
					side > 0 and "right" or "left", round(runEnd - runStart), round(runStart), seg + 1))
			end
			runStart = nil
		end
		for s = 2, geo.length - 2, 0.5 do
			local x, z = geo:offsetPoint(s, side * offset)
			if covered(x, z) or inLane(x, z) then
				flush()
			else
				runStart = runStart or s
				runEnd = s
			end
		end
		flush()
	end
	-- Outer corners: offsetPoint jumps across the outside of a kink, so walk
	-- each wall line past the node up to where the two wall lines meet
	-- (offset · tan(θ/2)) and require it to be walled (or inside the lane).
	local segs = geo.segments
	for i = 2, #segs do
		local A, B = segs[i - 1], segs[i]
		local cross = A.dx * B.dz - A.dz * B.dx
		local dot = math.clamp(A.dx * B.dx + A.dz * B.dz, -1, 1)
		if math.abs(cross) > 1e-6 and A.len > 0 and B.len > 0 then
			local lat = cross > 0 and -1 or 1   -- outside of the turn (+1 = right)
			local reachT = offset * math.tan(math.acos(dot) / 2)
			local worst = 0
			for _, leg in ipairs({ { A, A.len, A.len + reachT }, { B, -reachT, 0 } }) do
				local sg, ta, tb = leg[1], leg[2], leg[3]
				local rx, rz = -sg.dz * lat, sg.dx * lat
				local run = 0
				for t = ta, tb, 0.5 do
					local x = sg.ax + sg.dx * t + rx * offset
					local z = sg.az + sg.dz * t + rz * offset
					if covered(x, z) or inLane(x, z) then
						run = 0
					else
						run += 0.5
						worst = math.max(worst, run)
					end
				end
			end
			if worst > maxGap then
				table.insert(gaps, string.format("outside of the N%d turn: %d-stud hole in the wall", i, round(worst)))
			end
		end
	end
	return gaps
end

--- Pickups / triggers that must sit fully on the lane (e.g. boost pads).
function MapChecks.onLane(w, tag)
	local bad, half = {}, w.track.width / 2
	for _, sh in ipairs(MapChecks.tagged(w, tag)) do
		local p = w.geo:project(sh.cx, sh.cz)
		local reach = math.max(sh.hu, sh.hv)
		if p.dist + reach > half then
			table.insert(bad, string.format("%s at (%d,%d): %d studs from the centerline, edge %d studs past the lane edge",
				sh.name, round(sh.cx), round(sh.cz), round(p.dist), round(p.dist + reach - half)))
		end
	end
	table.sort(bad)
	return bad
end

--- Triggers the racing line must pass through (drift corners, jump zones).
function MapChecks.onCenterline(w, tag)
	local list = MapChecks.tagged(w, tag)
	local hit = {}
	for s = 0, w.geo.length, 1 do
		local x, z = w.geo:pointAt(s)
		for _, sh in ipairs(list) do
			if not hit[sh] and MapQuery.contains(sh, x, z) then hit[sh] = true end
		end
	end
	local bad = {}
	for _, sh in ipairs(list) do
		if not hit[sh] then
			table.insert(bad, string.format("%s at (%d,%d) is not on the centerline", sh.name, round(sh.cx), round(sh.cz)))
		end
	end
	table.sort(bad)
	return bad
end

--- Every lane point has a collidable floor part under it whose top is at the
-- track surface.
function MapChecks.floorCoverage(w, isFloor)
	local floors = {}
	for _, sh in ipairs(w.allShapes) do
		if sh.canCollide and isFloor(sh.name) and math.abs(sh.yMax - w.track.trackTop) < 0.5 then
			table.insert(floors, sh)
		end
	end
	local grid = MapQuery.grid(floors, 32)
	local holes = {}
	MapChecks.eachLanePoint(w, 2, 2, 2, function(x, z, s, _, seg)
		for _, f in ipairs(grid.near(x, z, 1)) do
			if MapQuery.contains(f, x, z) then return end
		end
		local node = seg + 1
		holes[node] = (holes[node] or 0) + 1
	end)
	for r = 2, w.track.width / 2 - 2, 2 do
		MapChecks.eachCornerPoint(w, r, "outer", 2, function(x, z, node)
			for _, f in ipairs(grid.near(x, z, 1)) do
				if MapQuery.contains(f, x, z) then return end
			end
			holes[node] = (holes[node] or 0) + 1
		end)
	end
	local lines = {}
	for node, n in pairs(holes) do
		table.insert(lines, string.format("near N%d: %d lane samples with no floor", node, n))
	end
	table.sort(lines)
	return lines
end

--- Visibility pass when MapVisibility never cached originals.
function MapChecks.uncachedVisibility(env, map)
	local MV = env.requirePath("ServerScriptService.Modules.MapVisibility")
	MV.applyRacingState(env.workspace.Maps, map)
	local bad = {}
	for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine", "DriftCorner", "JumpZone", "SlowZone", "UpdraftZone", "KillPlane" }) do
		for _, p in ipairs(env.mock.CollectionService:GetTagged(tag)) do
			if p.CanCollide or p.Transparency < 0.5 then
				table.insert(bad, p.Name .. " cc=" .. tostring(p.CanCollide) .. " t=" .. p.Transparency)
			end
		end
	end
	table.sort(bad)
	return bad
end

return MapChecks
