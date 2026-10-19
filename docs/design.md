# Design notes

What the game is trying to be, how each track is laid out, how "fun" is
measured, and the decisions behind the current state. Keep this short and
current: when a decision changes, edit the entry and add a dated line to the
log at the end.

## What the game is (from README)

- A round is **Farming → Crafting → Racing → Results**, up to 10 players.
- You build your vehicle from ordinary objects you collected; item rarity and
  biome affinity decide its stats. Contests and steals make farming social.
- Each biome has its own vehicle and physics: car (Forest), boat (Ocean),
  flyer (Sky).

Principles the code follows (keep them when changing things):

1. **A better build helps, but does not decide the race.** Driving, pads,
   drift corners and abilities must be able to beat a better car.
   Measured by `speedPlaceCorr` and `fastestWinRate` (below).
2. **Nobody gets stuck.** Every simulated driver profile finishes every map;
   respawns land on the centerline facing along the track.
3. **What you see is what collides.** No invisible walls, no props in the
   lane, no holes in walls, triggers span the whole lane.
4. **Data, not code.** Track layout and tunables live in data files
   (`Shared/Tracks/*`, `Shared/Constants.lua`); builders only turn data into
   parts.

## Tracks

All three are built by `ServerScriptService/Modules/Maps/TrackKit.lua` from
`ReplicatedStorage/Shared/Tracks/<Biome>Track.lua`; the biome builders add
only scenery. Current shape: `reports/<biome>/track.svg`.

| | Forest | Ocean | Sky |
|---|---|---|---|
| Lane width | 40 | 60 | 50 |
| Length (centerline) | ~7,610 | ~5,950 | ~7,580 |
| Walls | wood, 8 high, continuous | reef rock, sea floor to 12 above water, continuous | crystal pillars 2×2, touching, Y 54–114 |
| Off-track | mud slow zones | rough-water slow zones | none (kill plane below) |
| Sections | start straight, outcrop hairpin, river sweeper, farm U-bend, mud hook, pine switchbacks, ridge chicane | harbor launch, island arc, open channel, reef U-bend, return zigzag, reef hairpin + buoy slalom, kelp channel | launch tunnel, loop A, crossover plaza, loop B, crystal canyon, final descent |
| Checkpoints | N14, N19 | N5, N17 | N8, N18 |

Wall layout rule (`TrackGeometry:boundaryRuns`): every wall is extended to
close the outside of a turn and dropped wherever it would stand inside the
lane — the inside of a turn and Sky's figure-8 crossings at (0, 800) and
(0, 400). A wall stretch that only exists past a corner is dropped too (it
would poke out of the next wall as a spur).

## Fun as numbers

`Shared/RaceMetrics.lua` scores a race; the same code runs on simulated
matches (`tools/report.luau`, "Fun metrics" in `reports/<biome>/summary.md`)
and on real Studio playtests (`Modules/PlaytestReport`, printed at RESULTS).
Targets are in `Constants.FUN_TARGETS`. They are starting points: change
them when playtests say the game feels better somewhere else.

| Metric | Target | Meaning |
|---|---|---|
| winnerTime | 60–120 s | a race takes about 90 s |
| finishRate | ≥ 0.9 | almost everyone finishes |
| finishSpread | ≤ 45 s | nobody waits long for the last car |
| leadChanges | ≥ 1 | the lead changes at least once |
| closeShare | ≥ 0.25 | the top two race each other a quarter of the time |
| racingShare | ≥ 0.35 | share of a round spent racing |
| fastestWinRate | ≤ 0.7 | the fastest build does not always win |
| speedPlaceCorr | −0.85 to −0.3 | a better build helps, but is not everything |

Per section the report gives mean time, the spread between racers (where
races are won or lost), respawns, wall hits and playtest markers.

**Playtest markers.** In Studio (or a server with
`ReplicatedStorage:SetAttribute("PlaytestMarkers", true)`), press **M** where
something feels frustrating and **N** where it feels fun. The server logs the
spot with its track section; the RESULTS report lists them per section.

## Decision log

- **2026-10-18 — Walls are continuous on every map.** Forest and Ocean used
  to have 8-stud doorways every 48 studs (a risky shortcut into the slow
  zone); in Studio they read as broken walls. `wallGapHalfWidth = 0` in the
  track data; set it back to 4 to restore doorways.
- **2026-10-18 — Ocean walls reach the sea floor.** They used to stop at the
  waterline and looked like they were floating in the see-through water.
- **2026-10-18 — Ocean finish moved to Z −1530**, onto the straight after
  the last zigzag corner; on the corner, the finish poles stood in the lane.
- **2026-10-18 — Sky handling uses flyability.** Every build turned at the
  controller cap (1.5 rad/s); flyability now maps onto 1.0–1.5.
- **2026-10-18 — Contests end on time.** A contest used to wait for one more
  button press after its time ran out; if both players walked away, the item
  stayed locked for the round.
- **2026-10-18 — Forest S5 redesigned** as arcs (old ±105°/118° kinks trapped
  cars); MapVisibility no longer turns triggers into invisible walls.

- **2026-10-20 — Forest and Ocean are longer.** Winners took ~45 s (target
  60–120 s). New sections after the old finish: Forest S6 pine switchbacks
  (two 180° hairpins) and S7 ridge chicane; Ocean S6 reef hairpin and buoy
  slalom, S7 kelp channel. Every earlier feature kept its coordinates; the
  finish moved (`finishX` / `finishZ` in the track data). Simulated winner
  time is now 81 s (Forest) and 76 s (Ocean). The race failsafe
  (`Constants.RACING_TIMEOUT`) went from 180 to 240 s: the slowest build with
  a novice driver needs ~180 s.
- **2026-10-20 — Forest suspension probes nose, centre and tail.** With the
  centre ray only, cars in real Roblox physics drove into the jump ramps and
  stopped (0 of 4 bots finished a Studio match); the offline sim does not
  model ramps, so only the Studio harness saw it.
- **2026-10-20 — Terrain is painted for the played biome only**
  (`Modules/TerrainPlan`, kept out of every lane). The old script painted
  whichever map was built last, with hills in the new lanes.
- **2026-10-20 — Ocean start dock is decoration** (no collision); boats float
  with their hull below its top and were pinned on the grid.

## Open questions (from the reports, not decided)

Simulated matches (12 per biome, 6 bots, `reports/<biome>/summary.md`):

| | Forest | Ocean | Sky | Target |
|---|---|---|---|---|
| Winner time | 81 s | 76 s | 94 s | 60–120 s |
| Share of the round spent racing | 37% | 35% | 38% | ≥ 35% |
| Spread first → last finisher | 60 s | 51 s | 50 s | ≤ 45 s |
| Lead changes per race | 1.5 | 1.5 | 2.9 | ≥ 1 |
| Top two within 40 studs | 14% | 12% | 24% | ≥ 25% |

- The last finisher arrives 50–60 s after the winner on every map now that
  the races are long enough. The spread comes from builds (top speed 33–75
  on Ocean), not the tracks. End the race N seconds after the winner, or
  narrow the speed range?
- Close racing is low everywhere, but the simulation has no car-to-car
  contact or abilities; check with playtests (M / N markers) before acting.
