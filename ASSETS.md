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
| *(none yet: the character references are in review)* | | | | | |
