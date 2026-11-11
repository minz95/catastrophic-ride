--!nocheck
-- Friend invites: the INVITE FRIENDS button (Shared/Invite on the lobby and
-- results screens) and the coins a new friend's first visit pays the
-- inviter (Modules/Referral, InviteManager).
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local Server = require("../lib/server")
local fs = require("@lune/fs")
local Vector3 = require("@lune/roblox").Vector3

R.describe("Friend invites", function()
	local env = Loader.boot()
	local Referral = env.requirePath("ServerScriptService.Modules.Referral")
	local C = env.requirePath("ReplicatedStorage.Shared.Constants")
	local Progression = env.requirePath("ReplicatedStorage.Shared.Progression")

	R.it("a new friend pays the inviter once; a friend who already played pays nothing", function()
		local me = Progression.newRecord()
		local newFriend = Progression.newRecord()
		R.expect(Referral.credit(me, 77, newFriend)).toBe(C.INVITE.COINS)
		R.expect(Referral.credit(me, 77, newFriend)).toBe(0)
		R.expect(me.coins).toBe(C.INVITE.COINS)
		local old = Progression.newRecord(); old.rounds = 3
		R.expect(Referral.credit(me, 78, old)).toBe(0)
		R.expect(Referral.credit(nil, 79, newFriend)).toBe(0)
	end)

	R.it("pays for at most MAX_REWARDED friends", function()
		local me = Progression.newRecord()
		for i = 1, C.INVITE.MAX_REWARDED + 5 do Referral.credit(me, i, Progression.newRecord()) end
		R.expect(me.coins).toBe(C.INVITE.COINS * C.INVITE.MAX_REWARDED)
	end)

	R.it("an old save gets the referred list; client counts are cleaned", function()
		local rec = Progression.migrate({ coins = 5, level = 2 })
		R.expect(type(rec.referred)).toBe("table")
		R.expect(Referral.cleanCount(3)).toBe(3)
		R.expect(Referral.cleanCount(1e9)).toBe(C.INVITE.MAX_REPORT)
		R.expect(Referral.cleanCount(-2)).toBe(0)
		R.expect(Referral.cleanCount("x")).toBe(0)
		R.expect(Referral.cleanCount(0 / 0)).toBe(0)
	end)

	R.it("a friend joining through the invite pays the inviter in a running server", function()
		local srv = Server.boot({
			players = 1,
			scripts = {
				"ServerScriptService.GameBootstrap",
				"ServerScriptService.ProgressionManager",
				"ServerScriptService.InviteManager",
			},
			setup = function(e)
				local Ref = e.requirePath("ServerScriptService.Modules.Referral")
				Ref.referrerOf = function(p) return p.UserId == 2001 and 1001 or nil end
			end,
		})
		srv.advance(1)
		local e = srv.env
		local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
		local Consts = e.requirePath("ReplicatedStorage.Shared.Constants")
		local inviter = srv.players[1]
		local before = PlayerStore.get(inviter).coins
		srv.mock.addPlayer("Friend", 2001, Vector3.new(0, 3, 850))
		srv.advance(1)
		R.expect(PlayerStore.get(inviter).coins - before).toBe(Consts.INVITE.COINS)
		local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
		local calls = rawget(RE.InviteReward, "_calls") or {}
		R.expect(#calls).toBe(1)
		R.expect(calls[1].args[1]).toBe(inviter)
		R.expect(inviter.leaderstats.Coins.Value).toBe(PlayerStore.get(inviter).coins)
		-- someone who was not invited pays nobody
		srv.mock.addPlayer("Stranger", 2002, Vector3.new(4, 3, 850))
		srv.advance(1)
		R.expect(PlayerStore.get(inviter).coins - before).toBe(Consts.INVITE.COINS)
		-- invites the client reports are logged, at most one report per REPORT_GAP
		RE.InviteSent.OnServerEvent:Fire(inviter, 2)
		RE.InviteSent.OnServerEvent:Fire(inviter, 5)
		local sent = srv.Telemetry.events("invite_sent")
		R.expect(#sent).toBe(1)
		R.expect(sent[1].count).toBe(2)
		R.expect(#srv.Telemetry.events("referral")).toBe(1)
		R.expect(srv.mock.errors).toBeEmpty("server errors")
	end)

	R.it("the lobby and results screens have the button; the client reports and greets", function()
		local lobby = fs.readFile("roblox/StarterGui/LobbyUI/init.client.lua")
		local results = fs.readFile("roblox/StarterGui/ResultsUI/init.client.lua")
		R.expect(lobby:find("Shared.Invite).button(", 1, true) ~= nil).toBe(true)
		R.expect(results:find("Invite.button(stage", 1, true) ~= nil).toBe(true)
		local inv = fs.readFile("roblox/ReplicatedStorage/Shared/Invite.lua")
		R.expect(inv:find("CanSendGameInviteAsync", 1, true) ~= nil).toBe(true)
		R.expect(inv:find("PromptGameInvite(", 1, true) ~= nil).toBe(true)
		R.expect(inv:find("InviteSent:FireServer", 1, true) ~= nil).toBe(true)
		local client = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/GameClient.client.lua")
		R.expect(client:find("watchRewards()", 1, true) ~= nil).toBe(true)
	end)
end)
