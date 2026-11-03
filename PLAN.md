# Build plan: The Fortune Teahouse

Plan date: 2 Nov 2026. Companion to `DESIGN.md` (the design) and `docs/DESIGN-REVIEW.md`
(the review). This plan replaces the "Cloud session plan" section of the design with a
dated, dependency-ordered set of work packages, each with a model assignment, inputs,
outputs and acceptance criteria.

## 0. How this will be run

- **Integrator:** one long-running cloud session on the largest model (the session that wrote
  this plan, or its successor) owns decisions, merges, cross-cutting review and anything that
  gets stuck. It writes no feature code itself.
- **Workers:** each work package below runs as its own cloud session or agent on the smallest
  model that can do the job (section 6 has the sizing rule). Workers open pull requests; they
  never push to `main`.
- **Merge rule:** CI green, plus a review by a Sonnet-class agent for ordinary code and an
  Opus-class agent for puzzle data, solver logic and the scoreboard API. The integrator merges.
- **Trevor's role:** answer the decisions in section 1, grant access (Hetzner, domain, GitHub
  settings), talk to organizers and the cookie vendor, and do the human read-through of the
  18 fortunes. Everything else is delegated.
- **Rule of thumb for scope:** anything not in `DESIGN.md` or this plan is a question for the
  integrator, not a worker's judgment call.

## 1. Decisions before the first build session

Defaults are given so work can start today. Reply to change any of them.

| ID | Decision | Default if no answer |
| --- | --- | --- |
| D0 | Engine: Godot 4.7.2 (as designed) or a TypeScript web stack (smaller, sandbox-testable, no iOS WebGL risk). See review section 5. | Godot 4.7.2-stable, single-threaded web export, Compatibility renderer |
| D1 | Unit of progress: every player solves each part on their own device; a crew's machine "runs" when each of its six parts has been solved by at least one crew member (scoreboard-synced). | Yes |
| D2 | Crew assignment: first lucky word sets crew, later words only collect clues, player can switch crews, no-cookie players choose. | Yes |
| D3 | All three core logic puzzles are 5-to-5 matchings (5 jars, 5 phrase banks to 5 lines, 5 heat zones to 5 temperatures). | Yes |
| D4 | Hint ladder: nudge, stronger nudge, reveal without credit; mentors can push one nudge. | Yes |
| D5 | Scoreboard stack: Python FastAPI plus SQLite in one Docker container, behind the existing reverse proxy on the Hetzner server. | Yes |
| D6 | Test framework: gdUnit4 (official GitHub action, headless by default). | Yes |
| D7 | Pi string: ten digits "3.141592653" as the finale start code (no sixth lucky number). | Yes |
| D8 | Deploy target for the game: the Hetzner VPS is the production origin (Caddy serves the game, `/api/` and `/bigscreen/` on one origin; CI deploys on merge to `main`). GitHub Pages stays as a staging mirror. | Yes |

## 2. Phases and dates

Revised 2 Nov 2026 for design revision 2 (the world, game feel, art and sound). Phases 0 to 2 are complete; section 9 defines Phase 3 in detail.

| Phase | When | Goal | Exit criterion |
| --- | --- | --- | --- |
| 0 Repo prep | Today, 2 Nov | Repo ready for parallel workers | `DESIGN.md`, `PLAN.md`, LICENSE, PR template, labels, issues for every WP |
| 1 Credit window | 2 Nov to 4 Nov 23:59 PST | All hard engineering merged: foundation, solver and 18 fortunes, game shell, Cookie Machine slice, puzzle components, Fortune Machine and Oven, scoreboard | Web build deploys from `main`; a phone can enter a lucky word, join a crew, solve the batter puzzle and appear on the contributors list; CI proves the 4-of-6 rule for all three machines |
| 2 Design completion | Nov to Jan | Finale mechanics, story content plan, 18 fortunes human-approved, art direction brief | Finale section of `DESIGN.md` has concrete mechanics; fortunes frozen (pending vendor limits) |
| 3 Hands-on rebuild (revision 2, section 9) | Nov to Apr | Rebuild the player-facing layer as a pixel-art adventure: walkable town, item chains with misdirects, shared inventory, animated machines, sound; one focused session at a time, each slice played by Trevor on a phone before the next | Every machine has its six chains; finale runs in the new layer; playtest 3 passes (a cold group of 8 to 12 finishes a machine in under 60 min with no help) |
| 3b Art and audio (local session on Trevor's Mac) | Nov onward, in parallel | Pixel art and sound per DESIGN.md "Art and sound", landing by filename against the asset list | Character references approved by Trevor; placeholders replaced room by room |
| 4 Logistics | May to Sep | Vendor terms confirmed, cookies ordered, organizer sign-off, venue notes (k of N) designed, ops runbook | Cookies in hand, allergen card printed, runbook rehearsed |
| 5 Event | Oct or Nov 2027 | Dress rehearsal, code freeze two weeks out, run the event, retrospective | Closing-session reveal runs on the big screen |

Phase 1 is the only phase with hard time pressure. Phases 2 to 5 run on the normal plan and
their dates are indicative; SeaGL 2027's date is not yet announced (expect a Friday and
Saturday in late October or early November).

