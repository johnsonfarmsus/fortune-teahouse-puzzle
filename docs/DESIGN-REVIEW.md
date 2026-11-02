# Design review: The Fortune Teahouse

Reviewed 2 Nov 2026 against `DESIGN.md` (the "Nov 1, 2026" draft).

**Verdict.** The design is coherent and buildable. The story, the three-machine line, the
six-style clue scheme and the AGPL-through-GitHub pipeline all hang together, and the one
hard mathematical claim in the document (the batter puzzle's any-4-of-6 property) checks out
by brute force. The things that need fixing before building are: one factual error (the pi
digits), one timing assumption that is wrong (TeaGL is 30 to 40 minutes, not 50), several
game-mechanics decisions the document leaves open that the code cannot leave open (who
"solves" a machine, how crews are assigned, how big each logic puzzle is), and a set of
technical risks around running a Godot web export on conference phones that the plan should
mitigate explicitly.

Severity key: **Blocker** = must decide or fix before the build sessions start.
**Should fix** = fix in the next doc revision. **Note** = worth knowing.

## 1. What was verified

### 1.1 The batter puzzle (verified by solver, all claims hold)

A brute-force script over all 120 jar permutations confirms every claim in "The fortune
cookies":

| Claim | Result |
| --- | --- |
| Every 4 of the 6 clues gives exactly one answer | True for all 15 subsets |
| No 3 clues are enough | True: all 20 subsets leave exactly 2 answers |
| The four approachable styles alone reach the threshold | True (that subset is unique) |
| Structure is two anchors plus a four-link chain | True: sugar=1 and egg=5 anchor; flour=sugar+1, vanilla=flour+1, butter=vanilla+1, butter=egg-1 chain |

The unique solution is jars 1 to 5 = sugar, flour, vanilla, butter, egg, as the document
admits ("the real puzzle will use a shuffled answer").

**Fragility worth knowing.** Every chain clue is directional ("to the right", "just before",
"on the left"). If a player reads any one of them as plain adjacency, exactly one 4-subset
becomes ambiguous. The worst case is the poem: read as "vanilla and butter are neighbours"
it breaks the all-approachable subset. Keep an explicit direction word in every chain clue,
and have the generator's CI check also test the "either order" misreading and report which
subsets it would break, so the writer knows which clues carry the most weight.

### 1.2 Character counts

All six sample fronts and both backs match the document's counts, with one caveat: the code
clue is 71 characters without its backticks and 73 with. Decide whether backticks print.
Everything is far under 140 (longest front is 115).

### 1.3 Arithmetic

Pack and crew arithmetic is consistent: 18 fortunes, 5 or 6 copies of each per pack, about
33 cookies per crew, 30 per crew after holding 10 back. Holding back 10 cookies is safe only
if done randomly: taking back two full fortunes (about 10 cookies) would leave a machine at
exactly its 4-clue threshold. Hold back a random handful, not stacks of one fortune.

### 1.4 The pi digits (Should fix)

Pack A "3 1 4 1 5" plus Pack B "9 2 6 5 3" is 3141592653, the first ten digits of pi. The
document writes it as "3.14159 26535", which is eleven digits with an extra trailing 5.
Either correct the text to 3.141592653 or add a sixth lucky number (5) to Pack B. The
finale's "start code" must then use whichever string is chosen.

### 1.5 Each pack holds half of every machine's clues (Note, becomes an ops rule)

Each pack carries 3 fortunes per machine. A crew whose cookies all came from one pack can
never collect more than 3 of its 6 clues and can never finish. "Mix both packs together" is
therefore a hard requirement, not a nicety. Put it in the event-day runbook as a checklist
item.

## 2. Event facts the document gets wrong or leaves open

Research summary (web search only; seagl.org itself was not fetchable from this sandbox,
so confirm with organizers):

- **TeaGL is 30 to 40 minutes, not 50.** Past TeaGL slots were 40 min (2018) and 30 min
  (2019 to 2021). In 2026 it ran at 3:30pm on both days in the Expo Hall. The document's
  "about 50 minutes" and "most crews get their machine running in 40 to 60 minutes" do not
  fit inside TeaGL. **Should fix:** treat TeaGL as the kickoff where cookies are handed out
  and crews form, and expect machines to be fixed over the rest of the day. The design
  already tolerates this ("rest of day one: remaining crews finish").
- **TeaGL happens both days.** The open question "which day is TeaGL" probably has the answer
  "both"; pick the Friday one so the finale has all of Saturday.
- **SeaGL 2026 was 23 to 24 Oct 2026 at the UW HUB; 2027 is not announced.** The usual pattern
  is a Friday and Saturday in late October or early November, hybrid with an online track.
  The game date is roughly a year out, which makes the two-day credit window the only real
  schedule pressure.
- **Attendance:** sponsor prospectuses say 400+ over two days, in-person and online combined.
  100 cookies is a reasonable fraction of in-person attendees; the online track should get a
  "no cookie" path (the design already has one) and the lucky words should not be printed
  only on cookies if remote players are meant to join crews.
- **Vendor terms.** Update 2 Nov: Trevor confirmed the vendor is Fortune Cookie Guy
  (fortunecookieguy.com) and the product page shows a 140-character limit; the sandbox could
  not fetch the page. The research below predates that and stands only for the remaining
  terms. None of the custom fortune cookie vendors found (Fancy
  Fortune Cookies, Golden Gate Fortune Cookie Factory, Wonton Food) matches the document's
  terms (9 messages per 50-pack, 140 characters, $69 per pack, $30 per back message). The
  numbers may come from a quote not found online. **Blocker for the cookie order only:** get
  the vendor's written terms, including whether two packs may carry different back messages,
  the real character limit, and an allergen sheet (wheat and egg are certain; sesame and soy
  are likely). Fancy Fortune Cookies is the closest match (50 minimum, double-sided printing,
  ships in 3 to 7 business days) and its stated limit is 3 lines of about 32 characters,
  which is 96 to 99 characters, not 140. The sample fronts above would need trimming if that
  is the real limit; write the generator with the limit as a parameter.
- **Policies:** SeaGL has a code of conduct and a health and safety policy; no public policy
  on food handouts, hidden codes or shared screens was found. Organizer approval is the
  right path and is already on the open-questions list.

## 3. Game-mechanics gaps the code cannot leave open (Blockers)

These are decisions. Recommended answers are given so the build can proceed; change them if
you disagree.

1. **Unit of progress.** Is a machine fixed per device or per crew? If only the first solver
   counts, thirty people watch one phone. **Recommend:** every player solves every part on
   their own device (so everyone plays), and the crew's machine "runs" when each of its six
   parts has been solved by at least one crew member, as recorded by the scoreboard. Offline,
   the device's own progress is shown and synced later.
2. **Crew assignment.** Pooling clues means typing crewmates' lucky words, so a player will
   enter words from other machines too. **Recommend:** the first lucky word sets the crew;
   later words only collect clues; a menu lets a player switch crews; no-cookie players pick
   a crew.
3. **Lucky words will leak** (said aloud, shown on screens, visible in the public repo).
   Accept it and say so: the only real gate is finding people. Do not build anti-cheat.
4. **Logic puzzle size.** Only the batter puzzle is specified (5 jars, 5 ingredients). Fix the
   Fortune Machine (phrase banks to lines) and the Oven (heat zones to temperatures) at the
   same shape, a 5-to-5 matching, so one solver, one generator and one puzzle scene serve all
   three.
5. **The finale has theme but no mechanics.** "Rate puzzle", "timing puzzle" and "sorting
   puzzle" need a concrete definition of inputs (what each crew's handoff note contains), the
   solving interaction, and what k-of-N notes contribute. The scoreboard session must not
   wait for this: it should store generic "handoff steps with a settings count" and leave the
   puzzle logic to the game. Schedule a finale design pass after the credit window.
6. **Hint ladder.** Hints are mentioned in three places with no rule. **Recommend:** nudge,
   stronger nudge, then show the solution without credit; mentors can push one nudge to a
   crew. A one-line rule in the doc is enough.

## 4. Design observations (Should fix / Note)

- **Sound puzzles in a conference hall.** Phones are muted, the room is loud, and iOS needs a
  tap before audio plays. Make all "pattern / sound" puzzles visual-first (a pulsing light, a
  conveyor beat) with sound and haptics as optional reinforcement.
- **Colour-only information.** Resistor bands and wiring puzzles must label colours with text
  or numbers. Tap targets at least 44 px. No puzzle should have time pressure.
- **Public contributors list.** Names go on a big screen. Ask for a display name and allow
  "anonymous"; do not use real names from anywhere else.
- **Spoilers are in the repo.** Puzzle answers are data in a public AGPL repository. For a
  cooperative game this is fine and even on-theme (reading the source is doing open source).
  Keep the facts in `puzzles/` as data the build consumes rather than scattering them in
  scenes, and never print answers in CI logs, so the path of least resistance is still to play.
- **Clue hunt is not the time sink.** With about 5 copies of each clue and 30 crewmates,
  gathering 4 clues takes minutes. The 40 to 60 minutes of play come from the in-game puzzles,
  which is what the design intends; just do not expect the social search to fill TeaGL.
- **Session 3 is two sessions of work.** Town, lucky-word entry, clue board, patch-and-merge
  flow and a six-puzzle Cookie Machine with tests is more than one session reliably delivers.
  The plan below splits it.
- **Parallel sessions share a dependency.** Session 2 writes the puzzle data that Session 3
  reads, and they run at the same time. Session 1 must ship the schema and seed data (the
  six sample clues above) so Session 3 is never blocked.
- **CI cannot check that a poem means its fact.** The document already says a human does
  this. Make it a PR template checkbox and add an optional LLM-assisted "does this clue text
  entail this fact?" check that comments rather than fails.
- **Writing has no plan.** The Gnu's notes and voicemails, the Anglerfish bits, side puzzles
  and the README-that-writes-itself are all content with no owner or schedule. Add a content
  phase after the credit window.
- **Open-source nods.** Red Panda for Firefox is a nice touch and all designs are original;
  keep that sentence in the game's about screen so nobody reads them as official mascots.

## 5. Technology review

See section 5 of `PLAN.md` for the version pin and CI specifics. Findings from the
feasibility research are summarised here.

Sources: Godot GitHub releases, the godot-docs repository, the setup-godot, gdUnit4-action and
deploy-pages READMEs, and Godot forum threads for the mobile reports. godotengine.org itself
was not reachable from the sandbox, so the mobile points rest on secondary sources.

- **Version (Should fix).** Godot 4.7 is real and stable: 4.7-stable shipped 18 Jun 2026,
  4.7.2-stable on 18 Aug 2026 and is the latest. "4.7.x" is too loose for a build pinned by
  CI; pin `4.7.2-stable` everywhere (engine, export templates, test-runner action) and bump
  on purpose.
- **Web export must be single-threaded (Blocker if missed).** The threaded web build still
  needs Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy headers, which GitHub
  Pages cannot set. The single-threaded export (default since 4.3) needs no headers and the
  docs say it works well on iOS. Turn "Thread Support" off in the export preset and do not
  add a service-worker header shim.
- **Renderer.** Compatibility (WebGL 2) is the only renderer that works on web; Forward+ and
  Mobile do not. The document is right. Set it in `project.godot`, including the mobile
  override.
- **iOS Safari is the main unverifiable risk.** Forum reports from 4.3 to 4.5 include WebGL
  context loss, page reloads at high memory, audio crashes and low frame rates on iPhones.
  Nothing found confirms or denies fixes in 4.7, and no CI step can test it. The plan must
  include real-device testing on an iPhone and a mid-range Android early (right after the
  first playable build), plus a tap-to-start screen so audio is unlocked by a gesture.
- **Load size and conference Wi-Fi.** Small Godot 4.x 2D web builds measure roughly 5 to 7 MB
  compressed in public benchmarks (estimates vary up to 25 to 40 MB uncompressed; GitHub
  Pages serves gzip only). One developer measured a 22-second cold start on a mid-range
  Android phone, mostly from loose assets. A plain TypeScript web game would be well under
  1 MB. With about 100 people loading at the same moment on venue Wi-Fi, size is a real
  event-day risk: add a size budget check to CI, pack assets, show a loading screen, and
  consider pre-announcing the URL so people load it before TeaGL.
- **CI tooling exists and is maintained.** `chickensoft-games/setup-godot@v2` (set
  `use-dotnet: false`, `include-templates: true`), `godot --headless --import` (run twice;
  grep the log for errors because headless exit codes can be 0 on failure),
  `godot-gdunit-labs/gdUnit4-action@v1` (GdUnit4 v7 runs headless by default) or GUT 9.7.1
  (`godot_4_7` branch), `godot --headless --export-release "Web"` (preset name is case
  sensitive; `export_presets.cfg` must be committed), then `actions/upload-pages-artifact`
  and `actions/deploy-pages@v4` with `pages: write` and `id-token: write`.
- **Engine choice is worth one deliberate decision (Blocker, see PLAN.md D0).** The
  document's reason for Godot is "scenes are plain text, so agents can write them". That is
  true but `.tscn` files carry resource ids and uids that are easy to get wrong without the
  editor, Godot must be downloaded into every sandbox to test anything locally, and the game
  is mostly tap-to-move, menus, text and drag puzzles. A TypeScript web stack (for example
  Vite with PixiJS or plain DOM and SVG) would be smaller, faster to load, testable in the
  sandbox with no engine download, and free of the iOS WebGL reports. Godot gives a real
  scene tree, 2D animation, audio and a game feel for less effort, and the rest of this
  review and the plan assume it. The plan is written so that only the foundation session
  changes if you pick the web stack.

## 6. Smaller corrections for the next doc revision

- Pi digits: "3.141592653" (ten digits) or add a lucky number.
- TeaGL duration: "30 to 40 minutes"; machines are fixed over the rest of day one.
- Code clue count: 73 characters if backticks print.
- "Mix both packs together" becomes a required runbook step.
- Hold back the lost-fortunes jar at random, not by fortune.
- Say explicitly that every player solves on their own device and the crew's machine runs
  when each part has been solved by someone in the crew.
- State the crew-assignment rule (first lucky word wins; switchable).
- Fix all three core logic puzzles at a 5-to-5 matching.
- Replace "Pattern / sound" with "Pattern / rhythm" and note visual-first.
- Add "display name, anonymous allowed" to the contributors list.

## 7. Addendum: review of design revision 2 (2 Nov 2026)

The revision (the world, game feel, art and sound) is a clear direction and a better game than
the menu-style layer Phase 1 produced. Points for the plan:

- **Shared crew inventory needs a server change.** The current API has no inventory. PLAN.md D10
  adds idempotent crew-inventory endpoints; everything must still be findable alone offline.
- **The decoy CI check needs a data definition before it can exist.** "Every decoy answer follows
  from its named mistake and matches no valid set of clues" is checkable once decoys are data
  with a named mistake (which outdated scrap, which misread cipher) and a destination. PLAN.md
  D13 defines that; the solver gains the check in WP18.
- **Accessibility moves from default to option.** The text-assist mode is the right shape for a
  pixel adventure, but it must exist before playtest round 1, or round 1 excludes people.
- **Pixel viewport arithmetic.** 11 tiles of 16 px is 176 px wide; a 390 px phone gives an
  integer scale of 2 (352 px) with 19 px bars each side, and a 430 px phone the same. Integer
  scaling is the right call; PLAN.md D9 fixes the base at 176 by 320.
- **60 frames per second on web Godot** is a target, not a guarantee, on mid-range Android.
  The pixel viewport helps enormously; physics and shader use should be profiled on the slice
  before being used everywhere.
- **Licensing is in order.** Ninja Adventure and Kenney are CC0; the image models are Apache
  2.0 with a stated rule against research-only upgrades; Stable Audio 3's community licence is
  acceptable for a free conference game and should be recorded per asset in `ASSETS.md`.
- **Working model changes.** Player-facing code is now one session at a time with Trevor's phone
  test as the gate; the parallel-worker model continues only for data, server, docs and tests.
