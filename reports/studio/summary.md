# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [abilities-forest](abilities-forest.json) | WARN | fd36242+ | 2026-10-22T02:09 |
| [abilities-ocean](abilities-ocean.json) | PASS | aeab89c | 2026-10-22T01:10 |
| [abilities-sky](abilities-sky.json) | PASS | aeab89c+ | 2026-10-22T01:19 |
| [craft-afk-3p](craft-afk-3p.json) | PASS | aeab89c+ | 2026-10-22T01:34 |
| [escape-forest](escape-forest.json) | PASS | aeab89c | 2026-10-22T00:21 |
| [escape-ocean](escape-ocean.json) | PASS | aeab89c | 2026-10-22T00:21 |
| [escape-sky](escape-sky.json) | PASS | aeab89c | 2026-10-22T00:22 |
| [farm-forest-4p](farm-forest-4p.json) | FAIL | aeab89c+ | 2026-10-22T01:29 |
| [farm-ocean-4p](farm-ocean-4p.json) | PASS | a7efc25 | 2026-10-20T04:24 |
| [farm-sky-4p](farm-sky-4p.json) | PASS | a7efc25 | 2026-10-20T04:26 |
| [fight-4p](fight-4p.json) | PASS | aa48bae+ | 2026-10-22T02:19 |
| [match-forest](match-forest.json) | WARN | fd36242+ | 2026-10-22T02:03 |
| [match-ocean](match-ocean.json) | PASS | aeab89c | 2026-10-22T00:35 |
| [match-sky](match-sky.json) | PASS | aeab89c | 2026-10-22T00:39 |
| [race-forest-builds](race-forest-builds.json) | PASS | 954581a+ | 2026-10-21T13:22 |
| [race-forest](race-forest.json) | PASS | fd36242+ | 2026-10-22T01:58 |
| [race-ocean-builds](race-ocean-builds.json) | PASS | 954581a+ | 2026-10-21T12:53 |
| [race-ocean](race-ocean.json) | PASS | aeab89c | 2026-10-22T00:18 |
| [race-sky-builds](race-sky-builds.json) | PASS | 954581a+ | 2026-10-21T12:56 |
| [race-sky](race-sky.json) | PASS | aeab89c | 2026-10-22T00:20 |
| [start-6p](start-6p.json) | FAIL | aeab89c+ | 2026-10-22T01:26 |
| [steal-4p](steal-4p.json) | PASS | aa48bae+ | 2026-10-22T02:23 |
| [steal-crowd-6p](steal-crowd-6p.json) | PASS | a7efc25 | 2026-10-20T04:33 |
| [steal-defended-2p](steal-defended-2p.json) | PASS | aa48bae+ | 2026-10-22T02:21 |
| [vehicles-forest](vehicles-forest.json) | PASS | aeab89c | 2026-10-22T01:00 |
| [vehicles-ocean](vehicles-ocean.json) | PASS | aeab89c | 2026-10-22T01:01 |
| [vehicles-sky](vehicles-sky.json) | PASS | aeab89c | 2026-10-22T01:02 |

## abilities-forest — WARN

