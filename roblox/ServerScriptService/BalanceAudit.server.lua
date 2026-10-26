-- BalanceAudit.server.lua
-- Runs at server start in SOLO_TEST_MODE to print a full stat matrix.
-- Checks for outliers and logs warnings for combinations that are too strong/weak.
-- Resolves: Issue #61

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)

-- Only run in test mode
if not Constants.SOLO_TEST_MODE then return end
-- Disabled: too noisy during active debugging; remove the line below to re-enable.
do return end

-- ─── Collect items by slot ────────────────────────────────────────────────────

local bodyItems    = {}
local engineItems  = {}
local specialItems = {}

for name, cfg in pairs(ItemConfig) do
	if type(cfg) == "table" and cfg.slotType then
		if cfg.slotType == "BODY"    then bodyItems[name]    = cfg end
		if cfg.slotType == "ENGINE"  then engineItems[name]  = cfg end
		if cfg.slotType == "SPECIAL" then specialItems[name] = cfg end
	end
end

-- ─── Audit thresholds ────────────────────────────────────────────────────────

local WARN_SPEED_HIGH  = 55    -- speed above this is a concern
local WARN_SPEED_LOW   = 10    -- speed below this is a concern
local WARN_ACCEL_HIGH  = 35
local WARN_ACCEL_LOW   = 3
local WARN_BOOST_HIGH  = 7.5   -- seconds
local BUDGET           = Constants.BALANCE.STAT_BUDGET

-- ─── Run audit for one biome ──────────────────────────────────────────────────

local function _auditBiome(biome)
	local results   = {}
	local warnings  = {}

	for bName, bCfg in pairs(bodyItems) do
		for eName, eCfg in pairs(engineItems) do
			for sName, sCfg in pairs(specialItems) do
				local ok, stats = pcall(function()
					return VehicleStats.calculate(bCfg, eCfg, sCfg, biome)
				end)
				if not ok then
					table.insert(warnings, string.format(
						"[ERROR] %s + %s + %s: %s", bName, eName, sName, tostring(stats)))
					continue
				end

				-- Apply default mobility (nil = penalty)
				local mobileStats = VehicleStats.applyMobility(stats, nil, biome)

				local combo = {
					body    = bName, engine = eName, special = sName,
					speed   = mobileStats.speed,
					accel   = mobileStats.acceleration,
					stab    = mobileStats.stability,
					boost   = mobileStats.boostDuration,
				}
				table.insert(results, combo)

				-- Warn on outliers
				if mobileStats.speed > WARN_SPEED_HIGH then
					table.insert(warnings, string.format(
						"[HIGH SPEED] %s+%s+%s → speed=%.1f (biome=%s)",
						bName, eName, sName, mobileStats.speed, biome))
				end
				if mobileStats.speed < WARN_SPEED_LOW then
					table.insert(warnings, string.format(
						"[LOW SPEED]  %s+%s+%s → speed=%.1f (biome=%s)",
						bName, eName, sName, mobileStats.speed, biome))
				end
				if mobileStats.acceleration > WARN_ACCEL_HIGH then
					table.insert(warnings, string.format(
						"[HIGH ACCEL] %s+%s+%s → accel=%.1f (biome=%s)",
						bName, eName, sName, mobileStats.acceleration, biome))
				end
				if mobileStats.boostDuration > WARN_BOOST_HIGH then
					table.insert(warnings, string.format(
						"[HIGH BOOST] %s+%s+%s → boost=%.1fs (biome=%s)",
						bName, eName, sName, mobileStats.boostDuration, biome))
				end
			end
		end
	end

	-- Sort by speed desc
	table.sort(results, function(a, b) return a.speed > b.speed end)

	-- Print top 5 and bottom 5
	print(string.format("\n═══ BALANCE AUDIT: %s (%d combos) ═══", biome, #results))

	print("  TOP 5 fastest:")
	for i = 1, math.min(5, #results) do
		local r = results[i]
		print(string.format("    #%d  %-18s + %-14s + %-14s  | spd=%.1f  acc=%.1f  boost=%.1fs",
			i, r.body, r.engine, r.special, r.speed, r.accel, r.boost))
	end

	print("  BOTTOM 5 slowest:")
	for i = math.max(1, #results - 4), #results do
		local r = results[i]
		print(string.format("    #%-3d %-18s + %-14s + %-14s  | spd=%.1f  acc=%.1f  boost=%.1fs",
			i, r.body, r.engine, r.special, r.speed, r.accel, r.boost))
	end

	-- Speed range
	if #results > 0 then
		local fastest = results[1].speed
		local slowest = results[#results].speed
		local ratio   = fastest / math.max(slowest, 0.1)
		print(string.format("  Speed range: %.1f – %.1f  (ratio: %.2fx)", slowest, fastest, ratio))
		if ratio > 4 then
			table.insert(warnings, string.format(
				"[RANGE] %s speed ratio %.2fx may feel unfair", biome, ratio))
		end
	end

	if #warnings > 0 then
		print(string.format("  ⚠  %d warnings:", #warnings))
		for _, w in ipairs(warnings) do
			print("    " .. w)
		end
	else
		print("  ✓ No outliers detected")
	end

	return results, warnings
end

-- ─── Audit all biomes ────────────────────────────────────────────────────────

task.defer(function()
	print("\n╔══════════════════════════════════════╗")
	print("║   CATASTROPHIC RIDE — BALANCE AUDIT  ║")
	print("╚══════════════════════════════════════╝")

	local allWarnings = {}
	for _, biome in ipairs(Constants.BIOMES) do
		local _, warnings = _auditBiome(biome)
		for _, w in ipairs(warnings) do
			table.insert(allWarnings, w)
		end
	end

	-- Epic-only audit: best Epic combinations per biome
	print("\n═══ EPIC COMBINATIONS ═══")
	for _, biome in ipairs(Constants.BIOMES) do
		print("  " .. biome .. ":")
		local best = nil
		local bestSpeed = 0
		for bName, bCfg in pairs(bodyItems) do
			if bCfg.rarity == "Epic" then
				for eName, eCfg in pairs(engineItems) do
					if eCfg.rarity == "Epic" then
						for sName, sCfg in pairs(specialItems) do
							if sCfg.rarity == "Epic" then
								local ok, stats = pcall(VehicleStats.calculate, bCfg, eCfg, sCfg, biome)
								if ok and stats.speed > bestSpeed then
									bestSpeed = stats.speed
									best = { bName, eName, sName, stats }
								end
							end
						end
					end
				end
			end
		end
		if best then
			local s = best[4]
			print(string.format("    %s + %s + %s → spd=%.1f acc=%.1f stab=%.1f boost=%.1fs",
				best[1], best[2], best[3], s.speed, s.acceleration, s.stability, s.boostDuration))
		else
			print("    (no full Epic combo available)")
		end
	end

	-- Summary
	print(string.format("\n  Total warnings: %d", #allWarnings))
	if #allWarnings == 0 then
		print("  ✓ Balance audit passed!")
	end
	print("═══════════════════════════════════════\n")
end)
