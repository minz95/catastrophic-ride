-- LugeTest.lua
-- The Alpine Luge with real physics (harness arg `luge`, scenario
-- luge-ride): each bot client gets a car (`luge.riders[i].car`), takes the
-- booth and rides `runs` runs on autopilot (LugeClient with player
-- attribute LugeAuto: Shared/LugeDriver at `skill`; `keys` = like a person
-- on a keyboard, `late` s late; `blind` = does not keep its distance),
-- then leaves. Reports every lift, run, reset and bump (Telemetry luge_*;
-- the clients report scrapes and hops), then ends the match.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local LugeTest = {}

function LugeTest.run(args, done)
	local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
	local Telemetry = require(ServerScriptService.Modules.Telemetry)
	local opts = type(args.luge) == "table" and args.luge or {}
	local riders = type(opts.riders) == "table" and opts.riders or { { car = "Toilet", skill = 0.95 } }
	local players = {}
	local t0 = os.clock()
	repeat
		task.wait(0.5)
		players = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if PlayerStore.get(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then table.insert(players, p) end
		end
	until #players >= #riders or os.clock() - t0 > 90
	if #players == 0 then done("no luge rider") return end
	task.wait(3)   -- the hill
	table.sort(players, function(x, y) return x.UserId > y.UserId end)
	local running = {}
	for i, player in ipairs(players) do
		local r = riders[i]
		if r then
			local rec = PlayerStore.get(player)
			local car = r.car or "Toilet"
			rec.cars = { [car] = true }
			rec.legendOn = "car:" .. car
			running[player.UserId] = true
			task.delay((i - 1) * (r.after or 1.5), function()
				player:SetAttribute("LugeAuto", HttpService:JSONEncode({ skill = r.skill or 0.95, keys = r.keys, late = r.late,
					blind = r.blind, runs = r.runs or opts.runs or 2, film = r.film, whoop = r.whoop }))
			end)
		end
	end
	Telemetry.onRecord(function(kind, fields)
		if kind == "luge_run" or kind == "luge_reset" or kind == "luge_enter" or kind == "luge_denied" or kind == "luge_go" then
			print("[LugeTest] " .. kind .. " " .. HttpService:JSONEncode(fields))
		elseif kind == "luge_end" and running[fields.userId] then
			print("[LugeTest] end " .. HttpService:JSONEncode(fields))
			running[fields.userId] = nil
			if next(running) == nil then
				task.delay(2, function() done("luge done " .. tostring(fields.reason)) end)
			end
		end
	end)
end

return LugeTest
