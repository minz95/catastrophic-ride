-- CraftPreview.lua
-- The crafting screen's showroom: while a player arranges slots, the server
-- builds the vehicle those slots make (VehicleBuilder.build, the same call as
-- the race, with the player's shop look) and puts a still copy in that
-- player's PlayerGui.CraftPreview, which only they receive. CraftingUI shows
-- it in a ViewportFrame, turning slowly with the player's avatar seated.
-- Builds are coalesced: a burst of slot changes builds once, the latest wins.
-- Parts of spinning MOBILITY items carry the attribute SpinHub (their hub's
-- name) so the showroom can turn wheels, paddles and propellers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfig = require(ServerScriptService.Modules.ItemConfig)
local VehicleStats = require(ReplicatedStorage.Shared.VehicleStats)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local PlayerStore = require(ServerScriptService.Modules.PlayerStore)
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local CraftPreview = {}

CraftPreview.FOLDER = "CraftPreview"
CraftPreview.GAP = 0.3    -- s between two builds for one player (a draft flood built all the time)

-- weak keys: a player who left is not kept alive here
local _pending = setmetatable({}, { __mode = "k" })   -- [player] = { slots, biome }
local _busy = setmetatable({}, { __mode = "k" })
local _shown = setmetatable({}, { __mode = "k" })     -- [player] = { slots, biome } last asked for (refresh)

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
	-- spinning MOBILITY copies: say which hub each part turns round, the
	-- showroom turns them itself (the joints mean nothing once anchored)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") and d.Part0 and d.Part1 and d.Part0.Name:sub(1, 8) == "SpinHub_" then
			d.Part1:SetAttribute("SpinHub", d.Part0.Name)
		end
	end
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
	-- how many parts it has: the client shows it only once all arrived (a
	-- big item model can replicate after the Model itself; a copy taken too
	-- early showed the vehicle without its ridden item)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
	end
	model:SetAttribute("Parts", n)
	local folder = gui:FindFirstChild(CraftPreview.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CraftPreview.FOLDER
		folder.Parent = gui
	end
	-- crafting ended (clear) while this was building: no stray preview
	if not _shown[player] or not player.Parent then model:Destroy() return end
	for _, old in ipairs(folder:GetChildren()) do old:Destroy() end
	model.Parent = folder
	Telemetry.record("craft_preview", { userId = player.UserId, body = slots.BODY, riding = model:GetAttribute("Riding") })
end

--- Shows the vehicle `slots` (validated) make in `biome` to `player`.
function CraftPreview.show(player, slots, biome)
	_shown[player] = { slots = slots or {}, biome = biome }
	_pending[player] = _shown[player]
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

--- The player's shop look changed (Modules/Shop equip): build the same
-- slots again so the showroom shows the new paint / trail. Nothing outside
-- CRAFTING (no showroom then).
function CraftPreview.refresh(player)
	local last = _shown[player]
	if last then CraftPreview.show(player, last.slots, last.biome) end
end

--- Crafting over: the previews go.
function CraftPreview.clear(player)
	_pending[player] = nil
	_shown[player] = nil
	local gui = player:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild(CraftPreview.FOLDER)
	if folder then folder:ClearAllChildren() end
end

return CraftPreview
