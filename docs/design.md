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

1. **A better build helps, but does not decide the race.** Everyone leaves
   the grid together at GO, and every car's top speed is within ±6% of the
   biome's (`Constants.RACE_SPEED`). Driving, pads, drift corners and
   abilities must be able to beat a better car. Measured by
   `speedPlaceCorr` and `fastestWinRate` (below).
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
| Length (centerline) | ~8,020 | ~6,530 | ~8,160 |
| Walls | wood, 8 high, continuous | reef rock, sea floor to 12 above water, continuous | see-through glass pillars 2×2, touching, Y 54–114, cloud rail |
| Off-track | mud slow zones | rough-water slow zones | none (kill plane below) |
| Sections | start straight, outcrop hairpin, trestle climb (Y 1 → 44, river bridge), giant tree spiral (1½ turns down, 28.7 studs per turn), run-out, mud hook, pine switchbacks, ridge chicane | harbor launch, island arc, open channel, lighthouse spiral (flume up 1¼ turns, Y 2 → 40), water slide (down to the sea, 6.2%) + lagoon run, reef hairpin + buoy slalom, kelp channel | launch tunnel, cloud bend A, crossover, cloud bend B, crystal canyon, cloud corkscrew (one turn up around the sky tower, Y 80 → 128), dive to the finish (Y 90) |
| Checkpoints | N14, S4b straight | N5, water slide | N6, N13 |

