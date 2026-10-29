-- SideButtons.lua
-- The SHOP and ITEMS buttons sit at the left edge, mid-height. TutorialUI's
-- key list (KeyStrip) grows up from the bottom-left corner: on a short
-- window, or with ten rows of FARMING keys, its top rows ended up under the
-- buttons (playtest 2026-10-30, a screenshot: "Grab" and "Steal" hidden).
-- keepClear moves a button up so its bottom stays GAP over the strip.

local Players = game:GetService("Players")

local SideButtons = {}

SideButtons.GAP = 8         -- px between a button and the key list
SideButtons.TOP_MIN = 8     -- px: never above this in its ScreenGui
SideButtons.EVERY = 0.25    -- s between two checks

local function strip()
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, g in ipairs(pg and pg:GetChildren() or {}) do
		if g.Name == "TutorialUI" and g:IsA("ScreenGui") then
			local s = g:FindFirstChild("KeyStrip")
			if s and s.Visible and g.Enabled then return s end
		end
	end
	return nil
end

--- Where a button of height `h` goes: mid-height of `screen` (a ScreenGui,
-- `screenH` px tall), or higher when the key list's top (`stripTop`, in the
-- same ScreenGui's pixels; nil = no list) is under it. Returns the Y of the
-- button's centre. Pure: the spec checks it.
function SideButtons.centreY(screenH, h, stripTop)
	local y = screenH / 2
	if stripTop and y + h / 2 > stripTop - SideButtons.GAP then
		y = stripTop - SideButtons.GAP - h / 2
	end
	return math.max(y, SideButtons.TOP_MIN + h / 2)
end

--- Keeps `btn` (left edge, x px in) clear of the key list while it is a
-- child of `screen` (ShopUI moves its button into the crafting panel).
function SideButtons.keepClear(btn, screen, x)
	task.spawn(function()
		while btn.Parent ~= nil or screen.Parent ~= nil do
			if btn.Parent == screen then
				local s = strip()
				local top = s and (s.AbsolutePosition.Y - screen.AbsolutePosition.Y) or nil
				local h = btn.AbsoluteSize.Y > 0 and btn.AbsoluteSize.Y or 40
				local y = SideButtons.centreY(screen.AbsoluteSize.Y, h, top)
				btn.AnchorPoint = Vector2.new(0, 0.5)
				btn.Position = UDim2.new(0, x, 0, math.floor(y))
			end
			task.wait(SideButtons.EVERY)
		end
	end)
end

return SideButtons
