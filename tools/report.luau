--!nocheck
-- tools/report.luau — track + balance report for every biome.
--
--   lune run tools/report.luau            # all biomes, 12 simulated matches each
--   lune run tools/report.luau 40         # more matches for steadier numbers
--   lune run tools/report.luau 12 OCEAN   # one biome
--
-- Writes reports/<biome>/ (forest, ocean, sky):
--   track.svg    top-down map: corridor, walls, blocking parts, triggers,
--                respawn targets and simulated driving lines
--   summary.md   findings + race and match statistics
--   summary.json the same numbers for tools / AI to read
--
-- Run from the repository root.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local World = require("../tests/lib/world")
local MapQuery = require("../tests/lib/mapquery")
local KineSim = require("../tests/lib/kinesim")
local Builds = require("../tests/lib/builds")
local MatchSim = require("../tests/lib/matchsim")

local MATCHES = tonumber(process.args[1]) or 12
local ONLY = process.args[2]

-- Per-biome drawing and naming. isWall: the side walls; props: decoration
-- that must stay off the lane (drawn as red dots when it does not).
local BIOMES = {
	FOREST = {
		isWall = function(n) return n == "TrackWall" end, wallLabel = "walls (8-stud doorways)",
		props = { "Trunk" }, propLabel = "tree trunk inside the lane",
		ground = "#5d8a3c", lane = "#4a4540", wall = "#2b1d10", slow = "#6b4f2e",
	},
	OCEAN = {
		isWall = function(n) return n == "ReefWall" end, wallLabel = "reef walls (8-stud doorways)",
		props = { "^PalmTrunk$", "^ReefSpire_%d+$" }, propLabel = "palm or reef spire inside the lane",
		ground = "#1e5aa8", lane = "#3d8fd6", wall = "#5f4b37", slow = "#bfe6ff",
	},
	SKY = {
		isWall = function(n) return n:sub(1, 11) == "EdgePillar_" end, wallLabel = "crystal pillar fence (no doorways)",
		props = { "^CrystalSpire_" }, propLabel = "crystal spire inside the lane",
		ground = "#8ca5dc", lane = "#a693d6", wall = "#5b2fbf", slow = "#ffffff",
	},
}

local function report(biome)
local cfg = BIOMES[biome]
local OUT = "reports/" .. string.lower(biome)
fs.writeDir(OUT)

local intended = World.build(biome, { visibility = "intended" })
local shipped = World.build(biome, { visibility = "shipped" })
local geo, track = intended.geo, intended.track
local env = intended.env
local Autopilot = env.requirePath("ReplicatedStorage.Shared.Autopilot")
local RaceProgress = env.requirePath("ReplicatedStorage.Shared.RaceProgress")
local BiomeConfig = env.requirePath("ServerScriptService.Modules.BiomeConfig")
local HALF = track.width / 2
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

local function fmt(n, d) return string.format("%." .. (d or 1) .. "f", n) end

-- ─── Race runs (single car, no opponents) ──────────────────────────────────────
local reps = Builds.representative(Builds.enumerate(env, biome))
local raceRuns = {}
for _, rep in ipairs(reps) do
	local car = KineSim.carFromStats(rep.build.stats, Constants, biome)
	for _, profile in ipairs({ "expert", "average", "novice" }) do
		for _, world in ipairs({ intended, shipped }) do
			local r = KineSim.run(world, {
				car = car, profile = Autopilot.PROFILES[profile], profileName = profile,
				seed = 1, respawn = world == intended and "track" or "legacy",
			})
			r.carLabel = rep.label
			r.carDesc = Builds.describe(rep.build)
			r.world = world == intended and "authored" or "live code"
			table.insert(raceRuns, r)
		end
	end
end

-- ─── Matches (farm → craft → race) ─────────────────────────────────────────────
local matches = {}
for seed = 1, MATCHES do
	table.insert(matches, MatchSim.run({ players = 6, seed = seed, world = intended, biome = biome }))
