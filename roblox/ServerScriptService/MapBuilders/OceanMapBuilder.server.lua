-- OceanMapBuilder.server.lua
-- Builds the OCEAN map at server start. The build logic lives in the
-- Modules.Maps.OceanMap ModuleScript so the Studio harness and the preview
-- plugin can call it in edit mode; centerline data lives in
-- ReplicatedStorage.Shared.Tracks.OceanTrack.

local ServerScriptService = game:GetService("ServerScriptService")

local ok, err = pcall(function()
	require(ServerScriptService.Modules.Maps.OceanMap).build()
end)
if not ok then warn("[OceanMapBuilder] Build failed: " .. tostring(err)) end