```
Bot match: 4 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 4
    steal attempts: denied: too late=1
    -4: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -1: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  round 2 (FOREST): 0 finished of 4
    steal attempts: denied: too late=2
    -4: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: pic
abilities: 39 items fired ok, 47 effect keys measured
  backpackBoost   x1   rise 0.0  MaxSpeed 101.5→101.5  drawn 4
  barrelRoll      x7   rise 0.0  MaxSpeed 29.3→64.5 65.2→71.7  drawn 24
  bathSplash      x2   rise 0.1  MaxSpeed 97.3→97.3 97.3→97.3  drawn 8
  blocked         x4   rise 0.0  MaxSpeed 65.6→65.6 108.4→108.4  drawn 16
  bloomCleanse    x6   rise 0.0  MaxSpeed 65.6→65.6 65.6→65.6  drawn 24
  blown           x1   rise 0.0  MaxSpeed 103→87.5  drawn 4
  boost           x125 rise 5.5  MaxSpeed 65.6→98.4 66.3→99.4  drawn 24
  boostRocket     x41  rise 5.3  MaxSpeed 65.2→97.7 65.2→29.3  drawn 24
  bump            x16  rise 3.0  MaxSpeed 65.6→65.6 39.8→39.8  drawn 24
  bumperAbsorb    x21  rise 1.1  MaxSpeed 103→103 108.1→108.1  drawn 24
  cactusSting     x21  rise 5.6  MaxSpeed 65.2→32.6 97.7→29.3  drawn 24
  cartRam         x2   rise 0.0  MaxSpeed 106.2→106.2 70.8→106.2  drawn 8
  cartShove       x3   rise 1.3  MaxSpeed 102.5→102.5 99.4→69.6  drawn 12
  digMode         x2   rise 0.0  MaxSpeed 104.5→104.5 73.2→73.2  drawn 8
  disguise        x7   rise 0.1  MaxSpeed 29.5→19.7 65.6→65.6  drawn 24
  dropTrap        x31  rise 3.0  MaxSpeed 65.6→65.6 97.7→97.7  drawn 24
  flagAura        x12  rise 3.5  MaxSpeed 106.2→102 103.2→123.8  drawn 24
  frozen          x1   rise 0.0  MaxSpeed 83.8→0  drawn 4
  groundBounce    x4   rise 4.8  MaxSpeed 69.8→83.8 34.9→69.8  drawn 16
  gustBlast       x7   rise 0.6  MaxSpeed 65.2→65.2 97.7→48.9  drawn 24
  hover           x2   rise 0.0  MaxSpeed 82.5→82.5 68.8→68.8  drawn 8
  kiteLift        x1   rise 3.0  MaxSpeed 72.3→72.3  drawn 4
  leadFlag        x6   rise 0.1  MaxSpeed 103→108.1 69.7→73.2  drawn 24
  lifeFloat       x1   rise 0.0  MaxSpeed 68.8→68.8  drawn 4
  lockdown        x1   rise 0.0  MaxSpeed 104.5→104.5  drawn 4
  magnetPull      x3   rise 3.4  MaxSpeed 127.5→102 68.8→55  drawn 12
  microFreeze     x1   rise 0.0  MaxSpeed 86.1→123  drawn 4
  miniTurbo       x2   rise 0.1  MaxSpeed 108.1→168.9 43.2→54.1  drawn 8
  momentum        x22  rise 0.8  MaxSpeed 68.3→70.3 102.4→70.3  drawn 24
  noodleSnare     x2   rise 0.0  MaxSpeed 123→86.1 104.5→73.2  drawn 8
  raftGlide       x4   rise 2.9  MaxSpeed 119.3→114.4 66.3→76.2  drawn 16
  rammed          x38  rise 3.5  MaxSpeed 65.2→32.6 97.7→29.3  drawn 24
  redline         x1   rise 0.0  MaxSpeed 72.3→144.6  drawn 4
  reverseBoost    x6   rise 3.0  MaxSpeed 103.3→206.7 103.3→206.7  drawn 24
  rise            x8   rise 9.0  MaxSpeed 103.2→123.8 68.8→55  drawn 24
  rocketBurst     x7   rise 3.5  MaxSpeed 109.7→329.2 101.5→304.4  drawn 24
  skateSlide      x4   rise 0.6  MaxSpeed 32.4→135.1 54.1→67.6  drawn 16
  slipped         x18  rise 9.0  MaxSpeed 65.6→45.9 99.4→69.6  drawn 24
  slipstream      x16  rise 3.0  MaxSpeed 97.7→44 98.4→88.6  drawn 24
  sofaFortress    x1   rise 0.0  MaxSpeed 0→0  drawn 4
  spinBurst       x2   rise 0.0  MaxSpeed 102→255 127.5→255  drawn 8
  splashed        x4   rise 0.0  MaxSpeed 79.5→63.6 68.6→63.1  drawn 16
  steamed         x9   rise 0.4  MaxSpeed 92.2→92.2 72.3→108.4  drawn 24
  steerDisable    x7   rise 3.5  MaxSpeed 65.6→65.6 65.6→65.6  drawn 24
  umbrellaBlock   x3   rise 0.7  MaxSpeed 104.5→104.5 101.5→121.7  drawn 12
  windBlast       x2   rise 0.4  MaxSpeed 92.2→92.2 121.6→121.6  drawn 8
  windRide        x7   rise 3.0  MaxSpeed 66.3→79.5 99.4→79.5  drawn 24
driving: 18 hits (closing speed max 70, push max 45 studs/s), 2 drift turbos, drops: Cactus, Gas Can, Kettle, Log, Magnifying Glass, Pizza
```
- **warn** lifeFloat (1 landings): never rose 1.5 studs (rose 0.0)
- **warn** sofaFortress (1 landings): MaxSpeed never went down (0→0)

