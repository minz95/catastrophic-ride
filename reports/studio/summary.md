# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [craft-afk-3p](craft-afk-3p.json) | PASS | a7efc25 | 2026-10-20T04:35 |
| [escape-forest](escape-forest.json) | PASS | 954581a+ | 2026-10-21T13:19 |
| [farm-forest-4p](farm-forest-4p.json) | PASS | 954581a+ | 2026-10-21T13:10 |
| [farm-ocean-4p](farm-ocean-4p.json) | PASS | a7efc25 | 2026-10-20T04:24 |
| [farm-sky-4p](farm-sky-4p.json) | PASS | a7efc25 | 2026-10-20T04:26 |
| [match-forest](match-forest.json) | PASS | 954581a+ | 2026-10-21T13:19 |
| [match-ocean](match-ocean.json) | PASS | 954581a+ | 2026-10-21T13:05 |
| [match-sky](match-sky.json) | PASS | 954581a+ | 2026-10-21T13:08 |
| [race-forest-builds](race-forest-builds.json) | PASS | 954581a+ | 2026-10-21T13:22 |
| [race-ocean-builds](race-ocean-builds.json) | PASS | 954581a+ | 2026-10-21T12:53 |
| [race-sky-builds](race-sky-builds.json) | PASS | 954581a+ | 2026-10-21T12:56 |
| [start-6p](start-6p.json) | WARN | 954581a+ | 2026-10-21T12:48 |
| [steal-4p](steal-4p.json) | PASS | a7efc25 | 2026-10-20T04:30 |
| [steal-crowd-6p](steal-crowd-6p.json) | PASS | a7efc25 | 2026-10-20T04:33 |
| [steal-defended-2p](steal-defended-2p.json) | PASS | a7efc25 | 2026-10-20T04:28 |
| [vehicles-forest](vehicles-forest.json) | PASS | 954581a+ | 2026-10-21T13:22 |
| [vehicles-ocean](vehicles-ocean.json) | PASS | 954581a+ | 2026-10-21T13:11 |
| [vehicles-sky](vehicles-sky.json) | PASS | 954581a+ | 2026-10-21T13:12 |

## craft-afk-3p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 3
    steal attempts: denied: victim has nothing=2, stolen=1
    -3: picked 13, contests 0/0, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft auto, rejected 0
    -1: picked 7, contests 0/0, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: bot_craft=2 bot_defend=1 bot_joined=3 bot_ready=3 bot_steal=3 craft=3 harness_crafting=1 harness_round=1 item_drop=4 item_pickup=20 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal=1 steal_attempt=3 vehicle_spawn=3
```

## escape-forest — PASS

```
RaceSim FOREST (shipped) — 4.5s wall time
  cases 62: drove out 62, needed a respawn 0, stuck 0
```

## farm-forest-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 4
    steal attempts: defended=1, denied: too far=1, stolen=4
    -4: picked 10, contests 1/1, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 16, contests 4/5, stole 0, robbed 3, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 9, contests 1/6, stole 2, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 7, contests 0/0, stole 2, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: bot_craft=4 bot_defend=5 bot_hud=182 bot_joined=4 bot_ready=4 bot_steal=6 contest_result=6 craft=4 harness_crafting=1 harness_round=1 item_drop=10 item_pickup=42 phase=3 race_sample=8 race_start=1 steal=4 steal_attempt=6 vehicle_spawn=4
```

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

## match-forest — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 4 finished of 4
    steal attempts: defended=2, denied: victim has nothing=3
    -4: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 12, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 10, contests 1/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 11, contests 0/1, stole 0, robbed 0, defences 2, items 8 | craft submitted, rejected 0
    #1 Player4 88.1s
    #2 Player1 97.4s
    #3 Player2 98.1s
    #4 Player3 112.8s
  events: bot_craft=4 bot_defend=2 bot_hud=124 bot_joined=4 bot_ready=4 bot_respawn=4 bot_steal=5 checkpoint=8 contact=21 contest_result=1 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=33 hit=15 item_drop=9 item_pickup=41 phase=4 race_go=1 race_launch=4 race_progres
