-- VehicleDesign.lua
-- The look of each vehicle as data: a car (FOREST), a boat (OCEAN) and a
-- plane (SKY), sized from the vehicle stats. VehicleBuilder turns the layout
-- into parts; tests/specs/vehicle_design checks it (front at -Z, symmetric,
-- inside the grid slot, nothing under the ground or the hull).
--
-- Conventions
--   * Everything is relative to the physics chassis centre; -Z is the front
--     (the chassis LookVector, the way the vehicle drives).
--   * `chassis` is the only part with mass and collision. Its size comes from
--     the same stat formulas as before, so the look never changes handling;
--     every other part is decoration (massless, no collision).
--   * Items go into `mounts`: a box per slot in the place that matches the
--     slot's role (BODY = cabin / deckhouse / dorsal hump, ENGINE = engine
--     bay / outboard / nose, MOBILITY = hubcaps / masthead / wing pods,
--     SPECIAL = roof rack / foredeck / belly, HEAD = front, TAIL = back).
--     An item is scaled to fit its box, keeping its proportions.
--   * Parts listed in `replacedBy[slot]` are left out when that slot has an
--     item (the cabin when a BODY item takes its place, for example).
--   * You ride your BODY item: with one, `ride` takes over. The chassis turns
--     invisible, the body parts in `ride.hide` go, and the item is stretched
--     over the whole footprint (`ride.box`, bottom at `ride.bottom`, raised
--     so its top is at least the chassis top) — a pizza on wheels, a bathtub
--     boat, a flying sofa. What says car / boat / plane stays: wheels,
--     outboard motor and mast, wings / propeller / tail. Mounts and parts
--     marked `onRide` / listed in `ride.lift` sit on the item's real top,
--     which VehicleBuilder measures once the item is placed.
--
-- part = { name, shape = "block" | "wedge" | "cylinder" | "ball",
--          size = Vector3, cf = CFrame, color = role or Color3,
--          material = Enum.Material?, transparency = number? }
-- Cylinders run along their local X axis (Roblox); WedgePart slopes face -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local VehicleDesign = {}

local V3, CF = Vector3.new, CFrame.new
local ANG = CFrame.Angles
local HALF_PI = math.pi / 2

-- Widest any vehicle may be: start-grid columns are 7 studs apart.
VehicleDesign.MAX_WIDTH = 6.6
VehicleDesign.MAX_LENGTH = 10

VehicleDesign.PALETTE = {
	FOREST = { body = Color3.fromRGB(196, 72, 52), accent = Color3.fromRGB(235, 190, 70) },
	OCEAN  = { body = Color3.fromRGB(245, 245, 240), accent = Color3.fromRGB(40, 110, 185) },
	SKY    = { body = Color3.fromRGB(235, 225, 250), accent = Color3.fromRGB(120, 90, 230) },
}

VehicleDesign.COLORS = {
	trim      = Color3.fromRGB(55, 55, 60),
	glass     = Color3.fromRGB(150, 200, 230),
	tire      = Color3.fromRGB(30, 30, 32),
	hub       = Color3.fromRGB(190, 190, 195),
	headlight = Color3.fromRGB(255, 244, 200),
	taillight = Color3.fromRGB(230, 40, 40),
	wood      = Color3.fromRGB(175, 130, 85),
	sail      = Color3.fromRGB(250, 248, 235),
	mast      = Color3.fromRGB(120, 85, 55),
	metal     = Color3.fromRGB(160, 165, 175),
	nav_red   = Color3.fromRGB(230, 40, 40),
	nav_green = Color3.fromRGB(40, 200, 80),
}

local function statScale(val, lo, hi)
	local t = math.clamp((val or 0) / Constants.BALANCE.STAT_BUDGET, 0, 1)
	return lo + t * (hi - lo)
end
VehicleDesign.statScale = statScale

local function add(list, name, shape, size, cf, color, material, transparency)
	local p = { name = name, shape = shape, size = size, cf = cf, color = color,
		material = material, transparency = transparency }
	table.insert(list, p)
	return p
end

-- Adds a left/right pair; `cfAt(side)` gets side = -1 (left, -X) or 1 (right).
local function pair(list, name, shape, size, cfAt, color, material, transparency)
	add(list, name .. "L", shape, size, cfAt(-1), color, material, transparency)
	add(list, name .. "R", shape, size, cfAt(1), color, material, transparency)
end

-- ─── FOREST: car ─────────────────────────────────────────────────────────────

