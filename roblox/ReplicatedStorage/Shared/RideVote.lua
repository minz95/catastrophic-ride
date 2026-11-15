-- RideVote.lua
-- The ride show's vote (RESULTS, Modules/RideShowManager): every player
-- votes for the funniest ride but their own; the most votes win (ties all
-- win, no votes no winner). Pure: the spec checks it.

local RideVote = {}

--- A vote by `voter` for `target`; `entries` = { [userId] = true } of the
-- rides on show. Returns "ok" or why not. `votes` = { [voter] = target }.
function RideVote.cast(votes, entries, voter, target)
	if type(target) ~= "number" or not entries[target] then return "no such ride" end
	if voter == target then return "own ride" end
	if votes[voter] == target then return "same" end
	votes[voter] = target
	return "ok"
end

--- { [userId] = number of votes }.
function RideVote.counts(votes)
	local out = {}
	for _, target in pairs(votes) do out[target] = (out[target] or 0) + 1 end
	return out
end

--- The ride(s) with the most votes (at least one), sorted by id.
function RideVote.winners(votes)
	local best, out = 0, {}
	for id, n in pairs(RideVote.counts(votes)) do
		if n > best then best, out = n, { id } elseif n == best then table.insert(out, id) end
	end
	table.sort(out)
	return out, best
end

return RideVote
