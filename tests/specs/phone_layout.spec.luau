--!nocheck
-- Touch buttons on phone and tablet screens (Shared/TouchLayout, drawn by
-- TouchControls): on the screen, under the top bar, big enough for a
-- thumb, clear of each other, of Roblox's jump button, of the side where
-- its thumbstick starts and of the race position list.
-- Launch check 2026-10-30: with six racers listed, SKY's ▲ / ▼ moved left
-- of the list into the thumbstick's side of a phone.
local R = require("../lib/runner")
local P = require("../lib/phonelayout")

R.describe("touch buttons on phones and tablets", function()
	for _, s in ipairs(P.SCREENS) do
		R.it(string.format("%s (%d × %d): every phase and biome", s.name, s.w, s.h), function()
			local bad = {}
			for _, c in ipairs(P.cases(s.w, s.h)) do
				for _, p in ipairs((P.problems(s.w, s.h, c))) do
					table.insert(bad, c.label .. ": " .. p)
				end
			end
			R.expect(bad).toBeEmpty("touch layout problems")
		end)
	end
end)
