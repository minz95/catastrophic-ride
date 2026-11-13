-- AbilityKind.lua
-- What kind of thing an item's E ability is, in one word the crafting screen
-- can show next to it: SPEED (you go faster), ATTACK (hits other racers),
-- TRAP (left on the road behind you), SHIELD (protects you).
--
-- AbilityConfig is server only, so AbilityManager publishes every item's
-- kind, cooldown and hint as JSON in ReplicatedStorage "AbilityInfo"
-- (RideInfo below reads it on clients).

local AbilityKind = {}

AbilityKind.KINDS = {
	SPEED  = { label = "SPEED",  color = Color3.fromRGB(255, 200, 60) },
	ATTACK = { label = "ATTACK", color = Color3.fromRGB(255, 95, 95) },
	TRAP   = { label = "TRAP",   color = Color3.fromRGB(255, 150, 60) },
	SHIELD = { label = "SHIELD", color = Color3.fromRGB(90, 190, 255) },
}

-- self-targeted effects that hit others or protect you (the rest are SPEED)
local SELF_KIND = {
	barrelRoll = "ATTACK", cartRam = "ATTACK",
	disguise = "SHIELD", lockdown = "SHIELD", sofaFortress = "SHIELD",
	umbrellaBlock = "SHIELD", bloomCleanse = "SHIELD", emergencyFloat = "SHIELD",
}

--- Kind of an AbilityConfig entry.
function AbilityKind.of(cfg)
	if type(cfg) ~= "table" then return nil end
	local t = cfg.targetType
	if t == "track_drop" then return "TRAP" end
	if t and t ~= "self" then return "ATTACK" end
	return SELF_KIND[cfg.effectKey] or "SPEED"
end

AbilityKind.VALUE_NAME = "AbilityInfo"

--- Server: { [item] = { kind, cd, hint } } from AbilityConfig.
function AbilityKind.table(abilityConfig)
	local out = {}
	for item, cfg in pairs(abilityConfig) do
		if type(cfg) == "table" and cfg.effectKey then
			out[item] = { kind = AbilityKind.of(cfg), cd = cfg.cooldown, hint = cfg.uiHint }
		end
	end
	return out
end

local _cache = nil

--- Client: the published table (empty until the server wrote it).
function AbilityKind.info(replicatedStorage, httpService)
	if _cache then return _cache end
	local v = replicatedStorage:FindFirstChild(AbilityKind.VALUE_NAME)
	if not v or v.Value == "" then return {} end
	local ok, t = pcall(function() return httpService:JSONDecode(v.Value) end)
	if ok and type(t) == "table" then _cache = t return t end
	return {}
end

return AbilityKind
