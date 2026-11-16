# Achievement hats as Roblox avatar items (UGC)

Each achievement (`Shared/Achievements`) unlocks a hat in the game. The same
hat can also be a free Marketplace avatar item that only our game hands out,
so players wear it everywhere on Roblox ("where did you get that?"). The
game side is ready: an achievement whose `ugc` id is not 0 opens Roblox's
get-item prompt the moment it is earned, and the shop's 🏆 Awards tab has an
"⭐ Avatar item" button to ask again. Only the owner's account can upload.

## Build the models

```sh
lune run tools/ugc_dump.luau                     # the game's hat parts → assets/ugc/designs.json
                                                 # (ride-ons: tools/ugc_rides.py)
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/ugc_models.py
```

`assets/ugc/<id>/` gets `<id>.fbx` (one mesh, one palette texture, well
under the 4 000 triangle limit), `texture.png` and `preview.png`;
`assets/ugc/report.json` lists triangles and size in studs.

| Achievement | Hat | Accessory type |
|---|---|---|
| World Tour (win in all three biomes) | `hat_medal` World Tour Medal | Hat |
| Royal Flush (win riding a Toilet) | `hat_plunger` Golden Plunger | Hat |
| Funniest Ride (win the ride show vote) | `hat_jester` Jester Crown | Hat |
| Crowd Favorite (win the vote 5 times) | `hat_trophy` Trophy Hat | Hat |
| Master Thief (steal 20 items) | `hat_mask` Bandit Mask | Face |
| Road Rookie (finish 10 races) | `ride_cart` Shopping Cart Ride-On | Waist |
| Royal Flush | `ride_toilet` Toilet Ride-On (our own toilet, not the store model) | Waist |
| Funniest Ride | `ride_duck` Rubber Duck Ride-On | Waist |

Ride-ons are kids' ride-on toy cars worn round the waist: the avatar stands
in the cockpit and walks it around anywhere on Roblox. Their parts are data
in `tools/ugc_rides.py` (origin at the waist, ~2.6 studs over the ground).
Only items we made can be uploaded: the Creator Store models in the game
(Toilet, Rocking Horse, Piano, …) are other creators' work, which is why the
toilet ride-on is a model of its own.
An achievement may give several (`ugc = { { item, id }, … }`): the prompts
open one after the other.

## Upload (owner's account, UGC creator)

1. Studio: File → Import 3D → `assets/ugc/<id>/<id>.fbx`, Scale Unit
   **Stud**. It arrives as one MeshPart with its texture.
2. Avatar tab → Accessory Fitting Tool: pick the MeshPart, the type from the
   table, check it on the mannequins (R15 and the body types it lists), then
   Generate an Accessory.
3. Right-click the Accessory → Upload to Roblox. Name and description: the
   hat's name and "Earned in Catastrophic Ride: <achievement text>." The
   dialog shows the upload fee for your account.
4. Creator Hub → Creations → Avatar Items → the item → Sales: make it a
   **Limited**, price **free**, choose a quantity, and limit sales to
   **our experience only**. The fees for free Limiteds are shown there.
5. Copy the item's asset id into `Shared/Achievements` (the `id` of that
   item in the achievement's `ugc` list), open a PR, publish the place.

## Notes

- A free item limited to an experience can only be taken inside it, but any
  script in the game can show the prompt; Roblox has had reports of such
  items leaving through other paths (DevForum, August 2026). Keep the
  quantity modest.
- Animation packs and emotes have a minimum price on the Marketplace, so
  ride poses stay game-only rewards.
- Badges for the achievements: create one per achievement on the Creator
  Dashboard with `assets/badges/ach_<key>.png`, then put its id in
  `Shared/Achievements` (`badge = <id>`).
