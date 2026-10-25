-- FarmingClient.client.lua
-- Proximity detection, pickup prompt, contest UI, steal prompt, and fight
-- keys (F or left click punch, hold G guard, X drop). Animations and the defence prompt: FarmFx.
-- Resolves: Issue #18, #64

print("[FarmingClient] LocalScript started")

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Constants    = require(ReplicatedStorage.Shared.Constants)
local ItemScan     = require(ReplicatedStorage.Shared.ItemScan)
local RemoteEvents = require(ReplicatedStorage.RemoteEvents)
local KeyInput     = require(ReplicatedStorage.Shared.KeyInput)   -- keyboard + touch buttons

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- _getUIManager must be declared AFTER LocalPlayer: Lua resolves the
-- LocalPlayer name to a global if no local is in scope at function-define
-- time, and the global is nil — so picking up a dropped item (only path
-- that hits _getUIManager from pickup) errored "index nil with WaitForChild".
local _UIManager = nil
local function _getUIManager()
	if not _UIManager then
		local scripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
		local mods    = scripts and scripts:FindFirstChild("Modules")
		local mod     = mods and mods:FindFirstChild("UIManager")
		if mod then _UIManager = require(mod) end
	end
	return _UIManager
end

local FarmingClient = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _enabled        = false
local _inventory      = {}
local _nearestItem    = nil   -- Part
local _nearestPlayer  = nil   -- Player
local _contestItemId  = nil
local _contestPresses = 0
local _heartbeatConn  = nil
local _promptGui      = nil   -- BillboardGui attached to nearest item
local _stealGui       = nil   -- ScreenGui for steal prompt/defense

-- ─── Inventory (updated by server) ───────────────────────────────────────────

RemoteEvents.InventoryUpdated.OnClientEvent:Connect(function(inventory)
	_inventory = inventory
	-- Update inventory HUD (implemented in UIManager / FarmingUI)
	local inventoryBar = LocalPlayer.PlayerGui:FindFirstChild("FarmingUI")
	if inventoryBar then
		local bar = inventoryBar:FindFirstChild("InventoryBar")
		if bar then
			for i = 1, Constants.INVENTORY_SIZE do
				local slot = bar:FindFirstChild("Slot" .. i)
				if slot then
					local label = slot:FindFirstChildOfClass("TextLabel")
					if label then
						local item = inventory[i]
						label.Text = item and (require(
							game.ReplicatedStorage.Shared.ItemTypes
						).byName[item] and
						require(game.ReplicatedStorage.Shared.ItemConfig)[item] and
						require(game.ReplicatedStorage.Shared.ItemConfig)[item].icon or "?") or ""
					end
				end
			end
		end
	end
end)

-- ─── Proximity scan ───────────────────────────────────────────────────────────

local function _scanNearby()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil, nil end

	local nearestItem   = nil
	local nearestItemDist = math.huge
	local nearestPlayer = nil
	local nearestPlayerDist = math.huge

	-- Scan items: FarmingManager places a StringValue named "ItemName" on the
	-- item model's PrimaryPart. FBX-imported items can have the PrimaryPart
	-- offset from the visible mesh center, so we walk up from any part returned
	-- by the bounds check and resolve the containing item's PrimaryPart. This
	-- way ANY part of the model touching the radius triggers detection.
	local seenPrimary = {}
	local parts = workspace:GetPartBoundsInRadius(root.Position, Constants.PICKUP_RANGE)
	for _, part in ipairs(parts) do
		local primary = ItemScan.itemPrimary(part)
		if primary then
			if not seenPrimary[primary] then
				seenPrimary[primary] = true
				local d = (primary.Position - root.Position).Magnitude
				if d < nearestItemDist then
					nearestItemDist = d
					nearestItem = primary
				end
			end
		end
	end

	-- Scan players (for steal)
	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		local otherChar = player.Character
		local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
		if not otherRoot then continue end
		local d = (otherRoot.Position - root.Position).Magnitude
		if d <= Constants.STEAL_RANGE and d < nearestPlayerDist then
			nearestPlayerDist = d
			nearestPlayer = player
		end
	end

	-- Server farm bots (Modules/FarmBots) can be robbed too
	for _, m in ipairs(CollectionService:GetTagged("FarmBot")) do
		local botRoot = m:FindFirstChild("HumanoidRootPart")
		if botRoot then
			local d = (botRoot.Position - root.Position).Magnitude
			if d <= Constants.STEAL_RANGE and d < nearestPlayerDist then
				nearestPlayerDist = d
				nearestPlayer = { UserId = m:GetAttribute("BotUserId"), Name = m:GetAttribute("BotName"), Character = m }
			end
		end
	end

	return nearestItem, nearestPlayer
end

-- ─── Pickup prompt BillboardGui ───────────────────────────────────────────────

