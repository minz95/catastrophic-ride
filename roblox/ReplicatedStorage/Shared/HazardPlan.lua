-- HazardPlan.lua
-- Where falling logs (FOREST, HazardManager) land, as a pure function, so the
-- server, the offline race sim and the specs use the same rule:
--   * each log lies across part of the lane, never across all of it: an open
--     gap of at least Constants.HAZARDS.LOG_MIN_GAP studs stays on one side;
--   * logs of one drop are at least LOG_SPACING studs apart along the track,
--     so they never line up into a wall;
--   * none lands in the last stretch before the finish, on a jump ramp,
--     a mud patch or a boost pad, or under a higher layer of the road
--     (keepClear).
-- No Roblox types.

local Constants = require(script.Parent.Constants)

local HazardPlan = {}

--- Log spots ahead of `leadS` (progress of the leading car).
-- geo: TrackGeometry; width: lane width; rnd(): uniform [0, 1).
-- Returns { { s, lateral, x, z, y (road height), yaw, trackYaw, length } }.
--- Track progress of the features logs keep away from (track data).
function HazardPlan.keepClear(geo, track)
	local out = {}
	for _, key in ipairs({ "jumpRamps", "mudZones", "boostPads" }) do
		for _, p in ipairs(track[key] or {}) do
			table.insert(out, geo:project(p[1], p[2]).s)
		end
	end
	-- nor under a higher layer of the road (the spiral's lower turns): a log
	-- would fall through the deck above
	if geo.hasHeights then
		for s = 0, geo.length, 10 do
			local x, z = geo:pointAt(s)
			if geo:coveredAt(x, z, geo:heightAt(s), 0) then table.insert(out, s) end
		end
	end
	return out
end

function HazardPlan.logSpots(geo, width, leadS, count, rnd, keepClear)
	local H = Constants.HAZARDS
	local out = {}
	local half = width / 2
	local len = H.LOG_SIZE[1]
	-- furthest a log centre may sit from the centreline and still leave the gap
	local maxLat = math.max(0, half - H.LOG_MIN_GAP - len / 2 - H.LOG_WALL_MARGIN)
	maxLat = math.min(maxLat, H.LOG_LATERAL)
	for _ = 1, (count or 3) * 4 do
		if #out >= (count or 3) then break end
		local s = leadS + H.LOG_AHEAD_MIN + rnd() * (H.LOG_AHEAD_MAX - H.LOG_AHEAD_MIN)
		if s <= geo.length - H.LOG_FINISH_CLEAR then
			local ok = true
			for _, o in ipairs(out) do
				if math.abs(o.s - s) < H.LOG_SPACING then ok = false break end
			end
			for _, k in ipairs(keepClear or {}) do
				if math.abs(k - s) < H.LOG_KEEP_CLEAR then ok = false break end
			end
			if ok then
				local lateral = (rnd() * 2 - 1) * maxLat
				local x, z = geo:offsetPoint(s, lateral)
				local trackYaw = geo:yawAt(s)
				local yaw = trackYaw + (rnd() - 0.5) * 2 * H.LOG_YAW_JITTER
				table.insert(out, { s = s, lateral = lateral, x = x, z = z, y = geo:heightAt(s), yaw = yaw, trackYaw = trackYaw, length = len })
			end
		end
	end
	return out
end

--- Lateral span [lo, hi] a log covers across the lane (its long axis lies
-- across the track, turned by the jitter).
function HazardPlan.span(spot)
	local H = Constants.HAZARDS
	local tilt = math.abs(math.cos(spot.yaw - spot.trackYaw))   -- 1 = straight across
	local reach = spot.length / 2 * tilt + H.LOG_SIZE[2] / 2
	return spot.lateral - reach, spot.lateral + reach
end

--- The widest open stretch of lane (studs) left beside the logs within
-- `along` studs of progress `s`.
function HazardPlan.widestGap(spots, s, width, along)
	local half = width / 2
	local spans = {}
	for _, sp in ipairs(spots) do
		if math.abs(sp.s - s) <= along then
			local lo, hi = HazardPlan.span(sp)
			table.insert(spans, { lo, hi })
		end
	end
	table.sort(spans, function(a, b) return a[1] < b[1] end)
	local best, cursor = 0, -half
	for _, sp in ipairs(spans) do
		best = math.max(best, sp[1] - cursor)
		cursor = math.max(cursor, sp[2])
	end
	return math.max(best, half - cursor)
end

return HazardPlan