## abilities-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 2
  round 1 (OCEAN): 0 finished of 4
    steal attempts: denied: too late=1
    -4: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -1: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  events: ability=56 ability_probe=115 bot_craft=4 bot_fx=336 bot_hud=19 bot_joined=4 bot_pickup_denied=1 bot_ready=4 bot_respawn=1 bot_screen=4 bot_steal=1 checkpoint=8 contact=9 craft=4 harness_crafting=1 harness_round=1 hazard=3 item_pickup=2 phase=4 race_go=1 race_launch=4 race_progress=244 race_sample=504 race_start=1 respawn=1 speed_effect=143 steal_attempt=1 vehicle_spawn=4
abilities: 12 items fired ok, 23 effect keys measured
  bathSplash      x4   rise 0.0  MaxSpeed 88.8→88.8 88.8→88.8  drawn 20
  blocked         x1   rise 0.0  MaxSpeed 125.8→125.8  drawn 4
  boost           x33  rise 4.0  MaxSpeed 59.9→89.8 54→81.1  drawn 24
  boostRocket     x10  rise 3.0  MaxSpeed 61.4→92.1 92.1→92.1  drawn 24
  bumperAbsorb    x4   rise 0.0  MaxSpeed 60→60 90.1→90.1  drawn 16
  cactusSting     x1   rise 4.0  MaxSpeed 92.1→46  drawn 4
  cartShove       x3   rise 0.2  MaxSpeed 88.8→88.8 53.3→53.3  drawn 12
  dropTrap        x4   rise 0.0  MaxSpeed 92.1→92.1 82.9→82.9  drawn 16
  frozen          x1   rise 1.8  MaxSpeed 102.2→0  drawn 4
  fullBuoyancy    x4   rise 3.0  MaxSpeed 92.1→92.1 92.1→92.1  drawn 16
  hover           x5   rise 3.5  MaxSpeed 102.2→0 88.8→88.8  drawn 20
  kiteLift        x3   rise 4.0  MaxSpeed 92.1→92.1 92.1→46  drawn 16
  leadFlag        x5   rise 0.0  MaxSpeed 60→63.1 60→63.1  drawn 20
  lifeFloat       x4   rise 3.5  MaxSpeed 125.8→89.8 125.8→89.8  drawn 16
  microFreeze     x3   rise 0.0  MaxSpeed 60→60 63.1→37.8  drawn 12
  rammed          x1   rise 3.9  MaxSpeed 92.1→46  drawn 4
  rise            x8   rise 4.0  MaxSpeed 59.9→89.8 60→81.1  drawn 24
  rocketBurst     x6   rise 0.0  MaxSpeed 90.1→180.1 90.1→108.1  drawn 24
  slipstream      x5   rise 3.7  MaxSpeed 60→81.1 60→81.1  drawn 20
  splashed        x1   rise 0.0  MaxSpeed 89.8→71.9  drawn 4
  steamed         x2   rise 0.0  MaxSpeed 61.4→92.1 54→81.1  drawn 8
  umbrellaSail    x3   rise 0.0  MaxSpeed 88.8→102.2 88.8→102.2  drawn 12
  windRide        x4   rise 0.0  MaxSpeed 89.8→125.8 89.8→125.8  drawn 16
