# Pocket Arcade: an ad-free game hub, starting with Cat Drop

A Godot 4 project (4.3 or newer). The app opens on the hub: a game picker with a profile bar (XP and level), an achievements list and settings. Cat Drop is the first game; more are planned (see `docs/GAMES.md`).

## Run it
1. Install Godot 4.3+ from godotengine.org (the standard build, not .NET).
2. Open Godot, click Import, and pick `project.godot` in this folder.
3. Press F5 to open the hub, tap the Cat Drop tile, then press DROP ALL BALLS (or Space / Enter). The HUB button returns to the picker. To run Cat Drop alone, open `games/catdrop/catdrop.tscn` and press F6.

## What it does
- A black cat sweeps left and right across the top. Press DROP ALL BALLS to release every remaining ball in a quick burst from where the cat is at that moment, so your timing is your aim.
- Balls bounce through the pegs. Each gate multiplies a ball (X2, X3, X5) by spawning extra balls.
- Every ball that lands in the cup banks 1 coin.
- You get 12 balls per round. When they are all used and the board is empty, the round ends and the button becomes NEW ROUND. Coins carry over between rounds.

## The battle
- Tap BATTLE (top centre) to switch from the drop board to the battle grid, and DROP to go back. Both are locked while balls are in flight or a wave is running.
- Your cats sit on a 4x4 grid. Tap a cat chip at the top, then a tile, to place it. Tap a placed cat to pick it up. Cats come from the SHOP.
- Mice walk down the lanes and chew through the front-most cat in their column. Cats fight back on their own. Cats that fall come back at full health after the wave.
- Tiles: raised tiles give ranged cats +range but make any cat take 50% more damage; holes halve damage taken but cut ranged cats' range.
- Macho (melee) hits what is right in front of him, so he belongs at the front. Rosette (ranged) hits the closest mouse in range, so keep her behind, ideally on a raised tile.
- 10 waves, with the Rat King on wave 10. Clearing a wave gives coins (15 x wave number) and 4 bonus balls on your next drop round. If the house falls you restart at wave 1 but keep your cats and upgrades. Finishing wave 10 gives 200 coins and starts a new run.
- Rough balance (from simulated runs): 1 cat falls around wave 3, 2 cats around wave 5, 4 cats around wave 7 or 8, and about 6 well-placed cats beat the boss.

## The shop
- Tap SHOP between rounds or waves (it is locked while balls are in flight or a wave is running). Coins buy:
  - CATS: Macho (40 coins) and Rosette (60 coins). Each extra copy of the same cat costs 35% more, up to 10 of each.
  - MORE BALLS: +2 balls per round, up to 6 levels (costs 50, 80, 128, ...).
  - COIN VALUE: +1 coin per ball, up to 5 levels (costs 80, 144, 259, ...).
  - BIGGER GATES: every gate gets +1 multiplier, up to 2 levels (costs 200, 500).
- Progress (coins and upgrade levels) saves automatically. To reset it while testing, in the Godot editor use Project > Open User Data Folder and delete `hub.cfg`, or use Settings > Reset all progress in the hub. Saves from the old prototype (`catdrop.cfg`) are migrated into `hub.cfg` the first time the new version runs.

## Tuning (top of `games/catdrop/catdrop.gd`)
- `UPGRADES`: base cost, cost growth and max level of each shop upgrade.
- `BASE_BALLS` / `BALLS_STEP`: starting balls and balls gained per level.
- `BASE_COINS_PER_BALL`: the starting coin value per ball.
- `DROP_STAGGER`: the gap between balls in the burst (set to 0 for a single clump).
- `GATES`: position and multiplier of each gate. Move them or add more.
- `SWEEP_SPEED` / `SWEEP_RANGE`: how fast and wide the dropper swings.
- `MAX_BALLS_ALIVE`: safety cap on balls on screen at once.
- Gravity is in Project Settings > Physics > 2D (set to 1200).

## Notes
- Balls collide with the board but not with each other, so big multiplied piles don't jam.
- Everything is drawn in code for now (no art files). Real art slots in later by replacing the `_draw()` calls with sprites.

## Battle tuning (top of `games/catdrop/battle.gd`)
- `CAT_TYPES`: health, damage, attack speed, range and base cost of each cat.
- `MOUSE_*` and `BOSS_*`: enemy health, damage and speed, and how fast they scale per wave.
- `TILE_TYPES`: which tiles are flat, raised or holes. `RAISED_*` / `HOLE_*`: what those tiles do.
- `MAX_WAVE`, `HOUSE_MAX`, `HOUSE_REGEN`: run length and house health.

## Files
- `hub/hub.gd`, `hub/hub.tscn`: the hub screen (picker, profile bar, achievements, settings).
- `core/`: `game_base.gd` (interface every game extends), `save.gd` (Save autoload, `user://hub.cfg`), `games.gd` (registry of tiles), `profile.gd` (XP and levels), `achievements.gd`.
- `games/catdrop/`: `catdrop.gd` (drop board, shop, buttons), `battle.gd` (battle grid), `ball.gd`, and `art/` (face crops of Macho and Rosette).
- `tests/`, `scripts/run_tests.ps1`: tests; the script runs them all on Windows (`-Balance`, `-Shots` for more).

## Next steps
1. More cats and enemy types, plus a cat upgrade or merge system.
2. Real sprites (idle, attack, hit) in place of face crops and drawn mice.
3. Sound and screen shake.