end

-- ─── Geometry findings ─────────────────────────────────────────────────────────
local findings = { solid = {}, trees = {}, intrusions = {}, respawnOff = {}, cps = {} }
local intendedSolid = {}
for _, sh in ipairs(intended.obstacles) do intendedSolid[sh.name .. sh.cx .. sh.cz] = true end
for _, sh in ipairs(shipped.obstacles) do
	if not intendedSolid[sh.name .. sh.cx .. sh.cz] then
		local p = geo:project(sh.cx, sh.cz)
		if p.dist < HALF + 4 then
			table.insert(findings.solid, sh)
		end
	end
end
for _, sh in ipairs(intended.allShapes) do
	for _, pat in ipairs(cfg.props) do
		if sh.name:find(pat) then
			local p = geo:project(sh.cx, sh.cz)
			if p.dist < HALF + 2 then table.insert(findings.trees, sh) end
		end
	end
end
local worst = {}
for s = 0, geo.length, 2 do
	for lat = -(HALF - 6), HALF - 6, 2 do
		local x, z = geo:offsetPoint(s, lat)
		for _, ob in ipairs(intended.obstacleGrid.near(x, z, 1)) do
			if cfg.isWall(ob.name) and MapQuery.contains(ob, x, z) then
				local key = math.floor(s / 40)
				if not worst[key] then worst[key] = { x = x, z = z, s = s } end
			end
		end
	end
end
for _, w in pairs(worst) do table.insert(findings.intrusions, w) end
for s = 0, geo.length, 50 do
	local x, z = geo:pointAt(s)
	local rx, _, rz = RaceProgress.respawnPoint(biome, x, z, BiomeConfig[biome].raceStartY)
	local p = geo:project(rx, rz)
	if p.dist > HALF - 2 then
		table.insert(findings.respawnOff, { s = s, x = x, z = z, rx = rx, rz = rz })
	end
end

-- ─── SVG ───────────────────────────────────────────────────────────────────────
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, n in ipairs(track.nodes) do
	minX = math.min(minX, n[1]); maxX = math.max(maxX, n[1])
	minZ = math.min(minZ, n[2]); maxZ = math.max(maxZ, n[2])
end
local PAD = 80
minX -= PAD; maxX += PAD; minZ -= PAD; maxZ += PAD
local LEGEND_W = 330
local W = (maxX - minX) + LEGEND_W
local H = (maxZ - minZ)
local function X(x) return fmt(x - minX, 1) end
local function Y(z) return fmt(z - minZ, 1) end   -- -Z (race direction) is up

local svg = {}
local function add(s) table.insert(svg, s) end
local function poly(points, attrs)
	local pts = {}
	for _, p in ipairs(points) do table.insert(pts, X(p[1]) .. "," .. Y(p[2])) end
	add(string.format('<polygon points="%s" %s/>', table.concat(pts, " "), attrs))
end
local function shapePoly(sh, attrs) poly(MapQuery.corners(sh), attrs) end
local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