local function car(stats)
	local L = statScale(stats.stability, 3.0, 5.5)
	local W = statScale(stats.stability, 2.0, 3.2)
	local H = 1.2
	local top = H / 2
	local r = statScale(stats.stability, 0.5, 0.7)
	local d = { chassis = { size = V3(W, H, L), color = "body" }, parts = {}, mounts = {}, replacedBy = {} }
	local P = d.parts
	-- Ride height: the hover keeps the chassis bottom 0.2 above the ground,
	-- so wheels reach 0.2 below it.
	local wheelY = -H / 2 - 0.2 + r
	local wheelZ = L / 2 - r - 0.15
	local wheelX = W / 2 - 0.1
	for _, fz in ipairs({ -1, 1 }) do
		local tag = fz < 0 and "Front" or "Rear"
		pair(P, "Wheel" .. tag, "cylinder", V3(0.45, r * 2, r * 2),
			function(s) return CF(s * wheelX, wheelY, fz * wheelZ) end, "tire")
		pair(P, "Hub" .. tag, "cylinder", V3(0.08, r * 1.1, r * 1.1),
			function(s) return CF(s * (wheelX + 0.25), wheelY, fz * wheelZ) end, "hub", Enum.Material.Metal)
		-- Arch over each wheel
		pair(P, "Fender" .. tag, "block", V3(0.3, 0.25, r * 2.3),
			function(s) return CF(s * (W / 2 + 0.05), top - 0.05, fz * wheelZ) end, "body")
	end
	-- Bumpers, grille, lights (front is -Z)
	add(P, "BumperFront", "block", V3(W + 0.1, 0.35, 0.3), CF(0, -H / 2 + 0.3, -L / 2 - 0.12), "trim")
	add(P, "BumperRear", "block", V3(W + 0.1, 0.35, 0.3), CF(0, -H / 2 + 0.3, L / 2 + 0.12), "trim")
	add(P, "Grille", "block", V3(W * 0.4, 0.3, 0.06), CF(0, 0.1, -L / 2 - 0.03), "trim")
	pair(P, "Headlight", "block", V3(W * 0.2, 0.22, 0.08),
		function(s) return CF(s * W * 0.33, 0.12, -L / 2 - 0.04) end, "headlight", Enum.Material.Neon)
	pair(P, "Taillight", "block", V3(W * 0.2, 0.18, 0.08),
		function(s) return CF(s * W * 0.33, 0.15, L / 2 + 0.04) end, "taillight", Enum.Material.Neon)
	-- Hood line and the greenhouse: windshield, cabin, rear window
	local cabW, cabH = W * 0.86, 0.75
	local cabL = L * 0.36
	local cabZ = L * 0.08
	add(P, "Windshield", "wedge", V3(cabW, cabH, 0.55), CF(0, top + cabH / 2, cabZ - cabL / 2 - 0.275), "glass",
		Enum.Material.Glass, 0.35)
	add(P, "Cabin", "block", V3(cabW, cabH, cabL), CF(0, top + cabH / 2, cabZ), "accent")
	add(P, "RearWindow", "wedge", V3(cabW, cabH, 0.45), CF(0, top + cabH / 2, cabZ + cabL / 2 + 0.225) * ANG(0, math.pi, 0),
		"glass", Enum.Material.Glass, 0.35)
	pair(P, "SideWindow", "block", V3(0.05, cabH * 0.6, cabL * 0.8),
		function(s) return CF(s * (cabW / 2 + 0.02), top + cabH * 0.55, cabZ) end, "glass", Enum.Material.Glass, 0.35)
	add(P, "Roof", "block", V3(cabW + 0.08, 0.1, cabL + 0.1), CF(0, top + cabH + 0.05, cabZ), "body")
	d.replacedBy.BODY = { "Windshield", "Cabin", "RearWindow", "SideWindowL", "SideWindowR", "Roof" }
	-- Rear spoiler on fast builds
	if (stats.speed or 0) > Constants.BALANCE.STAT_BUDGET * 0.5 then
		pair(P, "SpoilerStrut", "block", V3(0.12, 0.4, 0.12),
			function(s) return CF(s * W * 0.3, top + 0.2, L / 2 - 0.25) end, "trim")
		add(P, "Spoiler", "block", V3(W * 0.9, 0.1, 0.45), CF(0, top + 0.42, L / 2 - 0.25), "accent")
	end
	-- Exhaust pipes
	pair(P, "Exhaust", "cylinder", V3(0.4, 0.18, 0.18),
		function(s) return CF(s * W * 0.25, -H / 2 + 0.15, L / 2 + 0.2) * ANG(0, HALF_PI, 0) end, "metal", Enum.Material.Metal)

	local M = d.mounts
	M.BODY = { { cf = CF(0, top + 0.55, cabZ), box = V3(cabW, 1.1, cabL + 0.9) } }
	M.ENGINE = { { cf = CF(0, top + 0.35, -L / 2 + L * 0.17), box = V3(W * 0.55, 0.7, L * 0.3) } }
	M.SPECIAL = { { cf = CF(0, top + 1.45, cabZ), box = V3(W * 0.6, 0.7, cabL * 0.8) } }
	M.MOBILITY = {}
	for _, fz in ipairs({ -1, 1 }) do
		for _, s in ipairs({ -1, 1 }) do
			table.insert(M.MOBILITY, { cf = CF(s * (wheelX + 0.35), wheelY, fz * wheelZ), box = V3(0.3, r * 1.3, r * 1.3) })
		end
	end
	M.HEAD = { { cf = CF(0, top + 0.3, -L / 2 + 0.25), box = V3(0.6, 0.6, 0.5) } }
	M.TAIL = { { cf = CF(0, -H / 2 + 0.4, L / 2 + 0.55), box = V3(0.8, 0.8, 0.6) } }
	d.seat = { size = V3(1.4, 0.3, 1.4), cf = CF(0, top + 0.15, cabZ) }
	-- Riding the BODY item: it sits on the axles, wheels stay
	d.ride = {
		hide = { "FenderFrontL", "FenderFrontR", "FenderRearL", "FenderRearR", "BumperFront", "BumperRear", "Grille",
			"HeadlightL", "HeadlightR", "TaillightL", "TaillightR", "Windshield", "Cabin", "RearWindow",
			"SideWindowL", "SideWindowR", "Roof", "SpoilerStrutL", "SpoilerStrutR", "Spoiler" },
		box = V3(W + 0.3, 2.2, L + 0.5), bottom = wheelY + r * 0.4, centreZ = 0,
		mounts = {
			ENGINE = { { cf = CF(0, 0.35, L * 0.32), box = V3(W * 0.5, 0.7, L * 0.25), onRide = true } },
			SPECIAL = { { cf = CF(0, 0.3, -L * 0.3), box = V3(W * 0.5, 0.6, L * 0.22), onRide = true } },
			HEAD = { { cf = CF(0, 0.3, -L / 2 + 0.25), box = V3(0.6, 0.6, 0.5), onRide = true } },
		},
		seatZ = cabZ,
	}
	return d
