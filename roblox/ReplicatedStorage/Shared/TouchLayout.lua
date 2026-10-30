-- TouchLayout.lua
-- Where TouchControls puts its buttons, as a pure function of the screen, so
-- the layout can be checked for phone and tablet screens without a device
-- (tests/specs/phone_layout, tools/studio/ui_overlap.py --phone).
--
-- col counts from the right edge, row from the bottom (1 = bottom-right,
-- under the right thumb). The grid is anchored bottom-right above Roblox's
-- jump button and below the race position list; on a short screen where
-- that leaves too little room it moves left of the list.

local TouchLayout = {}

TouchLayout.SIZE, TouchLayout.GAP = 74, 12   -- full-size button and gap (scaled down on small screens)
TouchLayout.MIN_SCALE = 0.55
TouchLayout.TOP_BAR   = 60                   -- Roblox's top bar buttons
TouchLayout.MARGIN    = 24
TouchLayout.MIN_TOUCH = 36                   -- px: a small button never shrinks below this
TouchLayout.STICK_W   = 0.4                  -- share of the width where Roblox's thumbstick starts

TouchLayout.LAYOUT = {
	-- Four at most (playtest 2026-10-30: "the farm is covered in buttons").
	-- DROP is a double tap on a bag slot (FarmingUI), EMOTE an icon at the
	-- top right (TouchControls).
	FARMING = {
		{ text = "GRAB",  key = Enum.KeyCode.E, col = 1, row = 1, color = Color3.fromRGB(60, 170, 90) },
		{ text = "PUNCH", key = Enum.KeyCode.F, col = 2, row = 1, color = Color3.fromRGB(210, 80, 60) },
		{ text = "GUARD", key = Enum.KeyCode.G, col = 1, row = 2, color = Color3.fromRGB(70, 110, 200) },
		{ text = "SMOKE", key = Enum.KeyCode.T, col = 2, row = 2, color = Color3.fromRGB(90, 90, 100), gadget = true },
	},
	RACING = {
		{ text = "BOOST", key = Enum.KeyCode.F, col = 1, row = 1, color = Color3.fromRGB(60, 150, 240) },
		{ text = "DRIFT", key = Enum.KeyCode.LeftShift, col = 2, row = 1, color = Color3.fromRGB(230, 160, 35) },
		{ text = "ITEM",  key = Enum.KeyCode.E, col = 1, row = 2, color = Color3.fromRGB(170, 80, 220) },
		{ text = "RESET", key = Enum.KeyCode.R, col = 3, row = 1, color = Color3.fromRGB(110, 110, 125), small = true },
		{ text = "BOMB",  key = Enum.KeyCode.T, col = 2, row = 2, color = Color3.fromRGB(220, 90, 40), attr = "RaceTrick" },
		{ text = "😜",    key = Enum.KeyCode.Q, col = 3, row = 2, color = Color3.fromRGB(240, 200, 60), small = true },
		{ text = "▲",     key = Enum.KeyCode.Space, col = 4, row = 2, color = Color3.fromRGB(80, 190, 230), biome = "SKY" },
		{ text = "▼",     key = Enum.KeyCode.LeftControl, col = 4, row = 1, color = Color3.fromRGB(80, 140, 200), biome = "SKY" },
	},
}

-- Roblox's own touch controls (screen pixels, x, y, w, h; from its
-- TouchJump / DynamicThumbstick): the jump button and the left part of the
-- screen where a touch starts the thumbstick (a button there takes the
-- touch instead).
function TouchLayout.robloxZones(w, h, inset)
	inset = inset or 0
	local small = math.min(w, h) <= 500
	local js = small and 70 or 120
	local jx, jy = small and 95 or 170, small and 90 or 210
	local top = inset + (h - inset) / 3
	return {
		jump = { w - jx, h - jy, js, js },
		thumbstick = { 0, top, w * TouchLayout.STICK_W, h - top },
	}
end

