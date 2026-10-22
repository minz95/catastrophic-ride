--!nocheck
-- Client UI scripts, checked on their sources (they do not run under Lune).
--
-- History (2026-10-22): StarterGui scripts run again after every respawn,
-- and a ScreenGui with ResetOnSpawn = false survives it, so each respawn
-- added another copy: Studio bots showed two or three crafting timers at
-- once, the older ones frozen. FarmingUI already removed its old copy.
local fs = require("@lune/fs")
local R = require("../lib/runner")

local SOURCES = {}
for _, name in ipairs(fs.readDir("roblox/StarterGui")) do
	local p = "roblox/StarterGui/" .. name .. "/init.client.lua"
	if fs.isFile(p) then SOURCES[name] = fs.readFile(p) end
end

R.describe("StarterGui screens", function()
	R.it("a screen that survives respawns removes its old copy first", function()
		local bad = {}
		for name, src in pairs(SOURCES) do
			if src:find("ResetOnSpawn%s*=%s*false") then
				local guiName = src:match('%.Name%s*=%s*"([%w_]+)"')
				if not src:find('old.Name == "' .. tostring(guiName) .. '"', 1, true) then
					table.insert(bad, name)
				end
			end
		end
		table.sort(bad)
		R.expect(bad).toBeEmpty("screens that pile up on respawn")
	end)
end)

-- Player-facing text is English (2026-10-22). Comments may be in any language.
R.describe("player-facing text", function()
	R.it("no Korean in strings shown to players", function()
		local bad = {}
		local function scan(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local p = dir .. "/" .. name
				if fs.isDir(p) then
					scan(p)
				elseif p:match("%.lua$") then
					local n = 0
					for line in fs.readFile(p):gmatch("[^\n]*") do
						n += 1
						local code = line:gsub("%-%-.*$", "")
						-- Hangul syllables are U+AC00..U+D7A3: UTF-8 lead bytes EA..ED
						if code:find("[\234-\237][\128-\191][\128-\191]") then
							table.insert(bad, p .. ":" .. n)
						end
					end
				end
			end
		end
		scan("roblox")
		R.expect(bad).toBeEmpty("lines with Korean text")
	end)
end)
