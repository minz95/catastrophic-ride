-- RaceStart.lua
-- Everyone starts the race at the same moment.
--
-- RACING begins with the cars on the grid, anchored. CraftingManager spawns
-- and seats them (hold), RacingManager starts the countdown (begin), and at
-- GO every held car is released in the same frame. The race clock starts at
-- GO, so seating order and spawn time never cost anyone time.
--
-- Clients read ReplicatedStorage attribute "RaceGoAt" (server time,
-- workspace:GetServerTimeNow()) for the 3-2-1 countdown and its sounds.
--
-- History: CraftingManager used to seat players one after another and
-- unanchor each car right after its own seat, about 0.4 s apart, with no
-- countdown: in a 6-player lobby the last car left 2-3 s after the first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Telemetry = require(ServerScriptService.Modules.Telemetry)

local RaceStart = {}

local _held = {}      -- [BasePart] = true, anchored until GO
local _goAt = nil     -- server time of GO for the current race
local _go = false
local _epoch = 0

local function release(primary)
	if primary and primary.Parent then
		primary.Anchored = false
	end
end

--- Forgets the previous race (call when RACING ends or a round starts).
function RaceStart.reset()
	_epoch += 1
	_held, _goAt, _go = {}, nil, false
	ReplicatedStorage:SetAttribute("RaceGoAt", nil)
end

--- Starts the countdown: GO in `seconds`. Returns the server time of GO.
function RaceStart.begin(seconds)
	_epoch += 1
	local epoch = _epoch
	_go = false
	_goAt = workspace:GetServerTimeNow() + seconds
	ReplicatedStorage:SetAttribute("RaceGoAt", _goAt)
	task.delay(seconds, function()
		if epoch ~= _epoch then return end
		_go = true
		local n = 0
		for primary in pairs(_held) do
			release(primary)
			n += 1
		end
		Telemetry.record("race_go", { released = n })
		_held = {}
	end)
	return _goAt
end

--- Keeps `primary` anchored until GO (released now if the race already went).
function RaceStart.hold(primary)
	if not primary then return end
	if _go then
		release(primary)
	else
		primary.Anchored = true
		_held[primary] = true
	end
end

function RaceStart.isGo()
	return _go
end

--- Seconds until GO (0 once the race is running, nil without a race).
function RaceStart.timeToGo()
	if not _goAt then return nil end
	return math.max(0, _goAt - workspace:GetServerTimeNow())
end

return RaceStart
