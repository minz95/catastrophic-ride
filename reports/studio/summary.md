# Studio experiments

Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` (scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.

| Scenario | Result | Commit | Ran |
|---|---|---|---|
| [abilities-forest](abilities-forest.json) | WARN | fd36242+ | 2026-10-22T02:09 |
| [abilities-ocean](abilities-ocean.json) | PASS | aeab89c | 2026-10-22T01:10 |
| [abilities-sky](abilities-sky.json) | PASS | aeab89c+ | 2026-10-22T01:19 |
| [api-analytics](api-analytics.json) | PASS | 81edf99+ | 2026-10-23T21:59 |
| [bots-abilities](bots-abilities.json) | PASS | e58978d+ | 2026-10-24T02:41 |
| [bots-fight](bots-fight.json) | PASS | 45ca943+ | 2026-10-24T11:39 |
| [bots-forest](bots-forest.json) | PASS | fce4824+ | 2026-10-24T12:29 |
| [bots-ocean](bots-ocean.json) | PASS | 4f74f56+ | 2026-10-24T00:33 |
| [bots-sky](bots-sky.json) | PASS | 4f74f56+ | 2026-10-24T00:36 |
| [craft-afk-3p](craft-afk-3p.json) | PASS | 15012db+ | 2026-10-23T21:53 |
| [escape-forest](escape-forest.json) | PASS | 9bae2bd+ | 2026-10-22T22:34 |
| [escape-ocean](escape-ocean.json) | PASS | c90f06d+ | 2026-10-23T00:03 |
| [escape-sky](escape-sky.json) | PASS | c90f06d+ | 2026-10-23T00:03 |
| [farm-forest-4p](farm-forest-4p.json) | FAIL | aeab89c+ | 2026-10-22T01:29 |
| [farm-ocean-4p](farm-ocean-4p.json) | PASS | a7efc25 | 2026-10-20T04:24 |
| [farm-sky-4p](farm-sky-4p.json) | PASS | a7efc25 | 2026-10-20T04:26 |
| [fight-4p](fight-4p.json) | PASS | 09194f2+ | 2026-10-24T02:12 |
| [gallery-hats](gallery-hats.json) | PASS | 51193a6+ | 2026-10-24T19:33 |
| [gallery-mobility](gallery-mobility.json) | PASS | 9d470b1+ | 2026-10-24T20:34 |
| [gallery](gallery.json) | PASS | 9d470b1+ | 2026-10-24T20:40 |
| [load-10p](load-10p.json) | FAIL | 62db88a+ | 2026-10-23T22:34 |
| [load-8p](load-8p.json) | WARN | 62db88a+ | 2026-10-23T22:45 |
| [match-forest](match-forest.json) | PASS | 9d470b1+ | 2026-10-24T20:38 |
| [match-ocean](match-ocean.json) | PASS | 2315090+ | 2026-10-22T23:11 |
| [match-sky](match-sky.json) | PASS | a81a12d+ | 2026-10-23T23:53 |
| [race-forest-builds](race-forest-builds.json) | PASS | 954581a+ | 2026-10-21T13:22 |
| [race-forest](race-forest.json) | PASS | c90f06d+ | 2026-10-23T00:20 |
| [race-ocean-builds](race-ocean-builds.json) | PASS | 954581a+ | 2026-10-21T12:53 |
| [race-ocean](race-ocean.json) | PASS | 2315090+ | 2026-10-22T23:02 |
| [race-sky-builds](race-sky-builds.json) | PASS | 954581a+ | 2026-10-21T12:56 |
| [race-sky](race-sky.json) | PASS | c90f06d+ | 2026-10-23T00:01 |
| [shop-4p](shop-4p.json) | PASS | 1bde8b9+ | 2026-10-24T00:10 |
| [showroom](showroom.json) | PASS | fce4824+ | 2026-10-24T12:35 |
| [sounds](sounds.json) | PASS | 9fbb280+ | 2026-10-23T21:23 |
| [start-6p](start-6p.json) | FAIL | aeab89c+ | 2026-10-22T01:26 |
| [steal-4p](steal-4p.json) | PASS | aa48bae+ | 2026-10-22T02:23 |
| [steal-crowd-6p](steal-crowd-6p.json) | PASS | a7efc25 | 2026-10-20T04:33 |
| [steal-defended-2p](steal-defended-2p.json) | PASS | aa48bae+ | 2026-10-22T02:21 |
| [vehicles-forest](vehicles-forest.json) | PASS | f7b6b60+ | 2026-10-24T02:27 |
| [vehicles-ocean](vehicles-ocean.json) | PASS | f7b6b60+ | 2026-10-24T02:28 |
| [vehicles-sky](vehicles-sky.json) | PASS | f7b6b60+ | 2026-10-24T02:28 |

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

## api-analytics — PASS

```
probeApi: 12 members, 0 missing
```

## bots-abilities — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 1
    steal attempts: none
    -100003: picked 4, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -100001: picked 6, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -100002: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -1: picked 1, contests 0/0, stole 0, robbed 0, defences 0, items 1 | craft submitted, rejected 0
  events: ability=22 ability_probe=42 ability_target=1 bot_blocked=1 bot_craft=1 bot_farm=18 bot_fx=28 bot_hud=6 bot_joined=1 bot_ready=1 bot_respawn=1 bot_screen=2 checkpoint=2 craft=1 drift_turbo=7 drop_placed=9 farm_bot=3 harness_crafting=1 harness_round=1 hazard=31 hit=3 item_pickup=19 item_wave=3 phase=4 race_bot=3 race_go=1 race_launch=1 race_progress=363 race_sample=185 race_start=1 race_timeout=1 respawn=1 reward=1 server_perf=56 speed_effect=91 vehicle_spawn=
driving: 0 hits, 7 drift turbos, drops: Log
farm bots: 3 on the farm, 18 pickups, 0 punches thrown, 0 punches/steals on bots
ability targets: 1, on bots 1
bots: 3 raced (average, novice, expert), 3 farmed their car, 0 finished: 
server: FARMING heartbeat 57-60 Hz, physics 59-60 fps, send max 67 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 10 kbps; RACING heartbeat 59-60 Hz, physics 60-60 fps, send max 23 kbps; memory max 2269 MB
```