local function _showPrompt(part)
	if _promptGui and _promptGui.Parent then
		_promptGui.Adornee = part
		return
	end
	_promptGui = Instance.new("BillboardGui")
	_promptGui.Size        = UDim2.new(0, 120, 0, 40)
	_promptGui.StudsOffset = Vector3.new(0, 2, 0)
	_promptGui.Adornee     = part
	_promptGui.AlwaysOnTop = true
	_promptGui.Parent      = part

	local label = Instance.new("TextLabel")
	label.Size            = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text            = "[E] Pick Up"
	label.TextColor3      = Color3.new(1, 1, 1)
	label.TextScaled      = true
	label.Font            = Enum.Font.GothamBold
	label.Parent          = _promptGui
end

local function _hidePrompt()
	if _promptGui then
		_promptGui:Destroy()
		_promptGui = nil
	end
end

local function _flashPromptDenied()
	if not _promptGui then return end
	local label = _promptGui:FindFirstChildOfClass("TextLabel")
	if not label then return end
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	task.delay(0.5, function()
		if label and label.Parent then
			label.TextColor3 = Color3.new(1, 1, 1)
		end
	end)
end

-- ─── E handler ────────────────────────────────────────────────────────────

KeyInput.began(function(input, processed)
	if processed or not _enabled then return end

	if input.KeyCode == Enum.KeyCode.E then
		if _contestItemId then
			-- We're in a contest — count presses
			_contestPresses = _contestPresses + 1
			RemoteEvents.RequestContest:InvokeServer(_contestItemId, _contestPresses)
			return
		end

		if _nearestItem then
			local idVal  = _nearestItem:FindFirstChild("ItemId")
			local itemId = idVal and idVal.Value
			if not itemId then
				warn("[FarmingClient] E pressed but ItemId missing on:", _nearestItem.Name)
				return
			end
			local result = RemoteEvents.RequestPickup:InvokeServer(itemId)
			if result == "ok" then
				_hidePrompt()
				_nearestItem = nil
			elseif result == "contested" then
				local idv = _nearestItem and _nearestItem:FindFirstChild("ItemId")
				_contestItemId  = idv and idv.Value or tostring(_nearestItem)
				_contestPresses = 1
			elseif result == "inventory_full" then
				local ui = _getUIManager()
				if ui then ui.showNotification("Inventory full — only better items swap in", 2, Color3.fromRGB(255, 140, 40)) end
				_flashPromptDenied()
			else
				_flashPromptDenied()
			end
		elseif _nearestPlayer then
			-- Long-press handled below via InputEnded
		end
	end
end)

-- X: drop the item in the first inventory slot (Q is the emote menu: a tap
-- of Q used to drop an item on the way to opening it)
KeyInput.began(function(input, processed)
	if processed or not _enabled then return end
	if input.KeyCode == Enum.KeyCode.X then
		if #_inventory == 0 then return end
		local result = RemoteEvents.RequestDrop:InvokeServer(1)
		if result == "ok" then
			local ui = _getUIManager()
			if ui then ui.showNotification("Item dropped", 1.2, Color3.fromRGB(180, 180, 180)) end
		end
	end
end)

-- ─── Steal: hold E next to someone (Constants.STEAL_HOLD) ───────────────────
-- A label over the nearest player or bot says so; while E is held its bar
-- fills and the steal starts the moment it is full (it used to wait for E to
-- be let go, so holding it down did nothing you could see).
local _eHoldStart, _eHoldTarget = nil, nil
local _targetGui, _targetFill, _targetOf = nil, nil, nil

local function _hideTargetPrompt()
	if _targetGui then _targetGui:Destroy() end
	_targetGui, _targetFill, _targetOf = nil, nil, nil
end

local function _showTargetPrompt(target)
	local char = target and target.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not head then _hideTargetPrompt() return end
	if _targetGui and _targetOf == head and _targetGui.Parent then return end
	_hideTargetPrompt()
	local gui = Instance.new("BillboardGui")
	gui.Name = "StealPrompt"
	gui.Size = UDim2.new(0, 190, 0, 46)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, 30)
	text.BackgroundTransparency = 1
	text.Text = "[Hold E] Steal   [F] Punch"
	text.TextColor3 = Color3.fromRGB(255, 225, 120)
	text.TextStrokeTransparency = 0.2
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0.8, 0, 0, 8)
	bar.Position = UDim2.new(0.1, 0, 0, 34)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	gui.Parent = head
	_targetGui, _targetFill, _targetOf = gui, fill, head
end

KeyInput.began(function(input, processed)
	if processed or not _enabled then return end
	if input.KeyCode == Enum.KeyCode.E and _nearestPlayer and not _nearestItem and not _contestItemId then
		_eHoldStart, _eHoldTarget = tick(), _nearestPlayer
	end
end)

KeyInput.ended(function(input)
	if input.KeyCode == Enum.KeyCode.E then
		_eHoldStart, _eHoldTarget = nil, nil
	end
end)

