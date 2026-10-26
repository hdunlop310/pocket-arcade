# Gemini asset prompts (redesign art pass)

Goal: separate image files I can drop into the game. The concept mockups you already have are the style reference: attach them to every prompt (hub, story map, drop board, battle placement) and say "match this exact art style, palette and line weight".

## Rules for every prompt (paste at the top)

- Portrait phone screen, exactly 780x1688 px (2x of 390x844) unless the prompt says otherwise.
- **Art only. No UI, no text, no numbers, no buttons, no coins, no characters** unless the prompt asks for them.
- Style: polished mobile-game illustration, soft painterly shading, thick dark outlines, neon cyan (#00F0FF) and magenta (#FF2E93) glow accents, deep purple base (#1A0B2E).
- One image per request. Keep important detail away from the very top and bottom 12% (the game draws UI there).
- For "transparent" items: plain flat #00FF00 green background (I will key it out), no shadow on the ground, no glow bleeding to the edges.

## 1. Map background (780x1688)
A dark enchanted forest at night seen straight on, misty layered tree silhouettes in purple, faint fireflies, a few glowing mushrooms and grass tufts at the edges. The centre should be calm and darker so a path can be drawn on top. No path, no UI.

## 2. Map road (transparent, 780x1688)
A single winding dirt road climbing from bottom to top in an S-shape, worn brown dirt with pebbles, a thin glowing cyan edge on both sides, small glowing grass tufts and tiny flowers along the edge. Flat #00FF00 background. It must pass roughly through these points (x, y as % of the image): (80,92) (50,84) (75,76) (30,68) (70,58) (25,48) (70,38) (28,28) (65,18) (50,6).

## 3. Battle background (780x1688)
Top 45%: a moody graveyard lawn at night, dark green grass, tombstones, an iron fence at the edges, faint fog. Bottom 55%: dark cobblestone wall and dirt (the game draws its board over this). No grid, no UI.

## 4. Battle board frame (transparent, 700x760)
An ornate stone-and-iron picture frame, dark grey stone with purple-silver metal corner brackets, empty dark-purple floor inside. The inner opening must be a clean rectangle 620x680 with a soft inner shadow. Flat #00FF00 outside the frame.

## 5. Bottom panel (transparent, 700x320)
A metal-and-stone panel, magenta health bar strip across the top labelled by nothing (leave blank), below it three empty square slots with glowing cyan borders and small corner ornaments. Flat #00FF00 outside.

## 6. START WAVE button (transparent, 640x170)
A wide gold ornate button with a pointed bevelled metal frame, glossy gold face, NO text. Also give a pressed version one pixel row darker. Flat #00FF00 background. Two separate images.

## 7. Drop board backdrop (780x1688)
Dark purple, very subtle: faint hexagon or circuit pattern, soft vignette, a tall rounded glass-like channel in the middle (about 90% of the width and 70% of the height) that is slightly darker than the rest. No pegs, no gates.

## 8. Drop board objects (each separate, transparent, flat #00FF00)
- Peg: a glowing cyan orb, 128x128, front view.
- Orange gate bumper: a wide slanted parallelogram bumper, glossy orange with a gold rim, NO text, 400x160.
- Magenta gate bumper: same shape, glossy magenta with a pink rim, NO text, 400x160.
- Cup: a steel-silver open-top bucket with a glowing cyan rim, front view, 520x300.

## 9. Optional icons (each 256x256, transparent)
Padlock, star (gold), crown (gold), gear (cyan), back chevron (cyan), coin (gold).

## How to hand them over
Save each file as the number and name above (for example `1_map_bg.png`) into `art_src/redesign/`, tell me, and I will slice, key out the green, and wire them in. Ask Gemini to redo anything with baked-in text or characters: those cannot be reused.
