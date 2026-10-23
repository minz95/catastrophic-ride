# Testing harness

This game is tested in two places:

| Layer | Runs where | Speed | What it can tell you |
|---|---|---|---|
| **Offline** (Lune) | any machine, CI, an AI agent's sandbox | ~1 min tests, a few minutes for the report | config mistakes, stat balance, map geometry, kinematic race and full farm→craft→race matches using the real server scripts |
| **Studio** (StudioTestService / StepPhysics) | Roblox Studio, through the plugin or the Studio MCP server | seconds to minutes | real Roblox physics for the race, real multiplayer clients playing a whole round |

Neither layer can judge whether the game is *fun*, how touch controls feel,
or how it behaves under real network latency. Those still need people.

---

## 1. Offline layer

Install [Lune](https://github.com/lune-org/lune) 0.10.x (or `rokit install`,
see `rokit.toml`) and run from the repository root:

```sh
lune run tests/run.luau            # all specs
lune run tests/run.luau map        # only spec files whose name contains "map"
lune run tools/report.luau         # track SVG + balance report, every biome (12 matches each)
lune run tools/report.luau 40      # more matches, steadier numbers
lune run tools/report.luau 12 SKY  # one biome
```

Outputs:

- `tests/out/results.json` – pass/fail plus every known bug with its details.
- `reports/<biome>/track.svg` (`forest`, `ocean`, `sky`) – top-down map:
  corridor, walls, parts that block the lane, checkpoint footprints, respawn
  targets, simulated driving lines.
- `reports/<biome>/summary.md` / `summary.json` – race results per car and
  driver, match statistics, **fun metrics** (`Shared/RaceMetrics` against
  `Constants.FUN_TARGETS`, per-section spreads), geometry findings, known bugs.

### How it works

`tests/lib/` emulates just enough of the engine to run the game's own code:

- `loader.luau` maps `roblox/` into an Instance tree with Rojo's rules, so
  `require(game.ReplicatedStorage.Shared.Constants)` works unchanged.
- `mock.luau` provides Instances, CollectionService, a deterministic Random,
  fake players with characters, and a **virtual clock**: `task.wait`,
  `task.delay`, `tick()` only advance when a test calls `advance(seconds)`,
  so a 90-second farming phase runs in milliseconds. Math types come from
  Lune's `@lune/roblox`.
- `server.luau` boots the real server scripts (GameManager, SessionManager,
  MapManager, FarmingManager, CraftingManager, RacingManager…) in that mock.
