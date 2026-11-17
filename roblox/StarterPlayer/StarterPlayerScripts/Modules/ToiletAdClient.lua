-- ToiletAdClient.lua
-- The filmer's half of the toilet ride reel (server: TestHarness/ToiletAd;
-- LobbyFilmClient hands over when ReplicatedStorage FilmStory = "toilet").
-- From FilmT0 it moves the avatar between the sets and the camera through
-- the shots (9:16 crops of the window: keep the subject in the middle):
--   0  hangout, the two of them           (wide)
--   3  the friend: "what is that?"        (over your shoulder)
--   6  you and the toilet: "won the vote" (close, you turn to show it)
--   11 the friend: "what's that?"         (your eyes)
--   14 the hall of fame statue            (three-quarter, rising)
--   22 the ad: on the turntable           (slow push, spotlight)
--   28 down the runway                    (low, the avatar walks at you)
--   33 the collection                     (wide, three pedestals)
--   38 hangout: both in toilets, dancing  (circling)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local ToiletAdClient = {}

local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end

function ToiletAdClient.run(report)
	local LocalPlayer = Players.LocalPlayer
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	while not ReplicatedStorage:GetAttribute("FilmT0") do task.wait(0.1) end
	local T0 = ReplicatedStorage:GetAttribute("FilmT0")
	local H = ReplicatedStorage:GetAttribute("FilmHangout")
	local S = ReplicatedStorage:GetAttribute("FilmStudio")
	local function now() return workspace:GetServerTimeNow() - T0 end
	local function waitUntil(t) while now() < t do task.wait() end end
	local V = Vector3.new

	-- a clean picture: no HUD, chat, player list or prompts
	local StarterGui = game:GetService("StarterGui")
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	pcall(function() game:GetService("ProximityPromptService").Enabled = false end)

	local cam = workspace.CurrentCamera
	local shot
	RunService:BindToRenderStep("ToiletAd", Enum.RenderPriority.Camera.Value + 1, function()
		for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled then g.Enabled = false end
		end
		local cf = shot and shot(now())
		if cf then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = 60
			cam.CFrame = cf
		end
	end)

	local function character() return LocalPlayer.Character end
	local function root()
		local c = character()
		return c and c:FindFirstChild("HumanoidRootPart")
	end
	local function hum()
		local c = character()
		return c and c:FindFirstChildOfClass("Humanoid")
	end
	local function standAt(feet, lookAt)
		local r, h = root(), hum()
		if not r then return end
		local y = (h and h.HipHeight or 2) + r.Size.Y / 2
		character():PivotTo(CFrame.lookAt(feet + V(0, y, 0), V(lookAt.X, feet.Y + y, lookAt.Z)))
	end
	local function headOf(model)
		local hd = model and model:FindFirstChild("Head")
		return hd and hd.Position
	end
	local function friend()
		local sets = workspace:FindFirstChild("FilmSets")
		return sets and sets:FindFirstChild(ReplicatedStorage:GetAttribute("FilmFriend") or "doyun0412")
	end
	local function look(from, to) return CFrame.lookAt(from, to) end

	-- 0: the hangout (put there again until it sticks: the first move did
	-- not, the first take's wide shot had only the friend)
	standAt(H, H + V(6, 0, 0))
	task.spawn(function()
		while now() < 3 do
			local r = root()
			if r and (Vector3.new(r.Position.X, H.Y, r.Position.Z) - H).Magnitude > 1 then standAt(H, H + V(6, 0, 0)) end
			task.wait(0.25)
		end
	end)
	shot = function(t)
		local a = smooth(t / 3)
		return look(H + V(3, 4.2, -15 + a * 1.5), H + V(3, 2.6, 0))
	end
	-- 3: the friend over your shoulder
	waitUntil(3)
	shot = function(t)
		local f = headOf(friend()) or (H + V(6, 4.5, 0))
		local a = smooth((t - 3) / 3)
		return look(H + V(-2.6 + a * 0.4, 5, 2.2), f - V(0, 0.6, 0))
	end
	-- 6: you and the toilet, turning to show it
	waitUntil(6)
	shot = function(t)
		local a = smooth((t - 6) / 5)
		return look(H + V(5.5 - a * 0.8, 3.6, 3.6 - a * 0.6), H + V(0, 2.2, 0))
	end
	waitUntil(7.2)
	standAt(H, H + V(0, 0, 6))       -- side on to the camera: the whole toilet
	waitUntil(9.6)
	standAt(H, H + V(6, 0, 0))
	-- 11: the friend from your eyes
	waitUntil(11)
	shot = function(t)
		local f = headOf(friend()) or (H + V(6, 4.5, 0))
		return look(H + V(0.6, 4.6, 0.3), f - V(0, 0.4, 0))
	end

	-- 14: the hall of fame (you are out of the picture: in the studio)
	waitUntil(14)
	standAt(S + V(0, 1, 0), S + V(0, 1, -10))
	local stage = LobbyLayout.STAGE.at
	shot = function(t)
		local a = smooth((t - 14) / 8)
		-- from high over the bunting, the whole statue and its name
		return look(stage + V(-5 + a * 2, 22 - a * 3, 40 - a * 6), stage + V(0, 9, 0))
	end

	-- 22: the turntable; a light on you for the dark studio
	waitUntil(22)
	local r = root()
	if r then
		local glow = Instance.new("PointLight")
		glow.Name = "FilmGlow"
		glow.Range = 12
		glow.Brightness = 1.6
		glow.Color = Color3.fromRGB(255, 240, 220)
		glow.Parent = r
	end
	standAt(S + V(0, 1, 0), S + V(0, 1, -10))
	if r then r.Anchored = true end
	local base = r and r.CFrame
	shot = function(t)
		local a = smooth((t - 22) / 6)
		local rr = root()
		if rr and base then
			rr.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, (t - 22) / 6 * math.pi * 2, 0) * (base - base.Position)
		end
		return look(S + V(0, 3.6 - a * 0.4, -10 + a * 2), S + V(0, 3, 0))
	end
	-- 28: down the runway at you
	waitUntil(28)
	if r then r.Anchored = false end
	standAt(S + V(0, 0, 46), S + V(0, 0, 0))
	local h = hum()
	local walkSpeed = h and h.WalkSpeed
	if h then
		h.WalkSpeed = 7
		h:MoveTo(S + V(0, 0, 18))
	end
	local runCam = nil
	shot = function()
		local rr = root()
		local p = rr and rr.Position or S + V(0, 3, 30)
		-- low, a few steps ahead of you, backing away as you come
		local want = p + V(1.8, -0.8, -8)
		runCam = runCam and runCam:Lerp(want, 0.1) or want
		return look(runCam, p + V(0, 0.4, 0))
	end
	-- 33: the collection
	waitUntil(33)
	if h then h.WalkSpeed = walkSpeed end
	standAt(S + V(0, 1, 0), S + V(0, 1, -10))
	shot = function(t)
		-- along the collection: the cart, you, the duck
		local a = smooth((t - 33) / 5)
		local x = -12 + 24 * a
		return look(S + V(x * 0.8, 3.6, -11), S + V(x, 2.4, 0))
	end

	-- 38: back in the hangout, dancing
	waitUntil(38)
	standAt(H, H + V(6, 0, 0))
	waitUntil(38.6)
	local animator = h and h:FindFirstChildOfClass("Animator")
	if animator then
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://507771019"
		local track = animator:LoadAnimation(a)
		track.Looped = true
		track:Play()
	end
	shot = function(t)
		local a = (t - 38) / 10
		local ang = math.rad(-110 + 70 * a)
		local c = H + V(3, 0, 0)
		return look(c + V(math.cos(ang) * 13, 4, math.sin(ang) * 13), c + V(0, 2.4, 0))
	end
	waitUntil(49)
	if report then report("toilet_ad_client", { done = true }) end
	RunService:UnbindFromRenderStep("ToiletAd")
end

return ToiletAdClient
