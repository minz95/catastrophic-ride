# Catastrophic Day — notes for AI agents

Roblox racing game (Luau, Rojo). Read `README.md` for the game loop,
`docs/design.md` for principles, track specs, fun targets and the decision
log, and `docs/testing.md` for how to verify changes. This file is the short
version.

## Verify every change

```sh
lune run tests/run.luau      # must stay green; ~1 min
lune run tools/report.luau   # regenerates reports/{forest,ocean,sky}/ (track.svg, summary.md)
```

- Tests run the REAL game modules and server scripts in a mock engine
  (`tests/lib/`). Prefer adding a spec over reasoning about behaviour; write
  the spec first and watch it fail on the bug.
- `R.known(...)` marks a documented bug. When you fix one, the run fails until
  you change that `known` to `it` — do that in the same change.
- Look at `reports/<biome>/track.svg` (render it to PNG if you cannot view
  SVG) after touching map code or track data. "Fun metrics" in
  `summary.md` shows whether a change moved the game toward or away from
  `Constants.FUN_TARGETS`.
- In Studio (MCP): `require(game.ServerScriptService.TestHarness.Runner)`
  → `runRace{ biome = "OCEAN", mode = "run" }` for real physics,
  `runMatch{ biome = "SKY" }` for bot clients. After any Studio playtest,
  `require(game.ServerScriptService.Modules.PlaytestReport).last` holds the
  fun report (also printed at RESULTS); players mark spots with M / N.
- Without MCP (macOS): `python3 tools/studio/sim.py run smoke|core|full`
  runs the saved Studio experiments (`tools/studio/scenarios.json`: races,
  escape tests, bot matches) and writes `reports/studio/`. Run `core` after
  changing driving, maps or track data.

## Where things live

- Track data: `roblox/ReplicatedStorage/Shared/Tracks/{Forest,Ocean,Sky}Track.lua`
  (nodes, widths, walls, triggers and their sizes, scenery positions).
  Shared track parts: `ServerScriptService/Modules/Maps/TrackKit.lua`.
  Biome builders (`Modules/Maps/{Forest,Ocean,Sky}Map.lua`) add scenery only.
  Change numbers in the data file, not the builders.
- Walls come from `TrackGeometry:boundaryRuns`: extended to close the outside
  of every turn, dropped wherever they would stand inside the lane (inside of
  turns, SKY's figure-8 crossings). `wallGapHalfWidth` > 0 adds doorways
  (currently 0 everywhere: continuous walls).
- Vehicle look: `Modules/VehicleDesign.lua` (car / boat / plane as data:
  parts, slot boxes for the crafted items), built by `Modules/VehicleBuilder`.
  Only the chassis has mass and collision, sized from the stats as before, so
  the look never changes handling. Check a change with
  `lune run tools/vehicle_gallery.luau` (`reports/vehicles/*.svg`, front on
  the left) and `python3 tools/studio/sim.py run vehicles`.
- Driving: `Shared/VehicleController.lua` is the single key → velocity path
  for players (RacingClient), bots and simulators. `Shared/Autopilot.lua` is
  the simulated driver; `Shared/BotBrain.lua` the farming/crafting bot.
- Rules as pure functions: `Shared/FarmingRules.lua` (pickup / contest /
  steal), `Shared/RaceProgress.lua` (progress, respawn), `Shared/RaceMetrics.lua`
  (fun numbers), `Shared/SpeedModifiers.lua` (speed effects).
- All tunable numbers: `Shared/Constants.lua`. No magic numbers in logic.
- Server phase machine: `ServerScriptService/GameManager.lua`. Harness
  overrides come from `Modules/HarnessConfig.lua` and are nil in live games.
- Telemetry: `Modules/Telemetry.lua` (event list in its header).

## Facts that are easy to get wrong

- Only `Modules/VehicleTuning` writes `VehicleSeat.MaxSpeed` / `TurnSpeed`
  during a race (named multipliers). Never save a seat value and restore it
  later: overlapping effects then leave cars permanently fast or slow.
- Harmful effects call `RaceEffects.blocksHit(player)` first (shields,
  Rubber Duck). Enemy abilities target only `_targetable` players.
- Connect Touched handlers once per part (`_once` in RacingManager) and check
  `_active`; connecting on every RACING phase doubles effects from round 2.
- The drive command ramps: acceleration = `ACCEL_BASE + Torque × ACCEL_PER_TORQUE`
  (`Constants.DRIVE`). Reset `VehicleController` state on spawn and respawn.
- Top speed: `Constants.maxSpeedFor(biome, stats)` puts every build within
  ±6% of `Constants.RACE_SPEED[biome].center` (the build must not decide the
  race). VehicleBuilder, the simulators and BotBrain all use it.
- Races start together: cars are held on the grid by `Modules/RaceStart`
  until GO (`RACE_COUNTDOWN` s after RACING begins); the race clock, boosts
  and respawns start at GO. Never unanchor a race car yourself.
- Client phase timers count down to the `PhaseEndsAt` attribute
  (`Shared/PhaseClock`), not to `Constants.PHASE_DURATION`.
- Handling: `Constants.turnSpeedFor(biome, stats)` maps the stat onto a range.
  SKY is also capped at `VehicleController.SKY_TURN_CAP` (1.5) inside the
  controller; use `VehicleController.turnRate` for the real rate.
- Track data `obstacleBand` is the body height band above `trackTop` that
  collides: boats ride over the 1-stud dock, flyers hover at Y 84.
- Race progress is distance along the centerline (`TrackGeometry:progressAt`,
  continuous across kinks), never a raw Z coordinate. Respawns go to
  `RaceProgress.respawnPoint`, on the centerline facing along the track.
- Steals: `DefendSteal` is one call per tap and counts only inside the
  victim's open window (`STEAL_DEFEND_PRESSES` taps defend). One steal at a
  time per thief and per victim; every attempt is logged as `steal_attempt`.
- A full inventory swaps out its weakest item only inside `_giveItem`, when
  the new item is really handed over (logged as `item_drop`); a refused
  pickup or a lost contest must not cost an item.
- The current phase and biome are also `ReplicatedStorage` attributes
  (`Phase`, `Biome`) for client scripts that start after the event went out.
- Craft submissions go through `Shared/CraftingRules.validate` (core slots
  only take their own item type; the rest is dropped and logged).
- Timed things end on a timer, not on the next client message (contests used
  to wait for one more press and locked items for the round).
- `MapVisibility.restore` must keep a stored `false` (the old
  `x ~= nil and x or true` idiom turned trigger volumes into invisible walls).
- `OnServerInvoke` / `OnInvoke` cannot be read in Roblox, only assigned.
- Lune's `fs` is async: never read files inside mock-managed coroutines
  (the loader caches sources at boot for this reason).
- The offline race sim moves a point at 60 Hz; gates are tested along each
  step's move (a fast car can cross a thin trigger between two steps).

## What the tests cannot tell you

Real Roblox physics for jumps, waves, updrafts and gusts; car-to-car contact
in a real server; touch controls; network latency; whether it is fun. The
Studio harness covers the first two; playtests with M / N markers cover the
rest.