- `world.luau` builds a biome's map with the real builder module
  (`Modules/Maps/ForestMap`, `OceanMap`, `SkyMap`: `World.build("OCEAN")`) and
  applies the RACING visibility state, either **as shipped** (today's
  `MapVisibility` code) or **authored** (every part's authored collision).
  The body height band used for collisions comes from the track data
  (`trackTop`, `obstacleBand`): boats ride over the 1-stud dock, flyers hover
  at Y 84.
- `mapchecks.luau` / `biomespecs.luau` are the geometry checks every map gets:
  lane obstacles, walls cutting into the lane (inside of turns), any hole in the walls (outside of turns included),
  wall spurs past a corner, slow zones on the lane, gates a car can drive
  past, pads off the lane, floor holes, decoration in the lane.
- `kinesim.luau` is a 2D kinematic race simulator. It is a fair model of this
  game because the car's velocity is *set* every frame
  (`VehicleController`), not produced by tyres. Collisions use the footprints
  of the actually built parts. Seat values per biome (`KineSim.SEAT`) are
  checked against the real `VehicleBuilder`. It does not model jumps, waves,
  updrafts, gusts or car-to-car contact.
- `matchsim.luau` runs a whole match: bots (`BotBrain`) walk to items and call
  the real `RequestPickup` / `RequestContest` / `RequestSteal` handlers, craft
  through `SubmitCraft`, and every resulting car is raced on `kinesim`.

### Known bugs

What the specs cover (`tests/specs/`): config consistency (track data vs
Constants, BiomeConfig and the spawn grid), stat balance per biome, the map
geometry of FOREST, OCEAN and SKY (`map_*`), race progress and respawn on
every track, the real RacingManager (speed effects, passives, shields,
rounds), every item's ability through the real AbilityManager, hazards,
farming rules (pure `FarmingRules` over hundreds of generated cases, plus
scenarios on the real FarmingManager), the driving model, kinematic race
sims per biome (`sim_*`), whole matches on every biome (`farming`,
`match_biomes`), fun metrics and the live playtest report (`race_metrics`),
and smoke runs of the Studio harness.

`R.known(name, why, fn)` marks a check that is **expected to fail today**
because it documents a bug. The run stays green while the bug exists and
**fails as soon as the bug is fixed**, telling you to turn `known` into `it`.
That keeps the list of known problems honest and visible.

---

## 2. Studio layer

The code lives in `roblox/ServerScriptService/TestHarness/` and
`StarterPlayerScripts/BotDriver.client.lua`. In live servers and ordinary
playtests it does nothing (see `Modules/HarnessConfig.lua`).

### From the Studio plugin

Rebuild the plugin (`rojo build studio-plugin/default.project.json -o …`) and
use the toolbar buttons **Race Sim**, **Race Sim (Run)** and **Bot Match**.
Each prints a summary to Output, followed by `[HarnessReport] {json}`.

### From the command line (saved experiments)

`tools/studio/sim.py` runs Studio real-physics experiments without MCP or an
open Studio window (macOS: Rojo builds the place, `RobloxStudio -task
RunScript` runs it, the result is read back from the Studio log):

```sh
python3 tools/studio/sim.py list                 # scenarios and tags
python3 tools/studio/sim.py run smoke            # 3 races, ~6 min
python3 tools/studio/sim.py run core             # + escape tests and bot matches, ~40 min
python3 tools/studio/sim.py run full             # + builds, car contact, ballast, 2 rounds
python3 tools/studio/sim.py run race-ocean --set seconds=200 --samples
```

Scenarios live in `tools/studio/scenarios.json` (kind `race`, `escape` or
`match`, Runner options, checks). Results go to `reports/studio/<name>.json`
and `reports/studio/summary.md`; the exit code is 1 when a check fails. Add a
scenario there instead of running one-off scripts, so the next change is
checked the same way.

| Kind | Runner call | Checks |
|---|---|---|
| `race` | `runRace{ mode = "run", ... }` (profiles, `car`, or `cases` = one car each with its own `car` / `profile` / `spawn`) | every car finishes, respawns per car, winner time vs `FUN_TARGETS` (warning) |
| `escape` | `runEscape{ biome }` | every case drives `RaceSim.ESCAPE_GAIN` studs on within `ESCAPE_SECONDS`: nose in the left / right wall at 70°, facing backwards (every 500 studs), on each jump ramp, mud zone and drift corner. "Needed a respawn" is a warning, "stuck" a failure |
| `match` | `runMatch{ biome, players, rounds }` | all bot clients joined, finish rate, no server errors; `fairStart` (every car leaves the grid after GO and within N s of the others, from `race_go` / `race_launch`), `hudTimer` (each bot's FARMING / CRAFTING timer: one copy on screen, counting down, within 2 s of the server's `PhaseEndsAt`) |

Farming and crafting scenarios (`match` with `stopAfter = "CRAFTING"`, tag
`farm`) end when the race would start and check each round's
`farm` / `craft` stats from `MatchHarness`:

| Check | Meaning |
|---|---|
| `ledger` | every player's inventory size equals what the pickup / steal events add up to (no item copied or lost) |
| `everyonePicks` | every non-AFK bot picked something up |
| `everyoneCrafted`, `noRejected` | every player has a craft and the server dropped no slot from a bot's submission |
| `autoFor` | players with these farm profiles got an automatic craft |
| `draftKept` | players with these farm profiles (`slow`: places items, never submits) kept what they placed when the timer ran out |
| `minAttempts` / `maxAttempts` | steal attempts by result (`stolen`, `defended`, `denied: …`) |

Ability scenarios (`abilities-forest` / `-ocean` / `-sky`, tag `abilities`)
give each bot a fixed loadout per round (`loadouts[round][botIndex]`,
crafted as given by `CraftingManager` whatever was farmed), so the four
rounds of `abilities-forest` fire all 39 items. Bots tap E every 2.5 s
through RacingClient's normal E handling. Every effect that lands on a car
goes through `Modules/EffectFx.play`, which the server measures
(`ability_probe`: height, speed, MaxSpeed and TurnSpeed just before and
over the next 0.5–1.5 s) and the bot clients report drawing (`bot_fx`).
The `abilities` check fails when an item never fired, a request named an
item that is not on the car, a lift never raised the car 1.5 studs, a speed
effect never moved MaxSpeed the right way, a steering lock never set
TurnSpeed to 0, or an effect was never drawn. `summary` lists every effect
key with what was measured.

Bot farm profiles (`Shared/BotBrain`): `sweaty`, `casual`, `afk`, and two
harness profiles, `thief` (hunts anyone within 120 studs and steals on every
chance) and `guard` (always taps the defence 3 times). Studio bots steal and
defend through the same remotes as the keyboard (`BotDriver`).

Harness cars in one race are ghosts to each other (collision group
`HarnessCars`) unless `contact = true`; the `*-contact` scenarios test
car-to-car contact from the grid.

Command-line caveats (Studio 0.743): `workspace:StepPhysics` crashes Studio
under `-task RunScript`, so only `mode = "run"` works there; `-outputFile`
writes nothing; log lines are cut at ~1000 characters (the runner prints the
JSON in chunks). The first session after a place opens can end at once with
no result; `Runner` retries it.

### From an AI agent (Roblox Studio MCP server)

With Studio open and Rojo syncing, run Luau through the MCP server's code
execution tool:

```lua
local Runner = require(game.ServerScriptService.TestHarness.Runner)
return Runner.runRace({ profiles = { "expert", "average", "novice" }, seconds = 180 })
```

Every Runner function returns `summary, json`.

| Call | What happens |
|---|---|
| `Runner.runRace({ biome = "SKY", ... })` | **Edit mode.** Builds the map (`biome` = FOREST, OCEAN or SKY), applies the RACING visibility state, spawns a VehicleBuilder car per driver profile and drives it with `workspace:StepPhysics` – faster than real time. |
| `Runner.runRace({ mode = "run", ... })` | Starts a fresh server-only session with `StudioTestService:ExecuteRunModeAsync`; same race in real time with the latest code. |
| `Runner.runMatch({ players = 4, rounds = 1 })` | `StudioTestService:ExecuteMultiplayerTestAsync`: a server and N client windows. Every client is a bot (`BotDriver`) that farms, crafts and races through the normal client code; the server returns a report with round results, telemetry and every server/client script error. |

Race options: `car = "slowest" | "p50" | "fastest" | { BODY = …, ENGINE = … }`,
`visibility = "shipped" | "intended"`, `respawn = "legacy" | "track"`,
`seconds`, `driverMass` (stand-in for the seated character), `seed`.

Caveats:

- Studio caches `require()` in edit mode. After changing game code, use
  `mode = "run"` (fresh session) or reopen the place.
- RaceSim does not run RacingManager. Mud, slow zones, boost pads and boost are
  emulated with `SpeedModifiers` using the same constants.
- In edit mode no character sits in the car; set `driverMass` to the
  `mass` reported by the `vehicle_spawn` telemetry event of a real playtest.

### Vehicle look

`lune run tools/vehicle_gallery.luau` draws side / top / front views of the
vehicles `VehicleBuilder` really assembles (procedural item models included)
into `reports/vehicles/<biome>.svg`. `tests/specs/vehicle_design.spec.luau`
builds every item in every slot plus 40 random full builds per biome and
checks: only the chassis has mass and collision (sized as before), every
part welded, width within the 7-stud grid slot, front parts at -Z, HEAD at
the front and TAIL at the back, nothing under the road or the hull, mirrored
left / right parts, and every item inside its slot box. In Studio,
`python3 tools/studio/sim.py run vehicles` drives every BODY item and random
full builds 700 studs on each biome (`maxTilt`, `minTopSpeedRatio`, stuck).
Each car holds only the throttle for the first 2.5 s (`minHoldGain`: studs
gained; Up alone must drive) and `maxNoseOff` caps the angle between the
nose and the travel direction while accelerating (a vehicle drawn or driven
sideways, issue #165; braking turns are not counted).

### Unusual sessions and load

`tests/specs/edge_cases.spec.luau` (issues #42, #54): ten players on one
item, a contest's item locked even after its players walk away, a contest
winner who left, a hundred items for ten players (no item twice,
inventories add up), solo play, empty and partly placed crafts, a racer
leaving, everyone leaving, someone joining mid-race (Spectating, not waited
for, plays the next round), cars that arrive just after RACING starts.

`python3 tools/studio/sim.py run load-8p` (run it alone): the fullest
server Studio can start (ExecuteMultiplayerTestAsync takes at most 8
players; MAX_PLAYERS is 10, so 10 needs a live server). Every match now
samples `server_perf` every 2 s (Heartbeat Hz, physics fps, send / receive
kbps, memory) and the summary prints the range per phase; the `perf` check
fails when the 5th percentile drops under the floor. 2026-10-23: FARMING
50–60 Hz, RACING 55–60 Hz, send ≤ 134 kbps (target 20+ Hz). Memory is the
whole Studio process, not the game.

### Saved progress

`tests/specs/progression.spec.luau`: the level / coin / daily-streak rules,
PlayerStore over the mock DataStore (`Mock.dataStores`, `Mock.dataStoreFail
= "get" | "set" | "all"`, `Mock.removePlayer`, `Mock.closeHandlers`: a failed
load is never saved over the real record, bots stay in memory, saves on leave
and shutdown) and a real race paying finishers by place and DNFs at RESULTS.
In Studio the `rewards` check (match-forest) wants a `reward` event for every
racer. Real DataStore writes need a published place with API access; bot
matches stay in memory.

### Shop

`tests/specs/shop.spec.luau`: the catalogue, buy / equip rules (coins,
level, owned), paint and trail on a real VehicleBuilder car in every biome
with the chassis and seat unchanged, the server handler, Robux coin packs
(granted once per PurchaseId, undone and retried when the save fails, never
for a record that failed to load) and the car CraftingManager builds wearing
the equipped look. A real purchase needs the published place and a product
id in `Shared/Products`.

### Analytics (live only)

Retention (D1 / D7 / D30), sessions and playtime are on the Creator
Dashboard (Analytics) once the place is public; nothing to build. On top,
`AnalyticsManager` sends: the onboarding funnel (first round ever: Joined →
First pickup → Car built → Raced → Finished a race → Got a reward), the
"Round" funnel every round (Farming → Crafting → Car built → Racing →
Finished → Results), coins earned (Gameplay / TimedReward), levels reached
and custom `ReturnDay` (days since the first round, on the first round of a
day) and `RoundPlace`. Studio and harness sessions send nothing;
`progression.spec.luau` records the calls through `Analytics.sink`, and
`sim.py run api-analytics` checks the AnalyticsService methods and enums
exist (a wrong name logs nothing).

### Sound

All audio ids live in `Shared/SoundConfig` and are played on the client by
`Shared/SoundFx` (SoundClient for phases, ambience and events; RacingClient
for boost and drift; the crafting screen for slots and submit).
`python3 tools/studio/sim.py run sounds` loads every id as a real Sound in
Studio (exists, this place may play it, has a length). New ids: pass
`--set 'search=[{"key":"x","keyword":"whoosh","music":false,"maxDur":3,
"creators":["ProSoundEffects","APMOfficial","DistrokidOfficial"],"pages":4}]'`
and read `report.searches` in `reports/studio/sounds.json` (Creator Store
search, each hit load-checked). Use only those licensed catalogues. Whether a
track fits the mood needs ears: listen in a playtest.

### Map and item look (3D preview without Studio)

`lune run tools/scene_dump.luau <BIOME> <node> [out.json] [radius] [cars|drops]`
builds a map with the real builders in the mock engine and writes the parts
near a chase camera at that centerline node; `python3 tools/scene_render.py
out.json` draws them as a PNG (flat shading, Neon glow, transparency, fog;
no textures or shadows). `cars` adds four cars on the lane, `drops` every
item an ability leaves on the track (`Modules/TrackDrops`). Use it to check
colours, brightness and that things are where they should be before a
Studio run.

### Driving: grip, drift and hits

`lune run tools/drift_sim.luau [FOREST|OCEAN] [profile]` drives the slowest /
median / fastest build around the track with and without drifting (offline
kinematic sim, real `VehicleController` and `Autopilot`) and prints the lap
and section times, drifts and mini-turbos. Drifting should win a little time
for a good driver (2026-10-22: 1–2 s per Forest lap), never a lot.
`tests/specs/vehicle_controller.spec.luau` covers grip, slide, turbo and
knock; `tests/specs/car_impact.spec.luau` the hit model. In Studio, match
scenarios log `impact`, `drift_turbo` and `drop_placed`; `sim.py` prints a
`driving:` line and fails on hits that push nobody or drops that miss the
ground (`checks.hits` / `checks.turbos` set minimum counts).

### Farming fights

`tests/specs/farming.spec.luau` ("fights") runs the real FarmingManager:
reach, facing, cooldown, guard, hit memory, knock-out drops and immunity.
In Studio, `python3 tools/studio/sim.py run fight-4p` puts two "brawler" bots
(walk up to players and punch) with a casual and a "guard" bot; checks:
landed hits, at least one knock-out and one block (`minPunches`), the
inventory ledger, and that every client drew the punch and guard animations
(`fightFx`; the steal scenarios check the grab / swat animations). "Drawn"
means the joint really moved: for a punch the bot client measures the
shoulder reaching the pose and the arm turning against the torso. (Until
2026-10-23 it only meant "the character exists", and it passed while every
pose did nothing: Roblox avatars now use AnimationConstraint joints with no
Motor6D, see FarmFx.) Brawlers leave a foe the server keeps one hit short of
a knock-out (empty hands) for a while; two empty-handed brawlers used to
punch each other all phase.

### Crafting balance

`lune run tools/balance.luau [BIOME|all] [seeds] [matches]` (~5 min for all,
2 seeds) measures what every item is worth and who wins, on the real game
modules (`tests/lib/balance.luau`):

1. **Pace**: KineSim races of ~20 builds spread over top speed and turning,
   fitted to MaxSpeed / TurnSpeed / Torque / boost seconds (R² ≈ 0.99), so
   any build's race time is known.
2. **Abilities**: each item's E, with the numbers AbilityManager uses
   (`AbilityConfig` selfSpeed / victimSpeed / push / …), fired by a sensible
   player in a KineSim race (bursts on straights, lifts and Drill before mud,
   Backpack when the gauge is empty). Harmful ones are applied to a victim
   car to measure what one hit costs; hits per race = uses × `HIT_RATE`
   (an assumption: nearest-target 75%, radius / 25, drops 30%).
3. **Matches**: Monte Carlo fields of 6 players with inventories drawn with
   the farming spawn odds; each crafts the items worth most; time = pace −
   own gains + hits taken from rivals + driver noise.

`reports/balance/summary.md` lists each item's value (stats / own gain /
offense / protection, uses per race, win lift) and checks
`Constants.BALANCE_TARGETS`: rarity tiers rise ≥ 0.3 s each, Epic − Common
1–4.5 s per slot, no item > 2 s above its tier, every item worth ≥ 0.2 s,
the most common winning item < 40% of wins, the rarest build of a field
wins 20–60%. It exits 1 when a check fails. Not modelled: HEAD / TAIL
passives, car contact, blinding screens on humans. Confirm a tuning change
with `python3 tools/studio/sim.py run abilities-forest` (real abilities,
bot clients).

### Idle time

`python3 tools/studio/idle_report.py` reads the saved Studio match reports
and writes `reports/studio/idle.md`: when each inventory filled up and how
long FARMING went on after a player's last pickup, how long crafters waited
after submitting, and how long finished racers waited for the results.
`tests/specs/farming.spec.luau` ("idle time") and
`racing_manager.spec.luau` ("after the finish line") check the fixes below.

### Obstacles

Falling logs (FOREST, `HazardManager`) land where `Shared/HazardPlan` says:
always a ≥ 12-stud gap beside them, 30 studs apart, never on a ramp, mud,
pad or the finish stretch; a red ring + ⚠ marks the spot 1.2 s before.
`hazards.spec.luau` checks 2000 random drops and races KineSim drivers
through them (`KineSim.run{ logs = true, avoid = false }` = a driver who
ignores them). `Autopilot` steers around `state.hazards`; Studio bots pass
the logs and obstacle drops they see. Look:
`lune run tools/scene_dump.luau FOREST 34 out.json 300 logs`.

### Roads with heights

`track_heights.spec.luau`: layered projection and walls on a test loop,
OCEAN's flume (grades ≤ 8%, 24+ studs where it passes over itself, a boat
up and down without respawns), SKY's corkscrew (the lower layer's fence and
lid stay under the upper road, a flyer round it without respawns), FOREST's grades (≤ 6%, change ≤ 6% per node), 24+ studs where the road
passes over itself, respawns on the right layer, logs never under a deck, a
KineSim driver whose progress never jumps a layer; `racing_manager.spec`
puts a car under the trestle and expects a "fell" respawn. The map checks
(`mapchecks.luau`) look only at parts in the body band of the road layer
they test. Look: `lune run tools/topview.luau FOREST` + `python3
tools/topview.py reports/forest/topview.json` (top-down, respawns marked)
and `lune run tools/scene_dump.luau FOREST 29 out.json 300` (under the
spiral). Studio: `race-forest`, `escape-forest`, `match-forest`; the race
samples (`--samples`) carry the car's Y, the road's Y and what the ground
ray hit.

