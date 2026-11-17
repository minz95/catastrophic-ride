-- LobbyHubClient.client.lua
-- Junk Town on the player's side (server: LobbyManager, Maps/LobbyHub):
--   * prompts with the attribute "Opens" open the shop on that tab
--     ("shop": as it was, "legend", "awards"), through ShopUI's Open event;
--   * prompts with "Talk" = an NPC id (Shared/LobbyNpcs) show the NPC's
--     next line in a speech box at the bottom of the screen and a chat
--     bubble over their head; the box goes after a few seconds or on Bye;
--   * now and then a townsperson near you says one of their idle lines.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LobbyNpcs = require(ReplicatedStorage.Shared.LobbyNpcs)
local LocalPlayer = Players.LocalPlayer

local SHOW_FOR = 7          -- s a line stays in the box
local IDLE_EVERY = { 14, 26 }
local IDLE_NEAR = 40        -- studs

local function hub()
	return workspace:FindFirstChild("LobbyHub")
end

local function bubble(npcId, text)
	local h = hub()
	local rig = h and h:FindFirstChild("Npc_" .. npcId)
	local head = rig and rig:FindFirstChild("Head")
	if head then pcall(function() TextChatService:DisplayBubble(head, text) end) end
end

-- ── The speech box ───────────────────────────────────────────────────────────
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "TownTalk" and old:IsA("ScreenGui") then old:Destroy() end
end
local screen = Instance.new("ScreenGui")
screen.Name = "TownTalk"
screen.ResetOnSpawn = false
screen.Parent = LocalPlayer.PlayerGui

local box = Instance.new("Frame")
box.Name = "Box"
box.AnchorPoint = Vector2.new(0.5, 1)
box.Size = UDim2.new(0.5, 0, 0, 96)
box.Position = UDim2.new(0.5, 0, 1, -44)
box.BackgroundColor3 = Color3.fromRGB(255, 248, 230)
box.Visible = false
box.Parent = screen
local c = Instance.new("UICorner")
c.CornerRadius = UDim.new(0, 12)
c.Parent = box
local st = Instance.new("UIStroke")
st.Thickness = 3
st.Color = Color3.fromRGB(120, 80, 50)
st.Parent = box
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(300, 80)
sizeLimit.MaxSize = Vector2.new(620, 120)
sizeLimit.Parent = box

local who = Instance.new("TextLabel")
who.Name = "Who"
who.Size = UDim2.new(1, -110, 0, 24)
who.Position = UDim2.new(0, 12, 0, 6)
who.BackgroundTransparency = 1
who.TextXAlignment = Enum.TextXAlignment.Left
who.TextScaled = true
who.Font = Enum.Font.GothamBlack
who.TextColor3 = Color3.fromRGB(150, 70, 20)
who.Parent = box

local says = Instance.new("TextLabel")
says.Name = "Says"
says.Size = UDim2.new(1, -24, 1, -40)
says.Position = UDim2.new(0, 12, 0, 32)
says.BackgroundTransparency = 1
says.TextXAlignment = Enum.TextXAlignment.Left
says.TextYAlignment = Enum.TextYAlignment.Top
says.TextWrapped = true
says.TextScaled = true
says.Font = Enum.Font.GothamMedium
says.TextColor3 = Color3.fromRGB(50, 35, 25)
says.Parent = box
local saysMax = Instance.new("UITextSizeConstraint")
saysMax.MaxTextSize = 22
saysMax.Parent = says

local bye = Instance.new("TextButton")
bye.Name = "Bye"
bye.AnchorPoint = Vector2.new(1, 0)
bye.Size = UDim2.new(0, 84, 0, 26)
bye.Position = UDim2.new(1, -8, 0, 6)
bye.Text = "Bye"
bye.TextScaled = true
bye.Font = Enum.Font.GothamBold
bye.TextColor3 = Color3.new(1, 1, 1)
bye.BackgroundColor3 = Color3.fromRGB(150, 100, 60)
bye.Parent = box
local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(0, 8)
bc.Parent = bye

local _shownAt = 0
local _last = {}   -- npc id → last line index
local function talk(npcId)
	local n = LobbyNpcs.get(npcId)
	if not n then return end
	local i = LobbyNpcs.pick(n, _last[npcId], math.random)
	_last[npcId] = i
	local line = n.lines[i]
	who.Text = n.name .. "  ·  " .. n.title
	says.Text = line
	box.Visible = true
	local at = os.clock()
	_shownAt = at
	bubble(npcId, line)
	task.delay(SHOW_FOR, function()
		if _shownAt == at then box.Visible = false end
	end)
end
bye.Activated:Connect(function() box.Visible = false end)

-- ── Prompts ──────────────────────────────────────────────────────────────────
local function openShop(tab)
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
		if g.Name == "ShopUI" and g:IsA("ScreenGui") then
			local ev = g:FindFirstChild("Open")
			if ev then ev:Fire(tab ~= "shop" and tab or nil) end
			return true
		end
	end
	return false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local talkTo = prompt:GetAttribute("Talk")
	if talkTo then
		talk(talkTo)
		return
	end
	local opens = prompt:GetAttribute("Opens")
	if opens then openShop(opens) end
end)

-- leaving the lobby closes the box
ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
	if ReplicatedStorage:GetAttribute("Phase") ~= Constants.PHASES.LOBBY then box.Visible = false end
end)

-- ── Idle chatter near you ────────────────────────────────────────────────────
task.spawn(function()
	while true do
		task.wait(math.random(IDLE_EVERY[1], IDLE_EVERY[2]))
		local h = hub()
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if h and root then
			local near = {}
			for _, n in ipairs(LobbyNpcs.LIST) do
				local rig = h:FindFirstChild("Npc_" .. n.id)
				local head = rig and rig:FindFirstChild("Head")
				if head and (head.Position - root.Position).Magnitude < IDLE_NEAR and n.idle then
					table.insert(near, n)
				end
			end
			if #near > 0 then
				local n = near[math.random(#near)]
				bubble(n.id, n.idle[math.random(#n.idle)])
			end
		end
	end
end)
