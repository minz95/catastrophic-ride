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
--     bay / outboard / nose, MOBILITY = the wheels / side paddle wheels /
--     wing propellers (copies of the item that spin, see SPIN),
--     SPECIAL = roof rack / foredeck / belly, HEAD = the rider's hat (see
--     HAT), TAIL = back).
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
--     which VehicleBuilder measures once the item is placed. The box is at
--     least RIDE_MIN; `ride.move` puts parts at its edges, and `ride.fit`
--     (VehicleDesign.fitRide) moves the wheels, paddle wheels and propellers
--     against the item's real size once it is placed.
--   * A mount or part with `spin` turns on every client (StarterPlayerScripts/SpinFx):
--     its copies are welded to an invisible hub joined to the chassis by a
--     Motor6D. `flat` = the axis the item is laid thin along (a wheel's
--     side, a propeller's face).
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

-- Smallest box a ridden item is stretched over (studs): an avatar sitting on
-- it is about 2 wide and 3.5 tall, and hid a smaller item (Studio gallery,
-- 2026-10-24). Decoration only: the chassis, and so the handling, is unchanged.
-- How some items are ridden (Studio gallery checks): `yaw` (degrees) fixes
-- which way the item faces instead of the best-fit turn (the model's -Z is
-- the front), `tip` lays it on its side first (a roll rides like a log),
-- `sink` lowers the seat by that share of the item's height (sit in the
-- tub, on the cushions), `stretch` overrides RIDE_STRETCH.
VehicleDesign.RIDE_LOOK = {
	["Red Sofa"]      = { yaw = 0, sink = 0.42, stretch = 2.2 },   -- backrest at the back
	["Bathtub"]       = { sink = 0.4 },
	["Shopping Cart"] = { yaw = 180, sink = 0.35 },                -- handle at the back
	["Toilet Paper"]  = { yaw = 0, tip = true },
	["Kite"]          = { yaw = 0, tip = true },                   -- flat, a flying carpet (stood on its edge)
	["Treadmill"]     = { stretch = 2.0 },                         -- narrow: the rider hid it
}