## bots-fight — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 1
    steal attempts: none
    -100003: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -100001: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -100002: picked 8, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -1: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  events: bot_craft=1 bot_farm=29 bot_farmfx=16 bot_hud=31 bot_joined=1 bot_punch=77 bot_ready=1 bot_screen=2 craft=1 farm_bot=3 harness_crafting=1 harness_round=1 item_pickup=24 item_wave=3 phase=3 punch=77 race_bot=3 race_sample=2 race_start=1 server_perf=34 vehicle_spawn=1
farm bots: 3 on the farm, 24 pickups, 0 punches thrown, 16 punches/steals on bots
farm bots: 0 steals tried (0 stolen), 5 guards
bots: 3 raced (average, novice, expert), 3 farmed their car, 0 finished: 
server: FARMING heartbeat 58-60 Hz, physics 59-60 fps, send max 231 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 5 kbps; memory max 2296 MB
```

## bots-forest — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 1 finished of 1
    steal attempts: defended=3, denied: too late=1, stolen=1
    -100003: picked 8, contests 4/4, stole 0, robbed 1, defences 0, items nil
    -100001: picked 5, contests 0/5, stole 0, robbed 0, defences 0, items nil
    -100002: picked 7, contests 0/0, stole 0, robbed 0, defences 0, items nil
    -1: picked 7, contests 1/1, stole 1, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    #1 Player1 105.8s
  events: ability=114 ability_probe=98 ability_target=6 bot_ability=41 bot_craft=1 bot_defend=1 bot_farm=26 bot_farmfx=19 bot_fx=59 bot_guard=1 bot_hud=23 bot_joined=1 bot_ready=1 bot_respawn=2 bot_screen=3 bot_steal=1 checkpoint=2 contest_result=5 craft=1 drift_turbo=10 drop_placed=14 farm_bot=3 finish=4 harness_crafting=1 harness_round=1 hazard=38 hit=1 item_pickup=27 item_wave=3 phase=4 phase_shortened=1 pun
driving: 0 hits, 10 drift turbos, drops: Gas Can, Pizza
farm bots: 3 on the farm, 20 pickups, 1 punches thrown, 4 punches/steals on bots
farm bots: 3 steals tried (0 stolen), 0 guards
bot abilities: 41 fired (Barrel, Cardboard Box, Gas Can, Hair Dryer, Pizza, Suitcase, Toilet Paper)
ability targets: 6, on bots 6
bots: 3 raced (average, novice, expert), 3 farmed their car, 3 finished: 121.0s, 123.9s, 126.8s
server: FARMING heartbeat 58-60 Hz, physics 60-60 fps, send max 54 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 51 kbps; RACING heartbeat 59-60 Hz, physics 60-60 fps, send max 54 kbps; memory max 2296 MB
```

