--!nocheck
-- tools/soak.luau — one server, many rounds, every server script: random
-- biome and weather each round, bots filling the grid, players driving the
-- track (checkpoints and finish by hand, a boost each race), a friend
-- joining through an invite, and the UTC day turning over halfway. Checks
-- after every round what the new features must keep true:
--   weather   Lighting = preset + weather; haze / clouds only while a
--             weather wants them; storm hazards only in storms
--   coins     every coin a player has is accounted for (rewards, daily
--             challenges, invite bonus)
--   challenges progress ≤ goal, done ⇔ progress = goal, paid once
--   health    no script errors, no phase errors, no warnings
--   lune run tools/soak.luau [rounds=12] [players=3] [seed=1]
local process = require("@lune/process")
local Server = require("../tests/lib/server")
local Vector3 = require("@lune/roblox").Vector3

local ROUNDS = tonumber(process.args[1]) or 12
local PLAYERS = tonumber(process.args[2]) or 3
local SEED = tonumber(process.args[3]) or 1
math.randomseed(SEED)

local SCRIPTS = {
	"ServerScriptService.MapBuilders.ForestMapBuilder",
	"ServerScriptService.MapBuilders.OceanMapBuilder",
	"ServerScriptService.MapBuilders.SkyMapBuilder",
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.ItemModelPreloader",
	"ServerScriptService.CharacterManager",
	"ServerScriptService.FarmingManager",
	"ServerScriptService.CraftingManager",
	"ServerScriptService.RacingManager",
	"ServerScriptService.AbilityManager",
	"ServerScriptService.HazardManager",
	"ServerScriptService.ProgressionManager",
	"ServerScriptService.ShopManager",
	"ServerScriptService.AnalyticsManager",
	"ServerScriptService.BadgeManager",
	"ServerScriptService.InviteManager",
	"ServerScriptService.ChallengeManager",
}

local day = 20759
local srv = Server.boot({
	players = PLAYERS,
	scripts = SCRIPTS,
	quiet = true,
	harness = { harness = "lune", players = PLAYERS, lobbyDelay = 0, fillBots = true, weather = "random",
		durations = { FARMING = 8, CRAFTING = 2, RACING = 150, RESULTS = 3 } },
	setup = function(e)
		-- the day is ours to turn over
		local P = e.requirePath("ReplicatedStorage.Shared.Progression")
		P.dayOf = function() return day end
		local Ref = e.requirePath("ServerScriptService.Modules.Referral")
		Ref.referrerOf = function(p) return p.UserId == 5001 and 1001 or nil end
	end,
})
local e = srv.env
local W = e.requirePath("ReplicatedStorage.Shared.Weather")
local DC = e.requirePath("ReplicatedStorage.Shared.DailyChallenge")
local Presets = e.requirePath("ServerScriptService.Modules.LightingPresets")
local PlayerStore = e.requirePath("ServerScriptService.Modules.PlayerStore")
local C = e.requirePath("ReplicatedStorage.Shared.Constants")
local RE = e.requirePath("ReplicatedStorage.RemoteEvents")
local Lighting = e.game:GetService("Lighting")
local terrain = e.workspace:FindFirstChildOfClass("Terrain")

local problems = {}
local function bad(round, msg)
	table.insert(problems, string.format("round %d: %s", round, msg))
end

local function waitPhase(phase, limit)
	local t = 0
	while srv.GameManager.getPhase() ~= phase and t < (limit or 60) do
		srv.advance(0.25); t += 0.25
	end
	return srv.GameManager.getPhase() == phase
end

