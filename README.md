# The Fortune Teahouse

A collaborative, phone-first puzzle game for SeaGL 2027: attendees get custom fortune cookies, form crews by the fortune they hold, and fix a retired gnu's three fortune cookie machines together. Godot 4.7 (GDScript), web export, free software under the GNU AGPL.

**Status:** Phase 3 has started: the rebuild slice (WP16) replaces the menu-style layer with a walkable pixel-art town of eight rooms, characters with portrait dialogue, a drag-to-use inventory shared by the crew through the scoreboard, the Cookie Machine as an animated contraption, the whole cutter-die chain (misdirects at the scrapyard and the harbour, the outdated-locker-code decoy) and the batter jars dragged onto a shelf, all with placeholder art drawn in code and sounds synthesised at run time (428 game tests pass; see section 15 of [game/ARCHITECTURE.md](game/ARCHITECTURE.md)). The old screens stay behind Menu > Old screens (debug) until the slices replace them, and the slice waits for Trevor's phone test. Phases 1 and 2 are done. All three machines (Fortune Machine, Cookie Machine and Oven) are playable with six parts each, the scoreboard server and the game's scoreboard client work together, and the web build exports at about 10 MB gzipped (357 game tests at the end of Phase 2). The finale is implemented end to end (handoff notes and words, the dials puzzle for three handoffs, Elephant's Archive, the start code, the README and the big-screen reveal; see docs/FINALE-DESIGN.md) and has been run against a real local scoreboard by a headless script and in a desktop browser with touch emulation, but not yet on a real phone or with a crowd. Still to come: real art, the Hetzner deploy of the scoreboard, a real-device finale test, and answers to the open event questions. See "Phase 1 outcome" and "Phase 2 outcome" in [PLAN.md](PLAN.md).

To repeat the end-to-end finale run, start a scoreboard with the finale settings (see "Finale integration run" below) and run `$GODOT --headless --path game -s ../tools/dev/finale_integration.gd`.

- [DESIGN.md](DESIGN.md) is the game design.
- [PLAN.md](PLAN.md) is the build plan and work packages.
- [docs/DESIGN-REVIEW.md](docs/DESIGN-REVIEW.md) is the design review.
- [docs/SMOKE-TEST.md](docs/SMOKE-TEST.md) is the checklist for trying the build on a real phone.

**Where it runs:** production is the Hetzner VPS, where Caddy serves the game, the scoreboard API (`/api/`) and the big screen (`/bigscreen/`) from one origin, deployed by CI on every merge to `main` ([docs/DEPLOY.md](docs/DEPLOY.md)). GitHub Pages is kept as a staging mirror.

## Get Godot locally

Godot 4.7.2-stable is pinned. On Linux x86_64 or macOS (Apple silicon or Intel):

```sh
GODOT=$(tools/dev/get-godot.sh)
$GODOT --version
```

The script downloads the editor binary (it runs headless) and the matching export templates into `~/.cache/fortune-godot` and installs the templates where Godot looks for them: `~/.local/share/godot/export_templates/4.7.2.stable/` on Linux, `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` on macOS. On macOS `$GODOT` is the binary inside `Godot.app` (`~/.cache/fortune-godot/Godot_v4.7.2-stable_macos/Godot.app/Contents/MacOS/Godot`), so the commands below work unchanged. Set `FORTUNE_GODOT_CACHE` to change the cache directory. On other platforms, install Godot 4.7.2 and its export templates yourself.

The server and solver tests need Python 3.12 (as in CI). With [uv](https://docs.astral.sh/uv/), from the repository root:

```sh
(cd server && uv run --python 3.12 --with-requirements requirements-dev.txt python -m pytest -q)
PYTHONPATH=tools uv run --python 3.12 --with pyyaml==6.0.2 --with jsonschema==4.23.0 python -m unittest discover -s tools/solver/tests -t tools
PYTHONPATH=tools uv run --python 3.12 python -m solver check puzzles/
```

## Run the tests

Tests use [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4). The addon is not committed; install the pinned version for local runs (git-ignored):

```sh
tools/dev/get-gdunit4.sh
$GODOT --headless --path game --import
$GODOT --headless --path game -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
```

Headless Godot can exit 0 even when something failed to load, so also look for `ERROR` in the output (CI greps for it). Unit tests live in `game/test/unit`, scene tests in `game/test/scene`, shared fixtures in `game/test/fixtures`.

To try the game itself, run `$GODOT --path game` (a window, 390x844 portrait) or serve the web export below.

## Point the game at a scoreboard

By default the game is offline-only: progress lives on the phone. To share progress through a scoreboard server (see [server/README.md](server/README.md); locally `uvicorn app.main:create_app --factory` in `server/` serves `http://localhost:8000`):

- **Build time:** set `fortune/scoreboard_url` in `game/project.godot` (section `[fortune]`) to the server root, for example `scoreboard_url="https://scoreboard.example.org"`.
- **Web, at run time:** open the game with `?scoreboard=` and the address, for example `https://example.github.io/fortune/?scoreboard=https://scoreboard.example.org`. It overrides the setting for that page load only (http and https only).
- **On the phone:** Menu > Scoreboard has a "Use scoreboard" switch, the address in use, and "Sync now", which sends anything still waiting. Writes queue in `user://queue.json` while the server is down and send when it is back; the game plays on regardless.

A browser blocks a plain `http://` scoreboard from an `https://` page, and the server must list the game's origin in `CORS_ORIGINS`.

## Finale integration run

`tools/dev/finale_integration.gd` plays the whole finale against a real scoreboard with three simulated phones, using the game's own `HttpTransport`, `FinaleClient`, `FinaleState` and `DialRules`. It is not part of CI. It runs all three machines through plain API calls, then checks handoff words and gating, the dials, four gnu-note codes, an early and a wrong start code, and the right one, against `GET /finale` and `GET /summary`. It exits 0 when every check passes.

```sh
cd server
DATABASE_PATH=/tmp/sb.db ADMIN_SECRET=test HANDOFF_SETTINGS_TOTAL=3 GNU_NOTES_K=4 START_CODE=3141592653 \
  GNU_NOTE_CODES=KETTLE27,GULLWING41,DRIPCOFFEE08,CROSSWIND63,INKBLOT19,SALTWATER52 \
  python3 -m uvicorn app.main:create_app --factory --port 8000 &
cd ..
$GODOT --headless --path game --import
$GODOT --headless --path game -s ../tools/dev/finale_integration.gd
```

Set `SCOREBOARD_URL` for another address. The run starts the line, so reset the server (`POST /api/v1/admin/reset` with `{"confirm":"reset","scope":"progress"}`) before running it again.

## Export the web build

```sh
mkdir -p game/build/web
$GODOT --headless --path game --import
$GODOT --headless --path game --export-release "Web" build/web/index.html
tools/dev/check-size.sh game/build/web
```

The export is single-threaded (no SharedArrayBuffer, no cross-origin isolation headers needed) and uses the Compatibility renderer (WebGL 2). To play it locally, serve `game/build/web` over HTTP, for example `python3 -m http.server -d game/build/web 8080` and open `http://localhost:8080/index.html` (add `?scoreboard=http://localhost:8000` for a local scoreboard, and start the server with `CORS_ORIGINS=http://localhost:8080`). A Godot web build does not run from a `file://` address.

### Size budget

CI fails if the exported build exceeds 12 MB **gzipped**, which is what a phone downloads from GitHub Pages. The uncompressed size is reported but not limited: Godot's engine `.wasm` alone is about 38 MB uncompressed (about 10 MB gzipped), so an uncompressed 12 MB limit could never pass. Both numbers appear in the job summary.

## CI and deploy

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

1. **test**: gdUnit4 tests via `godot-gdunit-labs/gdUnit4-action` (it installs Godot and the addon).
2. **build**: `chickensoft-games/setup-godot` with export templates, `--import` twice, export of the "Web" preset, then a size budget check. Each Godot log is grepped for `ERROR` and the job fails on a match. The web build is uploaded as the `web-build` artifact.
3. **deploy-vps** (push to `main` only, after test and build pass): publishes the build to the VPS over rsync and SSH, which serves the game, API and big screen from one origin; skipped with a notice unless the `VPS_*` secrets exist (see `docs/DEPLOY.md`).
4. **deploy** (push to `main` only, after test and build pass): publishes the build to GitHub Pages as a staging mirror with `actions/deploy-pages`. A `.nojekyll` file is added to the export. The deploy job asks `configure-pages` to enable Pages; if the repository setting refuses that, set Settings > Pages > Source to "GitHub Actions" once.

## Repository layout

| Path | What lives there |
| --- | --- |
| `game/` | The Godot project. `autoload/` singletons, `scripts/core/` plain classes, `scenes/` (`main`, `world`, `hud`, `ui`, `screens`, `puzzles`), `data/` (puzzle JSON and per-machine parts), `test/`. Start with [game/ARCHITECTURE.md](game/ARCHITECTURE.md) |
| `puzzles/` | Every clue as YAML; `tools/solver/export_json.py` turns it into `game/data/puzzles/*.json` |
| `tools/dev/` | Developer scripts: `get-godot.sh`, `get-gdunit4.sh`, `check-size.sh`, `finale_integration.gd` (see "Finale integration run") |
| `tools/solver/` | Python solver and clue generator |
| `server/` | Scoreboard service and big-screen page |
| `docs/` | Design review and other documents |
| `.github/workflows/` | CI, build and deploy |

## License

Code: GNU Affero General Public License, version 3 or later (`AGPL-3.0-or-later`). Art and audio in `game/art/`, `game/audio/` and `server/static/bigscreen/img/`: Creative Commons Attribution-ShareAlike 4.0 (`CC-BY-SA-4.0`, text in `LICENSES/CC-BY-SA-4.0.txt`, credits in `ASSETS.md`). Every source file carries an `SPDX-License-Identifier: AGPL-3.0-or-later` header. Because the AGPL covers network use, the game's about screen and the big-screen page must link to this source repository: https://github.com/johnsonfarmsus/fortune-teahouse-puzzle
