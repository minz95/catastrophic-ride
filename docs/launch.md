# Launch checklist

What is left to publish Catastrophic Day on Roblox and measure how players
react. Code-side switches are already set for a live server
(`Constants.SOLO_TEST_MODE = false`, live lobby countdown, DiagnosticLogger
and playtest markers Studio-only); `tests/specs/lobby.spec.luau` keeps them so.

## 1. Publish and settings (Creator Dashboard / Studio Game Settings)

| Setting | Value | Why |
|---|---|---|
| Max players per server | **10** | `Constants.MAX_PLAYERS` and the 10 character skins |
| Genre | Racing (or Party & Casual) | |
| Devices | Computer, Phone, Tablet, Console | touch buttons: `TouchControls`; gamepad: `KeyInput.GAMEPAD` |
| Security → Enable Studio Access to API Services | On | saves (DataStore) work in Studio playtests |
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

**Title:** Catastrophic Day

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
> - 39 items, each with its own ability
> - Steal, punch and guard while you farm
> - Drift for mini-turbos, hit boost pads, dodge falling logs
> - Level up, keep your daily streak, unlock paints, trails and special rides
>   like the Rainbow Comet and the Golden Legend
>
> PC: WASD drive · Shift drift · F boost · E item / grab · F punch · G guard
> Phone: thumbstick to drive, buttons on the right
> Gamepad: triggers / stick drive · X item / grab · B boost / punch · L1 drift · R1 guard

**Icon** (512 × 512, no text needed): one vehicle built from silly items
(bathtub body, rocket engine, rubber duck on top) mid-jump, bright sky.

**Thumbnails** (1920 × 1080, 3–5): a race start with 6+ cars on the grid; a
plane through the Sky cloud corkscrew; a boat on the Ocean water slide; the
crafting screen with items in slots; a farm brawl with a punch landing.
Studio screenshots (View → Screenshot) of a bot match work: `python3
tools/studio/sim.py run match-forest` leaves nothing open, so start a
Studio Test → Clients and Servers with 4–6 players and take them there.

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

## Known gaps

- Race bots fill the grid to 4 racers, but not FARMING: a lone player
  farms alone. Bots are not targets for abilities yet.
- Gamepad and touch buttons are tested offline only (key mapping); try
  them on a device before going public.
- The finish grace (45 s after the winner) sometimes cuts off the slowest
  driver when the winner is very fast (Studio match-forest, 2026-10-23: a
  novice 170 studs short).
