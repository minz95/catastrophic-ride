# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [escape-forest-novice](escape-forest-novice.json) | PASS | 979d8c1 | 2026-10-20T02:19 |
| [escape-forest](escape-forest.json) | PASS | 979d8c1 | 2026-10-20T02:18 |
| [escape-ocean](escape-ocean.json) | PASS | 979d8c1 | 2026-10-20T02:18 |
| [escape-sky](escape-sky.json) | PASS | 979d8c1 | 2026-10-20T02:19 |
| [match-forest-2rounds](match-forest-2rounds.json) | PASS | 979d8c1 | 2026-10-20T02:40 |
| [match-forest](match-forest.json) | PASS | 4b7461a | 2026-10-20T03:14 |
| [match-ocean](match-ocean.json) | PASS | 979d8c1 | 2026-10-20T02:28 |
| [match-sky](match-sky.json) | PASS | 979d8c1 | 2026-10-20T02:32 |
| [race-forest-builds](race-forest-builds.json) | PASS | 4b7461a | 2026-10-20T03:04 |
| [race-forest-contact](race-forest-contact.json) | PASS | c7dab7c | 2026-10-20T02:58 |
| [race-forest-heavy](race-forest-heavy.json) | PASS | c7dab7c | 2026-10-20T02:49 |
| [race-forest-intended](race-forest-intended.json) | PASS | 979d8c1 | 2026-10-20T02:17 |
| [race-forest](race-forest.json) | PASS | 979d8c1 | 2026-10-20T01:45 |
| [race-ocean-builds](race-ocean-builds.json) | PASS | 4b7461a | 2026-10-20T03:08 |
| [race-ocean-contact](race-ocean-contact.json) | PASS | c7dab7c | 2026-10-20T02:47 |
| [race-ocean](race-ocean.json) | PASS | 979d8c1 | 2026-10-20T01:48 |
| [race-sky-builds](race-sky-builds.json) | PASS | c7dab7c | 2026-10-20T02:56 |
| [race-sky-contact](race-sky-contact.json) | PASS | 4b7461a | 2026-10-20T03:11 |
| [race-sky](race-sky.json) | PASS | 979d8c1 | 2026-10-20T01:50 |

## escape-forest-novice — PASS

```
RaceSim FOREST (shipped) — 5.9s wall time
  cases 62: drove out 62, needed a respawn 0, stuck 0
```

## escape-forest — PASS

```
RaceSim FOREST (shipped) — 6.3s wall time
  cases 62: drove out 62, needed a respawn 0, stuck 0
```

## escape-ocean — PASS

```
RaceSim OCEAN (shipped) — 7.9s wall time
  cases 45: drove out 45, needed a respawn 0, stuck 0
```

## escape-sky — PASS

```
RaceSim SKY (shipped) — 14.4s wall time
  cases 51: drove out 51, needed a respawn 0, stuck 0
```

## match-forest-2rounds — PASS

```
Bot match: 2 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 3 finished of 3
    #1 Player1 104.7s
    #2 Player3 129.8s
    #3 Player2 145.0s
  round 2 (FOREST): 3 finished of 3
    #1 Player3 129.9s
    #2 Player1 139.0s
    #3 Player2 172.3s
  events: bot_craft=6 bot_joined=3 bot_ready=3 bot_respawn=19 checkpoint=12 contact=20 contest_result=5 craft=6 finish=6 hazard=73 hit=7 item_pickup=40 phase=9 race_progress=950 race_sample=1860 race_start=2 respawn=56 speed_effect=738 vehicle_spawn=6
```

## match-forest — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 4 finished of 4
    #1 Player1 79.9s
    #2 Player2 80.3s
    #3 Player4 100.1s
    #4 Player3 120.0s
  events: bot_craft=4 bot_joined=4 bot_pickup_denied=1 bot_ready=4 bot_respawn=7 checkpoint=8 contact=14 craft=4 finish=4 hazard=27 hit=10 item_pickup=40 phase=4 race_progress=477 race_sample=875 race_start=1 respawn=26 speed_effect=443 vehicle_spawn=4
```

## match-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (OCEAN): 4 finished of 4
    #1 Player4 72.7s
    #2 Player1 73.1s
    #3 Player2 74.2s
    #4 Player3 110.8s
  events: bot_craft=4 bot_joined=4 bot_ready=4 bot_respawn=12 checkpoint=8 contact=48 contest_result=6 craft=4 finish=4 hazard=6 item_pickup=41 phase=4 race_progress=441 race_sample=863 race_start=1 respawn=12 speed_effect=341 vehicle_spawn=4
```

