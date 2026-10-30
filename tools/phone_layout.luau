--!nocheck
-- tools/phone_layout.luau — the touch buttons (Shared/TouchLayout) on phone
-- and tablet screens, with Roblox's own jump button and thumbstick area.
--
--   lune run tools/phone_layout.luau          # problems per screen
--   lune run tools/phone_layout.luau --json   # boxes, for ui_overlap.py --phone
--
-- Screens are in points (Roblox's ViewportSize on a device), landscape.
local serde = require("@lune/serde")
local process = require("@lune/process")
local M = require("../tests/lib/phonelayout")
local TouchLayout = M.TouchLayout

if process.args[1] == "--json" then
	local out = {}
	for _, s in ipairs(M.SCREENS) do
		for _, c in ipairs(M.cases(s.w, s.h)) do
			local _, r = M.problems(s.w, s.h, c)
			local buttons = {}
			for _, rb in ipairs(r.buttons) do
				if rb.visible then table.insert(buttons, { name = rb.b.text, box = rb.box }) end
			end
			table.insert(out, { screen = s.name, w = s.w, h = s.h, phase = c.phase, label = c.label,
				buttons = buttons, zones = TouchLayout.robloxZones(s.w, s.h, M.INSET) })
		end
	end
	print(serde.encode("json", out))
else
	local total = 0
	for _, s in ipairs(M.SCREENS) do
		print(string.format("\n%s (%d × %d)", s.name, s.w, s.h))
		for _, c in ipairs(M.cases(s.w, s.h)) do
			local bad, r = M.problems(s.w, s.h, c)
			total += #bad
			print(string.format("  %-32s scale %.2f  %s", c.label, r.scale, #bad == 0 and "ok" or table.concat(bad, "; ")))
		end
	end
	print(string.format("\n%d problems", total))
end

