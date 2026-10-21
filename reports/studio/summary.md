# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [abilities-forest](abilities-forest.json) | PASS | aeab89c | 2026-10-22T01:08 |
| [abilities-ocean](abilities-ocean.json) | PASS | aeab89c | 2026-10-22T01:10 |
| [abilities-sky](abilities-sky.json) | PASS | aeab89c+ | 2026-10-22T01:19 |
| [craft-afk-3p](craft-afk-3p.json) | PASS | aeab89c+ | 2026-10-22T01:34 |
| [escape-forest](escape-forest.json) | PASS | aeab89c | 2026-10-22T00:21 |
| [escape-ocean](escape-ocean.json) | PASS | aeab89c | 2026-10-22T00:21 |
| [escape-sky](escape-sky.json) | PASS | aeab89c | 2026-10-22T00:22 |
| [farm-forest-4p](farm-forest-4p.json) | FAIL | aeab89c+ | 2026-10-22T01:29 |
| [farm-ocean-4p](farm-ocean-4p.json) | PASS | a7efc25 | 2026-10-20T04:24 |
| [farm-sky-4p](farm-sky-4p.json) | PASS | a7efc25 | 2026-10-20T04:26 |
| [match-forest](match-forest.json) | WARN | aeab89c+ | 2026-10-22T01:24 |
| [match-ocean](match-ocean.json) | PASS | aeab89c | 2026-10-22T00:35 |
| [match-sky](match-sky.json) | PASS | aeab89c | 2026-10-22T00:39 |
| [race-forest-builds](race-forest-builds.json) | PASS | 954581a+ | 2026-10-21T13:22 |
| [race-forest](race-forest.json) | PASS | aeab89c | 2026-10-22T00:15 |
| [race-ocean-builds](race-ocean-builds.json) | PASS | 954581a+ | 2026-10-21T12:53 |
| [race-ocean](race-ocean.json) | PASS | aeab89c | 2026-10-22T00:18 |
| [race-sky-builds](race-sky-builds.json) | PASS | 954581a+ | 2026-10-21T12:56 |
| [race-sky](race-sky.json) | PASS | aeab89c | 2026-10-22T00:20 |
| [start-6p](start-6p.json) | FAIL | aeab89c+ | 2026-10-22T01:26 |
| [steal-4p](steal-4p.json) | WARN | aeab89c | 2026-10-22T00:57 |
| [steal-crowd-6p](steal-crowd-6p.json) | PASS | a7efc25 | 2026-10-20T04:33 |
| [steal-defended-2p](steal-defended-2p.json) | FAIL | aeab89c+ | 2026-10-22T01:32 |
| [vehicles-forest](vehicles-forest.json) | PASS | aeab89c | 2026-10-22T01:00 |
| [vehicles-ocean](vehicles-ocean.json) | PASS | aeab89c | 2026-10-22T01:01 |
| [vehicles-sky](vehicles-sky.json) | PASS | aeab89c | 2026-10-22T01:02 |

## abilities-forest — PASS

