-- BotDriver.client.lua
-- Plays the game on a harness bot client (StudioTestService multiplayer test).
-- Does nothing unless the server marks this player with the HarnessBot
-- attribute (TestHarness.MatchHarness), so normal players never run it.
--
--   FARMING  walk to items chosen by BotBrain, pick up, mash contests,
--            steal from (or hunt) nearby players, defend steals with taps
--   CRAFTING submit the slots BotBrain picks from the real inventory
--   RACING   drive with Autopilot through InputSource → RacingClient's
--            normal drive loop (same code path as a keyboard)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ScriptContext     = game:GetService("ScriptContext")

local LocalPlayer = Players.LocalPlayer

-- Harness matches run only in Studio (StudioTestService): a live game never
-- drives a player, whatever attribute it carries.
if not game:GetService("RunService"):IsStudio() then return end

if not LocalPlayer:GetAttribute("HarnessBot") then
	LocalPlayer:GetAttributeChangedSignal("HarnessBot"):Wait()
end

local Constants     = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents  = require(ReplicatedStorage.RemoteEvents)
local BotBrain      = require(ReplicatedStorage.Shared.BotBrain)
local Autopilot     = require(ReplicatedStorage.Shared.Autopilot)

-- What a driver sees on the road ahead (Shared/RoadHazards).
local RoadHazards = require(ReplicatedStorage.Shared.RoadHazards)
local function _visibleHazards(pos) return RoadHazards.visible(pos) end
local TrackGeometry = require(ReplicatedStorage.Shared.TrackGeometry)
local VehicleController = require(ReplicatedStorage.Shared.VehicleController)
local InputSource   = require(script.Parent:WaitForChild("Modules"):WaitForChild("InputSource"))

local channel = ReplicatedStorage:WaitForChild("HarnessChannel", 30)
local function report(kind, payload)
	if channel then channel:FireServer(kind, payload) end
end

ScriptContext.Error:Connect(function(message, trace, scriptInst)
	report("client_error", {
		message = message, trace = trace,
		script = scriptInst and scriptInst:GetFullName() or "?",
	})
end)

