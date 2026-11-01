-- Invite.lua (client)
-- The INVITE FRIENDS button (lobby and results screens): opens Roblox's own
-- invite prompt and tells the server how many friends were picked
-- (RemoteEvents.InviteSent). Hidden where invites are not allowed
-- (SocialService:CanSendGameInviteAsync). A friend who joins through it for
-- the first time pays you Constants.INVITE.COINS (server: Modules/Referral).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)

local Invite = {}

Invite.TEXT = "👥 INVITE FRIENDS"
Invite.HINT = string.format("+%d coins for each new friend who joins", Constants.INVITE.COINS)

local _canSend = nil   -- nil: not asked yet
local function canSend()
	if _canSend == nil then
		local ok, yes = pcall(SocialService.CanSendGameInviteAsync, SocialService, Players.LocalPlayer)
		_canSend = ok and yes == true
	end
	return _canSend
end

function Invite.prompt()
	local player = Players.LocalPlayer
	if not canSend() then return end
	pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = Constants.INVITE.PROMPT
		SocialService:PromptGameInvite(player, options)
	end)
end

local _listening = false
local function listen()
	if _listening then return end
	_listening = true
	SocialService.GameInvitePromptClosed:Connect(function(sender, recipientIds)
		if sender ~= Players.LocalPlayer or type(recipientIds) ~= "table" or #recipientIds == 0 then return end
		RemoteEvents.InviteSent:FireServer(#recipientIds)
	end)
end

--- A green button in `parent` at `position` (`size` the button), with the
-- coin hint under it unless `noHint` (then the hint is on the button's
-- second line). Starts hidden; shows once invites are allowed.
function Invite.button(parent, position, size, noHint)
	local btn = Instance.new("TextButton")
	btn.Name             = "Invite"
	btn.Size             = size
	btn.Position         = position
	btn.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
	btn.Text             = Invite.TEXT
	btn.TextColor3       = Color3.new(1, 1, 1)
	btn.TextScaled       = true
	btn.Font             = Enum.Font.GothamBlack
	btn.Visible          = false
	btn.Parent           = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = btn
	local hint = Instance.new("TextLabel")
	hint.Name                   = "Hint"
	hint.Size                   = UDim2.new(1, 16, 0, 16)
	hint.Position               = UDim2.new(0, -8, 1, 8)
	hint.BackgroundTransparency = 1
	hint.Text                   = Invite.HINT
	hint.TextColor3             = Color3.fromRGB(170, 240, 170)
	hint.TextScaled             = true
	hint.Font                   = Enum.Font.GothamBold
	hint.Parent                 = btn
	if noHint then
		hint.Visible = false
		btn.Text = Invite.TEXT .. string.format("  (+%d each)", Constants.INVITE.COINS)
	end
	btn.Activated:Connect(Invite.prompt)
	listen()
	task.spawn(function()
		if canSend() then btn.Visible = true end
	end)
	return btn
end

--- "Friend joined" notice for InviteReward (call once per client).
function Invite.watchRewards()
	RemoteEvents.InviteReward.OnClientEvent:Connect(function(name, coins)
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Friend joined!",
				Text = string.format("%s joined: +%d coins", tostring(name), tonumber(coins) or 0),
				Duration = 6,
			})
		end)
	end)
end

return Invite
