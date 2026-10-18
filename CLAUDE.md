# Catastrophic Day — notes for AI agents

Roblox racing game (Luau, Rojo). Read `README.md` for the game loop and
`docs/testing.md` for how to verify changes. This file is the short version.

## Verify every change

```sh
lune run tests/run.luau      # must stay green; ~10 s
lune run tools/report.luau   # regenerates reports/forest/ (track.svg, summary.md)
```

- Tests run the REAL game modules and server scripts in a mock engine
  (`tests/lib/`). Prefer adding a spec over reasoning about behaviour.
- `R.known(...)` marks a documented bug. When you fix one, the run fails until
  you change that `known` to `it` — do that in the same change.
- Look at `reports/forest/track.svg` (render it to PNG if you cannot view SVG)
  after touching map code or track data.
- In Studio (MCP): `require(game.ServerScriptService.TestHarness.Runner)`
  → `runRace{ mode = "run" }` for real physics, `runMatch{}` for bot clients.

## Where things live

- Track layout data: `roblox/ReplicatedStorage/Shared/Tracks/ForestTrack.lua`.
  The builder (`ServerScriptService/Modules/Maps/ForestMap.lua`) only turns it
  into parts. Change numbers in the data file, not the builder.
- Driving: `Shared/VehicleController.lua` is the single key → velocity path
  for players (RacingClient), bots and simulators. `Shared/Autopilot.lua` is
  the simulated driver; `Shared/BotBrain.lua` the farming/crafting bot.
- All tunable numbers: `Shared/Constants.lua`. No magic numbers in logic.
- Server phase machine: `ServerScriptService/GameManager.lua`. Harness
  overrides come from `Modules/HarnessConfig.lua` and are nil in live games.
- Map show/hide: `Modules/MapVisibility.lua`. Race progress / respawn
  formulas: `Shared/RaceProgress.lua`. Speed effects (target design):
  `Shared/SpeedModifiers.lua`.

## Facts that are easy to get wrong

- The car's velocity is SET each frame (`LookVector * throttle * MaxSpeed`).
  There is no coasting and `VehicleSeat.Torque` is never read.
- `TurnSpeed` clamps to 3.0 for every FOREST build, so stability has no
  effect on handling today.
- `OnServerInvoke` / `OnInvoke` cannot be read in Roblox, only assigned.
- Lune's `fs` is async: never read files inside mock-managed coroutines
  (the loader caches sources at boot for this reason).
