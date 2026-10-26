--!nocheck
-- Shop extras: special rides on the vehicle, the Flying Kick (same punch,
-- other look) and the Smoke Bomb (one escape per round).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local env = Loader.boot()
local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")

R.describe("special rides (VehicleBuilder.applyRide)", function()
	local VehicleBuilder = env.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local VehicleStats = env.requirePath("ReplicatedStorage.Shared.VehicleStats")
	for _, it in ipairs(Cosmetics.ITEMS.ride) do
		if it.body then
			for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
				R.it(it.name .. " on " .. biome .. ": material, glow, speed particles, its trail; the chassis and seat unchanged", function()
					local stats = VehicleStats.calculate(nil, nil, nil, biome)
					local plain = VehicleBuilder.build(stats, biome, CFrame.new(), {})
					local car = VehicleBuilder.build(stats, biome, CFrame.new(), {}, Cosmetics.look({ ride = it.id }))
					R.expect(car:GetAttribute("Ride")).toBe(it.id)
					R.expect(car.PrimaryPart.Size).toBe(plain.PrimaryPart.Size)
					local a, b = plain:FindFirstChildWhichIsA("VehicleSeat", true), car:FindFirstChildWhichIsA("VehicleSeat", true)
					R.expect(b.MaxSpeed).toBe(a.MaxSpeed)
					R.expect(b.TurnSpeed).toBe(a.TurnSpeed)
					local body, emitter = 0, nil
					for _, d in ipairs(car:GetDescendants()) do
						if d:IsA("BasePart") and d:GetAttribute("RideBody") then body += 1 end
						if d:IsA("ParticleEmitter") and d:GetAttribute("BaseRate") then emitter = d end
					end
					R.expect(body).toBeGreaterThan(0)
					R.expect(emitter ~= nil).toBe(true)
					R.expect(emitter.Rate).toBe(0)   -- CosmeticFx turns it up while driving
					R.expect(car.PrimaryPart:FindFirstChild("RideGlow") ~= nil).toBe(true)
					R.expect(car.PrimaryPart:FindFirstChild("CosmeticTrail") ~= nil).toBe(true)
				end)
			end
		end
	end

	R.it("on SKY's pale road a ride's glow, particles and trail are toned down (they added up to a white blob)", function()
		local look = Cosmetics.look({ ride = "ride_rainbow" })
		local function parts(biome)
			local car = VehicleBuilder.build(VehicleStats.calculate(nil, nil, nil, biome), biome, CFrame.new(), {}, look)
			local emitter
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("ParticleEmitter") and d:GetAttribute("BaseRate") then emitter = d end
			end
			return car.PrimaryPart:FindFirstChild("RideGlow"), emitter, car.PrimaryPart:FindFirstChild("CosmeticTrail")
		end
		local g1, e1, t1 = parts("FOREST")
		local g2, e2, t2 = parts("SKY")
		R.expect(g2.Brightness).toBeLessThan(g1.Brightness * 0.5)
		R.expect(e2.LightEmission).toBeLessThan(e1.LightEmission * 0.5)
		R.expect(t2.LightEmission).toBeLessThan(t1.LightEmission * 0.5)
	end)

	R.it("a ride replaces the paint and the trail", function()
		local look = Cosmetics.look({ ride = "ride_neon", paint = "paint_lime", trail = "trail_fire" })
		R.expect(look.paint.body).toBe(Cosmetics.get("ride_neon").body)
		R.expect(look.trail).toBe(Cosmetics.get("ride_neon").trail)
	end)
end)

local function fightServer()
	local srv = Server.boot({
		players = 2,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
			durations = { FARMING = 120, CRAFTING = 5, RACING = 600 } },
		setup = function(e)
			local Store = e.requirePath("ServerScriptService.Modules.PlayerStore")
			for _, p in ipairs(e.mock.playerList) do
				local rec = Store.load(p)
				rec.owned.move_kick, rec.owned.gadget_smoke = true, true
				rec.equipped = { move = "move_kick", gadget = "gadget_smoke" }
			end
		end,
	})
	srv.advance(0.5)
	local a, b = srv.players[1], srv.players[2]
	a.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 850)
	b.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 846)
	local F = srv.env.requirePath("ReplicatedStorage.Shared.Constants").FIGHT
	return srv, a, b, F
