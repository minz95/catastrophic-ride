# Shop economy (simulated)

`lune run tools/economy.luau`: three kinds of player over 30 days, rewards from
`Shared/Progression` (6-car races, daily streak), prices and level gates from
`Shared/Cosmetics`. A player buys every item, cheapest first, as soon as it is
affordable and unlocked. Day = the day it was bought (— = not within 30 days).

| Item | Category | Price | Level | casual | regular | skilled |
|---|---|---|---|---|---|---|
| Too Slow | Taunts | 150 | 1 | day 2 | day 1 | day 1 |
| Midnight | Paint | 150 | 1 | day 3 | day 2 | day 1 |
| Lime Rush | Paint | 150 | 1 | day 8 | day 3 | day 2 |
| Cloud Puff | Trail | 200 | 1 | day 9 | day 4 | day 3 |
| Bubblegum | Paint | 200 | 1 | day 11 | day 4 | day 3 |
| Nyah Nyah | Taunts | 200 | 1 | day 16 | day 5 | day 4 |
| LOL | Taunts | 250 | 1 | day 18 | day 6 | day 4 |
| Sunset | Paint | 250 | 1 | day 24 | day 7 | day 5 |
| Arctic | Paint | 300 | 3 | day 29 | day 8 | day 6 |
| Bubbles | Trail | 300 | 1 | — | day 9 | day 7 |
| Eat My Dust | Taunts | 350 | 2 | — | day 10 | day 8 |
| Fire | Trail | 450 | 4 | — | day 12 | day 9 |
| Galaxy | Paint | 450 | 5 | — | day 13 | day 10 |
| Bow Down | Taunts | 600 | 4 | — | day 16 | day 11 |
| Flying Kick | Moves | 700 | 2 | — | day 18 | day 13 |
| Gold Rush | Paint | 800 | 8 | — | day 21 | day 15 |
| Smoke Bomb | Gadgets | 900 | 3 | — | day 24 | day 17 |
| Rainbow | Trail | 900 | 7 | — | day 27 | day 19 |
| Flame Rider | Special Rides | 1000 | 4 | — | — | day 21 |
| Bounce Bomb | Race Tricks | 1200 | 3 | — | — | day 24 |
| Neon Phantom | Special Rides | 1300 | 5 | — | — | day 28 |
| Rainbow Comet | Special Rides | 1800 | 6 | — | — | — |
| Golden Legend | Special Rides | 3000 | 10 | — | — | — |

Saving for just one item (the day it is bought):

| Item | Category | Price | Level | casual | regular | skilled |
|---|---|---|---|---|---|---|
| Too Slow | Taunts | 150 | 1 | day 2 | day 1 | day 1 |
| Midnight | Paint | 150 | 1 | day 2 | day 1 | day 1 |
| Lime Rush | Paint | 150 | 1 | day 2 | day 1 | day 1 |
| Cloud Puff | Trail | 200 | 1 | day 3 | day 1 | day 1 |
| Bubblegum | Paint | 200 | 1 | day 3 | day 1 | day 1 |
| Nyah Nyah | Taunts | 200 | 1 | day 3 | day 1 | day 1 |
| LOL | Taunts | 250 | 1 | day 3 | day 2 | day 1 |
| Sunset | Paint | 250 | 1 | day 3 | day 2 | day 1 |
| Arctic | Paint | 300 | 3 | day 3 | day 2 | day 1 |
| Bubbles | Trail | 300 | 1 | day 3 | day 2 | day 1 |
| Eat My Dust | Taunts | 350 | 2 | day 4 | day 2 | day 2 |
| Fire | Trail | 450 | 4 | day 8 | day 3 | day 2 |
| Galaxy | Paint | 450 | 5 | day 8 | day 3 | day 2 |
| Bow Down | Taunts | 600 | 4 | day 9 | day 3 | day 2 |
| Flying Kick | Moves | 700 | 2 | day 10 | day 4 | day 3 |
| Gold Rush | Paint | 800 | 8 | day 15 | day 4 | day 3 |
| Smoke Bomb | Gadgets | 900 | 3 | day 11 | day 4 | day 3 |
| Rainbow | Trail | 900 | 7 | day 11 | day 4 | day 3 |
| Flame Rider | Special Rides | 1000 | 4 | day 15 | day 5 | day 3 |
| Bounce Bomb | Race Tricks | 1200 | 3 | day 17 | day 5 | day 4 |
| Neon Phantom | Special Rides | 1300 | 5 | day 18 | day 6 | day 4 |
| Rainbow Comet | Special Rides | 1800 | 6 | day 29 | day 8 | day 6 |
| Golden Legend | Special Rides | 3000 | 10 | — | day 12 | day 9 |

| Player | Plays | Rounds in 30 days | Level on day 7 | Level on day 30 | Coins left |
|---|---|---|---|---|---|
| casual | 3 rounds on 4 days a week, mid-field | 54 | 5 | 11 | 169 |
| regular | 8 rounds every day, mid-field | 240 | 12 | 26 | 999 |
| skilled | 10 rounds every day, usually on the podium | 300 | 15 | 32 | 1170 |

Rewards: play 25 XP / 5 coins, finish +30 / +10, podium +55/35/20 XP; daily bonus 40 coins + 10 per streak day (max 7).