-- Playtest 2026-10-28: still too small next to the rider (and a plane's
-- wings outshone it): "the item is pasted on the default car". Bigger now.
VehicleDesign.RIDE_MIN = {
	FOREST = Vector3.new(4.2, 0, 6.0),
	OCEAN  = Vector3.new(4.0, 0, 6.2),
	SKY    = Vector3.new(3.6, 2.4, 5.8),
}

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
	-- the plain wheels roll too (SpinFx), each with its hubcap
	for _, p in ipairs(P) do
		local side = p.name:match("^Wheel(%a+)$") or p.name:match("^Hub(%a+)$")
		if side then p.spin = { axis = "X", mode = "wheel", radius = r, group = side } end
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
	-- MOBILITY: the item is the wheels (four spinning copies in their place)
	-- (flush with the outer side: a flat item is a thin wheel, and centred
	-- it would hide inside the body)
	local function wheelMount(x, z)
		return { cf = CF(x, wheelY, z), box = V3(VehicleDesign.WHEEL_WIDTH, r * 2, r * 2), flat = "X", stretch = 1.8,
			side = x < 0 and -1 or 1, spin = { axis = "X", mode = "wheel", radius = r } }
	end
	M.MOBILITY = {}
	for _, fz in ipairs({ -1, 1 }) do
		for _, s in ipairs({ -1, 1 }) do table.insert(M.MOBILITY, wheelMount(s * wheelX, fz * wheelZ)) end
	end
	d.replacedBy.MOBILITY = { "WheelFrontL", "WheelFrontR", "WheelRearL", "WheelRearR",
		"HubFrontL", "HubFrontR", "HubRearL", "HubRearR" }
	-- axles out to the item wheels (a kite or a flag makes a very thin wheel)
	for _, fz in ipairs({ -1, 1 }) do
		add(P, "Axle" .. (fz < 0 and "Front" or "Rear"), "cylinder",
			V3((wheelX + VehicleDesign.WHEEL_WIDTH / 2 - 0.05) * 2, 0.22, 0.22), CF(0, wheelY, fz * wheelZ), "trim", Enum.Material.Metal)
	end
	d.withSlot = { MOBILITY = { "AxleFront", "AxleRear" } }
	M.TAIL = { { cf = CF(0, -H / 2 + 0.4, L / 2 + 0.55), box = V3(0.8, 0.8, 0.6) } }
	d.seat = { size = V3(1.4, 0.3, 1.4), cf = CF(0, top + 0.15, cabZ) }
	-- Riding the BODY item: it sits on the axles, the wheels move out to its
	-- corners. At least RIDE_MIN big, so the rider does not hide it.
	local rideW = math.max(W + 0.3, VehicleDesign.RIDE_MIN.FOREST.X)
	local rideL = math.max(L + 0.5, VehicleDesign.RIDE_MIN.FOREST.Z)
	local rwX, rwZ = rideW / 2 - 0.2, rideL / 2 - r - 0.2
	local move = {}
	for _, fz in ipairs({ -1, 1 }) do
		local tag = fz < 0 and "Front" or "Rear"
		for _, s in ipairs({ -1, 1 }) do
			local side = s < 0 and "L" or "R"
			move["Wheel" .. tag .. side] = CF(s * rwX, wheelY, fz * rwZ)
			move["Hub" .. tag .. side] = CF(s * (rwX + 0.25), wheelY, fz * rwZ)
		end
	end
	local rideMob = {}
	for _, fz in ipairs({ -1, 1 }) do
		for _, s in ipairs({ -1, 1 }) do table.insert(rideMob, wheelMount(s * rwX, fz * rwZ)) end
	end
	-- Once the item is placed (lo / hi = its real box): the wheels go against
	-- its sides, front and rear ends; axles join each pair under it, and a
	-- post joins an axle to the item when the item sits higher.
	local function fit(dd, lo, hi)
		local halfW = math.max(-lo.X, hi.X)
		local wx = math.min(halfW + 0.1, VehicleDesign.MAX_WIDTH / 2 - VehicleDesign.WHEEL_WIDTH / 2 - 0.05)
		dd.withSlot.MOBILITY = nil   -- a ridden car always has its axles (added below)
		local reach = L * 0.3 + 0.05   -- the axles stay this far from the centre
		local zs = { [-1] = math.min(lo.Z + r + 0.15, -reach), [1] = math.max(hi.Z - r - 0.15, reach) }
		local at = {}
		local k = 0
		for _, fz in ipairs({ -1, 1 }) do
			local tag = fz < 0 and "Front" or "Rear"
			for _, s in ipairs({ -1, 1 }) do
				local side = s < 0 and "L" or "R"
				at["Wheel" .. tag .. side] = CF(s * wx, wheelY, zs[fz])
				at["Hub" .. tag .. side] = CF(s * (wx + 0.25), wheelY, zs[fz])
				k += 1
				if dd.mounts.MOBILITY[k] then dd.mounts.MOBILITY[k] = wheelMount(s * wx, zs[fz]) end
			end
			-- out to just inside the wheels' outer faces (a thin item wheel too)
			local axleHalf = wx + VehicleDesign.WHEEL_WIDTH / 2 - 0.05
			add(dd.parts, "Axle" .. tag, "cylinder", V3(axleHalf * 2, 0.22, 0.22), CF(0, wheelY, zs[fz]), "trim", Enum.Material.Metal)
			local gap = lo.Y - (wheelY + 0.11)
			if gap > 0.02 then
				add(dd.parts, "Post" .. tag, "block", V3(0.3, gap + 0.2, 0.3), CF(0, wheelY + 0.11 + gap / 2, zs[fz]), "trim",
					Enum.Material.Metal)
			end
		end
		for _, p in ipairs(dd.parts) do
			if at[p.name] then p.cf = at[p.name] end
		end
	end
	d.ride = {
		hide = { "FenderFrontL", "FenderFrontR", "FenderRearL", "FenderRearR", "BumperFront", "BumperRear", "Grille",
			"HeadlightL", "HeadlightR", "TaillightL", "TaillightR", "Windshield", "Cabin", "RearWindow",
			"SideWindowL", "SideWindowR", "Roof", "SpoilerStrutL", "SpoilerStrutR", "Spoiler", "ExhaustL", "ExhaustR",
			"AxleFront", "AxleRear" },   -- (fit adds its own)
		box = V3(rideW, 2.2, rideL), bottom = wheelY + r * 0.4, centreZ = 0,
		move = move,
		mounts = {
			ENGINE = { { cf = CF(0, 0.35, rideL * 0.32), box = V3(rideW * 0.45, 0.7, rideL * 0.22), onRide = true } },
			SPECIAL = { { cf = CF(0, 0.3, -rideL * 0.3), box = V3(rideW * 0.45, 0.6, rideL * 0.2), onRide = true } },
			MOBILITY = rideMob,
		},
		fit = fit,
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
	-- Below the chassis down into the water: a boat races with its chassis
	-- held over the water (WATERLINE), and the hull alone looked to float
	local skirt = -H / 2 - (VehicleDesign.WATERLINE - VehicleDesign.DRAFT)
	add(P, "Keel", "block", V3(W, skirt, L), CF(0, -H / 2 - skirt / 2, 0), "body")
	pair(P, "ProwSkirt", "wedge", V3(skirt, W / 2, prow),
		function(s) return CF(s * W / 4, -H / 2 - skirt / 2, -L / 2 - prow / 2) * ANG(0, 0, -s * HALF_PI) end, "body")
	add(P, "TransomSkirt", "block", V3(W, skirt, 0.12), CF(0, -H / 2 - skirt / 2, L / 2 + 0.06), "accent")
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
	-- the leg reaches into the water (the motor sits on top of it)
	local legTop, legBottom = top - 0.1, VehicleDesign.WATERLINE - VehicleDesign.DRAFT
	-- (right behind the transom: it holds the motor or an ENGINE item there)
	add(P, "MotorLeg", "block", V3(0.18, legTop - legBottom, 0.18), CF(0, (legTop + legBottom) / 2, L / 2 + 0.2), "trim")
	add(P, "Motor", "block", V3(0.55, 0.6, 0.6), CF(0, top + 0.2, L / 2 + 0.4), "trim")
	d.replacedBy.ENGINE = { "Motor" }
	-- Mast near the bow and a mainsail: its tall edge on the mast, the foot
	-- on the boom running back, ending before the deckhouse (it used to cut
	-- through the cabin and the rider). Sheeted out SHEET degrees to
	-- starboard so a chaser sees it, not just its edge.
	local mastH = statScale(stats.floatability, 3.0, 4.5)
	local mastZ = -L / 2 + 0.35
	local sailL = math.min(L * 0.42, houseZ - houseL / 2 - 0.2 - mastZ)
	d.withSlot = {}
	local function rig(z, len)
		local turn = CF(0, 0, z) * ANG(0, math.rad(VehicleDesign.SHEET), 0)
		return {
			Mast = CF(0, top + mastH / 2, z) * ANG(0, 0, HALF_PI),
			Sail = turn * CF(0, top + 0.35 + mastH * 0.4, len / 2 + 0.08) * ANG(0, math.pi, 0),
			Boom = turn * CF(0, top + 0.3, len / 2 + 0.05) * ANG(0, HALF_PI, 0),
		}
	end
	local at = rig(mastZ, sailL)
	add(P, "Mast", "cylinder", V3(mastH, 0.14, 0.14), at.Mast, "mast", Enum.Material.Wood)
	-- smooth: Fabric showed as a dark triangle on the shaded side (Studio gallery)
	add(P, "Sail", "wedge", V3(0.06, mastH * 0.8, sailL), at.Sail, "sail", Enum.Material.SmoothPlastic)
	add(P, "Boom", "cylinder", V3(sailL + 0.1, 0.1, 0.1), at.Boom, "mast", Enum.Material.Wood)
	-- MOBILITY: side paddle wheels, like a river steamer: on each side
	-- PADDLES copies of the item round a hub, turning (the hubs show only then)
	local rp = VehicleDesign.PADDLE_RADIUS
	local wheelY = VehicleDesign.WATERLINE - VehicleDesign.DRAFT + rp   -- the paddles dip into the water
	local function paddles(x, z)
		local list = {}
		for _, s in ipairs({ -1, 1 }) do
			local hub = CF(s * x, wheelY, z)
			for k = 0, VehicleDesign.PADDLES - 1 do
				table.insert(list, { cf = hub * ANG(k * 2 * math.pi / VehicleDesign.PADDLES, 0, 0) * CF(0, rp * 0.5, 0),
					box = V3(0.6, rp, 0.4), flat = "Z", stretch = 1.5, align = "bottom",   -- out from the hub
					spin = { axis = "X", mode = "wheel", radius = rp, hub = hub, group = s < 0 and "PaddleL" or "PaddleR" } })
			end
		end
		return list
	end
	local function paddleHubs(x, z)
		return {
			PaddleHubL = CF(-(x - 0.25), wheelY, z) * ANG(0, 0, 0),
			PaddleHubR = CF(x - 0.25, wheelY, z),
		}
	end
	local paddleX, paddleZ = W / 2 + 0.3, -L * 0.08
	pair(P, "PaddleHub", "cylinder", V3(0.8, 0.35, 0.35), function(s) return CF(s * (paddleX - 0.25), wheelY, paddleZ) end,
		"trim", Enum.Material.Metal)
	d.withSlot.MOBILITY = { "PaddleHubL", "PaddleHubR" }

	local M = d.mounts
	M.BODY = { { cf = CF(0, top + 0.08 + 0.6, houseZ), box = V3(houseW, 1.2, houseL + 0.4) } }
	-- on the stern, standing on the motor leg (centred, a thin item floated off it)
	M.ENGINE = { { cf = CF(0, top + 0.3, L / 2 + 0.45), box = V3(0.8, 0.9, 0.8), align = "bottom", front = true } }
	M.SPECIAL = { { cf = CF(0, top + 0.4, -L * 0.3), box = V3(W * 0.5, 0.7, L * 0.2) } }
	M.MOBILITY = paddles(paddleX, paddleZ)
	M.TAIL = { { cf = CF(W / 2 - 0.3, top + 1.4, L / 2 - 0.2), box = V3(0.6, 0.6, 0.6) } }
	add(P, "FlagPole", "cylinder", V3(1.3, 0.07, 0.07), CF(W / 2 - 0.3, top + 0.65, L / 2 - 0.2) * ANG(0, 0, HALF_PI), "mast")
	d.withSlot.TAIL = { "FlagPole" }
	d.seat = { size = V3(1.4, 0.3, 1.4), cf = CF(0, top + 0.15, L * 0.28) }
	-- Riding the BODY item: it floats on the water, motor and mast stay. The
	-- mast moves to the bow so the rider does not hide the sail.
	local rideL = math.max(L + prow * 0.6, VehicleDesign.RIDE_MIN.OCEAN.Z)
	local bowMast = -prow * 0.3 - rideL / 2 + 0.7
	local rideRig = rig(bowMast, sailL)
	-- once placed: the paddle wheels against the item's sides, by the rider
	local function fit(dd, lo, hi)
		local halfW = math.max(-lo.X, hi.X)
		local x = math.min(halfW + 0.3, VehicleDesign.MAX_WIDTH / 2 - 0.3)
		local z = (lo.Z + hi.Z) / 2 - (hi.Z - lo.Z) * 0.1
		if dd.mounts.MOBILITY and #dd.mounts.MOBILITY > 0 then dd.mounts.MOBILITY = paddles(x, z) end
		local at = paddleHubs(x, z)
		for _, p in ipairs(dd.parts) do
			if at[p.name] then p.cf = at[p.name] end
		end
		-- the outboard motor (or the ENGINE item in its place) on the item's
		-- back end and the flag on its back corner: they stood where the hull
		-- ended and floated behind a shorter item
		local motorZ = hi.Z + 0.25
		local fx = math.min(W / 2 - 0.3, halfW - 0.3)
		local fz = hi.Z - 0.35
		for _, p in ipairs(dd.parts) do
			if p.name == "Motor" then p.cf = CF(0, top + 0.2, motorZ)
			elseif p.name == "MotorLeg" then p.cf = CF(0, (legTop + legBottom) / 2, hi.Z + 0.1)
			elseif p.name == "FlagPole" then p.cf = CF(fx, top + 0.65, fz) * ANG(0, 0, HALF_PI) end
		end
		dd.mounts.ENGINE = { { cf = CF(0, top + 0.3, hi.Z + 0.35), box = V3(0.8, 0.9, 0.8), align = "bottom", front = true } }
		dd.mounts.TAIL = { { cf = CF(fx, 1.4, fz), box = V3(0.6, 0.6, 0.6), onRide = true } }
		-- a wooden float under the item, down into the water: the item was
		-- lifted to the chassis top and hovered over the water with its rider
		local floatTop = lo.Y + 0.05
		local depth = floatTop - (VehicleDesign.WATERLINE - VehicleDesign.DRAFT)
		if depth > 0.15 then
			add(dd.parts, "Float", "block", V3((hi.X - lo.X) * 0.92, depth, (hi.Z - lo.Z) * 0.9),
				CF((lo.X + hi.X) / 2, floatTop - depth / 2, (lo.Z + hi.Z) / 2), "wood", Enum.Material.WoodPlanks)
		end
	end
	d.ride = {
		hide = { "ProwL", "ProwR", "StripeL", "StripeR", "GunwaleL", "GunwaleR", "BowRailL", "BowRailR", "Deck", "Transom",
			"Keel", "ProwSkirtL", "ProwSkirtR", "TransomSkirt",
			"NavLightL", "NavLightR", "Cabin", "Windscreen" },
		box = V3(math.max(W + 0.3, VehicleDesign.RIDE_MIN.OCEAN.X), 1.9, rideL),
		bottom = -H / 2 + 0.05, centreZ = -prow * 0.3,
		move = rideRig,
		fit = fit,
		lift = { "Mast", "Sail", "Boom", "FlagPole" }, liftFrom = top,
		mounts = {
			SPECIAL = { { cf = CF(0, 0.3, -L * 0.3), box = V3(W * 0.5, 0.6, L * 0.2), onRide = true } },
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
	local d = { chassis = { size = V3(R * 2, R * 2, L), color = "body" }, parts = {}, mounts = {}, replacedBy = {},
		withSlot = {} }
	local P = d.parts
	-- Nose: cowl, spinner, two-blade propeller
	add(P, "Cowl", "block", V3(R * 1.9, R * 1.9, 0.5), CF(0, 0, -L / 2 - 0.25), "accent")
	d.replacedBy.ENGINE = { "Cowl" }
	add(P, "Spinner", "cylinder", V3(0.45, R * 1.0, R * 1.0), CF(0, 0, -L / 2 - 0.72) * ANG(0, HALF_PI, 0), "metal",
		Enum.Material.Metal)
	add(P, "PropBlade1", "block", V3(0.18, R * 3.6, 0.06), CF(0, 0, -L / 2 - 0.98) * ANG(0, 0, math.rad(45)), "trim")
	add(P, "PropBlade2", "block", V3(0.18, R * 3.6, 0.06), CF(0, 0, -L / 2 - 0.98) * ANG(0, 0, math.rad(-45)), "trim")
	for i = #P - 2, #P do P[i].spin = { axis = "Z", mode = "prop", group = "Prop" } end   -- spinner and blades turn
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
	-- MOBILITY: a propeller on each wing, the item spinning face-on in front
	-- of a nacelle (the nacelles show only then)
	local wingY, wingZ = -R * 0.35, -L * 0.04
	local propD = VehicleDesign.PROP_SIZE
	local propZ = wingZ - chord / 2 - 0.45
	local nacL = chord / 2 + 0.45   -- reaches the propeller's centre
	local function props(x)
		local list = {}
		for _, s in ipairs({ -1, 1 }) do
			table.insert(list, { cf = CF(s * x, wingY, propZ), box = V3(propD, propD, 0.35), flat = "Z", stretch = 1.8,
				spin = { axis = "Z", mode = "prop", dir = s } })
		end
		return list
	end
	local propX = span * 0.3
	pair(P, "Nacelle", "cylinder", V3(nacL, 0.42, 0.42), function(s) return CF(s * propX, wingY, wingZ - nacL / 2)
		* ANG(0, HALF_PI, 0) end, "accent")
	d.withSlot.MOBILITY = { "NacelleL", "NacelleR" }
	M.MOBILITY = props(propX)
	M.TAIL = { { cf = CF(0, R + R * 1.8 + 0.35, L / 2 + 0.7), box = V3(0.6, 0.6, 0.6) } }
	d.seat = { size = V3(1.2, 0.3, 1.2), cf = CF(0, R + 0.15, -L * 0.05) }
	-- Riding the BODY item: it is the fuselage, wings / prop / tail stay
	d.ride = {
		hide = { "Cowl", "TailCone", "Canopy", "CanopyBack" },
		box = V3(math.max(R * 3.2, VehicleDesign.RIDE_MIN.SKY.X), math.max(R * 3.0, VehicleDesign.RIDE_MIN.SKY.Y),
			math.max(L + 1.0, VehicleDesign.RIDE_MIN.SKY.Z)), bottom = -R * 1.2, centreZ = 0,
		lift = { "Fin", "Stabilizer" }, liftFrom = R,
		-- the wings and tail stay grey: the purple default wings, wider than
		-- the item, made it look like the default plane with something on it
		recolor = { Wing = "metal", WingTipL = "metal", WingTipR = "metal", Stabilizer = "metal", Fin = "metal",
			NacelleL = "metal", NacelleR = "metal" },
		-- once placed: the wing only a little wider than the item, the
		-- propellers out past the item's sides, on the wing
		fit = function(dd, lo, hi)
			local halfW = math.max(-lo.X, hi.X)
			local rideSpan = math.clamp(2 * halfW + VehicleDesign.RIDE_WING_OVER * 2, 3.4, span)
			for _, p in ipairs(dd.parts) do
				local side = (p.name:sub(-1) == "L") and -1 or 1
				if p.name == "Wing" then
					p.size = V3(rideSpan, p.size.Y, p.size.Z)
				elseif p.name == "WingTipL" or p.name == "WingTipR" then
					p.cf = CF(side * (rideSpan / 2 - 0.15), p.cf.Position.Y, p.cf.Position.Z)
				elseif p.name == "NavLightL" or p.name == "NavLightR" then
					p.cf = CF(side * (rideSpan / 2 - 0.05), p.cf.Position.Y, p.cf.Position.Z)
				elseif p.name == "Stabilizer" then
					p.size = V3(math.min(p.size.X, rideSpan * 0.45), p.size.Y, p.size.Z)
				end
			end
			span = rideSpan
			local x = math.clamp(halfW + propD / 2 + 0.15, math.min(propX, span / 2 - 0.2), span / 2 - 0.2)
			if dd.mounts.MOBILITY and #dd.mounts.MOBILITY > 0 then dd.mounts.MOBILITY = props(x) end
			for _, p in ipairs(dd.parts) do
				if p.name == "NacelleL" or p.name == "NacelleR" then
					local s = p.name == "NacelleL" and -1 or 1
					p.cf = CF(s * x, wingY, wingZ - nacL / 2) * ANG(0, HALF_PI, 0)
				end
			end
		end,
		mounts = {
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
			if ride.move and ride.move[p.name] then p.cf = ride.move[p.name] end
			-- parts that stay (to say plane) but should not outshine the item
			if ride.recolor and ride.recolor[p.name] then p.color = ride.recolor[p.name] end
		end
		local look = VehicleDesign.RIDE_LOOK[slots.BODY] or {}
		d.mounts.BODY = { { cf = CF(0, ride.bottom + ride.box.Y / 2, ride.centreZ), box = ride.box, align = "bottom",
			stretch = look.stretch or VehicleDesign.RIDE_STRETCH, orient = look.yaw == nil, yaw = look.yaw, tip = look.tip,
			sink = look.sink } }
		for slot, list in pairs(ride.mounts) do d.mounts[slot] = list end
	end
	-- HEAD: a hat over the seat (VehicleBuilder puts it on the real seat
	-- height, which a ridden item decides)
	local hat = VehicleDesign.HAT
	local seatTop = d.seat.cf.Position.Y + d.seat.size.Y / 2
	local seatZ = d.riding and d.ride.seatZ or d.seat.cf.Position.Z
	d.mounts.HEAD = { { cf = CF(0, seatTop + hat.headTop - hat.sink + hat.box.Y / 2, seatZ), box = hat.box,
		align = "bottom", hat = true } }
	return d
end

-- The HEAD item is worn as a hat by whoever sits in the seat. The vehicle
-- carries it at about head height above the seat (`headTop` studs above the
-- seat top: a seated R15 avatar, Studio gallery) so an empty seat, a race bot
-- or the showroom still shows it; VehicleBuilder.wearHat moves it onto the
-- real head when someone sits down. `sink` = how far it comes down over
-- the head.
VehicleDesign.HAT = { box = V3(1.7, 1.3, 1.7), headTop = 3.75, sink = 0.25 }

-- A boat races with its chassis centre this far above the water (local Y of
-- the water: BiomeConfig.OCEAN raceStartY 3, waterPlaneY 2; the hover holds
-- it). Hulls, floats, paddles and the motor leg reach DRAFT below it.
VehicleDesign.WATERLINE = -1.0
VehicleDesign.DRAFT = 0.15

-- MOBILITY looks: a car wheel's width, a boat's paddles per wheel and their
-- reach, a plane propeller's size, and how far the sail is sheeted out.
VehicleDesign.WHEEL_WIDTH = 0.7
VehicleDesign.PADDLES = 4
VehicleDesign.PADDLE_RADIUS = 0.8
VehicleDesign.PROP_SIZE = 1.3
VehicleDesign.SHEET = 20

--- Riding: moves the wheels / paddle wheels / propellers (parts and
-- MOBILITY mounts) against the ridden item's real box `lo`..`hi` (chassis
-- space), measured once VehicleBuilder has placed it.
function VehicleDesign.fitRide(d, lo, hi)
	if d.riding and d.ride.fit then d.ride.fit(d, lo, hi) end
end

-- How far a ridden item may be stretched beyond its own proportions along
-- one axis to fill the vehicle's footprint.
VehicleDesign.RIDE_STRETCH = 1.4
-- A ridden plane's wing reaches this far past the item on each side.
VehicleDesign.RIDE_WING_OVER = 1.6

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
