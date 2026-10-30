-- PlayerStore.lua
-- Each player's saved record (level, coins, daily streak, cosmetics) in a
-- DataStore. Rules for the record: Shared/Progression.
--
-- Safety:
--   * A record whose load failed is never saved in that session (saving the
--     fresh default would wipe the real one). The player still plays and
--     earns; `PlayerStore.isSaved(player)` is false and the results screen
--     says so.
--   * Session lock: loading claims the record (`_lock` = this server, time).
--     A player who hops servers waits until the old server's last save
--     released it (at most LOCK_TRIES × LOCK_WAIT s, then the lock is taken
--     over). Every write bumps `_n`; a server whose record was written by
--     someone else since stops saving instead of writing over it.
--   * Writes for one player run one at a time; `saveSoon` (shop) merges
--     clicks into one write every SAVE_SOON s (DataStore budget).
--   * Shutdown (BindToClose) saves everyone and waits for the saves already
--     running (a player who left just before the close).
--   * Rejoining the same server waits for the old session's release.
--   * Bots and harness players (UserId <= 0) and harness sessions use memory
--     only. So does Studio without "Enable Studio Access to API Services";
--     with it, Studio uses its own store (STUDIO_STORE_NAME), never the live
--     players' records.
--   * Saved on leave, every Constants.PROGRESSION.AUTOSAVE_SECONDS and on
--     shutdown.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Progression = require(ReplicatedStorage.Shared.Progression)

local PlayerStore = {}

PlayerStore.LIVE_STORE_NAME = "PlayerProgress_v1"
PlayerStore.STUDIO_STORE_NAME = "PlayerProgress_studio"
PlayerStore.STORE_NAME = RunService:IsStudio() and PlayerStore.STUDIO_STORE_NAME or PlayerStore.LIVE_STORE_NAME
PlayerStore.ATTEMPTS = 3
PlayerStore.RELEASE_ATTEMPTS = 5     -- leaving: 1, 2, 4, 8 s between tries
PlayerStore.LOCK_TRIES = 6
PlayerStore.LOCK_WAIT = 3            -- s between tries while another server holds the record
PlayerStore.LOCK_STALE = Constants.PROGRESSION.AUTOSAVE_SECONDS * 3   -- a lock not refreshed this long is dead
PlayerStore.SAVE_SOON = 6            -- s: shop clicks merge into one write
PlayerStore.CLOSE_WAIT = 25          -- s: BindToClose gives up after this

local _records = {}   -- userId → record
local _saved   = {}   -- userId → true when the record came from (and goes to) the DataStore
local _owner   = {}   -- userId → the Player the record belongs to
local _written = {}   -- userId → the `_n` this server last wrote (or loaded)
local _busy    = {}   -- userId → a write is running
local _soon    = {}   -- userId → a merged write is queued
local _releasing = {} -- userId → the leaving session is still saving
local _inflight = 0   -- writes running (BindToClose waits for them)
local _store   = nil
local _memoryOnly = false
local _started = false
local _onLoaded = {}

local SESSION = (function()
	local ok, job = pcall(function() return game.JobId end)
	if ok and type(job) == "string" and job ~= "" then return job end
	local ok2, guid = pcall(function() return HttpService:GenerateGUID(false) end)
	return ok2 and guid or ("s" .. tostring(os.clock()) .. tostring(math.random(1, 1e9)))
end)()
PlayerStore.SESSION = SESSION

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

local function retry(fn, attempts)
	local lastErr
	attempts = attempts or PlayerStore.ATTEMPTS
	for attempt = 1, attempts do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		if attempt < attempts then task.wait(2 ^ (attempt - 1)) end
	end
	return false, lastErr
end

local function lockedByOther(old)
	local lock = type(old) == "table" and old._lock
	return type(lock) == "table" and lock.job ~= SESSION
		and type(lock.t) == "number" and os.time() - lock.t < PlayerStore.LOCK_STALE
end

--- Memory only for every player (harness sessions, tests).
function PlayerStore.setMemoryOnly(on)
	_memoryOnly = on and true or false
end

--- The player's record (nil until loaded).
function PlayerStore.get(player)
	local userId = player.UserId
	if _owner[userId] ~= nil and _owner[userId] ~= player then return nil end
	return _records[userId]
end

function PlayerStore.isSaved(player)
	return _saved[player.UserId] == true and _owner[player.UserId] == player
end

--- Calls fn(player, record) after each load (leaderstats, UI).
function PlayerStore.onLoaded(fn)
	table.insert(_onLoaded, fn)
end

