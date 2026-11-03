# Art brief: NES-style pixel art (WP27)

For the art session on Trevor's Mac and anyone adding art. Read `DESIGN.md` "Art and sound" and the character table first, and `game/ARCHITECTURE.md` section 15 for how the game loads art. This replaces the WP11 brief's flat sticker style (revision 2).

## 1. The look

An NES-era top-down adventure: a seaside town of one-screen rooms on a 16×16 grid, chunky and readable, with one strict palette. Warm teahouse, plank pier, a scrapyard, and the gnu's hand-built machines held together with brass, rope and sticky labels. Cosy and a little messy. Inspired by, not copied from, classic top-down games: no Link, Triforce, Zelda item sprites, fonts or map layouts.

- **Grid:** 16×16 tiles. The play area is 176×320 base pixels (11×20 tiles), scaled up by whole numbers with no smoothing (`D9` in PLAN.md).
- **Characters:** 16×16 sprite sheets; portraits 32×32.
- **Colours per sprite:** at most 3 colours plus transparency for 16×16 sprites and items (the outline counts as one). Portraits, close-ups and machines use the palette freely but stay flat: no gradients, no dithering beyond a 2-colour checker.
- **Outline:** 1 px in `black` around characters, items and props, so they read on any floor.
- **Animation:** 2 to 4 frames per action, at most 8 fps.
- **No text baked into art.** Words stay live text in the game.

## 2. Palette

The game's one palette is `palette` in `game/assets.json`. Every committed PNG uses only these 25 colours; `tools/art/pixelize.py` enforces it for generated art and `python -m art sprites` for text sprites.

