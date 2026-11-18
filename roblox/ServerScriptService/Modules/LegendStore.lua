-- LegendStore.lua
-- Legend Rides shared by every server (rules: Shared/LegendRides). One
-- DataStore key holds the listings with their sold counts (UpdateAsync, so
-- two servers selling the last copy cannot both get it); "royalty_<userId>"
-- holds coins an owner earned while not on the buyer's server, taken when
-- they are next on a server (`claim`). Each listing on sale is built still
-- into ReplicatedStorage.LegendRides/<id> for the shop's pictures.
-- A store that cannot be reached (Studio without API access) leaves the
-- listings in this server's memory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LegendRides = require(ReplicatedStorage.Shared.LegendRides)

local LegendStore = {}

LegendStore.NAME = RunService:IsStudio() and "LegendRides_studio_v1" or "LegendRides_v1"
LegendStore.KEY = "listings"
LegendStore.FOLDER = "LegendRides"

local _list = {}
local _listeners = {}

--- `fn()` after the listings or their pictures change (the lobby's pads).
function LegendStore.onChanged(fn)
	table.insert(_listeners, fn)
end
local _memRoyalty = {}   -- userId → { coins, sales, title } when the store is down

LegendStore.memoryOnly = false   -- set by the lobby film (TestHarness/LobbyFilm): nothing it sells is kept

local function store()
	if LegendStore.memoryOnly then error("memory only") end
	return game:GetService("DataStoreService"):GetDataStore(LegendStore.NAME)
end

local function now()
	return os.time()
end

--- The listings this server knows (all, open or not).
function LegendStore.list()
	return _list
end

function LegendStore.find(id)
	for _, l in ipairs(_list) do
		if l.id == id then return l end
	end
	return nil
end

--- Builds the open listings' pictures; removes those gone.
function LegendStore.buildModels()
	local folder = ReplicatedStorage:FindFirstChild(LegendStore.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LegendStore.FOLDER
		folder.Parent = ReplicatedStorage
	end
	local open = {}
	-- every listing on sale (up to KEEP): the used-car lot shows them all
	for _, l in ipairs(LegendRides.active(_list, now(), Constants.LEGEND.KEEP)) do
		open[l.id] = true
		if not folder:FindFirstChild(l.id) then
			local HallOfFame = require(ServerScriptService.Modules.HallOfFame)
			local model = HallOfFame.buildStill(l)
			if model then
				model.Name = l.id
				model:SetAttribute("Title", l.title)
				model.Parent = folder
			end
		end
	end
	for _, c in ipairs(folder:GetChildren()) do
		if not open[c.Name] then c:Destroy() end
	end
	for _, fn in ipairs(_listeners) do task.spawn(fn) end
end

--- Reads the listings again (every Constants.LEGEND.POLL s).
function LegendStore.refresh()
	local ok, v = pcall(function() return store():GetAsync(LegendStore.KEY) end)
	if ok and type(v) == "table" then _list = v end
	pcall(LegendStore.buildModels)
end

--- Puts listing `l` on sale.
function LegendStore.add(l)
	local ok, v = pcall(function()
		return store():UpdateAsync(LegendStore.KEY, function(old)
			return LegendRides.add(type(old) == "table" and old or {}, l)
		end)
	end)
	if ok and type(v) == "table" then
		_list = v
	else
		_list = LegendRides.add(_list, l)
	end
	pcall(LegendStore.buildModels)
end

--- Takes one copy of listing `id`: "ok" or "denied: …".
function LegendStore.take(id)
	local result = "denied: unknown"
	local ok, v = pcall(function()
		return store():UpdateAsync(LegendStore.KEY, function(old)
			local list, res = LegendRides.take(type(old) == "table" and old or {}, id, now())
			result = res
			if res ~= "ok" then return nil end   -- nothing to write
			return list
		end)
	end)
	if ok then
		if type(v) == "table" then _list = v end
	else
		local _, res = LegendRides.take(_list, id, now())
		result = res
	end
	if result ~= "ok" then
		-- someone else may have taken the last one: show what the store says
		task.spawn(LegendStore.refresh)
	end
	pcall(LegendStore.buildModels)
	return result
end

--- Coins `ownerId` earned from a sale of `title` while not on this server.
function LegendStore.royalty(ownerId, coins, title)
	local ok = pcall(function()
		store():UpdateAsync("royalty_" .. ownerId, function(old)
			old = type(old) == "table" and old or { coins = 0, sales = 0 }
			old.coins += coins
			old.sales += 1
			old.title = title
			return old
		end)
	end)
	if not ok then
		local r = _memRoyalty[ownerId] or { coins = 0, sales = 0 }
		r.coins += coins
		r.sales += 1
		r.title = title
		_memRoyalty[ownerId] = r
	end
end

--- Takes what `ownerId` earned while away: { coins, sales, title } or nil.
function LegendStore.claim(ownerId)
	local got = nil
	pcall(function()
		store():UpdateAsync("royalty_" .. ownerId, function(old)
			if type(old) ~= "table" or (old.coins or 0) <= 0 then return nil end
			got = old
			return { coins = 0, sales = 0 }
		end)
	end)
	local mem = _memRoyalty[ownerId]
	if mem then
		_memRoyalty[ownerId] = nil
		got = got or { coins = 0, sales = 0 }
		got.coins += mem.coins
		got.sales += mem.sales
		got.title = got.title or mem.title
	end
	return got
end

--- Reads the store now and every POLL s.
function LegendStore.start()
	task.spawn(function()
		while true do
			LegendStore.refresh()
			task.wait(Constants.LEGEND.POLL)
		end
	end)
end

return LegendStore
