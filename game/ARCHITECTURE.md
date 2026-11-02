# Game architecture (WP3 build spec)

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
| `GameState` | `PlayerState` | Saved to `user://player.json` on change: `device_id` (`Crypto.generate_random_bytes(16).hex_encode()`), `display_name` ("" anonymous), `name_asked`, `crew` ("" none), `collected_clue_ids`, `solved_parts {machine: {part: credited}}`, `hint_levels`, `sound_on` |
| `Progress` | `ProgressStore` | `store`: `LocalProgressStore` if no scoreboard URL is configured (setting `fortune/scoreboard_url`, or `?scoreboard=` on the web build, section 12) or "Use scoreboard" is off, else `RemoteProgressStore`. A 1 s `Timer` calls the remote store's `tick()`; `use_scoreboard(on)`, `sync_now()`, `queue_size()`, `is_maintainer()`, `refresh_contributors()` serve Settings, the Hud and screens. After writes it diffs progress, emitting `part_fixed` (0 to 1) and `machine_running` (all six). At boot it writes the display name and crew to the store only if non-empty and changed. `Progress.reset()` calls `store.reset_local()` (new on `ProgressStore`; a remote store resets the local part it wraps and drops unsent writes) and keeps the active store |
| `Hints` | `HintLadder` | `advance(puzzle_id, can_reveal) -> int`: 0 none, 1 nudge, 2 stronger nudge, 3 reveal; capped at 2 without `can_reveal`; stored in `GameState.hint_levels`. `receive_pushed_nudge(puzzle_id, text)`: a mentor's nudge (Progress passes `""` for a whole-crew nudge); stores it, emits `nudge_received` and `Events.hint_received(text)` |
| `Audio` | none | Muted until the start tap calls `unlock()`; `play(name)` no-ops on missing streams or `sound_on` false |
| `Router` | none | Section 5 |

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

**MergeCelebration:** "Patch submitted: <part>", Crab slides in with "Merged!" (1.2 s tween, tap skips). The first credited solve asks for a name on the keypad ("Add my name" / "Stay anonymous") and sets `name_asked`. Lists contributors; adds "<Machine> runs!" if `now_running`. Uncredited: "Crab merged the fix. Solve one yourself to get on the list."

**MachineView:** six 64 px rows, each a light plus text: "Broken" (grey), "Fixed by your crew" (amber), "Fixed by you" (green). Header "N of 6 parts working", or "Running!".

## 8. MatchingPuzzle (type `matching`)

Its config is `{machine, domain, answer, clues (collected only), total_clues: 6, threshold: 4}`.

**Layout, top to bottom:** "Which <item> goes in which <position_noun>?"; five 60 px slot rows; a tray (HFlowContainer) of five 48 px item chips; Check (enabled when full); scrolling ClueCards of collected clues under "Clues: N of 6 (4 needed)", or "Find your crewmates and enter their lucky words at the Teahouse."

**Input:** tap a chip (outline plus "Selected"), then a slot; tap a filled slot to return its item. Drag (`_get_drag_data`, `_can_drop_data`, `_drop_data`) calls the same `place(item, slot)`. Test API: `place`, `clear_slot`, `placement()`, `check()`.

`MatchingRules` (static): `is_solved(placement, answer)`, `fact_holds(fact, placement)`, `fact_to_text(fact, domain)`. A wrong Check says "Not quite. Read your clues again." and never how many are right (that would bypass clues).

**Hints:** `can_reveal()` needs 4 or more of this machine's clues collected. Level 1 marks one card "Start here", preferring a `position` fact. Level 2 states the first fact the placement breaks in plain words, trying styles security, code, hardware, trivia, poem, animal; repeats move on. Texts: "Sugar is in jar 1.", "Vanilla is in the jar right after flour's.", "Egg is 2 jars after butter." Level 3 fills the answer.

**HelperPuzzle** (type `helper`, WP3): config `{speaker, lines, question, choices, correct, nudge}`; lines advance per tap, then choices; right calls `finish()`, wrong gets a retry line. Hint 1 shows `nudge`; hint 2 removes a wrong choice.

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

