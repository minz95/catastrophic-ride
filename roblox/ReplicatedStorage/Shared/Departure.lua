-- Departure.lua
-- Start pads in the hub place (Shared/Places "hub"): whoever stands on a
-- pad leaves together for the race place, Constants.DEPART.SECONDS after the
-- first stepped on; a pad that empties stops its clock. A "public" pad
-- joins a race server with room (Roblox keeps the group in one server), a
-- "private" pad opens a new server for just that group (and bots).
-- Pure rules: DepartureManager feeds who is on each pad, LobbyHub builds the
-- pads at LobbyLayout.SHOWCASE (the hub has no junk ride show).

local Departure = {}

Departure.PADS = {
	{ id = "race",   kind = "public",  title = "🏁 RACE",         sub = "join a race now" },
	{ id = "party1", kind = "private", title = "👥 PRIVATE RACE", sub = "just who's on the pad" },
	{ id = "party2", kind = "private", title = "👥 PRIVATE RACE", sub = "just who's on the pad" },
}

-- The series' next games (2026-11-18: Junk Town is the hub of the
-- Catastrophic series): pads that say "coming soon" and send nobody yet.
-- A game that opens becomes a PADS entry (its own place in Shared/Places).
Departure.SOON = {
	{ id = "day",     title = "CATASTROPHIC DAY",     sub = "coming soon" },
	{ id = "kitchen", title = "CATASTROPHIC KITCHEN", sub = "coming soon" },
}

function Departure.pad(id)
	for _, p in ipairs(Departure.PADS) do
		if p.id == id then return p end
	end
	return nil
end

function Departure.new()
	return { since = {} }
end

--- One check. `onPad[padId]` = user ids standing on it now (players
-- already sent are left out by the caller). Returns the groups that leave
-- now ({ pad, kind, ids }) and what each pad shows
-- ({ [padId] = { count, leavesAt } }).
function Departure.step(state, onPad, now, seconds, max)
	local leaving, view = {}, {}
	for _, p in ipairs(Departure.PADS) do
		local ids = onPad[p.id] or {}
		if #ids == 0 then
			state.since[p.id] = nil
		else
			state.since[p.id] = state.since[p.id] or now
			if now - state.since[p.id] >= seconds then
				local group = {}
				for i = 1, math.min(#ids, max) do group[i] = ids[i] end
				table.insert(leaving, { pad = p.id, kind = p.kind, ids = group })
				-- those left over (a full group went) start a new clock
				state.since[p.id] = #ids > max and now or nil
				ids = { table.unpack(ids, max + 1) }
			end
		end
		view[p.id] = { count = #ids, leavesAt = state.since[p.id] and (state.since[p.id] + seconds) or nil }
	end
	return leaving, view
end

return Departure