local function close(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-4 end
	if typeof and typeof(a) == "Color3" then
		return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
	end
	return a == b
end

local seenWeather = {}
local startCoins = {}
for _, p in ipairs(srv.players) do
	srv.advance(0.1)
	local rec = PlayerStore.get(p)
	startCoins[p.UserId] = rec and rec.coins or 0
end

local friend = nil
for r = 1, ROUNDS do
	if not waitPhase("FARMING", 60) then bad(r, "no FARMING (phase " .. tostring(srv.GameManager.getPhase()) .. ")") break end
	srv.advance(0.5)
	local biome, weather = srv.GameManager.getBiome(), srv.GameManager.getWeather()
	seenWeather[biome .. "/" .. weather] = (seenWeather[biome .. "/" .. weather] or 0) + 1
	if e.game.ReplicatedStorage:GetAttribute("Weather") ~= weather then bad(r, "Weather attribute out of step") end
	-- lighting
	local want = W.lighting(Presets[biome], biome, weather)
	for prop, v in pairs(want) do
		if not close(Lighting[prop], v) then bad(r, ("%s/%s Lighting.%s = %s, want %s"):format(biome, weather, prop, tostring(Lighting[prop]), tostring(v))) end
	end
	local look = W.look(biome, weather)
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if (air ~= nil) ~= (look ~= nil and look.atmosphere ~= nil) then bad(r, biome .. "/" .. weather .. ": Atmosphere " .. tostring(air ~= nil)) end
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if terrain and (clouds ~= nil) ~= (look ~= nil and look.clouds ~= nil) then bad(r, biome .. "/" .. weather .. ": Clouds " .. tostring(clouds ~= nil)) end
	if biome == "OCEAN" and terrain then
		local wl = look and look.water and look.water.WaterWaveSize or 0.15
		if not close(terrain.WaterWaveSize, wl) then bad(r, "WaterWaveSize " .. tostring(terrain.WaterWaveSize)) end
	end
	-- a friend arrives through an invite in round 2
	if r == 2 then
		friend = srv.mock.addPlayer("Friend", 5001, Vector3.new(0, 3, 850))
		srv.advance(1)
	end
	-- the day turns over halfway
	if r == math.floor(ROUNDS / 2) + 1 then day += 1 end

	if not waitPhase("RACING", 60) then bad(r, "no RACING") break end
	local hz0 = #srv.Telemetry.events("hazard")
	srv.advance(C.RACE_COUNTDOWN + 0.5)
	local racers = table.clone(srv.players)
	if friend then table.insert(racers, friend) end
	for _, p in ipairs(racers) do srv.mock.invoke(RE.RequestBoost, p) end
	srv.advance(14)   -- hazards run a while
	local mapName = biome:sub(1, 1) .. biome:sub(2):lower() .. "Map"
	local order = {}
	for _, p in ipairs(racers) do table.insert(order, p) end
	for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
	for _, p in ipairs(order) do
		local d = srv.SessionManager.getData(p)
		local car = d and d.vehicleModel
		if car and car.PrimaryPart then
			for _, tag in ipairs({ "Checkpoint1", "Checkpoint2", "FinishLine" }) do
				for _, part in ipairs(srv.mock.CollectionService:GetTagged(tag)) do
					if part:IsDescendantOf(e.workspace.Maps:FindFirstChild(mapName)) then part.Touched:Fire(car.PrimaryPart) end
				end
				srv.advance(0.05)
			end
		else
			bad(r, p.Name .. " has no car")
		end
	end
	local gusts = 0
	local hz = srv.Telemetry.events("hazard")
	for i = hz0 + 1, #hz do if hz[i].type == "gustZone" then gusts += 1 end end
	local wantGust = biome == "SKY" or (biome == "OCEAN" and weather == "storm")
	if wantGust ~= (gusts > 0) then bad(r, ("%s/%s: %d gusts"):format(biome, weather, gusts)) end
	if not waitPhase("RESULTS", 200) then bad(r, "no RESULTS") end
	srv.advance(1)
	-- challenge state
	for _, p in ipairs(racers) do
		local rec = PlayerStore.get(p)
		local s = rec and rec.challenges
		if s then
			for _, key in ipairs(DC.forDay(s.day)) do
				local c = DC.get(key)
				local n = s.progress[key] or 0
				if n > c.goal then bad(r, p.Name .. " " .. key .. " progress " .. n .. " > goal") end
				if (s.done[key] == true) ~= (n >= c.goal) then bad(r, p.Name .. " " .. key .. " done/progress disagree") end
			end
			if s.day ~= day then bad(r, p.Name .. " challenges for day " .. tostring(s.day) .. ", today " .. day) end
		end
	end
end

-- coins: start + rewards + challenges + invite bonus
local function sum(kind, field, uid, key)
	local t = 0
	for _, ev in ipairs(srv.Telemetry.events(kind)) do
		if ev[key or "userId"] == uid then t += (ev[field] or 0) end
	end
	return t
end
local everyone = table.clone(srv.players)
if friend then table.insert(everyone, friend) end
for _, p in ipairs(everyone) do
	local rec = PlayerStore.get(p)
	local uid = p.UserId
	local expect = (startCoins[uid] or 0) + sum("reward", "coins", uid) + sum("reward", "daily", uid)
		+ sum("challenge", "coins", uid) + sum("referral", "coins", uid)
	if not rec then
		table.insert(problems, p.Name .. ": no record")
	elseif rec.coins ~= expect then
		table.insert(problems, ("%s: %d coins, accounted for %d"):format(p.Name, rec.coins, expect))
	end
end

for _, er in ipairs(srv.mock.errors) do table.insert(problems, "error: " .. tostring(er)) end
for _, w in ipairs(srv.mock.warnings or {}) do table.insert(problems, "warn: " .. w) end
for _, ev in ipairs(srv.Telemetry.events("phase_error")) do table.insert(problems, "phase_error: " .. tostring(ev.error)) end

local seen = {}
for k, n in pairs(seenWeather) do table.insert(seen, k .. "×" .. n) end
table.sort(seen)
print(("soak: %d rounds, %d players + friend, seed %d"):format(ROUNDS, PLAYERS, SEED))
print("weathers: " .. table.concat(seen, ", "))
print(("challenges paid: %d, referrals: %d, finishes: %d"):format(#srv.Telemetry.events("challenge"),
	#srv.Telemetry.events("referral"), #srv.Telemetry.events("finish")))
do
	-- item boxes: laid out every race, taken and used by players and bots
	local picks, botPicks, uses, ok = 0, 0, 0, 0
	for _, ev in ipairs(srv.Telemetry.events("box_pick")) do
		picks += 1
		if ev.bot then botPicks += 1 end
	end
	for _, ev in ipairs(srv.Telemetry.events("box_use")) do
		uses += 1
		if ev.result == "ok" then ok += 1 end
	end
	print(("item boxes: %d races laid out, %d taken (%d by bots), %d used (%d ok)"):format(
		#srv.Telemetry.events("box_rows"), picks, botPicks, uses, ok))
	if #srv.Telemetry.events("box_rows") == 0 then table.insert(problems, "no item boxes laid out") end
end
if #problems == 0 then
	print("OK: no problems")
else
	print(#problems .. " problems:")
	local shown = {}
	for _, p in ipairs(problems) do
		if not shown[p] and #shown < 40 then shown[p] = true; table.insert(shown, p); print("  " .. p) end
	end
	process.exit(1)
end