### Playtests: markers and the fun report

In Studio (or on a server with `ReplicatedStorage:SetAttribute("PlaytestMarkers", true)`)
players press **M** where something feels frustrating and **N** where it
feels fun. `PlaytestReporter.server.lua` logs the spot and its track section,
and at RESULTS prints the race scored by `Shared/RaceMetrics` (winner time,
spread, lead changes, overtakes, close racing, per-section spreads, respawns,
hits, markers) followed by `[PlaytestReport] {json}`. Over MCP:

```lua
local PR = require(game.ServerScriptService.Modules.PlaytestReport)
return PR.format(PR.last), PR.json(PR.last)
```

### Telemetry in any session

`Modules/Telemetry.lua` records phases, pickups, contests, steals, crafts,
vehicle spawns (with assembly mass), every MaxSpeed change with before/after
values, respawns with their target, checkpoints and finishes. The bot match
returns it in its report; `Telemetry.setDetailed(true)` adds position samples
every 0.5 s.

---

## 3. Workflow for map and balance changes

1. Edit data, not code: `ReplicatedStorage/Shared/Tracks/<Biome>Track.lua`
   holds the node list, walls, checkpoints, pads, drift corners, ramps,
   trigger sizes and scenery positions; balance numbers live in
   `Shared/Constants.lua` and `Shared/ItemConfig.lua`. The shared parts are
   built by `Modules/Maps/TrackKit.lua`; walls follow
   `TrackGeometry:boundaryRuns` (closes the outside of each turn, drops wall
   that would stand inside the lane), so moving nodes needs no builder change.
2. `lune run tests/run.luau` – nothing new may fail.
3. `lune run tools/report.luau` – open `reports/<biome>/track.svg` and
   `summary.md`; compare finish rate, stuck locations, wall hits.
4. In Studio: `Runner.runRace{ mode = "run" }` to confirm with real physics,
   then `Runner.runMatch{}` for a full round with bot clients.
5. Commit the regenerated `reports/` with the change, so the diff shows
   what the change did to the track.
