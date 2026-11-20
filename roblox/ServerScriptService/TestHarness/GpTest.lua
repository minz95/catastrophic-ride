-- GpTest.lua
-- The Junk Grand Prix with real physics (harness arg `gp`, scenario
-- gp-drive): the bot client gets a car (`gp.car`, a Junk Motors item),
-- enters at the desk and drives a whole run on autopilot (GpClient with
-- player attribute GpAuto: Shared/GpDriver at `gp.skill`, into the pits
-- when the tyres call for it). Reports every lap, pit stop, reset and
-- rollover (Telemetry gp_*), then ends the match. `gp.film` = the reel
-- (scenario record-gp): StarterPlayerScripts/Modules/GpFilm directs the
-- camera, the lights wait `gp.hold` s for the helmet shot.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GpTest = {}

function GpTest.run(args, done)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local Telemetry = require(ServerScriptService.Modules.Telemetry)
	local opts = type(args.gp) == "table" and args.gp or {}
	-- gp.drivers: one entry per bot client ({ car, skill, keys, blind });
	-- else one driver from gp.car / gp.skill
	local drivers = type(opts.drivers) == "table" and opts.drivers
		or { { car = opts.car, skill = opts.skill, camera = opts.camera, film = opts.film, flips = opts.flips } }
	local players = {}
	local t0 = os.clock()
	repeat
		task.wait(0.5)
		players = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local r = PlayerStore.get(p)
			if r and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then table.insert(players, p) end
		end
	until #players >= #drivers or os.clock() - t0 > 90
	if #players == 0 then done("no gp player") return end
	task.wait(4)   -- the circuit and the bots
	-- gp.shapes: every Junk Motors car built once and measured (visible
	-- width / height → stability: which cars can roll over at all)
	if opts.shapes then
		local GpCars = require(ServerScriptService.Modules.GpCars)
		local NewCars = require(game:GetService("ReplicatedStorage").Shared.NewCars)
		local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
		for _, c in ipairs(NewCars.catalog(ItemConfig)) do
			local model, spec = GpCars.build(NewCars.ride(c.item), CFrame.new(0, 900, 0), "shape")
			if model then
				local shape, w, h = GpCars.shapeOf(model)
				Telemetry.record("gp_shape", { item = c.item, shape = math.floor(shape * 100) / 100, w = math.floor(w * 10) / 10,
					h = math.floor(h * 10) / 10, stability = math.floor(spec.stability * 100) / 100, top = math.floor(spec.top),
					grip = math.floor(spec.grip) })
				model:Destroy()
			end
			task.wait()
		end
	end
	local running = {}
	table.sort(players, function(x, y) return x.UserId > y.UserId end)
	for i, player in ipairs(players) do
		local d = drivers[i]
		if d then
			local rec = PlayerStore.get(player)
			local car = d.car or "Toilet"
			rec.cars = { [car] = true }
			rec.legendOn = "car:" .. car
			running[player.UserId] = true
			task.delay((i - 1) * 3, function()
				player:SetAttribute("GpAuto", HttpService:JSONEncode({ skill = d.skill or 0.92, camera = d.camera, film = d.film,
					keys = d.keys, blind = d.blind, flips = d.flips }))
			end)
		end
	end
	Telemetry.onRecord(function(kind, fields)
		if kind == "gp_lap" then
			print(string.format("[GpTest] lap %d  %.3f s  %s", fields.lap or 0, fields.time or 0, fields.valid and "valid" or "DELETED"))
		elseif kind == "gp_reset" or kind == "gp_pit" or kind == "gp_enter" or kind == "gp_denied" or kind == "gp_yank" then
			print("[GpTest] " .. kind .. " " .. HttpService:JSONEncode(fields))
		elseif kind == "gp_end" and running[fields.userId] then
			print("[GpTest] end " .. HttpService:JSONEncode(fields))
			running[fields.userId] = nil
			if next(running) == nil then
				task.delay(2, function() done("gp run " .. tostring(fields.reason)) end)
			end
		end
	end)
end

return GpTest
