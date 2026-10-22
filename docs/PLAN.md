# Project plan: ad-free game hub

Read this first, then `CLAUDE.md` (Cat Drop details), `docs/HUB.md` (architecture) and `docs/GAMES.md` (wishlist).

## Vision
One app of classic hybrid-casual games (idle, sort puzzles, roguelite) done properly: no ads, no real-money purchases, no timers or energy. Each game still has a working economy (coins, shop, upgrades, unlocks), earned only by playing and paced for fun. Built with Godot 4 as a portfolio project, iPhone first.

## Principles
1. Never add ads, IAP, timers, energy, fake scarcity or tracking. If in doubt, ask the owner.
2. Each game has its own theme, art and coin economy. Shared: save, UI kit, puzzle module, profile XP and achievements.
3. Mechanics may be borrowed from existing games; names, characters and art may not.
4. Every game's logic is pure and headless-testable. Run the tests before saying something works. Check layouts with screenshots.
5. Ship small, working increments. One polished game beats three half-done ones.
6. Keep `README.md`, `CLAUDE.md` and `docs/` current when behaviour changes.

## Phases

### Phase 0: groundwork (small)
- [x] Confirm Godot 4.7.x runs on the owner's PC; install a CLI path for tests. (Godot 4.7.2 from Downloads, `scripts/run_tests.ps1`.)
- [x] `git init` done. [ ] First commit: waiting for the owner's OK.
- [x] Run the test suite on the owner's machine; fix any Windows path issues. (Only a test timing issue: `frames()` now awaits `process_frame` too.)
Done when: tests pass locally and the game runs from the editor.

### Phase 1: platform (hub + core)
- [x] Create `core/game_base.gd` (the common interface in HUB.md) and `core/save.gd` autoload (single `user://hub.cfg`, section per game, migrate `catdrop.cfg`).
- [x] Move Cat Drop to `games/catdrop/`, wired through `GameBase`. Behaviour unchanged; update test paths; all tests pass.
- [x] `hub/hub.tscn`: game picker with tiles, progress lines, profile XP bar, settings.
- [x] Profile XP and level, achievements list (stub with 5 to 10 achievements across Cat Drop).
- [x] Hub named Pocket Arcade (2026-10-22). The project rename moved `user://`; `Save` imports from the old "Cat Drop" folder.
Done when: app launches into the hub, Cat Drop starts and returns to it, saves persist, tests pass.

### Phase 2: puzzle module + game #2 (car sort)
- [ ] `core/levels.gd`: level data format, level select screen, win/lose screen, stars.
- [ ] `core/helpers.gd`: helper items (undo, hammer, +1 slot, shuffle) given free, earned by play, never sold.
- [ ] Game #2 car sort (own name and art): cars queue in lanes, send to matching slots; pure logic in a testable class; 30+ generated levels with a solvability check; difficulty ramp.
- [ ] Own coin economy for car sort (cosmetic car skins, extra helpers) with a headless pacing test.
Done when: 30 levels playable, solver confirms each is winnable, tests and screenshots pass.

### Phase 3: more games (one at a time, in this order)
1. Category cards (words dropped into categories; deck data in JSON; decks LLM-drafted offline and hand-reviewed).
2. Unscrew or ring turn (reuse the puzzle module).
3. Pixel fill.
Each: design note in `docs/`, logic tests, 20+ levels, own economy, screenshots, hub tile with its own art.

### Phase 4: showpiece
- Action roguelite (Archero-style): movement, auto-aim, rooms, upgrades, boss. Large; plan separately before starting.

### Phase 5: release polish
- [ ] Sound effects and music, haptics, screen shake and juice, settings (sound, haptics, reset save).
- [ ] First-run onboarding per game.
- [ ] App icon, splash, store screenshots.
- [ ] Export: web build for quick sharing (thread support off), then iOS (Mac + Xcode; free Apple ID signing expires after 7 days; TestFlight needs a paid developer account), then Android.
- [ ] Privacy statement: collects nothing, no network calls.

## Cat Drop backlog (parallel track, from CLAUDE.md)
More cats and enemy types, cat upgrades or merging, aim mattering on the drop board, real sprites, rebalancing the Bigger Gates upgrade.

## Open questions for the owner
- Name for the hub app (neutral, not cat-themed).
- Exactly how the category-cards game should play: one card at a time vs a hand of cards.
- Whether to also release on Android and the web, or iPhone only.
- Whether to open-source the repo (good for the portfolio).

## Suggested first prompt for Claude Code
"Read docs/PLAN.md, CLAUDE.md, docs/HUB.md and docs/GAMES.md. Set up Godot so you can run the tests, then do Phase 0 and Phase 1. Keep tests green after every step, show me screenshots of the hub when it exists, and ask before committing."
