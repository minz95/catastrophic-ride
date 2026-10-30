-- ScreenFit.lua
-- Fitting a panel into the screen under Roblox's top bar (phones: about
-- 667 × 375 with a 36-58 px bar). Panels sized against the whole viewport
-- ran under the bar: the shop's close button and the crafting screen's
-- ITEMS button sat under Roblox's own menu buttons (launch check 2026-10-30).
-- A UIScale shrinks a GuiObject about its AnchorPoint, so a scaled panel
-- should be anchored at its centre.

local GuiService = game:GetService("GuiService")

local ScreenFit = {}

-- Screen width, height and the top bar's height (px).
function ScreenFit.view()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1000, 800)
	local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
	local top = (ok and typeof(inset) == "Vector2") and inset.Y or 0
	return vp.X, vp.Y, top
end

-- UIScale for a pw × ph panel to fit under the top bar with `margin` px on
-- every side (at most 1), plus the view.
function ScreenFit.scale(pw, ph, margin)
	margin = margin or 16
	local w, h, top = ScreenFit.view()
	return math.min(1, (w - 2 * margin) / pw, (h - top - 2 * margin) / ph), w, h, top
end

-- Call fn now and whenever the screen changes size (rotation, window).
function ScreenFit.watch(fn)
	fn()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fn) end
end

-- Fixed-size text under `root` (a panel with a UIScale of k) stays at least
-- minPx tall on screen: the crafting screen at 0.66 on a phone drew its item
-- names at 6 px. Text added later (cards rebuilt) gets the same; text that
-- does not wrap is cut with "…" rather than run out of its box.
function ScreenFit.keepReadable(root, getK, minPx)
	local function fix(d)
		if not (d:IsA("TextLabel") or d:IsA("TextButton")) or d.TextScaled then return end
		local base = d:GetAttribute("BaseTextSize")
		if not base then
			base = d.TextSize
			d:SetAttribute("BaseTextSize", base)
		end
		d.TextSize = math.max(base, math.ceil(minPx / math.max(getK(), 0.1)))
		if not d.TextWrapped then d.TextTruncate = Enum.TextTruncate.AtEnd end
	end
	local function all()
		for _, d in ipairs(root:GetDescendants()) do fix(d) end
	end
	root.DescendantAdded:Connect(function(d) task.defer(fix, d) end)
	return all
end

return ScreenFit
