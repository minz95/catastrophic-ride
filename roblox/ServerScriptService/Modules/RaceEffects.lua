-- RaceEffects.lua
-- Per-player protection flags written by abilities and passives, and read by
-- every system that hurts a car (obstacles, contact, enemy abilities).
--
--   shield     – Umbrella (FOREST), Suitcase lockdown: blocks the next hit
--   invincible – Red Sofa: blocks every hit while active
--   absorb     – Rubber Duck HEAD passive: blocks one hit per race
--   disguised  – Cardboard Box: cannot be targeted by enemy abilities
--   dig        – Drill: ignores mud and off-track slow zones

local ServerScriptService = game:GetService("ServerScriptService")

local SessionManager = require(ServerScriptService.SessionManager)

local RaceEffects = {}

local function data(player)
	return player and SessionManager.getData(player)
end

--- Sets a timed flag (seconds). Returns the expiry time.
function RaceEffects.grant(player, flag, duration)
	local d = data(player)
	if not d then return end
	d._flags = d._flags or {}
	local untilT = os.clock() + (duration or math.huge)
	d._flags[flag] = untilT
	return untilT
end

function RaceEffects.revoke(player, flag)
	local d = data(player)
	if d and d._flags then d._flags[flag] = nil end
end

function RaceEffects.has(player, flag)
	local d = data(player)
	local untilT = d and d._flags and d._flags[flag]
	if untilT and untilT > os.clock() then return true end
	if untilT then d._flags[flag] = nil end
	return false
end

--- Called before something harmful happens to `player`. Returns true when the
-- hit is blocked (and consumes a one-shot shield / absorb if that is what
-- blocked it).
function RaceEffects.blocksHit(player)
	if RaceEffects.has(player, "invincible") then return true end
	if RaceEffects.has(player, "shield") then
		RaceEffects.revoke(player, "shield")
		return true
	end
	if RaceEffects.has(player, "absorb") then
		RaceEffects.revoke(player, "absorb")
		return true
	end
	return false
end

function RaceEffects.reset(player)
	local d = data(player)
	if d then d._flags = {} end
end

return RaceEffects