```

## abilities-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (SKY): 0 finished of 4
    steal attempts: none
    -4: picked 4, contests 0/0, stole 0, robbed 0, defences 0, items 4 | craft submitted, rejected 0
    -2: picked 3, contests 0/0, stole 0, robbed 0, defences 0, items 3 | craft submitted, rejected 0
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
  events: ability=58 ability_probe=97 bot_craft=4 bot_fx=268 bot_hud=20 bot_joined=4 bot_pickup_denied=1 bot_ready=4 bot_respawn=1 checkpoint=7 contact=4 craft=4 harness_crafting=1 harness_round=1 hazard=5 item_pickup=8 phase=4 race_go=1 race_launch=4 race_progress=240 race_sample=496 race_start=1 respawn=1 speed_effect=81 vehicle_spawn=4
abilities: 12 items fired ok, 17 effect keys measured
  bathSplash      x5   rise 0.0  MaxSpeed 61.5→61.5 122.9→122.9  drawn 20
  boost           x31  rise 4.0  MaxSpeed 83.9→132.2 85→127.5  drawn 24
  boostRocket     x10  rise 3.0  MaxSpeed 87.4→131.2 131.2→170.5  drawn 24
  bumperAbsorb    x2   rise 0.0  MaxSpeed 132.2→132.2 88.1→88.1  drawn 8
  dropTrap        x4   rise 0.0  MaxSpeed 131.2→131.2 131.2→131.2  drawn 16
  hover           x5   rise 3.5  MaxSpeed 61.5→61.5 122.9→122.9  drawn 20
  kiteGlide       x4   rise 1.0  MaxSpeed 131.2→170.5 131.2→170.5  drawn 16
  leadFlag        x2   rise 0.0  MaxSpeed 125.9→132.2 251.8→132.2  drawn 8
  lifeFloat       x4   rise 3.5  MaxSpeed 204.1→127.5 204.1→127.5  drawn 16
  microFreeze     x3   rise 0.0  MaxSpeed 132.2→132.2 83.9→83.9  drawn 12
  parachute       x3   rise 2.0  MaxSpeed 122.9→61.5 122.9→41  drawn 12
  rammed          x2   rise 0.0  MaxSpeed 131.2→131.2 110.6→110.6  drawn 8
  rise            x8   rise 4.1  MaxSpeed 132.2→88.1 127.5→127.5  drawn 24
  rocketBurst     x5   rise 0.2  MaxSpeed 83.9→251.8 83.9→251.8  drawn 24
  slipstream      x1   rise 0.0  MaxSpeed 122.9→110.6  drawn 4
  softLanding     x4   rise 3.0  MaxSpeed 131.2→131.2 131.2→131.2  drawn 16
  windRide        x4   rise 0.0  MaxSpeed 127.5→204.1 127.5→204.1  drawn 16
```

## craft-afk-3p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 3
    steal attempts: denied: victim has nothing=1
    -3: picked 15, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft auto, rejected 0
    -1: picked 9, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: ability=2 bot_craft=2 bot_hud=162 bot_joined=3 bot_ready=3 bot_steal=1 craft=3 harness_crafting=1 harness_round=1 item_drop=8 item_pickup=24 phase=3 race_sample=3 race_start=1 steal_attempt=1 vehicle_spawn=3
```

## escape-forest — PASS

```
RaceSim FOREST (shipped) — 5s wall time
  cases 62: drove out 62, needed a respawn 0, stuck 0
```

## escape-ocean — PASS

```
RaceSim OCEAN (shipped) — 7.2s wall time
  cases 45: drove out 45, needed a respawn 0, stuck 0
```

## escape-sky — PASS

```
RaceSim SKY (shipped) — 9s wall time
  cases 51: drove out 51, needed a respawn 0, stuck 0
```

## farm-forest-4p — FAIL

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 3
    steal attempts: denied: too far=1, stolen=1
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 8, contests 1/1, stole 0, robbed 1, defences 1, items 7 | craft submitted, rejected 0
    -1: picked 5, contests 0/1, stole 1, robbed 0, defences 0, items 6 | craft submitted, rejected 0
  events: ability=2 bot_craft=3 bot_defend=1 bot_hud=143 bot_joined=3 bot_pickup_denied=11 bot_ready=3 bot_steal=2 contest_result=1 craft=3 harness_crafting=1 harness_round=1 item_pickup=13 phase=3 race_sample=6 race_start=1 steal=1 steal_attempt=2 vehicle_spawn=3
```
- **warn** round 1: 3 of 4 players joined (Studio did not start every client)
- **fail** round 1: picked up nothing: -3
- **fail** -3 CRAFTING: 3 timer screens at once
- **fail** -3 FARMING: timer is 11 s off the server's

## farm-ocean-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 1
  round 1 (OCEAN): 0 finished of 4
    steal attempts: defended=2, stolen=1
    -4: picked 13, contests 1/2, stole 0, robbed 1, defences 1, items 8 | craft submitted, rejected 0
    -2: picked 9, contests 1/1, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 0/2, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 11, contests 2/3, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: bot_craft=4 bot_defend=3 bot_joined=4 bot_pickup_denied=2 bot_ready=4 bot_steal=3 contest_result=4 craft=4 harness_crafting=1 harness_round=1 item_drop=9 item_pickup=41 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal=1 steal_attempt=3 vehicle_spawn=3
