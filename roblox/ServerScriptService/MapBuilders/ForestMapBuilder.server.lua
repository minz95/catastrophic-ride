-- ForestMapBuilder.server.lua
-- Builds the FOREST map at server start. The build logic lives in the
-- Modules.Maps.ForestMap ModuleScript so the Studio harness and the preview
-- plugin can call it in edit mode; layout data lives in
-- ReplicatedStorage.Shared.Tracks.ForestTrack.
-- Resolves: Issue #8, #83, #66, #87, #97, #128

local ServerScriptService = game:GetService("ServerScriptService")

local ok, err = pcall(function()
	require(ServerScriptService.Modules.Maps.ForestMap).build()
end)
if not ok then warn("[ForestMapBuilder] Build failed: " .. tostring(err)) end
-- Tells the Studio harness (TestHarness.RaceSim) the map is built, so it can
-- reuse it instead of building a second copy that this script would replace.
ServerScriptService:SetAttribute("MapBuilt_FOREST", ok)