## bots-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (OCEAN): 1 finished of 1
    steal attempts: none
    -1: picked 7, contests 0/0, stole 0, robbed 0, defences 0, items 7 | craft submitted, rejected 0
    #1 Player1 91.8s
  events: ability=16 ability_probe=35 bot_craft=1 bot_fx=20 bot_hud=11 bot_joined=1 bot_pickup_denied=1 bot_ready=1 bot_screen=3 checkpoint=2 craft=1 drift_turbo=8 finish=4 harness_crafting=1 harness_round=1 hazard=6 item_pickup=7 item_wave=3 phase=4 phase_shortened=1 race_bot=3 race_go=1 race_launch=1 race_progress=401 race_sample=209 race_start=1 reward=1 server_perf=67 speed_effect=82 vehicle_spawn=1
driving: 0 hits, 8 drift turbos
bots: 3 raced (average, novice, expert), 3 finished: 96.2s, 97.2s, 102.5s
server: FARMING heartbeat 58-60 Hz, physics 59-60 fps, send max 24 kbps; RACING heartbeat 60-60 Hz, physics 60-60 fps, send max 30 kbps; memory max 2263 MB
```

## bots-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (SKY): 1 finished of 1
    steal attempts: none
    -1: picked 6, contests 0/0, stole 0, robbed 0, defences 0, items 6 | craft submitted, rejected 0
    #1 Player1 86.3s
  events: ability=20 ability_probe=42 bot_craft=1 bot_fx=18 bot_hud=11 bot_joined=1 bot_ready=1 bot_respawn=5 bot_screen=3 checkpoint=2 craft=1 drop_placed=8 finish=4 harness_crafting=1 harness_round=1 hazard=11 item_pickup=6 item_wave=3 phase=4 phase_shortened=1 race_bot=3 race_go=1 race_launch=1 race_progress=443 race_sample=258 race_start=1 reward=1 server_perf=79 speed_effect=48 vehicle_spawn=1
driving: 0 hits, 0 drift turbos, drops: Magnifying Glass
bots: 3 raced (average, novice, expert), 3 finished: 91.5s, 94.7s, 127.2s
server: FARMING heartbeat 58-60 Hz, physics 60-60 fps, send max 24 kbps; RACING heartbeat 59-60 Hz, physics 60-60 fps, send max 36 kbps; memory max 2247 MB
```

## craft-afk-3p — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 1
  round 1 (FOREST): 0 finished of 4
    steal attempts: denied: too far=2, denied: victim has nothing=1
    -4: picked 15, contests 1/4, stole 0, robbed 0, defences 0, items 8 | craft auto, rejected 0
    -2: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft auto, rejected 0
    -1: picked 12, contests 2/3, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 15, contests 1/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
  events: ability=3 bot_craft=3 bot_farmfx=52 bot_guard=3 bot_hud=218 bot_joined=4 bot_pickup_denied=1 bot_punch=7 bot_ready=4 bot_screen=8 bot_steal=3 contest_result=4 craft=4 harness_crafting=1 harness_round=1 item_drop=18 item_pickup=42 item_wave=3 phase=3 punch=7 race_sample=8 race_start=1 steal_attempt=3 vehicle_spawn=4
