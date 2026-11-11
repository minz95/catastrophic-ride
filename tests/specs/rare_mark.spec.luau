--!nocheck
-- Rare loot marks its holder (Constants.RARE_MARK, client RareMark), farm
-- bots go for marked players, and bots talk in chat bubbles (Shared/BotTalk,
-- FarmBots, FarmAction "say"). Playtest 2026-11-12: "whoever gets a rare
-- item should stand out for a few seconds so people come after them";
-- "bots should talk ('give it!'), small, not like the effect popups".
local R = require("../lib/runner")
local Server = require("../lib/server")
local Loader = require("../lib/loader")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local env = Loader.boot()
local BotTalk = env.requirePath("ReplicatedStorage.Shared.BotTalk")
local IC = env.requirePath("ReplicatedStorage.Shared.ItemConfig")

local function farm(fillBots)
	local srv = Server.boot({
		players = 1,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = 1, lobbyDelay = 0, fillBots = fillBots,
			durations = { FARMING = 90, CRAFTING = 5, RACING = 600 } },
	})
	local e = srv.env
	local FarmBots = e.requirePath("ServerScriptService.Modules.FarmBots")
	FarmBots.kinematic = true
	local hb = e.game:GetService("RunService").Heartbeat
	local function tick(t) srv.advance(t, 1 / 30, function() hb:Fire(1 / 30) end) end
	tick(0.5)
	return srv, FarmBots, tick, e.requirePath("ReplicatedStorage.Shared.Constants")
end

local function rareName()
	local names = {}
	for name, cfg in pairs(IC) do
		if type(cfg) == "table" and cfg.rarity == "Rare" then table.insert(names, name) end
	end
	table.sort(names)
	return names[1]
end

R.describe("bot talk (Shared/BotTalk)", function()
	R.it("a line for every moment, short enough for a bubble", function()
		for event, list in pairs(BotTalk.LINES) do
			R.expect(#list > 0).toBe(true)
			for _, line in ipairs(list) do R.expect(#line <= 28).toBe(true) end
			R.expect(BotTalk.line(event, function() return 1 end)).toBe(list[1])
		end
		R.expect(BotTalk.line("nothing")).toBe(nil)
	end)

	R.it("one line per bot per GAP, one on the whole farm per ANY_GAP", function()
		local talk = { GAP = 8, ANY_GAP = 2 }
		local gate, a, b = {}, {}, {}
		R.expect(BotTalk.may(a, gate, 0, talk)).toBe(true)
		R.expect(BotTalk.may(b, gate, 1, talk)).toBe(false)   -- someone just spoke
		R.expect(BotTalk.may(b, gate, 2.5, talk)).toBe(true)
		R.expect(BotTalk.may(a, gate, 5, talk)).toBe(false)   -- its own gap
		R.expect(BotTalk.may(a, gate, 8.5, talk)).toBe(true)
	end)
end)

R.describe("rare loot marks its holder; bots go for them and say so", function()
	R.it("a stolen rare item takes the mark (server flag) to the thief", function()
		local srv, FarmBots, tick = farm(2)
		local player = srv.players[1]
		local bot = srv.SessionManager.bots()[1]
		FarmBots.paused = true
		local name = rareName()
		local pd, bd = srv.SessionManager.getData(player), srv.SessionManager.getData(bot)
		bd.inventory = { name }
		pd.inventory = {}
		player.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 850)
		bot.Character.HumanoidRootPart.Position = Vector3.new(1, 3, 850)
		tick(25)
		bd._rareAt = srv.mock.clock
		srv.mock.invoke(srv.RemoteEvents.RequestSteal, player, bot.UserId)
		tick(2)
		local att = srv.Telemetry.events("steal_attempt")
		R.expect(#att).toBe(1)
		if att[1].result == "stolen" then
			R.expect(pd._rareAt ~= nil).toBe(true)
			R.expect(bd._rareAt).toBe(nil)
			-- clients get the ids to move the mark
			local calls = rawget(srv.RemoteEvents.ItemStolen, "_calls") or {}
			local last = calls[#calls]
			R.expect(last.args[4]).toBe(player.UserId)
			R.expect(last.args[5]).toBe(bot.UserId)
		end
	end)

	R.it("a bot near a marked player goes for them and says so in a bubble", function()
		local srv, FarmBots, tick, C = farm(2)
		local F = C.BOTS.FARM
		local old = F.RARE_CHASE_CHANCE
		F.RARE_CHASE_CHANCE = 1
		local player = srv.players[1]
		local bot = srv.SessionManager.bots()[1]
		tick(20)   -- past the steal-free start
		local pd = srv.SessionManager.getData(player)
		pd.inventory = { rareName(), "Log" }
		srv.SessionManager.getData(bot).inventory = {}
		local at = bot.Character.HumanoidRootPart.Position
		for _ = 1, 40 do
			pd._rareAt = srv.mock.clock
			player.Character.HumanoidRootPart.Position = at + Vector3.new(20, 0, 0)
			tick(0.25)
			if #srv.Telemetry.events("steal_attempt") > 0 then break end
		end
		F.RARE_CHASE_CHANCE = old
		tick(2)
		local said = {}
		for _, ev in ipairs(srv.Telemetry.events("bot_say")) do said[ev.event] = true end
		R.expect(said.rare_chase).toBe(true)
		local att = srv.Telemetry.events("steal_attempt")
		R.expect(#att).toBeGreaterThan(0)
		R.expect(att[1].victim).toBe(player.UserId)
		local says = 0
		for _, c in ipairs(rawget(srv.RemoteEvents.FarmAction, "_calls") or {}) do
			if c.method == "FireAllClients" and c.args[1] == "say" then
				says += 1
				R.expect(type(c.args[4].text)).toBe("string")
			end
		end
		R.expect(says).toBeGreaterThan(0)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("bots don't chatter over each other: at most one line per ANY_GAP on the farm", function()
		local srv, _, tick, C = farm(4)
		tick(60)
		local times = {}
		for _, ev in ipairs(srv.Telemetry.events("bot_say")) do table.insert(times, ev.t or ev.time or 0) end
		R.expect(#times <= 60 / C.BOTS.FARM.TALK.ANY_GAP + 1).toBe(true)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("clients: the mark (icon + arrow + short glow) and the bot bubble are drawn", function()
		local mark = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RareMark.client.lua")
		R.expect(mark:find("RARE_MARK", 1, true) ~= nil).toBe(true)
		R.expect(mark:find("ItemStolen", 1, true) ~= nil).toBe(true)
		R.expect(mark:find('Instance.new("Highlight")', 1, true) ~= nil).toBe(true)
		local fx = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmFx.client.lua")
		R.expect(fx:find(':DisplayBubble(head, text)', 1, true) ~= nil).toBe(true)
	end)
end)
