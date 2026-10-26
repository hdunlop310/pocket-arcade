# Prompt for Gemini: full UI redesign, with wireframes (paste everything below the line)

---

You are a senior mobile game UI/UX director. I'm building a portrait mobile game hub called **Pocket Arcade**
(first game: **Cat Drop**). It's built in Godot 4 by an AI coding assistant (Claude), and I'm the owner. The game
works, but the UI looks dated and cluttered, and small restyling passes haven't helped. I want a complete
redesign: new wireframes for every screen, a style direction, and an asset list that Claude can build from.

## Step 1: interview me before you design anything
Do NOT start designing yet. First ask me questions, in rounds of 4 to 6 at a time, and wait for my answers.
Cover at least: which mobile games' look I love and hate (ask me to send screenshots, up to 6, and tell you what
I like about each: layout, colour, buttons, characters, effects); how serious or playful the tone should be; how
much text vs icons I want; one-handed thumb reach; how detailed the battle screen should be; whether I want a
bright or dark theme; how "premium" vs "arcade" I want it to feel; and anything I never want to see again.
After my answers, summarise the direction back to me in 5 bullets and ask me to confirm before you design.

## Step 2: what the game is (so your wireframes fit the real mechanics)
- Portrait, 390x844 design size, no ads, no purchases, no timers. Coins are the only currency.
- **Hub:** a home screen with tiles for each game (only Cat Drop exists; others are "coming soon"), a profile
  level/XP bar, achievements and settings. The hub is theme-neutral; each game has its own look.
- **Cat Drop loop:** story map -> drop board (one drop) -> battle -> back to the map.
  - **Story map (game home):** a 10-wave chapter path (boss on wave 10, the Rat King), a line of story text per
    wave, and upgrade cards (buy cats, level up cats, board upgrades). One big PLAY WAVE button. Hub button.
  - **Drop board:** a Plinko-style board. A cat launcher at the top sweeps left and right. I press once and all
    balls (about 5 to 10) drop through pegs and multiplier gates (X2, X3, X4) into a cup that banks coins.
    Needs balls, coins and cup celebration to feel great.
  - **Battle map (please design this one carefully):** a 4x4 grid of tiles near the bottom is where the player's
    cats stand. Tile types: flat, raised (ranged cats get more range but take 50% more damage) and hole (cats take
    half damage but ranged cats lose range). Four lanes run up the screen from the grid. Mice spawn at the top
    and walk down the lanes toward the grid and the house; a boss wave brings the Rat King. Melee cats (Macho the
    tank, Adora the acrobat) run out of their tile and chase mice anywhere on the field; Rosette (ranged sniper)
    stays on her tile and shoots. The screen needs: a house health bar, cat selection tray (3 cats now, more
    later), tile selection and placement feedback, damage numbers, a wave banner, and a START WAVE button.
  - Placement phase vs fight phase should look different. Show what happens when a cat is selected.
- Other screens: achievements list, settings, round-over / wave-cleared / defeat popups, a cat detail and upgrade
  sheet, a first-run tutorial hint, and locked/coming-soon states.
- Characters (real art exists): Macho (grumpy black Maine Coon), Rosette (Bengal with a sniper rifle), Adora
  (white acrobat). Art style so far: edgy cartoon, thick black outlines, spiked collars, amber eyes.
  Palette so far (open to change): deep plum, gold, hot magenta, cyan.

## Step 3: what to deliver (only after I confirm the direction)
1. **A style tile**: one image showing colours, button styles (normal, pressed, disabled), panel and card
   styles, icon style, type pairing, and a sample of how effects should look.
2. **Wireframes for every screen above** as clean, labelled images at 390x844 proportion, with real UI
   dimensions: safe margins, tap-target sizes (at least 44pt), spacing, and which element is the single focal
   point of each screen. Give each screen 2 layout options if the choice is genuinely open, and say which you
   recommend and why.
3. **The battle map in detail**: a full-screen wireframe plus callouts for the grid tiles (each tile type), lanes,
   enemy spawn area, house health, the cat tray, selection and glow states, and the placement vs fight phases.
4. **A component list** for the UI kit Claude must build, each with pixel size, 9-slice margins, states, and
   whether it should be real art (PNG) or can be drawn in code.
5. **An asset request list**: every PNG you can generate for real (backgrounds, panels, icons, gate bumpers,
   tiles, battle-field backdrop, mouse and Rat King sprites with the same sprite-sheet layout I used for the cats:
   8 frames, 2 columns by 4 rows, labelled, flat background, perch tile under the character), with exact sizes.
6. **An animation and juice sheet**: for each key moment, duration (ms), easing, and what moves.

## Constraints and honesty
Claude can build: 9-slice panels and buttons from PNGs, sprite sheets, fonts (open licences only), shaders,
particles, bloom and screen shake, and layouts to the pixel. Claude cannot paint, cannot see motion (only still
screenshots), and positions things with numbers, so be numeric. Do not suggest paid assets or engines. Keep it
free of ads, timers and purchases. If a design needs art that can't be made well by an AI image model, say so and
suggest an alternative.

Start now with Step 1: greet me in one line and ask your first round of questions.