-- Every sound that starts on this client, with what screen was open
-- (playtest 2026-10-30: "opening the shop still makes a very loud sound",
-- with no sound left in the shop's own code). Report kind "sound".
do
	local seen, sent = setmetatable({}, { __mode = "k" }), {}
	local function shopOpen()
		for _, g in ipairs(LocalPlayer:FindFirstChildOfClass("PlayerGui") and LocalPlayer.PlayerGui:GetChildren() or {}) do
			if g.Name == "ShopUI" and g:IsA("ScreenGui") then
				local panel = g:FindFirstChild("Panel")
				return panel ~= nil and panel.Visible
			end
		end
		return false
	end
	local function started(s)
		local key = s.SoundId .. "|" .. s:GetFullName()
		sent[key] = (sent[key] or 0) + 1
		if sent[key] > 4 then return end
		report("sound", {
			id = s.SoundId, name = s.Name, path = s:GetFullName(), volume = s.Volume,
			group = s.SoundGroup and s.SoundGroup.Name or nil, looped = s.Looped,
			phase = ReplicatedStorage:GetAttribute("Phase"), shopOpen = shopOpen(), t = os.clock(),
		})
	end
	local function hook(d)
		if not d:IsA("Sound") or seen[d] then return end
		seen[d] = true
		d.Played:Connect(function() started(d) end)
		d:GetPropertyChangedSignal("Playing"):Connect(function() if d.Playing then started(d) end end)
		if d.Playing then started(d) end
	end
	for _, root in ipairs({ workspace, game:GetService("SoundService"), LocalPlayer:WaitForChild("PlayerGui"),
		ReplicatedStorage, game:GetService("Lighting") }) do
		for _, d in ipairs(root:GetDescendants()) do hook(d) end
		root.DescendantAdded:Connect(hook)
	end
end

-- Screen layout (MatchHarness args.uiDump): every UI_EVERY s, each visible
-- element at the top of a ScreenGui with where it is on screen (top-left
-- of the whole window), the box of everything drawn inside it, and its
-- UDim2 layout, so tools/studio/ui_overlap.py can find overlaps here and
-- recompute them for other window sizes (playtest 2026-10-30: the SHOP
-- button covered the key list). Report kind "ui".
if LocalPlayer:GetAttribute("BotUiDump") then
	local GuiService = game:GetService("GuiService")
	local UI_EVERY = 2
	-- visible, and drawn on the screen (a name tag in a showroom model is a
	-- GuiObject too, under a BillboardGui: not part of the layout)
	local function shown(g)
		while g and g:IsA("GuiObject") do
			if not g.Visible then return false end
			g = g.Parent
		end
		return g ~= nil and g:IsA("ScreenGui")
	end
	local function drawn(g)
		if g:IsA("TextLabel") or g:IsA("TextButton") or g:IsA("TextBox") then
			if g.Text ~= "" and g.TextTransparency < 1 then return true end
		end
		if (g:IsA("ImageLabel") or g:IsA("ImageButton")) and g.Image ~= "" and g.ImageTransparency < 1 then return true end
		if g:IsA("ViewportFrame") then return true end
		return g.BackgroundTransparency < 0.95 and g.AbsoluteSize.X > 2 and g.AbsoluteSize.Y > 2
	end
	local function u(v) return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
	task.spawn(function()
		local last = {}
		while true do
			task.wait(UI_EVERY)
			local ph = ReplicatedStorage:GetAttribute("Phase") or "?"
			local inset = GuiService:GetGuiInset()
			local cam = workspace.CurrentCamera
			local out = {}
			for _, sg in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
				if sg:IsA("ScreenGui") and sg.Enabled then
					local so = sg.AbsolutePosition
					for _, top in ipairs(sg:GetChildren()) do
						if top:IsA("GuiObject") and top.Visible and top.AbsoluteSize.X > 0 then
							-- the box of everything drawn in it (clipped children aside)
							local x0, y0, x1, y1
							for _, g in ipairs({ top, table.unpack(top:GetDescendants()) }) do
								if g:IsA("GuiObject") and shown(g) and drawn(g) then
									local p, z = g.AbsolutePosition, g.AbsoluteSize
									x0 = x0 and math.min(x0, p.X) or p.X
									y0 = y0 and math.min(y0, p.Y) or p.Y
									x1 = x1 and math.max(x1, p.X + z.X) or p.X + z.X
									y1 = y1 and math.max(y1, p.Y + z.Y) or p.Y + z.Y
								end
							end
							if x0 then
								local p, z = top.AbsolutePosition, top.AbsoluteSize
								table.insert(out, {
									screen = sg.Name, name = top.Name, order = sg.DisplayOrder, ignoreInset = sg.IgnoreGuiInset,
									-- whole-window pixels: AbsolutePosition leaves the top bar out
									rect = { p.X, p.Y + inset.Y, z.X, z.Y },
									box = { x0, y0 + inset.Y, x1 - x0, y1 - y0 },
									pos = u(top.Position), size = u(top.Size), anchor = { top.AnchorPoint.X, top.AnchorPoint.Y },
									auto = top.AutomaticSize ~= Enum.AutomaticSize.None,
									screenOrigin = { so.X, so.Y + inset.Y },
								})
							end
						end
					end
				end
			end
			table.sort(out, function(a, b) return a.screen .. a.name < b.screen .. b.name end)
			local sig = ph
			for _, e in ipairs(out) do sig ..= "|" .. e.screen .. e.name .. table.concat(e.rect, ",") end
			if sig ~= last[ph] then
				last[ph] = sig
				report("ui", { phase = ph, view = cam and { cam.ViewportSize.X, cam.ViewportSize.Y }, inset = inset.Y,
					elements = out })
			end
		end
	end)
end

local farmProfile = BotBrain.PROFILES[LocalPlayer:GetAttribute("BotFarmProfile") or "casual"] or BotBrain.PROFILES.casual
local driverName = LocalPlayer:GetAttribute("BotDriverProfile") or "average"
local TRACKS = {
	FOREST = ReplicatedStorage.Shared.Tracks:FindFirstChild("ForestTrack"),
	OCEAN  = ReplicatedStorage.Shared.Tracks:FindFirstChild("OceanTrack"),
	SKY    = ReplicatedStorage.Shared.Tracks:FindFirstChild("SkyTrack"),
}

local phase, biome = nil, nil
local inventory = {}

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inv)
	inventory = inv or {}
