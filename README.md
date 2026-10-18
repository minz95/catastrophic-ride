# Catastrophic Day

A competitive multiplayer racing game for Roblox (up to 10 players) built with Luau and Rojo.
Each round cycles through three phases: Farming, Crafting, and Racing.

---

## Game Loop

1. **Farming** (90 seconds) -- Collect items scattered across the biome map.
   Items have four rarity tiers (Common, Uncommon, Rare, Epic) with distinct visual effects.
   Players can contest item pickups or attempt to steal from each other's inventory.

2. **Crafting** (120 seconds) -- Assign collected items to six vehicle slots:
   BODY, ENGINE, SPECIAL, MOBILITY (biome-specific), HEAD, and TAIL.
   Stats are computed server-side based on slot assignments, item rarity, and biome affinity.

3. **Racing** -- Drive the assembled vehicle to the finish line.
   Each biome has unique physics: mud drag (Forest), buoyancy (Ocean), or updraft zones (Sky).
   Boost pads, obstacles, and drift corners add moment-to-moment decisions.

---

## Controls

### Farming
| Key | Action |
|-----|--------|
| E (tap) | Pick up nearby item / mash during contest |
| E (hold 0.9s) | Attempt to steal from nearby player |
| E (tap x3 quickly) | Defend against steal attempt |
| Q (hold) | Open emote menu |

### Crafting
| Input | Action |
|-------|--------|
| Click and drag | Place item into a vehicle slot |
| Click occupied slot | Remove assigned item |
| COMBINE button | Submit vehicle and lock in stats |

### Racing
| Key | Action |
|-----|--------|
| W / Up | Accelerate |
| S / Down | Brake / reverse |
| A / D or Left / Right | Steer |
| Shift | Drift |
| F | Activate boost when the gauge is full (drift corners fill it) |
| E | Use item ability |
| R | Respawn on the track |
| Space / Ctrl | Climb / descend (Sky) |

### Playtesting (Studio and test servers only)
| Key | Action |
|-----|--------|
| M | Mark "this is frustrating" here |
| N | Mark "this is fun" here |

The round report printed at RESULTS lists the markers per track section
(see [docs/design.md](docs/design.md)).

---

## Biomes

| Biome | Vehicle | Unique Mechanic |
|-------|---------|-----------------|
| Forest | Car | Mud zones (50% speed reduction), drift corners |
| Ocean | Boat | Buoyancy physics, floating dock track |
| Sky | Flying vehicle | Updraft zones, kill plane respawn |

---

## Project Structure

```
roblox/
  ServerScriptService/
    GameManager.server.lua          -- Master state machine (Lobby -> Farming -> Crafting -> Racing -> Results)
    SessionManager.server.lua       -- Player join/leave, data storage
    FarmingManager.server.lua       -- Item spawning, pickup authority, contest, steal
    CraftingManager.server.lua      -- Slot validation, vehicle stat calculation
    RacingManager.server.lua        -- Race state, biome physics, finish detection
    CharacterManager.server.lua     -- Skin assignment, spawn placement
    BalanceAudit.server.lua         -- Stat matrix audit (runs only in SOLO_TEST_MODE)
    TestHarness/                    -- Studio harness: RaceSim, MatchHarness, Runner (docs/testing.md)
    MapBuilders/
      ForestMapBuilder.server.lua   -- calls Modules/Maps/ForestMap (layout data in Shared/Tracks)
      OceanMapBuilder.server.lua    -- calls Modules/Maps/OceanMap
      SkyMapBuilder.server.lua      -- calls Modules/Maps/SkyMap
    PlaytestReporter.server.lua     -- M/N playtest markers + fun report at RESULTS (Studio only)
      TerrainPainter.server.lua
    Modules/
      Maps/TrackKit.lua             -- walls, floor, triggers, finish shared by all maps
      PlaytestReport.lua            -- RaceMetrics on the last race's telemetry
      BiomeConfig.lua
      ItemConfig.lua                -- 37 items with stats, slot type, rarity, icon
      ItemModelBuilder.lua          -- Procedural 3D item models
      ItemVisualUpgrader.lua        -- Rarity glow, particles, idle animation
      CharacterConfig.lua           -- 10 skin definitions
  StarterPlayer/StarterPlayerScripts/
    FarmingClient.client.lua
    RacingClient.client.lua
    SoundClient.client.lua
  StarterGui/
    HUD/                            -- Race position, boost bar, speedometer
    FarmingUI/                      -- 8-slot inventory display
    CraftingUI/                     -- Slot drag-and-drop interface
    LobbyUI/                        -- Player list, biome reveal
    EmoteUI/                        -- Q-hold radial menu
    ResultsUI/                      -- Podium and leaderboard
    TutorialUI/                     -- Phase key guide (F1 to toggle)
  ReplicatedStorage/
    RemoteEvents/                   -- All server <-> client events
    Shared/
      Constants.lua                 -- All numeric constants and flags
      ItemConfig.lua
      VehicleStats.lua              -- Pure stat calculation functions
      SoundConfig.lua               -- BGM, ambience, SFX asset ID table
      Tracks/                       -- Forest/Ocean/Sky track data (edit these, not the builders)
      TrackGeometry.lua             -- centerline math, wall layout
      VehicleController.lua         -- keys -> velocity (players, bots, simulators)
      RaceProgress.lua              -- race progress and respawn points
      RaceMetrics.lua               -- "fun" numbers for a race
      FarmingRules.lua              -- pickup / contest / steal decisions
```

---

## Development Setup

### Requirements
- [Rojo 7.6.1](https://github.com/rojo-rbx/rojo/releases) (file sync to Studio)
- Roblox Studio
- [GitHub CLI](https://cli.github.com/) (for issue/PR workflow)

### Sync to Studio

1. Start the Rojo server:
   ```
   rojo serve roblox
   ```
2. In Roblox Studio, open the Rojo plugin panel and click **Connect**.
3. All Lua source files under `roblox/` sync live to the corresponding Studio locations.

### Solo Testing

`Constants.SOLO_TEST_MODE = true` (default) starts the game 2 seconds after one player connects,
skipping the lobby wait. Set to `false` before production deployment.

### Automated tests and simulations

See [docs/testing.md](docs/testing.md). In short:

```
lune run tests/run.luau        # offline suite: real game code in a mock engine
lune run tools/report.luau     # per-biome track SVG + race/match balance report
```

In Studio, the plugin's **Race Sim** / **Bot Match** buttons (or
`require(game.ServerScriptService.TestHarness.Runner)` over the Studio MCP
server) run the race with real physics and a full round with bot clients.
The latest reports: [Forest](reports/forest/summary.md), [Ocean](reports/ocean/summary.md),
[Sky](reports/sky/summary.md).

---

## Rarity System

| Tier | Spawn share | Stat multiplier | Visual |
|------|-------------|-----------------|--------|
| Common | 60% | 1.0x | Plain white |
| Uncommon | 25% | 1.3x | Green glow ring |
| Rare | 12% | 1.6x | Blue glow + particles |
| Epic | 3% | 2.0x | Purple glow + particles + 3 orbiting orbs |

Epic items also gain 1.3x ability duration, 1.2x ability radius, and 0.8x cooldown.

---

## Sound

All audio asset IDs are stored in `ReplicatedStorage/Shared/SoundConfig.lua`.
Replace the placeholder IDs with real Roblox free audio IDs from the Toolbox before publishing.
The `SoundClient` handles BGM fading between phases and SFX routing for all game events.
