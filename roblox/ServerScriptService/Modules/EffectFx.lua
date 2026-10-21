-- EffectFx.lua
-- One call for "effect `key` just landed on `player`'s car": tells every
-- client (RemoteEvents.EffectFx → StarterPlayerScripts/EffectFx draws it on
-- that car, for everyone to see) and, when Telemetry.detailed is on (Studio
-- harness), measures the car before and during the effect so the harness can
-- check that the effect really happened in Roblox physics:
--
--   ability_probe { userId, effect, from, y0, yMax, yMin, v0, vMax, vMin,
--                   maxSpeed0, maxSpeedMid, turn0, turnMid, lift0, window }
--
-- Look of every key: ReplicatedStorage/Shared/EffectLook.lua.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local RemoteEvents   = require(ReplicatedStorage.RemoteEvents)
local SessionManager = require(ServerScriptService.SessionManager)
local Telemetry      = require(ServerScriptService.Modules.Telemetry)

local EffectFx = {}

local P = Constants.EFFECT_PROBE

local function snap(player)
	local pdata = SessionManager.getData(player)
	local vehicle = pdata and pdata.vehicleModel
	local primary = vehicle and vehicle.PrimaryPart
	if not primary or not primary.Parent then return nil end
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	local v = primary.AssemblyLinearVelocity
	return {
		y = primary.Position.Y,
		v = Vector3.new(v.X, 0, v.Z).Magnitude,
		maxSpeed = seat and seat.MaxSpeed,
		turn = seat and seat.TurnSpeed,
		lift = primary:GetAttribute("LiftOffset") or 0,
	}
end

local function r1(x)
	return x and math.floor(x * 10 + 0.5) / 10
end

local function probe(key, player, duration, from)
	local s0 = snap(player)
	if not s0 then return end
	local window = math.clamp((duration or P.MIN) * P.FRACTION, P.MIN, P.MAX)
	task.spawn(function()
		local yMax, yMin, vMax, vMin = s0.y, s0.y, s0.v, s0.v
		local mid
		local t = 0
		while t < window do
			task.wait(P.STEP)
			t += P.STEP
			local s = snap(player)
			if not s then break end
			yMax, yMin = math.max(yMax, s.y), math.min(yMin, s.y)
			vMax, vMin = math.max(vMax, s.v), math.min(vMin, s.v)
			if not mid and t >= window * 0.5 then mid = s end
		end
		mid = mid or s0
		Telemetry.record("ability_probe", {
			userId = player.UserId, effect = key, from = from and from.UserId, window = r1(window),
			y0 = r1(s0.y), yMax = r1(yMax), yMin = r1(yMin),
			v0 = r1(s0.v), vMax = r1(vMax), vMin = r1(vMin),
			maxSpeed0 = r1(s0.maxSpeed), maxSpeedMid = r1(mid.maxSpeed),
			turn0 = r1(s0.turn), turnMid = r1(mid.turn),
			lift0 = r1(s0.lift),   -- a lift already active (lifts do not stack)
		})
	end)
end

--- Effect `key` lands on `player`. Call it just BEFORE applying the effect,
-- so the probe's first sample is the car without it. duration: seconds it lasts (nil = a
-- one-off burst). from: the player who caused it (draws a beam from their
-- car). extra: small table passed to the client look (e.g. { text = "+6%" }).
function EffectFx.play(key, player, duration, from, extra)
	if not player then return end
	RemoteEvents.EffectFx:FireAllClients(key, player.UserId, {
		duration = duration,
		from = from and from.UserId or nil,
		text = extra and extra.text or nil,
	})
	if Telemetry.detailed then
		probe(key, player, duration, from)
	end
end

return EffectFx
