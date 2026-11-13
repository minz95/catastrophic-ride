--!nocheck
-- Playtest 2026-11-14: on the crafting screen a player could not tell how
-- strong the ride was or what its E abilities did. Shared/RideRating rates a
-- build from the race's own numbers; AbilityManager publishes each item's
-- ability kind (Shared/AbilityKind) for the screen.
local R = require("../lib/runner")
local Server = require("../lib/server")

local srv = Server.boot({
	players = 1,
	swallowErrors = true,
	scripts = { "ServerScriptService.GameBootstrap", "ServerScriptService.AbilityManager" },
	harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0,
		durations = { FARMING = 900 } },
})
local env = srv.env
local RideRating = env.requirePath("ReplicatedStorage.Shared.RideRating")
local AbilityKind = env.requirePath("ReplicatedStorage.Shared.AbilityKind")
local ItemConfig = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local ItemBlurbs = env.requirePath("ReplicatedStorage.Shared.ItemBlurbs")
local AbilityConfig = env.requirePath("ServerScriptService.Modules.AbilityConfig")

R.describe("ride rating", function()
	R.it("bars stay in 0..1 and every grade shows up in every biome", function()
		for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
			local seen = {}
			for name, cfg in pairs(ItemConfig) do
				if type(cfg) == "table" and cfg.slotType then
					local r = RideRating.rate({ [cfg.slotType] = name }, biome)
					for _, bar in ipairs(RideRating.BARS) do
						local v = r.bars[bar.key]
						R.expect(v >= 0 and v <= 1).toBe(true)
					end
				end
			end
			-- full builds: every body and engine, with every special
			local of = {}
			for name, cfg in pairs(ItemConfig) do
				if type(cfg) == "table" and cfg.slotType then
					of[cfg.slotType] = of[cfg.slotType] or {}
					table.insert(of[cfg.slotType], name)
				end
			end
			local count = {}
			for _, body in ipairs(of.BODY) do
				for _, eng in ipairs(of.ENGINE) do
					for _, sp in ipairs(of.SPECIAL) do
						local g = RideRating.rate({ BODY = body, ENGINE = eng, SPECIAL = sp }, biome).grade
						seen[g] = true
						count[g] = (count[g] or 0) + 1
					end
				end
			end
			for _, g in ipairs({ "S", "A", "B", "C" }) do
				R.expect(seen[g] == true).toBe(true, biome .. " never grades " .. g)
			end
		end
	end)

	R.it("an engine with more power raises acceleration", function()
		local weak, strong
		for name, cfg in pairs(ItemConfig) do
			if type(cfg) == "table" and cfg.slotType == "ENGINE" and cfg.power then
				if not weak or cfg.power < ItemConfig[weak].power then weak = name end
				if not strong or cfg.power > ItemConfig[strong].power then strong = name end
			end
		end
		local a = RideRating.rate({ BODY = "Log", ENGINE = weak }, "FOREST").bars.accel
		local b = RideRating.rate({ BODY = "Log", ENGINE = strong }, "FOREST").bars.accel
		R.expect(b > a).toBe(true)
	end)

	R.it("with() moves an item into a slot and out of its old one", function()
		local s = RideRating.with({ BODY = "Log", SPECIAL = "Pizza" }, "Pizza", "BODY")
		R.expect(s.BODY).toBe("Pizza")
		R.expect(s.SPECIAL).toBe(nil)
	end)
end)

R.describe("ability kinds", function()
	R.it("the server publishes a kind and a blurb for every item with an ability", function()
		local info = AbilityKind.info(env.game:GetService("ReplicatedStorage"), env.game:GetService("HttpService"))
		local missing = {}
		for name, cfg in pairs(ItemConfig) do
			if type(cfg) == "table" and cfg.slotType and AbilityConfig[name] then
				local e = info[name]
				if not (e and AbilityKind.KINDS[e.kind] and ItemBlurbs.ABILITY[name]) then
					table.insert(missing, name)
				end
			end
		end
		R.expect(next(info) ~= nil).toBe(true)
		R.expect(missing).toBeEmpty("items without a published kind")
	end)

	R.it("kinds read right", function()
		local info = AbilityKind.table(AbilityConfig)
		R.expect(info["Toilet"].kind).toBe("SPEED")
		R.expect(info["Piano"].kind).toBe("SHIELD")
		R.expect(info["Microwave"].kind).toBe("ATTACK")
		R.expect(info["Pizza"].kind).toBe("TRAP")
	end)
end)

return R
