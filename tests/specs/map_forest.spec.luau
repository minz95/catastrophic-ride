--!nocheck
-- FOREST map built in the mock engine from the real ForestMap module, checked
-- for geometry problems a player would hit.
local R = require("../lib/runner")
local World = require("../lib/world")
local MapQuery = require("../lib/mapquery")

local shipped = World.forest({ visibility = "shipped" })
local intended = World.forest({ visibility = "intended" })
local geo, track = intended.geo, intended.track
local HALF = track.width / 2

local function tagged(w, tag)
	local out = {}
	for _, sh in ipairs(w.allShapes) do
		if table.find(sh.tags, tag) then table.insert(out, sh) end
	end
	return out
end

local function round(n) return math.floor(n + 0.5) end

R.describe("FOREST map build", function()
	R.it("has the expected tagged parts", function()
		local want = { Checkpoint1 = 1, Checkpoint2 = 1, FinishLine = 1, BoostPad = 4, DriftCorner = 4, MudZone = 4, JumpZone = 2 }
		local bad = {}
		for tag, n in pairs(want) do
			local got = #tagged(intended, tag)
			if got ~= n then table.insert(bad, tag .. ": " .. got .. " (want " .. n .. ")") end
		end
		R.expect(bad).toBeEmpty("tag counts")
	end)

	R.it("start grid slots sit inside the corridor", function()
		local bad = {}
		for _, z in ipairs(track.startGrid.rows) do
			for _, x in ipairs(track.startGrid.cols) do
				local p = geo:project(x, z)
				if p.dist > HALF - 3 then table.insert(bad, x .. "," .. z) end
			end
		end
		R.expect(bad).toBeEmpty("grid slots outside the lane")
	end)
end)

