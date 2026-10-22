# Hub plan (sketch, 2026-10-22; Phase 1 built, see the status section at the end)

An ad-free app of classic hybrid-casual games. No ads, no real-money purchases, no timers. Each game has its own theme and its own coin economy; a light shared layer ties them together.

## Folder layout
```
res://
  hub/            hub.tscn, hub.gd (game picker, profile, achievements)
  core/           save.gd (autoload), games.gd (registry), ui_kit/ (buttons, panels, toasts), levels.gd, helpers.gd
  games/
    catdrop/      current game moved here, unchanged behaviour
    carsort/      game #2
    ...
  tests/          one test scene per game + core
```

## Common game interface (core/game_base.gd)
Each game's root scene extends `GameBase`:
- `id: String`, `title: String`, `icon: Texture2D`
- `signal progress(result: Dictionary)`  // {xp = 10, achievements = ["id", ...]}: game keeps running; achievements lists every id that currently holds, the hub dedups
- `signal finished(result: Dictionary)`  // e.g. {xp = 20, stars = 2, achievements = ["first_win"]}; hub awards and returns to the picker
- `signal save_requested`               // game changed its slot; hub (or `start_standalone()`) calls `Save.flush()`
- `signal quit_requested`
- `func start(save_slot: Dictionary)`    // game reads its own section of the save (a live Dictionary: change it in place); override `_on_start()`
- `func suspend() / resume()`
The hub instances the scene, listens for `finished`, awards XP, writes the save, returns to the picker.

## Save
One ConfigFile (`user://hub.cfg`) with a section per game (`[catdrop]`, `[carsort]`) plus `[profile]` (xp, level, achievements). Migrate the existing `user://catdrop.cfg` into `[catdrop]` on first run. Games never read another game's section.

## Economy
- Per game: own coins, own shop, own pacing. Cat Drop stays as is.
- Shared: profile XP and level, achievements. Possible later: a rare hub currency for cosmetic hub themes.
- Pace for fun, not friction: no paywalls, no grind designed to push spending.

## Hub screen (portrait 390x844)
```
+------------------------------+
| [avatar] Lv 7  ====---- XP   |  profile bar, taps into achievements
|                              |
|  +--------+   +--------+     |
|  | CAT    |   | CAR    |     |  big tiles, one per game,
|  | DROP   |   | SORT   |     |  each in that game's own style,
|  +--------+   +--------+     |  progress line under each
|  +--------+   +--------+     |  ("Wave 4/10", "Level 12")
|  | ???    |   | ???    |     |  locked / coming soon
|  +--------+   +--------+     |
|                              |
| [settings]        [trophies] |
+------------------------------+
```

## Puzzle module (core/levels.gd, core/helpers.gd), for sort/unscrew/rotate/fill games
- Level list per game as data (JSON/Resource): seed or layout, par moves, star thresholds.
- Level select (grid of numbers, stars, locked ahead) and a win/lose screen.
- Helper items (undo, hammer, +1 slot, shuffle): earned by playing, given free at level starts, never sold. Each game decides which helpers apply.

## Build order
1. Move Cat Drop to `games/catdrop/` behind `GameBase`; tests still pass; migrate save.
2. `hub/` scene with picker, profile XP, achievements stub.
3. Game #2: car-sort puzzle (cars queue in lanes, send to matching parking slots; own art, own name). Proves the puzzle module.
4. Game #3: another puzzle (rings or screws), reusing the puzzle module.
5. Later: action roguelite (Archero-style) as the showpiece.
6. Polish: sound, haptics, icon, export, TestFlight.

## Rules for every game
- Mechanics are fair to borrow, characters, names and art are not. Each game gets its own name and look.
- Every game ships with a headless test for its logic (pure functions, no rendering) and screenshots for layout.

## Status (Phase 1 built)
- `core/game_base.gd`, `core/save.gd` (autoload `Save`), `core/games.gd` (registry), `core/profile.gd`, `core/achievements.gd`, `hub/hub.gd` exist and are tested by `tests/test_hub.gd`.
- Differences from the sketch: games also have a `progress` signal (Cat Drop has no natural end, so it reports XP per wave and per round); the registry lists tiles in `core/games.gd` (a tile without a `scene` is locked); `Save` sections are plain Dictionaries; the old `catdrop.cfg` is migrated into `[catdrop]`.
- Profile XP: level N to N+1 needs `100 + 50 * (N - 1)` XP. Cat Drop awards 10 XP per wave, 5 per finished round, 50 per run, plus 20 to 100 per achievement (8 defined).
- Adding a game: add `games/<id>/`, a root scene extending `GameBase` (set `id` and `title` in `_init`), an entry in `Games.LIST` with a `scene`, its achievements in `Achievements`, and a `progress_text` branch.