```

## farm-sky-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (SKY): 0 finished of 4
    steal attempts: defended=7, denied: too far=3, denied: victim has nothing=3
    -4: picked 10, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 9, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 11, contests 2/6, stole 0, robbed 0, defences 2, items 8 | craft submitted, rejected 0
    -3: picked 12, contests 4/6, stole 0, robbed 0, defences 5, items 8 | craft submitted, rejected 0
  events: bot_craft=4 bot_defend=7 bot_joined=4 bot_ready=4 bot_steal=13 contest_result=6 craft=4 harness_crafting=1 harness_round=1 item_drop=10 item_pickup=42 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal_attempt=13 vehicle_spawn=3
```

## fight-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 4
    steal attempts: none
    -4: picked 11, contests 1/3, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 15, contests 2/2, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 0, contests 0/1, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  events: ability=2 bot_craft=4 bot_farmfx=64 bot_guard=61 bot_hud=184 bot_joined=4 bot_punch=277 bot_ready=4 contest_result=3 craft=4 harness_crafting=1 harness_round=1 item_drop=10 item_pickup=26 phase=3 punch=276 race_sample=8 race_start=1 vehicle_spawn=4
```

## match-forest — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 3 finished of 3
    steal attempts: defended=5, denied: too far=1, denied: victim has nothing=2
    -3: picked 5, contests 4/6, stole 0, robbed 0, defences 2, items 5 | craft submitted, rejected 0
    -2: picked 14, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 3, contests 2/6, stole 0, robbed 0, defences 3, items 3 | craft submitted, rejected 0
    #1 Player2 77.5s
    #2 Player1 106.4s
    #3 Player3 113.7s
  events: ability=53 ability_probe=130 bot_craft=3 bot_defend=5 bot_fx=177 bot_hud=92 bot_joined=3 bot_ready=3 bot_respawn=4 bot_screen=1 bot_steal=8 checkpoint=6 contact=5 contest_result=6 craft=3 drift_turbo=11 drop_placed=9 finish=3 harness_crafting=1 harness_round=1 hazard=28 hit=2 hit_blocked=2 impact=2 item_drop=6 item_pickup=22 phase=4 race_go=1 race_launch=3 race_progress=
driving: 2 hits (closing speed max 36, push max 26 studs/s), 11 drift turbos, drops: Kettle
```
- **warn** round 1: 3 of 4 players joined (Studio did not start every client)

## match-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 2
  round 1 (OCEAN): 4 finished of 4
    steal attempts: defended=8, denied: too far=1, stolen=2
    -4: picked 12, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 11, contests 0/0, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 9, contests 1/3, stole 1, robbed 1, defences 3, items 8 | craft submitted, rejected 0
    -3: picked 9, contests 2/3, stole 1, robbed 0, defences 5, items 8 | craft submitted, rejected 0
    #1 Player4 58.2s
    #2 Player2 70.3s
    #3 Player1 84.6s
    #4 Player3 114.8s
  events: ability=90 ability_probe=180 bot_craft=4 bot_defend=10 bot_fx=300 bot_hud=122 bot_joined=4 bot_pickup_denied=3 bot_ready=4 bot_respawn=14 bot_screen=4 bot_steal=11 checkpoint=8 contact=16 contest_result=3 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=6 item_d
```

## match-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 2
  round 1 (SKY): 4 finished of 4
    steal attempts: denied: victim has nothing=1
    -4: picked 10, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 10, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    #1 Player1 68.7s
    #2 Player4 86.8s
    #3 Player2 98.8s
    #4 Player3 115.7s
  events: ability=111 ability_probe=157 bot_craft=4 bot_fx=280 bot_hud=122 bot_joined=4 bot_ready=4 bot_respawn=11 bot_screen=5 bot_steal=1 checkpoint=8 contact=5 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=10 hit=8 hit_blocked=1 item_drop=4 item_pickup=36 phase=4 race_go=1 race_
```

## race-forest-builds — PASS

```
RaceSim FOREST (shipped) — 128.9s wall time
  novice   [slowest-novice] car=slowest max=65 mass=10.12 → 129.19s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=73 mass=7.41 → 93.44s | CPs 2 | respawns 0 | blocked 0
```

## race-forest — PASS

```
RaceSim FOREST (shipped) — 123.9s wall time
  expert   car=p50 max=69 mass=8.03 → 111s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=69 mass=8.03 → 115.15s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=69 mass=8.03 → 124.18s | CPs 2 | respawns 0 | blocked 0
drifts: expert 14/10, average 14/6, novice 0/0
```

## race-ocean-builds — PASS

