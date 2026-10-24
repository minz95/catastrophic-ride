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
	OCEAN  = { front = {}, back = { "MotorLeg" } },
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
		}
		local function bad(kind, slots, msg)
			if #problems[kind] < 6 then table.insert(problems[kind], label(slots) .. ": " .. msg) end
		end

		for _, slots in ipairs(BUILDS) do
			local stats = statsFor(slots, biome)
			local model = VehicleBuilder.build(stats, biome, CFrame.new(), slots)
			local chassis = model.PrimaryPart
			local design = VehicleDesign.layout(biome, stats, slots)
			local byName = {}
			local lo, hi
			local welded = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("WeldConstraint") and d.Part0 == chassis then welded[d.Part1] = true end
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
					local floor = biome == "FOREST" and bottom - 0.2 or (biome == "OCEAN" and bottom or bottom - 1.2)
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
						local over = ext - m.box
						if over.X > 0.02 or over.Y > 0.02 or over.Z > 0.02 then
							bad("fit", slots, string.format("%s %s is %s, box %s", slot, slots[slot], tostring(ext), tostring(m.box)))
						end
						-- floor-standing and on-the-ride items: centred across, height set by the build
						local off = centre - m.cf.Position
						if m.align == "bottom" or m.onRide then off = Vector3.new(off.X, 0, off.Z) end
						if off.Magnitude > 0.02 then
							bad("fit", slots, slot .. " " .. slots[slot] .. " off its mount centre")
						end
						if m.align == "bottom" and not m.hat and centre.Y - ext.Y / 2 < m.cf.Position.Y - m.box.Y / 2 - 0.02 then
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

			-- Seat on top of the chassis
			local seat = model:FindFirstChildWhichIsA("VehicleSeat")
			if not seat or seat.Position.Y < chassis.Size.Y / 2 then bad("seat", slots, "seat missing or inside the chassis") end
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
