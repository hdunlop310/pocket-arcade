# Cat Drop

A free, ad-free mobile game in the hybrid-casual style. Built in Godot 4 (developed and tested on 4.7.2) as a portfolio project. Target platforms: iOS first (the owner has an iPhone), web build for quick phone testing, Android later.

## The game in one paragraph
Drop balls through a peg board with multiplier gates (X2/X3/X5) into a cup, and every ball in the cup banks coins. Spend coins on the map screen on cats, cat levels and board upgrades. Place cats on a 4x4 battle grid, then start a wave: mice walk down four lanes and chew through the front cat in their column while the cats fight back automatically. Clearing a wave pays coins and bonus balls for the next drop round. 10 waves per run, boss (the Rat King) on wave 10. The drop board is the hands-on part you play; the battle is the payoff.

## Decisions already made (do not reopen without asking the owner)
- No ads, no energy timers, no dark patterns. This is the whole pitch.
- Balls per round are a fixed number, upgradeable on the map. Pressing DROP ALL BALLS releases every ball at once from wherever the dropper cat is, so timing is the aim. **One drop per round, and no way to start another round without fighting a wave** (owner decision 2026-10-22, so coins cannot be farmed). Round loop: map -> drop (once) -> battle -> map. A failed wave still needs a fresh drop to retry.
- Cats are placed on a grid, not freely. Tile types matter: flat, raised (ranged cats +range, any cat takes +50% damage), hole (any cat takes -50% damage, ranged cats lose range). The layout is `TILE_TYPES` in `battle.gd`.
- Coins are the single currency. Cats, cat levels and board upgrades all cost coins. All upgrading happens on the map (story) screen, in the style of the owner's reference games (a chapter path with the next node highlighted, upgrade cards below, one big play button); there is no separate shop panel.
- Art style: edgy cartoon. Thick black outlines, flat fills, grungy texture, spiked collars, grumpy faces, amber eyes. Palette: crimson background `#7E1236`, near-black `#0B0B0E` / `#16161C`, amber `#F2A81D` for buttons and eyes, pink-red `#E0285E` for pegs and highlights. Reference art: the Maine Coon (Macho) and Bengal (Rosette) illustrations in `art/` come from the owner's own AI-generated reference images.
- Melee cats (Macho) run out of their tile to meet mice in their own lane, within a leash (`CHARGE_*` in `battle.gd`), block mice up front, and return home when the lane is clear (owner decision 2026-10-22). Tile bonuses only apply while a cat stands on its tile.
- UI direction (owner, 2026-10-22): the first look was "bland and boring". Aim for chunky, outlined, juicy: thick ink outlines, heavy text, raised buttons, particles, popups, screen shake. Art plan is hybrid: UI chrome is drawn in code now; real cat and mouse sprites will be supplied later and dropped in.
- Two cats exist so far: Macho (Maine Coon, melee, tank) and Rosette (Bengal, ranged sniper). More cats are wanted.
- Do not copy other games' characters, art or branding. Mechanics are fair game, assets are not.

**Start with `docs/PLAN.md` (phased roadmap and first steps).**

