-- GpTest.lua
-- The Junk Grand Prix with real physics (harness arg `gp`, scenario
-- gp-drive): the bot client gets a car (`gp.car`, a Junk Motors item),
-- enters at the desk and drives a whole run on autopilot (GpClient with
-- player attribute GpAuto: Shared/GpDriver at `gp.skill`, into the pits
-- when the tyres call for it). Reports every lap, pit stop, reset and
-- rollover (Telemetry gp_*), then ends the match.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GpTest = {}

function GpTest.run(args, done)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local Telemetry = require(ServerScriptService.Modules.Telemetry)
	local opts = type(args.gp) == "table" and args.gp or {}
	local player, rec
	local t0 = os.clock()
	repeat
		task.wait(0.5)
		player = Players:GetPlayers()[1]
		rec = player and PlayerStore.get(player)
	until (rec and player.Character and player.Character:FindFirstChild("HumanoidRootPart")) or os.clock() - t0 > 60
	if not rec then done("no gp player") return end
	task.wait(4)   -- the circuit and the bots
	local car = opts.car or "Toilet"
	rec.cars = { [car] = true }
	rec.legendOn = "car:" .. car
	player:SetAttribute("GpAuto", HttpService:JSONEncode({ skill = opts.skill or 0.92, camera = opts.camera }))
	Telemetry.onRecord(function(kind, fields)
		if kind == "gp_lap" then
			print(string.format("[GpTest] lap %d  %.3f s  %s", fields.lap or 0, fields.time or 0, fields.valid and "valid" or "DELETED"))
		elseif kind == "gp_reset" or kind == "gp_pit" or kind == "gp_enter" or kind == "gp_denied" then
			print("[GpTest] " .. kind .. " " .. HttpService:JSONEncode(fields))
		elseif kind == "gp_end" and fields.userId == player.UserId then
			print("[GpTest] end " .. HttpService:JSONEncode(fields))
			task.delay(2, function() done("gp run " .. tostring(fields.reason)) end)
		end
	end)
end

return GpTest
