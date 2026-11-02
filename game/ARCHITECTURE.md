# Game architecture (WP3 build spec; section 15 is the WP16 adventure layer)

This spec binds WP3, WP4, WP6 and WP7. Anything it does not cover is a question for the integrator.

## 1. Layout and conventions

```
game/
  autoload/  scripts/core/ (section 3)  ui/main_theme.tres  test/{unit,scene,fixtures}/
  scenes/main/ main, start_screen        scenes/world/ town, shop, hotspot, part_fixture
  scenes/hud/ hud                        scenes/ui/ letter_keypad, clue_card
  scenes/screens/ screen_base.gd + the section 5 screens (snake_case)
  scenes/puzzles/ puzzle_base.gd, matching_puzzle, helper_puzzle, coming_soon_puzzle
  data/puzzles/<machine>.json            data/machines/<machine>.json
```

- snake_case files; `class_name` is the PascalCase file name (`matching_rules.gd` is `MatchingRules`); autoload scripts have no `class_name`. One script per scene, beside it, same basename.
- Text only; the sole binaries allowed are placeholder PNGs in `game/art/`. `ext_resource` uses `path="res://..."` without `uid=`; never write `uid://` or hand-made `.uid` files.
- Scenes are reached only via `Paths` string constants passed to `load()` (`preload` would cycle).
- WP3 helpers beyond this spec: `PlaceBase` (shared tap handling for Town and Shop), `UiKit` (button and label builders that enforce the 44 px rule), `Progress.reset()`, `GameState.persist` (tests turn it off). Godot writes `*.uid` files beside scripts; they are git-ignored.
- Every new `.gd` starts with `# SPDX-License-Identifier: AGPL-3.0-or-later`. Typed GDScript. JSON numbers arrive as floats: loaders apply `int()`.
- WP3 deletes the placeholder scene, script and test, and sets `run/main_scene="res://scenes/main/main.tscn"`, `gui/theme/custom="res://ui/main_theme.tres"` (font size 20) and the export preset's `include_filter="data/*"`.

## 2. Data

Godot cannot read YAML or, on the web, anything outside `res://`. **Decision:** WP2's `tools/solver/export_json.py` writes `game/data/puzzles/<machine>.json` from `puzzles/<machine>.yaml`; the output is committed and `puzzle-checks` fails if it is stale. Machine ids: `fortune_machine`, `cookie_machine`, `oven`. This format is the game's contract; the exporter maps YAML naming differences, and in the game only `PuzzleCatalog._normalise_machine()` may adapt.

```json
{ "schema_version": 1, "machine": "cookie_machine", "title": "Cookie Machine", "puzzle_title": "Batter recipe",
  "domain": { "items": ["sugar","flour","butter","vanilla","egg"],
              "positions": ["Jar 1","Jar 2","Jar 3","Jar 4","Jar 5"], "position_noun": "jar" },
  "answer": { "sugar": 1, "flour": 2, "vanilla": 3, "butter": 4, "egg": 5 },
  "clues": [ { "id": "cookie_machine.security", "style": "security", "approachable": true,
               "fortune_text": "ROT13 says: Fhtne vf va wne bar.", "lucky_word": "CIPHER",
               "fact": { "kind": "position", "a": "sugar", "value": 1 },
               "nudge": "ROT13 swaps each letter with the one 13 places along." } ] }
```

Positions are 1 to 5; `position` means pos(a) = value, `offset` means pos(a) = pos(b) + value; `fortune_text` excludes the lucky word. The exporter has landed: `puzzles/*.yaml` is the source and `game/data/puzzles/*.json` is its committed output. The JSON carries no item display names or item noun, so `PuzzleCatalog._normalise_machine()` derives names ("sugar" becomes "Sugar", "c120" becomes "120 C") and also accepts optional `domain.item_names` and `domain.item_noun` if the exporter ever adds them.

`data/machines/<machine>.json` holds exactly six parts in `Ids.PARTS` order:

```json
{ "machine": "cookie_machine", "helper": "Penguin", "parts": [
  { "part": "logic", "type": "matching", "title": "Batter recipe", "config": { "from_puzzle_data": true } },
  { "part": "wiring", "type": "wiring", "title": "Mixer motor controller", "config": {} } ] }
```

WP3 ships all six Cookie Machine parts: `helper` configured, the other four with `{}` until WP4. `Paths.puzzle_scene(type)` returns `res://scenes/puzzles/<type>_puzzle.tscn`, or `coming_soon_puzzle.tscn` if that scene does not exist. Answers live in `config`, never in scripts.

## 3. Autoloads and core classes

Thin Nodes over core classes, registered in this order:

| Autoload | Wraps | Responsibility |
| --- | --- | --- |
| `Events` | none | Signals `part_fixed(machine, part)`, `machine_running(machine)`, `clue_collected(clue_id)`, `crew_changed(machine)`, `display_name_changed(name)`, `progress_changed(machine)`, `hint_received(text)` (a mentor nudge arrived), `scoreboard_status_changed` (online state or queue size changed) |
| `PuzzleData` | `PuzzleCatalog` | Loads existing files for `Ids.MACHINES` (no directory listing): `get_clue`, `get_clues`, `get_domain`, `get_answer`, `get_parts`, `get_part`, `matching_config(machine, collected_ids)`, `lookup_lucky_word(word) -> {machine, clue_id}` or `{}` |
| `GameState` | `PlayerState` | Saved to `user://player.json` on change: `device_id` (`Crypto.generate_random_bytes(16).hex_encode()`), `display_name` ("" anonymous), `name_asked`, `crew` ("" none), `collected_clue_ids`, `solved_parts {machine: {part: credited}}`, `hint_levels`, `sound_on`, `seen_story` (story piece ids and `visit:` marks) and `story_state` (last state shown per key) |
| `Progress` | `ProgressStore` | `store`: `LocalProgressStore` if no scoreboard URL is configured (setting `fortune/scoreboard_url`, or `?scoreboard=` on the web build, section 12) or "Use scoreboard" is off, else `RemoteProgressStore`. A 1 s `Timer` calls the remote store's `tick()`; `use_scoreboard(on)`, `sync_now()`, `queue_size()`, `is_maintainer()`, `refresh_contributors()` serve Settings, the Hud and screens. After writes it diffs progress, emitting `part_fixed` (0 to 1) and `machine_running` (all six). At boot it writes the display name and crew to the store only if non-empty and changed. `Progress.reset()` calls `store.reset_local()` (new on `ProgressStore`; a remote store resets the local part it wraps and drops unsent writes) and keeps the active store |
| `Hints` | `HintLadder` | `advance(puzzle_id, can_reveal) -> int`: 0 none, 1 nudge, 2 stronger nudge, 3 reveal; capped at 2 without `can_reveal`; stored in `GameState.hint_levels`. `receive_pushed_nudge(puzzle_id, text)`: a mentor's nudge (Progress passes `""` for a whole-crew nudge); stores it, emits `nudge_received` and `Events.hint_received(text)` |
| `Story` | `StoryCatalog` | Section 13. Registered after `Hints` |
| `Audio` | none | Muted until the start tap calls `unlock()`; `play(name)` no-ops on missing streams or `sound_on` false |
| `Router` | none | Section 5 |
| `Finale` | `FinaleData`, `FinaleState`, `FinaleClient` | Section 14. Registered last, after `Router`, so `Story` and `Router` exist in its `_ready` (it still comes after `Progress`) |

