--!nocheck
-- tests/run.luau — offline test suite (no Roblox Studio needed).
--
--   lune run tests/run.luau            # everything
--   lune run tests/run.luau map        # only spec files whose name contains "map"
--
-- Run from the repository root. Exit code 1 when a test fails or when a test
-- marked `known` (documented bug) unexpectedly passes.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local R = require("./lib/runner")

local filter = process.args[1]
local files = {}
for _, f in ipairs(fs.readDir("tests/specs")) do
	if f:match("%.spec%.luau$") and (not filter or f:find(filter, 1, true)) then
		table.insert(files, f)
	end
end
table.sort(files)

local started = os.clock()
for _, f in ipairs(files) do
	print("\n▸ " .. f)
	local ok, err = pcall(function()
		require("./specs/" .. f:gsub("%.luau$", ""))
	end)
	if not ok then
		local res = R.results()
		res.failed += 1
		table.insert(res.failures, { name = f .. " (load)", err = tostring(err) })
		print("  ✗ failed to load: " .. tostring(err):sub(1, 400))
	end
end

local res = R.results()
print(string.rep("─", 72))
for _, f in ipairs(res.failures) do
	print("✗ " .. f.name)
	print("  " .. tostring(f.err):gsub("\n", "\n  "):sub(1, 2500))
end
if #res.knownList > 0 then
	print(string.format("\nKnown bugs still present (%d) — documented, not failing the run:", #res.knownList))
	for _, k in ipairs(res.knownList) do
		print("  ~ " .. k.name)
		print("      " .. k.why)
	end
end
print(string.format("\n%d passed, %d failed, %d known bugs, %d known bugs now passing  (%.1fs)",
	res.passed, res.failed, res.known, res.fixed, os.clock() - started))

fs.writeDir("tests/out")
fs.writeFile("tests/out/results.json", serde.encode("json", {
	passed = res.passed, failed = res.failed, known = res.known, fixed = res.fixed,
	failures = res.failures, knownBugs = res.knownList,
}, true))

process.exit((res.failed > 0 or res.fixed > 0) and 1 or 0)
