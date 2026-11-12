-- BoxPlan.lua
-- Item boxes on the race track (Constants.MYSTERY_BOX), as pure functions so
-- the server (Modules/MysteryBoxes) and the specs use the same rules:
--   * rows: each race draws new spots. The road between START_CLEAR after
--     the grid and FINISH_CLEAR before the finish is cut into ROWS equal
--     stretches and each gets one row somewhere in it, never within
--     KEEP_CLEAR of a ramp, boost pad, mud, gap jump, tight corner
--     (HazardPlan.keepClear) or checkpoint gate. A row is PER_ROW boxes across the lane.
--   * power: what a box gives, drawn with the odds of your place
--     (ODDS: the leader mostly defence, the back of the field the strong ones).
-- No Roblox types.

local Constants  = require(script.Parent.Constants)
local HazardPlan = require(script.Parent.HazardPlan)

local BoxPlan = {}

local function clear(s, keep, gap)
	for _, k in ipairs(keep) do
		if math.abs(k - s) < gap then return false end
	end
	return true
end

--- Rows of boxes for one race.
-- geo: TrackGeometry; track: the track data; biome; rnd(): uniform [0, 1).
-- Returns { { s, boxes = { { x, y, z, lateral } } } }, sorted by s.
function BoxPlan.rows(geo, track, biome, rnd)
	local B = Constants.MYSTERY_BOX
	local finishS = geo.length
	if track.finishZ then
		finishS = geo:project(track.finishX or 0, track.finishZ).s
	end
	local from, to = B.START_CLEAR, finishS - B.FINISH_CLEAR
	if to <= from then return {} end
	local keep = HazardPlan.keepClear(geo, track)
	-- nor under a checkpoint gate (Studio record-sky 2026-11-12: a row in
	-- CP1's gate, boxes and gate beams in one heap)
	for _, c in ipairs(track.checkpoints or {}) do
		table.insert(keep, geo:project(c[1], c[2], nil, nil, c[3]).s)
	end
	local float = B.FLOAT[biome] or 3
	local half = geo.halfWidth
	local out = {}
	local bin = (to - from) / B.ROWS
	for r = 1, B.ROWS do
		local a = from + (r - 1) * bin
		for _ = 1, 12 do
			local s = a + bin * (0.1 + 0.8 * rnd())
			if clear(s, keep, B.KEEP_CLEAR) then
				local row = { s = s, boxes = {} }
				local y = geo:heightAt(s) + float
				-- evenly across the lane, the whole row shifted a little
				local span = half * B.LATERAL
				local shift = (rnd() - 0.5) * half * 0.2
				for k = 1, B.PER_ROW do
					local t = B.PER_ROW > 1 and (k - 1) / (B.PER_ROW - 1) or 0.5
					local lateral = -span + 2 * span * t + shift
					local x, z = geo:offsetPoint(s, lateral)
					table.insert(row.boxes, { x = x, y = y, z = z, lateral = lateral })
				end
				table.insert(out, row)
				break
			end
		end
	end
	return out
end

--- The odds table for a racer with `ahead` (0 = leader … 1 = last) of the
-- field in front.
function BoxPlan.oddsFor(ahead)
	local odds = Constants.MYSTERY_BOX.ODDS
	for _, o in ipairs(odds) do
		if ahead <= o[1] + 1e-9 then return o[2] end
	end
	return odds[#odds][2]
end

--- Share of the field ahead of a racer at `rank` of `n` (0 … 1).
function BoxPlan.ahead(rank, n)
	if not rank or not n or n <= 1 then return 0.5 end
	return math.clamp((rank - 1) / (n - 1), 0, 1)
end

--- A power drawn for a racer with `ahead` of the field in front.
function BoxPlan.power(ahead, rnd)
	local w = BoxPlan.oddsFor(ahead)
	local keys = {}
	local total = 0
	for k, v in pairs(w) do
		table.insert(keys, k)
		total += v
	end
	table.sort(keys)   -- the same draw for the same rnd
	local x = rnd() * total
	for _, k in ipairs(keys) do
		x -= w[k]
		if x < 0 then return k end
	end
	return keys[#keys]
end

return BoxPlan
