-- RaceProgress.lua
-- Race progress and respawn-target formulas used by RacingManager, extracted
-- verbatim so tests and simulators can check them against the real track.
-- Pure: takes plain numbers, returns plain numbers.
--
-- KNOWN LIMITATIONS (kept as-is; see tests/specs/race_progress.spec.luau):
--   * Progress is the distance travelled along -Z (zStart - z), not along the
--     track. On FOREST's figure-3 layout the Z coordinate does not decrease
--     monotonically, so the live ranking flips while cars drive sideways.
--   * The respawn target is always X = 0 at the progress-derived Z, which is
--     off the track wherever the track is not at X = 0.

local Constants = require(script.Parent.Constants)

local RaceProgress = {}

RaceProgress.RESPAWN_STEP_BACK = 30   -- studs behind current progress
RaceProgress.RESPAWN_LIFT      = 3    -- studs above raceStartY

--- Progress along the track axis, clamped to [0, trackLength].
function RaceProgress.progress(biome, z)
	local track = Constants.TRACK[biome]
	if not track then return 0 end
	return math.clamp(track.zStart - z, 0, track.zStart - track.zFinish)
end

--- World position where a respawning vehicle is placed.
-- @param raceStartY BiomeConfig[biome].raceStartY (or 2)
-- @returns x, y, z
function RaceProgress.respawnPoint(biome, z, raceStartY)
	local progress = RaceProgress.progress(biome, z)
	local track = Constants.TRACK[biome]
	local zStart = track and track.zStart or 600
	local safeZ = zStart - math.max(progress - RaceProgress.RESPAWN_STEP_BACK, 0)
	local y = (raceStartY or 2) + RaceProgress.RESPAWN_LIFT
	return 0, y, safeZ
end

return RaceProgress
