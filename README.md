# The Fortune Teahouse

A collaborative, phone-first puzzle game for SeaGL 2027: attendees get custom fortune cookies, form crews by the fortune they hold, and fix a retired gnu's three fortune cookie machines together. Godot 4.7 (GDScript), web export, free software under the GNU AGPL.

**Status:** all three machines (Fortune Machine, Cookie Machine and Oven) are playable, each with six parts; the finale, the scoreboard client and real art are still to come.

- [DESIGN.md](DESIGN.md) is the game design.
- [PLAN.md](PLAN.md) is the build plan and work packages.
- [docs/DESIGN-REVIEW.md](docs/DESIGN-REVIEW.md) is the design review.

## Get Godot locally

Godot 4.7.2-stable is pinned. On Linux x86_64:

```sh
GODOT=$(tools/dev/get-godot.sh)
$GODOT --version
```

The script downloads the editor binary (it runs headless) and the matching export templates into `~/.cache/fortune-godot` and installs the templates to `~/.local/share/godot/export_templates/4.7.2.stable/`. Set `FORTUNE_GODOT_CACHE` to change the cache directory. On other platforms, install Godot 4.7.2 and its export templates yourself.

## Run the tests

Tests use [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4). The addon is not committed; install the pinned version for local runs (git-ignored):

```sh
tools/dev/get-gdunit4.sh
$GODOT --headless --path game --import
$GODOT --headless --path game -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Headless Godot can exit 0 even when something failed to load, so also look for `ERROR` in the output (CI greps for it). Unit tests live in `game/test/unit`, scene tests in `game/test/scene`, shared fixtures in `game/test/fixtures`.

To try the game itself, run `$GODOT --path game` (a window, 390x844 portrait) or serve the web export below.

## Export the web build

```sh
mkdir -p game/build/web
$GODOT --headless --path game --import
$GODOT --headless --path game --export-release "Web" build/web/index.html
tools/dev/check-size.sh game/build/web
```

The export is single-threaded (no SharedArrayBuffer, no cross-origin isolation headers needed) and uses the Compatibility renderer (WebGL 2). To play it locally, serve `game/build/web` over HTTP, for example `python3 -m http.server -d game/build/web 8080`.

### Size budget

CI fails if the exported build exceeds 12 MB **gzipped**, which is what a phone downloads from GitHub Pages. The uncompressed size is reported but not limited: Godot's engine `.wasm` alone is about 38 MB uncompressed (about 10 MB gzipped), so an uncompressed 12 MB limit could never pass. Both numbers appear in the job summary.

## CI and deploy

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

1. **test**: gdUnit4 tests via `godot-gdunit-labs/gdUnit4-action` (it installs Godot and the addon).
2. **build**: `chickensoft-games/setup-godot` with export templates, `--import` twice, export of the "Web" preset, then a size budget check. Each Godot log is grepped for `ERROR` and the job fails on a match. The web build is uploaded as the `web-build` artifact.
3. **deploy** (push to `main` only, after test and build pass): publishes the build to GitHub Pages with `actions/deploy-pages`. A `.nojekyll` file is added to the export. The deploy job asks `configure-pages` to enable Pages; if the repository setting refuses that, set Settings > Pages > Source to "GitHub Actions" once.

## Repository layout

| Path | What lives there |
| --- | --- |
| `game/` | The Godot project. `autoload/` singletons, `scripts/core/` plain classes, `scenes/` (`main`, `world`, `hud`, `ui`, `screens`, `puzzles`), `data/` (puzzle JSON and per-machine parts), `test/`. Start with [game/ARCHITECTURE.md](game/ARCHITECTURE.md) |
| `puzzles/` | Every clue as YAML; `tools/solver/export_json.py` turns it into `game/data/puzzles/*.json` |
| `tools/dev/` | Developer scripts: `get-godot.sh`, `get-gdunit4.sh`, `check-size.sh` |
| `tools/solver/` | Python solver and clue generator |
| `server/` | Scoreboard service and big-screen page |
| `docs/` | Design review and other documents |
| `.github/workflows/` | CI, build and deploy |

## License

GNU Affero General Public License, version 3 or later (`AGPL-3.0-or-later`). Every source file carries an `SPDX-License-Identifier: AGPL-3.0-or-later` header. Because the AGPL covers network use, the game's about screen and the big-screen page must link to this source repository: https://github.com/johnsonfarmsus/fortune-teahouse-puzzle
