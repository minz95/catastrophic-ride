# Catastrophic Ride — notes for AI agents

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
  turns). No track crosses itself (a crossing leaves the fence open; SKY's
  old figure-8 let flyers slip out there). `wallGapHalfWidth` > 0 adds doorways
  (currently 0 everywhere: continuous walls).
- Look of a map or a drop without Studio: `tools/scene_dump.luau` +
  `tools/scene_render.py` (PNG). Layout and where simulated drivers
  slip out: `lune run tools/topview.luau <BIOME>` + `python3 tools/topview.py
  reports/<biome>/topview.json` (top-down PNG, respawns marked). Drift timing: `tools/drift_sim.luau`.
- Studio runs are heavy: one small batch at a time, never in parallel with
  another Studio run or the full offline suite.
- Vehicle look: `Modules/VehicleDesign.lua` (car / boat / plane as data:
  parts, slot boxes for the crafted items), built by `Modules/VehicleBuilder`.
  Only the chassis has mass and collision, sized from the stats as before, so
  the look never changes handling. Check a change with
  `lune run tools/vehicle_gallery.luau` (`reports/vehicles/*.svg`, front on
  the left) and `python3 tools/studio/sim.py run vehicles`.
  You ride your BODY item: with one, `VehicleDesign.layout(biome, stats,
  slots)` hides the chassis and body parts (`ride.hide`) and the item is
  stretched over the footprint (at least `VehicleDesign.RIDE_MIN`, so the
  rider does not hide it; wheels / motor, mast and sail / wings, prop and
  tail stay); seat and `onRide` mounts sit on the item's real top.
  `VehicleDesign.RIDE_LOOK` fixes items that ride wrong by default (facing,
  lying down, seat sunk into a tub or onto cushions). Some ENGINE / SPECIAL
  items are rideable too (ItemConfig `ride` = weight and grip as a body;
  `CraftingRules.fits`). See every rideable item as car, boat and plane with
  an avatar seated: `python3 tools/studio/sim.py run gallery` (side and rear
  shots in `reports/vehicles/studio/`, git-ignored: the whole screen; the
  view cropped out of them as contact sheets in `reports/vehicles/gallery/`,
  safe to commit; the screen must be awake and unlocked).
  The HEAD item is the rider's hat (`VehicleDesign.HAT`): built over the
  seat at a seated avatar's head height, moved onto the real head by
  `VehicleBuilder.wearHat` when someone sits (seat Occupant), back by
  `takeOffHat`; the showroom puts it on the avatar copy. A worn hat takes
  the head's Anchored (an anchored hat stays behind when the head moves).
  Quick look: `sim.py run gallery-hats` (report `hats`: offset from the
  head top).
  The MOBILITY item spins where it moves you: the car's four wheels (flush
  with the wheel's outer side, on axles), a boat's side paddle wheels
  (copies round a hub), a propeller in front of each wing nacelle. Mounts
  or parts with `spin` (plain car wheels, the plane's nose propeller too)
  hang on an invisible hub jointed to the chassis by a Motor6D "Spin";
  `StarterPlayerScripts/SpinFx` turns the joint's C0 on every client (never
  the server). The showroom turns them itself (CraftPreview tags each part
  with its hub, attribute SpinHub). Riding, `VehicleDesign.fitRide` moves wheels,
  paddles and propellers against the item's measured box, with axles and
  posts. The boat's mast stands near the bow and the sail runs back to
  just before the deckhouse, sheeted out `VehicleDesign.SHEET` degrees.
  Check: `sim.py run gallery-mobility` (close-ups, report `loose` = parts
  not touching what carries them; the spec checks the same offline);
  the match checks `spin` count cars whose items turned.
  Boats race with the chassis 1 stud over the water (`VehicleDesign.
  WATERLINE`, checked against BiomeConfig): the hull's Keel / ProwSkirt,
  a ridden item's wooden Float, the paddles and the motor leg reach DRAFT
  into it, or the boat and its rider look to hover. A ridden item's seat
  goes down onto its real surface (rays at the collision shape:
  `surfaceUnder`, not the box top of a treadmill's handle or a duck's
  head), up to `SEAT_INTO_CHASSIS` into the invisible chassis. The gallery
  reports `fit.gap` (seat above that surface; > 0.1 floats) and draws the
  water under each boat; `sim.py run gallery-rides` = close-ups of a few.
  Riding, the outboard motor / ENGINE item (flush on the stern, standing on
  the motor leg) and the flag move to the item's back end; the gallery's
  `loose` and the spec check they touch the hull, item or float.
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
- Abilities (E): the server checks the item is in the car's BODY / ENGINE /
  SPECIAL slot (`Shared/AbilitySlots`; VehicleBuilder writes them on the
  model as attributes, RacingClient reads them there) and that the race has
  gone. Every effect that lands on a car calls `Modules/EffectFx.play(key,
  player, ...)` just before it applies: all clients draw it on that car
  (`Shared/EffectLook` + `StarterPlayerScripts/EffectFx`) and the Studio
  harness measures it. A new effect needs an `EffectLook.CAR` entry; a new
  `ScreenEffect` name needs an `EffectLook.SCREEN` entry or a handler.
  Floating words (cars and FarmFx avatars) take their size from
  `EffectLook.TEXT`, one per car (bigger ones overlapped side by side).