Core classes in `scripts/core/` (one file each): `Ids`, `Paths`, `JsonFile`, `PuzzleCatalog`, `PlayerState`, `LuckyWords`, `MatchingRules`, `HintLadder`, `ProgressStore`, `LocalProgressStore`, `RemoteProgressStore`, and for the scoreboard `ScoreboardUrl`, `HttpTransport`, `Nudges` (section 12).

`Ids`: `MACHINES`, `MACHINE_TITLES`, `PARTS = ["logic","wiring","sequence","word","rhythm","helper"]`, `PART_TITLES`, `STYLE_LABELS`, `CLUE_THRESHOLD = 4`, `REPO_URL`. `Paths`: `PLACES` (`town`, `shop`), one constant per screen (`LUCKY_WORD_ENTRY`, `MERGE_CELEBRATION`, ...), `puzzle_scene(type)`. `JsonFile.read(path)` returns `{}` on a missing or bad file.

**ProgressStore** (`extends RefCounted`; getters return at once from local state or cache):

```
signal progress_changed(machine: String)
func set_display_name(device_id: String, name: String) -> void
func join_crew(device_id: String, machine: String) -> void
func record_part_solved(machine: String, part: String, device_id: String, credited: bool) -> void
func get_crew_progress(machine: String) -> Dictionary    # {part: solver_count}, all six parts
func get_contributors(machine: String) -> Array[String]  # first-solve order
func is_online() -> bool
func refresh() -> void
```

A machine's progress counts solves from devices in that crew; the scoreboard enforces this (a solve from a device not in the crew is rejected). The local store counts this device's solves. Mentors help other crews through hints, not solves. A revealed solve counts for progress but adds no contributor. Names are unique; anonymous shows once as "Anonymous". `LocalProgressStore.new(path := "user://progress.json")` saves `{version, names, crews, solves: [{machine, part, device_id, credited}]}`, ignoring repeats. `RemoteProgressStore.new(base_url, local, transport := Callable(), queue_path := "user://queue.json")` delegates to `local`, queues writes, sends them to the scoreboard and merges its answers into getters; `flush()` returns `queue.size()`. Section 12 has the details.

## 4. Scenes

```
Main (Node) > World (Node2D, current place), Hud (CanvasLayer 5), StartScreen (CanvasLayer 20)
Router > Screens (CanvasLayer 10)
```

**Start:** the first press on "Tap to start" calls `Audio.unlock()`, frees the start screen, shows the Hud, calls `Router.go_to_place("town")`, and pushes LuckyWordEntry if the player has no crew and no clues.

**Town** (Node2D, 390x844): an `Avatar` (ColorRect labelled "You") and `Hotspots/Shop`, `Hotspots/Pier`, `Hotspots/Teahouse`. A hotspot is an Area2D with `@export var place_id`, a RectangleShape2D of at least 96x96, a Label and a `Door` Marker2D. `_unhandled_input` tests each press at `get_global_mouse_position()` with `direct_space_state.intersect_point()` (`collide_with_areas = true`); no physics picking. A hit walks to the Door, then activates; a miss walks to the point clamped to `WALK_RECT`. Walking is a Tween on `position` at 320 px/s; a new tap kills it. Shop opens the Shop place, Teahouse (Red Panda) pushes LuckyWordEntry, Pier (Crab) pushes Contributors.

**Shop** (Node2D): `Machines/FortuneMachine`, `Machines/CookieMachine`, `Machines/Oven` and a Town button. Each machine has a hotspot opening MachineView and `Fixtures` with six `part_fixture.tscn`. `PartFixture` (`@export machine`, `@export part`) toggles `Broken` and `Fixed` children that differ in shape and label ("Mixer: off"/"Mixer: on"); it reads `Progress.store` in `_ready` and listens to `Events.part_fixed`. The Shop script has no machine-specific code.

