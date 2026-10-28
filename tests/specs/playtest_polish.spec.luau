--!nocheck
-- Small things playtests found that a player should never see or hear.
local R = require("../lib/runner")
local fs = require("@lune/fs")
local Loader = require("../lib/loader")

local env = Loader.boot()
local SoundConfig = env.requirePath("ReplicatedStorage.Shared.SoundConfig")

R.describe("playtest polish", function()
	R.it("farm spawn markers are invisible in every biome (they floated as yellow plates)", function()
		for _, b in ipairs({ "Forest", "Ocean", "Sky" }) do
			local src = fs.readFile("roblox/ServerScriptService/Modules/Maps/" .. b .. "Map.lua")
			local i = src:find('Name = "FarmSpawnPoint"', 1, true)
			R.expect(i ~= nil).toBe(true)
			local blk = src:sub(i, (src:find("})", i, true)))
			R.expect(blk:find("Transparency = 1", 1, true) ~= nil).toBe(true)
		end
	end)

	R.it("race start and bumps are not loud bangs", function()
		-- the air horn at GO and a wall-impact thud on every bump
		for _, key in ipairs({ "COUNTDOWN_GO", "COLLISION" }) do
			local id = SoundConfig.SFX[key].id
			R.expect(id ~= "rbxassetid://9113071178" and id ~= "rbxassetid://9113437833").toBe(true)
		end
		R.expect(SoundConfig.SFX.COLLISION.volume).toBeLessThan(0.6)
		R.expect(SoundConfig.COLLISION_GAP).toBeGreaterThan(0)
	end)

	R.it("every music tryout candidate has an id and a title", function()
		for slot, list in pairs(SoundConfig.TRY) do
			R.expect(#list).toBeGreaterThan(2)
			for _, t in ipairs(list) do
				R.expect(t.id:match("^%d+$") ~= nil).toBe(true)
				R.expect(#t.title).toBeGreaterThan(0)
			end
		end
	end)
end)