-- Reads and claims the record. Returns ok, record.
local function claim(s, userId)
	local key = keyOf(userId)
	for attempt = 1, PlayerStore.LOCK_TRIES do
		local takeOver = attempt == PlayerStore.LOCK_TRIES
		local other = false
		local ok, data = retry(function()
			return s:UpdateAsync(key, function(old)
				other = false
				if lockedByOther(old) and not takeOver then other = true; return nil end
				if type(old) ~= "table" then old = Progression.newRecord() end
				old._n = (tonumber(old._n) or 0) + 1
				old._lock = { job = SESSION, t = os.time() }
				return old
			end)
		end)
		if not ok then return false, data end
		if not other then
			if takeOver and attempt > 1 then
				warn(string.format("[PlayerStore] took over the record of %d from another server", userId))
			end
			return true, data
		end
		task.wait(PlayerStore.LOCK_WAIT)
	end
	return false, "locked"
end

--- Loads (or creates) the record. Never errors.
function PlayerStore.load(player)
	local userId = player.UserId
	-- the same player left this server a moment ago: their last save first
	local t0 = os.clock()
	while _releasing[userId] and os.clock() - t0 < 60 do task.wait(0.2) end
	if _records[userId] and _owner[userId] == player then return _records[userId] end
	local rec, saved = nil, false
	local s = userId > 0 and store() or nil
	if s then
		local ok, data = claim(s, userId)
		if ok and type(data) == "table" then
			rec, saved = Progression.migrate(data), true
		else
			warn(string.format("[PlayerStore] load failed for %d (%s): this session is not saved", userId, tostring(data)))
		end
	end
	rec = rec or Progression.newRecord()
	if not player.Parent then
		-- left while loading: give the record back
		if saved then
			_records[userId], _saved[userId], _owner[userId], _written[userId] = rec, true, player, rec._n
			PlayerStore.release(player)
		end
		return rec
	end
	_records[userId], _saved[userId], _owner[userId] = rec, saved, player
	_written[userId] = saved and rec._n or nil
	for _, fn in ipairs(_onLoaded) do task.spawn(fn, player, rec) end
	return rec
end

-- One write. `final`: the session ends (lock cleared, longer retries).
local function write(player, final)
	local userId = player.UserId
	local rec = _records[userId]
	if not rec or not _saved[userId] or _owner[userId] ~= player then return false end
	local s = store()
	if not s then return false end
	local t0 = os.clock()
	while _busy[userId] and os.clock() - t0 < 60 do task.wait(0.1) end
	if not _saved[userId] or _records[userId] ~= rec then return false end
	_busy[userId] = true
	_inflight += 1
	local refused = false
	local ok, err = retry(function()
		return s:UpdateAsync(keyOf(userId), function(old)
			refused = false
			local w = _written[userId] or 0
			local n = type(old) == "table" and tonumber(old._n) or 0
			local ours = type(old) == "table" and type(old._lock) == "table" and old._lock.job == SESSION
			-- written by another server since we loaded: never write over it
			if not (n == w or (n == w + 1 and ours)) then refused = true; return nil end
			rec._n = n + 1
			rec._lock = (not final) and { job = SESSION, t = os.time() } or nil
			return rec
		end)
	end, final and PlayerStore.RELEASE_ATTEMPTS or PlayerStore.ATTEMPTS)
	_inflight -= 1
	_busy[userId] = nil
	if ok and refused then
		warn(string.format("[PlayerStore] %d's record was saved by another server: this session stops saving", userId))
		_saved[userId] = false
		return false
	end
	if ok then
		_written[userId] = rec._n
	else
		warn(string.format("[PlayerStore] save failed for %d: %s", userId, tostring(err)))
	end
	return ok
end

--- Writes the record if it was loaded from the DataStore. Returns ok.
function PlayerStore.save(player)
	return write(player, false)
end

--- A write within SAVE_SOON s; clicks in between share it (shop).
function PlayerStore.saveSoon(player)
	local userId = player.UserId
	if _soon[userId] then return end
	_soon[userId] = true
	task.delay(PlayerStore.SAVE_SOON, function()
		_soon[userId] = nil
		if _owner[userId] == player then write(player, false) end
	end)
end

--- Saves, releases the lock and forgets the player (PlayerRemoving).
function PlayerStore.release(player)
	local userId = player.UserId
	if _owner[userId] ~= player then return end
	_releasing[userId] = true
	write(player, true)
	if _owner[userId] == player then
		_records[userId], _saved[userId], _owner[userId], _written[userId] = nil, nil, nil, nil
	end
	_releasing[userId] = nil
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
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(PlayerStore.release, p)
			end
			-- and the leaves already saving (the last player out)
			local t0 = os.clock()
			task.wait()
			while _inflight > 0 and os.clock() - t0 < PlayerStore.CLOSE_WAIT do task.wait(0.2) end
		end)
	end)
end

--- Writes running now (tests, BindToClose).
function PlayerStore.inflight()
	return _inflight
end

return PlayerStore