```

## match-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (OCEAN): 4 finished of 4
    steal attempts: defended=2, denied: too far=3, denied: victim has nothing=2
    -4: picked 11, contests 0/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 12, contests 0/0, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 0/0, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -3: picked 8, contests 1/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    #1 Player1 70.8s
    #2 Player4 76.9s
    #3 Player2 81.8s
    #4 Player3 110.2s
  events: bot_craft=4 bot_defend=2 bot_hud=124 bot_joined=4 bot_ready=4 bot_respawn=10 bot_steal=7 checkpoint=8 contact=18 contest_result=1 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=6 item_drop=7 item_pickup=39 phase=4 race_go=1 race_launch=4 ra
```

## match-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (SKY): 4 finished of 4
    steal attempts: defended=4, denied: too far=3, denied: victim has nothing=1, stolen=2
    -4: picked 11, contests 0/3, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 11, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 7, contests 2/4, stole 0, robbed 1, defences 1, items 6 | craft submitted, rejected 0
    -3: picked 7, contests 5/7, stole 2, robbed 0, defences 3, items 8 | craft submitted, rejected 0
    #1 Player4 74.3s
    #2 Player1 87.6s
    #3 Player2 97.4s
    #4 Player3 122.1s
  events: bot_craft=4 bot_defend=6 bot_hud=124 bot_joined=4 bot_ready=4 bot_respawn=12 bot_steal=10 checkpoint=8 contact=7 contest_result=7 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=10 item_drop=6 item_pickup=36 phase=4 race_go=1 race_la
```

## race-forest-builds — PASS

```
RaceSim FOREST (shipped) — 128.9s wall time
  novice   [slowest-novice] car=slowest max=65 mass=10.12 → 129.19s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=73 mass=7.41 → 93.44s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean-builds — PASS

```
RaceSim OCEAN (shipped) — 130.2s wall time
  novice   [slowest-novice] car=slowest max=59 mass=6.28 → 130.59s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=63 mass=6.51 → 91.5s | CPs 2 | respawns 0 | blocked 0
```

## race-sky-builds — PASS

```
RaceSim SKY (shipped) — 140.9s wall time
  novice   [slowest-novice] car=slowest max=82 mass=2.64 → 141.26s | CPs 2 | respawns 1 | blocked 0
  expert   [fastest-expert] car=fastest max=92 mass=2.83 → 89.3s | CPs 2 | respawns 0 | blocked 0
```

## start-6p — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 5
    steal attempts: defended=1, denied: too far=1, stolen=1
    -3: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
    -2: picked 9, contests 0/0, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 1, contests 0/0, stole 0, robbed 1, defences 0, items 0 | craft submitted, rejected 0
    -4: picked 6, contests 0/0, stole 0, robbed 0, defences 1, items 6 | craft submitted, rejected 0
    -5: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
  events: bot_craft=5 bot_defend=2 bot_hud=55 bot_joined=5 bot_ready=5 bot_steal=3 checkpoint=3 contact=17 craft=5 harness_crafting=1 harness_round=1 hazard=12 hit=7 item_drop=2 item_pickup=18 phase=4 race_go=1 race_launch=5 race_progress=150 race_sample=335 race_sta
```
- **warn** round 1: 5 of 6 players joined (Studio did not start every client)

## steal-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 4
    steal attempts: defended=3, denied: victim has nothing=11, stolen=3
    -4: picked 13, contests 0/1, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -2: picked 15, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 11, contests 5/9, stole 1, robbed 2, defences 1, items 8 | craft submitted, rejected 0
    -3: picked 11, contests 4/8, stole 2, robbed 1, defences 1, items 8 | craft submitted, rejected 0
  events: bot_craft=4 bot_defend=6 bot_joined=4 bot_pickup_denied=3 bot_ready=4 bot_steal=17 contest_result=9 craft=4 harness_crafting=1 harness_round=1 item_drop=18 item_pickup=50 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal=3 steal_attempt=17 vehicle_spawn=3
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
    steal attempts: defended=1, denied: too far=2, denied: victim has nothing=1
    -1: picked 15, contests 1/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 10, contests 0/1, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
  events: bot_craft=2 bot_defend=1 bot_joined=2 bot_ready=2 bot_steal=4 contest_result=1 craft=2 harness_crafting=1 harness_round=1 item_drop=9 item_pickup=25 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal_attempt=4 vehicle_spawn=2
```

## vehicles-forest — PASS

```
RaceSim FOREST (shipped) — 12.4s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-ocean — PASS

```
RaceSim OCEAN (shipped) — 13.3s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-sky — PASS

```
RaceSim SKY (shipped) — 10.5s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```
