--!nocheck
-- Pure shared modules: TrackGeometry, SpeedModifiers, BotBrain, Telemetry.
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local TG = env.requirePath("ReplicatedStorage.Shared.TrackGeometry")
local SM = env.requirePath("ReplicatedStorage.Shared.SpeedModifiers")
local BotBrain = env.requirePath("ReplicatedStorage.Shared.BotBrain")
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local Telemetry = env.requirePath("ServerScriptService.Modules.Telemetry")

R.describe("TrackGeometry", function()
	-- L-shaped track: 100 studs down -Z, then 100 studs toward +X (a right turn)
	local g = TG.new({ { 0, 0 }, { 0, -100 }, { 100, -100 } }, 20)
	R.it("measures arc length", function()
		R.expect(g.length).toBeNear(200, 1e-9)
	end)
	R.it("projects with signed lateral (+ = right of travel)", function()
		local p = g:project(5, -50)
		R.expect(p.s).toBeNear(50, 1e-9)
		R.expect(p.lateral).toBeNear(5, 1e-9)
		local q = g:project(50, -95)
		R.expect(q.s).toBeNear(150, 1e-9)
		R.expect(q.lateral).toBeNear(5, 1e-9)
	end)
	R.it("reports a right turn as a positive deflection", function()
		R.expect(g:deflections()[1].angle).toBeNear(90, 1e-6)
	end)
	R.it("pointAt and yawAt agree with Roblox LookVector convention", function()
		local x, z, dx, dz = g:pointAt(150)
		R.expect(x).toBeNear(50, 1e-9); R.expect(z).toBeNear(-100, 1e-9)
		local yaw = g:yawAt(150)
		R.expect(-math.sin(yaw)).toBeNear(dx, 1e-9)
		R.expect(-math.cos(yaw)).toBeNear(dz, 1e-9)
	end)
end)

R.describe("SpeedModifiers", function()
	R.it("stacks multiplicatively and returns to base when effects end", function()
		local m = SM.new(60)
		m:set("mud", 0.5)
		m:set("pad", 1.4, 2)
		R.expect(m:value(1)).toBeNear(42, 1e-9)
		R.expect(m:value(2.5)).toBeNear(30, 1e-9)
		m:remove("mud")
		R.expect(m:value(3)).toBe(60)
	end)
	R.it("re-applying an effect replaces it instead of compounding", function()
		local m = SM.new(60)
		m:set("pad", 1.4, 2)
		m:set("pad", 1.4, 4)
		R.expect(m:value(3)).toBeNear(84, 1e-9)
	end)
end)

R.describe("BotBrain", function()
	local inv = { "Log", "Kettle", "Pizza", "Trophy", "Skateboard", "Fan", "Barrel", "Cactus" }
	R.it("optimal crafting only uses inventory items, each at most once", function()
		local slots = BotBrain.chooseSlots(BotBrain.PROFILES.sweaty, inv, "FOREST")
		local count = {}
		for _, v in pairs(slots) do count[v] = (count[v] or 0) + 1 end
		for name, n in pairs(count) do
			R.expect(table.find(inv, name) ~= nil).toBe(true)
			R.expect(n).toBe(1)
		end
		R.expect(ItemConfig[slots.ENGINE].slotType).toBe("ENGINE")
		R.expect(ItemConfig[slots.BODY].slotType).toBe("BODY")
	end)
	R.it("optimal crafting is at least as fast as casual crafting", function()
		local a = BotBrain.topSpeed(BotBrain.chooseSlots(BotBrain.PROFILES.sweaty, inv, "FOREST"), "FOREST")
		local b = BotBrain.topSpeed(BotBrain.chooseSlots(BotBrain.PROFILES.casual, inv, "FOREST"), "FOREST")
		R.expect(a >= b).toBe(true)
	end)
	R.it("prefers a rarer item within its greed budget", function()
		local items = {
			{ id = "1", name = "Pizza", x = 5, z = 0 },     -- Common, close
			{ id = "2", name = "Kettle", x = 30, z = 0 },   -- Epic, further
		}
		R.expect(BotBrain.pickItem(BotBrain.PROFILES.sweaty, { x = 0, z = 0 }, items, {}).id).toBe("2")
		R.expect(BotBrain.pickItem({ greed = 0 }, { x = 0, z = 0 }, items, {}).id).toBe("1")
	end)
end)

R.describe("Telemetry", function()
	R.it("keeps events in order and bounds memory", function()
		Telemetry.reset({ test = true })
		local cap = Telemetry.CAPACITY
		Telemetry.CAPACITY = 5
		Telemetry.reset()
		for i = 1, 8 do Telemetry.record("e", { i = i }) end
		local ev = Telemetry.events()
		R.expect(#ev).toBe(5)
		R.expect(ev[1].i).toBe(4)
		R.expect(ev[5].i).toBe(8)
		R.expect(Telemetry.snapshot().dropped).toBe(3)
		Telemetry.CAPACITY = cap
		Telemetry.reset()
	end)
	R.it("samples only when detailed mode is on", function()
		Telemetry.reset()
		Telemetry.setDetailed(false)
		Telemetry.sample("race_sample", {})
		R.expect(#Telemetry.events()).toBe(0)
		Telemetry.setDetailed(true)
		Telemetry.sample("race_sample", {})
		R.expect(#Telemetry.events()).toBe(1)
		Telemetry.setDetailed(false)
	end)
end)

-- Launch audit 2026-10-30: all three maps stand in the place; a hidden one's
-- boost pads and checkpoints fired under the live map (FOREST and OCEAN share
-- the start straight) and drop rays landed on its invisible floors.
R.describe("MapVisibility: hidden maps do nothing", function()
	R.it("a hidden part is not touchable or hit by rays; showing restores it, a Dimmed pad stays dim", function()
		local e = Loader.boot()
		local MV = e.requirePath("ServerScriptService.Modules.MapVisibility")
		local Instance = e.mock.Instance
		local maps = Instance.new("Folder")
		local map = Instance.new("Model")
		map.Name = "ForestMap"
		map.Parent = maps
		local pad = Instance.new("Part")
		pad.Transparency = 0.2
		pad.Parent = map
		local sensor = Instance.new("Part")
		sensor.Transparency = 1
		sensor.CanCollide = false
		sensor.CanTouch = true
		sensor.CanQuery = false
		sensor.Parent = map
		MV.hideAll(maps)
		R.expect(pad.CanTouch).toBe(false)
		R.expect(pad.CanQuery).toBe(false)
		R.expect(pad.CanCollide).toBe(false)
		pad:SetAttribute("Dimmed", 0.75)
		MV.show(map)
		R.expect(pad.CanTouch).toBe(true)
		R.expect(pad.CanQuery).toBe(true)
		R.expect(pad.Transparency).toBe(0.75)
		R.expect(sensor.CanTouch).toBe(true)
		R.expect(sensor.CanQuery).toBe(false)
		R.expect(sensor.CanCollide).toBe(false)
	end)
end)