## Bigger picture: a hub of ad-free games (decided 2026-10-22)
Cat Drop is game #1 of a planned app that collects the classic ad-riddled hybrid-casual genres, each done properly with no ads and no real-money purchases. The in-game economy (currency, shop, upgrades, unlocks) stays, but everything is earned by playing and paced for fun, not friction.
- The hub is theme-neutral (own name and look). Each game keeps its own theme, characters and art; cats belong to Cat Drop only.
- Each game has its own currency and economy (easy to balance and test). A light shared layer (profile XP or stars, achievements) may sit on top. A rare shared hub currency is a possible later addition.
- Shared plumbing: save system, settings, UI kit, and a small common game interface (start, finish, report progress). Games are self-contained scenes under `games/<name>/`.
- The full game wishlist is in `docs/GAMES.md` and the hub design sketch in `docs/HUB.md`. Add the owner's new game ideas to the wishlist.
- Candidate next games: car-sort puzzle first, then category cards, another puzzle, and later an Archero-style roguelite. Quality over quantity: hub plus 2 or 3 polished games beats many half-built ones.
- Phase 1 done (2026-10-22): Cat Drop lives in `games/catdrop/` behind `GameBase`, saves go through the `Save` autoload (`user://hub.cfg`), and `hub/hub.tscn` is the main scene (picker, profile XP, achievements, settings). The hub is named Pocket Arcade (`HUB_NAME` in `core/games.gd`, Godot project name, repo `pocket-arcade`); `Save` copies saves from the old `Cat Drop` user folder on first run. Next is Phase 2 (puzzle module and game #2) in `docs/PLAN.md`.

## Files
- `hub/hub.gd` (+ `hub.tscn`, the main scene): game picker, profile bar, achievements and settings overlays, toasts. Opens games with `open_game(id)` and listens to their `GameBase` signals.
- `core/ui_kit.gd` (`UIKit`): the shared look. Heavy outlined font (`UIKit.heavy()`), `style_button`, outlined `box`/`panel`, `text`, `gradient`, and drawn icons (star, coin, lock, paw, crown, arrow). Use it for all new UI instead of raw StyleBoxFlat or plain `draw_string`. `core/fx.gd` (`Fx`): particle bursts and floating popups; the owner calls `update(dt)` and `draw(ci)`.
- `core/`: `game_base.gd` (common interface: `start(slot)`, signals `progress`, `finished`, `quit_requested`, `save_requested`), `save.gd` (autoload `Save`), `games.gd` (registry and tile progress text), `profile.gd` (XP to level, awarding), `achievements.gd` (definitions).
- `games/catdrop/catdrop.gd`: the map screen and upgrade panel, the drop board (physics, balls, gates, cup), the map/drop/battle state machine (`state`), HUD, and saving into its slot. Everything is drawn in code in `_draw()`. It reports XP and achievements to the hub through `progress`.
- `games/catdrop/battle.gd`: the battle grid. All fight maths is in `step(dt)` and has no dependency on rendering, so tests can run it thousands of times. Also placement, ownership, cat costs, banners.
- `games/catdrop/ball.gd`: a single RigidBody2D ball. Balls collide with the board (layer 1) but not each other (layer 2).
- `games/catdrop/catdrop.tscn`: just a Node2D with `catdrop.gd`. Everything else is created in code.
- `games/catdrop/art/macho.png`, `rosette.png`: 256x256 face crops used on the grid and upgrade panel. These are placeholders for proper sprites.
- `tests/`: integration test (`test_game`), hub/platform test (`test_hub`), balance sweep, screenshot script (includes hub shots 8 to 12). See Testing.
- Save file: `user://hub.cfg`, one section per game (`[catdrop]`: coins, levels, stats, bonus balls, wave, house HP, owned, grid) plus `[profile]` (xp, achievements) and `[settings]`. The old `user://catdrop.cfg` is migrated into `[catdrop]` on first run. To reset while developing, use Settings in the hub or delete `hub.cfg` (editor: Project > Open User Data Folder). Tests use `user://test_hub.cfg` via `Save.use_test_file()`, never your real save.

## Testing (do this before telling the owner something works)
The owner cannot see your terminal, so run the tests yourself. From the project folder, with `GODOT` being your Godot 4 executable:

0. On Windows, `powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1 [-Balance] [-Shots]` does steps 1 to 4 (it finds Godot in `$env:GODOT`, PATH or Downloads). The Godot 4.7.2 console exe works.
1. Import once after adding or changing assets or scripts: `GODOT --headless --import --path .`
2. Integration test (about 30 seconds, exits 1 on failure): `GODOT --headless --path . res://tests/test_game.tscn` and look for `failures=0`. Also run `res://tests/test_hub.tscn` (save, migration, profile, hub flow); same check.
3. Balance sweep (about a minute): `GODOT --headless --path . res://tests/sim_balance.tscn`
4. Screenshots (needs a real renderer, so not `--headless`). On Linux without a display: `SHOT_DIR=/some/dir xvfb-run -a -s "-screen 0 800x1300x24" GODOT --rendering-driver opengl3 --rendering-method gl_compatibility --path . res://tests/screenshots.tscn`. On Windows or Mac, run it normally with `SHOT_DIR` set. View the PNGs to check layout. Several layout bugs (text under buttons, sprites poking out of panels) only showed up this way.

If you add a feature, add checks for it to `tests/test_game.gd`. If you change enemy or cat stats, re-run the balance sweep and update the baselines below.

## Balance baselines (from `tests/sim_balance.gd`, optimal placement)
- Roster to waves cleared in a 10-wave run: 1 Macho about 3; Macho + Rosette about 5; 2+2 about 7 to 8; 3+3 clears everything including the boss.
- Economy: the base board earns about 100 coins per round of 12 balls. With more balls, coin value and gate upgrades it reaches about 630 per round. The Bigger Gates upgrade is very strong; consider raising its cost or capping it once more cats exist to spend coins on.
- Cat costs: Macho 40, Rosette 60, each extra copy x1.35. Cat levels (new): 1 to 5, +20% health and damage per level, level-up cost = base cost x 2 x 1.7^(level-1) (Macho 80, 136, 231, 393). Level 1 is x1.0, so the roster numbers above are unchanged; the sweep does not yet use levels.

## Gotchas learned the hard way
- Never move a node that has physics bodies as children to shake the screen (it freezes the balls). Shake through `get_viewport().canvas_transform` (see `kick()` in `catdrop.gd`).
- A typed `var x := arr.duplicate()` on a packed array can fail to infer; write `var x: PackedVector2Array = ...`.
- Setting a `Label.size` before `add_child` is overwritten with the text width; set it after (see `_label` in `hub.gd`). Enable autowrap before turning off `clip_text`.
- In headless tests, awaiting only `physics_frame` can skip `_process`; the `frames()` helpers await both.
- GDScript cannot infer a type from a Variant. `var x := some_dict["key"]` or `var busy := dropping or battle.active` fails to parse and stops the whole game loading. Write `var x: int = ...` or `var busy: bool = ...` whenever any part of the expression is untyped. Run the headless test after every edit to catch this.
- The test shell can be killed by `pkill -f Godot...` because the pattern matches your own command line. Avoid `pkill -f`.
- Physics callbacks cannot add bodies directly. Ball spawning from gates uses `call_deferred`.
- Z-order: the battle node and map panel are children added in `_ready`; balls are added at runtime (later in the tree), so they would draw above them, which is fine only because balls exist only in the drop state (you cannot leave the drop until every ball has landed).
- Web export: turn off Thread Support so it works on a plain static host (Netlify Drop, GitHub Pages). iOS needs a Mac with Xcode; a free Apple ID build expires after 7 days.
- Keep `tests/` out of release exports (Project > Export > Resources > exclude `tests/*`).

## Backlog (rough priority; ask the owner before big design changes)
1. More cats: a healer (Medic), a fast skirmisher, a heavy tank. Each needs a role that changes tile choice. Possibly cats that can only fit in holes.
2. More enemy types beyond mice: fast runners, ranged enemies that shoot over the front cat, a second boss.
3. Cat upgrades or merging duplicates, so coins have a long-term sink.
4. Make aim on the drop board matter more (bonus cup slots, edge gaps) since every ball currently reaches the cup.
5. Real sprites (idle, attack, hit) for cats and enemies in the same style as the reference art, replacing face crops and drawn mice. Sprite sheets on transparent backgrounds; keep line weight and palette consistent.
6. Juice: screen shake on hits and boss, particles on gate multiplies, sound effects and music, haptics on phone.
7. Onboarding: a short first-run hint flow (drop, buy a cat, place it, start a wave).
8. Daily run or seeded challenge, cosmetic cat skins (collars, eyepatches), no pay-to-win.
9. Release prep: app icon, splash, iOS and Android export presets, privacy note ("collects nothing"), TestFlight.

## How to work with the owner
- They are a software engineer building this for a portfolio and to learn. Explain choices briefly; do not over-explain basics.
- They like short answers and visual checks (screenshots, mockups). When something needs a decision, offer 2 or 3 concrete options with a recommendation.
- The README explains how to run the game and what each tuning constant does. Keep it updated when behaviour changes.