## match-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 1
  round 1 (SKY): 4 finished of 4
    #1 Player1 81.4s
    #2 Player2 86.7s
    #3 Player4 99.5s
    #4 Player3 129.9s
  events: bot_craft=4 bot_joined=4 bot_pickup_denied=1 bot_ready=4 bot_respawn=13 checkpoint=8 contact=7 contest_result=3 craft=4 finish=4 hazard=10 item_pickup=42 phase=4 race_progress=517 race_sample=1015 race_start=1 respawn=13 speed_effect=173 vehicle_spawn=4
```

## race-forest-builds — PASS

```
RaceSim FOREST (shipped) — 164s wall time
  novice   [slowest-novice] car=slowest max=49 mass=14.56 → 164.65s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=87 mass=10.64 → 77.85s | CPs 2 | respawns 0 | blocked 0
```

## race-forest-contact — PASS

```
RaceSim FOREST (shipped) — 142.2s wall time
  expert   car=p50 max=68 mass=11.53 → 142.91s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=68 mass=11.53 → 117.58s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=68 mass=11.53 → 131.11s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=68 mass=11.53 → 121.96s | CPs 2 | respawns 0 | blocked 0
  expert   car=p50 max=68 mass=11.53 → 142.29s | CPs 2 | respawns 0 | blocked 0
```

## race-forest-heavy — PASS

```
RaceSim FOREST (shipped) — 125.6s wall time
  expert   car=p50 max=68 mass=31.53 → 113.38s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=68 mass=31.53 → 126.35s | CPs 2 | respawns 0 | blocked 0
```

## race-forest-intended — PASS

```
RaceSim FOREST (intended) — 113s wall time
  average  car=p50 max=68 mass=11.53 → 113.94s | CPs 2 | respawns 0 | blocked 0
```

## race-forest — PASS

```
RaceSim FOREST (shipped) — 126s wall time
  expert   car=p50 max=68 mass=11.53 → 112.21s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=68 mass=11.53 → 112.63s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=68 mass=11.53 → 126.76s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean-builds — PASS

```
RaceSim OCEAN (shipped) — 187.3s wall time
  novice   [slowest-novice] car=slowest max=33 mass=7.64 → 188.06s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=60 mass=8.27 → 96.19s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean-contact — PASS

```
RaceSim OCEAN (shipped) — 143.8s wall time
  expert   car=p50 max=49 mass=7.73 → 130.8s | CPs 2 | respawns 1 | blocked 0
  average  car=p50 max=49 mass=7.73 → 126.93s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=49 mass=7.73 → 145.13s | CPs 2 | respawns 1 | blocked 0
  average  car=p50 max=49 mass=7.73 → 142.01s | CPs 2 | respawns 1 | blocked 0
  expert   car=p50 max=49 mass=7.73 → 122.65s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean — PASS

```
RaceSim OCEAN (shipped) — 137.8s wall time
  expert   car=p50 max=49 mass=7.73 → 122.65s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=49 mass=7.73 → 126.31s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=49 mass=7.73 → 138.52s | CPs 2 | respawns 0 | blocked 0
```

## race-sky-builds — PASS

```
RaceSim SKY (shipped) — 180.6s wall time
  novice   [slowest-novice] car=slowest max=52 mass=3.42 → 181.29s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=93 mass=3.68 → 88.92s | CPs 2 | respawns 0 | blocked 0
```

## race-sky-contact — PASS

```
RaceSim SKY (shipped) — 142.8s wall time
  expert   car=p50 max=74 mass=3.57 → 114.53s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=74 mass=3.57 → 134.03s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=74 mass=3.57 → 143.83s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=74 mass=3.57 → 127.36s | CPs 2 | respawns 0 | blocked 0
  expert   car=p50 max=74 mass=3.57 → 116.83s | CPs 2 | respawns 0 | blocked 0
```

## race-sky — PASS

```
RaceSim SKY (shipped) — 134s wall time
  expert   car=p50 max=74 mass=3.57 → 114.16s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=74 mass=3.57 → 119.13s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=74 mass=3.57 → 134.88s | CPs 2 | respawns 0 | blocked 0
```
