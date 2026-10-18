--!nocheck
-- Vehicle stat balance across every FOREST build, using the real VehicleStats
-- and the seat formulas VehicleBuilder applies.
local fs = require("@lune/fs")
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Builds = require("../lib/builds")

local env = Loader.boot()
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
local list = Builds.enumerate(env, "FOREST")

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

R.describe("vehicle stats (FOREST)", function()
	R.it("every build yields finite stats within the seat clamps", function()
		local bad = {}
		for _, b in ipairs(list) do
			for k, v in pairs(b.stats) do
				if type(v) == "number" and not isFinite(v) then
					table.insert(bad, Builds.describe(b) .. ": " .. k .. "=" .. tostring(v))
				end
			end
			if b.maxSpeed < 20 or b.maxSpeed > 120 then table.insert(bad, Builds.describe(b) .. ": MaxSpeed " .. b.maxSpeed) end
			if not (b.boostDuration > 0 and b.boostDuration <= 8) then table.insert(bad, Builds.describe(b) .. ": boost " .. b.boostDuration) end
		end
		R.expect(bad).toBeEmpty("builds with broken stats")
		R.expect(#list).toBeGreaterThan(1000)
	end)

	R.it("an Epic engine is never slower than a Common engine on the same body", function()
		local bad = {}
		for bname, bcfg in pairs(ItemConfig) do
			if type(bcfg) == "table" and bcfg.slotType == "BODY" then
				local common = VehicleStats.calculate(bcfg, ItemConfig["Flower"], nil, "FOREST")
				local epic = VehicleStats.calculate(bcfg, ItemConfig["Kettle"], nil, "FOREST")
				if epic.speed < common.speed then
					table.insert(bad, string.format("%s: Kettle %.1f < Flower %.1f", bname, epic.speed, common.speed))
				end
			end
		end
		R.expect(bad).toBeEmpty("bodies where the Epic engine is slower")
	end)

	R.known("stability changes how fast the car turns",
		"TurnSpeed = clamp(stability * 0.3, 0.5, 3) hits the 3.0 cap for every build, so BODY grip/weight never changes handling",
		function()
			local distinct = {}
			for _, b in ipairs(list) do distinct[string.format("%.2f", b.turnSpeed)] = true end
			local n = 0
			for _ in pairs(distinct) do n += 1 end
			R.expect(n).toBeGreaterThan(1)
		end)

	R.known("the acceleration stat affects driving",
		"VehicleSeat.Torque is derived from acceleration but the drive code sets velocity directly and never reads it",
		function()
			local readers = {}
			for _, path in ipairs({
				"roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua",
				"roblox/ReplicatedStorage/Shared/VehicleController.lua",
			}) do
				-- Code only: drop `--` comments so documentation does not count.
				local code = fs.readFile(path):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
				if code:find("%.Torque[^%w]") then
					table.insert(readers, path)
				end
			end
			R.expect(#readers).toBeGreaterThan(0)
		end)
end)
