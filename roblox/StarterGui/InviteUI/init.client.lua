-- InviteUI
-- 👥 INVITE FRIENDS while farming (playtest 2026-11-15: a lone player's lobby
-- is LOBBY.MAX_WAIT s and the round began before there was time to invite;
-- the button was only in the lobby and on the results screen). It sits next
-- to SHOP / ITEMS (SideButtons; on a phone in their row at the top right,
-- left of the emote icon), with the coin hint under it. A friend who joins
-- now farms this round (StarterItems gives them their junk on arrival).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local Invite       = require(ReplicatedStorage.Shared.Invite)
local SideButtons  = require(ReplicatedStorage.Shared.SideButtons)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local LocalPlayer  = Players.LocalPlayer

-- ResetOnSpawn = false: this script runs again after a respawn
for _, old in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
	if old.Name == "InviteUI" and old:IsA("ScreenGui") then old:Destroy() end
end

local screen = Instance.new("ScreenGui")
screen.Name         = "InviteUI"
screen.ResetOnSpawn = false
screen.DisplayOrder = 19
screen.Parent       = LocalPlayer.PlayerGui

-- the slot: SHOP is at 8, ITEMS at 136 (120 wide each); on a phone the
-- emote icon is at 264 from the right (TouchLayout.ICONS), so 312 there
local X, X_TOUCH = 264, 312
local slot = Instance.new("Frame")
slot.Name                   = "InviteSlot"
slot.Size                   = UDim2.new(0, 170, 0, 64)   -- the button and the coin hint under it
slot.BackgroundTransparency = 1
slot.Visible                = false
slot.Parent                 = screen
Invite.button(slot, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 40), false, Invite.TEXT)

SideButtons.keepClear(slot, screen, X, X_TOUCH)

local function onPhase(phase)
	slot.Visible = phase == Constants.PHASES.FARMING
end
RemoteEvents.PhaseChanged.OnClientEvent:Connect(onPhase)
onPhase(ReplicatedStorage:GetAttribute("Phase"))