```

## escape-forest — PASS

```
RaceSim FOREST (shipped) — 4.5s wall time
  cases 65: drove out 65, needed a respawn 0, stuck 0
```

## escape-ocean — PASS

```
RaceSim OCEAN (shipped) — 5.4s wall time
  cases 48: drove out 48, needed a respawn 0, stuck 0
```

## escape-sky — PASS

```
RaceSim SKY (shipped) — 7.5s wall time
  cases 54: drove out 54, needed a respawn 0, stuck 0
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
    -4: picked 14, contests 3/3, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 17, contests 2/2, stole 0, robbed 0, defences 0, items 7 | craft submitted, rejected 0
    -1: picked 0, contests 0/3, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -3: picked 0, contests 0/2, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
  events: ability=2 bot_craft=4 bot_farmfx=96 bot_guard=21 bot_hud=183 bot_joined=4 bot_punch=130 bot_ready=4 bot_screen=8 contest_result=5 craft=4 harness_crafting=1 harness_round=1 item_drop=16 item_dropped_world=16 item_pickup=31 item_wave=3 phase=3 punch=130 race_sample=8 race_start=1 server_perf=52 vehicle_spawn=4
server: FARMING heartbeat 54-60 Hz, physics 58-60 fps, send max 111 kbps; RACING heartbeat 59-59 Hz, physics 60-60 fps, send max 235 kbps; memory max 2287 MB
```

## gallery-hats — PASS

```
gallery: 15 vehicles, 10 shots, 12 riding their BODY item, 15 riders made, 15 seated, 12 hats worn
```

## gallery-mobility — PASS

```
gallery: 15 vehicles, 25 shots, 12 riding their BODY item, 15 riders made, 15 seated, 3 hats worn, 0 loose wheels / paddles / propellers
```

## gallery — PASS

```
gallery: 75 vehicles, 50 shots, 72 riding their BODY item, 75 riders made, 75 seated, 15 hats worn, 0 loose wheels / paddles / propellers
```

## load-10p — FAIL

```
ERROR number of players should be integer between 0 and 8
```
- **fail** no report (session returned nothing)

## load-8p — WARN

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 5 finished of 7
    steal attempts: defended=7, denied: too far=4, denied: too late=1, denied: victim has nothing=6, denied: victim under attack=1, stolen=1
    -3: picked 11, contests 1/1, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 7, contests 3/7, stole 0, robbed 1, defences 0, items 6 | craft submitted, rejected 0
    -1: picked 1, contests 0/2, stole 0, robbed 0, defences 2, items 1 | craft submitted, rejected 0
    -4: picked 11, contests 0/0, stole 0, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    -5: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -6: picked 4, contests 0/1, stole 0, robbed 0, defences 3, items 4 | craft submitted, rejected 0
    -7: picked 7, contests 4/5, stole 0, robbed 0, defences 1, items 7 | craft subm
driving: 12 hits (closing speed max 50, push max 39 studs/s), 60 drift turbos
server: FARMING heartbeat 50-60 Hz, physics 54-60 fps, send max 134 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 17 kbps; RACING heartbeat 55-60 Hz, physics 59-60 fps, send max 31 kbps; memory max 2262 MB
```
- **warn** round 1: 7 of 8 players joined (Studio did not start every client)

## match-forest — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (FOREST): 4 finished of 4
    steal attempts: stolen=3
    -4: picked 10, contests 0/0, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 13, contests 1/1, stole 0, robbed 2, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 8, contests 0/0, stole 1, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -3: picked 7, contests 0/1, stole 2, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    #1 Player2 114.3s
    #2 Player1 117.0s
    #3 Player4 120.1s
    #4 Player3 121.6s
  events: ability=77 ability_probe=241 bot_craft=4 bot_defend=3 bot_farmfx=112 bot_fx=352 bot_guard=6 bot_hud=123 bot_joined=4 bot_punch=13 bot_ready=4 bot_respawn=1 bot_screen=15 bot_spin_fx=125 bot_steal=3 checkpoint=8 contact=24 contest_result=1 craft=4 craft_preview=8 drift_turbo=40 drop_placed=9 finish=
