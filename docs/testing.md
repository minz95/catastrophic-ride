# Testing harness

This game is tested in two places:

| Layer | Runs where | Speed | What it can tell you |
|---|---|---|---|
| **Offline** (Lune) | any machine, CI, an AI agent's sandbox | ~10 s tests, ~45 s report | config mistakes, stat balance, map geometry, kinematic race and full farm→craft→race matches using the real server scripts |
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
lune run tools/report.luau         # track SVG + balance report (12 matches)
lune run tools/report.luau 40      # more matches, steadier numbers
```

Outputs:

- `tests/out/results.json` – pass/fail plus every known bug with its details.
- `reports/forest/track.svg` – top-down map: corridor, walls, parts that block
  the lane, checkpoint footprints, respawn targets, simulated driving lines.
- `reports/forest/summary.md` / `summary.json` – race results per car and
  driver, match statistics, geometry findings, known bugs.

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
- `world.luau` builds the FOREST map with the real `ForestMap` module and
  applies the RACING visibility state, either **as shipped** (today's
  `MapVisibility` code) or **authored** (every part's authored collision).
- `kinesim.luau` is a 2D kinematic race simulator. It is a fair model of this
  game because the car's velocity is *set* every frame
  (`VehicleController`), not produced by tyres. Collisions use the footprints
  of the actually built parts. It does not model jumps or car-to-car contact.
- `matchsim.luau` runs a whole match: bots (`BotBrain`) walk to items and call
  the real `RequestPickup` / `RequestContest` / `RequestSteal` handlers, craft
  through `SubmitCraft`, and every resulting car is raced on `kinesim`.

### Known bugs

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
| `Runner.runRace({ ... })` | **Edit mode.** Builds the map, applies the RACING visibility state, spawns a VehicleBuilder car per driver profile and drives it with `workspace:StepPhysics` – faster than real time. |
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

### Telemetry in any session

`Modules/Telemetry.lua` records phases, pickups, contests, steals, crafts,
vehicle spawns (with assembly mass), every MaxSpeed change with before/after
values, respawns with their target, checkpoints and finishes. The bot match
returns it in its report; `Telemetry.setDetailed(true)` adds position samples
every 0.5 s.

---

## 3. Workflow for map and balance changes

1. Edit data, not code: `ReplicatedStorage/Shared/Tracks/ForestTrack.lua`
   holds the node list, hazards and checkpoints; balance numbers live in
   `Shared/Constants.lua` and `Shared/ItemConfig.lua`.
2. `lune run tests/run.luau` – nothing new may fail.
3. `lune run tools/report.luau` – open `reports/forest/track.svg` and
   `summary.md`; compare finish rate, stuck locations, wall hits.
4. In Studio: `Runner.runRace{ mode = "run" }` to confirm with real physics,
   then `Runner.runMatch{}` for a full round with bot clients.
5. Commit the regenerated `reports/forest/` with the change, so the diff shows
   what the change did to the track.
