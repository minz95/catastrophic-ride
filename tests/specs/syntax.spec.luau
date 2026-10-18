--!nocheck
-- Every Luau source in the game and plugin must compile.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local R = require("../lib/runner")

local function walk(dir, out)
	for _, name in ipairs(fs.readDir(dir)) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			walk(p, out)
		elseif name:match("%.luau?$") then
			table.insert(out, p)
		end
	end
	return out
end

R.describe("syntax", function()
	R.it("every .lua/.luau file under roblox/ and studio-plugin/ compiles", function()
		local bad = {}
		local files = walk("roblox", {})
		walk("studio-plugin", files)
		for _, path in ipairs(files) do
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				table.insert(bad, path .. ": " .. tostring(err):match("syntax error:[^\n]*") or tostring(err))
			end
		end
		R.expect(bad).toBeEmpty("files that do not compile")
		R.expect(#files).toBeGreaterThan(40)
	end)
end)
