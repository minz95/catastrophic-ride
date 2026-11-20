-- GpHud.lua
-- The Junk Grand Prix's screen, F1 TV style (GpClient drives it): the
-- timing tower (lap, the session's best laps), the lap clock with S1 S2 S3
-- in purple / green / yellow, the five start lights, team radio, speed in
-- km/h with the gear and a shift-light strip, the tyres, LEAVE / RESET
-- buttons and the results card. Built in code; one ScreenGui "GpHud".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GpTiming = require(ReplicatedStorage.Shared.GpTiming)
local ScreenFit = require(ReplicatedStorage.Shared.ScreenFit)

local GpHud = {}

local C = Color3.fromRGB
GpHud.COLOURS = {
	purple = C(170, 60, 230), green = C(40, 200, 80), yellow = C(240, 200, 30), invalid = C(120, 120, 128),
	none = C(60, 60, 68),
}
local DARK = C(16, 16, 22)
local RED = C(225, 20, 30)

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function label(parent, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = C(255, 255, 255),
		TextScaled = true, Text = "",
	}, parent)
	for k, v in pairs(props) do t[k] = v end
	return t
end

local function corner(p, r) make("UICorner", { CornerRadius = UDim.new(0, r or 6) }, p) return p end

local _gui, _el
GpHud.DESIGN = Vector2.new(1080, 640)   -- the screen the HUD is laid out for (px under the top bar)