- Lift abilities set the chassis attribute `LiftOffset` through
  `Modules/VehicleLift`; an upward BodyForce cannot beat the ride-height
  BodyPosition. Never tween or set a race car's CFrame from a client.
  SKY updrafts (columns on the lane, `SkyTrack.updraftZones`) lift the same
  way (`Constants.UPDRAFT`, once per pass, players and race bots; telemetry
  `updraft`). They used to push with a BodyForce, and two stood 440 studs
  off the lane: they did nothing.
- Car-to-car hits: `RacingManager` resolves every contact with
  `Shared/CarImpact` and sends each driver `RemoteEvents.CarImpact`;
  `VehicleController.knock` adds it to the drive state. Never push a race
  car with a second BodyVelocity (it fights `DriveVelocity`).
- Drift: one rule, `VehicleController.updateDrift`, for RacingClient,
  RaceSim and the offline sim. While sliding the car travels along
  `state.travelYaw`, so `actualForward` must be measured along
  `VehicleController.travelDir`, not the nose (else the blocked-car clamp
  kills the speed). Mini-turbos are applied by the server (`DriftTurbo`).
- Boost (F): the server keeps the gauge (`Modules/BoostGauge`, full at
  the start, two DriftCorner zones refill it, Backpack fills it) and
  `RequestBoost` needs it full; the client's bar only mirrors it. Race bots
  use the same gauge and boost when going straight with no bend within the
  boost's reach (`Constants.BOTS.RACE.BOOST_*`). The harness player used to
  boost every 5 s on cooldown alone and won every match.
- Ability drops go through `Modules/TrackDrops` (item model on the ground,
  ring, label, hitbox the model's size).
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
  only take their own item type, BODY also an item with `ride`; the rest is
  dropped and logged). The
  crafting screen (`StarterGui/CraftingUI`; `CraftingClient` is not shown)
  sends `CraftDraft` on every change; at the timeout the auto craft keeps the
  draft and fills the rest with `CraftingRules.autoSlots`. Each draft also
  builds a still copy of the vehicle into that player's
  `PlayerGui.CraftPreview` (`Modules/CraftPreview`, the race's
  VehicleBuilder call), which the crafting screen's showroom turns in a
  ViewportFrame with the avatar seated (`sim.py run showroom` screenshots it). A new item needs
  a line in `Shared/ItemBlurbs`.
- Character poses (FarmFx): avatars may have AnimationConstraint joints and
  no Motor6D; pose through FarmFx's `joint()` handle, never `Motor6D.C0`
  alone.
- Fights (FARMING): `FarmingManager` RequestPunch / SetGuard with the
  pure rules in `FarmingRules.canPunch` / `punch`; knock-outs drop through
  `_dropItem` (reason "knocked_out"). Every fight or steal step is
  broadcast as `RemoteEvents.FarmAction` and drawn by `FarmFx` for all.
