# Game wishlist

Owner's list of games for the hub. Mechanics are fair to borrow; names, characters and art must be our own. Add new ideas here as they come up. "Working title" names are placeholders.

| # | Working title | Genre | Core loop | Status |
|---|---|---|---|---|
| 1 | Cat Drop | Idle / ball-drop + auto-battler | Drop balls through multiplier gates into a cup, bank coins, buy cats, place on a tile grid, beat mouse waves and a boss | Built (prototype) |
| 2 | Car sort | Colour-sort puzzle | Cars queue in lanes; send each to a matching parking slot; helpers: +1 slot, hammer, shuffle | Planned next (inspired by Parking Loop) |
| 3 | Category cards | Word-association / sorting | You are dealt cards (words or items) and drop each onto the category it belongs to; wrong placements cost a life or time-free penalty | Idea (owner request) |
| 4 | Unscrew | Physical puzzle | Remove bolts in the right order to free plates | Idea (inspired by Screw Machine) |
| 5 | Ring turn | Rotate / link puzzle | Rotate and link rings to solve a layout | Idea (inspired by Rotate Rings) |
| 6 | Loop kitchen | Conveyor / sorting | Probably a loop of items to sort or collect (needs a clear mechanic before building) | Idea (inspired by Hotpot Loop) |
| 7 | Pixel fill | Colour-by-number pixel art | Fill a pixel grid with colours to reveal a picture | Idea (inspired by Colorever / Colony Flow) |
| 8 | Action roguelite | Archero-style shooter | Move and auto-shoot through rooms, pick upgrades, boss at the end | Idea, big (inspired by Claw Master) |

## Notes on #3 Category cards (needs design)
- Content: category decks as data (JSON): `{category: "Things that are cold", items: ["ice", "snow", ...]}`. Hundreds of items, so content authoring is the main cost. Consider generating decks with an LLM offline and reviewing them by hand.
- Variants to consider: sort into 2 to 4 categories; a mix where some cards fit two; a "odd one out" mode; harder levels with subtler categories (e.g. "Scottish things", "Things with wings").
- Difficulty comes from category similarity and number of categories, not a timer.
- Puzzle module fit: levels = decks, stars = accuracy, helpers = hint (reveals one card's category), skip, undo.
- No ads, no purchases: content packs are free and ship with the app.
