-- RaceCamera.lua
-- Keeps the race camera on the near side of walls (playtest 2026-11-16: in
-- a bend the chase camera, 12+ studs behind the car, stood behind the
-- outer wall and the wall filled the screen). RacingClient asks `unblock`
-- each frame: when something solid stands between the car and where the
-- camera wants to be, the camera comes in to just before it.

local RaceCamera = {}

RaceCamera.MARGIN   = 0.8   -- studs kept in front of the blocking surface
RaceCamera.MIN_DIST = 3     -- never closer to the car than this
RaceCamera.TRIES    = 4     -- see-through or loose parts skipped per frame

--- `focus` (the point the camera looks at), `want` (the camera position
-- the chase rule asks for) and `cast(origin, dir)` → hit or nil, where a
-- hit is { Position = Vector3, Instance = part }. `skip(part)` → true for
-- parts the view may pass through (see-through, loose, other cars).
-- Returns the camera position to use.
function RaceCamera.unblock(focus, want, cast, skip)
	local offset = want - focus
	local dist = offset.Magnitude
	if dist < 1e-3 then return want end
	local dir = offset / dist
	local from = focus
	for _ = 1, RaceCamera.TRIES do
		local left = dist - (from - focus).Magnitude
		if left <= 0 then return want end
		local hit = cast(from, dir * left)
		if not hit then return want end
		if skip and skip(hit.Instance) then
			from = hit.Position + dir * 0.05
		else
			local d = math.max(RaceCamera.MIN_DIST, (hit.Position - focus).Magnitude - RaceCamera.MARGIN)
			return focus + dir * math.min(d, dist)
		end
	end
	return want
end

return RaceCamera
