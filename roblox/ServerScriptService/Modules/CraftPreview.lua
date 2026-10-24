-- CraftPreview.lua
-- The crafting screen's showroom: while a player arranges slots, the server
-- builds the vehicle those slots make (VehicleBuilder.build, the same call as
-- the race, with the player's shop look) and puts a still copy in that
-- player's PlayerGui.CraftPreview, which only they receive. CraftingUI shows
-- it in a ViewportFrame, turning slowly with the player's avatar seated.
-- Builds are coalesced: a burst of slot changes builds once, the latest wins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local CraftPreview = {}

CraftPreview.FOLDER = "CraftPreview"
CraftPreview.GAP = 0.15   -- s between two builds for one player

local _pending = {}   -- [player] = { slots, biome }
local _busy = {}

-- Physics movers and scripts have no place in a picture.
local STRIP = { "BodyMover", "BodyGyro", "BodyPosition", "BodyVelocity", "BodyAngularVelocity", "BodyForce",
	"Constraint", "BaseScript" }

local function build(player, slots, biome)
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then return end
	local VehicleBuilder = require(ServerScriptService.Modules.VehicleBuilder)
	local stats = VehicleStats.calculate(slots.BODY and ItemConfig[slots.BODY], slots.ENGINE and ItemConfig[slots.ENGINE],
		slots.SPECIAL and ItemConfig[slots.SPECIAL], biome)
	stats = VehicleStats.applyMobility(stats, slots.MOBILITY and ItemConfig[slots.MOBILITY], biome)
	local rec = PlayerStore.get(player)
	local model = VehicleBuilder.build(stats, biome, CFrame.new(), slots, Cosmetics.look(rec and rec.equipped))
	if not model then return end
	for _, d in ipairs(model:GetDescendants()) do
		local strip = false
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then strip = true break end
		end
		if strip then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Name = "Preview"
	model:SetAttribute("Biome", biome)
	local folder = gui:FindFirstChild(CraftPreview.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CraftPreview.FOLDER
		folder.Parent = gui
	end
	for _, old in ipairs(folder:GetChildren()) do old:Destroy() end
	model.Parent = folder
	Telemetry.record("craft_preview", { userId = player.UserId, body = slots.BODY, riding = model:GetAttribute("Riding") })
end

--- Shows the vehicle `slots` (validated) make in `biome` to `player`.
function CraftPreview.show(player, slots, biome)
	_pending[player] = { slots = slots or {}, biome = biome }
	if _busy[player] then return end
	_busy[player] = true
	task.spawn(function()
		while _pending[player] do
			local job = _pending[player]
			_pending[player] = nil
			local ok, err = pcall(build, player, job.slots, job.biome)
			if not ok then warn("[CraftPreview] " .. tostring(err)) end
			task.wait(CraftPreview.GAP)
		end
		_busy[player] = nil
	end)
end

--- Crafting over: the previews go.
function CraftPreview.clear(player)
	_pending[player] = nil
	local gui = player:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild(CraftPreview.FOLDER)
	if folder then folder:ClearAllChildren() end
end

return CraftPreview
