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
			physics = {}, welds = {}, size = {}, ends = {}, ground = {}, symmetry = {}, fit = {}, seat = {}, headtail = {},
		}
		local function bad(kind, slots, msg)
			if #problems[kind] < 6 then table.insert(problems[kind], label(slots) .. ": " .. msg) end
		end

		for _, slots in ipairs(BUILDS) do
			local stats = statsFor(slots, biome)
			local model = VehicleBuilder.build(stats, biome, CFrame.new(), slots)
			local chassis = model.PrimaryPart
			local design = VehicleDesign.layout(biome, stats)
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
			for _, n in ipairs(ENDS[biome].front) do
				local p = byName[n]
				if not p then bad("ends", slots, "missing " .. n)
				elseif p.Position.Z > -chassis.Size.Z * 0.3 then bad("ends", slots, n .. " is not at the front") end
			end
			for _, n in ipairs(ENDS[biome].back) do
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
						if (centre - m.cf.Position).Magnitude > 0.02 then
							bad("fit", slots, slot .. " " .. slots[slot] .. " off its mount centre")
						end
					end
				end
			end
			if slots.HEAD and holders.HEAD and VehicleBuilder.bounds(holders.HEAD[1]).Z > 0 then
				bad("headtail", slots, "HEAD item behind the centre")
			end
			if slots.TAIL and holders.TAIL and VehicleBuilder.bounds(holders.TAIL[1]).Z < 0 then
				bad("headtail", slots, "TAIL item in front of the centre")
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
		R.it("HEAD item at the front, TAIL item at the back", function()
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
		R.it("has a seat on top of the chassis", function()
			R.expect(problems.seat).toBeEmpty("seat problems")
		end)
	end)
end
