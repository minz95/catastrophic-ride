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