**Switching it on.** `ScoreboardUrl.configured()` gives the base URL: the project setting `fortune/scoreboard_url` (committed empty, so the game is offline-only by default), overridden on the web build by `?scoreboard=https://host` in the page address (read once through `JavaScriptBridge`, a no-op off web; only `http(s)` URLs are accepted). Settings shows a "Use scoreboard" toggle (saved in `user://scoreboard.json`, on by default; disabled when no URL is set) and the configured URL read-only. Typing a URL on the in-game keypad is deliberately not offered.

**RemoteProgressStore.** Extends `ProgressStore`, wraps the local store and never blocks. The network is an injected `transport(method, url, body, done)` that ends with `done(status, data, retry_after)` (status 0 means no answer); `HttpTransport` (a Node with one `HTTPRequest` per request) is the real one and tests inject `FakeScoreboard`. With no transport it only queues, as in WP3.

- *Writes* (`set_display_name`, `join_crew`, `record_part_solved`) apply to the local store at once and append to `queue`, saved to `user://queue.json` with the id of the last hint seen per crew, whether this device is registered, and the machines known to run. They map to `POST /devices` (name or crew) and `POST /crews/{m}/parts/{p}/solve`. The queue is sent in order, one request at a time, which also meets the "flush before switching crews" rule. A network error, 5xx or 429 keeps the head and retries after a backoff of 2, 4, 8, ... up to 60 s (or `Retry-After`); `tick()` (a 1 s Timer in `Progress`) does the retry, and `flush()` ("Sync now") ignores the backoff. `403 not_in_crew` drops the solve (it stays in the local store, so this phone still shows it); `404 device_not_registered` inserts one registration first; any other 4xx is kept for retry but dropped after five refusals so a malformed write cannot block the queue. A first-time device with a name or crew queues one `POST /devices` (`set_identity`).
- *Reads.* Getters return at once: `get_crew_progress` is the per-part maximum of the local count and the last server `solved_count`; `get_contributors` lists the server's names (reversed to first-merged order, "anonymous" shown as "Anonymous") then any local name the server lacks; `get_contributor_entries` adds `via` (`solve` or `mentor`). `is_online()` is the outcome of the last request. Every cache change that differs emits `progress_changed`, and `Progress` turns that into `part_fixed` and `machine_running` as for local solves. The solve response's crew object also updates the cache.
- *Polling budget.* `refresh()` looks once at the player's crew, every watched machine, and (if hint polling is on) new hints. Nothing polls on its own: `Progress` calls `set_watching(machines, hints)` when the Router stack changes. A MachineView or CrewProgress on top watches that machine and hints; a PuzzleHost on top watches hints only; anything else watches nothing. `tick()` repeats `refresh()` every 10 s while something is watched. Also one look at boot, on `crew_changed`, and one `GET /contributors` when the Contributors screen opens.
- *Maintainer.* `server_runs(machine)` is true once a crew response said `runs`, remembered in the queue file. `Progress.is_maintainer()` is that for the player's crew; the Hud badge and the nudge section use it.
- *Hints.* `GET /hints?crew=&after_id=` for the player's crew; each new hint is emitted as `hint_arrived`, and `Progress` passes `Nudges.describe(hint)` to `Hints.receive_pushed_nudge("", text)`, which emits `Events.hint_received(text)` for the `HintBanner` (dismissible; later hints queue behind it). On the first look for a crew only the newest hint is shown, then `after_id` pages forward 50 at a time. `fetch_nudge_ids(done)` and `send_nudge(to_crew, nudge_id, done)` wrap `GET /hints/nudges` and `POST /hints`; the words for each nudge id live in `Nudges`.

**CrewProgress screen** (`scenes/screens/crew_progress.tscn`, reached from MachineView): "Machine runs!" or "N of 6 parts working", one row per part (light plus text: "Broken" or "fixed by N crewmates", "fixed on this phone" offline), contributors (mentors marked), and the line "Online, showing your whole crew" or "Offline, showing this phone only". Maintainers also get "Send a nudge": pick one of the other two crews, then a nudge from the server's list.

**Tests.** `test/fixtures/fake_scoreboard.gd` is the fake transport; `test_remote_progress_store.gd`, `test_scoreboard_url.gd` and `test/scene/test_scoreboard_screens.gd` cover queue persistence, order, drops and retries, cache and offline getters, polling cadence, hints, URL parsing and the screens. No test opens a socket.