```
RaceSim OCEAN (shipped) — 130.2s wall time
  novice   [slowest-novice] car=slowest max=59 mass=6.28 → 130.59s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=63 mass=6.51 → 91.5s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean — PASS

```
RaceSim OCEAN (shipped) — 126.8s wall time
  expert   car=p50 max=61 mass=6.36 → 102.08s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=61 mass=6.36 → 106.53s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=61 mass=6.36 → 128.14s | CPs 2 | respawns 0 | blocked 0
```

## race-sky-builds — PASS

```
RaceSim SKY (shipped) — 140.9s wall time
  novice   [slowest-novice] car=slowest max=82 mass=2.64 → 141.26s | CPs 2 | respawns 1 | blocked 0
  expert   [fastest-expert] car=fastest max=92 mass=2.83 → 89.3s | CPs 2 | respawns 0 | blocked 0
```

## race-sky — PASS

```
RaceSim SKY (shipped) — 131.6s wall time
  expert   car=p50 max=86 mass=2.75 → 102.37s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=86 mass=2.75 → 109.37s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=86 mass=2.75 → 132.55s | CPs 2 | respawns 0 | blocked 0
```

## start-6p — FAIL

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 6
    steal attempts: denied: too late=2
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -4: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -5: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -6: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  events: ability=5 ability_probe=38 bot_craft=6 bot_fx=90 bot_hud=36 bot_joined=6 bot_pickup_denied=1 bot_ready=6 bot_respawn=5 bot_steal=2 checkpoint=1 contact=6 craft=6 harness_craftin
```
- **fail** cars left the grid 10.1 s apart (limit 1.0 s): 1.7, 5.0, 9.4, 11.8, 11.8
- **fail** -1 CRAFTING: 2 timer screens at once
- **fail** -2 CRAFTING: 2 timer screens at once
- **fail** -2 CRAFTING: timer is 111 s off the server's
- **fail** -3 FARMING: timer is 10 s off the server's
- **fail** -6 CRAFTING: 2 timer screens at once
- **fail** -6 FARMING: timer is 10 s off the server's

## steal-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 4
    steal attempts: defended=2, denied: too far=1, denied: victim has nothing=2, stolen=2
    -4: picked 9, contests 0/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 17, contests 4/4, stole 0, robbed 2, defences 2, items 8 | craft submitted, rejected 0
    -1: picked 13, contests 0/1, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 9, contests 0/2, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: ability=4 bot_craft=4 bot_defend=4 bot_farmfx=72 bot_guard=1 bot_hud=182 bot_joined=4 bot_pickup_denied=1 bot_punch=2 bot_ready=4 bot_steal=7 contest_result=4 craft=4 harness_crafting=1 harness_round=1 item_drop=16 item_pickup=48 phase=3 punch=2 race_sample=8 race_start=1 steal=2 steal_attempt=7 vehicle_spawn=4
```

## steal-crowd-6p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 1
  round 1 (FOREST): 0 finished of 6
    steal attempts: defended=6, denied: too far=12, denied: victim has nothing=1, denied: victim protected=1, stolen=7
    -3: picked 11, contests 5/6, stole 0, robbed 2, defences 2, items 8 | craft submitted, rejected 0
    -2: picked 9, contests 4/6, stole 2, robbed 1, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 2/5, stole 3, robbed 3, defences 1, items 8 | craft submitted, rejected 0
    -4: picked 11, contests 0/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -5: picked 10, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -6: picked 8, contests 0/4, stole 2, robbed 1, defences 2, items 8 | craft submitted, rejected 0
  events: bot_craft=6 bot_defend=13 bot_joined=6 bot_pickup_denied=46 bot_ready=6 bot_steal=27 contes
```

## steal-defended-2p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 2
    steal attempts: defended=3, denied: victim has nothing=1
    -1: picked 17, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 9, contests 0/0, stole 0, robbed 0, defences 3, items 8 | craft submitted, rejected 0
  events: ability=2 bot_craft=2 bot_defend=3 bot_farmfx=28 bot_hud=92 bot_joined=2 bot_ready=2 bot_steal=4 craft=2 harness_crafting=1 harness_round=1 item_drop=10 item_pickup=26 phase=3 race_sample=4 race_start=1 steal_attempt=4 vehicle_spawn=2
```

## vehicles-forest — PASS

```
RaceSim FOREST (shipped) — 13s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-ocean — PASS

```
RaceSim OCEAN (shipped) — 13.3s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-sky — PASS

```
RaceSim SKY (shipped) — 10.4s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```
