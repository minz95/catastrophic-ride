--!nocheck
-- Playtest 2026-10-25 (OCEAN): Space in a race jumped the driver off the
-- seat into the sea; they fell out of the map, respawned at the farm and
-- could not get back into the race. Racers now stay in their car
-- (Modules/RaceSeat via RacingManager, RacingClient turns jumping off), and
-- race bots have a driver in the seat (Modules/SeatedRider).
local fs = require("@lune/fs")
local R = require("../lib/runner")
local Server = require("../lib/server")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local function race(fillBots)
	local srv = Server.boot({
		players = 1,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.RacingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 0.1, CRAFTING = 0.1, RACING = 600 } },
	})
	local e = srv.env
	local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
	local stats = e.requirePath("ReplicatedStorage.Shared.VehicleStats").calculate(nil, nil, nil, "FOREST")
	local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(0, 2, 590), {})
	model.Parent = e.workspace
	local player = srv.players[1]
	srv.SessionManager.setVehicle(player, model, stats)
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	tick(0.5)
	assert(srv.GameManager.getPhase() == "RACING", "not racing")
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	return srv, player, model, seat, tick
end

local function newCharacter(srv, player, at)
	local Mock = srv.mock
	local char = Mock.Instance.new("Model")
	char.Name = player.Name
	local root = Mock.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	local hum = Mock.Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = root
	char.Parent = srv.env.workspace
	player.Character = char
	return char, hum
end

R.describe("racers stay in their car", function()
	R.it("a driver out of the seat is put back in it", function()
		local srv, player, _, seat, tick = race()
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		tick(1)
		R.expect(seat.Occupant).toBe(hum)
		-- jumped off
		seat.Occupant = nil
		hum.Sit = false
		tick(1)
		R.expect(seat.Occupant).toBe(hum)
		R.expect(#srv.Telemetry.events("reseat") >= 2).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("a character that respawned at the farm mid-race goes back into its car", function()
		local srv, player, model, seat, tick = race()
		tick(1)
		seat.Occupant = nil
		local _, hum = newCharacter(srv, player, Vector3.new(0, 5, 850))   -- the farm's spawn
		local spawned = #(rawget(srv.RemoteEvents.VehicleSpawned, "_calls") or {})
		tick(1)
		R.expect(seat.Occupant).toBe(hum)
		local whys = {}
		for _, ev in ipairs(srv.Telemetry.events("reseat")) do whys[ev.why] = true end
		R.expect(whys.respawned).toBe(true)
		-- the client is handed its car again (HUD, camera)
		local calls = rawget(srv.RemoteEvents.VehicleSpawned, "_calls") or {}
		R.expect(#calls > spawned).toBe(true)
		R.expect(calls[#calls].args[3]).toBe(model)   -- (player, userId, model)
	end)

	R.it("a dead driver gets a new character at once", function()
		local srv, player, _, _, tick = race()
		tick(1)
		local loads = 0
		rawset(player, "LoadCharacter", function() loads += 1 end)
		player.Character:FindFirstChildOfClass("Humanoid").Health = 0
		tick(1)
		R.expect(loads).toBe(1)
	end)

	R.it("the client turns jumping off for the race (Space no longer leaves the seat)", function()
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		R.expect(src:find("SetStateEnabled(Enum.HumanoidStateType.Jumping", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("race bots have a driver", function()
	R.it("every bot car has a massless rider in its seat", function()
		local srv, _, _, _, _ = race(4)
		local RaceBots = srv.env.requirePath("ServerScriptService.Modules.RaceBots")
		R.expect(#RaceBots.list).toBe(3)
		for _, b in ipairs(RaceBots.list) do
			local rider = b.model:FindFirstChild("Rider")
			R.expect(rider ~= nil).toBe(true)
			R.expect(b.seat.Occupant).toBe(rider:FindFirstChildOfClass("Humanoid"))
			for _, p in ipairs(rider:GetDescendants()) do
				if p:IsA("BasePart") then
					R.expect(p.Massless).toBe(true)
					R.expect(p.CanCollide).toBe(false)
				end
			end
		end
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

R.describe("farming keys", function()
	local farming = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua")
	local tutorial = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
	R.it("Q is only the emote menu (dropping an item moved to X)", function()
		R.expect(farming:find("KeyCode.Q", 1, true)).toBe(nil)
		R.expect(farming:find("KeyCode.X", 1, true) ~= nil).toBe(true)
	end)
	R.it("the steal starts while E is held, with a prompt over the target", function()
		R.expect(farming:find("Constants.STEAL_HOLD", 1, true) ~= nil).toBe(true)
		R.expect(farming:find("[Hold E] Steal", 1, true) ~= nil).toBe(true)
	end)
	R.it("the keys stay on screen and the RACING guide closes at GO", function()
		R.expect(tutorial:find("KeyStrip", 1, true) ~= nil).toBe(true)
		R.expect(tutorial:find("RaceGoAt", 1, true) ~= nil).toBe(true)
		R.expect(tutorial:find("KeyCode.H", 1, true) ~= nil).toBe(true)
	end)
end)