-- The grid for one phase on a w × h screen.
--   visible(b) → whether button entry b shows (gadget / trick / biome)
--   list = { bottom = y, left = x } of the race position list, or nil
-- Returns { frame = {x, y, w, h}, framePos = {right, bottom}, scale, s, g,
-- buttons = { { b = entry, box = {x, y, w, h}, offset = {right, bottom}, size } } }
-- (offset: the button's bottom-right corner from the frame's).
function TouchLayout.compute(w, h, phase, visible, list)
	local L = TouchLayout
	local entries = L.LAYOUT[phase]
	if not entries then return nil end
	local small = math.min(w, h) <= 500
	local bottom = small and 100 or 220
	local cols, rows = 1, 1
	for _, b in ipairs(entries) do
		if visible(b) or not b.biome then
			cols = math.max(cols, b.col)
			rows = math.max(rows, b.row)
		end
	end
	local gridW = cols * L.SIZE + (cols - 1) * L.GAP
	local gridH = rows * L.SIZE + (rows - 1) * L.GAP
	local right, top = L.MARGIN, L.TOP_BAR
	if list then top = math.max(top, list.bottom + 8) end
	local scale = math.min(1, (h - bottom - top) / gridH, (w * 0.5 - L.MARGIN) / gridW)   -- right half only
	if list and scale < L.MIN_SCALE then
		-- too little room under the list even at the smallest size: stand
		-- left of it instead (at 0.75 this put the race buttons in the
		-- middle of a phone screen, over the car, with six racers listed)
		right = (w - list.left) + 12
		-- never into the thumbstick's side (a thumb going for the stick
		-- pressed SKY's ▲ / ▼ on a phone with six racers in the list)
		top = L.TOP_BAR
		local room = (w - right) - (w * L.STICK_W + L.MARGIN / 2)
		scale = math.min(1, (h - bottom - top) / gridH, room / gridW)
	end
	scale = math.max(L.MIN_SCALE, scale)
	local s, g = L.SIZE * scale, L.GAP * scale
	local fw, fh = gridW * scale, gridH * scale
	local out = {
		frame = { w - right - fw, h - bottom - fh, fw, fh },
		framePos = { right, bottom },
		scale = scale, s = s, g = g, buttons = {},
	}
	for _, b in ipairs(entries) do
		local bs = b.small and math.max(s * 0.75, math.min(s, L.MIN_TOUCH)) or s
		local inset = (s - bs) / 2
		local ox, oy = (b.col - 1) * (s + g) + inset, (b.row - 1) * (s + g) + inset
		table.insert(out.buttons, {
			b = b, size = bs, offset = { ox, oy },
			box = { w - right - ox - bs, h - bottom - oy - bs, bs, bs },
			visible = visible(b),
		})
	end
	return out
end

-- The farm bag on a touch screen (FarmingUI): two rows of four between the
-- thumbstick's side and the buttons (the one-row bar ran under both).
-- Returns { x, y, w, h, cell } in screen pixels.
TouchLayout.BAG_CELL, TouchLayout.BAG_GAP, TouchLayout.BAG_PAD = 40, 4, 6
function TouchLayout.bag(w, h, gridLeft)
	local L = TouchLayout
	local x = w * L.STICK_W + 8
	local room = (gridLeft or w) - 8 - x
	local cell = math.min(L.BAG_CELL, math.floor((room - 2 * L.BAG_PAD - 3 * L.BAG_GAP) / 4))
	local bw = 4 * cell + 3 * L.BAG_GAP + 2 * L.BAG_PAD
	local bh = 2 * cell + L.BAG_GAP + 2 * L.BAG_PAD
	return { x = x, y = h - bh - 12, w = bw, h = bh, cell = cell }
end

-- The emote icon (TouchControls), top right left of SHOP / ITEMS
-- (SideButtons: 8 and 136 px from the right edge, 120 wide).
TouchLayout.EMOTE_RIGHT, TouchLayout.EMOTE_SIZE = 264, 40

-- Left edge (screen px) of the touch buttons shown now, or nil when there
-- are none (no touch screen, or a phase without buttons). Screens that would
-- sit under them (NEW item card, steal warning) stand left of it.
function TouchLayout.gridLeft(playerGui)
	local g = playerGui and playerGui:FindFirstChild("TouchControls")
	if not g or not g:IsA("ScreenGui") then return nil end
	for _, f in ipairs(g:GetChildren()) do
		if f:IsA("Frame") and f.Visible and f.AbsoluteSize.X > 0 then
			return f.AbsolutePosition.X
		end
	end
	return nil
end

return TouchLayout
