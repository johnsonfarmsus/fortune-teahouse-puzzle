# Art direction brief (WP11)

For a human artist or a later image-generation pass. Read `DESIGN.md` (story, characters) and `game/ARCHITECTURE.md` sections 1, 4 and 9 first. Today the game is coloured rectangles and labels; this brief says what replaces them.

## 1. Visual direction

A seaside pier town at dusk: a warm teahouse with paper lanterns, a plank pier with gulls, and the gnu's workshop of hand-built machines held together with brass, rope and sticky labels. Cosy and a little messy.

**Style.** Flat colour shapes, no gradients, textures or soft shadows. Every sprite has a thick dark outline (4 px at 2x) plus a thin Steam Cream rim outside it, like a die-cut sticker, so dark characters read on the dark UI. Detail must survive a 2x downscale: no line under 3 px at 2x, eyes at least 8 px at 2x, and no text baked into art (words stay live `Label` text).

**Palette (8 named colours).** Artwork uses only these plus at most one lighter and one darker tint of each. Ratios are WCAG 2.x contrast, computed in Python.

| Name | Hex | Role | vs Night Tea | vs Deep Brew |
| --- | --- | --- | --- | --- |
| Night Tea | `#291D17` | Screen background (`UiKit.BG_COLOR`) | 1.00 | 1.09 |
| Deep Brew | `#1F1611` | HUD bar, outlines | 1.09 | 1.00 |
| Steam Cream | `#F5E9D3` | Body text, sticker rim | 13.63 | 14.80 |
| Lantern Gold | `#F2B833` | Accent, "fixed" glow, lures | 9.11 | 9.89 |
| Tide Teal | `#4FB3A9` | Sea, cool accents | 6.51 | 7.07 |
| Crab Coral | `#F0735E` | Warm accent, warnings | 5.71 | 6.20 |
| Dusk Plum | `#B79AE0` | Sky, shadows | 6.79 | 7.38 |
| Dune Sand | `#C9A36F` | Planks, wood, earth | 6.98 | 7.58 |

All six light colours pass 4.5:1 as text on both dark backgrounds (lowest: Crab Coral 5.71). Dark text on a coloured button: Night Tea on Lantern Gold 9.11; Deep Brew on Tide Teal 7.07, Crab Coral 6.20, Dune Sand 7.58. Never put Steam Cream text on a light palette colour (2.4:1 or worse).

## 2. Character sheets

All eight are original designs inspired by an animal, not the projects' official mascot artwork. Sketch from animal photos, never mascot art. Each needs a distinct silhouette at 64 px tall.

**Gnu (retired maintainer).** Tall shoulders, heavy shaggy mane sagging into a long beard, small upturned horns, round spectacles on a string. Night Tea body, Steam Cream beard, Lantern Gold spectacles. Prop: a ring of mismatched keys and a roll of sticky labels. Expressions: neutral (tired kind eyes), happy (beard lifted, eyes closed), apologetic (ears down, scratching the neck, brows tilted up). Do not: draw the line-engraved GNU head, its swirl beard, or a black-and-white emblem.

**Seagull (collector of lost fortunes).** Wide chest, hooked beak, one foot raised, a satchel stuffed with paper scraps. Steam Cream, Tide Teal wing tips, Crab Coral beak spot. Prop: a butterfly net full of crumpled fortunes. Expressions: neutral, happy. Do not: reuse the SeaGL conference logo gull, its pose or colours.

**Penguin (Cookie Machine helper).** Slim and tall like a little blue penguin, with a feather tuft, goggles on the forehead and a tool belt. Tide Teal back, Steam Cream belly, Lantern Gold goggles. Prop: an oversized adjustable spanner. Expressions: neutral, happy. Do not: make it black and white with an orange beak and feet, an egg-shaped belly or Tux's pose.

**Gopher (courier).** Low, long pocket gopher in a courier cap, with cheek pouches, small dark beady eyes and digging claws. Dune Sand fur, Steam Cream muzzle, Crab Coral cap. Prop: a string-tied parcel bigger than its head. Expressions: neutral, happy. Do not: use sky-blue fur, big round white googly eyes, or the Go gopher's proportions and buck-tooth smile.

**Crab (apprentice).** Small shore crab with one oversized claw, eyes on short stalks, a too-big apron. Dusk Plum shell, Lantern Gold big claw, Steam Cream apron. Prop: a rubber "merge" stamp. Expressions: neutral, happy (plus the merge frames in section 3). Do not: make it flat orange-red, give it two matching claws, or use Ferris's wide smile and plain dot eyes.

