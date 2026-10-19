# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [craft-afk-3p](craft-afk-3p.json) | PASS | a7efc25 | 2026-10-20T04:35 |
| [farm-forest-4p](farm-forest-4p.json) | PASS | a7efc25 | 2026-10-20T04:21 |
| [farm-ocean-4p](farm-ocean-4p.json) | PASS | a7efc25 | 2026-10-20T04:24 |
| [farm-sky-4p](farm-sky-4p.json) | PASS | a7efc25 | 2026-10-20T04:26 |
| [match-forest](match-forest.json) | PASS | a7efc25 | 2026-10-20T04:39 |
| [match-ocean](match-ocean.json) | WARN | a7efc25 | 2026-10-20T04:44 |
| [match-sky](match-sky.json) | WARN | a7efc25 | 2026-10-20T04:49 |
| [steal-4p](steal-4p.json) | PASS | a7efc25 | 2026-10-20T04:30 |
| [steal-crowd-6p](steal-crowd-6p.json) | PASS | a7efc25 | 2026-10-20T04:33 |
| [steal-defended-2p](steal-defended-2p.json) | PASS | a7efc25 | 2026-10-20T04:28 |

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

## farm-forest-4p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 1
  round 1 (FOREST): 0 finished of 4
    steal attempts: defended=2
    -4: picked 9, contests 0/0, stole 0, robbed 0, defences 2, items 8 | craft submitted, rejected 0
    -2: picked 13, contests 0/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 9, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 8, contests 1/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: bot_craft=4 bot_defend=2 bot_joined=4 bot_pickup_denied=1 bot_ready=4 bot_steal=2 contest_result=1 craft=4 harness_crafting=1 harness_round=1 item_drop=7 item_pickup=39 phase=3 race_progress=1 race_sample=3 race_start=1 speed_effect=2 steal_attempt=2 vehicle_spawn=3
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
    steal attempts: defended=1, denied: victim has nothing=1, stolen=1
    -4: picked 11, contests 0/0, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 10, contests 0/0, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 8, contests 0/0, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    #1 Player1 80.7s
    #2 Player2 103.0s
    #3 Player4 126.2s
    #4 Player3 129.2s
  events: bot_craft=4 bot_defend=2 bot_joined=4 bot_ready=4 bot_respawn=11 bot_steal=3 checkpoint=8 contact=21 craft=4 finish=4 harness_crafting=1 harness_round=1 hazard=27 hit=8 item_drop=5 item_pickup=37 phase=4 race_progress=517 race_sample=1011 race_start=1 respaw
```

## match-ocean — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (OCEAN): 3 finished of 3
    steal attempts: defended=9, denied: victim has nothing=3, stolen=1
    -3: picked 7, contests 1/2, stole 1, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -2: picked 12, contests 0/1, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -1: picked 9, contests 1/1, stole 0, robbed 1, defences 7, items 8 | craft submitted, rejected 0
    #1 Player1 73.5s
    #2 Player2 93.2s
    #3 Player3 122.9s
  events: bot_craft=3 bot_defend=10 bot_joined=3 bot_ready=3 bot_respawn=8 bot_steal=13 checkpoint=6 contact=2 contest_result=2 craft=3 finish=3 harness_crafting=1 harness_round=1 hazard=7 item_drop=4 item_pickup=28 phase=4 race_progress=367 race_sample=720 race_start=1 respawn=8 speed_effect=274 steal=1 steal_attempt=13 vehicle_spawn=3
```
- **warn** round 1: 3 of 4 players joined (Studio did not start every client)

## match-sky — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (SKY): 3 finished of 3
    steal attempts: defended=2, denied: too far=1, denied: victim has nothing=1, stolen=1
    -3: picked 9, contests 0/0, stole 0, robbed 1, defences 1, items 8 | craft submitted, rejected 0
    -2: picked 13, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 7, contests 0/0, stole 1, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    #1 Player1 75.6s
    #2 Player3 120.5s
    #3 Player2 122.2s
  events: bot_craft=3 bot_defend=3 bot_joined=3 bot_ready=3 bot_respawn=6 bot_steal=5 checkpoint=6 contact=3 craft=3 finish=3 harness_crafting=1 harness_round=1 hazard=10 item_drop=5 item_pickup=29 phase=4 race_progress=367 race_sample=717 race_start=1 respawn=6 speed_effect=125 steal=1 steal_attempt=5 vehicle_spawn=3
```
- **warn** round 1: 3 of 4 players joined (Studio did not start every client)

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
