--!nocheck
-- phonelayout.luau — the touch buttons (Shared/TouchLayout) on phone and
-- tablet screens against Roblox's own jump button and thumbstick area.
-- Used by tests/specs/phone_layout and tools/phone_layout.luau.
local Loader = require("./loader")

local env = Loader.boot({ quiet = true })
local TouchLayout = env.requirePath("ReplicatedStorage.Shared.TouchLayout")

local M = {}

M.SCREENS = {
	{ name = "iPhone SE", w = 667, h = 375 },
	{ name = "Android small", w = 740, h = 360 },
	{ name = "iPhone 13 mini", w = 812, h = 375 },
	{ name = "iPhone 14", w = 844, h = 390 },
	{ name = "iPhone Pro Max", w = 932, h = 430 },
	{ name = "iPad", w = 1024, h = 768 },
	{ name = "iPad Air", w = 1180, h = 820 },
}
M.INSET = 58        -- Roblox's top bar
M.MIN_TOUCH = TouchLayout.MIN_TOUCH   -- px: smaller is hard to hit with a thumb (Apple asks 44)

-- The HUD's race position list (HUD PositionTracker, IgnoreGuiInset: 160
-- wide at (1, -180), 20 down, rows of 20 + 2, 6 px padding) for n racers.
function M.positionList(w, n, h)
	if h and math.min(w, h) <= 500 then n = math.min(n, 4) end   -- HUD COMPACT_ROWS on a phone
	local hgt = n * 22 + 10
	return { left = w - 180, bottom = 20 + hgt, box = { w - 180, 20, 160, hgt } }
end

-- Every case a phone shows: FARMING with / without a gadget, RACING on each
-- biome with / without a race trick, with no list and with a full grid.
function M.cases(w, h)
	local out = {}
	for _, gadget in ipairs({ false, true }) do
		table.insert(out, { phase = "FARMING", label = gadget and "FARMING + gadget" or "FARMING",
			vis = function(b) return not b.gadget or gadget end })
	end
	for _, biome in ipairs({ "FOREST", "SKY" }) do
		for _, trick in ipairs({ false, true }) do
			for _, n in ipairs({ 0, 6, 10 }) do
				table.insert(out, {
					phase = "RACING", list = n > 0 and M.positionList(w, n, h) or nil,
					label = string.format("RACING %s%s%s", biome, trick and " + trick" or "", n > 0 and (" + list of " .. n) or ""),
					vis = function(b)
						return (not b.biome or b.biome == biome) and (b.attr ~= "RaceTrick" or trick)
					end,
				})
			end
		end
	end
	return out
end

local function overlap(a, b, min)
	min = min or 1
	local ox = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1])
	local oy = math.min(a[2] + a[4], b[2] + b[4]) - math.max(a[2], b[2])
	return ox >= min and oy >= min
end
M.overlap = overlap

-- Problems for one screen and case: { "text" }.
function M.problems(w, h, case)
	local r = TouchLayout.compute(w, h, case.phase, case.vis, case.list)
	local zones = TouchLayout.robloxZones(w, h, M.INSET)
	local bad = {}
	local shown = {}
	for _, rb in ipairs(r.buttons) do
		if rb.visible then table.insert(shown, rb) end
	end
	if case.phase == "FARMING" then
		local b = TouchLayout.bag(w, h, r.frame[1])
		local box = { b.x, b.y, b.w, b.h }
		if b.cell < M.MIN_TOUCH then table.insert(bad, string.format("bag slots only %d px", b.cell)) end
		if overlap(box, zones.thumbstick) then table.insert(bad, "bag in the thumbstick area") end
		if overlap(box, zones.jump) then table.insert(bad, "bag on the jump button") end
		for _, rb in ipairs(shown) do
			if overlap(box, rb.box) then table.insert(bad, "bag on " .. rb.b.text) end
		end
	end
	for i, rb in ipairs(shown) do
		local x, y, bw, bh = table.unpack(rb.box)
		local n = rb.b.text
		if x < 0 or x + bw > w or y + bh > h then table.insert(bad, n .. " off the screen") end
		if y < M.INSET then table.insert(bad, n .. " under the top bar") end
		if x < w * 0.5 then table.insert(bad, n .. " in the middle of the screen (over the car)") end
		if bw < M.MIN_TOUCH then table.insert(bad, string.format("%s only %d px", n, bw)) end
		if overlap(rb.box, zones.jump) then table.insert(bad, n .. " on the jump button") end
		if overlap(rb.box, zones.thumbstick) then table.insert(bad, n .. " in the thumbstick area") end
		if case.list and overlap(rb.box, case.list.box) then table.insert(bad, n .. " on the position list") end
		for j = i + 1, #shown do
			if overlap(rb.box, shown[j].box) then table.insert(bad, n .. " on " .. shown[j].b.text) end
		end
	end
	return bad, r
end

M.TouchLayout = TouchLayout

return M
