-- DiagnosticLogger.server.lua
-- Prints key state to Output so you can see exactly what is happening during Play.
-- Remove or disable this script once bugs are confirmed fixed.

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
if not RunService:IsStudio() then return end   -- Studio only: live servers stay quiet
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Small helper: safe require with error reporting
local function safeRequire(path)
	local ok, result = pcall(require, path)
	if not ok then
		warn("[DIAG] require failed for", tostring(path), "->", result)
		return nil
	end
	return result
end

task.wait(1)  -- let all scripts initialize first

print("=== [DIAG] Starting diagnostics ===")

-- 1. Check RemoteEvents are in ReplicatedStorage
local reFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
if reFolder then
	print("[DIAG] RemoteEvents folder found:", reFolder.ClassName, "children:", #reFolder:GetChildren())
	for _, child in ipairs(reFolder:GetChildren()) do
		print("  [DIAG]   -", child.Name, "(", child.ClassName, ")")
	end
else
	warn("[DIAG] RemoteEvents folder NOT found in ReplicatedStorage!")
end

-- 2. Check Maps folder in Workspace
local mapsFolder = workspace:FindFirstChild("Maps")
if mapsFolder then
	print("[DIAG] Maps folder found, children:", #mapsFolder:GetChildren())
	for _, child in ipairs(mapsFolder:GetChildren()) do
		print("  [DIAG]   -", child.Name, "(", child.ClassName, ")")
	end
else
	warn("[DIAG] No Maps folder in workspace! ForestMapBuilder may not have run yet.")
end

-- 3. Check GameManager state
local GameManager = safeRequire(ServerScriptService.GameManager)
if GameManager then
	print("[DIAG] GameManager loaded OK, current phase:", GameManager.getPhase())
else
	warn("[DIAG] GameManager failed to load!")
end

-- 4. Check Constants
local Constants = safeRequire(ReplicatedStorage.Shared.Constants)
if Constants then
	print("[DIAG] Constants OK - SOLO_TEST_MODE:", Constants.SOLO_TEST_MODE,
		" MIN_TO_START:", Constants.MIN_TO_START,
		" FARMING duration:", Constants.PHASE_DURATION.FARMING)
else
	warn("[DIAG] Constants failed to load!")
end

-- 5. Watch phase changes
if GameManager then
	GameManager.onPhaseChanged(function(phase, biome)
		print(string.format("[DIAG] Phase changed → %s  biome=%s", phase, tostring(biome)))

		-- Check map visibility
		if phase == "FARMING" then
			task.wait(0.5)  -- let MapManager process first
			local maps = workspace:FindFirstChild("Maps")
			if maps then
				local mapName = biome and (biome:sub(1,1):upper() .. biome:sub(2):lower() .. "Map") or "???"
				local mapModel = maps:FindFirstChild(mapName)
				if mapModel then
					print("[DIAG] Map found:", mapName, "- checking visibility...")
					local visibleParts = 0
					local hiddenParts  = 0
					for _, desc in ipairs(mapModel:GetDescendants()) do
						if desc:IsA("BasePart") then
							if desc.Transparency < 1 then visibleParts += 1
							else hiddenParts += 1
							end
						end
					end
					print(string.format("[DIAG]   Visible parts: %d  Hidden parts: %d", visibleParts, hiddenParts))
				else
					warn("[DIAG] Map NOT found:", mapName, "- available maps:", table.concat(
						(function()
							local names = {}
							for _, c in ipairs(maps:GetChildren()) do table.insert(names, c.Name) end
							return names
						end)(), ", "
					))
				end

				-- Count spawned items
				task.wait(1)  -- let FarmingManager spawn items
				local itemCount = 0
				for _, part in ipairs(workspace:GetDescendants()) do
					if part:IsA("BasePart") and part:FindFirstChild("ItemName") then
						itemCount += 1
					end
				end
				print("[DIAG] Spawned item parts with ItemName tag:", itemCount)
				if itemCount == 0 then
					warn("[DIAG] NO ITEMS SPAWNED. Check FarmingManager output above for errors.")
				end
			else
				warn("[DIAG] Still no Maps folder during FARMING phase!")
			end
		end
	end)
end

-- 6. Player join diagnostics
Players.PlayerAdded:Connect(function(player)
	print("[DIAG] Player joined:", player.Name, "| Total players:", #Players:GetPlayers())
	task.wait(3)
	print("[DIAG] 3s after join - current phase:", GameManager and GameManager.getPhase() or "unknown")
end)

print("=== [DIAG] Diagnostics ready — play the game and check Output ===")
