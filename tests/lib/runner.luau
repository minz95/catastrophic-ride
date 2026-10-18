--!nocheck
-- runner.luau
-- Tiny test framework: describe / it / expect, plus `known` for documented
-- bugs that are not fixed yet.
--
--   it("name", fn)        → must pass
--   known("name", why, fn)→ expected to FAIL today. If it starts passing the
--                           run fails, so the marker gets removed with the fix.

local Runner = {}

local results = { passed = 0, failed = 0, known = 0, fixed = 0, failures = {}, knownList = {} }
local stack = {}

local function fullName(name)
	local parts = table.clone(stack)
	table.insert(parts, name)
	return table.concat(parts, " › ")
end

function Runner.describe(name, fn)
	table.insert(stack, name)
	fn()
	table.remove(stack)
end

local function format(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s, got %s", format(expected), format(actual)), 2)
		end
	end
	function e.toBeTruthy(msg)
		if not actual then
			error(msg or ("expected truthy, got " .. format(actual)), 2)
		end
	end
	function e.toBeFalsy(msg)
		if actual then
			error(msg or ("expected falsy, got " .. format(actual)), 2)
		end
	end
	function e.toBeNear(expected, tol)
		tol = tol or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tol then
			error(string.format("expected %s ± %s, got %s", format(expected), format(tol), format(actual)), 2)
		end
	end
	function e.toBeGreaterThan(n)
		if not (actual > n) then
			error(string.format("expected > %s, got %s", format(n), format(actual)), 2)
		end
	end
	function e.toBeLessThan(n)
		if not (actual < n) then
			error(string.format("expected < %s, got %s", format(n), format(actual)), 2)
		end
	end
	function e.toBeAtMost(n)
		if not (actual <= n) then
			error(string.format("expected <= %s, got %s", format(n), format(actual)), 2)
		end
	end
	function e.toBeAtLeast(n)
		if not (actual >= n) then
			error(string.format("expected >= %s, got %s", format(n), format(actual)), 2)
		end
	end
	--- Asserts an empty list; prints each offending entry on failure.
	function e.toBeEmpty(label)
		if #actual > 0 then
			local lines = {}
			for i, v in ipairs(actual) do
				if i > 25 then
					table.insert(lines, string.format("    … and %d more", #actual - 25))
					break
				end
				table.insert(lines, "    - " .. tostring(v))
			end
			error(string.format("%s (%d):\n%s", label or "expected no entries", #actual, table.concat(lines, "\n")), 2)
		end
	end
	return e
end

Runner.expect = expect

local function runCase(name, fn)
	local ok, err = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. debug.traceback(nil, 2)
	end)
	return ok, err
end

function Runner.it(name, fn)
	local label = fullName(name)
	local ok, err = runCase(name, fn)
	if ok then
		results.passed += 1
		print("  ✓ " .. label)
	else
		results.failed += 1
		table.insert(results.failures, { name = label, err = err })
		print("  ✗ " .. label)
	end
end

function Runner.known(name, why, fn)
	local label = fullName(name)
	local ok, err = runCase(name, fn)
	if ok then
		results.fixed += 1
		table.insert(results.failures, {
			name = label,
			err = "marked as a known bug but now PASSES — the bug looks fixed, change `known` to `it`.\n  reason was: " .. why,
		})
		print("  ! " .. label .. "  (known bug now passes)")
	else
		results.known += 1
		local firstLine = tostring(err):match("^[^\n]*") or ""
		local detail = tostring(err):match("^(.-)\nstack traceback") or tostring(err)
		table.insert(results.knownList, { name = label, why = why, detail = detail })
		print("  ~ " .. label .. "  [known bug] " .. firstLine:sub(1, 140))
	end
end

function Runner.results()
	return results
end

return Runner