end

R.describe("Flying Kick and Smoke Bomb (FARMING)", function()
	R.it("a kick is a punch with another look: same result, style = kick for every client", function()
		local srv, a = fightServer()
		R.expect(srv.invoke("RequestPunch", a)).toBe("hit")
		local calls = rawget(srv.RemoteEvents.FarmAction, "_calls")
		local last = calls[#calls].args
		R.expect(last[1]).toBe("punch")
		R.expect(last[4].style).toBe("kick")
	end)

	R.it("the gadget attribute is set for the button; one smoke per round", function()
		local srv, a = fightServer()
		R.expect(a:GetAttribute("Gadget")).toBe("smoke")
		R.expect(srv.invoke("UseGadget", a)).toBe("ok")
		R.expect(srv.invoke("UseGadget", a)).toBe("denied: used")
		R.expect(#srv.Telemetry.events("gadget")).toBe(1)
	end)

	R.it("while hidden in smoke no punch or steal reaches you; afterwards they do again", function()
		local srv, a, b, F = fightServer()
		srv.SessionManager.getData(b).inventory = { "Kettle", "Log" }
		srv.invoke("UseGadget", b)
		R.expect(srv.invoke("RequestPunch", a)).toBe("miss")
		R.expect(srv.invoke("RequestSteal", a, b.UserId)).toBe("denied: victim hidden")
		srv.advance(srv.env.requirePath("ReplicatedStorage.Shared.Constants").GADGETS.smoke.HIDE + 0.2)
		R.expect(srv.invoke("RequestPunch", a)).toBe("hit")
	end)

	R.it("a smoke bomb during a grab: the thief gets nothing", function()
		local srv, a, b = fightServer()
		srv.SessionManager.getData(b).inventory = { "Kettle", "Log" }
		local res
		srv.mock.task.spawn(function() res = srv.mock.invoke(srv.RemoteEvents.RequestSteal, a, b.UserId) end)
		srv.advance(0.3)
		R.expect(srv.invoke("UseGadget", b)).toBe("ok")
		srv.advance(5)
		local att = srv.Telemetry.events("steal_attempt")
		R.expect(att[#att].result).toBe("escaped")
		R.expect(#srv.SessionManager.getData(b).inventory).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("without the gadget equipped nothing happens", function()
		local srv = Server.boot({
			players = 1,
			scripts = { "ServerScriptService.MapBuilders.ForestMapBuilder", "ServerScriptService.GameBootstrap", "ServerScriptService.FarmingManager" },
			harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, durations = { FARMING = 120 } },
		})
		srv.advance(0.5)
		R.expect(srv.invoke("UseGadget", srv.players[1])).toBe("denied: no gadget")
	end)
end)

-- 2026-10-27: the shop's cards were colour swatches ("not a cool car, I
-- would not buy it"), and nothing pointed a player at the shop after a race.
R.describe("shop pictures (Modules/ShopPreview)", function()
	local ShopPreview = env.requirePath("ServerScriptService.Modules.ShopPreview")

	for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
		R.it(biome .. ": every ride, paint and trail is a still vehicle (anchored, no scripts, movers or particles)", function()
			local folder = ShopPreview.build(biome)
			R.expect(folder.Parent.Name).toBe(ShopPreview.FOLDER)
			R.expect(folder.Parent.Parent.Name).toBe("ReplicatedStorage")
			local missing, loose = {}, {}
			for _, cat in ipairs(ShopPreview.CATEGORIES) do
				for _, it in ipairs(Cosmetics.ITEMS[cat]) do
					local m = folder:FindFirstChild(it.id)
					if not m then
						table.insert(missing, it.id)
					else
						for _, d in ipairs(m:GetDescendants()) do
							if (d:IsA("BasePart") and not d.Anchored) or d:IsA("BaseScript") or d:IsA("ParticleEmitter")
								or d:IsA("BodyMover") or d:IsA("Constraint") then
								table.insert(loose, it.id .. ":" .. d.Name)
							end
						end
					end
				end
			end
			R.expect(missing).toBeEmpty("looks without a picture")
			R.expect(loose).toBeEmpty("moving or emitting parts in a picture")
		end)
	end

	R.it("a trail shows as a ribbon in its colours behind the vehicle; a ride in its body colour", function()
		local fire = Cosmetics.get("trail_fire")
		local m = ShopPreview.buildOne(fire, "FOREST")
		local first, last = m:FindFirstChild("TrailRibbon_1"), m:FindFirstChild("TrailRibbon_" .. ShopPreview.RIBBON.SEGMENTS)
		R.expect(first ~= nil and last ~= nil).toBe(true)
		R.expect(first.Color).toBe(fire.colors[1])
		R.expect(last.Color).toBe(fire.colors[2])
		local chassis = m:FindFirstChild("Chassis")
		R.expect(first.Position.Z > chassis.Position.Z).toBe(true)   -- behind (+Z is the back)
		R.expect(ShopPreview.buildOne(Cosmetics.get("paint_lime"), "FOREST"):FindFirstChild("TrailRibbon_1")).toBe(nil)
		local gold = ShopPreview.buildOne(Cosmetics.get("ride_gold"), "SKY")
		local body = 0
		for _, d in ipairs(gold:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("RideBody") and d.Color == Cosmetics.get("ride_gold").body then body += 1 end
		end
		R.expect(body).toBeGreaterThan(0)
		R.expect(gold:FindFirstChild("TrailRibbon_1") ~= nil).toBe(true)   -- a ride brings its trail
	end)

	R.it("the shop screen turns those models in viewports; the results screen suggests a buy", function()
		local fs = require("@lune/fs")
		local shop = fs.readFile("roblox/StarterGui/ShopUI/init.client.lua")
		R.expect(shop:find('FindFirstChild("ShopPreviews")', 1, true) ~= nil).toBe(true)
		R.expect(shop:find('Instance.new("ViewportFrame")', 1, true) ~= nil).toBe(true)
		R.expect(shop:find('openEvent.Name = "Open"', 1, true) ~= nil).toBe(true)
		local results = fs.readFile("roblox/StarterGui/ResultsUI/init.client.lua")
		R.expect(results:find("Cosmetics.suggest(", 1, true) ~= nil).toBe(true)
		R.expect(results:find("open:Fire(", 1, true) ~= nil).toBe(true)
		local mgr = fs.readFile("roblox/ServerScriptService/ShopManager.server.lua")
		R.expect(mgr:find("ShopPreview).buildAll()", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("Cosmetics.suggest (results screen)", function()
	R.it("the priciest look you can buy now; else the cheapest within your level and what it costs more", function()
		local s = Cosmetics.suggest({ coins = 460, level = 5, owned = {} })
		R.expect(s.affordable).toBe(true)
		R.expect(s.item.id).toBe("paint_galaxy")      -- 450, level 5
		local low = Cosmetics.suggest({ coins = 100, level = 1, owned = { "paint_midnight" } })
		R.expect(low.affordable).toBe(nil)
		R.expect(low.item.id).toBe("paint_lime")      -- 150, the cheapest not owned
		R.expect(low.short).toBe(50)
		R.expect(Cosmetics.suggest({ coins = 10000, level = 1, owned = {} }).item.minLevel).toBe(nil)
		local all = {}
		for _, cat in ipairs(Cosmetics.CATEGORIES) do
			for _, it in ipairs(Cosmetics.ITEMS[cat]) do all[it.id] = true end
		end
		R.expect(Cosmetics.suggest({ coins = 0, level = 99, owned = all })).toBe(nil)
	end)
end)