```
Bot match: 4 round(s), end: rounds complete, server errors: 0, client errors: 1
  round 1 (FOREST): 0 finished of 4
    steal attempts: denied: victim has nothing=1
    -4: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -2: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  round 2 (FOREST): 0 finished of 4
    steal attempts: none
    -4: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: picked 
abilities: 39 items fired ok, 41 effect keys measured
  backpackBoost   x1   rise 0.0  MaxSpeed 101.5→60.9  drawn 4
  barrelRoll      x10  rise 0.0  MaxSpeed 97.7→107.5 32.6→35.8  drawn 24
  bathSplash      x4   rise 0.6  MaxSpeed 97.3→97.3 97.3→97.3  drawn 16
  blocked         x4   rise 0.5  MaxSpeed 108.4→108.4 304.4→304.4  drawn 16
  bloomCleanse    x6   rise 0.2  MaxSpeed 59.1→59.1 65.6→65.6  drawn 24
  blown           x1   rise 0.0  MaxSpeed 98.4→55.8  drawn 4
  boost           x139 rise 8.4  MaxSpeed 65.6→98.4 66.3→99.4  drawn 24
  boostRocket     x46  rise 2.6  MaxSpeed 65.2→97.7 65.2→97.7  drawn 24
  bumperAbsorb    x6   rise 0.0  MaxSpeed 108.1→108.1 376.2→395  drawn 24
  cactusSting     x6   rise 1.5  MaxSpeed 97.7→48.9 76.2→33.1  drawn 24
  cartRam         x5   rise 0.1  MaxSpeed 106.2→106.2 106.2→106.2  drawn 20
  cartShove       x6   rise 1.3  MaxSpeed 39.4→39.4 99.4→99.4  drawn 24
  digMode         x4   rise 4.0  MaxSpeed 131.7→131.7 104.5→104.5  drawn 16
  disguise        x8   rise 1.9  MaxSpeed 65.6→39.4 65.6→98.4  drawn 24
  dropTrap        x36  rise 0.6  MaxSpeed 108.1→108.1 65.6→65.6  drawn 24
  flagAura        x8   rise 10.8  MaxSpeed 47.8→114.7 74.3→66  drawn 24
  groundBounce    x4   rise 5.9  MaxSpeed 104.7→104.7 104.7→104.7  drawn 16
  gustBlast       x9   rise 4.3  MaxSpeed 91.2→91.2 97.7→97.7  drawn 24
  hover           x5   rise 7.1  MaxSpeed 66→82.5 68.8→103.2  drawn 20
  kiteLift        x4   rise 8.5  MaxSpeed 43.4→108.4 72.3→108.4  drawn 16
  leadFlag        x6   rise 0.2  MaxSpeed 103→108.1 69.7→73.2  drawn 24
  lifeFloat       x4   rise 5.5  MaxSpeed 103.2→34.4 68.8→68.8  drawn 16
  lockdown        x3   rise 0.1  MaxSpeed 125.4→125.4 104.5→104.5  drawn 12
  magnetPull      x1   rise 10.8  MaxSpeed 92.8→66  drawn 4
  microFreeze     x4   rise 0.2  MaxSpeed 61.5→123 123→123  drawn 16
  momentum        x25  rise 0.6  MaxSpeed 68.3→70.3 102.4→105.5  drawn 24
  raftGlide       x6   rise 0.6  MaxSpeed 47.7→34.3 66.3→76.2  drawn 24
  rammed          x15  rise 2.5  MaxSpeed 97.7→48.9 65.6→65.6  drawn 24
  redline         x4   rise 0.0  MaxSpeed 72.3→144.6 108.4→144.6  drawn 16
  reverseBoost    x5   rise 0.6  MaxSpeed 98.4→196.8 103.3→206.7  drawn 24
  rise            x8   rise 12.7  MaxSpeed 92.8→66 68.8→68.8  drawn 24
  rocketBurst     x10  rise 0.6  MaxSpeed 125.4→395 101.5→304.4  drawn 24
  skateSlide      x4   rise 0.6  MaxSpeed 32.4→81.1 108.1→67.6  drawn 16
  slipstream      x12  rise 0.7  MaxSpeed 65.2→58.6 65.6→65.6  drawn 24
  sofaFortress    x3   rise 0.0  MaxSpeed 104.7→0 104.7→0  drawn 12
  spinBurst       x5   rise 2.1  MaxSpeed 127.5→153 70.8→212.5  drawn 20
  steamed         x10  rise 2.8  MaxSpeed 65.2→97.7 97.7→97.7  drawn 24
  steerDisable    x4   rise 0.5  MaxSpeed 65.6→65.6 65.6→65.6  drawn 16
  umbrellaBlock   x3   rise 2.3  MaxSpeed 104.5→101.5 104.5→104.5  drawn 12
  windBlast       x2   rise 0.0  MaxSpeed 102.4→102.4 105.5→105.5  drawn 8
  windRide        x8   rise 0.6  MaxSpeed 92.8→79.5 99.4→79.5  drawn 24
```

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

## match-forest — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 3 finished of 3
    steal attempts: defended=4, denied: victim has nothing=3, stolen=1
    -3: picked 2, contests 1/1, stole 0, robbed 1, defences 1, items 1 | craft submitted, rejected 0
    -2: picked 13, contests 0/4, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 6, contests 4/5, stole 1, robbed 0, defences 3, items 7 | craft submitted, rejected 0
    #1 Player1 70.8s
    #2 Player2 77.6s
    #3 Player3 121.1s
  events: ability=62 ability_probe=128 bot_craft=3 bot_defend=5 bot_fx=144 bot_hud=91 bot_joined=3 bot_ready=3 bot_respawn=10 bot_screen=2 bot_steal=8 checkpoint=6 contact=6 contest_result=5 craft=3 finish=3 harness_crafting=1 harness_round=1 hazard=27 hit=7 item_drop=5 item_pickup=21 phase=4 race_go=1 race_launch=3 race_progress=363 race_sample=732 race_start=1 respawn=36 speed_effect=237
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
RaceSim FOREST (shipped) — 121.8s wall time
  expert   car=p50 max=69 mass=8.03 → 110.82s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=69 mass=8.03 → 111.58s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=69 mass=8.03 → 123.3s | CPs 2 | respawns 0 | blocked 0
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

## steal-4p — WARN

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 2
  round 1 (FOREST): 0 finished of 2
    steal attempts: defended=1, denied: too far=3, denied: victim has nothing=1, stolen=1
    -1: picked 9, contests 0/0, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 10, contests 0/0, stole 0, robbed 1, defences 1, items 8 | craft submitted, rejected 0
  events: ability=2 bot_craft=2 bot_defend=2 bot_hud=90 bot_joined=2 bot_ready=2 bot_steal=6 craft=2 harness_crafting=1 harness_round=1 item_drop=3 item_pickup=19 phase=3 race_sample=2 race_start=1 steal=1 steal_attempt=6 vehicle_spawn=2
```
- **warn** round 1: 2 of 4 players joined (Studio did not start every client)

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

## steal-defended-2p — FAIL

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 1
  round 1 (FOREST): 0 finished of 2
    steal attempts: defended=2, denied: too far=2
    -1: picked 16, contests 1/3, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 9, contests 2/3, stole 0, robbed 0, defences 2, items 8 | craft submitted, rejected 0
  events: ability=2 bot_craft=2 bot_defend=2 bot_hud=91 bot_joined=2 bot_ready=2 bot_steal=4 contest_result=3 craft=2 harness_crafting=1 harness_round=1 item_drop=9 item_pickup=25 phase=3 race_sample=4 race_start=1 steal_attempt=4 vehicle_spawn=2
```
- **fail** -2 FARMING: timer is 20 s off the server's

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
