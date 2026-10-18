-- MapPreviewPlugin.lua
-- Studio plugin: build maps and item models in edit mode without pressing Play.
-- Install: rojo build studio-plugin/default.project.json -o ~/Desktop/CatastrophicDayPreview.rbxm
--          then drag the .rbxm into Studio's Plugins folder (or use Plugin Manager)

if not plugin then return end  -- safety: do nothing if loaded outside Studio

-- ─── Services ─────────────────────────────────────────────────────────────────

local Selection         = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

-- ─── Toolbar ──────────────────────────────────────────────────────────────────

local toolbar = plugin:CreateToolbar("Catastrophic Day Preview")

local btnForest = toolbar:CreateButton(
	"Forest Map",
	"Build FOREST biome map in Workspace",
	"rbxassetid://6031094667"  -- tree icon (generic)
)
local btnOcean = toolbar:CreateButton(
	"Ocean Map",
	"Build OCEAN biome map in Workspace",
	"rbxassetid://6031094667"
)
local btnSky = toolbar:CreateButton(
	"Sky Map",
	"Build SKY biome map in Workspace",
	"rbxassetid://6031094667"
)
local btnClear = toolbar:CreateButton(
	"Clear Maps",
	"Remove all biome maps from Workspace",
	"rbxassetid://6031094667"
)
local btnItems = toolbar:CreateButton(
	"Preview Items",
	"Spawn one of each item model into Workspace for inspection",
	"rbxassetid://6031094667"
)
local btnClearItems = toolbar:CreateButton(
	"Clear Items",
	"Remove the ItemPreview folder from Workspace",
	"rbxassetid://6031094667"
)
local btnRaceSim = toolbar:CreateButton(
	"Race Sim",
	"Test harness: drive 3 simulated drivers around FOREST with StepPhysics (edit mode)",
	"rbxassetid://6031094667"
)
local btnRaceSimRun = toolbar:CreateButton(
	"Race Sim (Run)",
	"Test harness: same race in a fresh Run-mode session (latest code, real time)",
	"rbxassetid://6031094667"
)
local btnBotMatch = toolbar:CreateButton(
	"Bot Match",
	"Test harness: 4 bot clients play a full FOREST round (StudioTestService multiplayer)",
	"rbxassetid://6031094667"
)

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function notify(msg)
	print("[CatastrophicDayPreview] " .. msg)
end

