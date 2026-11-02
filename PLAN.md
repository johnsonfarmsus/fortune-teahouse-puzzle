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
| D8 | Deploy target for the game: GitHub Pages at the repo's default URL now; custom domain later. | Yes |

## 2. Phases and dates

| Phase | When | Goal | Exit criterion |
| --- | --- | --- | --- |
| 0 Repo prep | Today, 2 Nov | Repo ready for parallel workers | `DESIGN.md`, `PLAN.md`, LICENSE, PR template, labels, issues for every WP |
| 1 Credit window | 2 Nov to 4 Nov 23:59 PST | All hard engineering merged: foundation, solver and 18 fortunes, game shell, Cookie Machine slice, puzzle components, Fortune Machine and Oven, scoreboard | Web build deploys from `main`; a phone can enter a lucky word, join a crew, solve the batter puzzle and appear on the contributors list; CI proves the 4-of-6 rule for all three machines |
| 2 Design completion | Nov to Jan | Finale mechanics, story content plan, 18 fortunes human-approved, art direction brief | Finale section of `DESIGN.md` has concrete mechanics; fortunes frozen (pending vendor limits) |
| 3 Content and polish | Feb to Jun | Original character art, town art, writing (Gnu's notes, Anglerfish), finale implemented, scoreboard deployed to Hetzner, three playtests | Playtest 3: a cold group of 8 to 12 finishes a machine in under 60 min with no help |
| 4 Logistics | Jul to Sep | Vendor terms confirmed, cookies ordered, organizer sign-off, venue notes (k of N) designed, ops runbook | Cookies in hand, allergen card printed, runbook rehearsed |
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
