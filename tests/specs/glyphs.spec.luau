--!nocheck
-- Every symbol a player can see is in Roblox's fonts (Gotham = Montserrat,
-- plus the Twemoji emoji font): "✕" close buttons and a "⟲" reset icon drew
-- empty boxes, and Studio's own fallback font (Noto CJK) hid others that a
-- phone would show as boxes (Studio Device Simulator, 2026-10-30).
-- tests/glyphs.txt lists the symbols checked against the font files; a new
-- one: run `python3 tools/glyph_check.py --write` (needs Roblox Studio).
local R = require("../lib/runner")
local fs = require("@lune/fs")

local DIRS = { "roblox/StarterGui", "roblox/StarterPlayer", "roblox/ReplicatedStorage" }
local FILES = { "roblox/ServerScriptService/Modules/AbilityConfig.lua", "roblox/ServerScriptService/Modules/ItemConfig.lua" }

local function walk(dir, out)
	for _, name in ipairs(fs.readDir(dir)) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then walk(p, out) elseif p:match("%.lua$") then table.insert(out, p) end
	end
	return out
end

R.describe("symbols on screen", function()
	R.it("are all in Montserrat or Twemoji (tests/glyphs.txt)", function()
		local allowed = {}
		for _, c in utf8.codes(fs.readFile("tests/glyphs.txt")) do allowed[c] = true end
		local files = table.clone(FILES)
		for _, d in ipairs(DIRS) do walk(d, files) end
		local bad = {}
		for _, f in ipairs(files) do
			for line in fs.readFile(f):gmatch("[^\n]+") do
				if not line:match("^%s*%-%-") then
					local code = line:match("^(.-)%-%-") or line
					for str in code:gmatch('"([^"]*)"') do
						for _, c in utf8.codes(str) do
							if c > 0x7F and c ~= 0xFE0F and c ~= 0x200D and not allowed[c] then
								table.insert(bad, string.format("%s U+%04X in %s", utf8.char(c), c, f))
							end
						end
					end
				end
			end
		end
		R.expect(bad).toBeEmpty("symbols not checked against Roblox's fonts")
	end)
end)