The values were fitted to the [Ninja Adventure pack](https://pixel-boy.itch.io/ninja-adventure-asset-pack) in WP27: each name was snapped to the nearest colour the pack's tilesets and characters actually use (by area), unless that moved it too far from its name. `blue` and `purple` keep their original values as saturated accents the pack lacks. Against the pack's 190 colours the mean distance to the nearest palette colour fell from 14 to 9, so pack tiles survive the palette lock with little change.

| Name | Hex | Typical use |
| --- | --- | --- |
| `black` | `#141b1b` | Outlines, deepest shadow |
| `ink` | `#2b3631` | Dark shading, text on light |
| `dark_brown` | `#5c2d25` | Dark wood, fur shadow |
| `brown` | `#7b473c` | Wood, fur |
| `brown_light` | `#a3754e` | Planks, light wood |
| `tan` | `#c8966b` | Skin, rope, paper shadow |
| `sand` | `#eecf9b` | Sand, paper |
| `cream` | `#fce2ca` | Highlights, bellies, beards |
| `red` | `#d14b34` | Red panda fur, warnings |
| `orange` | `#e67c44` | Warm accents, lantern light |
| `yellow` | `#f1c471` | Brass, gold, glow |
| `green_dark` | `#345a52` | Deep foliage |
| `green` | `#74a334` | Grass, apron |
| `lime` | `#adbc3a` | Grass highlight |
| `teal` | `#548789` | Sea, penguin back |
| `blue_dark` | `#4a5270` | Night, slate, deep water |
| `blue` | `#4b84c4` | Accents (kept: the pack has no strong blue) |
| `sky` | `#b8dce5` | Sky, shallow water, glass |
| `grey_dark` | `#4e484a` | Iron, machine shadow |
| `grey` | `#8d977f` | Stone, steel |
| `silver` | `#d2c9c9` | Polished metal |
| `white` | `#f2eaf1` | Paper, teeth, sparkle |
| `pink` | `#ef9597` | Cheeks, tongue, coral |
| `purple` | `#71498a` | Anglerfish suit, magic (kept: the pack has no strong purple) |
| `dirt` | `#ad8d6d` | Paths, dust |

## 3. Characters

All eight are original designs inspired by an animal, never by a project's mascot artwork. Prompts for generated art describe the animal, its clothes, colours and props, and **never name a project, a mascot or a logo**. Each needs a distinct silhouette at 16 px.

Portrait expressions, matching `game/assets.json`: `neutral`, `happy`, `worried`, `surprised`, `sly`. The neutral portrait comes first; the others are edits of the approved reference, never fresh generations.

| Character | Design notes | Do not |
| --- | --- | --- |
| **Gnu** (retired maintainer) | Tall shoulders, heavy dark mane sagging into a long cream beard, small upturned horns, gold round spectacles on a string, a worn brown cardigan with pencils and sticky notes. Prop: a ring of mismatched keys. Appears only in portraits (notes and voicemails). | Draw the line-engraved GNU head, its swirl beard or a black-and-white emblem. |
| **Seagull** (collector of lost fortunes) | Wide cream chest, teal-grey wing tips, hooked beak with a coral spot, one foot raised, a satchel of crumpled fortune slips. | Reuse the SeaGL logo gull, its pose or colours. |
| **Penguin** (Cookie Machine helper) | Slim and tall like a little blue penguin, short feather tuft, teal back, cream belly, gold goggles on the forehead, tool belt. Prop: an oversized spanner. | Make it black and white with an orange beak and feet, an egg-shaped belly or Tux's pose. |
| **Gopher** (courier) | Low, long, sandy pocket gopher with cheek pouches, small dark beady eyes, digging claws, a coral courier cap. Prop: a string-tied parcel bigger than its head. | Use sky-blue fur, big round white eyes, or the Go gopher's proportions and buck-tooth smile. |
| **Crab** (apprentice) | Small shore crab, dusky purple shell, one oversized gold claw, eyes on short stalks, a too-big cream apron. Prop: a rubber "merge" stamp. | Make it flat orange-red, give it two matching claws, or use Ferris's wide smile and dot eyes. |
| **Elephant** (archivist) | Broad and gentle, light sandy-tan skin, huge ears with paper tags, half-moon glasses, a plum cardigan. Prop: a card-catalogue drawer with notes. | Use blue-grey or blue-violet skin, a head-in-a-circle logo, a raised-trunk emblem, Slonik's linework or the PHP elephpant's shape. |
| **Red Panda** (teahouse keeper) | Round and fluffy, white cheek patches, ringed tail, tea towel on the shoulder, green apron. Prop: a steaming teapot. | Curl it around a globe, use flame gradients, or draw a pointed-muzzle fox like the Firefox logo. |
| **Anglerfish** (FortuneCloud salesperson) | Round, wide-grinning deep-sea fish standing on its fins, dark teal body, tiny tie, cream teeth, a glowing gold lure on a stalk (the "FREE TRIAL" words stay live text). Prop: a clamshell briefcase that never opens. | Echo any real cloud vendor's logo, colours or shapes. |

The player is the Ninja Adventure `Boy` sheet until the town slice's art lands.

## 4. Asset list

`game/assets.json` is the contract (PLAN.md D11): the game loads every sprite, tile and portrait by logical name and draws a labelled placeholder until the file lands at its path. Print the current list, with what has landed:

```sh
PYTHONPATH=tools uv run --python 3.12 --with pillow==13.0.0 python -m art list                 # everything
PYTHONPATH=tools uv run --python 3.12 --with pillow==13.0.0 python -m art list --prefix portrait
PYTHONPATH=tools uv run --python 3.12 --with pillow==13.0.0 python -m art list --missing  # still placeholders
```

| Names | Count | Frame px | Path under `game/` | Source |
| --- | --- | --- | --- | --- |
| `tile.*` | 23 | 16×16 | `art/ninja/Backgrounds/Tilesets/...` | Ninja Adventure tilesets, at the listed `origin` |
| `char.*` | 8 | 16×16, 4 columns (down, up, left, right), rows are frames | `art/characters/<id>_sheet.png`; player from Ninja Adventure | Hand-drawn from the approved reference |
| `portrait.*` | 40 | 32×32 | `art/portraits/<id>_<expression>.png` | Generated reference, pixelized; expressions by edit |
| `item.*` | 6 | 16×16 | `art/items/item_<id>.png` | Text sprites |
| `prop.*` | 20 | 16×16 to 64×48 | `art/props/prop_<id>.png` | Text sprites or Ninja Adventure |
| `machine.*` | 17 | 8×8 to 144×64 | `art/machines/machine_<machine>_<part>.png` | Text sprites, or generated and pixelized |
| `closeup.*` | 18 | 16×16 to 176×40 | `art/closeups/closeup_<id>.png` | Generated and pixelized |
| `fx.*` | 6 | 8×8 | `art/fx/fx_<id>.png` | Text sprites |
| `ui.*` | 1 | 20×20 | `art/ui/ui_<id>.png` | Text sprite |

When a file lands, fix `origin`, `frame_size` or `animations` in `game/assets.json` if the art differs from the guess. The game needs no code change.

**Ninja Adventure paths.** The current pack (download from itch.io, CC0) keeps characters under `Actor/Character/<Name>/`, not `Actor/Characters/` as `assets.json` guessed for the player. The tile batch corrects that path and the tile `origin` values. Commit only the sheets the game uses, under `game/art/ninja/` with the pack's own folder names.

**Size budget.** Pixel art is small: aim for `game/art/` under 1 MB. The web export's 12 MB gzip budget in CI covers it.

## 5. The pipeline

Everything runs from the repository root on Trevor's Mac with `uv` (Python 3.12, Pillow 13.0.0). Below, `art` means `PYTHONPATH=tools uv run --python 3.12 --with pillow==13.0.0 python -m art`.

**1. Generate** through the steam-machine's media API only, one render at a time, never ComfyUI directly, changing nothing on the box. The address, key and user come from the environment; the private handoff file says where to find them:

```sh
export MEDIA_API_URL=...   MEDIA_API_USER=...   MEDIA_API_KEY="$(...)"   # never into a file
art render image "<prompt>" ~/.cache/fortune-art/renders/<id>_a.png --quality best --shape square
```

Use `best` (Qwen-Image-2512) for references and portraits, `fast` (Z-Image-Turbo) for quick drafts, and `edit` (Qwen-Image-Edit-2511) with `--source <library item>` for new poses and expressions of an approved reference. The client reads the render graph that ComfyUI embeds in the PNG and writes `<out>.json` with the model, LoRA, seed and steps, and exits 1 if the graph loads anything but the pinned models (DESIGN.md, D21). Renders stay outside the repo (`~/.cache/fortune-art/`) and in Trevor's Media tab.

**Prompt template for a character reference:**

> Character design reference for a cozy retro top-down adventure game: *<design notes from section 3>*. Full body, front view, standing upright facing the viewer, centered, chunky cute proportions with a big head. 16-bit pixel art style, clean flat colours, bold dark outline, simple readable shapes. Plain solid flat magenta background, no shadow, no text, no frame.

The flat backdrop matters: the pixelizer removes the background by flood fill from the border.

**2. Pixelize** every generated image with `tools/art/pixelize.py`: background removal, crop, palette lock, shrink to the grid by majority colour per cell, colour limit, speck removal and a 1 px outline.

```sh
art pixelize render.png game/art/portraits/red_panda_neutral.png --size 32x32 --crop 0.05,0,0.85,0.55 --preview /tmp/p.png --scale 8
art pixelize render.png sprite.png --size 16x16 --max-colors 2 --anchor bottom    # 2 + outline = 3
```

`--crop` takes fractions of the subject's bounding box (head and shoulders for portraits), `--colors` limits the subject to named palette colours, `--background NAME` fills behind it, `--outline none` drops the outline.

**3. Clean up** by hand in Pixelorama where needed: eyes, mouth, a stray pixel. Keep to the palette.

**4. Review.** Trevor approves each batch from a contact sheet before anything is committed. Character references come first, and work stops there until they are approved.

**5. Commit** only the approved, final PNG, plus its provenance: a line in `ASSETS.md` and the render record (`<out>.json` with the pixelize command added) as `art-src/generated/<asset>.json`. Raw renders, drafts and rejected variants are never committed.

**Text sprites.** Small items, props, effects and UI are grids of characters in `art-src/sprites/*.txt`, built into PNGs by `art sprites` (format in `tools/art/sprites.py`). Commit the `.txt` and the PNG; `art sprites --check` fails if a PNG is stale.

**Tests:** `PYTHONPATH=tools uv run --python 3.12 --with pillow==13.0.0 python -m unittest discover -s tools/art/tests -t tools` (also in CI).

## 6. Accessibility

- **Colour is never alone.** Broken and fixed parts differ in shape, not only colour: a cracked gear against a turning one, a dry pipe against a flowing one.
- **Readable at 1×.** Every sprite must read at its native size before scaling; check the 1× contact sheet.
- **No flashing.** Nothing flashes more than 3 times a second; glows pulse over a second or more.
- **Tap targets** are set by the game, not the art; art never shrinks a hit area.

## 7. Licensing and provenance

Art and audio are **CC-BY-SA 4.0** (`LICENSES/CC-BY-SA-4.0.txt`); code is AGPL-3.0-or-later. `ASSETS.md` lists every committed asset with its source, licence and author, and for generated assets the model, prompt and seed, labelled AI-generated. Ninja Adventure (Pixel-boy and AAA) and Kenney are CC0 and credited anyway.

Only the pinned, Apache 2.0 image models may produce shipped art: Z-Image-Turbo, Qwen-Image-2512 and Qwen-Image-Edit-2511, with their Lightning LoRAs. Newer Qwen-Image releases (2.1 and later) carry a research-only licence; no upgrade without a licence check.

**No third-party mascot artwork** is used, traced, recoloured, kept as a reference overlay or named in a prompt: Tux, the Go gopher, Ferris, Slonik, the PHP elephpant, the Firefox logo, the GNU head, the SeaGL logo.

**Private details stay out.** No addresses, host names, keys or paths of Trevor's machines in commits, records or prompts. Records name the library item, never the server.

## 8. Review checklist

1. File at the exact path and pixel size in `game/assets.json`.
2. Palette colours only; at most 3 per 16×16 sprite including the outline.
3. Reads at 1×; distinct silhouette.
4. No baked-in text; no mascot or logo resemblance (section 3 "Do not").
5. Animation 2 to 4 frames, at most 8 fps, no flashing.
6. `ASSETS.md` line and, for generated art, the `art-src/generated/` record with a pinned model.
7. Approved by Trevor.
