-- LobbyFilmClient.lua
-- The filmer's half of the lobby reel (server: TestHarness/LobbyFilm; run by
-- BotDriver on a harness bot client with the attribute LobbyFilm). From
-- ReplicatedStorage's FilmT0 (server time) it walks the avatar and moves the
-- camera through the shots:
--   0  over the arch to the stage          (crane down, the avatar walks in)
--   7  the statue: you, twice your size    (low, from the front, pushing in)
--   15 off to your Legend pad              (the normal follow camera)
--   22 at the pad, the crowd in front       (high over the crowd)
--   34 they buy copies, the notices come    (wider, from the side)
--   50 the shop's Legend tab                (UI)
--   58 a dance in front of the crowd       (circling you)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LobbyFilmClient = {}

local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end

function LobbyFilmClient.run(report)
	local LocalPlayer = Players.LocalPlayer
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	local O = LobbyLayout.ORIGIN
	local function W(x, y, z) return O + Vector3.new(x, y, z) end

	while not ReplicatedStorage:GetAttribute("FilmT0") do task.wait(0.1) end
	if ReplicatedStorage:GetAttribute("FilmStory") == "toilet" then   -- TestHarness/ToiletAd
		return require(script.Parent.ToiletAdClient).run(report)
	end
	local T0 = ReplicatedStorage:GetAttribute("FilmT0")
	local function now() return workspace:GetServerTimeNow() - T0 end
	local function waitUntil(t) while now() < t do task.wait() end end

	local pad = LobbyLayout.legendSpot(1)
	local toCentre = (Vector3.new(O.X, pad.Y, O.Z) - pad).Unit
	local side = Vector3.new(-toCentre.Z, 0, toCentre.X)
	local standAt = pad + toCentre * 4        -- LobbyFilm.spots F: the crowd stands round it
	local stageSpot = W(0, 0, -31)            -- in front of the statue, between the crowd
	local front = pad + toCentre * 10         -- the finale: in front of the crowd

	-- a clean picture: no HUD, buttons, player list or prompts; Roblox's
	-- corner notices (the achievement, every sale) and chat bubbles stay
	local StarterGui = game:GetService("StarterGui")
	for _, t in ipairs({ Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }) do
		pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
	end
	pcall(function() game:GetService("ProximityPromptService").Enabled = false end)
	pcall(function() game:GetService("ProximityPromptService").MaxPromptsVisible = 0 end)
	local showShop = false
	local KEEP = { TownTalk = true }

	local cam = workspace.CurrentCamera
	local shot   -- function(t) → CFrame, or nil for the follow camera
	local function look(from, to) return CFrame.lookAt(from, to) end
	local function rootPos()
		local c = LocalPlayer.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		return r and r.Position or LobbyLayout.SPAWN
	end
	RunService:BindToRenderStep("LobbyFilm", Enum.RenderPriority.Camera.Value + 1, function()
		for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and not KEEP[g.Name] then
				local on = showShop and g.Name == "ShopUI"
				if g.Enabled ~= on then g.Enabled = on end
			end
		end
		local t = now()
		local cf = shot and shot(t)
		if cf then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = 60
			cam.CFrame = cf
		elseif cam.CameraType == Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Custom
		end
	end)

	local function hum()
		local c = LocalPlayer.Character
		return c and c:FindFirstChildOfClass("Humanoid")
	end
	local function walk(points)
		for _, p in ipairs(points) do
			local h = hum()
			if not h then return end
			h:MoveTo(p)
			local t0 = os.clock()
			local root = h.Parent:FindFirstChild("HumanoidRootPart")
			while root and (Vector3.new(root.Position.X, p.Y, root.Position.Z) - p).Magnitude > 2 and os.clock() - t0 < 8 do
				task.wait()
			end
		end
	end
	local function faceTowards(p)
		local c = LocalPlayer.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(p.X, root.Position.Y, p.Z))
		end
	end

	-- 0: crane down over the arch while walking in
	shot = function(t)
		local a = smooth(t / 7)
		local from = W(0, 46, 112):Lerp(W(0, 20, 58), a)
		return look(from, W(0, 6, -40))
	end
	waitUntil(0.5)
	task.spawn(walk, { W(9, 0, 30), W(7, 0, -20), stageSpot })

	-- 7: the statue, low and pushing in
	waitUntil(7)
	shot = function(t)
		local a = smooth((t - 7) / 8)
		local from = W(0, 3, -17):Lerp(W(0, 3.6, -22), a)
		return look(from, W(0, 8.5, -46))
	end
	waitUntil(10)
	faceTowards(W(0, 0, 0))   -- to the camera, the statue behind

	-- 15: off to the pad, the camera following behind
	waitUntil(15)
	task.spawn(walk, { W(-12, 0, -6), standAt })
	local back = nil
	shot = function()
		local c = LocalPlayer.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if not root then return back end
		local fwd = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if fwd.Magnitude < 0.1 then return back end
		local want = root.Position - fwd.Unit * 11 + Vector3.new(0, 5, 0)
		local from = back and back.Position:Lerp(want, 0.08) or want
		back = look(from, root.Position + Vector3.new(0, 1.5, 0))
		return back
	end

	-- 22: at the pad, over the crowd's heads
	waitUntil(22)
	local over = standAt + toCentre * 11 + Vector3.new(0, 4, 0)
	faceTowards(over)
	shot = function(t)
		local a = smooth((t - 22) / 12)
		local from = over + side * (-2 + 4 * a) - toCentre * (2.5 * a)
		return look(from, standAt + Vector3.new(0, 2.2, 0))
	end

	-- what this client sees of the shop hat (report film_hat_client)
	if report then
		local c = LocalPlayer.Character
		local hat = c and c:FindFirstChild("ShopHat")
		local head = c and c:FindFirstChild("Head")
		local info = { hat = hat ~= nil }
		if hat and head then
			local n, maxL, maxT, dy = 0, 0, 0, -math.huge
			for _, p in ipairs(hat:GetDescendants()) do
				if p:IsA("BasePart") then
					n += 1
					maxL = math.max(maxL, p.LocalTransparencyModifier)
					maxT = math.max(maxT, p.Transparency)
					dy = math.max(dy, (p.Position - head.Position).Magnitude)
				end
			end
			info.parts, info.localTransparency, info.transparency, info.farthest = n, maxL, maxT, dy
		end
		report("film_hat_client", info)
	end

	-- 34: wider, from the side: copies appear on the buyers
	waitUntil(34)
	shot = function(t)
		local a = smooth((t - 34) / 16)
		local from = standAt + toCentre * (13 - a) + side * (6 - a) + Vector3.new(0, 7, 0)
		return look(from, standAt + toCentre * 2 + Vector3.new(0, 1, 0))
	end

	-- 50: the shop on the Legend tab
	waitUntil(50)
	showShop = true
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if g.Name == "ShopUI" and g:IsA("ScreenGui") then
			local ev = g:FindFirstChild("Open")
			if ev then ev:Fire("legend") end
		end
	end
	waitUntil(57)
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if g.Name == "ShopUI" and g:IsA("ScreenGui") then
			local panel = g:FindFirstChild("Panel")
			if panel then panel.Visible = false end
		end
	end
	showShop = false
	task.spawn(walk, { front })

	-- 58: a dance in front of the crowd, the camera circling
	waitUntil(58)
	faceTowards(front + toCentre * 10)
	local h = hum()
	local animate = h and h.Parent:FindFirstChild("Animate")
	local dance = animate and animate:FindFirstChild("dance")
	local anim = dance and dance:FindFirstChildWhichIsA("Animation")
	local animator = h and h:FindFirstChildOfClass("Animator")
	if anim and animator then
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end
	shot = function(t)
		local a = (t - 58) / 12
		local ang = math.rad(-30 + 60 * a)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, ang) * toCentre
		local p = rootPos()
		return look(p + dir * 9 + Vector3.new(0, 2.5, 0), p + Vector3.new(0, 1.5, 0) - toCentre * 3)
	end
	waitUntil(72)
	RunService:UnbindFromRenderStep("LobbyFilm")
end

return LobbyFilmClient