end)
RemoteEvents.BiomeSelected.OnClientEvent:Connect(function(b)
	biome = b
end)

-- ─── FARMING ──────────────────────────────────────────────────────────────────

local function visibleItems()
	local out = {}
	local maps = workspace:FindFirstChild("Maps")
	if not maps then return out end
	for _, d in ipairs(maps:GetDescendants()) do
		if d.Name == "ItemId" and d:IsA("StringValue") then
			local part = d.Parent
			local nameVal = part and part:FindFirstChild("ItemName")
			if part and part:IsA("BasePart") and nameVal then
				table.insert(out, { id = d.Value, name = nameVal.Value, x = part.Position.X, z = part.Position.Z, part = part })
			end
		end
	end
	return out
end

-- Other players' inventories are not replicated, so every other player is
-- assumed to hold something; the server refuses ("victim has nothing").
-- Server farm bots (NPCs tagged "FarmBot", attribute BotUserId) count too.
local function otherPlayers()
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then table.insert(out, { userId = p.UserId, x = r.Position.X, z = r.Position.Z, items = 1, root = r }) end
	end
	for _, m in ipairs(game:GetService("CollectionService"):GetTagged("FarmBot")) do
		local r = m:FindFirstChild("HumanoidRootPart")
		local id = m:GetAttribute("BotUserId")
		if r and id then table.insert(out, { userId = id, x = r.Position.X, z = r.Position.Z, items = 1, root = r }) end
	end
	return out
end

local stealing = false
local nextStealAt = 0
local function trySteal(victim)
	stealing = true
	task.spawn(function()
		local ok, result = pcall(function()
			return RemoteEvents.RequestSteal:InvokeServer(victim.userId)
		end)
		report("steal", { victim = victim.userId, result = ok and result or ("error: " .. tostring(result)) })
		nextStealAt = os.clock() + (result == "stolen" and Constants.STEAL_COOLDOWN
			or result == "defended" and Constants.STEAL_DEFENDED_COOLDOWN or 1)
		stealing = false
	end)
end

-- Shop experiments (MatchHarness args.shop): buy the listed items through
-- the same ShopAction the shop screen uses.
task.spawn(function()
	local list = LocalPlayer:GetAttribute("BotShop")
	if type(list) ~= "string" or list == "" then return end
	local t0 = os.clock()
	while not LocalPlayer:GetAttribute("BotShopReady") and os.clock() - t0 < 15 do task.wait(0.2) end
	for id in string.gmatch(list, "[^,]+") do
		local res
		for _ = 1, 20 do
			local ok, r = pcall(function() return RemoteEvents.ShopAction:InvokeServer("buy", id) end)
			res = ok and type(r) == "table" and r.result or tostring(r)
			if res ~= "denied: loading" then break end
			task.wait(0.5)
		end
		report("shop", { id = id, result = res })
	end
end)

-- Shop screen test (MatchHarness args.shopUi): press B, as a player would,
-- in the lobby and at the start of CRAFTING, and report every 0.5 s whether
-- the panel is open and what its clock says (sim.py check shopUi: it must
-- close itself before the car is built and when the round starts).
if LocalPlayer:GetAttribute("BotShopUi") then
	local KeyInput = require(ReplicatedStorage.Shared.KeyInput)
	local function shopPanel()
		local gui = nil
		for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
			-- the ScreenGui, not the LocalScript of the same name next to it
			if g.Name == "ShopUI" and g:IsA("ScreenGui") then gui = g end
		end
		return gui and gui:FindFirstChild("Panel"), gui and gui:FindFirstChild("ShopNotice")
	end
	local pressedIn = {}
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ph = ReplicatedStorage:GetAttribute("Phase")
			local panel, notice = shopPanel()
			if panel and not pressedIn[ph] and (ph == Constants.PHASES.LOBBY or ph == Constants.PHASES.CRAFTING) then
				pressedIn[ph] = true
				task.wait(1)
				if not panel.Visible then
					report("shop_open", { phase = ph, t = os.clock() })
					KeyInput.press(Enum.KeyCode.B)
				end
				task.wait(0.3)
			end
			if panel then
				local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
				local clock = panel:FindFirstChild("PhaseClock")
				report("shop_ui", {
					phase = ph, open = panel.Visible,
					left = endsAt and endsAt - workspace:GetServerTimeNow(),
					clock = clock and clock.Text,
					notice = notice and notice.Visible and notice.Text or nil,
				})
			end
		end
	end)
