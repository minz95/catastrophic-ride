--!nocheck
-- Playtest 2026-11-15: a player who had finished saw only "TIME LEFT" and
-- could not tell why the race went on. Shared/RaceClockText (HUD).
local R = require("../lib/runner")
local Loader = require("../lib/loader")

R.describe("race clock text", function()
	local env = Loader.boot()
	local T = env.requirePath("ReplicatedStorage.Shared.RaceClockText")
	R.it("driving: the time left; finished: your place and who is still racing", function()
		R.expect(T.text(nil, 3, 45)).toBe("🏁 TIME LEFT 0:45")
		R.expect(T.text(1, 2, 38)).toBe("🏁 FINISHED #1 · 2 still racing · 0:38")
		R.expect(T.text(2, 0, 4)).toBe("🏁 FINISHED #2 · results in 0:04")
	end)
	R.it("the server publishes RacersLeft and the HUD reads it with the player's place", function()
		local fs = require("@lune/fs")
		local rm = fs.readFile("roblox/ServerScriptService/RacingManager.server.lua")
		R.expect(rm:find('SetAttribute("RacersLeft"', 1, true) ~= nil).toBe(true)
		local hud = fs.readFile("roblox/StarterGui/HUD/init.client.lua")
		R.expect(hud:find('RaceClockText.text(_myPlace, ReplicatedStorage:GetAttribute("RacersLeft")', 1, true) ~= nil).toBe(true)
	end)
end)

return R