--- Builds (or rebuilds) the HUD. Returns the element table.
function GpHud.build()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("GpHud")
	if old then old:Destroy() end
	local screen = make("ScreenGui", { Name = "GpHud", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 20,
		Enabled = false }, pg)
	-- everything is laid out for a ~1080 × 640 screen and scaled down to fit
	-- a smaller one (a phone, a small window: at full size the tower, clock,
	-- dash and tyres covered the whole road)
	local gui = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, screen)
	local fit = make("UIScale", { Name = "Fit" }, gui)
	ScreenFit.watch(function()
		local w, h, top = ScreenFit.view()
		local k = math.clamp(math.min((h - top) / GpHud.DESIGN.Y, w / GpHud.DESIGN.X), 0.4, 1)
		fit.Scale = k
		gui.Size = UDim2.fromScale(1 / k, 1 / k)
	end)
	local el = {}
	_gui, _el = screen, el

	-- timing tower (top left)
	local tower = corner(make("Frame", { Name = "Tower", Position = UDim2.new(0, 12, 0, 54), Size = UDim2.new(0, 230, 0, 230),
		BackgroundColor3 = DARK, BackgroundTransparency = 0.15 }, gui))
	el.lap = label(tower, { Name = "Lap", Size = UDim2.new(1, -12, 0, 30), Position = UDim2.new(0, 6, 0, 4),
		Text = "OUT LAP", TextXAlignment = Enum.TextXAlignment.Left })
	make("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 0, 36), BackgroundColor3 = RED, BorderSizePixel = 0 }, tower)
	el.rows = {}
	for k = 1, 7 do
		local row = label(tower, { Name = "Row" .. k, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 0, 40 + (k - 1) * 26),
			Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C(230, 230, 235) })
		el.rows[k] = row
	end

	-- lap clock and sectors (top centre)
	local clock = corner(make("Frame", { Name = "Clock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 300, 0, 86), BackgroundColor3 = DARK, BackgroundTransparency = 0.15 }, gui))
	el.time = label(clock, { Name = "Time", Size = UDim2.new(1, -16, 0, 42), Position = UDim2.new(0, 8, 0, 4), Text = "0.000",
		Font = Enum.Font.Code })
	el.sectors = {}
	for i = 1, 3 do
		local box = corner(make("Frame", { Name = "S" .. i, Size = UDim2.new(1 / 3, -8, 0, 30), Position = UDim2.new((i - 1) / 3, 4, 0, 50),
			BackgroundColor3 = GpHud.COLOURS.none }, clock), 4)
		el.sectors[i] = { box = box, text = label(box, { Size = UDim2.fromScale(1, 1), Text = "S" .. i, Font = Enum.Font.GothamBold }) }
	end
	el.last = label(gui, { Name = "Last", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.new(0, 300, 0, 22), Font = Enum.Font.GothamBold, TextStrokeTransparency = 0.4 })

	-- start lights (centre)
	local lights = make("Frame", { Name = "Lights", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 330, 0, 70), BackgroundColor3 = C(10, 10, 12), Visible = false }, gui)
	corner(lights, 10)
	el.lights = lights
	el.lamps = {}
	for k = 1, 5 do
		local lamp = make("Frame", { Size = UDim2.new(0, 50, 0, 50), Position = UDim2.new(0, 14 + (k - 1) * 63, 0, 10),
			BackgroundColor3 = C(50, 10, 12) }, lights)
		corner(lamp, 25)
		el.lamps[k] = lamp
	end

	-- the big message (lights out, track limits, chequered flag)
	-- (high on the screen: at mid height it covered the car going over)
	el.banner = label(gui, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.27, 0),
		Size = UDim2.new(0.7, 0, 0, 54), TextStrokeTransparency = 0.2, Visible = false })

	-- team radio (left middle)
	local radio = corner(make("Frame", { Name = "Radio", Position = UDim2.new(0, 12, 0.48, 0), Size = UDim2.new(0, 300, 0, 70),
		BackgroundColor3 = DARK, BackgroundTransparency = 0.1, Visible = false }, gui))
	make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0 }, radio)
	label(radio, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 14, 0, 4), Text = "TEAM RADIO",
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C(255, 90, 90) })
	el.radioText = label(radio, { Size = UDim2.new(1, -20, 0, 42), Position = UDim2.new(0, 14, 0, 24), Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true })
	el.radio = radio

	-- speed, gear, shift lights (bottom centre)
	local dash = corner(make("Frame", { Name = "Dash", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 290, 0, 96), BackgroundColor3 = DARK, BackgroundTransparency = 0.15 }, gui), 10)
	el.leds = {}
	for k = 1, 15 do
		local led = make("Frame", { Size = UDim2.new(0, 14, 0, 10), Position = UDim2.new(0, 14 + (k - 1) * 17.5, 0, 8),
			BackgroundColor3 = C(40, 40, 46), BorderSizePixel = 0 }, dash)
		corner(led, 3)
		el.leds[k] = led
	end
	el.speed = label(dash, { Name = "Speed", Size = UDim2.new(0, 150, 0, 54), Position = UDim2.new(0, 14, 0, 24), Text = "0",
		Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Right })
	label(dash, { Size = UDim2.new(0, 50, 0, 18), Position = UDim2.new(0, 168, 0, 56), Text = "KM/H", Font = Enum.Font.GothamBold,
		TextColor3 = C(180, 180, 190), TextXAlignment = Enum.TextXAlignment.Left })
	el.gear = label(dash, { Name = "Gear", Size = UDim2.new(0, 56, 0, 60), Position = UDim2.new(1, -66, 0, 22), Text = "N",
		TextColor3 = C(255, 220, 60) })

	-- tyres (bottom right)
	local tyres = corner(make("Frame", { Name = "Tyres", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -14),
		Size = UDim2.new(0, 120, 0, 120), BackgroundColor3 = DARK, BackgroundTransparency = 0.15 }, gui), 10)
	label(tyres, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 4), Text = "TYRES", Font = Enum.Font.GothamBold,
		TextColor3 = C(180, 180, 190) })
	make("Frame", { Size = UDim2.new(0, 22, 0, 56), Position = UDim2.new(0.5, -11, 0, 26), BackgroundColor3 = C(70, 70, 80),
		BorderSizePixel = 0 }, tyres)
	el.wheels = {}
	for k, p in ipairs({ { 22, 26 }, { 76, 26 }, { 22, 58 }, { 76, 58 } }) do
		local w = make("Frame", { Size = UDim2.new(0, 20, 0, 26), Position = UDim2.new(0, p[1], 0, p[2]),
			BackgroundColor3 = GpHud.COLOURS.green, BorderSizePixel = 0 }, tyres)
		corner(w, 4)
		el.wheels[k] = w
	end
	el.tyrePct = label(tyres, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -28), Text = "100%", Font = Enum.Font.Code })
	el.box = label(gui, { Name = "Box", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -140),
		Size = UDim2.new(0, 120, 0, 34), Text = "BOX BOX", TextColor3 = C(255, 255, 255), BackgroundColor3 = RED,
		BackgroundTransparency = 0, Visible = false })
	corner(el.box, 6)

	-- buttons (top right)
	local function button(name, text, pos)
		local b = make("TextButton", { Name = name, AnchorPoint = Vector2.new(1, 0), Position = pos, Size = UDim2.new(0, 110, 0, 36),
			BackgroundColor3 = DARK, BackgroundTransparency = 0.1, Text = text, TextScaled = true, Font = Enum.Font.GothamBlack,
			TextColor3 = C(255, 255, 255), AutoButtonColor = true }, gui)
		corner(b, 8)
		return b
	end
	el.leave = button("Leave", "LEAVE (L)", UDim2.new(1, -12, 0, 54))
	el.reset = button("Reset", "RESET (R)", UDim2.new(1, -12, 0, 96))
	el.reset.Visible = false
	el.help = label(gui, { Name = "Help", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -116),
		Size = UDim2.new(0, 520, 0, 20), Font = Enum.Font.GothamBold, TextColor3 = C(235, 235, 240),
		TextStrokeTransparency = 0.4, Text = "W / S gas and brake  ·  A / D steer  ·  V camera  ·  stop on your box for tyres" })

	-- results card
	local card = corner(make("Frame", { Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 300), BackgroundColor3 = DARK, BackgroundTransparency = 0.05, Visible = false }, gui), 12)
	make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = RED, BorderSizePixel = 0 }, card)
	el.cardTitle = label(card, { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 14), Text = "CHEQUERED FLAG" })
	el.cardLines = {}
	for k = 1, 6 do
		el.cardLines[k] = label(card, { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 60 + (k - 1) * 36),
			Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
	end
	el.card = card
	return el
end

function GpHud.show(on) if _gui then _gui.Enabled = on end end
function GpHud.el() return _el end

local _radioToken
function GpHud.radio(text, seconds)
	if not _el then return end
	_el.radioText.Text = text
	_el.radio.Visible = true
	local token = {}
	_radioToken = token
	task.delay(seconds or 4, function() if _radioToken == token and _el then _el.radio.Visible = false end end)
end

local _bannerToken
function GpHud.banner(text, colour, seconds)
	if not _el then return end
	_el.banner.Text = text
	_el.banner.TextColor3 = colour or C(255, 255, 255)
	_el.banner.Visible = true
	local token = {}
	_bannerToken = token
	task.delay(seconds or 2.5, function() if _bannerToken == token and _el then _el.banner.Visible = false end end)
end

--- Lights: `lit` red lamps (0 … 5), or "out" (all dark), or nil (hidden).
function GpHud.lights(lit)
	if not _el then return end
	if lit == nil then _el.lights.Visible = false return end
	_el.lights.Visible = true
	for k, lamp in ipairs(_el.lamps) do
		lamp.BackgroundColor3 = (lit ~= "out" and k <= lit) and C(255, 30, 30) or C(50, 10, 12)
	end
end

function GpHud.sector(i, colour, time)
	if not _el then return end
	local s = _el.sectors[i]
	if not s then return end
	s.box.BackgroundColor3 = GpHud.COLOURS[colour] or GpHud.COLOURS.none
	s.text.Text = time and GpTiming.format(time) or ("S" .. i)
end

function GpHud.clearSectors()
	for i = 1, 3 do GpHud.sector(i, "none") end
end

--- Speed (studs/s shown as km/h), gear, rpm (0..1), tyre wear (0..1), box call.
function GpHud.dash(kmh, gear, rpm, tyre, boxCall)
	if not _el then return end
	_el.speed.Text = tostring(math.floor(kmh + 0.5))
	_el.gear.Text = gear and tostring(gear) or "N"
	local lit = math.floor(rpm * 15 + 0.5)
	for k, led in ipairs(_el.leds) do
		local col = k <= 5 and C(40, 210, 80) or (k <= 10 and C(230, 40, 40) or C(70, 120, 255))
		led.BackgroundColor3 = k <= lit and col or C(40, 40, 46)
	end
	local col = tyre > 0.6 and GpHud.COLOURS.green or (tyre > 0.35 and GpHud.COLOURS.yellow or C(230, 40, 40))
	for _, w in ipairs(_el.wheels) do w.BackgroundColor3 = col end
	_el.tyrePct.Text = string.format("%d%%", math.floor(tyre * 100 + 0.5))
	_el.box.Visible = boxCall == true and (os.clock() % 0.8 < 0.55)
end

function GpHud.clock(text, lapText)
	if not _el then return end
	_el.time.Text = text
	if lapText then _el.lap.Text = lapText end
end

--- The tower's rows from ReplicatedStorage "GpBoard"; `me` (display name) highlighted.
function GpHud.board(me)
	if not _el then return end
	local ok, list = pcall(function() return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("GpBoard") or "[]") end)
	list = ok and list or {}
	for k, row in ipairs(_el.rows) do
		local e = list[k]
		if e then
			row.Text = string.format("%d  %s  %s", k, GpTiming.format(e.time), e.name)
			row.TextColor3 = (e.name == me) and C(255, 220, 60) or (k == 1 and GpHud.COLOURS.purple or C(230, 230, 235))
		else
			row.Text = ""
		end
	end
end

function GpHud.results(lines, title)
	if not _el then return end
	_el.cardTitle.Text = title or "CHEQUERED FLAG"
	for k, l in ipairs(_el.cardLines) do
		local e = lines[k]
		l.Text = e and e.text or ""
		l.TextColor3 = e and e.colour or C(255, 255, 255)
	end
	_el.card.Visible = true
end

function GpHud.hideResults() if _el then _el.card.Visible = false end end

return GpHud