end

-- Race tricks and taunts bought in a shop experiment: after GO the bot
-- throws its Bounce Bomb as soon as a car is ahead in range (retrying), and
-- taunts every few seconds when it bought a taunt.
local function raceTricks()
	local shop = LocalPlayer:GetAttribute("BotShop") or ""
	local taunts = shop:find("taunt_", 1, true) ~= nil
	local bombed = false
	local t0 = os.clock()
	while phase == Constants.PHASES.RACING and os.clock() - t0 < 300 do
		task.wait(1.5)
		if not bombed and LocalPlayer:GetAttribute("RaceTrick") then
			local ok, r = pcall(function() return RemoteEvents.UseRaceTrick:InvokeServer() end)
			report("race_trick", { result = ok and r or tostring(r) })
			bombed = ok and r == "ok"
		end
		if taunts and os.clock() - t0 > 8 and math.floor(os.clock() - t0) % 6 < 2 then
			RemoteEvents.Taunt:FireServer()
		end
	end
end

-- A grabbed bot with a Smoke Bomb throws it (once per round).
local _gadgetUsed = false
RemoteEvents.StealAttempt.OnClientEvent:Connect(function()
	if phase ~= Constants.PHASES.FARMING or _gadgetUsed or not LocalPlayer:GetAttribute("Gadget") then return end
	_gadgetUsed = true
	task.spawn(function()
		local ok, r = pcall(function() return RemoteEvents.UseGadget:InvokeServer() end)
		report("gadget", { result = ok and r or tostring(r) })
	end)
end)

RemoteEvents.StealAttempt.OnClientEvent:Connect(function(thiefName)
	if phase ~= Constants.PHASES.FARMING then return end
	local defend = BotBrain.defends(farmProfile)
	report("defend", { thief = thiefName, tried = defend })
	if not defend then return end
	task.spawn(function()
		for _ = 1, Constants.STEAL_DEFEND_PRESSES do
			RemoteEvents.DefendSteal:InvokeServer()
			task.wait(0.12)
		end
	end)
end)

-- Fights: punch a player in reach (facing them first), guard when punched.
local punching = false
local function punchAt(root, foe)
	punching = true
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(foe.x, root.Position.Y, foe.z))
	-- like FarmingClient on F: our own swing starts now (FarmFx, PunchAt)
	-- and the server gets the aim hint
	LocalPlayer:SetAttribute("PunchAt", os.clock())
	task.spawn(function()
		local ok, result = pcall(function() return RemoteEvents.RequestPunch:InvokeServer(foe.userId) end)
		report("punch", { victim = foe.userId, result = ok and result or ("error: " .. tostring(result)) })
		task.wait(Constants.FIGHT.COOLDOWN)
		punching = false
	end)
end

-- A foe the server keeps one hit short of a knock-out has nothing to drop
-- (FarmingRules.punch): leave them alone for a while. Without this two
-- brawlers with empty hands punched each other for the whole phase.
local EMPTY_FOE_REST = 12
local _shortHits, _emptyUntil = {}, {}

RemoteEvents.FarmAction.OnClientEvent:Connect(function(kind, actorId, targetId, info)
	if phase ~= Constants.PHASES.FARMING or kind ~= "punch" then return end
	if actorId == LocalPlayer.UserId and targetId and info and info.result == "hit" then
		local short = info.hits == (info.needed or Constants.FIGHT.HITS_TO_DROP) - 1
		_shortHits[targetId] = short and (_shortHits[targetId] or 0) + 1 or 0
		if _shortHits[targetId] >= 2 then
			_emptyUntil[targetId] = os.clock() + EMPTY_FOE_REST
			_shortHits[targetId] = 0
		end
	end
	if targetId ~= LocalPlayer.UserId then return end
	if info and (info.result == "hit") and BotBrain.guards(farmProfile) then
		RemoteEvents.SetGuard:FireServer(true)
		report("guard", { after = info.hits })
		task.delay(1.2, function() RemoteEvents.SetGuard:FireServer(false) end)
	end
end)

