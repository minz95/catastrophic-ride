# Launch checklist

What is left to publish Catastrophic Ride on Roblox and measure how players
react. Code-side switches are already set for a live server
(`Constants.SOLO_TEST_MODE = false`, live lobby countdown, DiagnosticLogger
and playtest markers Studio-only, a leftover `HarnessArgs` attribute is
ignored on a published place); `tests/specs/lobby.spec.luau` keeps them so.

## Release day, in order

Who: **you** = the place owner in Studio / Creator Dashboard; **repo** =
already done in this repository.

1. **repo** `main` is green: `lune run tests/run.luau`, CI, and the Studio
   batch (`python3 tools/studio/sim.py run core`, plus `bots-forest`,
   `bots-ocean`, `bots-sky`, `match-sky`) on the commit you publish.
2. **you** Open the published place in Studio (Universe 9983801557, Place
   74883519312765). Run `rojo serve roblox` and press **Connect** in the Rojo
   plugin; wait for the sync, then **Disconnect**.
3. **you** Studio Test → Start (one player): play one round (farm, craft,
   race). Then Test → Clients and Servers with 2–4 players for one round.
4. **you** File → **Publish to Roblox** (Alt+P). Keep the place **Private**.
5. **you** Creator Dashboard: the settings in section 1 (max players 10,
   devices, genre), the **Maturity questionnaire**, the store page (section
   3: title, description, `assets/store/icon.png`, the five
   `assets/store/*.png` thumbnails).
6. **you** Optional: the three coin packs (section 2), ids into
   `Shared/Products.lua`, sync, publish again.
7. **you** Join the live game from the Roblox app (not Studio) with a
   friend: a full round, then rejoin: Level / Coins kept (real DataStore).
   On a phone too.
8. **you** Privacy → Friends for a day, then **Public**. Watch section 5.

If a live server misbehaves: Creator Dashboard → the place → Version
History → restore the previous version (publishing is reversible).

## 1. Publish and settings (Creator Dashboard / Studio Game Settings)

| Setting | Value | Why |
|---|---|---|
| Workspace → StreamingEnabled | **Off** | Rojo sets it too; with it on, item models looked broken and players froze after teleports |
| Max players per server | **10** | `Constants.MAX_PLAYERS` and the 10 character skins |
| Genre | Racing (or Party & Casual) | |
| Devices | Computer, Phone, Tablet, Console | touch buttons: `TouchControls`; gamepad: `KeyInput.GAMEPAD` |
| Security → Enable Studio Access to API Services | On | saves (DataStore) work in Studio playtests; Studio uses its own store `PlayerProgress_studio`, so Studio play and test purchases never touch live players' records |
| Maturity & compliance questionnaire | fill in (cartoon fighting: punches, no blood) | required before public |
| Privacy | Private → Friends → Public | invite friends first, then open |
| Private servers | On, free or 10 R$ | friends groups keep playing together |

## 2. Robux coin packs (optional at launch)

Monetization → Developer Products → create three products, then put each id
into `roblox/ReplicatedStorage/Shared/Products.lua` (`id = 0` packs are
hidden and cannot be bought):

| key | name | coins | price |
|---|---|---|---|
| coins_small | Pouch of Coins | 300 | 49 R$ |
| coins_medium | Bag of Coins | 1000 | 129 R$ |
| coins_large | Chest of Coins | 2500 | 279 R$ |

Coins buy looks (special rides, paints, trails), the Flying Kick (a look)
and the Smoke Bomb (one escape per round); nothing sold changes speed.
`reports/economy.md` shows how long each item takes to earn.

## 3. Store page

**Title:** Catastrophic Ride

**Description (English, paste as is):**

> Grab junk. Build a ride. Race your friends!
>
> Run around the farm and grab everything you can: barrels, bathtubs,
> rubber ducks, rockets. Punch, guard and steal to keep the best stuff. Then
> bolt your loot onto a car, a boat or a plane and race across the Forest,
> the Ocean and the Sky. Every item gives your ride its own trick: press E
> (or ITEM) to use it.
>
> - 3 worlds: drive the forest, sail the ocean, fly through the clouds
> - 39 items, each with its own ability: ride a pizza, roll on rubber-duck
>   wheels, wear a cactus as a hat
> - Watch your ride turn on the showroom stand while you build it
> - Steal, punch and guard while you farm
> - Fly off jump ramps and spring over a broken bridge, drift for
>   mini-turbos, ride updrafts in the sky, dodge falling logs
> - Level up, keep your daily streak, unlock paints, trails and special rides
>   like the Rainbow Comet and the Golden Legend
>
> PC: WASD drive · Shift drift · F boost · E item / grab · F punch · G guard
> Phone: thumbstick to drive, buttons on the right
> Gamepad: triggers / stick drive · X item / grab · B boost / punch · L1 drift · R1 guard

**Icon** (512 × 512, no text needed) and **thumbnails** (1920 × 1080):
`assets/store/` (`icon.png`, `1_grid`, `2_ramp_jump`, `3_gap_jump`,
`4_ocean`, `5_sky`), taken from the real maps by `python3
tools/studio/sim.py run promo` (TestHarness/Promo: the race lighting,
varied builds and riders, cars frozen mid-jump). Re-run it after visual
changes; the screen must be awake and unlocked, and a bigger Studio view
(close the Output / Explorer panels) gives sharper pictures. A crafting
screen or farm brawl picture needs a play client: Studio Test → Clients and
Servers, then View → Screenshot.

## 4. Before going public

- [ ] Friends playtest (2–5 people), M / N markers on: fun and frustrating spots
- [ ] Try it on a phone (thumbstick driving, buttons, the shop and crafting screens fit) and with a gamepad
- [ ] Listen to the music and sounds (`Shared/SoundConfig`, picked by title)
- [ ] One 10-player live server (Studio can only test 8): watch the Developer Console → Server Stats
- [ ] Real DataStore: play a round, rejoin, Level / Coins are kept
- [ ] If coin packs are set: a test purchase in Studio grants once

## 5. After launch: what to watch (Creator Dashboard → Analytics)

- Retention D1 / D7 (Roblox computes it), average session length
- Funnels: **Onboarding** (Joined → First pickup → Car built → Raced →
  Finished a race → Got a reward) and **Round** (where a round loses people)
- Custom events: `ReturnDay` (on which day players come back), `RoundPlace`
- Economy: coins earned vs spent (are shop prices reachable?)

A first-week rule of thumb for small Roblox games: D1 around 20 % or more and
sessions over 10 minutes mean the loop works; worse, look at the funnel step
where most players leave before adding content or ads.

## Player data requests

Roblox sends "Right to erasure" requests for a UserId: delete the key
`u<UserId>` in the DataStore `PlayerProgress_v1` (Creator Dashboard → the
experience → Data Stores, or `DataStore:RemoveAsync`).

## Known gaps

- Positions are the client's (Roblox physics ownership): a cheat that moves
  its own character or car is not caught in general. The finish needs most
  of the road driven at a believable speed, and every farm action is
  checked for range and rate, but there is no speed / teleport detector.

- Bots fill each round to 4–6 racers (drawn per round): they farm, punch, guard, steal, race and fire
  their abilities; they ride updrafts and jumps like players.
- Gamepad and touch buttons are tested offline only (key mapping); try
  them on a device before going public.
- The finish grace (45 s after the winner) sometimes cuts off the slowest
  driver when the winner is very fast (Studio match-forest, 2026-10-23: a
  novice 170 studs short).