**Elephant (archivist).** Broad and gentle, huge ears carrying paper tags, half-moon glasses, a cardigan. Light Dune Sand skin, Dusk Plum cardigan, Steam Cream tags. Prop: a card-catalogue drawer with notes sticking out. Expressions: neutral, happy. Do not: use blue-grey or blue-violet skin, a head-in-a-circle logo, a raised-trunk emblem, or Slonik's linework (or the PHP elephpant's shape).

**Red Panda (teahouse keeper).** Round and fluffy, ringed tail, white cheek patches, tea towel on the shoulder. Crab Coral fur, Steam Cream face, Night Tea tail rings. Prop: a steaming teapot. Expressions: neutral, happy. Do not: curl it around a globe, use flame gradients, or draw a pointed-muzzle fox like the Firefox logo.

**Anglerfish (FortuneCloud salesperson).** Round, wide-grinning deep-sea fish in a tiny tie, with a glowing lure on a stalk (the "FREE TRIAL" words stay live text). Darker Tide Teal body, Lantern Gold lure, Steam Cream teeth. Prop: a clamshell briefcase that never opens. Expressions: neutral (smooth smile), smug (lure bright). Do not: echo any real cloud vendor's logo, colours or shapes.

## 3. Asset list

PNG with alpha at 2x of the 390x844 base (a full screen is 780x1688). `canvas_items` stretch shows a texture at half its pixel size. Prefer indexed PNG-8 with alpha (lossless with 8 colours).

| Asset | Scene source | Base px | File px | Count | Path and name |
| --- | --- | --- | --- | --- | --- |
| Place and machine tiles | `Hotspot/Visual` | 96x96 | 192x192 | 6 | `game/art/world/tile_{shop,pier,teahouse,fortune_machine,cookie_machine,oven}.png` |
| Avatar | Town `Avatar` | 32x48 | 64x96 | 3 | `game/art/world/avatar_{idle,walk_a,walk_b}.png` |
| Town, shop backgrounds | `Ground`, `Path`, `Floor` | 390x950 | 780x1900 | 2 | `game/art/world/bg_{town,shop}.png` |
| Fixture icons | `PartFixture` Broken, Fixed | 48x48 | 96x96 | 36 | `game/art/fixtures/<machine>_<part>_<state>.png` |
| Status lights | machine view lights | 24x24 | 48x48 | 3 | `game/art/ui/status_{todo,partial,done}.png` |
| Chips (nine-slice) | matching 104x48, sequence 150x52, word 96x48 | n/a | 96x96, 24 px margins | 4 | `game/art/ui/chip_{normal,selected,placed,decoy}.png` |
| Slots (nine-slice) | matching slot 60 high, word blank 88x48 | n/a | 96x120, 24 px margins | 2 | `game/art/ui/slot_{empty,filled}.png` |
| Rhythm lamps | 44x44 | 44x44 | 88x88 | 2 | `game/art/ui/lamp_{dim,lit}.png` |
| Crab merge frames | `MergeCelebration`, Crab 120x90 | 120x90 | 240x180 | 8 | `game/art/crab/crab_merge_00.png` to `_07.png` |
| Portraits | helpers, dialogue, finale | 128x128 | 256x256 | 17 | `game/art/characters/<animal>_<expression>.png` |
| Title art | Start `Title` 340x130 | 340x130 | 680x260 | 1 | `game/art/screens/title.png` |
| Start background | Start `Background` | 390x950 | 780x1900 | 1 | `game/art/screens/bg_start.png` |
| Big-screen background | `server/static/bigscreen` | 1920x1080 | 1920x1080 | 1 | `server/static/bigscreen/img/bigscreen_bg.png` |

- **Fixtures:** `<machine>` is `fortune_machine`, `cookie_machine` or `oven`; `<part>` is `logic`, `wiring`, `sequence`, `word`, `rhythm` or `helper`; `<state>` is `broken` or `fixed` (3 x 6 x 2 = 36). They must differ in shape, not just colour: a cracked gear against a turning one, a dry pipe against a flowing one. Keep the bottom 16 px (2x) clear for the label.
- **Portraits:** Gnu has `neutral`, `happy`, `apologetic`; Anglerfish `neutral`, `smug`; the other six `neutral`, `happy` (3 + 2 + 12 = 17). Bust, facing right.
- **Crab frames:** 00 to 03 a four-step sideways scuttle loop, 04 to 06 raise and press the stamp, 07 the held pose. At most 8 fps; the existing tween slides it across.
- **Backgrounds** are 950 base px tall because `aspect="expand"` shows extra height on tall phones. Keep everything important in the central 390x844; the rest is flat bleed.
- **Big screen** is a landscape page outside the Godot project, so it is not in the pck. Keep the central 70 percent plain so live text passes 4.5:1.
- **Sources:** layered files go in `art-src/` at the repo root, mirroring the names (the AGPL requires the preferred form for modification).

