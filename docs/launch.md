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
   3: name, description, `assets/store/final/icon.png` and the five
   `thumb_*.png`).
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

Everything below is ready to paste. Creator Dashboard → the experience →
**Configure → Basic Info** (name, description, genre), **Places → the
place → Configure → Access** (devices, max players), **Monetization →
Private Servers**, **Localization**, **Audience → Maturity & Compliance**.

**Name:** Catastrophic Ride (the place is still called "대재앙": rename it)

**Description** (English, 885 of 1 000 characters, paste as is):

> Grab junk. Build a ride. Race your friends!
>
> Run around the farm and grab everything you can: bathtubs, rubber ducks, rockets, a red sofa. Punch, guard and steal to keep the best stuff. Then bolt your loot onto a car, a boat or a plane and race through the Forest, the Ocean and the Sky. Every item gives your ride its own trick!
>
> 🌲 3 worlds: drive the forest, sail the ocean, fly through the clouds
> 🛁 39 items: ride a pizza, roll on rubber-duck wheels, wear a cactus as a hat
> 👊 Punch, guard and steal while you farm
> 🏁 Jump ramps, spring over a broken bridge, drift for turbo, ride updrafts
> 🎩 Level up and unlock paints, trails, hats, taunts and special rides
> 🤖 Nobody online? Bots join, so every round is a race
>
> PC: WASD drive · Shift drift · F boost · E item / grab · F punch · G guard
> Phone: thumbstick + buttons on the right
> Gamepad: triggers + stick · X item · B boost · L1 drift

**Korean description** (optional: Localization → Korean → add the
translation; other languages: turn on automatic translation):

> 잡동사니를 줍고, 탈것을 만들고, 친구들과 레이스!
>
> 농장을 뛰어다니며 욕조, 고무오리, 로켓, 빨간 소파까지 닥치는 대로 주우세요. 주먹, 막기, 뺏기로 좋은 아이템을 지키세요. 그다음 모은 걸 자동차, 배, 비행기에 붙여서 숲, 바다, 하늘을 달리세요. 아이템마다 탈것에 특별한 기술이 생겨요!
>
> 🌲 3개의 월드: 숲을 달리고, 바다를 항해하고, 구름 사이를 날아요
> 🛁 39개의 아이템: 피자를 타고, 고무오리 바퀴로 달리고, 선인장을 모자로 써요
> 👊 파밍하면서 주먹, 막기, 뺏기
> 🏁 점프대, 끊어진 다리 뛰어넘기, 드리프트 터보, 상승 기류
> 🎩 레벨업하고 페인트, 트레일, 모자, 도발, 특별 탈것 잠금 해제
> 🤖 접속자가 없어도 봇이 들어와서 언제나 레이스
>
> PC: WASD 운전 · Shift 드리프트 · F 부스트 · E 아이템/줍기 · F 주먹 · G 막기
> 폰: 왼쪽 스틱 + 오른쪽 버튼
> 게임패드: 트리거 + 스틱 · X 아이템 · B 부스트 · L1 드리프트

**Icon and thumbnails** (upload these, in this order):
`assets/store/final/icon.png` (512 × 512) and `thumb_1.png` … `thumb_5.png`
(1920 × 1080): the title card first, then ramps, the gap jump, the ocean,
the sky. `python3 tools/store_art.py` draws them (game logo in Luckiest Guy,
captions in Montserrat Black, fonts from the Studio install) over the raw
shots in `assets/store/*.png`, which `python3 tools/studio/sim.py run promo`
takes from the real maps (TestHarness/Promo: the race lighting, varied
builds and riders, cars frozen mid-jump). Re-run both after visual changes;
the screen must be awake and unlocked, Studio's **Device Simulator off**
(Test menu: with it on the shots came out as a small phone), and a bigger
Studio view gives sharper pictures. Videos for social posts: `reports/video/`
(`tools/video/cut.py build`).

| Field | Value |
|---|---|
| Genre / subgenre | Sports & Racing → Racing (or Party & Casual) |
| Devices | Computer, Phone, Tablet, Console (VR off) |
| Max players | 10 |
| Private servers | On, free (friend groups) |
| Allow copying | Off |
| Chat | On (TextChatService, Roblox filters it) |
| Voice chat | Off (not needed) |

**Maturity & Compliance questionnaire** (what this game has; the answers
decide the content label, most likely Mild):

| Question | Answer |
|---|---|
| Violence | Yes, mild: cartoon punches and kicks between blocky avatars, knock-backs, cars bumping; no weapons, no death, no injury shown |
| Blood / gore | No |
| Strong language | No |
| Crude humour | No (taunts are "Blehhh", "Too Easy", emoji; no toilet humour) |
| Fear / horror | No |
| Romance | No |
| Alcohol, drugs, tobacco | No |
| Gambling / random paid items | No (coin packs give a fixed amount; the shop sells chosen items) |
| Real-money trading | No |
| Free-form user creation | No (players build from fixed items) |
| Social hangout | No |
| Text chat | Yes (Roblox default chat) |
| Voice chat | No |
| Political / religious content | No |
| Ads, sponsored content | No |

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
- Gamepad and touch buttons are tested offline only (key mapping, and the
  touch layout on seven phone / tablet screens: `lune run
  tools/phone_layout.luau`, `python3 tools/studio/ui_overlap.py --phone`);
  try them on a phone before going public: thumb reach, the stick, the
  shop and crafting screens at their phone size.
- Every client holds all three maps (~5 900 parts) and the shop previews
  for all three biomes; OCEAN's terrain is painted when a round picks it
  (a short hitch at FARMING start).
- The finish grace (45 s after the winner) sometimes cuts off the slowest
  driver when the winner is very fast (Studio match-forest, 2026-10-23: a
  novice 170 studs short).
