-- MapVisibility.lua
-- Show/hide helpers for biome maps, extracted from MapManager so the harness
-- and offline tests exercise the exact code the live server runs.
--
-- Each map is workspace.Maps.<Biome>Map with sub-models FarmArea / RaceTrack.
-- Hiding sets Transparency=1 / CanCollide=false; showing restores the values
-- cached in the OriginalTransparency / OriginalCanCollide attributes.
--
-- Two rules keep trigger volumes non-solid:
--   * restore() treats a stored `false` as false. (The old
--     `stored ~= nil and stored or true` idiom turned every false into true,
--     so checkpoints and drift corners became invisible walls.)
--   * the authored values are recorded right before a part is first hidden,
--     so the result no longer depends on whether cacheOriginals ran before or
--     after the map builders.

local MapVisibility = {}

function MapVisibility.mapName(biome)
	return biome:sub(1, 1):upper() .. biome:sub(2):lower() .. "Map"
end

local function remember(desc)
	if desc:GetAttribute("OriginalTransparency") == nil then
		desc:SetAttribute("OriginalTransparency", desc.Transparency)
	end
	if desc:GetAttribute("OriginalCanCollide") == nil then
		desc:SetAttribute("OriginalCanCollide", desc.CanCollide)
	end
end

local function hide(desc)
	remember(desc)
	desc.Transparency = 1
	desc.CanCollide   = false
end

local function restore(desc)
	local storedT  = desc:GetAttribute("OriginalTransparency")
	local storedCC = desc:GetAttribute("OriginalCanCollide")
	if storedT == nil then storedT = 0 end
	if storedCC == nil then storedCC = true end
	desc.Transparency = storedT
	desc.CanCollide   = storedCC
end

--- Records each BasePart's authored Transparency / CanCollide once.
function MapVisibility.cacheOriginals(mapsFolder)
	for _, mapModel in ipairs(mapsFolder:GetChildren()) do
		for _, desc in ipairs(mapModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				remember(desc)
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
					hide(desc)
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
				hide(desc)
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
