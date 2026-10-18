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
| Length (centerline) | ~4,420 | ~3,180 | ~7,580 |
| Walls | wood, 8 high, continuous | reef rock, sea floor to 12 above water, continuous | crystal pillars 2×2, touching, Y 54–114 |
| Off-track | mud slow zones | rough-water slow zones | none (kill plane below) |
| Sections | start straight, outcrop hairpin, river sweeper, farm U-bend, mud hook | harbor launch, island arc, open channel, reef U-bend, return zigzag | launch tunnel, loop A, crossover plaza, loop B, crystal canyon, final descent |
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

## Open questions (from the reports, not decided)

Simulated matches (12 per biome, 6 bots, `reports/<biome>/summary.md`):

| | Forest | Ocean | Sky | Target |
|---|---|---|---|---|
| Winner time | 47 s | 43 s | 94 s | 60–120 s |
| Share of the round spent racing | 25% | 23% | 38% | ≥ 35% |
| Spread first → last finisher | 35 s | 30 s | 50 s | ≤ 45 s |
| Lead changes per race | 1.1 | 1.5 | 2.9 | ≥ 1 |
| Top two within 40 studs | 12% | 22% | 24% | ≥ 25% |

- Forest and Ocean races are short (~45 s vs ~90 s). Lengthen the tracks,
  or lower top speeds?
- Racing is a quarter of a round on Forest and Ocean (farming 90 s +
  crafting 120 s + results 30 s). Shorten crafting?
- Sky's last finisher arrives 50 s after the winner; the slowest car with a
  novice driver needs ~170 s of the 180 s limit.
- Close racing is low everywhere, but the simulation has no car-to-car
  contact or abilities; check with playtests (M / N markers) before acting.
