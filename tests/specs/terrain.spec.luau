--!nocheck
-- Decorative terrain (Modules/TerrainPlan + TerrainPainter).
--
-- Studio run (2026-10-20): the old MapBuilders/TerrainPainter repainted on
-- every map model it saw, so the last-built biome's terrain covered all three
-- maps (an OCEAN race ran on FOREST hills), and hills laid out for the old
-- straight tracks stood in the lanes: OCEAN boats stopped against a FOREST
-- hill at s≈490.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")

local env = Loader.boot()
local TerrainPlan = env.requirePath("ServerScriptService.Modules.TerrainPlan")
local TrackGeometry = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")

-- Independent of TerrainPlan.clearOf: horizontal distance from (x, z) to the
-- nearest centerline segment.
local function distToCenterline(nodes, x, z)
	local best = math.huge
	for i = 1, #nodes - 1 do
		local ax, az, bx, bz = nodes[i][1], nodes[i][2], nodes[i + 1][1], nodes[i + 1][2]
		local dx, dz = bx - ax, bz - az
		local t = math.clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1)
		local px, pz = ax + dx * t - x, az + dz * t - z
		best = math.min(best, math.sqrt(px * px + pz * pz))
	end
	return best
end

for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	R.describe(biome .. " terrain plan", function()
		local ops, track = TerrainPlan.build(biome)

		R.it("has decorations", function()
			R.expect(#ops > 0).toBe(true)
		end)

		R.it("is deterministic", function()
			local again = TerrainPlan.build(biome)
			R.expect(#again).toBe(#ops)
			R.expect(again[1].cx).toBe(ops[1].cx)
		end)

		R.it("keeps every fill out of the corridor above the driving surface", function()
			local bad = {}
			local floorY = TerrainPlan.floorY(track)
			local half = track.width / 2 + (track.wallThickness or 2)
			for i, op in ipairs(ops) do
				local top = op.kind == "ball" and op.cy + op.r or op.cy + op.sy / 2
				local reach = op.kind == "ball" and op.r or math.max(op.sx, op.sz) / 2
				local d = distToCenterline(track.nodes, op.cx, op.cz)
				if top > floorY and d < half + reach then
					table.insert(bad, string.format("#%d %s %s at (%.0f, %.0f, %.0f) top %.1f, %.0f studs from centerline",
						i, op.kind, op.material, op.cx, op.cy, op.cz, top, d))
				end
			end
			R.expect(bad).toBeEmpty("terrain in the lane or walls")
		end)
	end)
end

R.describe("terrain follows the played biome", function()
	for _, biome in ipairs({ "OCEAN", "SKY" }) do
		R.it("MapManager paints " .. biome .. " when a round on it starts", function()
			local srv = Server.boot({
				players = 2,
				harness = { harness = "lune", biome = biome, players = 2, lobbyDelay = 0,
					durations = { FARMING = 60, CRAFTING = 5, RACING = 600 } },
			})
			srv.advance(1)
			local painter = srv.env.requirePath("ServerScriptService.Modules.TerrainPainter")
			R.expect(painter.current()).toBe(biome)
		end)
	end

	R.it("the old paint-on-every-map script is gone", function()
		local ok, inst = pcall(env.find, "ServerScriptService.MapBuilders.TerrainPainter")
		R.expect(ok and inst ~= nil).toBe(false)
	end)
end)

R.describe("OCEAN water is Terrain water (playtest: the parts read as flat blue)", function()
	local water, look = TerrainPlan.water("OCEAN")
	local track = env.requirePath("ReplicatedStorage.Shared.Tracks.OceanTrack")
	R.it("covers every track node, from the sea floor up to the surface", function()
		R.expect(#water > 0).toBe(true)
		R.expect(look and look.WaterTransparency ~= nil).toBe(true)
		local missing = {}
		for i, n in ipairs(track.nodes) do
			local inside = false
			for _, op in ipairs(water) do
				if math.abs(n[1] - op.cx) <= op.sx / 2 and math.abs(n[2] - op.cz) <= op.sz / 2 then inside = true end
			end
			if not inside then table.insert(missing, i) end
		end
		R.expect(missing).toBeEmpty("nodes outside the water")
		for _, op in ipairs(water) do
			R.expect(op.material).toBe("Water")
			R.expect(op.cy + op.sy / 2).toBeNear(track.trackTop, 1e-6)
		end
	end)
	R.it("no water in FOREST or SKY", function()
		R.expect(#TerrainPlan.water("FOREST")).toBe(0)
		R.expect(#TerrainPlan.water("SKY")).toBe(0)
	end)
	R.it("race rays ignore it (it is not ground)", function()
		local fs = require("@lune/fs")
		for _, f in ipairs({
			"roblox/ServerScriptService/Modules/RaceBots.lua",
			"roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua",
			"roblox/ServerScriptService/TestHarness/RaceSim.lua",
		}) do
			R.expect(fs.readFile(f):find("IgnoreWater = true", 1, true) ~= nil).toBe(true)
		end
	end)
end)

local _ = TrackGeometry