**Size budget.** 85 PNGs in `game/art/`, estimated 1.4 MB (fixtures about 6 KB, portraits about 25 KB, backgrounds about 150 KB each). Caps: icon or tile 15 KB, portrait 40 KB, background 200 KB, big-screen background 400 KB. Hard limit: `game/art/` at most 2.5 MB of PNG, adding under 3 MB to the pck (Godot imports to lossless WebP, no larger than PNG).

## 4. Accessibility

- **Colour is never alone.** Broken against fixed differs in silhouette; status lights are an empty ring, a half disc and a disc with a check mark.
- **Text contrast at least 4.5:1**, using only the pairs in section 1. Art behind live text (title, tiles, big screen) keeps that ratio under the glyphs.
- **Tap targets at least 44x44 base px.** Art never shrinks a hit area; Area2D and Button sizes stay as they are.
- **No flashing.** Nothing flashes more than 3 times a second, no large brightness jumps. Glows pulse over a second or more. Animations stay skippable, as the current tweens are.

## 5. Licensing

**Decided 3 Nov 2026: art and audio are CC-BY-SA 4.0** (`game/art/`, `game/audio/`, `art-src/`, `server/static/bigscreen/img/`); code stays AGPL-3.0-or-later. Only approved, final assets are committed. This brief is due to be rewritten for the NES pixel style (PLAN.md WP27). The root `LICENSE` stays the AGPL text, and the README License section must state the art licence explicitly, naming those folders if CC-BY-SA 4.0 is chosen. PNGs cannot carry SPDX headers, so `game/art/CREDITS.md` holds one line per asset group:

`<path glob> | <artist name or handle> | <year> | <AGPL-3.0-or-later or CC-BY-SA-4.0> | <link to artist or source>`

**No third-party mascot artwork is used, traced, recoloured or kept as a reference overlay**: Tux, the Go gopher, Ferris, Slonik, the PHP elephpant, the Firefox logo, the GNU head, the SeaGL logo. Image generators must not be prompted with those names or images; keep prompts in `art-src/PROMPTS.md`.

## 6. Delivery and integration

**Handover.** One PR (or a zip) containing: PNGs at the exact names and sizes above; layered sources in `art-src/`; `CREDITS.md` updated; a contact sheet (not shipped) on Night Tea at 1x. Checklist:

1. Names match the table (lowercase, underscores).
2. Pixel sizes and nine-slice margins match.
3. Alpha PNG, palette colours and tints only.
4. Contrast at least 4.5:1 under live text; no baked-in text.
5. No flashing; animation at most 8 fps.
6. Licence and attribution lines added.
7. Size caps met.
8. Written confirmation that no official mascot art was used or traced.

**Swapping a placeholder without touching scripts.** Edit only the `.tscn`:

- Replace each `ColorRect` or `Polygon2D` placeholder with a `TextureRect` (or `Sprite2D`) with the **same node name** and offsets: `mouse_filter = 2`, `expand_mode = 1`, `stretch_mode = 5`. Examples: `Hotspot/Visual`, `PartFixture/Broken/Shape`, `PartFixture/Fixed/Shape`, `Town/Ground`, `Shop/Floor`, `StartScreen/Background`. `Label` children stay.
- Where a script types the node (`town.gd`: `var avatar: ColorRect = $Avatar`), keep the `ColorRect` at alpha 0 and add the art as a child named `Sprite`.
- Per-place tiles are texture overrides on `Visual` in `town.tscn` and `shop.tscn`, not in `hotspot.tscn`.
- `ext_resource` paths have no `uid=`, per `ARCHITECTURE.md`.

**Exceptions needing a small code PR:** the Crab and "Merged!" stage (built in `merge_celebration.gd`), status lights (`ColorRect.new()` in `machine_view.gd` and `crew_progress.gd`), and chips, slots and lamps (`StyleBoxFlat` in the puzzle scripts). A follow-up adds one `UiKit` hook for nine-slice `StyleBoxTexture`; the 44 px minimums do not change.

**CI size budget.** Today `tools/dev/check-size.sh` fails when the gzip of the web export exceeds 12 MB (the design doc says uncompressed, but the engine `.wasm` alone is about 39 MB, so the script budgets gzip). Add `tools/dev/check-art-size.sh`: `game/art/**/*.png` totals at most 2.5 MB, no file over 400 KB, and each PNG's pixel size matches this table (read the PNG header with `python3 -I`). It passes on an empty folder, so it can land before the art.
