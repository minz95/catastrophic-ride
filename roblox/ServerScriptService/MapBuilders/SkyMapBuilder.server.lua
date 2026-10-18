-- SkyMapBuilder.server.lua
-- Builds the SKY map at server start. The build logic lives in the
-- Modules.Maps.SkyMap ModuleScript so the Studio harness and the preview
-- plugin can call it in edit mode; centerline data lives in
-- ReplicatedStorage.Shared.Tracks.SkyTrack.

local ServerScriptService = game:GetService("ServerScriptService")

local ok, err = pcall(function()
	require(ServerScriptService.Modules.Maps.SkyMap).build()
end)
if not ok then warn("[SkyMapBuilder] Build failed: " .. tostring(err)) end
