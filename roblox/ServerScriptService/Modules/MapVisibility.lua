-- MapVisibility.lua
-- Show/hide helpers for biome maps, extracted from MapManager so the harness
-- and offline tests exercise the exact code the live server runs.
--
-- Each map is workspace.Maps.<Biome>Map with sub-models FarmArea / RaceTrack.
-- Hiding sets Transparency=1 / CanCollide=false; showing restores the values
-- cached in the OriginalTransparency / OriginalCanCollide attributes.
--
-- KNOWN BUG (kept as-is, see tests/specs/map_forest.spec.luau):
--   `storedCC ~= nil and storedCC or true` evaluates to true when the stored
--   value is false (Lua and/or idiom), so every non-collidable part — trigger
--   volumes, decorations — becomes solid when its map is shown.

local MapVisibility = {}

function MapVisibility.mapName(biome)
	return biome:sub(1, 1):upper() .. biome:sub(2):lower() .. "Map"
end

local function restore(desc)
	local storedT  = desc:GetAttribute("OriginalTransparency")
	local storedCC = desc:GetAttribute("OriginalCanCollide")
	desc.Transparency = storedT  ~= nil and storedT  or 0
	desc.CanCollide   = storedCC ~= nil and storedCC or true
end

--- Records each BasePart's authored Transparency / CanCollide once.
function MapVisibility.cacheOriginals(mapsFolder)
	for _, mapModel in ipairs(mapsFolder:GetChildren()) do
		for _, desc in ipairs(mapModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc:GetAttribute("OriginalTransparency") == nil then
					desc:SetAttribute("OriginalTransparency", desc.Transparency)
				end
				if desc:GetAttribute("OriginalCanCollide") == nil then
					desc:SetAttribute("OriginalCanCollide", desc.CanCollide)
				end
			end
		end
	end
end

function MapVisibility.hideAll(mapsFolder)
	for _, child in ipairs(mapsFolder:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			child:SetAttribute("MapVisible", false)
			for _, desc in ipairs(child:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Transparency = 1
					desc.CanCollide   = false
				end
			end
		end
	end
end

--- Shows every part of one map. Returns false if the map model is missing.
function MapVisibility.show(mapModel)
	if not mapModel then
		return false
	end
	mapModel:SetAttribute("MapVisible", true)
	for _, desc in ipairs(mapModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			restore(desc)
		end
	end
	return true
end

--- Shows or hides one sub-model (FarmArea / RaceTrack) of a map.
function MapVisibility.setSubVisible(mapModel, subName, visible)
	if not mapModel then return end
	local sub = mapModel:FindFirstChild(subName)
	if not sub then return end
	for _, desc in ipairs(sub:GetDescendants()) do
		if desc:IsA("BasePart") then
			if visible then
				restore(desc)
			else
				desc.Transparency = 1
				desc.CanCollide   = false
			end
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			-- GUIs ignore the Part.Transparency of their adornee, so the
			-- transparency loop above won't hide their text. Without this
			-- branch the floating checkpoint labels stayed visible all phases.
			desc.Enabled = visible
		end
	end
end

--- The state a map is in during the RACING phase, as MapManager drives it:
-- FARMING shows the whole map then hides RaceTrack; RACING shows RaceTrack
-- and hides FarmArea.
function MapVisibility.applyRacingState(mapsFolder, mapModel)
	MapVisibility.hideAll(mapsFolder)
	MapVisibility.show(mapModel)
	MapVisibility.setSubVisible(mapModel, "FarmArea", true)
	MapVisibility.setSubVisible(mapModel, "RaceTrack", false)
	MapVisibility.setSubVisible(mapModel, "FarmArea", false)
	MapVisibility.setSubVisible(mapModel, "RaceTrack", true)
end

return MapVisibility