local function getMapsFolder()
	local f = Workspace:FindFirstChild("Maps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Maps"
		f.Parent = Workspace
	end
	return f
end

-- Try to load a map builder module and run it.
-- Map builders are Scripts in ServerScriptService/MapBuilders/ — we can require()
-- them in plugin context because plugins run with full Studio permissions.
local function buildBiome(biome)
	local builderName = biome:sub(1,1):upper() .. biome:sub(2):lower() .. "MapBuilder"
	local buildersFolder = ServerScriptService:FindFirstChild("MapBuilders")
	if not buildersFolder then
		warn("[CatastrophicDayPreview] ServerScriptService.MapBuilders folder not found.")
		warn("Make sure Rojo is syncing the project (rojo serve roblox/default.project.json)")
		return
	end

	local builderScript = buildersFolder:FindFirstChild(builderName)
	if not builderScript then
		warn("[CatastrophicDayPreview] Builder not found: " .. builderName)
		return
	end

	-- Map builders are Scripts (not ModuleScripts), so we can't require() them.
	-- Instead we clone and run the build logic by invoking its exported table.
	-- BUT: Roblox plugin can't execute Scripts directly.
	-- Workaround: builders expose a module-like table — we temporarily convert.
	local ok, result = pcall(function()
		-- The builder Scripts all have a local MapBuilders table and call build().
		-- Since we can't require a Script, we read its source and run via loadstring.
		-- This works in Studio's plugin context.
		local src = builderScript.Source
		local fn, err = loadstring(src)
		if not fn then
			error("loadstring failed: " .. tostring(err))
		end
		fn()
	end)

	if ok then
		notify("Built " .. biome .. " map.")
	else
		warn("[CatastrophicDayPreview] Error building " .. biome .. ": " .. tostring(result))
		notify("Build failed — check Output for details.")
	end
end

local function clearMaps()
	local mapsFolder = Workspace:FindFirstChild("Maps")
	if mapsFolder then
		mapsFolder:Destroy()
		notify("Cleared Maps folder.")
	else
		notify("No Maps folder to clear.")
	end
end

-- ─── Item preview ─────────────────────────────────────────────────────────────

local ITEM_NAMES = {
	-- BODY
	"Stick", "Cardboard Box", "Bamboo Raft", "Skateboard", "Log",
	"Shopping Cart", "Life Preserver", "Kite", "Laptop", "Backpack",
	"Red Sofa", "Microwave", "Bathtub",
	-- ENGINE
	"Shovel", "Flower", "Pinwheel", "Watering Can", "Big Gear",
	"Leaf Blower", "Spinning Top", "Propeller", "V8 Engine",
	"Rocket", "Cup Noodle", "Kettle",
	-- SPECIAL
	"Pizza", "Toilet Paper", "Leaves", "Racing Flag", "Cactus",
	"Scarf", "Boombox", "Umbrella", "Rubber Duck",
	"Bubble Wrap", "Balloon Bunch", "Soda Bottle",
}

local function buildItemPreview()
	-- Remove old preview
	local existing = Workspace:FindFirstChild("ItemPreview")
	if existing then existing:Destroy() end

	local ItemModelBuilder
	local ok, err = pcall(function()
		ItemModelBuilder = require(ServerScriptService.Modules.ItemModelBuilder)
	end)
	if not ok then
		warn("[CatastrophicDayPreview] Cannot load ItemModelBuilder: " .. tostring(err))
		warn("Make sure Rojo is syncing and the Modules folder is in ServerScriptService.")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "ItemPreview"
	folder.Parent = Workspace

	local COLS  = 8
	local SPACE = 5  -- studs between items
	local built = 0

	for i, name in ipairs(ITEM_NAMES) do
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		local pos = Vector3.new(col * SPACE, 5, row * SPACE)

		local buildOk, model = pcall(function()
			return ItemModelBuilder.build(name, folder)
		end)

		if buildOk and model then
			if model.PrimaryPart then
				model:SetPrimaryPartCFrame(CFrame.new(pos))
				-- Anchor all parts so they don't fall
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") then part.Anchored = true end
				end
			end
			built += 1
		else
			warn("[CatastrophicDayPreview] Failed to build item: " .. name .. " — " .. tostring(model))
		end
	end

	Selection:Set({ folder })
	notify(string.format("Spawned %d / %d items into ItemPreview folder.", built, #ITEM_NAMES))
end

local function clearItems()
	local f = Workspace:FindFirstChild("ItemPreview")
	if f then
		f:Destroy()
		notify("Cleared ItemPreview folder.")
	else
		notify("No ItemPreview folder to clear.")
	end
end

-- ─── Test harness ─────────────────────────────────────────────────────────────
-- See docs/testing.md. Each button prints a one-screen summary to Output; the
-- full JSON report is printed after it for copy/paste or an AI agent.

local function runHarness(label, fn)
	local runnerModule = ServerScriptService:FindFirstChild("TestHarness")
		and ServerScriptService.TestHarness:FindFirstChild("Runner")
	if not runnerModule then
		warn("[CatastrophicDayPreview] ServerScriptService.TestHarness.Runner not found — is Rojo syncing?")
		return
	end
	notify(label .. " started…")
	task.spawn(function()
		local ok, summary, json = pcall(function()
			return fn(require(runnerModule))
		end)
		if ok then
			print(summary)
			print("[HarnessReport] " .. tostring(json))
			notify(label .. " finished.")
		else
			warn("[CatastrophicDayPreview] " .. label .. " failed: " .. tostring(summary))
		end
	end)
end

-- ─── Button connections ───────────────────────────────────────────────────────

btnForest.Click:Connect(function()
	btnForest:SetActive(false)
	buildBiome("FOREST")
end)

btnOcean.Click:Connect(function()
	btnOcean:SetActive(false)
	buildBiome("OCEAN")
end)

btnSky.Click:Connect(function()
	btnSky:SetActive(false)
	buildBiome("SKY")
end)

btnClear.Click:Connect(function()
	btnClear:SetActive(false)
	clearMaps()
end)

btnItems.Click:Connect(function()
	btnItems:SetActive(false)
	buildItemPreview()
end)

btnClearItems.Click:Connect(function()
	btnClearItems:SetActive(false)
	clearItems()
end)

btnRaceSim.Click:Connect(function()
	btnRaceSim:SetActive(false)
	runHarness("Race Sim", function(Runner)
		return Runner.runRace({ profiles = { "expert", "average", "novice" } })
	end)
end)

btnRaceSimRun.Click:Connect(function()
	btnRaceSimRun:SetActive(false)
	runHarness("Race Sim (Run)", function(Runner)
		return Runner.runRace({ mode = "run" })
	end)
end)

btnBotMatch.Click:Connect(function()
	btnBotMatch:SetActive(false)
	runHarness("Bot Match", function(Runner)
		return Runner.runMatch({ players = 4, rounds = 1 })
	end)
end)

notify("Plugin loaded. Use the 'Catastrophic Day Preview' toolbar buttons.")