driving: 12 hits (closing speed max 69, push max 45 studs/s), 40 drift turbos, drops: Cactus
spinning MOBILITY items: 2 cars (wheel), most turns 2200
server: FARMING heartbeat 51-60 Hz, physics 55-60 fps, send max 214 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 9 kbps; RACING heartbeat 59-60 Hz, physics 60-60 fps, send max 10 kbps; memory max 2312 MB
```

## match-ocean — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 1
  round 1 (OCEAN): 4 finished of 4
    steal attempts: defended=5, denied: too far=4, stolen=2
    -4: picked 12, contests 1/2, stole 0, robbed 1, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 13, contests 1/2, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 10, contests 2/3, stole 1, robbed 1, defences 3, items 8 | craft submitted, rejected 0
    -3: picked 7, contests 0/1, stole 1, robbed 0, defences 2, items 8 | craft submitted, rejected 0
    #1 Player1 97.5s
    #2 Player4 98.7s
    #3 Player2 105.4s
    #4 Player3 112.1s
  events: ability=97 ability_probe=208 bot_craft=4 bot_defend=7 bot_farmfx=144 bot_fx=328 bot_guard=3 bot_hud=122 bot_joined=4 bot_punch=12 bot_ready=4 bot_respawn=3 bot_screen=22 bot_steal=11 checkpoint=8 cleanse=6 contact=8 contest_result=4 craft=4 drift_turbo=10 drop_placed=36
driving: 4 hits (closing speed max 53, push max 37 studs/s), 10 drift turbos, drops: Cactus, Gas Can, Kettle, Log
```

## match-sky — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 0
  round 1 (SKY): 4 finished of 4
    steal attempts: defended=4, denied: too far=4, denied: victim has nothing=5, stolen=1
    -4: picked 11, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -2: picked 12, contests 0/1, stole 0, robbed 0, defences 0, items 8 | craft submitted, rejected 0
    -1: picked 7, contests 4/6, stole 0, robbed 1, defences 3, items 6 | craft submitted, rejected 0
    -3: picked 8, contests 2/5, stole 1, robbed 0, defences 1, items 8 | craft submitted, rejected 0
    #1 Player2 83.6s
    #2 Player4 85.7s
    #3 Player1 88.2s
    #4 Player3 122.9s
  events: ability=92 ability_probe=189 bot_craft=4 bot_defend=5 bot_farmfx=128 bot_fx=304 bot_guard=3 bot_hud=124 bot_joined=4 bot_punch=13 bot_ready=4 bot_respawn=14 bot_screen=29 bot_steal=14 checkpoint=8 contact=13 contest_result=6 craft=4 drop_placed
driving: 5 hits (closing speed max 60, push max 44 studs/s), 0 drift turbos, drops: Cactus
server: FARMING heartbeat 56-60 Hz, physics 58-60 fps, send max 76 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 6 kbps; RACING heartbeat 58-60 Hz, physics 60-60 fps, send max 13 kbps; memory max 2242 MB
```

## race-forest-builds — PASS

```
RaceSim FOREST (shipped) — 128.9s wall time
  novice   [slowest-novice] car=slowest max=65 mass=10.12 → 129.19s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=73 mass=7.41 → 93.44s | CPs 2 | respawns 0 | blocked 0
```

## race-forest — PASS

```
RaceSim FOREST (shipped) — 125.3s wall time
  expert   car=p50 max=69 mass=7.88 → 113.76s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=69 mass=7.88 → 120.65s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=69 mass=7.88 → 126.68s | CPs 2 | respawns 0 | blocked 0
drifts: expert 19/10, average 33/9, novice 0/0
```

## race-ocean-builds — PASS

```
RaceSim OCEAN (shipped) — 130.2s wall time
  novice   [slowest-novice] car=slowest max=59 mass=6.28 → 130.59s | CPs 2 | respawns 0 | blocked 0
  expert   [fastest-expert] car=fastest max=63 mass=6.51 → 91.5s | CPs 2 | respawns 0 | blocked 0