R.describe("FOREST map during RACING", function()
	R.known("trigger volumes stay non-collidable when the track is shown",
		"MapVisibility restores CanCollide with `stored ~= nil and stored or true`, which turns every false into true: checkpoints, finish line, drift corners and jump zones become invisible solid boxes",
		function()
			local solid = {}
			for _, sh in ipairs(shipped.allShapes) do
				local isTrig, tag = MapQuery.isTrigger(sh)
				if isTrig and sh.canCollide and tag ~= "SlowZone" and tag ~= "BoostPad" and tag ~= "MudZone" then
					table.insert(solid, sh.name .. " (" .. tag .. ")")
				end
			end
			table.sort(solid)
			R.expect(solid).toBeEmpty("solid trigger volumes")
		end)

	R.it("with authored collision, nothing but walls blocks the lane", function()
		local hits, seen = {}, {}
		for s = 0, geo.length, 4 do
			for lat = -(HALF - 3), HALF - 3, 3 do
				local x, z = geo:offsetPoint(s, lat)
				for _, ob in ipairs(intended.obstacleGrid.near(x, z, 1)) do
					if ob.name ~= "TrackWall" and not seen[ob] and MapQuery.contains(ob, x, z) then
						seen[ob] = true
						table.insert(hits, string.format("%s at s=%d lateral=%d", ob.name, s, lat))
					end
				end
			end
		end
		R.expect(hits).toBeEmpty("non-wall obstacles inside the lane")
	end)

	R.known("walls never cut into the lane",
		"walls are one straight box per segment; at sharp kinks the next segment's wall slices into the current lane",
		function()
			local intrusions = {}
			local worst = {}
			for s = 0, geo.length, 2 do
				for lat = -(HALF - 6), HALF - 6, 2 do
					local x, z, _, _, seg = geo:offsetPoint(s, lat)
					for _, ob in ipairs(intended.obstacleGrid.near(x, z, 1)) do
						if ob.name == "TrackWall" and MapQuery.contains(ob, x, z) then
							local node = seg + 1
							local depth = HALF - math.abs(lat)
							if not worst[node] or depth > worst[node].depth then
								worst[node] = { depth = depth, s = s }
							end
						end
					end
				end
			end
			local defl = {}
			for _, d in ipairs(geo:deflections()) do defl[d.node] = d.angle end
			for node, w in pairs(worst) do
				table.insert(intrusions, { node = node, depth = w.depth, s = w.s })
			end
			table.sort(intrusions, function(a, b) return a.depth > b.depth end)
			local lines = {}
			for _, it in ipairs(intrusions) do
				table.insert(lines, string.format("near N%d (%+.0f° turn): wall %d studs into the lane at s=%d",
					it.node, defl[it.node] or defl[it.node - 1] or 0, round(it.depth), it.s))
			end
			R.expect(lines).toBeEmpty("wall intrusions deeper than 6 studs from the lane edge")
		end)

	R.known("off-track slow zones never cover the lane",
		"SlowZone pads are placed per segment just outside its walls; at sharp kinks they overlap the next segment's lane, so cars on the racing line get the 0.6× off-track penalty",
		function()
			local zones = {}
			for _, sh in ipairs(intended.allShapes) do
				if table.find(sh.tags, "SlowZone") then table.insert(zones, sh) end
			end
			local grid = MapQuery.grid(zones, 32)
			local hit = {}
			for s = 0, geo.length, 4 do
				for lat = -(HALF - 3), HALF - 3, 3 do
					local x, z, _, _, seg = geo:offsetPoint(s, lat)
					for _, zsh in ipairs(grid.near(x, z, 1)) do
						if MapQuery.contains(zsh, x, z) then
							hit[zsh.name] = hit[zsh.name] or { s = s, seg = seg }
						end
					end
				end
			end
			local lines = {}
			for name, h in pairs(hit) do
				table.insert(lines, string.format("%s covers the lane near N%d (s=%d)", name, h.seg + 1, h.s))
			end
			table.sort(lines)
			R.expect(lines).toBeEmpty("slow zones inside the driving lane")
		end)

	R.known("checkpoint triggers span the whole corridor",
		"checkpoint boxes are axis-aligned 40×6; CP1 sits where the track runs along X, so it covers only a 6-stud strip of the lane",
		function()
			local gaps = {}
			for i = 1, #track.checkpoints do
				local box = tagged(intended, "Checkpoint" .. i)[1]
				local cx, cz = track.checkpoints[i][1], track.checkpoints[i][2]
				local p = geo:project(cx, cz)
				local missed = 0
				for lat = -(HALF - 2), HALF - 2, 1 do
					local x, z = geo:offsetPoint(p.s, lat)
					if not MapQuery.contains(box, x, z) then missed += 1 end
				end
				local total = 2 * (HALF - 2) + 1
				if missed > 0 then
					table.insert(gaps, string.format("CP%d misses %d/%d lateral positions across the lane", i, missed, total))
				end
			end
			R.expect(gaps).toBeEmpty("checkpoints a car can drive past without touching")
		end)

	R.known("jump ramps sit inside the corridor and face the direction of travel",
		"JumpRamp_1 is placed 18 studs off the centerline of a 40-wide lane and is not aligned with the track",
		function()
			local bad = {}
			for i, r in ipairs(track.jumpRamps) do
				local p = geo:project(r[1], r[2])
				local trackYaw = geo:yawAt(p.s)
				-- WedgePart is built with CFrame.Angles(0, yaw + pi, 0); its slope faces
				-- the vehicle when that yaw matches the travel direction ± 180°.
				local diff = math.abs(math.deg(((r[3] + math.pi - trackYaw + math.pi) % (2 * math.pi)) - math.pi))
				diff = math.min(diff, math.abs(180 - diff))
				if math.abs(p.lateral) > 4 then
					table.insert(bad, string.format("JumpRamp_%d is %.0f studs off centre (ramp half-width %d)", i, math.abs(p.lateral), track.jumpRampSize[1] / 2))
				end
				if diff > 15 then
					table.insert(bad, string.format("JumpRamp_%d is rotated %.0f° from the track direction", i, diff))
				end
			end
			R.expect(bad).toBeEmpty("misplaced ramps")
		end)

	R.known("no tree trunk stands inside the corridor",
		"tree placement only keeps 35 studs from track NODES, not from the segments between them, so trees grow inside long straights (solid during RACING because of the CanCollide bug)",
		function()
			local bad = {}
			for _, sh in ipairs(intended.allShapes) do
				if sh.name:find("Trunk") then
					local p = geo:project(sh.cx, sh.cz)
					if p.dist < HALF + 2 then
						table.insert(bad, string.format("%s at (%d,%d), %d studs from the centerline at s=%d", sh.name, sh.cx, sh.cz, p.dist, p.s))
					end
				end
			end
			R.expect(bad).toBeEmpty("trees in the lane")
		end)
end)