local function farmLoop()
	local target, contestId, presses, giveUpAt = nil, nil, 0, 0
	local hunt, huntUntil, nextHuntAt = nil, 0, 0
	local targetUntil, skip = 0, {}
	while phase == Constants.PHASES.FARMING do
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local me = root and { x = root.Position.X, z = root.Position.Z, items = #inventory }
		-- fight first: a player in reach (or, for brawlers, in sight)
		local foe, foeDist = nil, math.huge
		if me and not contestId and not stealing then
			local foes = {}
			for _, o in ipairs(otherPlayers()) do
				if os.clock() >= (_emptyUntil[o.userId] or 0) then table.insert(foes, o) end
			end
			foe, foeDist = BotBrain.pickFoe(farmProfile, me, foes)
		end
		if foe and root and hum then
			if foeDist <= Constants.FIGHT.RANGE * 0.8 then
				if not punching and BotBrain.wantsPunch(farmProfile, 0.1) then punchAt(root, foe) end
				if (farmProfile.punchChance or 0) >= 1 then
					task.wait(0.1)
					continue
				end
			elseif (farmProfile.punchChance or 0) >= 1 then
				hum:MoveTo(foe.root.Position)
				task.wait(0.1)
				continue
			end
		end
		local victim, victimDist = nil, math.huge
		if me and not contestId and not stealing and os.clock() >= nextStealAt then
			victim, victimDist = BotBrain.pickVictim(farmProfile, me, otherPlayers())
		end
		if root and hum and victim and victimDist <= Constants.STEAL_RANGE * 0.6
			and BotBrain.wantsSteal(farmProfile, 0.1) then
			hunt = nil
			trySteal(victim)
		elseif root and hum and (hunt or (victim and victimDist > Constants.STEAL_RANGE
			and os.clock() >= nextHuntAt and BotBrain.wantsSteal(farmProfile, 0.1))) then
			-- Hunting: follow the victim for a few seconds, then farm a while
			-- (a thief that only hunted never picked anything up).
			if not hunt then hunt, huntUntil = victim, os.clock() + BotBrain.HUNT_TIME end
			local r = hunt.root
			if os.clock() > huntUntil or not r.Parent then
				hunt = nil
				nextHuntAt = os.clock() + BotBrain.HUNT_REST
			else
				hum:MoveTo(r.Position)
				if (r.Position - root.Position).Magnitude <= Constants.STEAL_RANGE * 0.6 and not stealing then
					trySteal(hunt)
					hunt = nil
					nextHuntAt = os.clock() + BotBrain.HUNT_REST
				end
			end
		elseif root and hum then
			if contestId then
				presses += math.max(1, math.floor(farmProfile.mashRate * 0.1))
				RemoteEvents.RequestContest:InvokeServer(contestId, presses)
				if os.clock() > giveUpAt then contestId = nil end
			else
				local items = visibleItems()
				if target and os.clock() > targetUntil then
					skip[target.id] = true
					target = nil
				end
				if not target or not target.part.Parent then
					local reachable = {}
					for _, it in ipairs(items) do
						if not skip[it.id] then table.insert(reachable, it) end
					end
					target = BotBrain.pickItem(farmProfile, { x = root.Position.X, z = root.Position.Z }, reachable, inventory)
					targetUntil = os.clock() + BotBrain.ITEM_GIVE_UP
				end
				if target and farmProfile.mashRate > 0 then
					local d = (Vector3.new(target.x, root.Position.Y, target.z) - root.Position).Magnitude
					if d > Constants.PICKUP_RANGE * 0.7 then
						hum:MoveTo(Vector3.new(target.x, root.Position.Y, target.z))
					else
						local result = RemoteEvents.RequestPickup:InvokeServer(target.id)
						if result == "contested" then
							contestId, presses, giveUpAt = target.id, 0, os.clock() + Constants.CONTEST_DURATION + 1.5
						elseif result ~= "ok" then
							report("pickup_denied", { result = result, item = target.name })
						end
						target = nil
					end
				end
			end
		end
		task.wait(0.1)
	end
end

-- ─── CRAFTING ─────────────────────────────────────────────────────────────────

local function craft()
	task.wait(1 + math.random())
	local slots = BotBrain.chooseSlots(farmProfile, inventory, biome or "FOREST")
	if farmProfile.crafter == "none" then return end
	if farmProfile.crafter == "slow" then
		-- places items (as the crafting screen sends them) but never submits
		RemoteEvents.CraftDraft:FireServer(slots)
		report("craft", { result = "draft only", slots = slots, inventory = inventory })
		return
	end
	local result = RemoteEvents.SubmitCraft:InvokeServer(slots)
	report("craft", { result = result, slots = slots, inventory = inventory })
end

-- ─── RACING ───────────────────────────────────────────────────────────────────

local vehicle, autopilot, geo = nil, nil, nil
local raceStart = 0
local lastBoostTry = 0
local lastAbilityTap = 0
local ABILITY_EVERY = 2.5   -- s between E taps (items have 10-60 s cooldowns)

-- Eject test (attribute BotEjectTest, scenario eject-*): what a curious
-- player did in the 2026-10-25 playtest. Some seconds after GO it jumps
-- (what Space does: Humanoid.Jump) and reports whether it is still seated;
-- then its character dies, and it reports whether the new one is back in
-- the car (Modules/RaceSeat).
local _ejectDone = false
local function _seatedIn(model)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	local seatPart = hum and hum.SeatPart
	return seatPart ~= nil and model ~= nil and seatPart:IsDescendantOf(model)
end
local function _ejectTest(model)
	if _ejectDone or not LocalPlayer:GetAttribute("BotEjectTest") then return end
	_ejectDone = true
	task.spawn(function()
		local goAt = ReplicatedStorage:GetAttribute("RaceGoAt")
		if type(goAt) == "number" then task.wait(math.max(goAt - workspace:GetServerTimeNow(), 0)) end
		task.wait(6)
		for _ = 1, 5 do
			local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Jump = true end
			task.wait(0.2)
		end
		task.wait(1)
		report("eject", { stage = "jump", seated = _seatedIn(model) })
		task.wait(3)
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		local old = LocalPlayer.Character
		if hum then hum.Health = 0 end
		local t0 = os.clock()
		repeat task.wait(0.25) until (LocalPlayer.Character ~= old and _seatedIn(model)) or os.clock() - t0 > 12
		report("eject", { stage = "respawn", seated = LocalPlayer.Character ~= old and _seatedIn(model),
			after = math.floor((os.clock() - t0) * 10) / 10 })
	end)
end

-- What the driver sees: the angle (degrees, flat) between the camera's view
-- and the car's nose, sampled through the race and reported at its end
-- (`camera`). Two chase cams once fought and left SKY's view ~45° off.
local _camSamples = {}
RunService.Heartbeat:Connect(function()
	if phase ~= Constants.PHASES.RACING or not vehicle or not vehicle.PrimaryPart then return end
	if #_camSamples > 4000 then return end
	local cam = workspace.CurrentCamera
	local a, b = cam.CFrame.LookVector, vehicle.PrimaryPart.CFrame.LookVector
	a, b = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return end
	table.insert(_camSamples, math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))))
