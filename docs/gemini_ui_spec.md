# UI and animation spec from Gemini (2026-10-22), and what is implemented

Gemini's reply to `docs/gemini_ui_brief.md`, condensed. The right-hand column says where we are.

## Colour tokens (in `core/ui_kit.gd`)
| Token | Value | Status |
|---|---|---|
| Base plum | `#1E121F` | done (`PLUM`) |
| Panel charcoal | `#2A1B2D` | done (`CHARCOAL`) |
| Panel border | `#412945` | added (`PANEL_BORDER`), not used much yet |
| Magenta / cyan / gold | `#FF2E93` / `#27E1F2` / `#FFD700` | done |
| Header white / body / disabled | `#FFFFFF` / `#D0C2D3` / `#6B5C6E` | done (`CREAM`, `MUTED`, `GRAY`) |

## Typography
Headers: Changa or Fredoka, 24 to 32px bold, 1px tracking, shadow (0, 2px, #00000088). Buttons: 16 to 18px bold caps.
Body and numbers: Inter 14px medium. Outline 4px black on all UI text.
**Status:** done. Fredoka (headings, numbers) and Inter (body) are in `fonts/` with their OFL licences, used through
`UIKit.heavy()` and `UIKit.body()`; outline and drop shadow as before.

## Shape metrics
Cards radius 16, pills radius 24 (fully round), border 2px with 40% inner highlight, shadow offset (0, 4) blur 8
`#000000AA`. **Status:** roughly matched by `UIKit.card` and `UIKit.pill` (generated 9-slice textures).

## Assets (9-slice art)
Panel 128x128 margins 32; pill button 256x64 margins 24/0/24/0 with normal, pressed and disabled states; currency
pill 128x48 margins 20; gate bumpers 160x54. Gemini asked for real textured art instead of code-drawn shapes.
**Status:** Gemini supplied no image files, only specs, and Claude cannot paint. `UIKit.pill` generates 9-slice
textures in code, which is the closest we can get; real artwork would still look better. If the owner generates the
art, drop the PNGs in `art/ui/` and load them with `StyleBoxTexture` using the margins above.

## Animations
| Effect | Spec | Status |
|---|---|---|
| Button press | 80ms ease-out, scale 0.95, y +2px, pops back | done (`UIKit.attach_press`) |
| Panel pop-in | 250ms back-out, scale 0 to 1, alpha 0 to 1 | done for the map panel and hub overlays (`UIKit.pop_in`, from 0.94 and 0.92 rather than 0 for big panels) |
| Ball squash | on hit (1.2, 0.7) 40ms, then (0.8, 1.2), then (1, 1), 90ms total | done (`ball.gd`) |
| Coin counter | 400ms count-up, text scale 1.15 on increment | pop done (`coin_pulse`); the count-up uses a fast ease rather than exactly 400ms |
| Peg hit flash | 100ms, tint to white and back | done (`peg_fx`, 0.10s) |
| Cup catch | 150ms squash (1.1, 0.8), shake x +/-3px | done (`cup_squash`) |
| CUP! popup | 600ms elastic, scale 0.2 to 1.2, float up 40px, fade | done (`Fx` elastic popups; 0.9s so it holds longer) |

## Character sprite sheets (for future cats)
Horizontal strip, 8 frames wide, 256x256 per frame, anchor bottom-centre (0.5, 1.0), bold ink outline, flat cel
shading. Our current extractor (`tools/extract_sheet.gd`) handles the owner's 2x4 labelled sheets instead.

## Rules from Gemini
1. No flat code-drawn rectangles for buttons, panels or bars: use textured 9-slice or rich gradients with inner shadows.
2. No linear animation: use back-out or elastic easing so things have weight.
3. No plain system fonts: use heading colours, a 4px outline and a drop shadow.
