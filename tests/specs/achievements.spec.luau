--!nocheck
-- Achievements (2026-11-16: "give players something to show off"):
-- Shared/Achievements counts, unlocks a look nobody can buy and puts it
-- on; AchievementManager wires Telemetry, badges, the player's screen and
-- the avatar-item prompt.
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local CFrame = require("@lune/roblox").CFrame

R.describe("Achievements rules", function()
	local env = Loader.boot()
	local A = env.requirePath("ReplicatedStorage.Shared.Achievements")
	local Cosmetics = env.requirePath("ReplicatedStorage.Shared.Cosmetics")
	local P = env.requirePath("ReplicatedStorage.Shared.Progression")
	local Badges = env.requirePath("ServerScriptService.Modules.Badges")

	R.it("every achievement unlocks one look that is not sold, and has a badge slot with a picture", function()
		local bad, rewards = {}, {}
		for _, a in ipairs(A.LIST) do
			local it = Cosmetics.get(a.reward)
			if not it then table.insert(bad, a.key .. ": no reward item")
			elseif it.achievement ~= a.key then table.insert(bad, a.key .. ": reward not marked")
			elseif Cosmetics.canBuy({ coins = 1e9, level = 99, owned = {} }, it.id) ~= "denied: award" then
				table.insert(bad, a.key .. ": reward can be bought")
			end
			if rewards[a.reward] then table.insert(bad, a.key .. ": reward shared") end
			rewards[a.reward] = true
			if type(a.badge) ~= "number" or type(a.ugc) ~= "table" then table.insert(bad, a.key .. ": badge / ugc ids") end
			for _, u in ipairs(a.ugc) do
				-- every avatar item has its model (tools/ugc_models.py)
				if not fs.isFile("assets/ugc/" .. u.item .. "/" .. u.item .. ".fbx") then table.insert(bad, u.item .. ": no model") end
				if u.id ~= 0 and type(u.id) ~= "number" then table.insert(bad, u.item .. ": bad id") end
			end
			local b = Badges.get("ach_" .. a.key)
			if not b or b.id ~= a.badge then table.insert(bad, a.key .. ": no badge entry") end
			if not fs.isFile("assets/badges/ach_" .. a.key .. ".png") then table.insert(bad, a.key .. ": no picture") end
		end
		R.expect(bad).toBeEmpty("achievements")
	end)

	R.it("counts up to the goal, then unlocks and equips the reward once", function()
		local rec = P.newRecord()
		for i = 1, 9 do R.expect(#A.step(rec, "finish")).toBe(0) end
		local got = A.step(rec, "finish")
		R.expect(#got).toBe(1)
		R.expect(got[1].key).toBe("races10")
		R.expect(rec.owned.pose_handsup).toBe(true)
		R.expect(rec.equipped.pose).toBe("pose_handsup")
		R.expect(#A.step(rec, "finish")).toBe(0)   -- races50 still counting, races10 not again
		R.expect(A.state(rec).progress.races50).toBe(11)
	end)

	R.it("World Tour counts each biome once", function()
		local rec = P.newRecord()
		A.step(rec, "win_biome", "FOREST")
		A.step(rec, "win_biome", "FOREST")
		A.step(rec, "win_biome", "OCEAN")
		R.expect(A.state(rec).progress.tour).toBe(2)
		R.expect(#A.step(rec, "win_biome", "SKY")).toBe(1)
		R.expect(rec.equipped.hat).toBe("hat_medal")
	end)

	R.it("events: wins (with biome, Toilet), votes, steals, knock-outs; bots earn nothing", function()
		local function evs(kind, e, ctx)
			local out = {}
			for _, x in ipairs(A.eventsOf(kind, e, ctx)) do table.insert(out, x.userId .. ":" .. x.ev .. (x.value and ("=" .. x.value) or "")) end
			return table.concat(out, ", ")
		end
		local ctx = { biome = "SKY", bodyOf = function(id) return id == 5 and "Toilet" or "Bathtub" end }
		R.expect(evs("finish", { userId = 4, place = 2 }, ctx)).toBe("4:finish")
		R.expect(evs("finish", { userId = 5, place = 1 }, ctx)).toBe("5:finish, 5:win, 5:win_biome=SKY, 5:win_toilet")
		R.expect(evs("finish", { userId = -1, place = 1, bot = true }, ctx)).toBe("")
		R.expect(evs("ride_vote", { userId = 6, votes = 2 })).toBe("6:vote_win")
		R.expect(evs("steal", { thief = 7, victim = 8 })).toBe("7:steal")
		R.expect(evs("punch", { attacker = 7, result = "knockout" })).toBe("7:knockout")
		R.expect(evs("punch", { attacker = 7, result = "hit" })).toBe("")
	end)

	R.it("old saves get no achievements field trouble; the shop never suggests an award", function()
		local rec = P.migrate({ coins = 5, level = 1 })
		R.expect(#A.view(rec)).toBe(#A.LIST)
		local all = {}
		for _, cat in ipairs(Cosmetics.CATEGORIES) do
			for _, it in ipairs(Cosmetics.ITEMS[cat]) do
				if not it.achievement then all[it.id] = true end
			end
		end
		R.expect(Cosmetics.suggest({ coins = 0, level = 99, owned = all })).toBe(nil)
	end)

	R.it("ride poses point the arms where their names say (an arm hanging down, turned by the pose)", function()
		local RP = env.requirePath("ReplicatedStorage.Shared.RidePoses")
		local roblox = require("@lune/roblox")
		local function arm(deg)
			local cf = roblox.CFrame.Angles(math.rad(deg[1]), math.rad(deg[2]), math.rad(deg[3]))
			return cf:VectorToWorldSpace(roblox.Vector3.new(0, -1, 0))
		end
		-- Hands Up: both arms up, each on its own side (2026-11-17: the first
		-- angles crossed them inward)
		local hu = RP.get("handsup")
		R.expect(arm(hu.right).Y > 0.8 and arm(hu.right).X > 0.1).toBe(true, tostring(arm(hu.right)))
		R.expect(arm(hu.left).Y > 0.8 and arm(hu.left).X < -0.1).toBe(true, tostring(arm(hu.left)))
		-- Flex: arms straight out to the sides, not across the chest
		local fl = RP.get("flex")
		R.expect(arm(fl.right).X > 0.9).toBe(true, tostring(arm(fl.right)))
		R.expect(arm(fl.left).X < -0.9).toBe(true, tostring(arm(fl.left)))
		-- Cool Lean: the right arm up, the left one resting out to the left
		local ln = RP.get("lean")
		R.expect(arm(ln.right).Y > 0.8).toBe(true)
		R.expect(arm(ln.left).X < -0.3).toBe(true)
	end)

	R.it("every ride pose names joints RidePoses knows", function()
		local RP = env.requirePath("ReplicatedStorage.Shared.RidePoses")
		for _, it in ipairs(Cosmetics.ITEMS.pose) do
			if it.pose then
				local pose = RP.get(it.pose)
				R.expect(pose ~= nil).toBe(true, it.id)
				for which in pairs(pose) do R.expect(RP.JOINTS[which] ~= nil).toBe(true, which) end
			end
		end
	end)
end)

R.describe("AchievementManager in a server", function()
	R.it("winning a race on a Toilet unlocks Royal Flush: plunger on, badge, the player told, get-item prompt", function()
		local srv = Server.boot({
			players = 2,
			scripts = {
				"ServerScriptService.MapBuilders.ForestMapBuilder",
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.RacingManager",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.AchievementManager",
			},
			harness = { harness = "lune", biome = "FOREST", players = 2, lobbyDelay = 0,
				durations = { FARMING = 0.1, CRAFTING = 0.1, RESULTS = 30 } },
		})
		local e = srv.env
		local A = e.requirePath("ReplicatedStorage.Shared.Achievements")
		local Badges = e.requirePath("ServerScriptService.Modules.Badges")
		local badgeCalls = {}
		Badges.sink = function(userId, key) table.insert(badgeCalls, userId .. ":" .. key) end
		A.get("flush").ugc[1].id = 4242
		Badges.get("ach_flush").id = 99
		local prompts = {}
		local MS = e.game:GetService("MarketplaceService")
		MS.PlayerOwnsAsset = function() return false end
		MS.PromptPurchase = function(_, player, id) table.insert(prompts, player.UserId .. ":" .. id) end

		local VehicleBuilder = e.requirePath("ServerScriptService.Modules.VehicleBuilder")
		local VehicleStats = e.requirePath("ReplicatedStorage.Shared.VehicleStats")
		local Consts = e.requirePath("ReplicatedStorage.Shared.Constants")
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local cars = {}
		for i, p in ipairs(srv.players) do
			local stats = VehicleStats.calculate(nil, nil, nil, "FOREST")
			stats.slotAssignments = { BODY = i == 1 and "Toilet" or "Bathtub" }
			local model = VehicleBuilder.build(stats, "FOREST", CFrame.new(i * 7, 2, 590), stats.slotAssignments)
			model.Parent = e.workspace
			srv.SessionManager.setVehicle(srv.players[i], model, stats)
			cars[i] = model
		end
		-- the mock's avatars have no head: give player 1 one for the hat
		local head = e.mock.Instance.new("Part")
		head.Name = "Head"
		head.Parent = srv.players[1].Character
		srv.advance(0.5)
		srv.advance(Consts.RACE_COUNTDOWN + 0.5)
		local function tagged(tag) return srv.mock.CollectionService:GetTagged(tag)[1] end
		for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
			tagged(tag).Touched:Fire(cars[1].PrimaryPart)
			srv.advance(0.1)
		end
		srv.advance(1)
		local p1 = srv.players[1]
		local rec = PlayerStore.get(p1)
		R.expect(A.state(rec).done.flush).toBe(true)
		R.expect(rec.owned.hat_plunger).toBe(true)
		R.expect(rec.equipped.hat).toBe("hat_plunger")
		R.expect(table.concat(badgeCalls, ",")).toBe(p1.UserId .. ":ach_flush")
		R.expect(table.concat(prompts, ",")).toBe(p1.UserId .. ":4242")
		local told = rawget(RE.AchievementUpdate, "_calls") or {}
		R.expect(#told).toBe(1)
		R.expect(told[1].args[2].name).toBe("Royal Flush")
		-- the hat is on the avatar (ShopHat.refresh)
		local hat = p1.Character and p1.Character:FindFirstChild("ShopHat")
		R.expect(hat and hat:GetAttribute("HatId")).toBe("hat_plunger")

		-- the Awards tab: a get-item button only for an earned achievement
		local function fn(player, ...) return (srv.mock.invoke(RE.AchievementAction, player, ...)) end
		R.expect(fn(p1, "ugc", "flush").result).toBe("ok")
		R.expect(fn(p1, "ugc", "flush").result).toBe("denied: busy")   -- one prompt per UGC_GAP s
		R.expect(fn(srv.players[2], "ugc", "flush").result).toBe("denied: not earned")
		R.expect(fn(p1, "state").list[5].done).toBe(true)
		A.get("flush").ugc[1].id = 0
		Badges.get("ach_flush").id = 0
		Badges.sink = nil
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)
end)

return R