end)
-- How the car really drives (playtest 2026-10-29: "SKY: the plane does not
-- look forward and will not go forward", "OCEAN: sometimes it goes
-- backwards"): the nose against the road's direction, the travel against
-- the nose (sliding sideways), frames moving backwards, slow frames, and
-- every knock the server sends (how many pushed backwards). `drive` at the
-- race's end.
local _drv = nil
local function _drvReset() _drv = { nose = {}, crab = {}, back = 0, slow = 0, n = 0, knocks = 0, knockBack = 0, knockMax = 0,
	backAt = {}, seg = nil } end
_drvReset()
RemoteEvents.CarImpact.OnClientEvent:Connect(function(dvx, dvz)
	if phase ~= Constants.PHASES.RACING or not vehicle or not vehicle.PrimaryPart then return end
	local k = Vector3.new(dvx or 0, 0, dvz or 0)
	local m = k.Magnitude
	if m < 0.5 then return end
	local look = vehicle.PrimaryPart.CFrame.LookVector
	_drv.knocks += 1
	_drv.knockMax = math.max(_drv.knockMax, m)
	if k.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) < -0.5 then _drv.knockBack += 1 end
end)
RunService.Heartbeat:Connect(function()
	if phase ~= Constants.PHASES.RACING or not vehicle or not vehicle.PrimaryPart or not geo then return end
	if os.clock() - raceStart < 6 or #_drv.nose > 6000 then return end
	local primary = vehicle.PrimaryPart
	if primary.Anchored then return end
	local pos, v = primary.Position, primary.AssemblyLinearVelocity
	local look = Vector3.new(primary.CFrame.LookVector.X, 0, primary.CFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then return end
	look = look.Unit
	local flat = Vector3.new(v.X, 0, v.Z)
	local proj = geo:project(pos.X, pos.Z, _drv.seg, 3, pos.Y)
	_drv.seg = proj.seg
	local seg = geo.segments[proj.seg]
	local road = Vector3.new(seg.dx, 0, seg.dz)
	_drv.n += 1
	table.insert(_drv.nose, math.deg(math.acos(math.clamp(look:Dot(road.Unit), -1, 1))))
	if flat.Magnitude > 10 then
		table.insert(_drv.crab, math.deg(math.acos(math.clamp(look:Dot(flat.Unit), -1, 1))))
	end
	if flat:Dot(look) < -2 then
		_drv.back += 1
		if #_drv.backAt < 12 then table.insert(_drv.backAt, { s = math.floor(proj.s), v = math.floor(flat:Dot(look)) }) end
	end
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat and flat.Magnitude < seat.MaxSpeed * 0.35 then _drv.slow += 1 end
end)
local function _stats(list)
	if #list == 0 then return nil end
	table.sort(list)
	local sum, over = 0, 0
	for _, d in ipairs(list) do sum += d; if d > 20 then over += 1 end end
	return { mean = math.floor(sum / #list * 10) / 10, p90 = math.floor(list[math.ceil(#list * 0.9)] * 10) / 10,
		over20 = math.floor(over / #list * 1000) / 1000 }
end
local function _reportDrive()
	if _drv.n == 0 then return end
	report("drive", { biome = biome, frames = _drv.n, noseVsRoad = _stats(_drv.nose), travelVsNose = _stats(_drv.crab),
		backFrac = math.floor(_drv.back / _drv.n * 1000) / 1000, slowFrac = math.floor(_drv.slow / _drv.n * 1000) / 1000,
		knocks = _drv.knocks, knockBack = _drv.knockBack, knockMax = math.floor(_drv.knockMax * 10) / 10, backAt = _drv.backAt })
	_drvReset()
end

local function _reportCamera()
	local n = #_camSamples
	if n == 0 then return end
	table.sort(_camSamples)
	local sum, off = 0, 0
	for _, d in ipairs(_camSamples) do
		sum += d
		if d > 20 then off += 1 end
	end
	report("camera", { samples = n, mean = math.floor(sum / n * 10) / 10,
		median = math.floor(_camSamples[math.ceil(n / 2)] * 10) / 10,
		p90 = math.floor(_camSamples[math.ceil(n * 0.9)] * 10) / 10,
		over20 = math.floor(off / n * 1000) / 1000, biome = biome,
		cameraType = workspace.CurrentCamera.CameraType.Name })
	_camSamples = {}
end

RemoteEvents.VehicleSpawned.OnClientEvent:Connect(function(userId, model)
	if userId ~= LocalPlayer.UserId then return end
	_ejectTest(model)
	vehicle = model
	local data = TRACKS[biome or "FOREST"]
	if data then
		local track = require(data)
		geo = TrackGeometry.new(track.nodes, track.width, track.trackTop)
		autopilot = Autopilot.new(geo, Autopilot.PROFILES[driverName] or Autopilot.PROFILES.average, LocalPlayer.UserId)
	end
	raceStart = os.clock()
end)

InputSource.setOverride(function()
	if phase ~= Constants.PHASES.RACING or not vehicle or not vehicle.PrimaryPart then
		return nil
	end
	local primary = vehicle.PrimaryPart
	if not autopilot then
		return { W = true } -- no track data for this biome: just hold W
	end
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	local _, yaw = primary.CFrame:ToEulerAnglesYXZ()
	local v = primary.AssemblyLinearVelocity
	local isSky = primary:FindFirstChild("HoverPosition") ~= nil
	local keys, info = autopilot:update({
		hazards = _visibleHazards(primary.Position),
		x = primary.Position.X, z = primary.Position.Z, y = primary.Position.Y, yaw = yaw,
		speed = Vector3.new(v.X, 0, v.Z).Magnitude,
		forward = v:Dot(primary.CFrame.LookVector),
		maxSpeed = seat and seat.MaxSpeed or 40,
		turnSpeed = VehicleController.turnRate(seat and seat.TurnSpeed or 1, isSky),
		t = os.clock() - raceStart,
		isSky = isSky, biome = ReplicatedStorage:GetAttribute("Biome"),
		travelYaw = primary:GetAttribute("TravelYaw"),
	})
	if info.respawn then
		local ap = autopilot   -- the race may end (autopilot = nil) before the reply
		task.spawn(function()
			local r = RemoteEvents.RequestRespawn:InvokeServer()
			report("respawn", { result = r, s = math.floor(info.s) })
			if ap then ap:resetTracking() end
		end)
	end
	if os.clock() - lastBoostTry > 1 and math.abs(info.err) < 0.1 then
		lastBoostTry = os.clock()
		task.spawn(function() RemoteEvents.RequestBoost:InvokeServer() end)
	end
	-- Abilities: tap E every ABILITY_EVERY s (one frame down), through
	-- RacingClient's E handling like a keyboard press.
	if os.clock() - lastAbilityTap > ABILITY_EVERY then
		lastAbilityTap = os.clock()
		keys = table.clone(keys)
		keys.E = true
	end
	return keys
end)

-- ─── Phase driver ─────────────────────────────────────────────────────────────

local function onPhase(newPhase)
	if newPhase == phase then return end
	phase = newPhase
	if newPhase == Constants.PHASES.FARMING then
		_gadgetUsed = false
		task.spawn(farmLoop)
	elseif newPhase == Constants.PHASES.CRAFTING then
		task.spawn(craft)
	elseif newPhase == Constants.PHASES.RACING then
		task.spawn(raceTricks)
	elseif newPhase ~= Constants.PHASES.RACING then
		_reportCamera()
		_reportDrive()
		vehicle, autopilot = nil, nil
	end
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)

-- A bot client that loads slowly (6 Studio windows) can start after the
-- FARMING event went out; join the phase that is already running.
biome = biome or ReplicatedStorage:GetAttribute("Biome")
if ReplicatedStorage:GetAttribute("Phase") then
	onPhase(ReplicatedStorage:GetAttribute("Phase"))
end

-- What a player sees: the phase timers on screen, sampled every 2 s, so the
-- harness can check they count down (MatchHarness `hud`).
-- Every ScreenGui with that name (a respawn must not leave a second, frozen
-- copy behind) and the timer text of each.
local function timerTexts(guiName)
	local out = {}
	for _, gui in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if gui.Name == guiName and gui:IsA("ScreenGui") then
			local label = gui:FindFirstChild("TimerLabel", true)
			table.insert(out, { text = label and label.Text, shown = gui.Enabled })
		end
	end
	return out
end
task.spawn(function()
	while true do
		task.wait(2)
		if phase == Constants.PHASES.FARMING or phase == Constants.PHASES.CRAFTING then
			local guis = timerTexts(phase == Constants.PHASES.FARMING and "FarmingUI" or "CraftingUI")
			report("hud", { phase = phase, guis = guis, serverLeft = ReplicatedStorage:GetAttribute("PhaseEndsAt")
				and ReplicatedStorage:GetAttribute("PhaseEndsAt") - workspace:GetServerTimeNow() })
		end
	end
end)

report("ready", { farm = LocalPlayer:GetAttribute("BotFarmProfile"), driver = driverName })
