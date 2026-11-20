-- LugeHud.lua
-- The Alpine Luge's screen (LugeClient drives it), light and cheerful: the
-- run clock and your best at the top, speed small at the bottom, the
-- chairlift's way up as a bar, the gate's 3-2-1, big friendly words (GO!,
-- WHOOPS!, BONK!, FINISH), LEAVE and RESET. Laid out for a 1080 × 640
-- screen and scaled down to fit a smaller one (GpHud's way). One ScreenGui
-- "LugeHud" (TrackFocus keeps it while the town's screens step aside).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ScreenFit = require(ReplicatedStorage.Shared.ScreenFit)

local LugeHud = {}
LugeHud.DESIGN = Vector2.new(1080, 640)

local C = Color3.fromRGB
local CREAM = C(255, 248, 232)
local INK = C(70, 52, 40)
local RED = C(214, 60, 52)

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function label(parent, props)
	local t = make("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextColor3 = INK, TextScaled = true,
		Text = "" }, parent)
	for k, v in pairs(props) do t[k] = v end
	return t
end

local function round(p, r) make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, p) return p end

local _gui, _el

--- Builds (or rebuilds) the HUD; returns the element table.
function LugeHud.build()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("LugeHud")
	if old then old:Destroy() end
	local screen = make("ScreenGui", { Name = "LugeHud", ResetOnSpawn = false, DisplayOrder = 20, Enabled = false }, pg)
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, screen)
	local fit = make("UIScale", {}, root)
	ScreenFit.watch(function()
		local w, h, top = ScreenFit.view()
		local k = math.clamp(math.min((h - top) / LugeHud.DESIGN.Y, w / LugeHud.DESIGN.X), 0.4, 1)
		fit.Scale = k
		root.Size = UDim2.fromScale(1 / k, 1 / k)
	end)
	local el = {}
	_gui, _el = screen, el

	-- the clock (top centre): a wooden sign
	local clock = round(make("Frame", { Name = "Clock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 260, 0, 78), BackgroundColor3 = CREAM }, root), 14)
	make("UIStroke", { Color = C(150, 100, 60), Thickness = 3 }, clock)
	el.time = label(clock, { Name = "Time", Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 4), Text = "0.00" })
	el.best = label(clock, { Name = "Best", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 8, 0, 48), Text = "",
		TextColor3 = C(150, 100, 60) })

	-- speed (bottom centre)
	local speed = round(make("Frame", { Name = "Speed", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 170, 0, 58), BackgroundColor3 = CREAM, BackgroundTransparency = 0.1 }, root), 14)
	el.speed = label(speed, { Size = UDim2.new(0, 100, 1, -10), Position = UDim2.new(0, 8, 0, 5), Text = "0",
		TextXAlignment = Enum.TextXAlignment.Right })
	label(speed, { Size = UDim2.new(0, 52, 0, 22), Position = UDim2.new(0, 112, 0.5, -4), Text = "km/h", TextColor3 = C(150, 100, 60),
		TextXAlignment = Enum.TextXAlignment.Left })

	-- the chairlift's way up
	local lift = round(make("Frame", { Name = "Lift", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.new(0, 420, 0, 46), BackgroundColor3 = CREAM, Visible = false }, root), 12)
	label(lift, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 3), Text = "🚡 Up the chairlift · enjoy the view" })
	local track = round(make("Frame", { Size = UDim2.new(1, -20, 0, 12), Position = UDim2.new(0, 10, 0, 28), BackgroundColor3 = C(220, 205, 180) }, lift), 6)
	el.liftBar = round(make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C(80, 170, 110) }, track), 6)
	el.lift = lift

	-- the big words
	el.banner = label(root, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 640, 0, 76), TextColor3 = C(255, 255, 255), TextStrokeTransparency = 0, TextStrokeColor3 = INK,
		Visible = false })
	el.sub = label(root, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 52),
		Size = UDim2.new(0, 560, 0, 30), TextColor3 = CREAM, TextStrokeTransparency = 0.2, TextStrokeColor3 = INK, Visible = false })

	-- buttons (top right)
	local function button(name, text, y)
		local b = make("TextButton", { Name = name, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y),
			Size = UDim2.new(0, 120, 0, 38), BackgroundColor3 = CREAM, Text = text, TextScaled = true, Font = Enum.Font.FredokaOne,
			TextColor3 = INK, AutoButtonColor = true }, root)
		round(b, 10)
		make("UIStroke", { Color = C(150, 100, 60), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		return b
	end
	el.leave = button("Leave", "LEAVE (L)", 54)
	el.reset = button("Reset", "RESET (R)", 98)
	el.reset.Visible = false
	el.help = label(root, { Name = "Help", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -78),
		Size = UDim2.new(0, 560, 0, 20), Font = Enum.Font.GothamBold, TextColor3 = CREAM, TextStrokeTransparency = 0.3,
		Text = "A / D steer  ·  S brake  ·  W push off  ·  the hill does the rest" })
	return el
end

function LugeHud.show(on) if _gui then _gui.Enabled = on end end
function LugeHud.el() return _el end

local _bannerToken = 0
--- Big words for `seconds` (a sub line under them optional).
function LugeHud.banner(text, colour, seconds, sub)
	if not _el then return end
	_bannerToken += 1
	local token = _bannerToken
	local b = _el.banner
	b.Text = text
	b.TextColor3 = colour or C(255, 255, 255)
	b.Visible = true
	b.Size = UDim2.new(0, 560, 0, 60)
	TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.new(0, 640, 0, 76) }):Play()
	_el.sub.Text = sub or ""
	_el.sub.Visible = sub ~= nil
	task.delay(seconds or 1.6, function()
		if token == _bannerToken and _el then
			_el.banner.Visible = false
			_el.sub.Visible = false
		end
	end)
end

function LugeHud.clock(t, best)
	if not _el then return end
	_el.time.Text = t and string.format("%.2f", t) or "—"
	_el.best.Text = best and string.format("best %.2f", best) or "first run!"
end

function LugeHud.speed(kmh)
	if _el then _el.speed.Text = tostring(math.floor(kmh + 0.5)) end
end

function LugeHud.lift(f)
	if not _el then return end
	_el.lift.Visible = f ~= nil
	_el.help.Visible = f == nil   -- (on the lift the bar stood over the keys' line)
	if f then _el.liftBar.Size = UDim2.new(math.clamp(f, 0, 1), 0, 1, 0) end
end

return LugeHud
