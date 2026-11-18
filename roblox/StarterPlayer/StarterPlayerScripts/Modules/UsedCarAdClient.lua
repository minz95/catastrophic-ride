-- UsedCarAdClient.lua
-- The filmer's half of the used-car reel (server: TestHarness/UsedCarAd;
-- LobbyFilmClient hands over when ReplicatedStorage FilmStory = "usedcar").
-- From FilmT0 it walks the avatar, says the lines in speech bubbles (its
-- own and Hank's) and moves the camera (9:16 crops of the window: keep
-- the subject in the middle):
--   0  out of the west gate               (behind, the AUTO STREET sign)
--   4  down the street, into the lot      (wide, the JUNK AUTO MART arch)
--   9  Hank: "Hey boss!"                  (two-shot)
--   14 the JUST IN car, its price card    (close)
--   16.5 the inspection card              (closer)
--   19 three offers, three no's           (over the shoulder, both ways)
--   30 walking off across the road        (wide)
--   32 Junk Motors: the duck, 1,200       (close on the stand)
--   35 trying it on                       (circling)
--   39 bought                             (close)
--   41 riding it down the street          (low, in front)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local UsedCarAdClient = {}

local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end

-- A speech bubble over `head` for `secs` (drawn here, not Roblox's bubble
-- chat: the film hides the CoreGui).
local function bubble(head, text, secs)
	if not head then return end
	local old = head:FindFirstChild("FilmBubble")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "FilmBubble"
	bb.Size = UDim2.new(0, 300, 0, 64)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local box = Instance.new("TextLabel")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	box.TextColor3 = Color3.fromRGB(25, 25, 30)
	box.Font = Enum.Font.GothamBold
	box.TextScaled = true
	box.Text = text
	box.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = box
	bb.Parent = head
	task.delay(secs or 2.4, function() if bb.Parent then bb:Destroy() end end)
end

