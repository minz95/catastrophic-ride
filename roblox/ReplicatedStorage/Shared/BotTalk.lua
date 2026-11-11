-- BotTalk.lua
-- What farm bots say (FarmBots → FarmAction "say" → a chat bubble over the
-- bot, FarmFx). Short lines, one per moment; Constants.BOTS.FARM.TALK keeps
-- them rare enough not to crowd the screen (playtest 2026-11-12: "bots
-- should talk: 'give it!'"; "not as big as the effect popups"). Pure.

local BotTalk = {}

BotTalk.LINES = {
	rare_chase = { "Gimme that!", "Hand it over!", "That's MINE!", "Ooh, I want that!", "Shiny! Give!" },
	steal      = { "Nice bag you got...", "Don't mind me!", "Sharing is caring!", "Just borrowing!" },
	stolen     = { "Mine now!", "Thanks, sucker!", "Yoink!", "Finders keepers!" },
	defended   = { "Aw, come on!", "So greedy!", "Fine, keep it!" },
	robbed     = { "HEY! Give it back!", "THIEF!", "That was mine!", "You'll pay for that!" },
	hit        = { "Ow!", "Rude!", "Hey, watch it!", "Oh, it's ON!" },
	rare_got   = { "Ooh, shiny!", "JACKPOT!", "Look what I found!" },
	idle       = { "Junk! Glorious junk!", "Where's the good stuff?", "My ride's gonna be epic", "Who took my cart?" },
}

--- A line for `event` ("robbed", "hit", ...), or nil. `rand(n)` → 1..n.
function BotTalk.line(event, rand)
	local list = BotTalk.LINES[event]
	if not list or #list == 0 then return nil end
	return list[(rand or math.random)(#list)]
end

--- May bot `state` ({ nextTalk }) speak at `now`, with `gate` ({ nextAny })
-- shared by all bots? Marks the time when it may.
function BotTalk.may(state, gate, now, talk)
	if now < (state.nextTalk or 0) or now < (gate.nextAny or 0) then return false end
	state.nextTalk = now + talk.GAP
	gate.nextAny = now + talk.ANY_GAP
	return true
end

return BotTalk
