-- Snapshot.lua (client)
-- 📸: a picture of a ride to share (playtest 2026-11-15: "it must be easy to
-- take a snapshot"). `Snapshot.card` lays a full-screen card over everything
-- (the ride big, its name, items and grade, the game's name), takes a
-- screenshot with CaptureService (it captures the GUI too), then offers
-- the device's share sheet (PromptShareCapture), or saving it to the
-- Captures gallery where sharing is not available, and removes the card.

local Players           = game:GetService("Players")

local RideCard = require(script.Parent.RideCard)

local Snapshot = {}

Snapshot.GAME = "CATASTROPHIC RIDE"
Snapshot.SETTLE = 0.35   -- s for the card's viewports to draw before the shot

local _busy = false

local function capture(done)
	local ok = pcall(function()
		local CaptureService = game:GetService("CaptureService")
		CaptureService:CaptureScreenshot(function(contentId)
			task.defer(done)
			local shared = pcall(function()
				CaptureService:PromptShareCapture(contentId, "", function() end, function() end)
			end)
			if not shared then
				pcall(function() CaptureService:PromptSaveCapturesToGallery({ contentId }, function() end) end)
			end
		end)
	end)
	if not ok then done() end
end

local function text(parent, str, size, pos, font, colour)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size, l.Position = size, pos
	l.Text, l.Font = str, font or Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = colour or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

--- `rides` = { { model, char, name, items, grade } } (one: a big picture of
-- your ride; more: side by side, "vs"); `title` over them.
function Snapshot.card(rides, title)
	if _busy or #rides == 0 then return end
	_busy = true
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name           = "SnapshotCard"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder   = 100
	gui.ResetOnSpawn   = false
	gui.Parent         = pg
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 14, 36)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	text(bg, title, UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.05, 0.03), nil, Color3.fromRGB(255, 210, 60))
	local n = #rides
	local w = 0.9 / n
	for i, ride in ipairs(rides) do
		local slot = Instance.new("Frame")
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromScale(w - 0.02, 0.62)
		slot.Position = UDim2.fromScale(0.05 + (i - 1) * w + 0.01, 0.15)
		slot.Parent = bg
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = slot
		local view = RideCard.view(slot, ride.model, ride.char)
		if view then local vc = Instance.new("UICorner"); vc.CornerRadius = UDim.new(0, 14); vc.Parent = view end
		text(bg, ride.name or "", UDim2.fromScale(w - 0.02, 0.06), UDim2.fromScale(0.05 + (i - 1) * w + 0.01, 0.78))
		text(bg, ride.items or "", UDim2.fromScale(w - 0.02, 0.05), UDim2.fromScale(0.05 + (i - 1) * w + 0.01, 0.84),
			Enum.Font.GothamBold, Color3.fromRGB(200, 210, 240))
		if ride.grade then
			text(slot, ride.grade, UDim2.fromOffset(56, 56), UDim2.new(0, 10, 0, 10), nil, Color3.fromRGB(255, 210, 60))
		end
		if n > 1 and i < n then
			text(bg, "VS", UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.05 + i * w - 0.03, 0.4), nil, Color3.fromRGB(255, 90, 90))
		end
	end
	text(bg, Snapshot.GAME, UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.25, 0.91), nil, Color3.fromRGB(150, 230, 255))
	task.delay(Snapshot.SETTLE, function()
		capture(function()
			gui:Destroy()
			_busy = false
		end)
	end)
end

--- A 📸 button (`size`, `position`) in `parent` that calls `onPress`.
function Snapshot.button(parent, size, position, label, onPress)
	local b = Instance.new("TextButton")
	b.Name             = "Snapshot"
	b.Size, b.Position = size, position
	b.BackgroundColor3 = Color3.fromRGB(70, 90, 170)
	b.Text             = label or "📸"
	b.TextColor3       = Color3.new(1, 1, 1)
	b.TextScaled       = true
	b.Font             = Enum.Font.GothamBlack
	b.Parent           = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	b.Activated:Connect(onPress)
	return b
end

return Snapshot