function UsedCarAdClient.run(report)
	local LocalPlayer = Players.LocalPlayer
	local LobbyLayout = require(ReplicatedStorage.Shared.LobbyLayout)
	local O = LobbyLayout.ORIGIN
	while not ReplicatedStorage:GetAttribute("FilmT0") do task.wait(0.1) end
	local T0 = ReplicatedStorage:GetAttribute("FilmT0")
	local duckSpot = ReplicatedStorage:GetAttribute("FilmDuck") or (O + Vector3.new(-200, 0, -41))
	local function now() return workspace:GetServerTimeNow() - T0 end
	local function waitUntil(t) while now() < t do task.wait() end end
	local V = Vector3.new
	local function W(x, y, z) return O + V(x, y, z) end

	-- a clean picture: no HUD, chat, player list or prompts
	local StarterGui = game:GetService("StarterGui")
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	pcall(function() game:GetService("ProximityPromptService").Enabled = false end)

	local cam = workspace.CurrentCamera
	local shot
	RunService:BindToRenderStep("UsedCarAd", Enum.RenderPriority.Camera.Value + 1, function()
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
	local function myHead()
		local c = character()
		return c and c:FindFirstChild("Head")
	end
	local function hankHead()
		local hub = workspace:FindFirstChild("LobbyHub")
		local rig = hub and hub:FindFirstChild("Npc_hank")
		return rig and rig:FindFirstChild("Head")
	end
	local function standAt(feet, lookAt)
		local r, h = root(), hum()
		if not r then return end
		local y = (h and h.HipHeight or 2) + r.Size.Y / 2
		character():PivotTo(CFrame.lookAt(feet + V(0, y, 0), V(lookAt.X, feet.Y + y, lookAt.Z)))
	end
	local function walk(points)
		local h = hum()
		if not h then return end
		task.spawn(function()
			for _, p in ipairs(points) do
				h:MoveTo(p)
				local t0 = os.clock()
				while os.clock() - t0 < 6 do
					local r = root()
					if not r or (V(r.Position.X, p.Y, r.Position.Z) - p).Magnitude < 2 then break end
					task.wait(0.05)
				end
			end
		end)
	end
	local function look(from, to) return CFrame.lookAt(from, to) end
	local function pos()
		local r = root()
		return r and r.Position or W(0, 3, 0)
	end

	-- 0: out of the west gate, from behind; the AUTO STREET sign ahead.
	-- Put there again until it sticks (the first move after the film starts
	-- does not: take 1 stayed on the spawn), then walk.
	local start = W(-52, 0, 0)
	standAt(start, W(-90, 0, 0))
	for _ = 1, 20 do
		task.wait(0.1)
		local r = root()
		if r and (V(r.Position.X, start.Y, r.Position.Z) - start).Magnitude < 2 then break end
		standAt(start, W(-90, 0, 0))
	end
	walk({ W(-100, 0, 0), W(-124, 0, 6), W(-130, 0, 14) })
	local behind
	shot = function(t)
		-- from behind, a little high: the signs over the gate, the street beyond
		local p = pos()
		local want = p + V(11, 5.5, 2.5)
		behind = behind and behind:Lerp(want, 0.15) or want
		return look(behind, V(p.X - 24, O.Y + 7, O.Z))
	end
	-- 4: from the road, the lot's arch, the filmer walking in under it
	waitUntil(4)
	shot = function(t)
		local a = smooth((t - 4) / 5)
		local p = pos()
		return look(W(-110 - a * 6, 6, -7), p:Lerp(W(-128, 6, 17), 0.6))
	end

	-- 9: at the JUST IN car; Hank comes over
	waitUntil(9)
	local car = W(-140, 0, 24)
	local me = W(-138, 0, 15.5)
	local hank = ReplicatedStorage:GetAttribute("FilmHank") or W(-144, 0, 16.5)
	standAt(me, car)
	local mid = (me + hank) / 2
	shot = function(t)
		local a = smooth((t - 9) / 5)
		return look(mid + V(5 + a, 4.2, -7 + a), mid + V(0, 3.4, 1))
	end
	waitUntil(9.4)
	bubble(hankHead(), "Hey boss! Looking for a ride?", 2.6)
	waitUntil(12)
	standAt(me, hank)
	bubble(myHead(), "Just looking...", 2)

	-- 14: the car and its price card, then the inspection card
	waitUntil(14)
	standAt(me, car)
	local stand = W(-140, 0, 19.35)
	shot = function(t)
		local a = smooth((t - 14) / 2.5)
		return look(W(-134.5 + a, 5.5, 13.5), car:Lerp(stand, 0.45) + V(0, 3.4 - a * 0.4, 0))
	end
	waitUntil(15)
	bubble(hankHead(), "JUST IN! Won the vote!", 1.8)
	waitUntil(16.5)
	shot = function(t)
		local a = smooth((t - 16.5) / 2.5)
		return look(stand + V(1.2, 3.6 + a * 0.2, -3.2 + a * 0.6), stand + V(0, 3.4, 0))
	end

	-- 19: the haggling, over the shoulder both ways
	waitUntil(19)
	standAt(me, hank)
	local function onMe(t)
		return look(hank + V(-0.6, 5.2, -1.8), me + V(0, 4.2, 0))
	end
	local function onHank(t)
		return look(me + V(0.8, 5.2, -1.8), hank + V(0, 4.2, 0))
	end
	shot = onMe
	bubble(myHead(), "1,000?", 1.6)
	waitUntil(20.6)
	shot = onHank
	bubble(hankHead(), "2,500, boss. That's the total!", 2.2)
	waitUntil(23)
	shot = onMe
	bubble(myHead(), "1,500? I'll take it today!", 1.8)
	waitUntil(24.8)
	shot = onHank
	bubble(hankHead(), "It WON the vote! Only 50 copies!", 2.2)
	waitUntil(27)
	shot = onMe
	bubble(myHead(), "...1,200?", 1)
	waitUntil(28)
	shot = function(t)
		local a = smooth((t - 28) / 2)
		return look(mid + V(4.5, 4.2 + a * 0.6, -6), mid + V(0, 3.6, 0))
	end
	bubble(hankHead(), "Are you KIDDING me?!", 2)

	-- 30: walking off across the road
	waitUntil(30)
	walk({ W(-150, 0, 8), W(-150, 0, -14) })
	shot = function(t)
		local p = pos()
		return look(W(-136, 7, 26), p + V(0, 2, 0))
	end
	waitUntil(31)
	bubble(hankHead(), "Hey! Where are you going?!", 1.8)

	-- 32: Junk Motors, the brand new duck, 1,200
	waitUntil(32)
	local duckStand = duckSpot + V(0, 0, 5.5)
	standAt(duckStand, duckSpot)
	shot = function(t)
		local a = smooth((t - 32) / 3)
		return look(duckStand + V(3.5 - a * 1.5, 4.6, 4.5 - a), duckSpot + V(0, 2.6, 0))
	end
	waitUntil(33)
	bubble(myHead(), "Wait... a NEW one for 1,200?", 2)

	-- 35: trying it on (the server puts it round the waist), turning round
	waitUntil(35)
	standAt(duckStand, duckStand + V(6, 0, 0))
	shot = function(t)
		local ang = math.rad(-60 + (t - 35) / 4 * 90)
		local c = duckStand
		return look(c + V(math.cos(ang) * 8, 4.2, math.sin(ang) * 8), c + V(0, 2.2, 0))
	end
	waitUntil(37)
	bubble(myHead(), "Ooh. Comfy.", 1.6)

	-- 39: bought
	waitUntil(39)
	shot = function(t)
		return look(duckStand + V(2.5, 3.8, -4.5), duckStand + V(0, 2.8, 0))
	end
	bubble(myHead(), "1,200. DEAL!", 2)

	-- 41: riding it down the street, the camera backing away in front
	waitUntil(41)
	standAt(W(-250, 0, 2), W(-120, 0, 2))
	local h = hum()
	if h then h:MoveTo(W(-150, 0, 2)) end
	local follow
	shot = function()
		local p = pos()
		local want = p + V(10, 1.2, -2.5)   -- ahead of you (you walk east), backing away
		follow = follow and follow:Lerp(want, 0.12) or want
		return look(follow, p + V(0, 1.2, 0))
	end
	waitUntil(45)
	bubble(myHead(), "Anyone wanna race?", 3)
	waitUntil(UsedCarAdClient.END or 50)
	if report then report("usedcar_ad_client", { done = true }) end
	RunService:UnbindFromRenderStep("UsedCarAd")
end

return UsedCarAdClient