-- Called every frame from _tick.
local function _updateSteal()
	if _nearestPlayer and not _nearestItem and not _contestItemId then
		_showTargetPrompt(_nearestPlayer)
	else
		_hideTargetPrompt()
	end
	if not _eHoldStart then
		if _targetFill then _targetFill.Size = UDim2.new(0, 0, 1, 0) end
		return
	end
	-- walked away from (or past) the one being robbed: start over
	if not _nearestPlayer or not _eHoldTarget or _nearestPlayer.UserId ~= _eHoldTarget.UserId then
		_eHoldStart, _eHoldTarget = nil, nil
		return
	end
	local f = math.clamp((tick() - _eHoldStart) / Constants.STEAL_HOLD, 0, 1)
	if _targetFill then _targetFill.Size = UDim2.new(f, 0, 1, 0) end
	if f >= 1 then
		local target = _eHoldTarget
		_eHoldStart, _eHoldTarget = nil, nil
		task.spawn(function() RemoteEvents.RequestSteal:InvokeServer(target.UserId) end)
	end
end

-- ─── Gadget: T (shop "gadget", e.g. Smoke Bomb; server: UseGadget) ───────────
KeyInput.began(function(input, processed)
	if processed or not _enabled then return end
	if input.KeyCode == Enum.KeyCode.T and LocalPlayer:GetAttribute("Gadget") then
		task.spawn(function()
			local r = RemoteEvents.UseGadget:InvokeServer()
			if r == "denied: used" then
				local ui = _getUIManager()
				if ui then ui.showNotification("Already used this round", 1.5, Color3.fromRGB(200, 200, 200)) end
			end
		end)
	end
end)

-- ─── Fight: F punches the player you face, hold G to guard ───────────────────
-- (server: FarmingManager RequestPunch / SetGuard; looks: FarmFx)
KeyInput.began(function(input, processed)
	if processed or not _enabled then return end
	if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton1 then
		task.spawn(function() RemoteEvents.RequestPunch:InvokeServer() end)
	elseif input.KeyCode == Enum.KeyCode.G then
		RemoteEvents.SetGuard:FireServer(true)
	end
end)

KeyInput.ended(function(input)
	if input.KeyCode == Enum.KeyCode.G and _enabled then
		RemoteEvents.SetGuard:FireServer(false)
	end
end)

-- ─── Contest UI listener ──────────────────────────────────────────────────────

RemoteEvents.ContestUpdate.OnClientEvent:Connect(function(itemId, p1, p2)
	_contestItemId = itemId
	-- TODO: update BillboardGui above the item with live press counts
	-- For now just print (full UI in FarmingUI issue)
	print(string.format("[Contest] %d vs %d", p1.count, p2.count))
end)

RemoteEvents.ContestResult.OnClientEvent:Connect(function(itemId, winnerUserId)
	if _contestItemId == itemId then
		_contestItemId  = nil
		_contestPresses = 0
		if winnerUserId == LocalPlayer.UserId then
			print("[Contest] YOU WIN!")
		else
			print("[Contest] You lost.")
		end
	end
end)

-- ─── Steal listener (defend prompt) ──────────────────────────────────────────

RemoteEvents.StealAttempt.OnClientEvent:Connect(function(thiefName)
	-- Show defend UI
	print(string.format("[Steal] %s is trying to steal from you! Press E x3!", thiefName))
	-- TODO: proper ScreenGui overlay (Issue #44 / #64 UI)
	local defendPresses = 0
	local defended = false
	local conn
	conn = KeyInput.began(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.E then
			-- The server counts the taps (one call each) inside its window.
			defendPresses = defendPresses + 1
			task.spawn(function() RemoteEvents.DefendSteal:InvokeServer() end)
			if defendPresses >= Constants.STEAL_DEFEND_PRESSES then
				defended = true
				conn:Disconnect()
			end
		end
	end)
	task.delay(Constants.STEAL_DEFEND_WINDOW, function()
		conn:Disconnect()
	end)
end)

-- ─── Heartbeat scan ───────────────────────────────────────────────────────────

local function _tick()
	local item, player = _scanNearby()
	_nearestItem   = item
	_nearestPlayer = player

	local isFull = #_inventory >= Constants.INVENTORY_SIZE

	if item and not isFull then
		_showPrompt(item)
	else
		_hidePrompt()
	end
	_updateSteal()
end

-- ─── Enable / Disable ─────────────────────────────────────────────────────────

function FarmingClient.enable()
	_enabled = true
	if not _heartbeatConn then
		_heartbeatConn = RunService.Heartbeat:Connect(function()
			if _enabled then _tick() end
		end)
	end
end

function FarmingClient.disable()
	_enabled = false
	_hidePrompt()
	_hideTargetPrompt()
	_eHoldStart, _eHoldTarget = nil, nil
	_nearestItem    = nil
	_nearestPlayer  = nil
	_contestItemId  = nil
	_contestPresses = 0
end

-- ─── Self-manage via PhaseChanged ────────────────────────────────────────────
-- Activates without relying on GameClient.require() chain, which can fail
-- silently when file renames cause Rojo sync inconsistencies.

RemoteEvents.PhaseChanged.OnClientEvent:Connect(function(phase)
	print("[FarmingClient] PhaseChanged received:", phase)
	if phase == Constants.PHASES.FARMING then
		FarmingClient.enable()
		print("[FarmingClient] Enabled, scanning for items every heartbeat")
	else
		FarmingClient.disable()
	end
end)

return FarmingClient
