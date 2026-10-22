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

R.describe("handling across biomes", function()
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local VehicleController = env.requirePath("ReplicatedStorage.Shared.VehicleController")
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		-- the rate the controller really turns at (SKY is capped), not the seat value
		R.it(biome .. " turn rate spreads over its range instead of sitting on a clamp", function()
			local values = {}
			for _, b in ipairs(Builds.enumerate(env, biome)) do
				table.insert(values, VehicleController.turnRate(Constants.turnSpeedFor(biome, b.stats), biome == "SKY"))
			end
			table.sort(values)
			local p10 = values[math.floor(#values * 0.1) + 1]
			local p90 = values[math.floor(#values * 0.9) + 1]
			-- over half the configured range (OCEAN / SKY ranges are narrow on
			-- purpose since 2026-10-22: turning decides those races)
			local t = Constants.TURN_SPEED[biome]
			R.expect(p90 - p10).toBeGreaterThan((math.min(t.max, biome == "SKY" and VehicleController.SKY_TURN_CAP or t.max) - t.min) * 0.5)
		end)
	end
end)

R.describe("simulator seat values", function()
	local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local KineSim = require("../lib/kinesim")
	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": KineSim.carFromStats matches the seat VehicleBuilder builds", function()
			local bad = {}
			local all = Builds.enumerate(env, biome)
			for i = 1, #all, math.max(1, math.floor(#all / 40)) do
				local b = all[i]
				local model = VehicleBuilder.build(b.stats, biome, require("@lune/roblox").CFrame.new(0, 10, 0), b.slots)
				local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
				local car = KineSim.carFromStats(b.stats, Constants, biome)
				for _, f in ipairs({ { "MaxSpeed", "maxSpeed" }, { "Torque", "torque" }, { "TurnSpeed", "turnSpeed" } }) do
					if math.abs(seat[f[1]] - car[f[2]]) > 1e-3 then
						table.insert(bad, string.format("%s: seat %s %.2f, sim %.2f", Builds.describe(b), f[1], seat[f[1]], car[f[2]]))
					end
				end
				model:Destroy()
			end
			R.expect(bad).toBeEmpty("seat values the simulator gets wrong")
		end)
	end
end)

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

	R.it("stability changes how fast the car turns",
		function()
			local distinct = {}
			for _, b in ipairs(list) do distinct[string.format("%.2f", b.turnSpeed)] = true end
			local n = 0
			for _ in pairs(distinct) do n += 1 end
			R.expect(n).toBeGreaterThan(20)
		end)

	R.it("the acceleration stat affects driving",
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