add(string.format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" font-family="Helvetica, Arial, sans-serif">', W, H, W, H))
add(string.format('<rect x="0" y="0" width="%d" height="%d" fill="%s"/>', W, H, cfg.ground))

-- Corridor (one rectangle per segment, exactly like the builder)
for _, seg in ipairs(geo.segments) do
	local rx, rz = -seg.dz * HALF, seg.dx * HALF
	poly({ { seg.ax + rx, seg.az + rz }, { seg.bx + rx, seg.bz + rz }, { seg.bx - rx, seg.bz - rz }, { seg.ax - rx, seg.az - rz } }, 'fill="' .. cfg.lane .. '"')
end
-- Round lane joints at the nodes (the outside of each turn)
for i = 2, #track.nodes - 1 do
	local n = track.nodes[i]
	add(string.format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', X(n[1]), Y(n[2]), fmt(HALF), cfg.lane))
end
-- Slow zones (outside walls)
for _, sh in ipairs(intended.allShapes) do
	if table.find(sh.tags, "SlowZone") then shapePoly(sh, 'fill="' .. cfg.slow .. '" fill-opacity="0.25"') end
end
-- Walls
for _, sh in ipairs(intended.obstacles) do
	if cfg.isWall(sh.name) then shapePoly(sh, 'fill="' .. cfg.wall .. '"') end
end
-- Triggers
for _, sh in ipairs(intended.allShapes) do
	local tags = sh.tags
	if table.find(tags, "BoostPad") then shapePoly(sh, 'fill="#ffd23c"') end
	if table.find(tags, "MudZone") then shapePoly(sh, 'fill="#7a4f1e"') end
	if table.find(tags, "DriftCorner") then shapePoly(sh, 'fill="none" stroke="#ff9f1c" stroke-width="2" stroke-dasharray="6 4"') end
	if table.find(tags, "Checkpoint1") or table.find(tags, "Checkpoint2") then shapePoly(sh, 'fill="#4cc9f0" fill-opacity="0.85"') end
	if table.find(tags, "FinishLine") then shapePoly(sh, 'fill="#ffffff"') end
	if table.find(tags, "JumpZone") then shapePoly(sh, 'fill="#c8a26b" fill-opacity="0.8" stroke="#000" stroke-width="0.5"') end
	if table.find(tags, "UpdraftZone") then shapePoly(sh, 'fill="#73c8ff" fill-opacity="0.6"') end
end
-- Parts that are solid only because of the CanCollide restore bug
for _, sh in ipairs(findings.solid) do
	shapePoly(sh, 'fill="#e63946" fill-opacity="0.55" stroke="#e63946" stroke-width="1.5"')
end
for _, sh in ipairs(findings.trees) do
	add(string.format('<circle cx="%s" cy="%s" r="5" fill="#e63946" stroke="#fff" stroke-width="1.5"/>', X(sh.cx), Y(sh.cz)))
end
-- Wall intrusions into the lane
for _, w in ipairs(findings.intrusions) do
	add(string.format('<circle cx="%s" cy="%s" r="16" fill="none" stroke="#ff006e" stroke-width="3"/>', X(w.x), Y(w.z)))
end
-- Respawn targets that land off the track
for _, r in ipairs(findings.respawnOff) do
	add(string.format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="#ffb3c1" stroke-width="1" stroke-dasharray="3 3"/>', X(r.x), Y(r.z), X(r.rx), Y(r.rz)))
	add(string.format('<path d="M %s %s m -4 -4 l 8 8 m 0 -8 l -8 8" stroke="#ff006e" stroke-width="2"/>', X(r.rx), Y(r.rz)))
end
-- Simulated driving lines (authored map, median car)
local LINE_COLORS = { expert = "#00f5d4", average = "#fee440", novice = "#f15bb5" }
for _, r in ipairs(raceRuns) do
	if r.world == "authored" and r.carLabel == "p50" then
		local pts = {}
		for _, smp in ipairs(r.samples) do table.insert(pts, X(smp.x) .. "," .. Y(smp.z)) end
		add(string.format('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.6" stroke-opacity="0.9"/>', table.concat(pts, " "), LINE_COLORS[r.profile]))
		for _, rs in ipairs(r.respawns) do
			add(string.format('<circle cx="%s" cy="%s" r="4" fill="none" stroke="%s" stroke-width="2"/>', X(rs.from.x), Y(rs.from.z), LINE_COLORS[r.profile]))
		end
	end
end
-- Node labels (sharp turns highlighted)
local defl = {}
for _, d in ipairs(geo:deflections()) do defl[d.node] = d.angle end
for i, n in ipairs(track.nodes) do
	local a = defl[i]
	local sharp = a and math.abs(a) >= 40
	add(string.format('<circle cx="%s" cy="%s" r="2.5" fill="%s"/>', X(n[1]), Y(n[2]), sharp and "#ff006e" or "#ddd"))
	add(string.format('<text x="%s" y="%s" font-size="%d" fill="%s" stroke="#000" stroke-width="0.4">N%d%s</text>',
		fmt(n[1] - minX + 6), fmt(n[2] - minZ - 6), sharp and 15 or 11, sharp and "#ff8fab" or "#f1f1f1", i,
		sharp and string.format(" %+.0f°", a) or ""))
end
add(string.format('<text x="%s" y="%s" font-size="14" fill="#fff">START ↑</text>', X(8), Y(track.nodes[1][2] + 30)))

-- Legend
local lx = maxX - minX + 20
local ly = 30
add(string.format('<rect x="%d" y="0" width="%d" height="%d" fill="#1b1b1b"/>', lx - 20, LEGEND_W, H))
add(string.format('<text x="%d" y="%d" font-size="22" fill="#fff" font-weight="bold">%s track report</text>', lx, ly, biome))
ly += 26
add(string.format('<text x="%d" y="%d" font-size="12" fill="#bbb">Top-down; race runs bottom → top. 1 px = 1 stud.</text>', lx, ly))
ly += 30
local legend = {
	{ "rect", cfg.lane, string.format("corridor (%d studs)", track.width) },
	{ "rect", cfg.wall, cfg.wallLabel },
	{ "rect", "#e63946", "solid during RACING but not in the authored map (should be none)" },
	{ "dot", "#e63946", cfg.propLabel },
	{ "ring", "#ff006e", "wall cuts into the lane (> 6 studs)" },
	{ "x", "#ff006e", "respawn target that lands off the track" },
	{ "rect", "#4cc9f0", "checkpoint trigger (actual footprint)" },
	{ "rect", "#ffd23c", "boost pad" },
	{ "rect", "#7a4f1e", "mud" },
	{ "dash", "#ff9f1c", "drift-corner trigger" },
	{ "rect", "#c8a26b", "jump zone" },
	{ "line", LINE_COLORS.expert, "sim: expert driver (median car)" },
	{ "line", LINE_COLORS.average, "sim: average driver" },
	{ "line", LINE_COLORS.novice, "sim: novice driver" },
	{ "ringsm", "#ffffff", "sim: respawn (stuck)" },
}
for _, e in ipairs(legend) do
	local kind, col, label = e[1], e[2], e[3]
	if kind == "rect" then
		add(string.format('<rect x="%d" y="%d" width="18" height="12" fill="%s"/>', lx, ly - 10, col))
	elseif kind == "dot" then
		add(string.format('<circle cx="%d" cy="%d" r="5" fill="%s" stroke="#fff"/>', lx + 9, ly - 4, col))
	elseif kind == "ring" or kind == "ringsm" then
		add(string.format('<circle cx="%d" cy="%d" r="%d" fill="none" stroke="%s" stroke-width="2"/>', lx + 9, ly - 4, kind == "ring" and 7 or 4, col))
	elseif kind == "x" then
		add(string.format('<path d="M %d %d l 8 8 m 0 -8 l -8 8" stroke="%s" stroke-width="2"/>', lx + 5, ly - 8, col))
	elseif kind == "dash" then
		add(string.format('<rect x="%d" y="%d" width="18" height="12" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>', lx, ly - 10, col))
	elseif kind == "line" then
		add(string.format('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="3"/>', lx, ly - 4, lx + 18, ly - 4, col))
	end
	-- wrap long labels
	local words, line, lines = {}, "", {}
	for w in label:gmatch("%S+") do table.insert(words, w) end
	for _, w in ipairs(words) do
		if #line + #w > 34 then table.insert(lines, line); line = w else line = (line == "" and w) or (line .. " " .. w) end
	end
	table.insert(lines, line)
	for i, l in ipairs(lines) do
		add(string.format('<text x="%d" y="%d" font-size="13" fill="#eee">%s</text>', lx + 28, ly + (i - 1) * 15, esc(l)))
	end
	ly += 10 + #lines * 15
end
ly += 20
add(string.format('<text x="%d" y="%d" font-size="15" fill="#fff" font-weight="bold">Single-car sim (%d s limit)</text>', lx, ly, Constants.RACING_TIMEOUT))
ly += 20
for _, r in ipairs(raceRuns) do
	if r.carLabel == "p50" then
		local status = r.finished and (fmt(r.time) .. " s") or string.format("stuck at %d%%", math.floor(100 * r.maxProgress / r.trackLength))
		add(string.format('<text x="%d" y="%d" font-size="12" fill="#ddd">%s · %s: %s, %d respawns</text>', lx, ly, r.world, r.profile, status, #r.respawns))
		ly += 16
	end
end
add("</svg>")
fs.writeFile(OUT .. "/track.svg", table.concat(svg, "\n"))

-- ─── Match statistics ──────────────────────────────────────────────────────────
local function mean(t)
	if #t == 0 then return 0 end
	local s = 0
	for _, v in ipairs(t) do s += v end
	return s / #t
end
local function spearman(xs, ys)
	local n = #xs
	if n < 3 then return 0 end
	local function rank(v)
		local idx = {}
		for i = 1, n do idx[i] = i end
		table.sort(idx, function(a, b) return v[a] < v[b] end)
		local r = {}
		for k, i in ipairs(idx) do r[i] = k end
		return r
	end
	local rx, ry = rank(xs), rank(ys)
	local d2 = 0
	for i = 1, n do d2 += (rx[i] - ry[i]) ^ 2 end
	return 1 - 6 * d2 / (n * (n * n - 1))
end

local all = {}
local byFarm, byDriver = {}, {}
local finished, total = 0, 0
local speedsAll, placesAll, rarityAll = {}, {}, {}
local rarityPts = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8 }
local fastestWins, matchesWithFinisher = 0, 0
for _, m in ipairs(matches) do
	local fastest, fastestName = -1, nil
	for _, p in ipairs(m.results) do
		total += 1
		if p.race.finished then finished += 1 end
		byFarm[p.farmProfile] = byFarm[p.farmProfile] or {}
		table.insert(byFarm[p.farmProfile], p.place)
		byDriver[p.driver] = byDriver[p.driver] or {}
		table.insert(byDriver[p.driver], p.place)
		table.insert(speedsAll, p.maxSpeed)
		table.insert(placesAll, p.place)
		local pts = 0
		for r, n in pairs(p.rarity) do pts += rarityPts[r] * n end
		table.insert(rarityAll, pts)
		if p.maxSpeed > fastest then fastest, fastestName = p.maxSpeed, p.name end
	end
	if m.results[1].race.finished then
		matchesWithFinisher += 1
		if m.results[1].name == fastestName then fastestWins += 1 end
	end
end

local summary = {
	generatedBy = "tools/report.luau", biome = biome,
	track = { length = geo.length, nodes = #track.nodes },
	geometry = {
		solidOnlyBecauseOfCanCollideBug = #findings.solid,
		treesInLane = #findings.trees,
		wallIntrusionSpots = #findings.intrusions,
		respawnOffTrackSamples = #findings.respawnOff,
		respawnSamples = math.floor(geo.length / 50) + 1,
	},
	raceRuns = {},
	matches = {
		count = #matches, bots = total,
		finishRate = finished / math.max(total, 1),
		spearmanTopSpeedVsPlace = spearman(speedsAll, placesAll),
		spearmanRarityVsPlace = spearman(rarityAll, placesAll),
		fastestCarWins = fastestWins, matchesWithFinisher = matchesWithFinisher,
		meanPlaceByFarmProfile = {}, meanPlaceByDriver = {},
	},
}
-- Fun as numbers (Shared/RaceMetrics; targets in Constants.FUN_TARGETS)
local RaceMetrics = env.requirePath("ReplicatedStorage.Shared.RaceMetrics")
do
	local list = {}
	for _, m in ipairs(matches) do table.insert(list, m.fun) end
	local agg = RaceMetrics.aggregate(list)
	agg.racingShare = RaceMetrics.racingShare(agg.lastTime, Constants.PHASE_DURATION)
	agg.fastestWinRate = matchesWithFinisher > 0 and fastestWins / matchesWithFinisher or nil
	agg.speedPlaceCorr = spearman(speedsAll, placesAll)
	summary.fun = { aggregate = agg, verdicts = RaceMetrics.verdicts(agg, Constants.FUN_TARGETS) }
end
for k, v in pairs(byFarm) do summary.matches.meanPlaceByFarmProfile[k] = mean(v) end
for k, v in pairs(byDriver) do summary.matches.meanPlaceByDriver[k] = mean(v) end
for _, r in ipairs(raceRuns) do
	table.insert(summary.raceRuns, {
		world = r.world, car = r.carLabel, carBuild = r.carDesc, maxSpeed = r.car.maxSpeed,
		driver = r.profile, finished = r.finished, time = r.time,
		progress = math.floor(r.maxProgress), respawns = #r.respawns, impacts = #r.impacts,
	})
end
fs.writeFile(OUT .. "/summary.json", serde.encode("json", summary, true))

-- ─── Markdown ──────────────────────────────────────────────────────────────────
local md = {}
local function line(s) table.insert(md, s or "") end
line("# " .. biome .. " track report")
line()
line("Generated by `lune run tools/report.luau` from the real map builder, game modules and server scripts running in the offline mock engine. Re-run it after every map or balance change.")
line()
line("![track](track.svg)")
line()
line("## Single-car race simulation")
line()
line("Each car drives alone with the shared Autopilot. \"Authored\" restores every part's authored collision. \"Live code\" runs MapVisibility and RaceProgress exactly as the server does; the two should match.")
line()
line("| Map | Car | Top speed | Driver | Result | Respawns | Wall hits |")
line("|---|---|---|---|---|---|---|")
for _, r in ipairs(summary.raceRuns) do
	local res = r.finished and (fmt(r.time) .. " s") or string.format("stuck at %d / %d studs", r.progress, math.floor(geo.length))
	line(string.format("| %s | %s | %s | %s | %s | %d | %d |", r.world, r.car, fmt(r.maxSpeed), r.driver, res, r.respawns, r.impacts))
end
line()
line("Cars by top speed: " .. table.concat((function()
	local t = {}
	for _, rep in ipairs(reps) do
		local c = KineSim.carFromStats(rep.build.stats, Constants, biome)
		table.insert(t, string.format("%s = %s (top speed %s, turn %s rad/s)", rep.label, Builds.describe(rep.build), fmt(c.maxSpeed),
			fmt(env.requirePath("ReplicatedStorage.Shared.VehicleController").turnRate(c.turnSpeed, biome == "SKY"), 2)))
	end
	return t
end)(), "; ") .. ".")
line()
line(string.format("## Simulated matches (%d × 6 bots, authored map)", #matches))
line()
local ms = summary.matches
line(string.format("- Finish rate within %d s: %d%%", Constants.RACING_TIMEOUT, math.floor(ms.finishRate * 100 + 0.5)))
line(string.format("- Fastest car won %d of %d matches that had a finisher", ms.fastestCarWins, ms.matchesWithFinisher))
line(string.format("- Rank correlation, top speed vs place: %s (−1 = faster always places better)", fmt(ms.spearmanTopSpeedVsPlace, 2)))
line(string.format("- Rank correlation, rarity points collected vs place: %s", fmt(ms.spearmanRarityVsPlace, 2)))
line()
line("| Group | Mean place (1 = best) |")
line("|---|---|")
for k, v in pairs(ms.meanPlaceByFarmProfile) do line(string.format("| farming: %s | %s |", k, fmt(v, 2))) end
for k, v in pairs(ms.meanPlaceByDriver) do line(string.format("| driving: %s | %s |", k, fmt(v, 2))) end
line()
line("## Fun metrics")
line()
line("Each simulated match is scored with `Shared/RaceMetrics` (the same code scores real Studio playtests, see `Modules/PlaytestReport`). Bots race as ghosts on one clock: no car-to-car contact, no abilities, so lead changes come from build and driving differences only. Targets are starting points in `Constants.FUN_TARGETS`; playtests decide.")
line()
line("| | Metric | Value | Target | Why |")
line("|---|---|---|---|---|")
for _, v in ipairs(summary.fun.verdicts) do
	local range = (v.min and fmt(v.min, 2) or "") .. " .. " .. (v.max and fmt(v.max, 2) or "")
	line(string.format("| %s | %s | %s | %s | %s |", v.ok == nil and "·" or (v.ok and "✓" or "✗"), v.key,
		v.value and fmt(v.value, 2) or "n/a", range, v.why or ""))
end
line()
line(string.format("Overtakes per match: %s. Per section (mean over matches; \"decided\" = matches whose largest time spread between bots was in that section):", fmt(summary.fun.aggregate.overtakes or 0, 1)))
line()
line("| Section | Mean time (s) | Spread between bots (s) | Decided | Respawns | Wall hits |")
line("|---|---|---|---|---|---|")
for _, sec in ipairs(summary.fun.aggregate.sections) do
	line(string.format("| %s | %s | %s | %d | %d | %d |", sec.name, fmt(sec.meanTime), fmt(sec.spread), sec.deciding, sec.respawns, sec.hits))
end
line()
line("## Geometry findings")
line()
line(string.format("- %d parts inside or next to the lane are solid during RACING but not in the authored map (red boxes).", #findings.solid))
line(string.format("- %d decoration parts (%s) stand inside the lane (red dots).", #findings.trees, table.concat(cfg.props, ", ")))
line(string.format("- %d spots where a wall cuts more than 6 studs into the lane (pink rings).", #findings.intrusions))
line(string.format("- %d of %d sampled positions respawn off the track (pink ×).", #findings.respawnOff, summary.geometry.respawnSamples))
line()
if fs.isFile("tests/out/results.json") then
	local res = serde.decode("json", fs.readFile("tests/out/results.json"))
	line(string.format("## Known bugs from the test suite (%d)", #res.knownBugs))
	line()
	for _, k in ipairs(res.knownBugs) do
		line("- **" .. k.name .. "** — " .. k.why)
	end
	line()
end
line("## What this does not cover")
line()
line("- Real Roblox physics: jumps, ramps, impulses, car-to-car contact. Confirm with the Studio RaceSim (`TestHarness.Runner.runRace`).")
line("- Network latency, touch controls and whether it is fun. Those need people.")
fs.writeFile(OUT .. "/summary.md", table.concat(md, "\n") .. "\n")

print("wrote " .. OUT .. "/track.svg, summary.md, summary.json")
print(string.format("%s matches: %d, finish rate %d%%, fastest car won %d/%d", biome, #matches, math.floor(ms.finishRate * 100 + 0.5), ms.fastestCarWins, ms.matchesWithFinisher))
for _, v in ipairs(summary.fun.verdicts) do
	print(string.format("  %s %-14s %s", v.ok == nil and "·" or (v.ok and "✓" or "✗"), v.key, v.value and fmt(v.value, 2) or "n/a"))
end
end

for _, biome in ipairs({ "FOREST", "OCEAN", "SKY" }) do
	if not ONLY or ONLY == biome then
		report(biome)
	end
end