**Hud:** a 56 px top bar with crew label (and a "Maintainer" badge once the scoreboard says the crew's machine runs), "Clues N" (ClueBoard) and "Menu" (Settings). It also hosts a `HintBanner` on its own CanvasLayer 30, above every screen.

## 5. Router

`Main._ready` calls `Router.attach_world(world)`. API: `go_to_place(id)` (from `Paths.PLACES`, frees the old place), `push(path, args := {}) -> ScreenBase`, `pop()`, `replace_top(path, args)`, `clear()`, `top()`, signal `stack_changed(depth)`.

`ScreenBase extends Control`: full rect, opaque, `mouse_filter = STOP`. Router calls `setup(args)` (stores args only) before `add_child`; `_ready` builds the UI. A top-left Back button and `ui_cancel` call `Router.pop()`.

| Screen | Args | Content |
| --- | --- | --- |
| LuckyWordEntry | none | Keypad, result line, "No cookie? Choose a crew" (three buttons) |
| ClueBoard | none | Clues by machine, crew first, "N of 6, 4 needed"; ClueCard "Help me read this" shows `nudge` |
| MachineView | `machine` | Six part rows opening PuzzleHost, and "See crew progress" |
| PuzzleHost, MergeCelebration | `machine`, `part` (+ `credited`, `now_running`) | Section 7 |
| Contributors | `machine` (optional) | Names per machine (from the scoreboard when it is on) |
| CrewProgress | `machine` (optional, default the player's crew) | Section 12 |
| Settings | none | Display name, switch crew, sound, scoreboard section (section 12), "Source code (AGPL)" (`REPO_URL`), "Reset this device" (confirm) |

**No LineEdit** (Godot's web virtual keyboard is experimental on iOS). `LetterKeypad` has in-game keys A to Z, 0 to 9, Space, Delete and Enter (48x48 or larger), also takes physical keys, and emits `submitted(text)`. It serves lucky words and display names (max 20 characters).

## 6. Lucky words and crews

`LuckyWords.normalise(s)` uppercases and keeps only A to Z and 0 to 9 (" tux." becomes "TUX"). `PlayerState.enter_lucky_word(word, catalog)` returns `UNKNOWN`, `ALREADY_HAVE`, `COLLECTED` or `COLLECTED_JOINED`: a known word from any machine adds its clue, and sets the crew only if none is set (D2). `choose_crew(machine)` serves no-cookie players and switching in Settings, keeping clues and solves. Crew changes call `Progress.store.join_crew` and emit `crew_changed`; name changes call `set_display_name` and emit `display_name_changed`.

## 7. PuzzleBase, PuzzleHost, MergeCelebration

```
class_name PuzzleBase extends Control    # scenes/puzzles/puzzle_base.gd
signal solved(credited: bool)
signal hint_requested(level: int)
signal give_up
var puzzle_id: String    # "<machine>/<part>"
var machine: String
var part: String
func configure(config: Dictionary) -> void   # virtual, called before add_child
func can_reveal() -> bool                     # virtual, default true
func get_hint_text(level: int) -> String      # virtual, levels 1 and 2
func reveal() -> void                         # virtual
func request_hint() -> void   # final: level = Hints.advance(puzzle_id, can_reveal()); emit hint_requested;
                              # at 3: reveal(), emit solved(false)
func quit() -> void           # final: emit give_up
func finish() -> void         # final: emit solved(true)
```

Puzzle subclasses never touch Router, GameState or Progress.

**PuzzleHost** reads `PuzzleData.get_part` (a `from_puzzle_data` config becomes `matching_config(machine, GameState.collected_clue_ids)`), loads `Paths.puzzle_scene(type)`, sets ids, calls `configure`, and adds it to `PuzzleSlot`. On open, a part not yet credited has its hint ladder reset (`Hints.reset`), so a returning player starts at a nudge. Header: Back (`quit()`; pop on `give_up`), title, Hint. When `next_hint_level()` would be 3, Hint first asks "Reveal the answer? You will not get credit." with Reveal / Keep trying; only Reveal calls `request_hint()`. On `hint_requested(level)` show `get_hint_text(level)`, or at 3 "Answer revealed. No credit this time.". On `solved(credited)`: `GameState.mark_solved`, `Progress.store.record_part_solved`, `Router.replace_top(MERGE_CELEBRATION, ...)` with `now_running` true if this solve completed all six parts, so Continue returns to MachineView.

**MergeCelebration:** "Patch submitted: <part>", Crab slides in with one of his `merged` lines (1.2 s tween, tap skips). The first credited solve shows `crab.first_contribution` in a box, then asks for a name on the keypad (`crab.name_prompt`; buttons "Add my name" / "Stay anonymous") and sets `name_asked`. Lists contributors; adds "<Machine> runs!" if `now_running`. Uncredited: the `uncredited` line instead of a merged line. All of Crab's words come from `data/story/crab.json` (section 13).

**MachineView:** six 64 px rows, each a light plus text: "Broken" (grey), "Fixed by your crew" (amber), "Fixed by you" (green). Header "N of 6 parts working", or "Running!".

## 8. MatchingPuzzle (type `matching`)

Its config is `{machine, domain, answer, clues (collected only), total_clues: 6, threshold: 4}`.

**Layout, top to bottom:** "Which <item> goes in which <position_noun>?"; five 60 px slot rows; a tray (HFlowContainer) of five 48 px item chips; Check (enabled when full); scrolling ClueCards of collected clues under "Clues: N of 6 (4 needed)", or "Find your crewmates and enter their lucky words at the Teahouse."

**Input:** tap a chip (outline plus "Selected"), then a slot; tap a filled slot to return its item. Drag (`_get_drag_data`, `_can_drop_data`, `_drop_data`) calls the same `place(item, slot)`. Test API: `place`, `clear_slot`, `placement()`, `check()`.

`MatchingRules` (static): `is_solved(placement, answer)`, `fact_holds(fact, placement)`, `fact_to_text(fact, domain)`. A wrong Check says "Not quite. Read your clues again." and never how many are right (that would bypass clues).

**Hints:** `can_reveal()` needs 4 or more of this machine's clues collected. Level 1 marks one card "Start here", preferring a `position` fact. Level 2 states the first fact the placement breaks in plain words, trying styles security, code, hardware, trivia, poem, animal; repeats move on. Texts: "Sugar is in jar 1.", "Vanilla is in the jar right after flour's.", "Egg is 2 jars after butter." Level 3 fills the answer.

**HelperPuzzle** (type `helper`, WP3): config `{speaker, lines, question, choices, correct, nudge, success_line?}` (`success_line` defaults to "Yes, that is it."); lines advance per tap, then choices; right calls `finish()`, wrong gets a retry line. Hint 1 shows `nudge`; hint 2 removes a wrong choice.

## 8b. WP4 puzzle types and their `config` (for authoring Fortune Machine and Oven parts)

Each type is `scenes/puzzles/<type>_puzzle.tscn`, found by `Paths.puzzle_scene(type)`. Answers live in `config`. Every config may also carry an optional `intro` string shown above the puzzle, and `hints`: `hints[0]` is the level 1 text, `hints[1]` the level 2 fallback (level 2 is normally computed from the player's current state, such as the first wrong wire, step or blank; `hints[1]` is used when nothing is wrong yet). Level 3 is `reveal()`. Pure logic lives in `scripts/core/`: `WiringRules`, `SequenceRules`, `WordRules`, `RhythmClock`.

| Type | Config | Notes |
| --- | --- | --- |
| `wiring` | `{terminals: [{id, label, color}], sockets: [{id, label, color}], connections: {terminal_id: socket_id}, hints}` | Tap a terminal then a socket (either order); tap a wire, or its row in the list, to remove it. `color` is any `Color.from_string` value (a name such as `"red"` or `"#c0392b"`). Colour is decoration only: write labels a colour-blind player can solve from, such as `"Red band (2)"`. Test API: `tap_terminal`, `tap_socket`, `connect_wire`, `remove_wire`, `wires()`, `check()` |
| `sequence` | `{steps: [{id, label}], order: [step_ids], hints}` | Tap a step chip to append it; Undo; tap a placed step to take it out; Check once `order.size()` steps are placed. Steps missing from `order` are decoys. Drag a chip or row onto a row (`_get_drag_data`, `_can_drop_data`, `_drop_data`). Test API: `append`, `insert`, `move`, `remove_at`, `undo`, `sequence()`, `check()` |
| `word` | `{lines: ["The mixer hums when the {0} is tight", ...], blanks: [{index, answer}], bank: [words, decoys included], hints}` | `{n}` marks blank n. Tap a blank then a bank word; tap a filled blank to clear it. Answers compare case-insensitively. A word listed once in `bank` fills one blank. Test API: `tap_blank`, `choose_word`, `fill`, `clear_blank`, `filled()`, `check()` |
| `rhythm` | `{bpm, pattern: [1,0,1,1], tolerance_ms: 180, required: 6, hints}` | No fail state: an off-beat tap resets the streak with a gentle message. `pattern` has one entry per beat over a bar; 1 is lit. Hint 2 slows the tempo by 25 percent; `reveal()` lights the whole row. `Audio.play("tick")` on each beat; `Input.vibrate_handheld(30)` on on-beat taps, only on web and mobile. Test API: set `manual_clock = true` before `add_child`, then `advance(seconds)`, `press()`, `clock.seconds_to_next_lit_beat()` |

For all four, `check()` (or the last on-beat press) calls `finish()`, which emits `solved(true)`; `reveal()` only fills in the answer, and `request_hint()` then emits `solved(false)`.

## 9. Phone and accessibility rules

- 390x844 portrait base, `canvas_items` stretch, `expand` aspect; anchored layouts so larger screens only add margin.
- Buttons and tap areas at least 44x44 (`custom_minimum_size`), test-enforced; clue text at least 18 px.
- Colour always paired with text or shape. No timers; tweens are skippable; sound optional.

## 10. Tests (gdUnit4)

Unit tests use the core classes with data from `test/fixtures/fixtures.gd`, never autoload state. WP3 ships at least these:

1. `test/unit/test_lucky_words.gd`: normalisation; known, unknown and other-machine lookups.
2. `test_player_state.gd`: first word joins; later words only collect; duplicates give `ALREADY_HAVE`; `choose_crew` with no clues; switching keeps clues; dict round trip.
3. `test_matching_rules.gd`: `is_solved` (answer, one swap); `fact_holds` incl. negative offsets; `fact_to_text`; for every `data/puzzles/` file, a 120-ordering brute force proves any 4 facts give exactly the stored answer and no 3 do.
4. `test_hint_ladder.gd`: levels 0 to 3, the cap at 2, dict persistence.
5. `test_local_progress_store.gd`: round trip via a new instance on `user://test_*.json` (deleted after); credited vs revealed; one "Anonymous"; duplicates ignored.
6. `test_puzzle_catalog.gd`: 5 items, 5 positions, 6 clues, answer an ordering of 1 to 5, lucky words unique across files, six parts per machine.
7. `test/scene/test_screens.gd`: main and every screen instantiate; all buttons at least 44 px; MatchingPuzzle emits `solved(true)` for the answer, nothing for a wrong full placement, `solved(false)` after three hints with 4 clues; Router depth after push, pop, replace_top.

## 11. Owned by later packages

| Package | May add | May edit | Must not edit |
| --- | --- | --- | --- |
| WP2 | `game/data/puzzles/*.json`, through the exporter | those files | the rest of `game/` |
| WP4 | `scenes/puzzles/{wiring,sequence,word,rhythm}_puzzle.*` extending PuzzleBase, their tests, helpers in `scripts/core/` | the `config` of those four parts in `data/machines/cookie_machine.json` | autoloads, Router, PuzzleBase, PuzzleHost, screens |
| WP6 | `data/machines/fortune_machine.json` and `oven.json`, Seagull and Gopher helper configs, tests | `shop.tscn`, adding nodes only, under the existing machine nodes | as WP4 |
| WP7 | crew progress and mentor screens, tests | `remote_progress_store.gd`, `progress.gd` (store choice, refresh), a Settings scoreboard section, `fortune/scoreboard_url` in `project.godot`, new `events.gd` signals, `receive_pushed_nudge` | PuzzleBase, ProgressStore signatures |

Contract changes (PuzzleBase, ProgressStore, data formats) go through the integrator.

## 12. Scoreboard client (WP7)

The contract is `server/API.md`; this section is the client's side of it. The game plays unchanged with no scoreboard.

**Switching it on.** `ScoreboardUrl.configured()` gives the base URL: the project setting `fortune/scoreboard_url` (committed empty, so the game is offline-only by default), overridden on the web build by `?scoreboard=https://host` in the page address (read once through `JavaScriptBridge`, a no-op off web; the query accepts `https` only, or `http` for localhost; the project setting may be any `http(s)` URL). Settings shows a "Use scoreboard" toggle (saved in `user://scoreboard.json`, on by default; disabled when no URL is set) and the configured URL read-only. Typing a URL on the in-game keypad is deliberately not offered.

**RemoteProgressStore.** Extends `ProgressStore`, wraps the local store and never blocks. The network is an injected `transport(method, url, body, done)` that ends with `done(status, data, retry_after)` (status 0 means no answer); `HttpTransport` (a Node with one `HTTPRequest` per request) is the real one and tests inject `FakeScoreboard`. With no transport it only queues, as in WP3.

- *Writes* (`set_display_name`, `join_crew`, `record_part_solved`) apply to the local store at once and append to `queue`, saved to `user://queue.json` with the id of the last hint seen per crew, whether this device is registered, and the machines known to run. They map to `POST /devices` (name or crew) and `POST /crews/{m}/parts/{p}/solve` with body `{device_id, credited}` (an uncredited, revealed solve counts for progress but adds no contributor). The queue is sent in order, one request at a time, which also meets the "flush before switching crews" rule. A network error, 5xx or 429 keeps the head and retries after a backoff of 2, 4, 8, ... up to 60 s (or `Retry-After`); `tick()` (a 1 s Timer in `Progress`) does the retry, and `flush()` ("Sync now") ignores the backoff. `403 not_in_crew` drops the solve (it stays in the local store, so this phone still shows it); `404 device_not_registered` inserts one registration first; any other 4xx is kept for retry but dropped after five refusals so a malformed write cannot block the queue. A first-time device with a name or crew queues one `POST /devices` (`set_identity`). Solves made before the scoreboard was on are queued once per device (`backfill_solves`, from `GameState.player.solved_parts`). `retire()` stops a store for good (no transport, no queue writes, late answers ignored); `Progress` retires the old store when the scoreboard is switched off or the address changes, and keeps the existing one when the toggle is set again for the same address. `reset_local()` also forgets the device id, crew and `runs` cache.
- *Reads.* Getters return at once: `get_crew_progress` is the per-part maximum of the local count and the last server `solved_count`; `get_contributors` lists the server's names (reversed to first-merged order, "anonymous" shown as "Anonymous") then any local name the server lacks; `get_contributor_entries` adds `via` (`solve` or `mentor`). `is_online()` is the outcome of the last request. A crew answer with `runs: false` clears the remembered flag (an admin reset). A 429 on a poll pushes the next poll out to `max(Retry-After, 10 s)`. Every cache change that differs emits `progress_changed`, and `Progress` turns that into `part_fixed` and `machine_running` as for local solves. The solve response's crew object also updates the cache.
- *Polling budget.* `refresh()` looks once at the player's crew, every watched machine, and (if hint polling is on) new hints. Nothing polls on its own: `Progress` calls `set_watching(machines, hints)` when the Router stack changes. A MachineView or CrewProgress on top watches that machine and hints; a PuzzleHost on top watches hints only; anything else watches nothing. `tick()` repeats `refresh()` every 10 s while something is watched. Also one look at boot, on `crew_changed`, and one `GET /contributors` when the Contributors screen opens.
- *Maintainer.* `server_runs(machine)` is true once a crew response said `runs`, remembered in the queue file. `Progress.is_maintainer()` is that for the player's crew; the Hud badge and the nudge section use it.
- *Hints.* `GET /hints?crew=&after_id=` for the player's crew; each new hint is emitted as `hint_arrived`, and `Progress` passes `Nudges.describe(hint)` to `Hints.receive_pushed_nudge("", text)`, which emits `Events.hint_received(text)` for the `HintBanner` (dismissible; later hints queue behind it). On the first look for a crew only the newest hint is shown, then `after_id` pages forward 50 at a time. `fetch_nudge_ids(done)` and `send_nudge(to_crew, nudge_id, done)` wrap `GET /hints/nudges` and `POST /hints`; the words for each nudge id live in `Nudges`.

**CrewProgress screen** (`scenes/screens/crew_progress.tscn`, reached from MachineView): "Machine runs!" or "N of 6 parts working", one row per part (light plus text: "Broken" or "fixed by N crewmates", "fixed on this phone" offline), contributors (mentors marked), and the line "Online, showing your whole crew" or "Offline, showing this phone only". Maintainers also get "Send a nudge": pick one of the other two crews, then a nudge from the server's list.

**Tests.** `test/fixtures/fake_scoreboard.gd` is the fake transport; `test_remote_progress_store.gd`, `test_scoreboard_url.gd` and `test/scene/test_scoreboard_screens.gd` cover queue persistence, order, drops and retries, cache and offline getters, polling cadence, hints, URL parsing and the screens. No test opens a socket.

## 13. Story (WP10b)

The words live in `data/story/*.json` (format `data/story/schema.json`, rules in `docs/STORY.md`, checked by `tools/dev/check-story.py`). A piece has `id`, `speaker`, `kind`, up to 3 `lines`, `where` (screen or place) and `when` (trigger). The `where` and `when` values in the data are the contract; code asks for them as written and never invents a trigger.

**`StoryCatalog`** (`scripts/core/story_catalog.gd`, pure data): loads the files in `StoryCatalog.FILES` (listed explicitly, no directory listing on the web; `side_puzzles.json` holds concepts and is not loaded) and indexes pieces by `where` and `when`. Every call returns copies with `{name}`, `{machine}`, `{part}` and `{repo_url}` filled from a context dictionary (unknown placeholders stay as written) and a joined `text`. `pieces_for(where, when := "", context)`, `next_unseen(where, when, seen, context)` (first in data order not in `seen`, so a group is walked in turn), `unseen(...)` (all of them, for a first-visit sequence), `pick(where, when, rng, context)` (a random alternative from a group), `pieces_by_speaker(speaker, place)`, `get_piece(id)`.

**`Story`** (autoload, after `Hints`): wraps a catalog and the player's state. `pieces_for`, `next_unseen`, `unseen`, `pick` and `get_piece` fill `{name}` (display name, or "friend") and `{repo_url}` for you. Seen ids persist in `PlayerState.seen_story` (saved with the player); `mark_seen(id)`, `is_seen(id)`. `visit(key)` is true once per key (a "first open", stored as `visit:<key>`). `state_changed(key, state)` is true when the state differs from the last one stored in `PlayerState.story_state`. `rotate(key, size)` walks 0..size-1 round and round (not saved). `set_flag(name, on)` / `flag(name)` / `flags_changed` serve triggers that nothing in the game raises yet; `trigger_active(when)` says whether a note's trigger holds (`machine_running:crew` from `Progress`, everything else from flags). `play(host, pieces, mark := true)` opens a DialogueBox and marks the pieces seen. `load_msec` is how long loading took (`PuzzleData.load_msec` likewise).

**`DialogueBox`** (`scenes/ui/dialogue_box.tscn`): a full-rect Control that stops input, with an opaque (97 percent) panel along the bottom: speaker (plus "(note)", "(voicemail)" and so on), up to 3 lines, "Tap to go on (n of m)" or "Tap to close", and a 44 px Skip button. `show_pieces(pieces)` takes substituted pieces; a tap anywhere calls `advance()`, Skip or Escape calls `skip()`; `finished` fires once, after the last piece or on Skip, and the box then frees itself (`free_on_finish`). `advanced(index)` fires on each step. No timers: `auto_advance_seconds` (default 0, off) is the only way to get one. Open it with `DialogueBox.open(host, pieces)` or `Story.play`: a Control host (a screen) gets it as a child, any other node (a place) gets a CanvasLayer 9 (above the Hud, below screens).

**Who calls it.**

| Where | Trigger used |
| --- | --- |
| StartScreen | `start_screen/always` (tagline), `loading/always` (one tip). If `PuzzleData.load_msec + Story.load_msec` is 400 ms or more, "Tap to start" is held for 1.5 s so the tip can be read; otherwise no wait |
| LuckyWordEntry | `lucky_word_entry`: `first_visit` (welcome, two boxes in one go), then one of `no_crew`, `has_crew` or `machine_running:crew` only when that state differs from the last one shown |
| PuzzleHost | `puzzle:<machine>/<part>/first_visit` (the Gnu's note, once per part) |
| MergeCelebration | `merge_celebration`: `merged` (random pick, credited solves), `first_credit` (`crab.first_contribution` in a box once; `crab.name_prompt` replaces the name question), `uncredited` |
| MachineView | `machine_view:<machine>/idle`: on the first open of each machine, then after 20 s without input (a `Timer` named `IdleTimer`; `cancel_idle()` stops it; it only speaks while the screen is on top) |
| Contributors | `contributors/first_visit` (Crab on the Pier, once) |
| Settings | `settings/always` (About block, with the repo URL, above the "Source code (AGPL)" button) |
| Town | the Gnu's pieces whose `where` is `town` or `town:<spot>` as `StoryMarker` buttons (76x44, "! Note" until read, "Note" after); the first tap on the Shop door reads `town:shop/first_visit` before the Shop opens; the Anglerfish (`town/interval`) |
| Shop | the Gnu's pieces whose `where` is `shop` as markers (the answering machine only once the crew's machine runs) |

`PlaceBase.add_story_markers(place, positions)` builds the markers (positions are in a constant of the place's script, keyed by piece id). The six `gnu.town.*` pieces therefore split by their `where`: four markers in the Town (`shop_door`, `teahouse_board`, `pier_bottle`, `handoffs`) and two in the Shop (`shop_counter`, `answering_machine`).

**Anglerfish.** A Button with a ColorRect placeholder, bottom edge of the Town. A repeating `Timer` (90 s) calls `spawn_anglerfish()`, which shows the next `town/interval` bit (first line cut to 44 characters) for 8 s (`LeaveTimer`) unless a screen is open; tapping it opens the full piece. It does not mark the bits seen, since they come round again.

**Finale triggers (wired by WP12).** `finale_archive` (Elephant: `first_visit` in the Archive, `finale_open` in FinaleView, `note_found` and `handoff_solved` after a note is filed or a handoff is connected) and the `Story.set_flag` flags `finale_open` and `line_running`, which `Finale` raises from the cached `GET /finale` (`line_running` also drives the Anglerfish farewell in the Town; after it plays the Anglerfish never returns). Still unwired: `red_panda.finale_open`, `lucky_word_entry/finale_open`, `town/finale_open` (the `gnu.town.handoffs` marker is now shown once `finale_open` is set), `elephant.archive.line_running` and `gnu.last_fortune` as a story piece (the ClueBoard shows the last fortune from `readme.json` instead), and `big_screen/line_running` (the big-screen page has its own text). To raise a late trigger, call `Story.set_flag(name)`; Town and Shop update their markers on `flags_changed`.

**Tests.** `test/unit/test_story_catalog.gd` (loading, indexing, late triggers, placeholders, `next_unseen`), `test_story_state.gd` (seen and state round trip), `test/scene/test_story_hooks.gd` (autoload, DialogueBox advance and skip, and every hook above).

## 14. Finale (WP12)

The spec is `docs/FINALE-DESIGN.md`; this section is the game's side. The big-screen page is `server/static/bigscreen/`, and `game/data/finale/readme.json` must stay byte-identical to its `readme.json` (a pytest checks it).

**Data** (`data/finale/`, answers live here and nowhere else): `handoffs.json` (`notes`: crew notes with `handoff_word`, Gopher's free slip; `handoffs`: three `dials` puzzles, each with `needs`, `preview` and three dials), `gnu_notes.json` (six notes, each with a printed code such as "KETTLE 27", its venue spot and a `helper` twin; `needed` 4) and `readme.json`. `FinaleData` loads and validates them (`errors()` is empty for sound data). Codes are compared and posted normalised (`KETTLE27`).

**Core** (`scripts/core/`): `DialRules` (pure: marks ok/low/high/wrong, locking, reveal, the beats landing ticks), `FinaleState` (`user://finale.json`: `{version, notes_held, settings, gnu_notes, queue, cache}`; adds are idempotent and queue the POST), `FinaleClient` (same injected `transport(method, url, body, done)` as `RemoteProgressStore`; `GET /finale` every 15 s only while `set_watching(true)`, queued settings and notes with 403 `finale_closed` / 409 `handoff_waiting` held until a poll shows them possible, 404 registering first, the start code online only).

**Autoload `Finale`** (registered last, so after `Progress`, `Story` and `Router`): owns the state and the client (a client exists only when `Progress` has a scoreboard URL and the toggle is on), drives it with a 1 s `Timer`, watches the Router stack (FinaleView, HandoffHost or Archive on top means polling), and hands out notes: a crew's note when its machine runs or on joining a running crew, free notes once the finale is open. It sets the Story flags `finale_open` and `line_running`. `Finale.reset()` runs from `GameState.reset_device()`.

**Screens:** `DialsPuzzle` (`scenes/puzzles/dials_puzzle.tscn`, a `PuzzleBase` with `setting_set(index)`, `locked_indices` in its config and the test API `step`, `set_value`, `values`, `locked`, `test_run`; `DialPreview` draws the belt, beats and routes shapes). `HandoffHost` (args `handoff` or `twin`) shows the gate message or the puzzle, the header "Settings set by everyone: N of 3. On this phone: M of 3." and Continue. `FinaleView` (Shop's "The line" button), `Archive` (Town hotspot `Hotspots/Archive`), `ReadmeScreen`. `ClueBoard` shows "Handoff notes" first and "The gnu's last fortune" once started; `LuckyWordEntry` falls back to `Finale.collect_word`. Elephant's story lines play in the `DialogueBox`. A twin puzzle files its gnu note only on a credited solve; a hint-3 reveal shows "Elephant smiles. Find the real note, or solve it yourself." and files nothing. While FinaleView, HandoffHost or Archive is on top, `Progress` watches all three machines so crew progress (the pre-open rows, note grants, README triggers) keeps refreshing.

**Tests:** `test_dial_rules`, `test_finale_data`, `test_finale_state`, `test_finale_client` (with `FakeScoreboard` and `test/fixtures/finale_fixtures.gd`), and `test/scene/test_finale_screens.gd`.

## 15. Adventure layer (WP16)

The player-facing layer since WP16 (PLAN.md section 9, decisions D9 to D14). It sits on top of everything above: PuzzleData, GameState, Progress and the scoreboard client, Story, Hints, Router and Finale are unchanged in role. The old Town, Shop and Hud stay reachable behind `fortune/debug_legacy_screens` (section 15.10).

```
game/assets.json                     logical art names -> files (15.4)
game/data/rooms.json                 the town (15.2)
game/data/sfx.json                   sounds, synthesised at run time (15.5)
game/data/chains/<machine>.json      chains (15.7); WP16 ships cookie_machine.json with the cutter chain
game/data/story/chains.json          what rooms, items and the chain say
autoload/adventure.gd                Adventure: rooms, assets, chain states, crew inventory, interact()
scripts/core/                        AssetLoader, PixelGlyphs, SfxSynth, SfxBank, RoomGraph, ChainRules,
                                     ChainState, InventoryStore, LocalInventoryStore, RemoteInventoryStore,
                                     DebugSettings
scenes/adventure/                    adventure_view, room, cookie_machine_rig, portrait_dialogue,
                                     inventory_bar, close_up_base, lock_dials, straighten_bench, tighten_bolts
scenes/puzzles/batter_shelf_puzzle   the batter jars as a PuzzleBase (15.8)
```

`Adventure` is registered after `Finale`. Main starts `AdventureView` (on a CanvasLayer 1) after the start tap unless the legacy setting is on; a new player still gets LuckyWordEntry pushed first.

### 15.1 View, scale and input (D9)

`AdventureView` renders the room in a `SubViewport` of 176x320 (11 by 20 tiles), drawn by a `SubViewportContainer` with nearest filtering and `snap_2d_transforms_to_pixel`. The container is scaled (Control `scale`), not stretched, so the scale can be a whole number of **device** pixels: `device = root.get_final_transform().x.x` (at least 1), `k = floor(min(width * device / 176, (height - 52 - 96) * device / 320))`, `pixel_scale = k / device`. On a 390x844 phone that is 2 layout pixels per art pixel (6 device pixels at DPR 3). Left and right are letterboxed; the inventory bar takes the space above (at least 52), the dialogue bar the space below (at least 96, growing upward over the room for a long line). If a screen is too short, the bars overlay the room. `screen_to_room()` and `room_to_screen()` convert through the frame and the room camera.

Taps reach the room through the container (`Room._unhandled_input`, room position from `get_canvas_transform().affine_inverse()`); hit tests use the data rects (`RoomGraph.thing_at`), never physics picking. While dialogue is open a transparent catcher over the room turns any tap into "next line"; while a close-up or a Router screen is open the room ignores taps. Menus are Router screens on CanvasLayer 10 above everything: Clues and Menu in the inventory bar, LuckyWordEntry (Red Panda's board), Contributors (Crab's board), MergeCelebration after a solve. The mentor `HintBanner` is added on CanvasLayer 30 by the view.

### 15.2 Rooms, walking, camera, transitions

`data/rooms.json` holds a shared `legend` (map character -> `tile` asset, `solid`) and `rooms`. A room has `title`, `kind`, `sound` (its ambient loop), `map` (rows of 11 characters), `spawns` ({name: [x, y]}), `exits` ([{tiles, to, arrive, kind: door|edge, dir}]), `npcs` and `props` (things: `id`, `asset`, `at`/`size` or `rect_px`, `stand`, `solid`, `facing`, `say` (piece ids, shown in turn), `open` (a menu or close-up), `hint` (Red Panda)), `rigs` (the Cookie Machine) and `ambient` (steam, gulls, sparkle, bubbles). WP16's rooms: teahouse (start), square (the connecting street; not in the design's list but needed to join four doors and two edges), shop, workshop, depot, pier, scrapyard and harbour. Thing ids are the targets chain data names.

`RoomGraph` is the pure side: walkability (legend plus solid things; exit tiles always open), `path()` (AStarGrid2D, 4-way), `thing_at`, `stand_cell`, `nearest_walkable`, `targets()` for chain validation, and `validate()` (11 wide, every exit to an existing room and spawn and back, no blocked spawns or exits, somewhere to stand by every thing).

`Room` (scenes/adventure/room.tscn) builds itself from that data: a `TileLayer` that draws static tiles once and another that redraws animated tiles (water) at about 2 Hz, props and characters as `AnimatedSprite2D` in a y-sorted layer (characters play `idle_<facing>`), the rig, ambient motion, the player and a `Camera2D` limited to the room with position smoothing, so rooms taller than 320 (square, pier, scrapyard, harbour) scroll as you walk. A tap plays `tap` or `select` and a ring at once, flashes the thing hit, walks to its stand cell (96 px/s; distance left at a cell carries on, so slow frames never slow the walk) and then emits `thing_activated` or, with an item picked or dropped, `item_used`. Stepping onto an exit tile emits `exit_reached`; the view fades through black for doors and, for edges, slides a snapshot of the old room out while the new one slides in (flip-screen), falling back to the fade where the viewport cannot be read. The view saves the room and cell in `user://adventure.json` after each walk, so a reload resumes there. On the web build `?room=<id>` starts in that room (playtests and screenshots).

### 15.3 Characters and dialogue

Characters are `char.<id>` sheets (4 columns for down, up, left, right; idle and walk animations listed in assets.json). The player walks with 4-frame walk cycles (placeholders alternate feet) and idles facing where it last moved. `PortraitDialogue` is the bottom bar: portrait `portrait.<speaker>.<expression>` (falls back to neutral; none for the Narrator), speaker and kind ("Gnu (sticky label)"), and one line at a time typed out at 70 characters a second with `babble.<speaker>` beeps every 3 characters. A tap finishes the line, the next moves on; pieces queue. Story pieces gained an optional `expression` (neutral, happy, worried, surprised, sly), kept by `StoryCatalog`. With nothing to say the bar shows the room, crew and online state, and a one-line how-to.

### 15.4 AssetLoader (D11)

`game/assets.json`: `tile_size`, the game's one `palette` and `assets` {name: {file, frame_size, frames, kind, origin?, columns?, animations?, color, glyph, ...}}. `AssetLoader.shared()` loads by logical name: `texture(name, frame)` and `frames(name)` (SpriteFrames). If `res://<file>` exists as an imported resource it is used (an AtlasTexture for one frame of a sheet); otherwise a placeholder is drawn in code: a block in the palette colour with a 1 px outline and a 3x5 pixel glyph (`PixelGlyphs`), shaped by kind (tiles fill and their glyph drifts per frame, characters face the animation's direction and step, portraits draw a mouth per expression, `fx` and `glyph` kinds are transparent). `frame_colors` and `frame_glyphs` give placeholders states (a lamp off and on, dial digits). No art is committed: the Ninja Adventure tiles are listed under `art/ninja/Backgrounds/Tilesets/...` with a best-guess `origin`, characters under `art/characters/`, portraits under `art/portraits/`, props, machines, close-ups and effects under their own folders. When the art session lands a file at its path (and fixes `origin` or `frame_size` if needed), the game picks it up with no code change. Static textures are released when Adventure leaves the tree.

### 15.5 Sound (D12)

`data/sfx.json` maps interaction ids to `{wave: square|triangle|saw|sine|noise, freq, freq_end, notes, note_len, duration, attack, decay, volume, duty, vibrato, loop, lfo}` or `{alias}`. `SfxSynth` builds a 16-bit mono `AudioStreamWAV` at 22050 Hz in code (no audio files); `SfxBank` caches them. `Audio.play(id)` uses six voices in turn (taps overlap), records every id in `played` even while muted (tests), and stays silent until the start tap (`unlock()`) and while Menu > Sound is off. `Audio.play_ambient(id)` loops the room's `sound` (`ambient.indoor`, `town`, `sea`, `wind`, `machines`) quietly. The ids a scene plays itself are `SfxBank.CORE_IDS`; with one babble per speaker and every id in chain and room data, `test_sfx.gd` checks each has a sound.

### 15.6 Crew inventory (D10)

`InventoryStore` entries are `{item_id, state: found|installed, found_by (device id), found_at, place}`; state only moves forward and a repeat changes nothing. `LocalInventoryStore` (`user://inventory.json`, per machine) is the whole inventory offline. `RemoteInventoryStore` wraps it, like `RemoteProgressStore`: writes apply locally and queue (`user://inventory_queue.json`) as `POST /crews/{m}/inventory/{item_id}` `{device_id, state, place}`, sent in order with backoff 2 to 60 s (or Retry-After); a write already queued is not queued again; `403 not_in_crew` drops it (it stays on the phone); other 4xx are dropped after five refusals. `GET /crews/{m}/inventory` merges rows into the local store (the server's `found_by` wins: first writer). `backfill()` sends this phone's offline finds once a scoreboard appears. Adventure builds the remote store when `Progress.scoreboard_active()` (same address and toggle), using `Progress.network()` (the shared HttpTransport, or the tests' fake), polls the player's crew every 15 s from a 1 s Timer, and "Sync now" flushes it. The bar shows "Found by you" or "Found by a crewmate" (device ids are not names). `place` is `<room>:<target>`. Checked against the real WP5c server (find, crewmate repeat keeps the first finder, install, 403 drop) besides the fake-transport tests.

Only **shared** items sync. Unshared items (`shared: false`: misdirects and Seagull's scrap) live in `ChainState.held` on the phone, each with a `home` to be put back, so a crewmate's look-alike never clutters everyone's bar and nothing needs a "returned" state on the server.

### 15.7 Chains (D13)

`data/chains/<machine>.json` has `items` (kind tool, part or knowledge; `asset`, `about` piece, `shared`, `replaced_by`, `home`) and `chains`, each with `part` (the machine part its goal credits), `goal`, `places`, `steps` (find, decode, repair, install: `room`, `done_when`, two Red Panda `hints`), `locks`, `misdirects` (item, room, `tell`, `tell_piece`), `decoys` (lock, outdated `code`, named `mistake`, `source_item`, `destination`, `flash`, `wrong_place_says`, `tell`) and `interactions`.

An interaction is `{id, room, target, verb, item?, result?, requires, effects, say, sfx, misdirect?, decoy?}`. Verbs: `tap`, `use` (an item in hand dropped or tapped onto the target), `code` (a lock; `result` is right, wrong or decoy:<id>), `done` (a close-up finished; the target is the close-up's name) and `enter` (arriving in the room; the target is the room). `requires` keys: facts, not_facts, have, not_have, found, installed, not_installed, decoys_seen, not_decoys_seen. Effects: `learn`, `hold`, `release`, `see_decoy` (ChainState, this phone) and `find`, `install`, `solve_part`, `open` (handed back). The first interaction in data order whose requirements hold wins.

`ChainRules` is static and pure: `resolve`, `apply`, `apply_to_inventory`, `has_item` (found, not installed, not replaced; unshared: held), `visible_items`, `current_step` (the step after the furthest one done, so a crewmate's find skips ahead), `lock_code` and `code_result`, `validate`, `sfx_ids`, `piece_ids`. Lock codes are never written in data: `code_from` names the logic puzzle and items, and the digits are those items' positions in `PuzzleData.get_answer` (the fortunes point around town, as the design says). `ChainState` saves facts, held items and decoys seen to `user://chain_<machine>.json`. `Adventure.interact(room, target, verb, item, code)` resolves across every machine's chains, applies the effects (finds and installs through the inventory, `solve_part` through `Adventure.record_solve`, which does what PuzzleHost does) and returns `{say, sfx, open, solved_part, now_running, misdirect, decoy, result}` for the view to present; a part solve ends in MergeCelebration. Red Panda's help is `Adventure.next_hint()`: the current step's nudge, then its stronger nudge.

**How a step maps to a room interaction (the cutter chain):**

| Step | Room, target, verb | Effect |
| --- | --- | --- |
| find | shop, `cutter`, tap | the gnu's sticky label; learn `die_out` |
| (ask) | workshop, `penguin`, tap (needs `die_out`) | learn `die_mailed`; find `spanner` |
| decode | depot, `gnu_locker`, tap | open the dials close-up (`lock:gnu_locker`) |
| decode | depot, `gnu_locker`, code right (egg, vanilla, sugar jars) | find `die_bent` |
| decoy | pier, `seagull`, tap; depot, `gnu_locker`, code 241 | hold `old_scrap`; see decoy; "Code changed. Parcel forwarded: HARBOUR." |
| decoy | harbour, `harbour`, enter (decoy seen) | Anglerfish's pitch and the dated slip, pointing back to the fortunes |
| misdirects | scrapyard `scrap_pile` tap; harbour `anglerfish` tap; their dies used on `cutter` | hold a look-alike; its tell (10 teeth; a connector that fits nothing); give it back to its home |
| repair | workshop, `bench`, use `die_bent`; `straighten` done | find `cutter_die` (replaces the bent one) |
| install | shop, `cutter`, use `cutter_die` (with the spanner); `tighten` done | install `cutter_die`; solve part `rhythm` |

The cutter is the press's die, so WP16 credits the Cookie Machine's **rhythm** part ("Press and conveyor beat") when the die is installed; the old beat puzzle stays on the old screens. WP19 may move the beat into this chain as its last step.

`test_chain_rules.gd` plays the chain in step order, checks prerequisites, misdirect tells, the decoy's route, message and tell, crew finds skipping steps, and "nothing lost for good": a breadth-first search over every reachable state (taps, every item on every target, right, decoy and wrong codes, close-ups finished or abandoned) finds the goal still reachable from each.

### 15.8 Close-ups and the batter shelf

Repairs zoom in: `CloseUpBase` covers the room view and draws pixel art on the same 176x320 grid at the view's scale, with a header (title, Hint for puzzles, X). `LockDials` (tap a dial's top or bottom, or drag it; pull the handle; `code_entered`, then `show_result` swings the door, flashes the forwarding notice with the decoy's destination from data, or buzzes), `StraightenBench` (tap each dent; two mallet blows each, sparks; `done`) and `TightenBolts` (tap or drag the spanner over each bolt three quarter turns; `done`). They emit, the view calls `Adventure.interact`.

`batter_shelf_puzzle.tscn` is a `PuzzleBase` with MatchingPuzzle's config and `MatchingRules`: drag jars from the counter onto five shelf places; a dropped jar falls with gravity and bounces (a little physics, done by hand: no physics bodies), a displaced jar tumbles home, a tap on a shelved jar takes it down, five jars check themselves (glow and solve, or wobble and "Not quite"). Hints and reveal follow MatchingPuzzle's rules. Test API: `place`, `clear_slot`, `placement`, `check`, `drop_jar`, `simulate`, `settle`, `is_settled`. The view hosts it like PuzzleHost does (hint ladder, reveal confirmation, the gnu's first-visit note, credit through `Adventure.record_solve`, MergeCelebration). The Cookie Machine's other four parts and the Fortune Machine and Oven still open their old PuzzleHost or MachineView from the shop until their chains land.

### 15.9 The Cookie Machine rig

`CookieMachineRig` draws the machine in the shop from `machine.cookie.*` assets and reads the crew's progress: jars fill the shelf (logic), the paddle turns (wiring), the panel blinks (sequence), the note glows (word), the cutter stamps a round onto the moving belt every 0.9 s (rhythm), the lamp lights (helper); all six send finished cookies along. A part fixed since this phone last saw it gets its moment once (sparks, a shake, `part_fixed`, a caption `narrator.fixed.cookie_machine.<part>`), held back while a close-up or a screen is open; seen parts are remembered in `GameState.story_state`.

### 15.10 Legacy screens

`DebugSettings.legacy_screens()`: a phone override saved by Menu > Old screens (debug) in `user://debug.json`, else the project setting `fortune/debug_legacy_screens` (false). On, Main shows the old Town with the Hud instead of the adventure layer; toggling restarts the main scene without asking for the start tap again. The old screens' tests force it on (`DebugSettings.forced`).

### 15.11 Tests

`test/unit/`: `test_chain_rules`, `test_inventory_store` (local; remote with `FakeScoreboard` in the server's row shape: body, idempotence, 403 drop, offline queue and backoff, five refusals, first writer, polling, backfill, retire), `test_room_graph`, `test_asset_loader` (well-formed list, every placeholder draws at its size, outline and glyph, animations, portraits, a real file replaces the placeholder), `test_sfx` (data, every interaction id, babble, synthesis). `test/scene/test_adventure.gd`: main into the teahouse, the legacy switch and its toggle, integer scaling and bars, feedback on every tap, walking frames, doors and edges both ways, idle characters and portraits, the whole cutter chain through the view including both misdirects and the decoy, putting misdirects back, wrong drops, tap-to-use, the batter shelf (solve, tumble, swap, hints, reveal, from the shop), the rig coming alive, the dialogue bar, `?room=`.

**Known limits.** On the web build, files saved just before a page reload can be lost if the browser's storage sync has not run yet (seconds); the next save syncs everything. The text-assist mode (D14) is WP23.

### 15.12 What later packages may add

| Package | May add | May edit |
| --- | --- | --- |
| WP17 (chain design) | the other chains in `data/chains/*.json`, their story pieces, `docs/CHAINS.md`, new rooms in `rooms.json` (archive, cottage) | room things and exits, Red Panda's hints |
| WP18 (checks) | CI checks for the asset list (files exist or are placeholders), the decoy rule against the solver, chain validation in Python | none |
| WP19 to WP21 (chains) | close-ups extending `CloseUpBase` (or puzzles extending `PuzzleBase`) for each part, rigs for the Fortune Machine and Oven, new verbs or requirement keys in `ChainRules` with tests | `open_target`/`open_closeup` in AdventureView, `CHAIN_FILES` in Adventure |
| WP22 (finale) | the line as a rig in the shop, Archive as Elephant's room | the finale screens' entry points |
| Art session | files at the paths in `assets.json`; corrected `origin`, `frame_size`, `animations` | `assets.json` paths only |

Must not change without the integrator: the inventory and chain data formats above, `Adventure.interact()`'s result, ProgressStore and PuzzleBase.