### Phase 1 outcome

**Merged to `main`:** WP0 repo prep, WP1 foundation (Godot project, CI, scripts), WP2 solver, generator and the 18 fortunes, WP2b JSON exporter, WP2c item display names, WP3 game shell and the batter puzzle, WP4 reusable puzzle components and the remaining Cookie Machine parts, WP5 scoreboard service and big screen, WP5b credited flag on part solves, WP6 Fortune Machine and Oven (six parts each), WP7 game-to-scoreboard client. WP8 (this pass) adds the smoke-test checklist and documentation only; it changes no game or server code.

**Numbers (2 Nov, Godot 4.7.2):** 207 gdUnit4 test cases in 16 suites, 0 failures, no `ERROR` in the import, test or export logs. Web export: 38.21 MB uncompressed (`index.wasm` 39.5 MB of that), 9.87 MB gzipped against the 12 MB budget (`index.wasm` 10.08 MB gzipped; everything else under 0.5 MB).

**Not done:**

- Finale mechanics (DESIGN.md has no concrete mechanics yet) and the finale implementation (the scoreboard has the finale state and the line's handoffs; the game does not use them).
- Art (everything is coloured rectangles and labels), story content (the gnu's notes, the Anglerfish, character dialogue beyond the helper parts) and audio.
- Hetzner deploy of the scoreboard (it runs locally and in Docker only).
- Real-device testing: the checklist is in [docs/SMOKE-TEST.md](docs/SMOKE-TEST.md) and nobody has run it on an iPhone or Android phone yet.
- GitHub Pages enablement: the deploy job exists but the repository setting (Settings > Pages > Source: GitHub Actions) and the first deploy have not been confirmed.

**WP8 browser smoke test (headless Chromium, 390x844, touch, `http.server`):**

- The exported build loads and runs: the canvas is up in about 2 seconds on localhost, the start screen, town, Lucky word keypad (tapping keys), result line, Clues, Shop, machine view and the batter puzzle all rendered and responded to taps. The browser log has no errors and no page errors; the only warnings are Chromium's "GPU stall due to ReadPixels" (software WebGL, not the game).
- Against a local scoreboard (`?scoreboard=http://localhost:8000`, CORS for `http://localhost:8765`) the phone registered itself (`POST /api/v1/devices`, then `GET /api/v1/crews/cookie_machine` shows `members: 1`), and the big-screen page renders.
- Transfer without compression was 40 MB (`python3 -m http.server` does not gzip); on GitHub Pages it is about 10 MB. First-load time on venue Wi-Fi is not measured; the phone checklist asks for it.

### Known gaps for Phase 2

- Finale: design concrete mechanics in `DESIGN.md` and build them (gate on `finale.open`, three handoffs, the gnu's notes k of N).
- Real-device results: run docs/SMOKE-TEST.md on iPhone Safari and Android Chrome and fix what it finds (touch size, audio unlock, memory, rotating, private-tab storage).
- Load time: the 10 MB gzipped engine is the whole download; check it on venue-like Wi-Fi and consider a cached or lighter build if it is slow.
- Scoreboard deploy: Hetzner host, TLS, `CORS_ORIGINS`, admin secret, note codes, backups; point the Pages build at it with the `fortune/scoreboard_url` project setting.
- Pages: enable it, and confirm the build deployed from `main` loads at `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/`.
- Art, audio and story content; replace the rectangle placeholders (part fixtures, hotspots, avatar).
- Fortunes: human approval of the 18 fortunes, and vendor limits on cookie text.
- Accessibility pass: contrast, text size, screen reader behaviour of the canvas build.
- Layout nit: on the Lucky word screen the keypad shifts down about 3 px when the result line appears.

### Phase 2 outcome

**Merged to `main`:** WP9 finale design ([docs/FINALE-DESIGN.md](docs/FINALE-DESIGN.md)), WP10 and WP10b story content and its dialogue box and hooks, WP11 art direction brief ([docs/ART-BRIEF.md](docs/ART-BRIEF.md)), WP12a the finale in the game (handoff notes and words, the dials puzzle, Elephant's Archive, the start code, the README screen), WP12b the big-screen finale states and closing reveal, WP13 the scoreboard deployment kit ([docs/DEPLOY.md](docs/DEPLOY.md)) and WP14 the playtest protocol ([docs/PLAYTEST.md](docs/PLAYTEST.md)). WP15 (this pass) adds the end-to-end run, the finale section of the smoke test and these notes, and changes no game or server code.

**Numbers (2 Nov, Godot 4.7.2):** 357 gdUnit4 test cases in 24 suites, 0 failures, no `ERROR` in the import, test or export logs; 45 server pytest cases. Web export: 38.35 MB uncompressed, 9.97 MB gzipped against the 12 MB budget.

**Part A, finale against the real scoreboard (local server, headless Godot and Chromium at 390x844 with touch):**

- `tools/dev/finale_integration.gd` plays three phones through the game's real `HttpTransport`, `FinaleClient` and `FinaleState`: handoff notes and words, the dials solved from `handoffs.json`, four gnu-note codes (one repeated), an early start code (refused as not ready), a wrong one, then the right one. 69 checks pass. The server ends with every handoff at 3 of 3, notes 4 of 6, `line_ready` true and `started` true, and `/summary` agrees.
- In the web build against the same server, a phone joined the Cookie Machine crew with a lucky word, got its note and the "Maintainer" badge, saw "The line" open, was told it needed the Oven note, collected `GOLDENROUND`, set one dial, ran the test batch (the header read "Settings set by everyone: 1 of 3" and the server showed index 0 solved) and filed `KETTLE27` in the Archive ("1 of 6"). The browser console had no errors, only Chromium's software-WebGL "GPU stall" warnings.
- The big screen at 1920x1080 showed the S4 README and "The line is running!", and `?replay=1` played the reveal (start code, then the four machines lighting in turn).
- One layout nit: in the Shop, the gnu's "answering machine" marker (`game/scenes/world/shop.gd`, 250, 786) overlaps the left part of the "The line" button, so a tap there opens the voicemail instead. The right half of the button works.

**Not done:**

- Art, audio and story pieces still unwired (see ARCHITECTURE section 13); everything is still rectangles and labels.
- The Hetzner deploy of the scoreboard (the kit exists; nobody has run it on the real host), and GitHub Pages confirmation.
- A real-device finale test: the finale section of [docs/SMOKE-TEST.md](docs/SMOKE-TEST.md) has not been run on a phone, and no crowd has played the handoffs.
- Trevor's four finale questions ([docs/FINALE-DESIGN.md](docs/FINALE-DESIGN.md) section 10): the six physical notes at the venue, who runs the big screen and the admin secret on day two, whether 18:00 on day one is the right safety net, and whether the start code is entered whenever ready or on stage.
- The cookie order (Fortune Cookie Guy terms: different backs per pack, messages per pack, allergens, lead time).

## 3. Phase 1 schedule (credit window)

Times are Pacific. Each row is one worker session. Sessions in the same block run in parallel.

| Block | When | Work packages | Notes |
| --- | --- | --- | --- |
| A | Sun 2 Nov, evening | WP0 repo prep (integrator), then WP1 foundation | WP1 must merge before anything else starts |
| B | Mon 3 Nov, morning | WP2 solver and fortunes, WP3 game shell, WP5 scoreboard | Independent given WP1's schema and seed data |
| C | Mon 3 Nov, afternoon | WP4 puzzle components (starts when WP3 merges) | Reads WP3's shell; writes only new scenes |
| D | Tue 4 Nov, morning | WP6 Fortune Machine and Oven (needs WP2 data and WP4 components), WP7 game-to-scoreboard client (needs WP3 and WP5) | |
| E | Tue 4 Nov, afternoon | WP8 integration pass, real-device smoke test, buffer | Stop new work by 20:00 to leave time for merges |

If a block slips by more than half a day, drop WP6 to the Oven only (the Fortune Machine
is the most content-heavy) and finish it in Phase 3.

## 4. Work packages

Every package: branch `wp<N>/<short-name>`, one PR, `DESIGN.md` and this file as the first two
reads, AGPL SPDX header on every new source file, and tests for anything with logic.

### WP0 Repo prep (integrator, Haiku for the mechanical edits)

- Inputs: this plan, the review.
- Outputs: `DESIGN.md` (renamed, done), apply the section 6 corrections from the review to
  `DESIGN.md`, `LICENSE` (AGPL-3.0-or-later full text), `.github/pull_request_template.md`
  with the clue-meaning checkbox, `.github/ISSUE_TEMPLATE/`, one issue per WP with its
  acceptance criteria, labels `wp`, `puzzle-data`, `needs-trevor`.
- Acceptance: issues exist; `DESIGN.md` has no known factual errors.

### WP1 Foundation (Sonnet)

- Inputs: `DESIGN.md` "Technology and pipeline"; decisions D0, D6, D8.
- Outputs: folder layout (`game/`, `puzzles/`, `tools/solver/`, `server/`,
  `.github/workflows/`); minimal Godot 4.7.2 project with one placeholder scene,
  `project.godot` set to `gl_compatibility` with mobile override, committed
  `export_presets.cfg` with a "Web" preset, thread support off; `puzzles/schema.json` plus
  `puzzles/cookie_machine.yaml` seeded with the six sample clues from `DESIGN.md` (fact
  encoded as `{kind: position|offset, a, b, value}`); CI workflow: setup-godot 4.7.2 with
  templates, import twice, grep log for `ERROR`, gdUnit4 action, web export, size budget
  check (fail above 12 MB), upload and deploy to Pages on `main`; `README.md` describing how
  to run it all; `tools/dev/get-godot.sh` that downloads the headless binary into a sandbox.
- Acceptance: CI green on the PR; after merge the Pages URL shows the placeholder scene.
- Risk to check first: can the sandbox download Godot from GitHub releases? If not, the
  worker writes everything and relies on CI, and says so in the PR.

### WP2 Solver, generator and the 18 fortunes (Opus for design and the fortune text, Sonnet for implementation and CI)

- Inputs: "The fortune cookies" section; decisions D3, D7; the review's fragility note.
- Outputs: `tools/solver/` Python package with a generic 5-to-5 matching solver; a generator
  that produces six clue facts per machine (two anchors plus a four-link chain, shuffled
  answer) satisfying: every 4 of 6 unique, no 3 unique, approachable four unique, and a
  report of which 4-subsets break under the "either order" misreading; 18 fortunes in
  `puzzles/*.yaml` with styled text, lucky word, style, fact, and front length; a configurable
  character limit (140 default, confirmed by the vendor Fortune Cookie Guy; a 99 profile is
  kept as a stricter option); both back messages; CI job `puzzle-checks` covering the 4-of-6 rule per
  machine, approachable-four rule, length limits, unique lucky words across all 18, and a
  JSON report artifact. Answers must not appear in CI logs.
- Acceptance: `puzzle-checks` green; a human (Trevor) later confirms each styled text
  entails its fact, tracked in the PR template checkbox. Opus writes the fortunes; Sonnet
  wires the checks.

### WP3 Game shell and the batter puzzle (Opus for the architecture note and scene plan, Sonnet to build)

- Inputs: "How it plays at SeaGL", "The three machines"; decisions D1, D2, D4.
- Outputs: phone-first shell in `game/`: tap-to-start screen (audio unlock), tap-to-move town
  with three places (shop, pier, teahouse), lucky-word entry reading `puzzles/`, crew
  assignment per D2, clue board, a generic 5-to-5 matching puzzle scene driven by data, the
  patch-and-merge flow with Crab adding a display name (anonymous allowed) to a local
  contributors list, a progress model with a `ProgressStore` interface (local
  implementation now; WP7 adds the remote one), hint ladder per D4. Placeholder art. gdUnit4
  tests for clue collection, crew assignment, matching-puzzle validation and the progress
  model.
- Acceptance: on the Pages build, entering the six sample lucky words collects six clues;
  solving the batter puzzle with any four shows the merge animation and the name on the list.
- Constraint: the worker writes a short `game/ARCHITECTURE.md` first (scene tree, autoloads,
  data flow), which the integrator approves before scenes are built. This is the main
  defence against unreadable `.tscn` sprawl.

### WP4 Reusable puzzle components (Sonnet)

- Inputs: WP3's architecture note; the puzzle-type table in "The three machines".
- Outputs: data-driven scenes for wiring (connect labelled terminals, colour plus text),
  sequence (drag to order steps), word/poem (fill the blanks or unscramble), and pattern/
  rhythm (visual-first beat matching, optional sound and haptics); each with a `PuzzleBase`
  contract (load config, emit solved, support hint ladder) and tests; the five remaining
  Cookie Machine puzzles instantiated from them.
- Acceptance: Cookie Machine shows six parts; fixing each visibly changes the shop (a light,
  a gear, placeholder is fine); tests cover each component's validation.

### WP5 Scoreboard and big screen (Sonnet)

- Inputs: "The finale", "Technology and pipeline"; decisions D1, D5.
- Outputs: `server/` FastAPI plus SQLite, Dockerfile and compose file; API: register device,
  join crew, report part solved, crew progress, contributors, generic finale state (handoffs
  with a settings count and solved count, Gnu's notes found of N, configurable k, start code
  check), mentor hint push; safety-net unlock at a configurable time; big-screen page
  polling the API; AGPL source link in the page footer; tests with pytest; a GitHub Actions
  job building the image. No deploy yet (Hetzner access is Trevor's).
- Acceptance: `docker compose up` locally shows the big screen reacting to curl calls.

### WP6 Fortune Machine and Oven (Sonnet, Opus review of puzzle wiring)

- Inputs: WP2 data, WP4 components.
- Outputs: both machines with one puzzle per type from the table, core logic puzzles reading
  their clues from `puzzles/`, world changes on each fix, the Seagull and Gopher helpers as
  placeholder dialogue, tests.
- Acceptance: all three machines solvable on the Pages build using the 18 lucky words.

### WP7 Game-to-scoreboard client (Sonnet)

- Inputs: WP3's `ProgressStore` interface, WP5's API.
- Outputs: remote `ProgressStore` behind a setting with a configurable base URL, queued
  writes when offline, crew progress view, maintainer status and mentor hints when a crew's
  machine runs, contributors list from the server.
- Acceptance: with the server down the game plays unchanged; with it up, two browsers in the
  same crew see each other's parts.

### WP8 Integration pass (integrator plus one Sonnet worker)

- Outputs: merged `main`, Pages build smoke-tested on an iPhone (Safari) and an Android
  (Chrome) by Trevor or a volunteer with a short checklist, bug list for Phase 3, credit
  spend report, updated `README.md`.

### Phase 2 to 5 packages (not scheduled in detail yet)

- WP9 Finale mechanics design (Opus draft, integrator review, Trevor approval).
- WP10 Story and dialogue content (Opus for voice, Haiku for formatting into data files).
- WP11 Art direction brief and original character designs (human artist or image tooling;
  out of scope for agents beyond the brief).
- WP12 Finale implementation in game and server (Sonnet).
- WP13 Scoreboard deploy to Hetzner with TLS and backups (Sonnet, Trevor grants access).
- WP14 Playtest protocol and three playtests (Haiku writes the protocol; humans play).
- WP15 Cookie order: confirm the remaining Fortune Cookie Guy terms (different backs per
  pack, messages per pack, allergens, lead time), allergen card, order (Trevor with Haiku
  support).
- WP16 Venue notes (k of N), organizer approvals, event runbook (Sonnet drafts).
- WP17 Dress rehearsal, freeze, event, retrospective.

## 5. Technology specifics the workers must follow

- Godot `4.7.2-stable` pinned in the setup action, export templates and the gdUnit4 action.
- Export preset "Web" with thread support off; no COOP/COEP service-worker shim.
- `rendering/renderer/rendering_method = "gl_compatibility"` and the `.mobile` override.
- CI: import twice, grep the import and export logs for `ERROR`, fail on match.
- Size budget: fail CI if the exported `web/` directory exceeds 12 MB uncompressed; report
  the gzip size in the job summary.
- Tap-to-start screen before any audio; all rhythm puzzles visual-first.
- Every puzzle scene is data-driven from `puzzles/` or a scene-local resource; no answers
  hard-coded in scripts.
- SPDX header `# SPDX-License-Identifier: AGPL-3.0-or-later` on every `.gd`, `.py`, `.js`,
  `.yml`; the game's about screen and the big-screen footer link to the repo.
- Colour is never the only carrier of information; tap targets at least 44 px; no timers.
- Game feel (DESIGN.md) applies to every player-facing pull request from Phase 3 on: direct
  manipulation, feedback within a tenth of a second, a walking character, scenes not screens,
  machines that animate part by part, sound on every interaction, 60 frames per second target
  on a mid-range Android and a recent iPhone. Every gameplay PR carries screenshots or a short
  capture, and Trevor plays each slice on a phone before the next slice starts.
- Art is loaded by filename from an asset list with a placeholder fallback, so code never waits
  for art. `ASSETS.md` records source, licence and author for every asset.
- Accessibility becomes an option (text-assist mode) rather than the default from Phase 3; the
  44 px and colour-plus-text rules still apply to the default UI where they cost nothing.
- If D0 switches to a web stack, WP1 becomes: Vite plus TypeScript plus PixiJS, Vitest,
  Playwright smoke test against the built site, same `puzzles/` schema, same Pages deploy.
  WP3 to WP7 keep their scope; only the implementation language changes.

## 6. Model sizing rule

| Model class | Use for | Examples in this plan |
| --- | --- | --- |
| Haiku | Mechanical edits, boilerplate, formatting, scripts under 50 lines, issue and label creation, checklists | WP0 edits, SPDX headers, playtest protocol, formatting content into YAML |
| Sonnet | Well-specified implementation with tests, CI workflows, services, Godot scenes from an approved architecture, code review of ordinary PRs | WP1, WP4, WP5, WP6, WP7, implementation half of WP2 and WP3 |
| Opus | Design under constraints, creative writing that must satisfy a checker, architecture notes, review of puzzle data and APIs | Generator design and the 18 fortunes (WP2), architecture note (WP3), finale design (WP9), story voice (WP10) |
| Largest available | Integration, decisions, cross-cutting review, anything an Opus attempt failed once | Integrator session only |

Escalate one step only after a concrete failure (a failing check, a wrong answer, a stuck
worker), never pre-emptively.

## 7. Risks and mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Godot web build unstable on iPhone Safari | Medium | Real-device test at end of Phase 1; D0 fallback to web stack decided by Dec if it fails |
| 100 phones loading several MB at once on venue Wi-Fi | Medium | Size budget, packed assets, loading screen, announce the URL before TeaGL, QR codes on tables |
| Sandbox cannot run Godot, so workers iterate only through CI | Medium | `get-godot.sh` in WP1; CI kept under 10 minutes; unit-testable logic kept in plain GDScript classes |
| Session 3-sized packages overrun the credit | High if not split | Already split into WP3 and WP4; WP6 can drop to the Oven only |
| Vendor terms change (two-sided printing, different backs per pack, messages per pack) | Low | Vendor is Fortune Cookie Guy and 140 characters is confirmed; generator keeps a limit parameter anyway; confirm the remaining terms in writing before the order |
| Parallel workers touch the same `game/` files | Medium | WP3 owns the shell; WP4 and WP6 create new scenes only and extend via the `PuzzleBase` contract; integrator rebases |
| Headless Godot exits 0 on failure | High | Log grep in CI |
| Fortune text does not mean its fact | Medium | PR checklist, human read-through, optional LLM entailment comment |
| Organizers decline hidden codes or big screen | Low to medium | Finale works with k of N where N can be the game's own in-app notes; big screen is optional |
| TeaGL is 30 to 40 minutes | Certain | Design treats TeaGL as kickoff; machines are fixed over the rest of day one |

## 8. Questions for Trevor (consolidated)

Blocking Phase 1 only if you want a non-default answer: D0 to D8 above.

Not blocking Phase 1:

1. Vendor is Fortune Cookie Guy, 140 characters confirmed. Still needed in writing: message
   count per pack, two-sided cost, different backs per pack, allergens, lead time.
2. Hetzner server access and the domain for the scoreboard and, later, the game.
3. Organizer contact and whether to approach them now or after a playable build exists.
4. Whether a human artist is planned for the original character designs.
5. Who the playtest groups will be (a local user group would be ideal).

## 9. Revision 2: the hands-on rebuild (2 Nov 2026)

### 9.1 What changed in the design

DESIGN.md gained three sections and two live session prompts. The game lives in a town of nine
places, not the shop: each machine part is reached through a chain of parts, tools and knowledge
found around town, with dead ends and misdirects that cost time but never progress, and one or
two decoy answers per machine that lead to a real place which explains the mistake. Crews share
an inventory through the scoreboard. Game feel is now a requirement on every pull request:
direct manipulation, a walking character, scenes not screens, animated machines, physics where
it is fun, portraits, sound everywhere, 60 frames per second. The look is NES-style top-down
pixel art on a 16 by 16 grid with one strict palette, built from CC0 Ninja Adventure and Kenney
tiles plus assets generated on Trevor's local machine and pixelized by one script. The design
also says how to build it: one focused session rebuilds the player-facing layer as a vertical
slice, and Trevor plays it on a phone before anything else is built on it.

### 9.2 What this means for what exists

| Keep as is | Rebuild on top of it | Rework later |
| --- | --- | --- |
| Solver, 18 fortunes, puzzle data and exporter, CI puzzle checks | Town: nine walkable pixel-art rooms with flip-screen transitions and a walking player | Finale dials become hands-on controls on the animated line, and the closing reveal becomes the line simulation |
| Scoreboard service, API, deploy kit, big screen | Puzzles: direct manipulation inside the room where the chain says they happen, replacing button lists | Hint ladder stays, re-skinned as Red Panda's help |
| Game state, progress store, scoreboard client, finale client and data | Chains: parts, tools and knowledge as an inventory; misdirects and decoys as data | Big-screen page unchanged |
| Story data and the Story catalog | Characters as sprites with idle and walk frames and portrait dialogue | |
| gdUnit4 tests for logic; CI and Pages deploy | Machines as animated contraptions that start moving part by part | |

The current screens stay reachable behind a debug setting until each slice replaces them, as the
design's rebuild prompt says.

### 9.3 How the work runs from here

Superseded on 3 Nov 2026 by section 10.3: the integrator moves to a local session on Trevor's Mac.

- **One player-facing session at a time.** The rebuild slice is one focused session on an
  Opus-class model, with an integrator review and then Trevor's phone test as the gate. Fleets
  of parallel Sonnet workers continue only for data, server, docs and tests.
- **Art and audio come from Trevor's Mac,** on the normal plan, through pull requests reviewed
  here. Cloud sessions never generate art; they load it by filename and ship placeholders.
- **Gate at every slice:** CI green, review, screenshots in the PR, Trevor plays it on a phone,
  then the next package starts. Nothing is built on an unplayed slice.

### 9.4 Decisions for the rebuild (defaults apply unless Trevor says otherwise)

| ID | Decision | Default |
| --- | --- | --- |
| D9 | Pixel viewport | 176 by 320 base (11 by 20 tiles of 16 px), integer-scaled with no smoothing, letterboxed on odd phones; inventory and dialogue use the bars above and below |
| D10 | Shared inventory | New scoreboard endpoints for crew inventory (item found, found-by, installed), queued offline like solves; everything findable alone without the scoreboard |
| D11 | Asset list | `game/assets.json` maps logical names to files, frames and sizes; a missing file shows a labelled placeholder; CI checks that every referenced file exists or is declared as a placeholder |
| D12 | Sound in cloud sessions | Effects generated by a committed script into small WAV files with their settings in data; ambient loops and music come from the local art session |
| D13 | Chains as data | `game/data/chains/<machine>.json`: steps (find, decode, repair, install), places, items, tools, misdirects with tells, decoys with their named mistake and destination; CI checks every decoy follows from its mistake and matches no valid 4-clue set |
| D14 | Accessibility | Text-assist mode (list of interactive objects, button alternatives) is a Phase 3 package, off by default |

### 9.5 Phase 3 work packages

Model sizing follows section 6: Opus for the slice and the chain design, Sonnet for data,
server and tests, Haiku for mechanical edits.

- **WP16 Rebuild slice: the town and one full chain (Opus, one session).** The design's
  "Rebuild" prompt verbatim: six connected rooms (teahouse, shop, pier, workshop, depot,
  scrapyard), walking character and camera, characters with idle animation and portraits,
  drag-to-use shared inventory through the scoreboard client, the Cookie Machine as an animated
  contraption, the cutter-die chain with its scrapyard and Anglerfish misdirects and the
  outdated-locker-code decoy to the harbour, the batter-jar puzzle rebuilt as dragging jars onto a
  shelf, Ninja Adventure tiles, art by filename with placeholders, a sound on every interaction,
  old screens behind a debug setting, tests for the chain logic, screenshots in the PR.
  Acceptance: Trevor plays it on a phone and approves; 60 fps on his iPhone.
- **WP5c Crew inventory API (Sonnet, parallel with WP16).** Endpoints per D10, idempotent,
  tests, API.md, deploy kit env unchanged.
- **WP17 Chain design for all 18 parts (Opus, after WP16 approval).** `docs/CHAINS.md` and the
  chain data per D13: six chains per machine with places, items, tools, misdirects with tells
  and one or two decoys per machine; the twelve existing puzzle configs mapped to the room where
  each now happens; the fortune clues' second job (where to look, which part is real, lock
  codes). Reviewed by the integrator for the "fair in hindsight" and "still approachable" rules.
- **WP18 Decoy and asset checks in CI (Sonnet).** The decoy check in the solver and the asset
  list check per D11 and D13.
- **WP19 Cookie Machine, remaining five chains (Opus or Sonnet per slice, one at a time).**
- **WP20 Fortune Machine chains and rooms (archive, cottage, harbour) (one at a time).**
- **WP21 Oven chains (one at a time).**
- **WP22 Finale in the new layer (Opus design pass, Sonnet build).** Hands-on handoff controls
  on the animated line, the line simulation for the reveal, Archive as Elephant's room.
- **WP23 Text-assist mode (Sonnet).**
- **WP24 Performance and polish pass (Sonnet, repeated).** Frame budget on a mid-range Android
  and an iPhone, download size, audio latency, physics counts.
- **WP14 rounds 1 to 3** interleave: round 1 after WP19, round 2 after WP21, round 3 after WP22.
- **Art landing (local session, continuous):** character references first, then tiles for the
  slice, then room by room, each as its own PR reviewed here against `ASSETS.md`.

### 9.6 Risks added by revision 2

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Scope: nine rooms, eighteen chains, animation, sound and physics is several times the Phase 1 scope | High | One slice at a time with a phone gate; chains as data so content scales without code; cut rooms before cutting chains |
| 60 fps on web Godot with physics and shaders on mid-range phones | Medium | Pixel viewport keeps fill rate tiny; few physics bodies; profile on a real Android after the slice; palette-swap shader optional |
| Shared inventory races and double-finds | Medium | Server is the source of truth with idempotent item ids; found-by is first writer |
| Decoys frustrate newcomers | Medium | Design rules (fair in hindsight, approachable, hint ladder within two minutes) enforced in WP17 review and playtest round 1 |
| Art and code drift (sizes, frame counts) | Medium | Asset list is the contract; CI checks existence; placeholders labelled with the expected size |
| Licensing of generated assets and audio | Low | Pinned Apache 2.0 image models, Stable Audio 3 community licence recorded in `ASSETS.md`; no research-only model upgrades |
| Single-session cadence slows throughput | Certain | Run data, server, docs and art work in parallel with each slice; only player-facing code is serialised |

### 9.7 Immediate next steps

1. Merge this revision (DESIGN.md and PLAN.md).
2. Start WP16, the rebuild slice, as one Opus session, and WP5c in parallel.
3. Trevor starts the local art and audio session on his Mac with the steam-machine brief.
4. After WP16 lands: review, screenshots, Trevor's phone test, then WP17.

## 10. Revision 3: local integrator, media and hosting (3 Nov 2026)

### 10.1 What changed

Trevor supplied a private handoff (git-ignored; never committed) covering the steam-machine's
media API and the Hetzner VPS. Its consequences, without the private details:

- **The steam-machine is reachable only from Trevor's network,** and the VPS key lives on his
  Mac. No cloud session can generate media or set up hosting.
- **Media goes through one JSON API** on the steam-machine: images (`fast` Z-Image-Turbo, `best`
  Qwen-Image), instruction edits (Qwen-Image-Edit), music (ACE-Step), speech, video. There is no
  sound-effect mode. Never call ComfyUI directly, never change the box, one render at a time.
- **Its images are large, softly shaded rasters,** so everything goes through `pixelize.py`
  into the 25-colour palette in `game/assets.json`. The handoff's size targets came from the old
  flat-sticker brief and are superseded by revision 2's 16 by 16 pixel art.
- **Ports 80 and 443 on the VPS belong to a reverse proxy that already serves another site.**
  The kit's own Caddy must not start there; the game is added as a site on the existing proxy.

### 10.2 Decisions

| ID | Decision |
| --- | --- |
| D15 | **Domain:** `fortune.johnsonfarms.us`, one origin for the game, the API and the big screen. A DNS-only A record to the VPS so the proxy gets its own certificate. Check first that no wildcard or proxy rule on `johnsonfarms.us` already claims `fortune`. The cookie backs now carry this address (88 characters each). |
| D16 | **Only approved, final art and audio are committed.** Raw renders, drafts and rejected variants stay on the steam-machine. `ASSETS.md` records source, licence, author, and for generated assets the model, prompt and seed. |
| D17 | **Audio:** no voice acting. Sound effects on every interaction from the runtime synth, CC0 packs to fill gaps, rendered batches only on request. Music: a loop per place plus a finale track, from ACE-Step through the media API; FamiStudio optional. Separate music and effects toggles in Settings, muted until tap-to-start. |
| D18 | **Backups:** GitHub covers code and the VPS's regular backups cover the server. The kit's nightly consistent SQLite copy stays on the box so those backups capture a clean file; hourly during the event. No off-box rsync target (`BACKUP_RSYNC_TARGET` stays unset). |
| D19 | **Licences:** code AGPL-3.0-or-later; art and audio CC-BY-SA 4.0 (`LICENSES/CC-BY-SA-4.0.txt`). |
| D20 | **Hosting behind the existing proxy:** run only the scoreboard container on loopback; add a site block for D15 to the existing proxy (static game from `/srv/fortune/current` with the kit's headers and pre-compressed files, `/api/*` and `/bigscreen*` to the scoreboard) plus a read-only `/srv/fortune` mount and a host-gateway entry on the proxy's container. Back up the proxy config first; check the other site answers before and after. No `apt upgrade`, reboot or firewall change. Deploy user `fortune`. |
| D21 | **Model versions:** before any generated art ships, confirm `best` and `edit` run Qwen-Image-2512 and Qwen-Image-Edit-2511, not 2.1 or later. |
| D22 | **Local integrator from 4 Nov 2026:** the Mac session drives, reviews and merges. Cloud sessions run only for parallel batches with no player-facing code. The phone-test gate per slice is unchanged. |

### 10.3 How the work runs from here

- **One local session on Trevor's Mac is the integrator.** It reads this plan, `DESIGN.md`,
  `game/ARCHITECTURE.md`, `docs/DESIGN-REVIEW.md` and the git-ignored handoff file.
- **Player-facing slices stay one at a time,** each gated by Trevor's phone test.
- **Media and hosting work are local by necessity.** Cloud batches are launched from the local
  session when parallel, non-player-facing work is worth it.
- **Model sizing (section 6) still applies** to subagents the local session starts.

### 10.4 Work packages added

- **WP25 Local tooling (first).** `tools/dev/get-godot.sh` and `get-gdunit4.sh` gain a macOS path
  for Godot 4.7.2; the full suite and the web export run on the Mac; README updated.
- **WP26 Hosting behind the existing proxy (local, with Trevor).** Rewrite `docs/DEPLOY.md`'s
  "If 80/443 are taken" section into the full D20 path with a ready site block and the two
  container additions; rename the deploy user to `fortune` throughout; then, with Trevor: DNS
  record, deploy user and forced-command shell, the four GitHub secrets, `.env`, first deploy.
  Verify Brotli with `curl -I --compressed`, `config.json` with the game, and the other site.
- **WP27 Art pipeline (local).** Rewrite `docs/ART-BRIEF.md` for NES pixel art with the asset
  list the game loads by filename; `tools/art/pixelize.py`; `ASSETS.md`; download the Ninja
  Adventure and Kenney packs on the Mac; D21 check; the eight character references, then stop
  for Trevor's review; then the slice's tiles room by room.
- **WP28 Music and sound (local).** A loop per place and a finale track through the media API;
  effects polish over the runtime synth; Settings toggles; an audio size budget in CI.

The cookie backs were moved to the new domain in this revision, so no package is needed for that.

### 10.5 Order from here

1. Trevor plays the rebuild slice on a phone (the WP16 gate, issue #39).
2. WP25, then WP26 with Trevor.
3. WP27 in parallel with fixes from the phone test; character references go to Trevor for review.
4. After the slice verdict: WP17 chain design, then the remaining chains one slice at a time,
   with WP28 alongside.

### 10.6 Risks added by revision 3

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| A config mistake takes down the other site on the shared VPS | Medium | Back up proxy config and compose file first; validate before reload; check the other site before and after; no upgrades, reboots or firewall changes |
| A model update on the steam-machine changes licence terms | Low | D21 check before shipping; record the model per asset in `ASSETS.md` |
| Music pushes the download past the budget | Medium | Short compressed loops; audio counted in the CI size budget (WP28) |
| `fortune.johnsonfarms.us` collides with an existing rule on the family domain | Low | Check DNS and any wildcard or proxy rule before adding the record |
| Private details leak into the public repo | Low | Handoff file git-ignored; a repo-wide check for private addresses before each art or hosting PR |

