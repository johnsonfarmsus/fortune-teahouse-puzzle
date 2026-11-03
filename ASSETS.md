# Assets and provenance

Every art and audio file committed to this repository, where it came from, its licence and its author. See `docs/ART-BRIEF.md` for the pipeline and DESIGN.md "Art and sound" for the rules.

- **Our own art and audio** (`game/art/`, `game/audio/`, `art-src/`, `server/static/bigscreen/img/`) are licensed **CC-BY-SA 4.0** (`LICENSES/CC-BY-SA-4.0.txt`), © the Fortune Teahouse contributors.
- **Third-party packs** keep their own licence (CC0 below) and are credited even where the licence does not require it.
- **AI-generated assets** are labelled as such, with the model, prompt and seed. Each has a record in `art-src/generated/<asset>.json` (the render graph's model, LoRA, seed and steps, plus the pixelize command). Only approved, final assets are committed; raw renders stay on the steam-machine.
- Only the pinned models may produce shipped art: Z-Image-Turbo, Qwen-Image-2512 and Qwen-Image-Edit-2511 (all Apache 2.0), with the Qwen-Image Lightning LoRAs (Apache 2.0).

## Credits

| Source | Author | Licence | Link | Used for |
| --- | --- | --- | --- | --- |
| Ninja Adventure asset pack | Pixel-boy and AAA | CC0 1.0 | https://pixel-boy.itch.io/ninja-adventure-asset-pack | Tiles, the player sprite, the palette reference |
| Kenney 16×16 packs | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets | Gap fills (none yet) |

## Files

| Path | Source | Licence | Author | AI-generated | Record |
| --- | --- | --- | --- | --- | --- |
| `game/art/portraits/gnu_neutral.png` | Gnu neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682048113), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.gnu.neutral.json` |
| `game/art/portraits/seagull_neutral.png` | Seagull neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682120206), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.seagull.neutral.json` |
| `game/art/portraits/penguin_neutral.png` | Penguin neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682161086), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.penguin.neutral.json` |
| `game/art/portraits/gopher_neutral.png` | Gopher neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682180214), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.gopher.neutral.json` |
| `game/art/portraits/crab_neutral.png` | Crab neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682220861), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.crab.neutral.json` |
| `game/art/portraits/elephant_neutral.png` | Elephant neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682262240), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.elephant.neutral.json` |
| `game/art/portraits/red_panda_neutral.png` | Red Panda neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682326074), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.red_panda.neutral.json` |
| `game/art/portraits/anglerfish_neutral.png` | Anglerfish neutral portrait: generated reference (Qwen-Image-2512 + Qwen-Image-2512-Lightning 8-step, seed 1682345199), pixelized to 32×32 | CC-BY-SA-4.0 | Fortune Teahouse contributors | Yes | `art-src/generated/portrait.anglerfish.neutral.json` |
