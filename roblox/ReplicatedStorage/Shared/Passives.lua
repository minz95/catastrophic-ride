-- Passives.lua
-- Pure rules for the HEAD / TAIL slot passives (VehicleStats.HEAD_PASSIVES /
-- TAIL_PASSIVES). RacingManager applies them; tests check them under Lune.
-- Positions and look vectors are plain { x, z } tables on the ground plane.

local Constants    = require(script.Parent.Constants)
local VehicleStats = require(script.Parent.VehicleStats)

local Passives = {}

local P = Constants.PASSIVES

local function unit(x, z)
	local m = math.sqrt(x * x + z * z)
	if m < 1e-6 then return 0, 0 end
	return x / m, z / m
end

--- Who rear-ended whom. Returns "a", "b" or nil (side swipe / head-on).
-- a, b: { x, z, lx, lz } position and LookVector of each car.
function Passives.rearEnd(a, b)
	local abx, abz = unit(b.x - a.x, b.z - a.z)
	local dA = a.lx * abx + a.lz * abz          -- a facing towards b?
	local dB = b.lx * -abx + b.lz * -abz        -- b facing towards a?
	if dA >= P.REAR_END_DOT and dB < 0 then return "a" end
	if dB >= P.REAR_END_DOT and dA < 0 then return "b" end
	return nil
end

--- True when `other` is directly behind `leader` within range.
function Passives.isDirectlyBehind(leader, other, range, cone)
	range = range or P.SLIPSTREAM_RANGE
	cone = cone or P.SLIPSTREAM_CONE
	local dx, dz = other.x - leader.x, other.z - leader.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > range or d < 1e-6 then return false end
	local ux, uz = dx / d, dz / d
	return (leader.lx * ux + leader.lz * uz) <= -cone
end

--- Flower HEAD: speed multiplier after `cleanSeconds` without a hit.
function Passives.momentumMult(cleanSeconds, perStep)
	perStep = perStep or (VehicleStats.HEAD_PASSIVES["Flower"] or {}).momentumBonus or 0.03
	local steps = math.floor(math.max(cleanSeconds, 0) / P.MOMENTUM_STEP)
	return 1 + math.min(steps * perStep, P.MOMENTUM_MAX)
end

--- Passive tables for a car's HEAD and TAIL items (empty tables if none).
function Passives.forSlots(slots)
	slots = slots or {}
	return VehicleStats.HEAD_PASSIVES[slots.HEAD or ""] or {},
		VehicleStats.TAIL_PASSIVES[slots.TAIL or ""] or {}
end

--- Effects of a rear-end contact, as data for the caller to apply.
-- attackerSlots / victimSlots: slot assignment tables.
-- returns {
--   victimPush   = studs/s shove on the victim (0 if absorbed),
--   victimSlow   = { mult, duration } or nil,
--   attackerSlow = { mult, duration } or nil,
-- }
function Passives.contactEffects(attackerSlots, victimSlots)
	local aHead = Passives.forSlots(attackerSlots)
	local _, vTail = Passives.forSlots(victimSlots)
	local out = { victimPush = P.RAM_PUSH * (aHead.collisionPower or 1) }
	if vTail.rearImpactAbsorb then
		out.victimPush = 0
	elseif aHead.headCollisionSlow then
		out.victimSlow = { mult = P.HEAD_SLOW_MULT, duration = aHead.headCollisionSlow }
	end
	if vTail.rearContactSlow then
		out.attackerSlow = { mult = P.REAR_SLOW_MULT, duration = vTail.rearContactSlow }
	end
	return out
end

return Passives
