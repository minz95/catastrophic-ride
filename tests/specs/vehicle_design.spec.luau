--!nocheck
-- Vehicle look (Modules/VehicleDesign + VehicleBuilder) over many item
-- combinations: every item in every slot on every biome, plus random full
-- builds. Checks what makes a car read as a car (and a boat as a boat, a plane
-- as a plane) and what keeps the look from touching handling.
-- See it: lune run tools/vehicle_gallery.luau → reports/vehicles/*.svg
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local env = Loader.boot()
env.run(env.find("ServerScriptService.ItemModelPreloader"))
local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
local VehicleDesign = env.requirePath("ServerScriptService.Modules.VehicleDesign")
local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local ItemTypes = env.requirePath("ReplicatedStorage.Shared.ItemTypes")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

local SLOTS = { "BODY", "ENGINE", "SPECIAL", "MOBILITY", "HEAD", "TAIL" }
local CORE = { BODY = true, ENGINE = true, SPECIAL = true }
local names, byType = {}, { BODY = {}, ENGINE = {}, SPECIAL = {} }
for _, it in ipairs(ItemTypes.ALL) do
	table.insert(names, it.name)
	table.insert(byType[it.slotType], it.name)
end

local seed = 20261020
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end

-- Every item alone in every slot it can go in, then random full builds.
local function builds()
	local out = { {} }
	for _, slot in ipairs(SLOTS) do
		for _, name in ipairs(names) do
			if not CORE[slot] or ItemConfig[name].slotType == slot then
				table.insert(out, { [slot] = name })
			end
		end
	end
	for _ = 1, 40 do
		table.insert(out, {
			BODY = byType.BODY[rnd(#byType.BODY)], ENGINE = byType.ENGINE[rnd(#byType.ENGINE)],
			SPECIAL = byType.SPECIAL[rnd(#byType.SPECIAL)], MOBILITY = names[rnd(#names)],
			HEAD = names[rnd(#names)], TAIL = names[rnd(#names)],
		})
	end
	return out
end
local BUILDS = builds()

local function statsFor(slots, biome)
	local s = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	return VehicleStats.applyMobility(s, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
end

local function label(slots)
	local t = {}
	for _, s in ipairs(SLOTS) do if slots[s] then table.insert(t, s .. "=" .. slots[s]) end end
	return #t > 0 and table.concat(t, ",") or "no items"
end

-- Chassis sizes from before the redesign: the look must not change physics.
local function scale(v, lo, hi) return lo + math.clamp(v / Constants.BALANCE.STAT_BUDGET, 0, 1) * (hi - lo) end
local OLD_CHASSIS = {
	FOREST = function(s) return Vector3.new(scale(s.stability, 2.0, 3.2), 1.2, scale(s.stability, 3.0, 5.5)) end,
	OCEAN  = function(s) return Vector3.new(scale(s.floatability, 2.0, 3.4), 0.9, scale(s.floatability, 4.0, 7.0)) end,
	SKY    = function(s) local r = scale(s.flyability, 0.45, 0.75); return Vector3.new(r * 2, r * 2, scale(s.flyability, 3.5, 6.0)) end,
}

-- Named parts that must sit at the front (z < 0) and at the back (z > 0).
local ENDS = {
	FOREST = { front = { "HeadlightL", "HeadlightR", "BumperFront", "Grille" }, back = { "TaillightL", "TaillightR", "BumperRear" } },
	OCEAN  = { front = { "ProwL", "ProwR" }, back = { "Transom" } },
	SKY    = { front = { "Spinner", "PropBlade1" }, back = { "Fin", "Stabilizer" } },
}
-- Riding a BODY item: what is left of the car / boat / plane
local RIDE_ENDS = {
	FOREST = { front = { "WheelFrontL", "WheelFrontR" }, back = { "WheelRearL", "WheelRearR" } },
	OCEAN  = { front = {}, back = {} },   -- the motor: behind the item (attach check)
	SKY    = { front = { "Spinner", "PropBlade1" }, back = { "Fin", "Stabilizer" } },
}

local function box(part)
	local lo, hi
	local cf, h = part.CFrame, part.Size * 0.5
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local v = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
		lo = lo and Vector3.new(math.min(lo.X, v.X), math.min(lo.Y, v.Y), math.min(lo.Z, v.Z)) or v
		hi = hi and Vector3.new(math.max(hi.X, v.X), math.max(hi.Y, v.Y), math.max(hi.Z, v.Z)) or v
	end end end
	return lo, hi
end

for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	R.describe(biome .. " vehicle look (" .. #BUILDS .. " builds)", function()
		local problems = {
			physics = {}, welds = {}, size = {}, ends = {}, ground = {}, symmetry = {}, fit = {}, seat = {}, headtail = {}, ride = {},
			attach = {}, water = {},
		}
		local function bad(kind, slots, msg)
			if #problems[kind] < 6 then table.insert(problems[kind], label(slots) .. ": " .. msg) end
		end

		for _, slots in ipairs(BUILDS) do
			local stats = statsFor(slots, biome)
			local model = VehicleBuilder.build(stats, biome, CFrame.new(), slots)
			local chassis = model.PrimaryPart
			local design = VehicleDesign.layout(biome, stats, slots)
			if design.riding then
				local rlo, rhi = VehicleBuilder.boundsIn(model, CFrame.new(), "BODY")
				if rlo then VehicleDesign.fitRide(design, rlo, rhi) end
			end
			local byName = {}
			local lo, hi
			local welded = {}
			-- welded to the chassis, or to a spin hub jointed to it (MOBILITY)
			local hubs = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Motor6D") and d.Part0 == chassis then hubs[d.Part1] = true; welded[d.Part1] = true end
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("WeldConstraint") and (d.Part0 == chassis or hubs[d.Part0]) then welded[d.Part1] = true end
			end
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					byName[p.Name] = p
					local a, b = box(p)
					lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
					hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
					if p ~= chassis then
						if not welded[p] then bad("welds", slots, p.Name .. " is not welded to the chassis") end
						if p.CanCollide then bad("physics", slots, p.Name .. " collides") end
						if not p:IsA("VehicleSeat") and not p.Massless then bad("physics", slots, p.Name .. " has mass") end
					end
				end
			end

			-- Physics: chassis exactly as before the redesign
			local want = OLD_CHASSIS[biome](stats)
			if (chassis.Size - want).Magnitude > 1e-6 or chassis.Name ~= "Chassis" or not chassis.CanCollide then
				bad("physics", slots, "chassis " .. tostring(chassis.Size) .. " (want " .. tostring(want) .. ")")
			end

			-- Fits the grid slot and the lane
			local size = hi - lo
			if size.X > VehicleDesign.MAX_WIDTH + 1e-6 or size.Z > VehicleDesign.MAX_LENGTH + 1e-6 then
				bad("size", slots, string.format("%.1f wide, %.1f long", size.X, size.Z))
			end

			-- Front and back
			local ends = design.riding and RIDE_ENDS[biome] or ENDS[biome]
			if design.riding and biome == "FOREST" and slots.MOBILITY then
				ends = { front = { "AxleFront" }, back = { "AxleRear" } }   -- the item is the wheels
			end
			for _, n in ipairs(ends.front) do
				local p = byName[n]
				if not p then bad("ends", slots, "missing " .. n)
				elseif p.Position.Z > -chassis.Size.Z * 0.3 then bad("ends", slots, n .. " is not at the front") end
			end
			for _, n in ipairs(ends.back) do
				local p = byName[n]
				if not p then bad("ends", slots, "missing " .. n)
				elseif p.Position.Z < chassis.Size.Z * 0.3 then bad("ends", slots, n .. " is not at the back") end
			end

			-- Nothing under the road / below the hull
			local bottom = -chassis.Size.Y / 2
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					local a = box(p)
					-- a boat's hull, float, paddles and motor leg reach into the water
					local floor = biome == "FOREST" and bottom - 0.2
						or (biome == "OCEAN" and VehicleDesign.WATERLINE - VehicleDesign.DRAFT or bottom - 1.2)
					if p.Name == "MotorLeg" then floor = bottom - 0.8 end
					if a.Y < floor - 0.02 then bad("ground", slots, string.format("%s reaches y %.2f (floor %.2f)", p.Name, a.Y, floor)) end
				end
			end

			-- Mirror pairs
			for name, p in pairs(byName) do
				if p.Parent == model and name:sub(-1) == "L" and byName[name:sub(1, -2) .. "R"] then
					local q = byName[name:sub(1, -2) .. "R"]
					if math.abs(p.Position.X + q.Position.X) > 1e-3 or math.abs(p.Position.Y - q.Position.Y) > 1e-3
						or math.abs(p.Position.Z - q.Position.Z) > 1e-3 then
						bad("symmetry", slots, name .. " / R not mirrored")
					end
				end
			end

			-- Every item sits inside its slot box, one copy per mount
			local holders = {}
			for _, c in ipairs(model:GetChildren()) do
				if c:IsA("Model") and c:GetAttribute("Slot") then
					local s = c:GetAttribute("Slot")
					holders[s] = holders[s] or {}
					table.insert(holders[s], c)
				end
			end
			for _, slot in ipairs(SLOTS) do
				local mounts = design.mounts[slot] or {}
				local got = holders[slot] or {}
				if slots[slot] and #got ~= #mounts then
					bad("fit", slots, string.format("%s: %d copies for %d mounts", slot, #got, #mounts))
				end
				for i, h in ipairs(got) do
					local m = mounts[i]
					local centre, ext = VehicleBuilder.bounds(h)
					if m then
						-- measured in the mount's own axes (a paddle is turned)
						local mlo, mhi
						for _, p in ipairs(h:GetDescendants()) do
							if p:IsA("BasePart") and p.Name ~= "HatBase" then
								local a, b = box(p)
								for _, v in ipairs({ a, b }) do
									local q = m.cf:PointToObjectSpace(v)
									mlo = mlo and Vector3.new(math.min(mlo.X, q.X), math.min(mlo.Y, q.Y), math.min(mlo.Z, q.Z)) or q
									mhi = mhi and Vector3.new(math.max(mhi.X, q.X), math.max(mhi.Y, q.Y), math.max(mhi.Z, q.Z)) or q
								end
							end
						end
						if m.spin then ext = mhi - mlo end
						local over = ext - m.box
						if over.X > 0.02 or over.Y > 0.02 or over.Z > 0.02 then
							bad("fit", slots, string.format("%s %s is %s, box %s", slot, slots[slot], tostring(ext), tostring(m.box)))
						end
						-- floor-standing and on-the-ride items: centred across, height set by the build
						local off = centre - m.cf.Position
						if m.spin then off = (mlo + mhi) * 0.5 end   -- in the mount's axes
						if m.side then
							-- flush with the outer side instead of centred across
							local outer = m.side > 0 and mhi.X or mlo.X
							if math.abs(outer - m.side * m.box.X / 2) > 0.02 then bad("fit", slots, slot .. " " .. slots[slot] .. " not flush outside") end
							off = Vector3.new(0, off.Y, off.Z)
						end
						if m.align == "bottom" or m.onRide then off = Vector3.new(off.X, 0, off.Z) end
						if m.front then off = Vector3.new(off.X, off.Y, 0) end   -- against the front instead
						if off.Magnitude > 0.02 then
							bad("fit", slots, slot .. " " .. slots[slot] .. " off its mount centre")
						end
						if m.align == "bottom" and not m.hat and not m.spin and centre.Y - ext.Y / 2 < m.cf.Position.Y - m.box.Y / 2 - 0.02 then
							bad("fit", slots, slot .. " " .. slots[slot] .. " below its mount floor")
						end
					end
				end
			end
			-- HEAD is a hat: over the seat, its bottom at a seated avatar's head top
			if slots.HEAD and holders.HEAD then
				local hs = model:FindFirstChildWhichIsA("VehicleSeat")
				local c, e = VehicleBuilder.bounds(holders.HEAD[1])
				local want = hs.Position.Y + hs.Size.Y / 2 + VehicleDesign.HAT.headTop - VehicleDesign.HAT.sink
				if math.abs(c.X - hs.Position.X) > 0.05 or math.abs(c.Z - hs.Position.Z) > 0.05
					or math.abs(c.Y - e.Y / 2 - want) > 0.1 then
					bad("headtail", slots, "HEAD item not over the seat at head height")
				end
			end
			if slots.TAIL and holders.TAIL and VehicleBuilder.bounds(holders.TAIL[1]).Z < 0 then
				bad("headtail", slots, "TAIL item in front of the centre")
			end

			-- Riding: the chassis is hidden and the item covers the footprint
			if design.riding then
				local h = holders.BODY and holders.BODY[1]
				local seat = model:FindFirstChildWhichIsA("VehicleSeat")
				if chassis.Transparency < 1 then bad("ride", slots, "chassis still shows") end
				if not h then bad("ride", slots, "no ridden item")
				else
					local c, e = VehicleBuilder.bounds(h)
					if e.Z < chassis.Size.Z * 0.6 and e.X < chassis.Size.X * 0.6 then
						bad("ride", slots, string.format("ridden item only %.1f x %.1f on a %.1f x %.1f chassis", e.X, e.Z, chassis.Size.X, chassis.Size.Z))
					end
					if c.Y + e.Y / 2 < chassis.Size.Y / 2 - 0.02 then bad("ride", slots, "ridden item below the chassis top") end
					-- on the item's top, or down into it by RIDE_LOOK `sink` (a tub, a sofa)
					local sink = ((VehicleDesign.RIDE_LOOK[slots.BODY] or {}).sink or 0) * e.Y
					if seat and math.abs(seat.Position.Y - seat.Size.Y / 2 + sink - math.min(c.Y + e.Y / 2, design.mounts.BODY[1].cf.Position.Y + design.mounts.BODY[1].box.Y / 2)) > 0.05 then
						bad("ride", slots, "seat not on the ridden item")
					end
				end
			end

			-- Wheels, paddle wheels and propellers touch what carries them: the
			-- body (or the ridden item), or an axle / post that does
			do
				local function boxOf(x)
					if x:IsA("BasePart") then return box(x) end
					local a, b
					for _, p in ipairs(x:GetDescendants()) do
						if p:IsA("BasePart") and p.Transparency < 1 then
							local pa, pb = box(p)
							a = a and Vector3.new(math.min(a.X, pa.X), math.min(a.Y, pa.Y), math.min(a.Z, pa.Z)) or pa
							b = b and Vector3.new(math.max(b.X, pb.X), math.max(b.Y, pb.Y), math.max(b.Z, pb.Z)) or pb
						end
					end
					return a, b
				end
				local function touch(x, y)
					if not x or not y then return false end
					local a1, b1 = boxOf(x)
					local a2, b2 = boxOf(y)
					if not a1 or not a2 then return false end
					local t = 0.05
					return a1.X <= b2.X + t and a2.X <= b1.X + t and a1.Y <= b2.Y + t and a2.Y <= b1.Y + t
						and a1.Z <= b2.Z + t and a2.Z <= b1.Z + t
				end
				local base = design.riding and holders.BODY and holders.BODY[1] or chassis
				local function carried(x)
					if touch(x, base) then return true end
					for _, n in ipairs({ "AxleFront", "AxleRear" }) do
						local axle = byName[n]
						if axle and touch(x, axle) and (touch(axle, base)
							or touch(byName[n:gsub("Axle", "Post")], base) and touch(axle, byName[n:gsub("Axle", "Post")])) then
							return true
						end
					end
					return false
				end
				if biome == "FOREST" then
					local wheels = slots.MOBILITY and (holders.MOBILITY or {}) or {}
					if not slots.MOBILITY then
						for _, n in ipairs({ "WheelFrontL", "WheelFrontR", "WheelRearL", "WheelRearR" }) do table.insert(wheels, byName[n]) end
					end
					for _, w in ipairs(wheels) do
						if not carried(w) then bad("attach", slots, "a wheel hangs loose") break end
					end
				elseif biome == "OCEAN" and slots.MOBILITY then
					for _, n in ipairs({ "PaddleHubL", "PaddleHubR" }) do
						if not (touch(byName[n], base) or touch(byName[n], byName.Float)) then bad("attach", slots, n .. " off the hull") end
					end
					for _, h in ipairs(holders.MOBILITY or {}) do
						if not (touch(h, byName.PaddleHubL) or touch(h, byName.PaddleHubR)) then
							bad("attach", slots, "a paddle off its hub") break
						end
					end
				end
				-- the boat's motor (or ENGINE item) and flag hold on to the boat
				if biome == "OCEAN" then
					-- the boat's own parts (an item may have a part called "Motor")
					local function own(n) return model:FindFirstChild(n) end
					local motor = slots.ENGINE and holders.ENGINE and holders.ENGINE[1] or own("Motor")
					local leg = own("MotorLeg")
					local function onHull(x)
						for _, h in pairs({ base, own("Float"), own("Transom"), own("TransomSkirt"), own("Keel") }) do
							if h.Parent and touch(x, h) then return true end
						end
						return false
					end
					if motor and not onHull(motor) then bad("attach", slots, "the motor floats behind the boat") end
					if leg and motor and not touch(leg, motor) then bad("attach", slots, "the motor leg is off the motor") end
					if own("FlagPole") and not onHull(own("FlagPole")) then bad("attach", slots, "the flag pole floats") end
					-- riding: behind the item (the hull's old stern means nothing then)
					if design.riding and leg and holders.BODY then
						local c = VehicleBuilder.bounds(holders.BODY[1])
						if leg.Position.Z <= c.Z then bad("attach", slots, "the motor is not behind the ridden item") end
					end
				end
				if biome == "SKY" and slots.MOBILITY then
					for _, n in ipairs({ "NacelleL", "NacelleR" }) do
						if not touch(byName[n], byName.Wing) then bad("attach", slots, n .. " off the wing") end
					end
					for _, h in ipairs(holders.MOBILITY or {}) do
						if not (touch(h, byName.NacelleL) or touch(h, byName.NacelleR)) then
							bad("attach", slots, "a propeller off its nacelle") break
						end
					end
				end
				-- the sail stays clear of the deckhouse and the seat
				if biome == "OCEAN" and byName.Sail then
					local seatP = model:FindFirstChildWhichIsA("VehicleSeat")
					for _, other in ipairs({ byName.Cabin, byName.Windscreen, seatP }) do
						if other and other.Parent and touch(byName.Sail, other) then bad("attach", slots, "the sail cuts through " .. other.Name) end
					end
				end
			end

			-- A boat's lowest visible part is in the water (it races held over it)
			if biome == "OCEAN" then
				local low = math.huge
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "MotorLeg" and not p:FindFirstAncestor("Item_MOBILITY_" .. tostring(slots.MOBILITY)) then
						local a = box(p)
						if p.Name == "Keel" or p.Name == "Float" or (p.Parent and p.Parent:GetAttribute("Slot") == "BODY") then
							low = math.min(low, a.Y)
						end
					end
				end
				if low > VehicleDesign.WATERLINE + 0.02 then
					bad("water", slots, string.format("lowest hull part at y %.2f, the water at %.2f", low, VehicleDesign.WATERLINE))
				end
			end

			-- Seat on top of the chassis
			local seat = model:FindFirstChildWhichIsA("VehicleSeat")
			local into = design.riding and VehicleBuilder.SEAT_INTO_CHASSIS or 0
			if not seat or seat.Position.Y < chassis.Size.Y / 2 - into - 1e-6 then bad("seat", slots, "seat missing or inside the chassis") end
			model:Destroy()
		end

		R.it("only the chassis has mass and collision, and it is sized as before", function()
			R.expect(problems.physics).toBeEmpty("physics changed by the look")
		end)
		R.it("every part is welded to the chassis", function()
			R.expect(problems.welds).toBeEmpty("loose parts")
		end)
		R.it("fits the 7-stud grid slot", function()
			R.expect(problems.size).toBeEmpty("too big")
		end)
		R.it("front parts at the front (-Z, the driving direction), back parts at the back", function()
			R.expect(problems.ends).toBeEmpty("vehicle facing the wrong way")
		end)
		R.it("the boat waterline matches the race: chassis held over the water", function()
			local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
			R.expect(VehicleDesign.WATERLINE).toBe(BiomeConfig.OCEAN.waterPlaneY - BiomeConfig.OCEAN.raceStartY)
		end)
		R.it("HEAD item worn as a hat over the seat, TAIL item at the back", function()
			R.expect(problems.headtail).toBeEmpty("head / tail swapped")
		end)
		R.it("nothing reaches under the ground or the hull", function()
			R.expect(problems.ground).toBeEmpty("parts below the vehicle")
		end)
		R.it("left / right parts mirror each other", function()
			R.expect(problems.symmetry).toBeEmpty("asymmetric pairs")
		end)
		R.it("items fit their slot boxes, centred, one per mount", function()
			R.expect(problems.fit).toBeEmpty("items outside their slot")
		end)
		R.it("with a BODY item you ride it: it covers the hidden chassis and carries the seat", function()
			R.expect(problems.ride).toBeEmpty("ride problems")
		end)
		R.it("wheels, paddle wheels and propellers are attached; the sail is clear of cabin and seat", function()
			R.expect(problems.attach).toBeEmpty("loose parts")
		end)
		R.it("boats reach the water: the hull, or the float under a ridden item", function()
			R.expect(problems.water).toBeEmpty("boats over the water")
		end)
		R.it("has a seat on top of the chassis", function()
			R.expect(problems.seat).toBeEmpty("seat problems")
		end)
	end)
end

R.describe("HEAD item worn as a hat", function()
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		for _, body in ipairs({ false, true }) do
			local slots = { HEAD = "Rubber Duck", BODY = body and "Pizza" or nil }
			R.it(biome .. (body and " riding a Pizza" or "") .. ": goes onto the rider's head and back", function()
				local model = VehicleBuilder.build(statsFor(slots, biome), biome, CFrame.new(5, 10, 20), slots)
				local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
				local char = env.mock.Instance.new("Model")
				char.Name = "Rider"
				local head = env.mock.Instance.new("Part")
				head.Name = "Head"
				head.Size = Vector3.new(1.2, 1.2, 1.2)
				head.CFrame = seat.CFrame * CFrame.new(0, 2.6, 0.2)
				head.Parent = char
				R.expect(VehicleBuilder.wearHat(model, char)).toBe(true)
				local hat
				for _, c in ipairs(model:GetChildren()) do
					if c:IsA("Model") and c:GetAttribute("Hat") then hat = c end
				end
				local c, e = VehicleBuilder.bounds(hat)
				local top = head.Position + Vector3.new(0, head.Size.Y / 2 - VehicleDesign.HAT.sink, 0)
				R.expect(math.abs(c.X - top.X) < 0.05 and math.abs(c.Z - top.Z) < 0.05).toBe(true)
				R.expect(math.abs(c.Y - e.Y / 2 - top.Y) < 0.1).toBe(true)
				for _, p in ipairs(hat:GetDescendants()) do
					if p:IsA("BasePart") then
						local w = p:FindFirstChildWhichIsA("WeldConstraint")
						R.expect(w and w.Part0 == head).toBe(true)
					end
				end
				R.expect(VehicleBuilder.takeOffHat(model)).toBe(true)
				c, e = VehicleBuilder.bounds(hat)
				local want = seat.Position.Y + seat.Size.Y / 2 + VehicleDesign.HAT.headTop - VehicleDesign.HAT.sink
				R.expect(math.abs(c.Y - e.Y / 2 - want) < 0.1).toBe(true)
				R.expect(hat.PrimaryPart:FindFirstChildWhichIsA("WeldConstraint").Part0 == model.PrimaryPart).toBe(true)
				model:Destroy()
			end)
		end
	end
end)
