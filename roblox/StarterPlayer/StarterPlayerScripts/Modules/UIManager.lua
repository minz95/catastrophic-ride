-- UIManager.lua
-- Central hub for showing/hiding phase UIs and applying biome theming.
-- Required by GameClient.

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

local UIManager = {}

-- ─── UI registry ─────────────────────────────────────────────────────────────
-- Each key maps to a ScreenGui name in PlayerGui.
-- Some GUIs are init.client.lua scripts (auto-created); others are Studio GUIs.

local PHASE_UIS = {
	LOBBY     = { show = { "LobbyUI" },    hide = { "HUD", "FarmingUI", "CraftingUI", "ResultsUI", "AbilityUI" } },
	FARMING   = { show = { "FarmingUI" },  hide = { "LobbyUI", "HUD", "CraftingUI", "ResultsUI" } },
	CRAFTING  = { show = { "CraftingUI" }, hide = { "LobbyUI", "HUD", "FarmingUI", "ResultsUI" } },
	RACING    = { show = { "HUD", "AbilityUI" }, hide = { "LobbyUI", "FarmingUI", "CraftingUI", "ResultsUI" } },
	RESULTS   = { show = { "ResultsUI" },  hide = { "LobbyUI", "HUD", "FarmingUI", "CraftingUI", "AbilityUI" } },
}

-- ─── Biome colour palettes ───────────────────────────────────────────────────
local BIOME_THEME = {
	FOREST = {
		primary   = Color3.fromRGB(60, 160, 60),
		secondary = Color3.fromRGB(180, 120, 40),
		accent    = Color3.fromRGB(100, 200, 80),
		text      = Color3.fromRGB(230, 255, 220),
	},
	OCEAN = {
		primary   = Color3.fromRGB(40, 100, 220),
		secondary = Color3.fromRGB(0, 180, 200),
		accent    = Color3.fromRGB(60, 210, 255),
		text      = Color3.fromRGB(220, 240, 255),
	},
	SKY = {
		primary   = Color3.fromRGB(120, 80, 220),
		secondary = Color3.fromRGB(200, 100, 200),
		accent    = Color3.fromRGB(180, 140, 255),
		text      = Color3.fromRGB(240, 230, 255),
	},
}

local _currentBiome   = nil
local _origTransp     = {}   -- { [guiName] = { [childName] = originalTransparency } }
local _intendedEnabled = {}  -- { [guiName] = bool } — guards against stale task.delay disables

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function _cacheTransparencies(guiName, gui)
	if _origTransp[guiName] then return end
	_origTransp[guiName] = {}
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("Frame") or child:IsA("ScrollingFrame") then
			_origTransp[guiName][child.Name] = child.BackgroundTransparency
		end
	end
end

local function _findScreenGui(guiName)
	for _, child in ipairs(PlayerGui:GetChildren()) do
		if child.Name == guiName and child:IsA("ScreenGui") then
			return child
		end
	end
	return nil
end

local function _setEnabled(guiName, enabled, fadeDuration)
	local gui = _findScreenGui(guiName)
	if not gui then return end
	_intendedEnabled[guiName] = enabled
	_cacheTransparencies(guiName, gui)

	if fadeDuration and fadeDuration > 0 then
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("Frame") or child:IsA("ScrollingFrame") then
				local orig = (_origTransp[guiName] or {})[child.Name] or 0
				TweenService:Create(child, TweenInfo.new(fadeDuration), {
					BackgroundTransparency = enabled and orig or 1
				}):Play()
			end
		end
		if not enabled then
			task.delay(fadeDuration, function()
				-- Only disable if intent hasn't changed to 'show' in the meantime
				if _intendedEnabled[guiName] == false then
					gui.Enabled = false
				end
			end)
		else
			gui.Enabled = true
		end
	else
		-- Restore child transparencies when showing without animation
		if enabled then
			for _, child in ipairs(gui:GetChildren()) do
				if child:IsA("Frame") or child:IsA("ScrollingFrame") then
					child.BackgroundTransparency = (_origTransp[guiName] or {})[child.Name] or 0
				end
			end
		end
		gui.Enabled = enabled
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function UIManager.setPhase(phase, biome)
	local config = PHASE_UIS[phase]
	if not config then return end

	for _, name in ipairs(config.hide) do
		_setEnabled(name, false, 0.3)
	end
	for _, name in ipairs(config.show) do
		_setEnabled(name, true, 0)
	end

	if biome then
		UIManager.applyBiomeTheme(biome)
	end
end

function UIManager.applyBiomeTheme(biome)
	_currentBiome = biome
	local theme = BIOME_THEME[biome]
	if not theme then return end

	-- Apply to HUD boost bar
	-- the ScreenGui, not the LocalScript also named "HUD" in PlayerGui
	local hud = nil
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g.Name == "HUD" and g:IsA("ScreenGui") then hud = g; break end
	end
	if hud then
		local boostFill = hud:FindFirstChild("BoostBar", true)
		if boostFill then
			local fill = boostFill:FindFirstChild("Fill")
			if fill then
				TweenService:Create(fill, TweenInfo.new(0.5), {
					BackgroundColor3 = theme.primary
				}):Play()
			end
		end
	end

	-- Fire a BindableEvent or use a shared value so individual UIs can self-theme
	-- (each UI listens to BiomeSelected remote directly in their own script)
end

function UIManager.getBiomeTheme(biome)
	return BIOME_THEME[biome or _currentBiome] or BIOME_THEME.FOREST
end

function UIManager.showNotification(text, duration, colour)
	duration = duration or 2.5
	colour   = colour or Color3.fromRGB(255, 220, 60)

	local existing = PlayerGui:FindFirstChild("NotificationGui")
	if existing then existing:Destroy() end

	local notifGui = Instance.new("ScreenGui")
	notifGui.Name           = "NotificationGui"
	notifGui.ResetOnSpawn   = false
	notifGui.IgnoreGuiInset = true
	notifGui.Parent         = PlayerGui

	local frame = Instance.new("Frame")
	frame.Size             = UDim2.new(0, 340, 0, 50)
	frame.Position         = UDim2.new(0.5, -170, 0.08, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel  = 0
	frame.Parent           = notifGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius    = UDim.new(0, 10)
	corner.Parent          = frame

	local accent = Instance.new("Frame")
	accent.Size            = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = colour
	accent.BorderSizePixel = 0
	accent.Parent          = frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 10)
	accentCorner.Parent       = accent

	local lbl = Instance.new("TextLabel")
	lbl.Size               = UDim2.new(1, -14, 1, 0)
	lbl.Position           = UDim2.new(0, 14, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = text
	lbl.TextColor3         = Color3.new(1, 1, 1)
	lbl.TextScaled         = true
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.Parent             = frame

	-- Slide down from top
	frame.Position = UDim2.new(0.5, -170, -0.05, 0)
	TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -170, 0.08, 0)
	}):Play()

	task.delay(duration, function()
		TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, -170, -0.05, 0)
		}):Play()
		task.delay(0.3, function() notifGui:Destroy() end)
	end)
end

return UIManager
