-- GpTiming.lua
-- Lap and sector times at the Junk Grand Prix, F1 style. Pure: fed the
-- car's lap share (GpLayout.where) and the time, it reports the line and
-- sector crossings. The server keeps one per car (GpManager); clients only
-- show what it sends.
--
--   local t = GpTiming.new(now)
--   for each sample: local events = GpTiming.feed(t, share, lateral, now, inPit)
--   events: { kind = "lap", lap, time, valid, sectors = { s1, s2, s3 } }
--           { kind = "sector", index, time }
--           { kind = "limits" }            -- the lap was spoiled (once a lap)
--           { kind = "start" }             -- the first crossing: timing begins
--
-- Rules
--   * A lap is timed line to line; the first crossing starts lap 1 (the out
--     lap before it is not timed).
--   * A lap counts only when its sectors were passed in order (no short
--     cuts across the infield) and it took at least MIN_SHARE of the lap at
--     the best car's top speed.
--   * Going past Constants.GP.TRACK_LIMIT sideways (not in the pit lane)
--     spoils the lap: it is shown but never a best.
-- Colours (F1): "purple" = the best anyone set this session, "green" = your
-- own best, "yellow" = slower.

local Constants = require(script.Parent.Constants)
local GpLayout = require(script.Parent.GpLayout)

local GpTiming = {}

GpTiming.MIN_SHARE = 0.9   -- of the time the fastest possible car needs

function GpTiming.new(now)
	return {
		lap = 0, started = false, lapStart = now, sector = 0, sectorStart = now, split = {},
		valid = true, lastShare = nil, best = nil, bestSectors = {}, laps = {},
	}
end

--- The least time a lap may take (studs / the fastest top speed).
function GpTiming.minLap()
	return GpTiming.MIN_SHARE * GpLayout.lapLength() / Constants.GP.TOP[2]
end

--- Feeds one sample. Returns a list of events (often empty).
function GpTiming.feed(t, share, lateral, now, inPit)
	local out = {}
	local last = t.lastShare
	t.lastShare = share
	if last == nil then return out end
	-- track limits
	if t.started and t.valid and not inPit and math.abs(lateral or 0) > Constants.GP.TRACK_LIMIT then
		t.valid = false
		table.insert(out, { kind = "limits" })
	end
	-- the line: from the end of the lap to its start
	local crossed = last > 0.8 and share < 0.2
	local backwards = last < 0.2 and share > 0.8
	if backwards then
		t.sector = -1   -- reversed over the line: this lap cannot count
		return out
	end
	-- sectors: crossing a sector line forwards
	if t.started and t.sector >= 0 then
		local nextLine = GpLayout.SECTORS[t.sector + 1]
		if nextLine and last < nextLine and share >= nextLine and share - last < 0.2 then
			t.sector += 1
			local time = now - t.sectorStart
			t.split[t.sector] = time
			t.sectorStart = now
			table.insert(out, { kind = "sector", index = t.sector, time = time })
		end
	end
	if crossed then
		if t.started then
			local time = now - t.lapStart
			local inOrder = t.sector == #GpLayout.SECTORS
			local ok = inOrder and time >= GpTiming.minLap()
			local s3 = now - t.sectorStart
			local sectors = { t.split[1], t.split[2], s3 }
			t.lap += 1
			local valid = ok and t.valid
			local lap = { lap = t.lap, time = time, valid = valid, counted = ok, sectors = sectors }
			table.insert(t.laps, lap)
			if valid and (not t.best or time < t.best) then t.best = time end
			if ok then
				for i, s in ipairs(sectors) do
					if t.valid and s and (not t.bestSectors[i] or s < t.bestSectors[i]) then t.bestSectors[i] = s end
				end
			end
			table.insert(out, { kind = "lap", lap = t.lap, time = time, valid = valid, counted = ok, sectors = sectors })
		else
			t.started = true
			table.insert(out, { kind = "start" })
		end
		t.lapStart, t.sectorStart, t.sector, t.split, t.valid = now, now, 0, {}, true
	end
	return out
end

--- The colour of time `time` against your own best `mine` and the
-- session's best `all` (both may be nil).
function GpTiming.colour(time, mine, all)
	if all == nil or time <= all + 1e-6 then return "purple" end
	if mine == nil or time <= mine + 1e-6 then return "green" end
	return "yellow"
end

--- "1:02.345" / "42.345".
function GpTiming.format(seconds)
	if not seconds then return "--.---" end
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	if m > 0 then return string.format("%d:%06.3f", m, s) end
	return string.format("%.3f", s)
end

--- The session board: best laps, fastest first, one line per driver.
-- board: { [key] = { name, time, car, bot } }; returns the first `n`.
function GpTiming.ranked(board, n)
	local list = {}
	for key, e in pairs(board) do
		table.insert(list, { key = key, name = e.name, time = e.time, car = e.car, bot = e.bot })
	end
	table.sort(list, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		return tostring(a.key) < tostring(b.key)
	end)
	local out = {}
	for i = 1, math.min(n or #list, #list) do out[i] = list[i] end
	return out
end

return GpTiming
