--!nocheck
-- Starter junk (Shared/StarterItems, FarmingManager): when FARMING starts,
-- a whole car's worth of junk waits in front of each player (the very first
-- round with the Shopping Cart), one rarer item more with a Roblox friend in
-- the server, kept for that player a while (others and bots leave it), and
-- the client is told which ones to point at. Also: the results screen's
-- challenge-worded invite and the "???" pickup card.
local R = require("../lib/runner")
local Server = require("../lib/server")
local Loader = require("../lib/loader")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local env = Loader.boot()
local SI = env.requirePath("ReplicatedStorage.Shared.StarterItems")
local IC = env.requirePath("ReplicatedStorage.Shared.ItemConfig")
local C = env.requirePath("ReplicatedStorage.Shared.Constants")
local FarmBounds = env.requirePath("ReplicatedStorage.Shared.FarmBounds")

local function seq(...)
	local list, i = { ... }, 0
	return function(n) i += 1; return ((list[i] or 1) - 1) % n + 1 end
end

R.describe("starter junk: the rules (Shared/StarterItems)", function()
	R.it("a first round gets the Shopping Cart and a whole car: BODY, ENGINE, SPECIAL", function()
		local list = SI.pick(IC, true, false, seq(3, 5, 2))
		R.expect(#list).toBe(3)
		R.expect(list[1].name).toBe(SI.FIRST)
		local slots = {}
		for _, e in ipairs(list) do
			slots[IC[e.name].slotType] = true
			R.expect(e.bonus).toBe(false)
		end
		R.expect(slots.BODY and slots.ENGINE and slots.SPECIAL).toBe(true)
	end)

	R.it("the starter items are plain ones (Common / Uncommon), never a rare prize for free", function()
		for k = 1, 40 do
			for _, e in ipairs(SI.pick(IC, k % 2 == 0, false, function(n) return (k * 7) % n + 1 end)) do
				R.expect(e.rarity == "Common" or e.rarity == "Uncommon").toBe(true)
			end
		end
	end)

	R.it("with a friend in the server: one more, a Rare, marked as the bonus", function()
		local list = SI.pick(IC, false, true, seq(1, 1, 1, 4))
		R.expect(#list).toBe(4)
		R.expect(list[4].bonus).toBe(true)
		R.expect(list[4].rarity).toBe("Rare")
	end)

	R.it("they stand in a fan in front of the player, apart, and only where items may stand", function()
		local origin = Vector3.new(0, 5, 0)
		local spots = SI.spots(origin, Vector3.new(0, 0, -1), 3)
		R.expect(#spots).toBe(3)
		for i, p in ipairs(spots) do
			R.expect(p.Z < -5).toBe(true)   -- in front (looking at -Z)
			R.expect((Vector3.new(p.X, 0, p.Z) - Vector3.new(0, 0, 0)).Magnitude <= C.STARTER.DIST + C.STARTER.SPREAD * 1.5).toBe(true)
			if i > 1 then R.expect((p - spots[i - 1]).Magnitude >= C.STARTER.SPREAD - 0.01).toBe(true) end
		end
		-- a wall ahead: pulled in toward the player, or dropped
		local near = SI.spots(origin, Vector3.new(0, 0, -1), 3, function(_, z) return z > -7 end)
		for _, p in ipairs(near) do R.expect(p.Z > -7).toBe(true) end
	end)

	R.it("kept for its player until RESERVE runs out", function()
		local it = { reservedFor = 7, reservedUntil = 100 }
		R.expect(SI.heldFrom(it, 8, 50)).toBe(true)
		R.expect(SI.heldFrom(it, 7, 50)).toBe(false)
		R.expect(SI.heldFrom(it, 8, 101)).toBe(false)
		R.expect(SI.heldFrom({}, 8, 50)).toBe(false)
	end)
end)

local function farm(n, friends)
	local srv = Server.boot({
		players = n,
		scripts = {
			"ServerScriptService.MapBuilders.ForestMapBuilder",
			"ServerScriptService.GameBootstrap",
			"ServerScriptService.CharacterManager",
			"ServerScriptService.FarmingManager",
			"ServerScriptService.CraftingManager",
		},
		harness = { harness = "lune", biome = "FOREST", players = n, lobbyDelay = 0,
			durations = { FARMING = 60, CRAFTING = 5, RACING = 600 } },
		setup = function(e)
			local FH = e.requirePath("ServerScriptService.Modules.FriendsHere")
			FH.reset()
			FH.check = function() return friends == true end
		end,
	})
	srv.advance(0.5 + C.STARTER.AFTER + 0.5)
	return srv
end

local function startersOf(srv, player)
	local out = {}
	for _, d in ipairs(srv.env.workspace.Maps.ForestMap:GetDescendants()) do
		if d.Name == "ItemId" and d.Parent:GetAttribute("StarterFor") == player.UserId then
			table.insert(out, { id = d.Value, part = d.Parent, name = d.Parent.ItemName.Value })
		end
	end
	return out
end

local function sentTo(srv, player)
	for _, c in ipairs(rawget(srv.RemoteEvents.StarterItems, "_calls") or {}) do
		if c.method == "FireClient" and c.args[1] == player then return c.args[2], c.args[3] end
	end
	return nil
end

R.describe("starter junk in a real FARMING phase (FarmingManager)", function()
	R.it("every player gets three items a few steps in front, the first round's BODY the Shopping Cart", function()
		local srv = farm(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
		for _, p in ipairs(srv.players) do
			local mine = startersOf(srv, p)
			R.expect(#mine).toBe(3)
			local root = p.Character.HumanoidRootPart.Position
			local names = {}
			for _, it in ipairs(mine) do
				local flat = Vector3.new(it.part.Position.X - root.X, 0, it.part.Position.Z - root.Z)
				R.expect(flat.Magnitude <= C.STARTER.DIST + C.STARTER.SPREAD * 1.5 + 1).toBe(true)
				local x, z = it.part.Position.X, it.part.Position.Z
				R.expect(FarmBounds.itemSpotOk("FOREST", x, z)).toBe(true)
				names[it.name] = true
			end
			R.expect(names[SI.FIRST]).toBe(true)
			local list, friend = sentTo(srv, p)
			R.expect(#list).toBe(3)
			R.expect(friend).toBe(false)
		end
		R.expect(#srv.Telemetry.events("starter_items")).toBe(2)
	end)

	R.it("the owner picks theirs up at once; another player is refused while it is kept, then may take it", function()
		local srv = farm(2)
		local a, b = srv.players[1], srv.players[2]
		local it = startersOf(srv, a)[1]
		-- both stand at a's item: b is refused, a gets it without a contest
		b.Character.HumanoidRootPart.Position = it.part.Position + Vector3.new(-2, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, b, it.id)).toBe("denied: reserved")
		a.Character.HumanoidRootPart.Position = it.part.Position + Vector3.new(2, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, a, it.id)).toBe("ok")
		-- after RESERVE, someone else's leftover starter item is fair game
		local other = startersOf(srv, a)[2]
		srv.advance(C.STARTER.RESERVE + 1)
		b.Character.HumanoidRootPart.Position = other.part.Position + Vector3.new(0, 2, 0)
		a.Character.HumanoidRootPart.Position = other.part.Position + Vector3.new(60, 2, 0)
		R.expect(srv.mock.invoke(srv.RemoteEvents.RequestPickup, b, other.id)).toBe("ok")
	end)

	R.it("with a Roblox friend in the server each friend gets a fourth, rarer bonus item", function()
		local srv = farm(2, true)
		for _, p in ipairs(srv.players) do
			local list, friend = sentTo(srv, p)
			R.expect(friend).toBe(true)
			R.expect(#list).toBe(4)
			local bonus = 0
			for _, e in ipairs(list) do if e.bonus then bonus += 1 end end
			R.expect(bonus).toBe(1)
			R.expect(#startersOf(srv, p)).toBe(4)
		end
	end)

	R.it("a player not on the farm yet (still loading) gets theirs once there; a mid-round joiner too", function()
		local srv = farm(1)
		local a = srv.players[1]
		-- late joiner: arrives 5 s into FARMING, off the farm at first
		srv.mock.addPlayer("Late", 4004, Vector3.new(0, 300, 0))
		srv.advance(2)
		local late
		for _, p in ipairs(srv.env.game:GetService("Players"):GetPlayers()) do
			if p.UserId == 4004 then late = p end
		end
		R.expect(#startersOf(srv, late)).toBe(0)
		-- now standing on the farm: the next retry gives them
		local zone = FarmBounds.get("FOREST")
		late.Character.HumanoidRootPart.Position = Vector3.new(zone.cx, zone.floorY + 3, zone.cz)
		srv.advance(C.STARTER.RETRY + 0.5)
		R.expect(#startersOf(srv, late)).toBe(3)
		-- and nobody gets a second set
		srv.advance(5)
		R.expect(#startersOf(srv, a)).toBe(3)
		R.expect(#startersOf(srv, late)).toBe(3)
		R.expect(#srv.Telemetry.events("starter_items")).toBe(2)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("no starter items in the last MIN_LEFT s of FARMING", function()
		local srv = farm(1)
		srv.advance(60 - C.STARTER.MIN_LEFT)
		srv.mock.addPlayer("VeryLate", 5005, Vector3.new(0, 300, 0))
		srv.advance(1)
		local p
		for _, q in ipairs(srv.env.game:GetService("Players"):GetPlayers()) do
			if q.UserId == 5005 then p = q end
		end
		local zone = FarmBounds.get("FOREST")
		p.Character.HumanoidRootPart.Position = Vector3.new(zone.cx, zone.floorY + 3, zone.cz)
		srv.advance(3)
		R.expect(#startersOf(srv, p)).toBe(0)
	end)

	R.it("farm bots leave a player's starter items while they are kept", function()
		local src = fs.readFile("roblox/ServerScriptService/Modules/FarmBots.lua")
		R.expect(src:find("StarterItems.heldFrom(it,", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("friends and the first look (client sources)", function()
	R.it("the results screen asks for a rematch: my ride vs yours", function()
		local src = fs.readFile("roblox/StarterGui/ResultsUI/init.client.lua")
		R.expect(src:find("Invite.RESULTS_TEXT", 1, true) ~= nil).toBe(true)
		local inv = fs.readFile("roblox/ReplicatedStorage/Shared/Invite.lua")
		R.expect(inv:find("MY RIDE VS YOURS", 1, true) ~= nil).toBe(true)
	end)

	R.it("a pickup shows a face-down ??? card that turns over to the item's ability", function()
		local src = fs.readFile("roblox/StarterGui/ItemGuideUI/init.client.lua")
		R.expect(src:find('cardTitle.Text = "???"', 1, true) ~= nil).toBe(true)
		R.expect(src:find("UDim2.fromScale(0, 1)", 1, true) ~= nil).toBe(true)   -- the turn
		R.expect(src:find("showCard(info.item, isNew)", 1, true) ~= nil).toBe(true)  -- every pickup
	end)

	R.it("the music button stands right of Roblox's top-left buttons (TopbarInset), not under them", function()
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/SoundClient.client.lua")
		R.expect(src:find("GuiService.TopbarInset", 1, true) ~= nil).toBe(true)
		R.expect(src:find('GetPropertyChangedSignal("TopbarInset")', 1, true) ~= nil).toBe(true)
	end)

	R.it("the phase toast slides in under the phase timer (which ends at Y 60), not over it", function()
		local src = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
		local y = tonumber(src:match("local TOAST_FROM_Y = (%d+)"))
		R.expect(y ~= nil and y > 60).toBe(true)
		R.expect(src:find("-180, 0, 40)", 1, true)).toBe(nil)
	end)

	R.it("the client arrow follows the server's StarterItems event", function()
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/StarterArrow.client.lua")
		R.expect(src:find("RemoteEvents.StarterItems.OnClientEvent", 1, true) ~= nil).toBe(true)
	end)
end)