```

## race-ocean — PASS

```
RaceSim OCEAN (shipped) — 109.3s wall time
  expert   car=p50 max=62 mass=6.46 → 102.36s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=62 mass=6.46 → 104.23s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=62 mass=6.46 → 110.61s | CPs 2 | respawns 0 | blocked 0
drifts: expert 24/3, average 29/0, novice 0/0
```

## race-sky-builds — PASS

```
RaceSim SKY (shipped) — 140.9s wall time
  novice   [slowest-novice] car=slowest max=82 mass=2.64 → 141.26s | CPs 2 | respawns 1 | blocked 0
  expert   [fastest-expert] car=fastest max=92 mass=2.83 → 89.3s | CPs 2 | respawns 0 | blocked 0
```

## race-sky — PASS

```
RaceSim SKY (shipped) — 133.4s wall time
  expert   car=p50 max=87 mass=2.9 → 106.01s | CPs 2 | respawns 0 | blocked 0
  average  car=p50 max=87 mass=2.9 → 102.58s | CPs 2 | respawns 0 | blocked 0
  novice   car=p50 max=87 mass=2.9 → 134.95s | CPs 2 | respawns 0 | blocked 0
```

## shop-4p — PASS

```
Bot match: 1 round(s), end: rounds complete, server errors: 0, client errors: 1
  round 1 (FOREST): 4 finished of 4
    steal attempts: denied: too late=1, denied: victim has nothing=22, escaped=1
    -4: picked 0, contests 0/0, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -2: picked 0, contests 0/3, stole 0, robbed 0, defences 0, items 0 | craft submitted, rejected 0
    -1: picked 4, contests 0/0, stole 0, robbed 0, defences 0, items 4 | craft submitted, rejected 0
    -3: picked 10, contests 3/3, stole 0, robbed 0, defences 0, items 7 | craft submitted, rejected 0
    #1 Player1 97.0s
    #2 Player4 111.2s
    #3 Player2 123.8s
    #4 Player3 127.9s
  events: ability=54 ability_probe=198 bot_craft=4 bot_defend=1 bot_farmfx=76 bot_fx=284 bot_gadget=1 bot_guard=8 bot_hud=123 bot_joined=4 bot_pickup_denied=1 bot_punch=106 bot_ready=4 bot_respawn=6 bot_ride_fx=261 bot_screen=20 bot_shop=10 bot_steal=24 check
driving: 2 hits (closing speed max 20, push max 19 studs/s), 36 drift turbos, drops: Kettle
server: FARMING heartbeat 56-60 Hz, physics 58-60 fps, send max 28496 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 26 kbps; RACING heartbeat 58-60 Hz, physics 60-60 fps, send max 40 kbps; memory max 2284 MB
```

## showroom — PASS

```
Bot match: 1 round(s), end: stopAfter CRAFTING, server errors: 0, client errors: 0
  round 1 (FOREST): 0 finished of 1
    steal attempts: none
    -1: picked 12, contests 0/0, stole 0, robbed 0, defences 0, items 8 | craft auto, rejected 0
  events: ability=1 bot_craft=1 bot_farmfx=4 bot_hud=35 bot_joined=1 bot_pickup_denied=1 bot_ready=1 bot_screen=2 craft=1 craft_preview=2 harness_crafting=1 harness_round=1 item_drop=4 item_dropped_world=4 item_pickup=12 item_wave=3 phase=3 race_sample=2 race_start=1 server_perf=38 vehicle_spawn=1
server: FARMING heartbeat 58-60 Hz, physics 59-60 fps, send max 25 kbps; CRAFTING heartbeat 60-60 Hz, physics 60-60 fps, send max 14 kbps; memory max 2282 MB
```

## sounds — PASS

```
SoundCheck: 50 sounds load, 0 missing
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
RaceSim FOREST (shipped) — 9.7s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-ocean — PASS

```
RaceSim OCEAN (shipped) — 11.3s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```

## vehicles-sky — PASS

```
RaceSim SKY (shipped) — 10.9s wall time
  cases 20: drove out 20, needed a respawn 0, stuck 0
```