end

-- ─── OCEAN: boat ─────────────────────────────────────────────────────────────

local function boat(stats)
	local L = statScale(stats.floatability, 4.0, 7.0)
	local W = statScale(stats.floatability, 2.0, 3.4)
	local H = 0.9
	local top = H / 2
	local prow = W * 0.9
	local d = { chassis = { size = V3(W, H, L), color = "body" }, parts = {}, mounts = {}, replacedBy = {} }
	local P = d.parts
	-- Pointed prow: two wedges laid on their side make a V in plan view
	pair(P, "Prow", "wedge", V3(H, W / 2, prow),
		function(s) return CF(s * W / 4, 0, -L / 2 - prow / 2) * ANG(0, 0, -s * HALF_PI) end, "body")
	-- Waterline stripe, gunwales, deck, transom
	pair(P, "Stripe", "block", V3(0.05, 0.2, L), function(s) return CF(s * (W / 2 + 0.02), -0.05, 0) end, "accent")
	pair(P, "Gunwale", "block", V3(0.15, 0.18, L + 0.1), function(s) return CF(s * (W / 2 - 0.05), top + 0.09, 0) end, "wood",
		Enum.Material.Wood)
	local edge = math.sqrt(prow * prow + (W / 2) ^ 2)
	local yaw = math.atan2(W / 2, prow)
	pair(P, "BowRail", "block", V3(0.15, 0.18, edge),
		function(s) return CF(s * W / 4, top + 0.09, -L / 2 - prow / 2) * ANG(0, s * yaw, 0) end, "wood", Enum.Material.Wood)
	add(P, "Deck", "block", V3(W - 0.3, 0.08, L - 0.2), CF(0, top + 0.04, 0), "wood", Enum.Material.WoodPlanks)
	add(P, "Transom", "block", V3(W, H, 0.12), CF(0, 0, L / 2 + 0.06), "accent")
	pair(P, "NavLight", "ball", V3(0.22, 0.22, 0.22),
		function(s) return CF(s * (W / 2 - 0.05), top + 0.3, -L / 2 + 0.2) end, "trim", Enum.Material.Neon)
	P[#P - 1].color, P[#P].color = "nav_red", "nav_green"
	-- Deckhouse with a windscreen (a BODY item takes its place)
	local houseL, houseW = L * 0.32, W * 0.72
	local houseZ = L * 0.12
	add(P, "Cabin", "block", V3(houseW, 0.8, houseL), CF(0, top + 0.08 + 0.4, houseZ), "accent")
	add(P, "Windscreen", "wedge", V3(houseW, 0.55, 0.45), CF(0, top + 0.08 + 0.8 + 0.275, houseZ - houseL / 2 + 0.25), "glass",
		Enum.Material.Glass, 0.35)
	d.replacedBy.BODY = { "Cabin", "Windscreen" }
	-- Outboard motor at the stern (an ENGINE item takes the motor's place)
	add(P, "MotorLeg", "block", V3(0.18, 1.0, 0.18), CF(0, -0.2, L / 2 + 0.4), "trim")
	add(P, "Motor", "block", V3(0.55, 0.6, 0.6), CF(0, top + 0.2, L / 2 + 0.4), "trim")
	d.replacedBy.ENGINE = { "Motor" }
	-- Mast and sail only with a MOBILITY item (it rides at the masthead)
	local mastH = statScale(stats.floatability, 3.0, 4.5)
	local mastZ = -L * 0.12
	d.withSlot = { MOBILITY = { "Mast", "Sail", "Boom" } }
	add(P, "Mast", "cylinder", V3(mastH, 0.14, 0.14), CF(0, top + mastH / 2, mastZ) * ANG(0, 0, HALF_PI), "mast",
		Enum.Material.Wood)
	add(P, "Sail", "wedge", V3(0.06, mastH * 0.8, L * 0.42), CF(0, top + 0.35 + mastH * 0.4, mastZ + L * 0.21 + 0.08) * ANG(0, math.pi, 0), "sail",
		Enum.Material.Fabric)
	add(P, "Boom", "cylinder", V3(L * 0.45, 0.1, 0.1), CF(0, top + 0.3, mastZ + L * 0.22) * ANG(0, HALF_PI, 0), "mast",
		Enum.Material.Wood)

	local M = d.mounts
	M.BODY = { { cf = CF(0, top + 0.08 + 0.6, houseZ), box = V3(houseW, 1.2, houseL + 0.4) } }
	M.ENGINE = { { cf = CF(0, top + 0.3, L / 2 + 0.45), box = V3(0.8, 0.9, 0.8) } }
	M.SPECIAL = { { cf = CF(0, top + 0.4, -L * 0.3), box = V3(W * 0.5, 0.7, L * 0.2) } }
	M.MOBILITY = { { cf = CF(0, top + mastH + 0.4, mastZ), box = V3(0.9, 0.9, 0.9) } }
	M.HEAD = { { cf = CF(0, top + 0.35, -L / 2 - prow + 0.35), box = V3(0.6, 0.6, 0.6) } }
	M.TAIL = { { cf = CF(W / 2 - 0.3, top + 1.4, L / 2 - 0.2), box = V3(0.6, 0.6, 0.6) } }
	add(P, "FlagPole", "cylinder", V3(1.3, 0.07, 0.07), CF(W / 2 - 0.3, top + 0.65, L / 2 - 0.2) * ANG(0, 0, HALF_PI), "mast")
	d.withSlot.TAIL = { "FlagPole" }
	d.seat = { size = V3(1.4, 0.3, 1.4), cf = CF(0, top + 0.15, L * 0.28) }
	-- Riding the BODY item: it floats on the water, motor and mast stay
	d.ride = {
		hide = { "ProwL", "ProwR", "StripeL", "StripeR", "GunwaleL", "GunwaleR", "BowRailL", "BowRailR", "Deck", "Transom",
			"NavLightL", "NavLightR", "Cabin", "Windscreen" },
		box = V3(W + 0.3, 1.9, L + prow * 0.6), bottom = -H / 2 + 0.05, centreZ = -prow * 0.3,
		lift = { "Mast", "Sail", "Boom", "FlagPole" }, liftFrom = top,
		mounts = {
			SPECIAL = { { cf = CF(0, 0.3, -L * 0.3), box = V3(W * 0.5, 0.6, L * 0.2), onRide = true } },
			MOBILITY = { { cf = CF(0, mastH + 0.4, mastZ), box = V3(0.9, 0.9, 0.9), onRide = true } },
			HEAD = { { cf = CF(0, 0.3, -L / 2 - prow * 0.4), box = V3(0.6, 0.6, 0.6), onRide = true } },
			TAIL = { { cf = CF(W / 2 - 0.3, 1.4, L / 2 - 0.2), box = V3(0.6, 0.6, 0.6), onRide = true } },
		},
		seatZ = L * 0.15,
	}
	return d
end

-- ─── SKY: plane ──────────────────────────────────────────────────────────────

local function plane(stats)
	local L = statScale(stats.flyability, 3.5, 6.0)
	local R = statScale(stats.flyability, 0.45, 0.75)
	local span = math.min(statScale(stats.flyability, 4.5, 7.5), VehicleDesign.MAX_WIDTH)
	local chord = statScale(stats.flyability, 1.1, 1.6)
	local d = { chassis = { size = V3(R * 2, R * 2, L), color = "body" }, parts = {}, mounts = {}, replacedBy = {} }
	local P = d.parts
	-- Nose: cowl, spinner, two-blade propeller
	add(P, "Cowl", "block", V3(R * 1.9, R * 1.9, 0.5), CF(0, 0, -L / 2 - 0.25), "accent")
	d.replacedBy.ENGINE = { "Cowl" }
	add(P, "Spinner", "cylinder", V3(0.45, R * 1.0, R * 1.0), CF(0, 0, -L / 2 - 0.72) * ANG(0, HALF_PI, 0), "metal",
		Enum.Material.Metal)
	add(P, "PropBlade1", "block", V3(0.18, R * 3.6, 0.06), CF(0, 0, -L / 2 - 0.98) * ANG(0, 0, math.rad(45)), "trim")
	add(P, "PropBlade2", "block", V3(0.18, R * 3.6, 0.06), CF(0, 0, -L / 2 - 0.98) * ANG(0, 0, math.rad(-45)), "trim")
	-- Tail cone tapering up to the fin
	add(P, "TailCone", "wedge", V3(R * 2, R * 2, 1.2), CF(0, 0, L / 2 + 0.6) * ANG(math.pi, 0, 0), "body")
	-- Canopy
	add(P, "Canopy", "wedge", V3(R * 1.3, R * 0.9, 0.9), CF(0, R + R * 0.45, -L * 0.18), "glass", Enum.Material.Glass, 0.3)
	add(P, "CanopyBack", "block", V3(R * 1.3, R * 0.9, 0.7), CF(0, R + R * 0.45, -L * 0.18 + 0.8), "glass", Enum.Material.Glass, 0.3)
	-- Main wing (low), wing tips with nav lights
	add(P, "Wing", "block", V3(span, 0.16, chord), CF(0, -R * 0.35, -L * 0.04), "accent")
	pair(P, "WingTip", "block", V3(0.3, 0.2, chord * 0.7),
		function(s) return CF(s * (span / 2 - 0.15), -R * 0.35 + 0.02, -L * 0.04 + 0.05) end, "body")
	pair(P, "NavLight", "ball", V3(0.2, 0.2, 0.2),
		function(s) return CF(s * (span / 2 - 0.05), -R * 0.35 + 0.15, -L * 0.04 - chord / 2 + 0.15) end, "trim", Enum.Material.Neon)
	P[#P - 1].color, P[#P].color = "nav_red", "nav_green"
	-- Tailplane and fin
	add(P, "Stabilizer", "block", V3(span * 0.38, 0.12, 0.75), CF(0, R * 0.4, L / 2 + 0.75), "accent")
	add(P, "Fin", "wedge", V3(0.12, R * 1.8, 1.0), CF(0, R + R * 0.9, L / 2 + 0.6), "accent")
	-- Fixed landing gear
	pair(P, "GearLeg", "block", V3(0.1, 0.5, 0.1),
		function(s) return CF(s * span * 0.18, -R * 0.35 - 0.3, -L * 0.04) end, "trim")
	pair(P, "GearWheel", "cylinder", V3(0.15, 0.4, 0.4),
		function(s) return CF(s * span * 0.18, -R * 0.35 - 0.55, -L * 0.04) end, "tire")

	local M = d.mounts
	M.BODY = { { cf = CF(0, R + 0.45, L * 0.18), box = V3(R * 1.8, 0.9, L * 0.4) } }
	M.ENGINE = { { cf = CF(0, 0, -L / 2 - 0.3), box = V3(R * 2.1, R * 2.1, 0.6) } }
	M.SPECIAL = { { cf = CF(0, -R - 0.35, L * 0.08), box = V3(R * 1.6, 0.7, L * 0.3) } }
	M.MOBILITY = {}
	for _, s in ipairs({ -1, 1 }) do
		table.insert(M.MOBILITY, { cf = CF(s * span * 0.32, -R * 0.35 - 0.4, -L * 0.04), box = V3(0.6, 0.6, 1.0) })
	end
	M.HEAD = { { cf = CF(0, R + 0.3, -L / 2 + 0.3), box = V3(0.6, 0.6, 0.5) } }
	M.TAIL = { { cf = CF(0, R + R * 1.8 + 0.35, L / 2 + 0.7), box = V3(0.6, 0.6, 0.6) } }
	d.seat = { size = V3(1.2, 0.3, 1.2), cf = CF(0, R + 0.15, -L * 0.05) }
	-- Riding the BODY item: it is the fuselage, wings / prop / tail stay
	d.ride = {
		hide = { "Cowl", "TailCone", "Canopy", "CanopyBack" },
		box = V3(R * 3.2, R * 3.0, L + 1.0), bottom = -R * 1.2, centreZ = 0,
		lift = { "Fin", "Stabilizer" }, liftFrom = R,
		mounts = {
			HEAD = { { cf = CF(0, 0.3, -L / 2 + 0.3), box = V3(0.6, 0.6, 0.5), onRide = true } },
			TAIL = { { cf = CF(0, R * 1.8 + 0.35, L / 2 + 0.7), box = V3(0.6, 0.6, 0.6), onRide = true } },
		},
		seatZ = -L * 0.05,
	}
	return d
end

--- Layout for a biome's vehicle sized by `stats`. With a BODY item in
-- `slots` the vehicle is that item (`d.riding`, see the header).
function VehicleDesign.layout(biome, stats, slots)
	stats = stats or {}
	local d
	if biome == "OCEAN" then d = boat(stats)
	elseif biome == "SKY" then d = plane(stats)
	else d = car(stats) end
	d.biome = biome
	d.palette = VehicleDesign.PALETTE[biome] or VehicleDesign.PALETTE.FOREST
	d.withSlot = d.withSlot or {}
	if slots and slots.BODY and d.ride then
		local ride = d.ride
		d.riding = true
		local hide = {}
		for _, n in ipairs(ride.hide) do hide[n] = true end
		local keep = {}
		for _, p in ipairs(d.parts) do
			if not hide[p.name] then table.insert(keep, p) end
		end
		d.parts = keep
		d.replacedBy.BODY = nil
		local lift = {}
		for _, n in ipairs(ride.lift or {}) do lift[n] = true end
		for _, p in ipairs(d.parts) do
			if lift[p.name] then p.lift = true end
		end
		d.mounts.BODY = { { cf = CF(0, ride.bottom + ride.box.Y / 2, ride.centreZ), box = ride.box, align = "bottom",
			stretch = VehicleDesign.RIDE_STRETCH, orient = true } }
		for slot, list in pairs(ride.mounts) do d.mounts[slot] = list end
	end
	return d
end

-- How far a ridden item may be stretched beyond its own proportions along
-- one axis to fill the vehicle's footprint.
VehicleDesign.RIDE_STRETCH = 1.4

--- Colour for a part's role.
function VehicleDesign.color(d, role)
	if typeof(role) == "Color3" then return role end
	return d.palette[role] or VehicleDesign.COLORS[role] or Color3.fromRGB(180, 180, 180)
end

--- Parts to build for these slots (drops replaced parts and parts that only
-- exist with an item in some slot).
function VehicleDesign.partsFor(d, slots)
	local skip = {}
	for slot, names in pairs(d.replacedBy) do
		if slots[slot] then for _, n in ipairs(names) do skip[n] = true end end
	end
	for slot, names in pairs(d.withSlot) do
		if not slots[slot] then for _, n in ipairs(names) do skip[n] = true end end
	end
	local out = {}
	for _, p in ipairs(d.parts) do
		if not skip[p.name] then table.insert(out, p) end
	end
	return out
end

return VehicleDesign
