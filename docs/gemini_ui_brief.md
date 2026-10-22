# Prompt for Gemini: help Claude make the Pocket Arcade UI and animation look professional

Paste this into Gemini together with the screen recording (`recordings/cat_drop_demo2.avi`).

---

I'm building a mobile game hub called Pocket Arcade (first game: Cat Drop, a ball-drop plus auto-battler with
cats) in the Godot 4 engine. The code is written by Claude (an AI coding assistant) working from a terminal.
The attached video is the current build. I like the direction (plum background, gold currency, magenta and
cyan neon, outlined cartoon cats) but it still looks dated and homemade next to games like Vampire Survivors
or Supercell titles. Please act as a senior mobile UI/UX and game-art director and help me fix that.

**Why Claude is struggling (so you can tailor your advice):**

1. Claude cannot paint. Every shape in the UI is drawn in code (rectangles, polygons, gradients, outlines),
   so it looks like a programmer's approximation of an arcade UI. The only real artwork is what I give it
   (the cat sprite sheets and a few assets from you).
2. Claude cannot see motion. It only checks static screenshots, so it cannot judge easing, timing, weight,
   anticipation, overshoot or whether an animation feels good. Animations are guessed from numbers.
3. Claude has no visual design tool. It cannot drag guides, compare against a reference, or nudge a box by
   eye. Text, icons and boxes are positioned with arithmetic, which is why text alignment inside buttons,
   pills and cards has been off (I can see it in the video). I have just fixed the worst of it, but a proper
   layout spec would prevent it.
4. Claude works best from precise, numeric, implementable instructions, not mood words like "make it pop".

**What I need from you (be concrete and numeric, because Claude will implement it from your text):**

1. A critique of the video, screen by screen (hub, story map, drop board, placement grid, battle): list what
   looks dated or amateur and why (spacing, hierarchy, contrast, outline weights, shadow style, icon style,
   typography, colour balance), ranked by impact.
2. A small UI kit spec I can hand to Claude: colour tokens (hex) for every state; type scale (sizes, weights)
   and a free font to use (open licence, for example OFL from Google Fonts) plus a number font; corner radii,
   border widths, shadow offsets and blur, inner-stroke opacity; button states (normal, pressed, disabled)
   with exact gradients; the 9-slice margins for each panel/button sprite.
3. Production assets as transparent PNGs where possible: button and panel 9-slice frames, a currency pill,
   a wave pill, icons (coin, star, lock, ball, heart, paw, arrow, crown), plus the gate bumpers, the cup,
   and peg and ball sprites. Please give the exact pixel size of each and say which edge pixels are stretchable.
4. An animation spec as tables Claude can code: for each effect (button press, panel pop-in, coin counter
   count-up, gate hit, ball squash, peg hit, cup catch, CUP! celebration, screen transitions, cat attack and
   run) give duration in ms, easing curve (for example cubic out, back out with overshoot 1.7), scale/offset/
   rotation keyframes, particle count, lifetime, speed, gravity, colours and fade curve.
5. Any sprite-sheet requests for characters (frame count, frame size, anchor point, transparent background,
   consistent line weight) so Claude can cut them automatically.
6. Finally, tell Claude what NOT to do (code-drawn effects that will always look cheap) and what must be
   real artwork instead.

Game facts you can rely on: portrait 390x844; Godot 4; no ads or purchases; cats are Macho (grumpy black Maine
Coon, melee), Rosette (Bengal sniper) and Adora (white acrobat); art style is edgy cartoon with thick black
outlines, spiked collars and amber eyes; hub accent colours are gold, hot magenta (#FF2E93) and cyan (#27E1F2)
on a deep plum base (#1E121F).