- Ability strengths are data in `AbilityConfig` (selfSpeed, victimSpeed,
  push, …); `tests/lib/balance.luau` reads the same numbers. After changing
  items, stats or abilities run `lune run tools/balance.luau` and keep
  `Constants.BALANCE_TARGETS` green. Speed buffs stack to `SPEED_STACK_MAX`.
- Shoves (abilities, obstacles) go to the driver as a `CarImpact` knock.
- Jumps (FOREST): `VehicleController` flies the car an arcade arc
  (`Constants.DRIVE.JUMP`: up at VY under a lighter GRAVITY, attribute
  "AirT") when the ground under it drops MIN_DROP at once at speed (a
  ramp's lip); `resetRide` ends a jump. Probes ahead also start
  RAMP_PROBE_RISE higher and count only on parts named `JumpRamp_*`, plus
  RAMP_CLEARANCE over them: a ray from the centre started inside the ramp,
  the car hit it and lost half its speed. Studio `race-forest` reports
  `jumps` (approach / launch / landing speed, height, air time, landedOn).
  Gap jumps: track data `gapJumps` (FOREST: one on the S3 climb, ~28 up).
  `TrackKit:buildSurface` cuts the road there, `buildGapJumps` lays the
  spring pad ("SpringPad_<i>", attributes VY / MinSpeed); a car whose
  probes saw a pad launches at its VY and keeps MinSpeed in the air.
  Falling in is a normal "fell" respawn, and `RaceProgress.respawnPoint`
  puts it GAP_RUNUP before the pad. Logs keep off it (`HazardPlan`).
  Checked by `tests/specs/gap_jump` (no floor in the gap, pad, the arc
  clears it with 40 % to spare, respawn before the pad).
- Falling-log spots come from `Shared/HazardPlan` (always a way past);
  `Autopilot` avoids `state.hazards`. Jump ramps span the whole corridor (a
  narrower wedge's side face snagged cars near the wall). Race bots respawn
  after `BOTS.RACE.STUCK_RESPAWN` s pinned and fire no abilities below
  `MIN_SPEED` (a drop lands in their own way after a respawn).
- Road heights: a track node may be `{ x, z, y }` (road surface Y). Pass
  the car's Y to `TrackGeometry:project` / `progressAt`,
  `RaceProgress.progress` / `respawnPoint` and `Autopilot` state, or a
  road passing over itself (FOREST's spiral) is read on the wrong layer.
  Build things on the road with `TrackKit:segCF` / `trackCF` (they follow
  the height). Suspension rays use `RespectCanCollide = true` (track drops
  do not: OCEAN's water is not solid). Boats (OCEAN) and flyers (SKY)
  hold a height: pass `roadRise = RaceProgress.roadRise(...)` to
  `VehicleController.apply` and call `VehicleController.resetRide` after
  moving a car. A raised stretch's walls / fence stand on the road
  (`TrackKit.RAISED_WALL_DROP`); SKY's lid is per segment
  (`TrackKit:buildCeiling`).
- Phase timers: `GameManager.shortenPhase` (crafting hurry, finish grace).
  A finished car is parked (MaxSpeed 0) and may not respawn; each road has a
  run-off and an end wall (`TrackKit:buildEndWall`).
- Sounds: ids in `Shared/SoundConfig` (only APM / ProSoundEffects /
  DistroKid catalogue ids, which Roblox licenses for every experience),
  played through `Shared/SoundFx.play(key)`; check new ids with
  `python3 tools/studio/sim.py run sounds`.
- Saved progress: `Modules/PlayerStore` (DataStore) holds each player's
  record; `Shared/Progression` the rules (levels, coins, daily streak);
  `ProgressionManager` pays at RESULTS (`RemoteEvents.RewardGranted`,
  leaderstats). A failed load is never saved; bots, harness sessions and
  Studio without API access stay in memory. Add record fields in
  `Progression.newRecord` (migrate fills them in for old saves).
- Analytics (live servers only): `AnalyticsManager` turns Telemetry events
  (`Telemetry.onRecord`) into Roblox AnalyticsService events through
  `Modules/Analytics` (onboarding funnel, "Round" funnel, coins, levels,
  `ReturnDay`). Retention itself is on the Creator Dashboard. A new step:
  record a Telemetry event, map it there; check engine names with
  `python3 tools/studio/sim.py run api-analytics`.
- Shop: looks only (`Shared/Cosmetics`: paints recolour VehicleDesign's
  body / accent roles, trails hang on the chassis; no mass or collision).
  `Modules/Shop` buys / equips over the saved record and grants Robux coin
  packs (`Shared/Products`, ids from the Creator Dashboard; 0 = not sold)
  once per PurchaseId and only after the save succeeded.
  `VehicleBuilder.build(…, look)` takes `Cosmetics.look(rec.equipped)`.
  Special rides (`ride`) add material, glow and particles whose Rate the
  client sets from forward speed (`CosmeticFx`, attribute BaseRate). Moves
  only change the punch's look (`style`); gadgets (Smoke Bomb) are one use
  per round (`Constants.GADGETS`, `RemoteEvents.UseGadget`, key T).
  Prices vs earnings: `lune run tools/economy.luau` (reports/economy.md).
  The shop screen (ShopUI, B) opens in every phase but RACING; a buy or
  equip rebuilds the crafting showroom (`CraftPreview.refresh`). It shows
  the phase clock and closes itself when a round starts, for the race and
  once `Constants.SHOP.CRAFT_CLOSE_AT` s before the car is built
  (`Shared/ShopTiming`; the draft is kept either way). Studio: `sim.py run
  shop-ui`. Live lobby: `Constants.LOBBY` (15 s once two players are in).
- Who races: everyone present when RACING starts except players with the
  `Spectating` attribute (joined during RACING / RESULTS); whoever still has
  no car at GO becomes a spectator. Never count cars at the RACING
  transition: CraftingManager builds them just after it. A running pickup
  contest locks its item for its two players.
- Racers stay in their car: RacingClient turns the humanoid's Jumping state
  off during RACING (Space on a seated humanoid leaves the seat whatever
  its JumpHeight), and `Modules/RaceSeat` (RacingManager, every
  `Constants.RACE_SEAT.CHECK_EVERY`) seats a racer who is out of it again,
  reloads a dead one at once and re-sends VehicleSpawned after a respawn
  (telemetry `reseat`; Studio `eject-ocean`). StarterGui scripts restart on
  a respawn: the HUD turns itself back on when Phase is RACING.
- Race bots have a driver: `Modules/SeatedRider` (also the gallery's rider)
  seats a massless, non-colliding avatar in the bot's car (`Rider`).
- OCEAN's water is Terrain water (`TerrainPlan.WATER`, painted with the
  biome), not parts: race and drop rays set `IgnoreWater = true` (it is
  not ground; boats hold their height). A drop at sea floats at
  `BiomeConfig.waterPlaneY` (+ flood offset) unless a dock is higher
  (`TrackDrops` groundY). waveFlood raises a see-through
  `FloodSurface` sheet only while the sea is up.
- Farming keys: E grab, hold E steal (`Constants.STEAL_HOLD`, starts while
  held, label over the target), F / left click punch, hold G guard, X drop,
  hold Q emotes, B shop. TutorialUI keeps the phase's keys on screen (`KeyStrip`),
  H / F1 opens all. RACING shows no guide toast: the keys are on the
  strip, the objective and tips in RacingClient's RACE START banner under
  the 3-2-1 (the three used to pile up mid-screen).
- Input: gameplay clients take keys through `Shared/KeyInput.began / ended`
  (keyboard, gamepad map, on-screen `TouchControls` buttons), never
  `UserInputService.InputBegan` directly. Touch / gamepad driving comes from
  the seat's ThrottleFloat / SteerFloat (RacingClient). Live-server
  switches and the store page: `docs/launch.md`.
- Catch-up: `Shared/CatchUp` (RacingManager "catchUp" MaxSpeed multiplier
  for cars far behind the leader, never the leader; finish grace
  `CatchUp.graceFor(winner)`). The offline match sim uses the same rules
  (second pass + grace cut); compare with `lune run tools/catchup_compare.luau`.
- Race bots (`Modules/RaceBots`): live servers fill the grid to
  `Constants.BOTS.FILL_TO` with server-driven cars (Autopilot +
  VehicleController, hazards via `Shared/RoadHazards`, same catch-up).
  RacingManager counts them as racers; finishOrder entries have `bot = true`
  and a negative id (ProgressionManager pays only players, but bots take
  places). Harness sessions get bots only with `fillBots`. Grid slots:
  `Modules/RaceGrid`.
- Bots are SessionManager proxies (`SessionManager.addBot`, `bots()`,
  `actors()` = players + bots, `actorById`, `isBot`): a table with UserId,
  Name, isBot, Character. They first farm as NPCs (`Modules/FarmBots`,
  `Constants.BOTS.FARM`) through FarmingManager's own pickup / contest /
  punch / guard / steal / defend functions (they keep a bag slot free to rob
  someone), then race the auto craft of their bag and fire its abilities
  through AbilityManager's handler (`RaceBots.setAbilityHandler`,
  `Constants.BOTS.RACE`). Loop over
  `SessionManager.actors()` where bots take part (targets, contests), and
  never FireClient to a bot (FarmingManager `_fireClient`, AbilityManager
  `_screen`; shoves go to `RaceBots.knock`). Clients find a bot's NPC by the
  tag "FarmBot" and attribute BotUserId.
- Item models: the FBX items are imported in Studio into the published
  place's ServerStorage; `python3 tools/studio/item_meshes.py` copies them
  into `Modules/ItemMeshData` (mesh / texture ids), from which
  `ItemModelPreloader` builds them in any place without an import
  (`AssetService:CreateMeshPartAsync`). Item and car models are
  `ModelStreamingMode.Atomic`.
- Streaming is off (`Workspace.StreamingEnabled = false` in the Rojo
  project): with it on, multi-part item models arrived part by part (looked
  broken) and clients stalled after teleports. Rojo test places never had it.
- Drops (`FarmingManager._dropItem`) land `Constants.DROP_TOSS` studs ahead of
  the dropper and are broadcast as FarmAction "drop" (FarmFx throws the item
  in an arc).
- Player-facing text is English.
- A ScreenGui with `ResetOnSpawn = false` must destroy its old copy at the
  top of its script (the script runs again on every respawn).
- Timed things end on a timer, not on the next client message (contests used
  to wait for one more press and locked items for the round).
- `MapVisibility.restore` must keep a stored `false` (the old
  `x ~= nil and x or true` idiom turned trigger volumes into invisible walls).
- `OnServerInvoke` / `OnInvoke` cannot be read in Roblox, only assigned.
- Lune's `fs` is async: never read files inside mock-managed coroutines
  (the loader caches sources at boot for this reason).
- The offline race sim moves a point at 60 Hz; gates are tested along each
  step's move (a fast car can cross a thin trigger between two steps).

## Release

`docs/launch.md` is the release-day runbook (sync with Rojo into the
published place, publish, Creator Dashboard settings, store page). Store
pictures: `python3 tools/studio/sim.py run promo` (TestHarness/Promo, real
maps and lighting) → `assets/store/`. Chat is the new TextChatService (set
in the Rojo project; the legacy chat scripts errored in Studio clients).
A published place ignores a leftover `HarnessArgs` attribute
(`HarnessConfig`, lobby spec).

Trailer videos: `python3 tools/studio/sim.py run record-forest` (also
`record-ocean`, `record-sky`; one at a time, screen unlocked) records the bot
client's window in 10 s pieces; `python3 tools/video/cut.py sheets` shows the
footage every 2 s, `tools/video/cuts.json` is the edit (explainer 16:9, ad
16:9, reel 9:16), `cut.py build` writes `reports/video/*.mp4` (git-ignored,
silent: add music where you post). Needs ffmpeg (`pip install
imageio-ffmpeg`) and Pillow.

## What the tests cannot tell you

Real Roblox physics for jumps, waves, updrafts and gusts; car-to-car contact
in a real server; touch controls; network latency; whether it is fun. The
Studio harness covers the first two; playtests with M / N markers cover the
rest.
