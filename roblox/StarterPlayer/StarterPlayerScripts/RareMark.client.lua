-- RareMark.client.lua
-- Whoever picks up or steals a Rare / Epic item is marked for everyone
-- (Constants.RARE_MARK): an arrow in the rarity's colour with the item's
-- icon bobs over their head for SECONDS and their outline glows for GLOW,
-- so the farm knows whom to chase (playtest 2026-11-12). Players and farm
-- bots (tag "FarmBot", attribute BotUserId) alike; only during FARMING.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local ItemConfig   = require(ReplicatedStorage.Shared.ItemConfig)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local M = Constants.RARE_MARK
local MARK_NAME = "RareMark"
local COLORS = {
	Rare = Color3.fromRGB(70, 160, 255),
	Epic = Color3.fromRGB(190, 90, 255),
}
local BOB, BOB_SPEED, HEIGHT = 0.5, 6, 3.4

local _marks = {}   -- [character] = { gui, untilT, highlight }

local function charOf(userId)
	local p = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if p then return p.Character end
	if type(userId) == "number" and userId < 0 then
		for _, m in ipairs(CollectionService:GetTagged("FarmBot")) do
			if m:GetAttribute("BotUserId") == userId then return m end
		end
	end
	return nil
end

local function unmark(character)
	local m = _marks[character]
	if not m then return end
	_marks[character] = nil
	if m.gui then m.gui:Destroy() end
	if m.highlight then m.highlight:Destroy() end
end

local function build(color, icon)
	local gui = Instance.new("BillboardGui")
	gui.Name = MARK_NAME
	gui.Size = UDim2.new(0, 56, 0, 78)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	local badge = Instance.new("TextLabel")
	badge.Name = "Icon"
	badge.Size = UDim2.new(0, 40, 0, 40)
	badge.Position = UDim2.new(0.5, -20, 0, 0)
	badge.BackgroundColor3 = color
	badge.BackgroundTransparency = 0.1
	badge.Text = icon or "!"
	badge.TextScaled = true
	badge.Font = Enum.Font.GothamBlack
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Parent = gui
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = badge
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.new(1, 0, 0, 36)
	arrow.Position = UDim2.new(0, 0, 0, 40)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.TextScaled = true
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextColor3 = color
	arrow.TextStrokeColor3 = Color3.new(1, 1, 1)
	arrow.TextStrokeTransparency = 0.2
	arrow.Parent = gui
	return gui
end

local function mark(userId, itemName)
	if ReplicatedStorage:GetAttribute("Phase") ~= Constants.PHASES.FARMING then return end
	local cfg = itemName and ItemConfig[itemName]
	local rarity = cfg and cfg.rarity
	if not (rarity and M.RARITIES[rarity]) then return end
	local character = charOf(userId)
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then return end
	unmark(character)
	local color = COLORS[rarity] or COLORS.Rare
	local gui = build(color, cfg.icon)
	gui.Adornee = head
	gui.StudsOffset = Vector3.new(0, HEIGHT, 0)
	gui.Parent = head
	local hl = Instance.new("Highlight")
	hl.Name = MARK_NAME
	hl.FillColor, hl.OutlineColor = color, color
	hl.FillTransparency, hl.OutlineTransparency = 0.55, 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = character
	local now = os.clock()
	_marks[character] = { gui = gui, highlight = hl, untilT = now + M.SECONDS, glowUntil = now + M.GLOW }
end

RemoteEvents.ItemPickedUp.OnClientEvent:Connect(function(_itemId, userId, info)
	mark(userId, type(info) == "table" and info.item or nil)
end)

-- a stolen rare item takes its mark to the thief
RemoteEvents.ItemStolen.OnClientEvent:Connect(function(_thiefName, _victimName, itemName, thiefId, victimId)
	local cfg = itemName and ItemConfig[itemName]
	if not (cfg and M.RARITIES[cfg.rarity]) then return end
	local victim = charOf(victimId)
	if victim then unmark(victim) end
	mark(thiefId, itemName)
end)

RunService.RenderStepped:Connect(function()
	if not next(_marks) then return end
	local now = os.clock()
	local farming = ReplicatedStorage:GetAttribute("Phase") == Constants.PHASES.FARMING
	for character, m in pairs(_marks) do
		if not farming or now > m.untilT or not character.Parent or not m.gui.Parent then
			unmark(character)
		else
			m.gui.StudsOffset = Vector3.new(0, HEIGHT + math.sin(now * BOB_SPEED) * BOB, 0)
			if m.highlight then
				if now > m.glowUntil then
					m.highlight:Destroy()
					m.highlight = nil
				else
					-- pulse while it lasts
					m.highlight.FillTransparency = 0.45 + 0.35 * (0.5 + 0.5 * math.sin(now * 14))
				end
			end
			-- the last second fades the arrow out
			local left = m.untilT - now
			if left < 1 then
				m.gui.Icon.BackgroundTransparency = 1 - left * 0.9
				m.gui.Icon.TextTransparency = 1 - left
				m.gui.Arrow.TextTransparency = 1 - left
			end
		end
	end
end)