Wall layout rule (`TrackGeometry:boundaryRuns`): every wall is extended to
close the outside of a turn and dropped wherever it would stand inside the
lane — the inside of a turn. No track crosses itself: a crossing leaves the
fence open (Sky's old figure-8 did, and flyers slipped out there). A wall stretch that only exists past a corner is dropped too (it
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
| speedPlaceCorr | −0.6 to 0.1 | the build helps a little; it must not decide the race |

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

- **2026-10-20 — Steals and crafts checked with several players.** Found by
  the Studio farming scenarios: a defence tap sent before an attempt blocked
  it, one tap defended (3 are required), a thief could run several steals at
  once and two thieves could rob one victim inside its protection, and a full
  inventory dropped its weakest item before the pickup was confirmed. Craft
  submissions are validated (`Shared/CraftingRules`).
- **2026-10-20 — Vehicles look like a car, a boat and a plane.** Items used
  to be stacked on a box (a BODY item 4–5 studs across hid the vehicle; the
  boat's bow and the car's HEAD / TAIL were at the back). The shape is now
  data (`Modules/VehicleDesign`): car with wheels, hubcaps, bumpers, lights,
  windshield and cabin; boat with a V prow, gunwales, deck, deckhouse,
  outboard motor and (with a MOBILITY item) mast and sail; plane with
  propeller, canopy, wings, tailplane, fin and landing gear. Each item fills
  the box of its role (BODY = cabin / deckhouse / dorsal hump, ENGINE =
  engine bay / outboard / nose, MOBILITY = four hubcaps / masthead / two
  wing pods, SPECIAL = roof rack / foredeck / belly, HEAD = front, TAIL =
  back), scaled to fit with its proportions kept. The chassis is unchanged
  and the only part with mass, so handling does not depend on the look.

- **2026-10-21 — Everyone starts together.** Cars used to be seated one
  after another and each was released right after its own seat (~0.4 s
  apart, no countdown): with 6 players the last car left 2–3 s late. Now all
  cars are seated in parallel and held on the grid (`Modules/RaceStart`), a
  3-2-1 countdown runs to the server's GO time (`RaceGoAt`), and all are
  released in the same frame; the race clock, boosts and respawns start at
  GO. Studio, 5 bots: all left the grid in the same 0.5 s sample.
- **2026-10-21 — The build no longer decides the race.** Top speed was
  speed stat × 2.5 / 2.0 / 3.0: the fastest build was 1.8× the slowest and
  the field finished 50–60 s apart in build order. Now the stat only picks a
  place inside ±6% of a biome speed (`Constants.RACE_SPEED`, centers 69 /
  63 / 87 so the best build with a good driver wins in ~85 s). Simulated:
  winner 89 / 84 / 89 s, first → last 40 / 34 / 47 s, the fastest build won
  5 / 5 / 2 of 12. The `speedPlaceCorr` target moved from −0.85…−0.3 to
  −0.6…0.1.
- **2026-10-21 — Phase timers show the server's time.** GameManager
  publishes `PhaseEndsAt`; the farming and crafting timers count down to it
  (`Shared/PhaseClock`) instead of each counting its own default length
  (a 20 s harness crafting phase showed 2:00), and a UI script that starts
  late joins the running phase.
- **2026-10-22 — Item abilities work and can be seen.** E never fired in a
  real game (the client read a slot list nothing created), and the server
  took any item name. Now the car's BODY / ENGINE / SPECIAL items are on the
  model, the server refuses items that are not on the car and anything
  before GO, and E fires the next item that is off cooldown (the HUD shows
  which, with its cooldown). Every effect that lands on a car is drawn on
  that car for everyone (label, glow, particles, a beam from the car that
  caused it, a bubble for shields) and on the victim's screen. Lift
  abilities raise the ride height (`LiftOffset`); the old upward force moved
  cars less than 0.3 studs.

- **2026-10-22 — Cars hit each other.** The drive model sets every car's
  velocity each frame, so Roblox's own collision response vanished and a
  hit felt like touching a wall. The server now resolves every car-to-car
  contact as an inelastic collision (`Shared/CarImpact`: heavier cars push
  more, a hit near the nose or tail spins the car) and sends each driver a
  knock that fades (`Constants.IMPACT`), with a camera shake and a "💥" on
  hard hits. HEAD / TAIL passives adjust that push instead of adding their
  own BodyVelocity.
- **2026-10-22 — Drifting works.** Drifting used to only turn slower
  (× 0.35). Now turning is limited by grip at speed (`GRIP_LAT`), a drift
  turns tighter and slides (the travel direction lags the nose), and a
  slide of 0.6 s / 1.4 s pays a mini / super turbo on release. Forest's two
  switchback hairpins are each two tight 90° corners (R = 25) now. Offline:
  drifting saves a good driver 1–2 s per Forest lap; in Ocean's zigzags it
  only helps experts. Every car that slides smokes for everyone.
- **2026-10-22 — Items left on the track show the item.** Pizza, Gas Can,
  Magnifying Glass, Kettle, Cactus and Log drops are a copy of the item's
  model on the track surface with a warning ring and a label
  (`Modules/TrackDrops`); obstacle hitboxes are the model's size.
- **2026-10-22 — Sky looks like sky.** The fence of alternating neon
  pillars (60-stud stripes) is one even, see-through pale-blue barrier with
  a cloud rail; the road is cloud coloured with gold edge lines, cloud puffs
  line it, floating islands and balloons replace the neon crystal spires,
  and the lighting is daytime blue. Collision is unchanged (the same packed
  pillars; slabs left a pocket at the figure-8 crossings).
- **2026-10-22 — Start apron.** Forest and Sky have 24 studs of floor and a
  back wall behind the grid; cars nudged backwards at GO fell to the kill
  plane in Studio.

- **2026-10-22 — Fights in FARMING.** F punches the player you face (6
  studs, `Constants.FIGHT`); 4 landed hits within 4 s of each other knock a
  random item onto the ground for anyone to grab, then the victim is immune
  for 4 s. Holding G guards (blocks punches, walks at half speed, at most
  3 s). Steals stay (hold E, the victim taps E three times) but now show:
  the thief reaches, the victim wriggles and swats, and the victim gets a
  big on-screen prompt (it was a console print). Every client animates
  fights by rotating shoulder / waist joints (`StarterPlayerScripts/FarmFx`,
  R6 and R15).
- **2026-10-22 — Screens no longer pile up.** StarterGui scripts run again
  after each respawn; screens kept across respawns (`ResetOnSpawn = false`)
  were created again each time, so Studio bots saw two or three crafting
  timers. Every such screen now removes its old copy (`tests/specs/ui`).

- **2026-10-22 — Crafting balance from simulation.** `tools/balance.luau`
  measured every item. Before: an Epic ENGINE + SPECIAL was worth ~25 s of a
  100 s race (Rocket ×3 bursts, an 8 s boost), Rare / Epic bodies were the
  worst (weight was × rarity by mistake), Red Sofa and Suitcase stopped their
  own car, Toilet Paper (Common) cost a rival 12 s. Now: rarity × 1 / 1.15 /
  1.3 / 1.5; boost 1.6 s + 0.01 s per point (≤ 3.6 s); top-speed band ±1.5%;
  OCEAN / SKY turn ranges narrow (turning decides those races); bursts sized
  by (multiplier − 1) × duration × uses ≈ 2–4 s per race; lifts glide ×1.1–1.2;
  speed buffs stack to ×2 at most. Result: each tier is worth more than the
  one below, Epic − Common ≈ 1–4.5 s per slot, no item is in more than ~20%
  of winning builds, the rarest build of a field wins about half the time.
- **2026-10-22 — Less waiting.** FARMING starts with 12 + 6 × players items
  and drops two waves of rarer items at 35% and 65% of the phase (100 items
  for 4 players filled every inventory in 15–50 s of 90). CRAFTING: once half
  the players have submitted, the rest get 25 s (40 s since 2026-10-23, below). RACING: the winner's finish
  leaves the others 45 s (a HUD countdown; was 30 s, raised with the longer
  climbing / spiral tracks), then non-finishers are listed as
  DNF (a timed-out race used to show nobody).
- **2026-10-23 — Time to think in CRAFTING.** Bots cannot measure how long
  a person deliberates, so it was estimated with a keystroke model: read 8
  cards, ~4 s per slot (decide, click item, click slot), weigh the core
  slots, submit — an experienced player ~35–50 s, a first-timer 60–90 s
  (cards showed only icon and name). The 25 s hurry cut first-timers off
  around 65 s and the timeout auto craft threw their picks away. Now: the
  hurry gives 40 s; the crafting screen sends the arrangement on every change
  (`CraftDraft`) and the timeout craft keeps it, filling only empty slots
  (`CraftingRules.autoSlots`, also behind the Auto fill button, which used
  to put items in inventory order and lose core slots); each card shows its
  slot type, and pointing at or picking an item shows what its E ability
  does (`Shared/ItemBlurbs`). Studio `craft-afk-3p` has a "slow" bot that
  places items and never submits (`draftKept`).
- **2026-10-23 — Fight animations were invisible.** FarmFx posed arms by
  rotating Motor6D C0, but Roblox avatars now use AnimationConstraint joints
  (no Motor6D), so every punch, guard, grab and swat pose did nothing while
  the harness check ("a character exists") passed. Poses now rotate the
  joint's parent-side attachment on those rigs; the check measures the arm.
- **2026-10-24 — Bots fill the grid.** A lone player used to race alone.
  With fewer than 4 racers, server-driven bots (mostly average drivers, one
  expert, random builds) take the empty slots, race with the same driver
  and rules, and appear in the results; they earn nothing but do take
  places. They skip FARMING and abilities ignore them for now.
- **2026-10-24 — Show-off items.** Special rides (Flame Rider, Neon Phantom,
  Rainbow Comet, Golden Legend, 1000–3000 coins, level 4–10) turn the whole
  car / boat / plane into a show that pours particles while driving; still
  no mass, same seat values. Farming extras stay fair: the Flying Kick is a
  punch with a kick's look, the Smoke Bomb one 3.5 s escape per round.
  Coins can also come from Robux packs, so a gadget must never be a weapon
  (it would be pay-to-win). Simulated: a daily player saves for a ride in
  5–12 days, a casual one in 2–4 weeks.
- **2026-10-23 — Catch-up and a longer grace after a slow winner.** A fast
  winner (92 s) left the novice 170 studs short of the line when the flat
  45 s grace ran out. Cars 60+ studs behind the leader now get up to +12 %
  top speed (full at 400 studs); the leader never does. The grace is half
  the winner's time, 45–75 s. Simulated spread: Forest 20 → 18 s, Ocean
  14 → 10 s, Sky 37 → 33 s; winner times unchanged. Studio: Forest and Sky
  4 / 4 finished. The offline sim now also applies the grace cut (it let
  every car finish before).
- **2026-10-23 — Late joiners watch.** Someone joining during a race is
  marked Spectating (banner: "you join the next round"), is not in the
  results and is not waited for; everyone plays from the next FARMING. A
  pickup contest locks its item, and if the winner left, the other player
  gets it.
- **2026-10-23 — A shop for looks.** Coins buy paints and trails (some need
  a level, so levels mean something); Robux coin packs are ready but sold
  only once their product ids are set. Nothing in the shop changes speed,
  turning or abilities.
- **2026-10-23 — Where players drop off.** Retention numbers come from the
  Creator Dashboard; the game adds funnels (first session and every round),
  coins, levels and the day a player came back on, so a low D1 can be
  traced to a step (e.g. many join but few finish their first race).
- **2026-10-23 — Saved levels and coins, a daily streak.** Before launch
  there was no reason to come back: nothing was saved. Every round now pays
  XP and coins by place (a DNF still earns the play reward, so a last place
  is not wasted), the first round of a day pays a bonus that grows with a
  streak of days (up to 7), and Level / Coins show on the player list.
  Coins are for cosmetics only (the build must not decide the race).
- **2026-10-22 — Nobody falls off after the finish.** A finished car is parked
  (MaxSpeed 0, no respawns); the road runs 150 studs (Sky 220) past the line
  to an end wall. In Studio the winner ran off the 50-stud run-off and fell
  again and again.
- **2026-10-22 — Obstacles that look like obstacles.** Falling logs are round
  trunks with bark, cut ends and moss, marked by a red ring 1.2 s before they
  drop, lying still where they land with a gap always open; mud is a dark wet
  patch with puddles (was a see-through brown box). Hitting either knocks the
  car through `CarImpact` (a second BodyVelocity did nothing). All effect and
  notice text is English.
- **2026-10-22 — Roads that climb and spiral.** A node may carry the road
  height ({ x, z, y }). FOREST climbs a wooden trestle through S3 (Y 1 → 44,
  3.7%) and winds down 1½ turns around a giant tree (R 90, 5.1%), each turn
  28.7 studs over the one below; it replaces the flat farm U-bend. Everything
  that asks "where on the track is this car" passes the car's Y
  (`TrackGeometry` layers, `LAYER_GAP` 10), walls of one layer are kept over
  the lane of another, a car more than 12 studs under the road respawns
  ("fell"), logs never drop under a higher turn. Studio found the suspension
  ray resting on the Sky map's haze planes (Y 28–34, same XZ) once the road
  went below them: suspension and drop rays now count only collidable parts.
- **2026-10-22 — Sky corkscrew.** The 1000-stud final straight becomes a
  corkscrew: one full turn (R 160) around a sky tower, climbing 48 studs so
  the top passes over its own start, then a dive to the finish (Y 90).
  The fence stands on a raised road (not 26 studs below it), the invisible
  lid is one part per segment 40 above the road (one sheet over the map
  would cap the upper turn), and the round road joints are tilted to the
  slope (flat, they stood 1.2 studs proud going uphill). FINISH_GRACE
  30 → 45 s (= FUN_TARGETS finishSpread): on the longer tracks a novice is
  30-40 s behind the winner. Studio: escape cases spawned up a raised road
  shot to the lid (the held height got the rise twice): `RaceSim` now calls
  `resetRide` on spawn.
- **2026-10-22 — Ocean flume.** A white water flume winds up 1¼ turns
  around a lighthouse (Y 2 → 40, each turn 30 studs over the one below, the
  top turn also over the end of S3) and slides back down to the sea,
  replacing the reef U-bend and the return zigzag. Boats hold a height above
  the water instead of riding the ground, so that height now follows the
  road (`VehicleController.apply{ roadRise }`, `RaceProgress.roadRise`,
  `resetRide` on respawn; buoyancy uses the flume's water). A raised
  stretch's walls stand on the road (`TrackKit.RAISED_WALL_DROP`), not down
  to the sea floor where they hung into the turn below.
- **2026-10-22 — Sky without crossings.** The two 360° loops met their own
  entry (a fork, and an open fence where the novice slipped out); they are
  now 270° / 225° bends forming an S. A map spec fails any track that meets
  itself on one layer.

## Open questions (from the reports, not decided)

Simulated matches (12 per biome, 6 bots, `reports/<biome>/summary.md`):

| | Forest | Ocean | Sky | Target |
|---|---|---|---|---|
| Winner time | 89 s | 84 s | 89 s | 60–120 s |
| Share of the round spent racing | 35% | 33% | 36% | ≥ 35% |
| Spread first → last finisher | 40 s | 34 s | 47 s | ≤ 45 s |
| Lead changes per race | 1.6 | 1.3 | 2.1 | ≥ 1 |
| Top two within 40 studs | 17% | 19% | 23% | ≥ 25% |

- With the narrow speed band the remaining spread is driving: the novice
  bot is 20–40 s slower than the expert in the same car. If playtests want
  the field closer still, the next step was a catch-up for cars far behind
  the leader: built 2026-10-23 (Shared/CatchUp).
- Close racing is low everywhere, but the simulation has no car-to-car
  contact or abilities; check with playtests (M / N markers) before acting.
- Drift turbos are tuned on the offline driver; how often players drift,
  and whether the turbo is worth it, needs playtests.
