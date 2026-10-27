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

-- History (playtest 2026-10-28): the crafting screen put any item into Body;
-- the server dropped the ones that do not fit (CraftingRules.validate) and the
-- car kept its plain body: "it goes into Body but the body does not become it".
R.describe("crafting screen slots", function()
	local src = SOURCES.CraftingUI
	R.it("a slot click checks CraftingRules.fits before placing and says why not", function()
		local click = src:sub((src:find("MouseButton1Click:Connect", (src:find("Slot click handlers", 1, true)), true)))
		local check = click:find("CraftingRules.fits(capturedSlot", 1, true)
		local place = click:find("_assignments[capturedSlot] = _selectedItem", 1, true)
		R.expect(check ~= nil and place ~= nil and check < place).toBe(true)
		R.expect(click:find("CraftingRules.whyNot", 1, true) ~= nil).toBe(true)
	end)
	R.it("whyNot explains Body and the core slots in English", function()
		local env = require("../lib/loader").boot()
		local CraftingRules = env.requirePath("ReplicatedStorage.Shared.CraftingRules")
		local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
		R.expect(CraftingRules.whyNot("BODY", "Magnet", ItemConfig.Magnet):find("RIDE", 1, true) ~= nil).toBe(true)
		R.expect(CraftingRules.whyNot("ENGINE", "Log", ItemConfig.Log)).toBe("Log is a BODY item: Engine takes only ENGINE items.")
	end)
end)
