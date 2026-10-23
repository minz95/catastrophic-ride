-- PlayerStore.lua
-- Each player's saved record (level, coins, daily streak, cosmetics) in a
-- DataStore. Rules for the record: Shared/Progression.
--
-- Safety:
--   * A record whose load failed is never saved in that session (saving the
--     fresh default would wipe the real one). The player still plays and
--     earns; `PlayerStore.isSaved(player)` is false and the results screen
--     says so.
--   * Bots and harness players (UserId <= 0) and harness sessions use memory
--     only. So does Studio without "Enable Studio Access to API Services".
--   * Saved on leave, every Constants.PROGRESSION.AUTOSAVE_SECONDS and on
--     shutdown (BindToClose).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Progression = require(ReplicatedStorage.Shared.Progression)

local PlayerStore = {}

PlayerStore.STORE_NAME = "PlayerProgress_v1"
PlayerStore.ATTEMPTS = 3

local _records = {}   -- userId → record
local _saved   = {}   -- userId → true when the record came from (and goes to) the DataStore
local _store   = nil
local _memoryOnly = false
local _started = false
local _onLoaded = {}

local function keyOf(userId) return "u" .. tostring(userId) end

local function store()
	if _memoryOnly then return nil end
	if _store then return _store end
	local ok, s = pcall(function() return DataStoreService:GetDataStore(PlayerStore.STORE_NAME) end)
	if ok and s then
		_store = s
	else
		warn("[PlayerStore] no DataStore (" .. tostring(s) .. "): progress is kept in memory only")
		_memoryOnly = true
	end
	return _store
end

local function retry(fn)
	local lastErr
	for attempt = 1, PlayerStore.ATTEMPTS do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		if attempt < PlayerStore.ATTEMPTS then task.wait(attempt) end
	end
	return false, lastErr
end

--- Memory only for every player (harness sessions, tests).
function PlayerStore.setMemoryOnly(on)
	_memoryOnly = on and true or false
end

--- The player's record (nil until loaded).
function PlayerStore.get(player)
	return _records[player.UserId]
end

function PlayerStore.isSaved(player)
	return _saved[player.UserId] == true
end

--- Calls fn(player, record) after each load (leaderstats, UI).
function PlayerStore.onLoaded(fn)
	table.insert(_onLoaded, fn)
end

--- Loads (or creates) the record. Never errors.
function PlayerStore.load(player)
	local userId = player.UserId
	if _records[userId] then return _records[userId] end
	local rec, saved = nil, false
	local s = userId > 0 and store() or nil
	if s then
		local ok, data = retry(function() return s:GetAsync(keyOf(userId)) end)
		if ok then
			rec, saved = Progression.migrate(data), true
		else
			warn(string.format("[PlayerStore] load failed for %d (%s): this session is not saved", userId, tostring(data)))
		end
	end
	rec = rec or Progression.newRecord()
	if not player.Parent then return rec end   -- left while loading
	_records[userId], _saved[userId] = rec, saved
	for _, fn in ipairs(_onLoaded) do task.spawn(fn, player, rec) end
	return rec
end

--- Writes the record if it was loaded from the DataStore. Returns ok.
function PlayerStore.save(player)
	local userId = player.UserId
	local rec = _records[userId]
	if not rec or not _saved[userId] then return false end
	local s = store()
	if not s then return false end
	local ok, err = retry(function()
		return s:UpdateAsync(keyOf(userId), function() return rec end)
	end)
	if not ok then warn(string.format("[PlayerStore] save failed for %d: %s", userId, tostring(err))) end
	return ok
end

--- Saves and forgets the player (PlayerRemoving).
function PlayerStore.release(player)
	PlayerStore.save(player)
	_records[player.UserId], _saved[player.UserId] = nil, nil
end

--- Connects join / leave / autosave / shutdown. Safe to call twice.
function PlayerStore.start()
	if _started then return end
	_started = true
	Players.PlayerAdded:Connect(function(p) PlayerStore.load(p) end)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(PlayerStore.load, p) end
	Players.PlayerRemoving:Connect(PlayerStore.release)
	task.spawn(function()
		while true do
			task.wait(Constants.PROGRESSION.AUTOSAVE_SECONDS)
			for _, p in ipairs(Players:GetPlayers()) do task.spawn(PlayerStore.save, p) end
		end
	end)
	pcall(function()
		game:BindToClose(function()
			local pending = 0
			for _, p in ipairs(Players:GetPlayers()) do
				pending += 1
				task.spawn(function() PlayerStore.save(p); pending -= 1 end)
			end
			local t0 = os.clock()
			while pending > 0 and os.clock() - t0 < 25 do task.wait(0.2) end
		end)
	end)
end

return PlayerStore
