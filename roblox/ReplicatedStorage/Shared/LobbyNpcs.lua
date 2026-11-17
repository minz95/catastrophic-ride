-- LobbyNpcs.lua
-- The townsfolk of Junk Town (2026-11-17: "if it gets boring, talk to an
-- NPC"). Each stands at a spot (offset from LobbyLayout.ORIGIN), wears a
-- shop hat, and says one of their lines when a player talks to them
-- (prompt "Talk", attribute Talk = id; LobbyHubClient shows the line and a
-- chat bubble over their head). `idle` lines are said now and then to
-- whoever is near. Lines are tips that are true in the game, or jokes.

local LobbyNpcs = {}

local V = Vector3.new

LobbyNpcs.LIST = {
	{
		id = "mayor", name = "Mayor Quackers", title = "Mayor of Junk Town",
		at = V(-10, 0, 9), hat = "hat_top", shirt = Color3.fromRGB(60, 70, 140),
		lines = {
			"Welcome to Junk Town! Everything here was somebody's trash once. Including me.",
			"Here's how it goes: grab junk on the farm, build a ride out of it, then race it.",
			"Your BODY item is what you ride. A toilet? A sofa? Nobody will stop you.",
			"The funniest ride gets voted onto that stage up north. Make them laugh!",
			"Win the vote and your ride goes on sale as a Legend Ride. You keep the original, free.",
			"Bored? Talk to the folks around town. Everyone here has an opinion.",
		},
		idle = { "Lovely day for a race!", "Keep Junk Town junky!" },
	},
	{
		id = "gran", name = "Grease Gran", title = "Mechanic",
		at = V(-36, 0, -8), hat = "hat_viking", shirt = Color3.fromRGB(70, 110, 80),
		lines = {
			"ENGINE items push you, SPECIAL items do tricks. Press E in the race to use them.",
			"A rocket on a toilet? I've seen worse. I've BUILT worse.",
			"These Legend Rides won the vote. Only fifty copies each, then they're gone for good.",
			"Every copy is numbered. Number one of fifty, now that's bragging rights.",
			"Whoever won the vote gets coins every time somebody buys a copy. Smart, eh?",
			"Out of junk? Steal some. I didn't say that. Ask Sam.",
		},
		idle = { "Hand me that wrench!", "Who parked a bathtub here?" },
	},
	{
		id = "penny", name = "Penny", title = "Shopkeeper",
		at = V(-15, 0, 24), hat = "hat_party", shirt = Color3.fromRGB(200, 80, 120),
		lines = {
			"Paints, trails, hats! Looks only, your ride drives the same. Promise.",
			"Win races and come back every day: that's how the coins pile up.",
			"Some hats you can't buy at all. Dr. Plunger keeps them in the trophy room.",
			"The Golden Legend ride glitters. Level 10 though. Keep racing!",
			"Press B any time outside a race to open the shop.",
		},
		idle = { "Fresh paint, get your fresh paint!", "Open for business!" },
	},
	{
		id = "plunger", name = "Dr. Plunger", title = "Keeper of Trophies",
		at = V(44, 0, -16), hat = "hat_propeller", shirt = Color3.fromRGB(240, 240, 245),
		lines = {
			"Every trophy here is earned, never sold. That's what makes them shine.",
			"Win a race riding a toilet and the Golden Plunger is yours. Royal Flush!",
			"Win in the Forest, at Sea AND in the Sky for the World Tour Medal.",
			"Some of these come as real avatar items too. Wear them in any game.",
			"Finish ten races and you'll ride with your hands up. Wheee!",
		},
		idle = { "Don't touch the trophies. Okay, look, but don't touch.", "Polishing, polishing..." },
	},
	{
		id = "tom", name = "Turbo Tom", title = "Racer",
		at = V(28, 0, -8), hat = "hat_cat", shirt = Color3.fromRGB(230, 120, 40),
		lines = {
			"Drift through the corners. Slide long enough and you get a turbo.",
			"Press F to boost when the bar is full. Save it for a straight!",
			"Hit the ? boxes on the track for a power. Rockets are my favourite.",
			"Fell off? You'll be put back on the road. No shame. Okay, a little shame.",
			"In the Sky you fly. Ride the updrafts up and over!",
			"Too easy~",
		},
		idle = { "Vroom vroom!", "Anyone want a race? Oh wait, everyone does." },
	},
	{
		id = "sam", name = "Sticky Sam", title = "Totally Not a Thief",
		at = V(-50, 0, 40), hat = "hat_top", shirt = Color3.fromRGB(40, 40, 50),
		lines = {
			"Hold E next to someone on the farm to steal from their bag. You didn't hear it from me.",
			"Someone stealing from you? Tap the key on screen fast to keep your stuff.",
			"Punch with F. Hold G to guard. A good guard beats a bad thief.",
			"Steal twenty items and the Bandit Mask is yours. I have three.",
			"Rare loot glows over your head. Everyone can see it. Everyone.",
		},
		idle = { "Psst.", "Nice shoes. Shame if someone... never mind." },
	},
}

local _byId = {}
for _, n in ipairs(LobbyNpcs.LIST) do _byId[n.id] = n end

function LobbyNpcs.get(id)
	return _byId[id]
end

--- The next line to say: never the same one twice in a row.
function LobbyNpcs.pick(npc, last, rand)
	local lines = npc.lines
	if #lines == 1 then return 1 end
	local i
	repeat i = rand(1, #lines) until i ~= last
	return i
end

return LobbyNpcs
