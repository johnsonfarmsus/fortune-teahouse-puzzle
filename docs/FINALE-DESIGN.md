# Finale design (WP9)

Status: approved by the integrator on 2 Nov 2026 with two amendments (start_tick range 0 to 3 so the only valid start is tick 0; code normalisation stated). Trevor's four questions in section 10 are open and do not block implementation.

Binds WP12 and WP16. Every point is decided; quoted strings are exact.

## 1. Timeline and gating

- **Open and availability** are the server's. Safety net: **18:00 local, day one**. A handoff waits only for the machines it touches (`oven_to_packaging`: the Oven only).
- **Phone gate:** a handoff's puzzle also needs both notes it `needs`. Notes are the cross-crew gate; facts make it quick.
- **FinaleView** (Shop's new "The line" button): three handoff rows "<name>: <status>" (tap opens HandoffHost), a notes row (opens the Archive), the start-code row.
- **Before it opens**, FinaleView shows: "The gnu ran the handoffs between his machines by hand and never wrote down how. Once all three machines run, everyone connects them into one line. Opens when they all run, or at <safety-net time, e.g. 6:00 pm> at the latest." Then "<Machine>: running" or "<Machine>: N of 6 parts working". Archive and handoff words already work.
- **No scoreboard:** "The finale is played together on the event scoreboard. Open the game from the event link to join in." **Unreachable:** cached `/finale`; writes queue.

## 2. Handoff notes and handoff words

A player gets their crew's note when its machine runs, or on joining a running crew. Each note prints a **handoff word**; typing it on the Lucky word keypad collects the note. Gopher's packing slip is free once the finale is open.

**Cookie Machine note**, `BATTERBOWL`: "You got my Cookie Machine going! Thank you, and sorry about the mess. The Oven folk will need two things from you. Every round comes off my press 9 cm across. One bowl of batter makes 24 rounds, then the press runs dry. – G."

**Fortune Machine note**, `PAPERCHUTE`: "You fixed my Fortune Machine. I knew someone would. For the Oven: fresh ink must dry for 1 tick before a strip goes down the chute, or it smudges. The chute takes 2 ticks to reach the end of the Oven. – G."

**Oven note**, `GOLDENROUND`: "The Oven runs again, bless you. I never wrote this down, so here it is. The baking tunnel is 120 cm long, and a round bakes in exactly 40 seconds. Leave 6 cm of bare belt between rounds. A warm round reaches the folding arms at tick 3, then every 4 ticks, and its fortune must land right then. Cooled cookies leave by three chutes: chute 1 the extra crisp ones, chute 2 the golden ones, chute 3 the soft ones. – G."

**Gopher's packing slip**: "Seagull wants the extra crisp ones for the rooftop basket. Red Panda wants golden ones for the teahouse tins. Crab's little claws need soft ones, packed in the pier crate. Penguin and Elephant have already had theirs. – Gopher"

ClueBoard shows them first, under "Handoff notes", each ending in large type "Handoff word: GOLDENROUND. Share it with someone from another crew." Keypad results: "Handoff note collected! See it under Clues." / "You already have that note."

## 3. The handoff puzzles

One new component, **`dials`** (`scenes/puzzles/dials_puzzle.tscn`, logic in `DialRules`), in a new **HandoffHost** screen. One dial = one server setting; three per handoff.

**Layout:** per dial: label, "−", value (`labels[i]` or `values[i]` plus `unit`), "+" (48x48), state tag; a live preview; the test button (`test_label`). A test locks each right dial ("Set" plus a check; emits `setting_set(setting_index)`) and shows the others' `low`/`high` (ordered, by index) or `wrong`. All locked: `finish()`. No timers, no fail state.

**Hints:** level 1 `hints[0]`; level 2 the first unlocked dial's `hint`; level 3 `reveal()` locks the rest (emitting `setting_set`), then `solved(false)`. Revealed settings still post: progress, not credit.

**Test API:** `step(id, delta)`, `set_value(id, v)`, `values()`, `locked()`, `test_run() -> {id: ok|low|high|wrong}`. `configure` takes `locked_indices` from FinaleState.

**Previews** (shape plus word): `belt`: rounds "burnt"/"golden"/"raw" for dial 0 low/ok/high, spacing "touching"/"even"/"gappy" for dial 1, a bowl "overflowing"/"full"/"empty" for dial 2. `beats`: two rows of `ticks` numbered cells, "Arms ready" lit at `targets`, "Fortune lands" lit at `start + dry + chute_ticks + k*every` (k ≥ 0, below `ticks`); cells lit in both show a check and "folded"; while dry is below its answer, fortune cells show "smudged". `routes`: a line from each chute to its package, dashed until locked.

### Cookie Machine to Oven (rate), preview `belt`

intro: "Penguin's rounds drop onto the Oven belt. Set the belt, the press and the bowl so every round comes out golden." Test: "Run a test batch". Dials `belt_speed`, `press_every`, `bowl_every` (index, label and unit, values):

0. Belt speed, cm per second: 1–6, answer **3**. Low "Too slow: the rounds come out burnt." High "Too fast: the rounds come out raw." Hint "120 cm in 40 seconds. How far each second?"
1. Press: one round every, seconds: 3–8, answer **5**. Low "Too often: the rounds bump into each other." High "Too slow: big gaps on the belt." Hint "A round plus its bare belt is 9 + 6 cm."
2. New bowl every, minutes: 1–6, answer **2**. Low "Too soon: the bowl overflows." High "Too late: the press runs dry." Hint "24 rounds, one every 5 seconds."

### Fortune Machine to Oven (timing), preview `beats`

`{kind: "beats", ticks: 12, targets: [3, 7, 11], chute_ticks: 2, roles: {every: "print_every", dry: "dry", start: "start_tick"}}`. intro: "Each printed fortune must land on a warm round just as the arms fold it. Line up the two rows." Test: "Run a test batch". Dials (index, label and unit, values):

0. Print a fortune every, ticks (`print_every`): 2–6, answer **4**. Low "Too often: fortunes pile up." High "Too slow: some rounds get no fortune." Hint "How often does a round reach the arms?"
1. Let the ink dry, ticks (`dry`): 0–3, answer **1**. Low "Too short: the ink smudges." High "Too long: the strip misses its round." Hint "How long does fresh ink need?"
2. Start printing at tick (`start_tick`): 0–3, answer **0**. Low "Too early: the fortune lands on a bare belt." High "Too late: the round has cooled and cracks." Hint "Work back from tick 3: take away drying and chute time."

### Oven to packaging (routing, with Gopher), preview `routes`

Unordered dials `chute_1` to `chute_3`, "Chute 1 goes to" (answer `rooftop_basket`), "Chute 2 goes to" (`teahouse_tin`), "Chute 3 goes to" (`pier_crate`). Values and labels: `rooftop_basket` "Seagull's rooftop basket", `teahouse_tin` "Red Panda's teahouse tin", `pier_crate` "Crab's pier crate", `shed_box` "Penguin's shed box", `archive_drawer` "Elephant's archive drawer". wrong: "Gopher frowns: that's not who wants these." hints: "What comes down chute 1? Then who wants those?", "Chute 2 carries the golden ones.", "Soft cookies, for little claws." intro: "Gopher's paws are full. Send each chute to the package that's waiting for it." Test: "Send a test cookie".

### Progress mapping

`setting_set(i)` → `FinaleState.add_setting(handoff_id, i)` → queued `POST /finale/handoffs/{id}/settings {device_id, setting_index: i}` (idempotent). `403 finale_closed` and `409 handoff_waiting` keep the write until a poll shows it `available`; `404 device_not_registered` first sends `POST /devices {device_id, display_name, crew}`. HandoffHost header: "Settings set by everyone: N of 3. On this phone: M of 3." On `finish()`: "<Handoff>: connected on this phone. Elephant adds a page to the README." and Continue.

Gate messages: "You need <note title>. Find someone from the <crew> crew and ask for their handoff word." / "This handoff waits for the <machine>." / locked: "The finale hasn't opened yet."

## 4. The gnu's notes and Elephant's Archive

**N = 6, k = 4.** A code is a word plus two digits, printed with a space ("KETTLE 27"), typed on the Archive's LetterKeypad. Codes are normalised before comparing and before posting: uppercase, spaces removed ("KETTLE27"), which is also the form in the server's `GNU_NOTE_CODES`. Codes ship in game data (leaks are fine) and are checked locally, so they work offline and early; valid ones queue to `POST /finale/notes`.

Each note has an **in-game twin** for remote and no-venue players: a `helper` puzzle started from its Archive slot once the finale is open. Solving it files the note.

Default venue spots; twin speaker, question, choices (correct first, shuffled in data):

- `note_1` KETTLE 27, Registration desk sign. Red Panda: "How many sugars did the gnu take in his tea?" Three / One / None
- `note_2` GULLWING 41, Seagull hidden in the welcome slides. Seagull: "Where did the gnu hide his spare key?" Under the bait bucket / In the Oven / In the till
- `note_3` DRIPCOFFEE 08, Hallway-track coffee. Crab: "What does Crab do with every fix?" Merges it / Hides it / Eats it
- `note_4` CROSSWIND 63, Big-screen stand. Penguin: "Which way does the Cookie Machine's belt run?" Towards the Oven / Towards the sea / In circles
- `note_5` INKBLOT 19, Session schedule board. Gopher: "What does Gopher never pack?" A warm cookie / A cold cookie / A map
- `note_6` SALTWATER 52, Info and swag table. Elephant: "What does Elephant keep?" The town records / The cookies / The keys

Twin `lines` state the answer. A note's `text` is one gnu line plus its code, e.g. "Note to self: the registration desk always runs out of pens. Bring more. – G. Code: KETTLE 27".

**Archive** (new Town hotspot `Hotspots/Archive`):
- Elephant: "I keep the town's records. The gnu left notes all over the place. Bring me any you find."
- "Notes found by everyone: F of 6 (4 needed). On this phone: P."
- Keypad, "Type the code from one of the gnu's notes." Results: "Elephant files it. Thank you!", before open "Elephant files it. It goes in when the finale opens.", "Elephant already has that one.", "That isn't one of the gnu's notes. Check the code."
- Six slots: the text if found, else "Somewhere at the venue, or ask <speaker>." and, once open, "Ask <speaker>".
- "README so far".

LuckyWordEntry on an unknown word adds: "If it's from one of the gnu's notes, take it to Elephant at the Archive."

## 5. Pack A meets Pack B, and the closing reveal

**Start code** `3141592653` (server default). FinaleView's last row, once `line_ready`: "The line is ready! The start code is the lucky numbers from the backs of two cookies, Pack A then Pack B." with a keypad; otherwise "Start code: the line isn't ready yet." Anyone may enter it, online only. Results: "Wrong code. Read both cookie backs again." / `409`: "The line isn't quite ready yet." / "The line is running!"

On `started` FinaleView reads "The line is running!" and ClueBoard gains "The gnu's last fortune".

**Big-screen reveal** (on `started`, `?replay=1` or key R; any key skips): "Starting the line…" over "3.141592653" (3 s); "Fortune Machine: printing", "Cookie Machine: pressing", "Oven: baking", "Gopher: packing" light in turn (2 s each); "The first cookie is out." (3 s); it opens: "You figured out what I never wrote down. It's yours now. – G." (8 s); "The Anglerfish snaps his briefcase shut and swims off. Nobody took the free trial." (4 s); the full README scrolls; then S4.

**README**, "# The gnu's shop: README", subtitle "Written by everyone who fixed it, because I never did. – G." Sections appear as their triggers hold. Handoff sections publish the settings on purpose: written down, anyone can run the line.

1. **Fortune Machine** (machine runs): "Five phrase banks feed the printer, one line each. Each ink tube goes to the nozzle with its letter. Print, dry, send down the chute."
2. **Cookie Machine** (runs): "Dry first, then wet, then mix and rest. The motor controller turns the mixer. The press thumps with the conveyor's beat."
3. **Oven** (runs): "Five heat zones bake the rounds through the tunnel. Each thermostat lead goes to the port its sticker names. Bake, drop the fortune, fold warm, cool, package."
4. **Cookie Machine to Oven** (connected): "Belt at 3 cm a second. One round every 5 seconds. A fresh bowl every 2 minutes. Every round comes out golden."
5. **Fortune Machine to Oven** (connected): "Print every 4 ticks, dry for 1, start at tick 0. With the 2-tick chute, every fortune lands as the arms fold."
6. **Oven to packaging** (connected): "Chute 1, extra crisp, to Seagull's rooftop basket. Chute 2, golden, to the teahouse tins. Chute 3, soft, to Crab's pier crate. Gopher takes it from there."

Closing: "## Maintainers", "Not one gnu. All of you:", then every contributor name.

## 6. Mentors, no-cookie players, late joiners

- **Mentors** keep nudging unfinished crews, and carry words: FinaleView shows maintainers "Your crew's handoff word: <WORD>. Share it!"
- **No-cookie players** choose a crew and can do everything except read a cookie back.
- **Day-two late joiners** join a running crew from a lost-fortunes-jar word, get its note at once, can still solve parts for credit, and play the whole finale.

## 7. Server and data

**API deltas: none.** Event config: `HANDOFF_SETTINGS_TOTAL=3`, `GNU_NOTE_CODES=KETTLE27,GULLWING41,DRIPCOFFEE08,CROSSWIND63,INKBLOT19,SALTWATER52`, `GNU_NOTES_K=4`, `FINALE_SAFETY_NET_AT=<day one>T18:00:00<offset>`. Server work: the static big-screen page and `server/static/bigscreen/readme.json`, a copy of the game's.

**Game:** core classes `FinaleData`, `FinaleState`, `FinaleClient`, `DialRules`; autoload `Finale` after `Progress`, polling `GET /finale` at boot and every 15 s while FinaleView, HandoffHost or Archive is on top, transport injected as in WP7. `FinaleState` saves `user://finale.json` `{version, notes_held, settings: {handoff_id: [indices]}, gnu_notes, queue, cache}`; device reset clears it.

`game/data/finale/handoffs.json`: `{schema_version, notes: [{id, title, handoff_word, free, text}], handoffs: [{id, title, needs, type: "dials", config}]}`. Note ids: `cookie_machine`, `fortune_machine`, `oven`, `gopher` (`free: true`, `handoff_word: ""`). `needs`: `cookie_to_oven` `["cookie_machine", "oven"]`, `fortune_to_oven` `["fortune_machine", "oven"]`, `oven_to_packaging` `["oven", "gopher"]`. Dials `config`: `{intro, test_label, preview, hints, dials: [{id, setting_index, label, unit, ordered, values, labels, start, answer, low, high, wrong, hint}]}`. `start` is the initial index: 3 for `start_tick` and the chute dials, else 0 (never the answer). `hints[0]`: "Read both notes side by side. Everything you need is in them."

`game/data/finale/gnu_notes.json`: `{schema_version, needed: 4, notes: [{id, code, venue, text, twin: {speaker, config}}]}`, `config` a `helper` config.

`game/data/finale/readme.json`: `{schema_version, title, subtitle, sections: [{id, heading, trigger: {"machine_runs": id} | {"handoff_connected": id}, body}], closing: {heading, line, fortune}}`.

## 8. Big-screen states

- **S0**, not `open`: "Finale locked: it opens when all three machines run, or at <time>." Crew progress below.
- **S1**, `open`: "The finale is open: make the line run!" Handoff rows, "Gnu's notes: F of 6 found (4 needed)", README so far.
- **S2**, `line_ready`: "The line is ready! Find a Pack A cookie and a Pack B cookie: the start code is on their backs."
- **S3**, on the `started` transition or a replay: the reveal.
- **S4**, `started`: "The line is running! The machines belong to everyone who fixed them." Full README and contributors.

Rows: "<name>: not started", "<name>: N of 3 settings", "<name>: connected", "<name>: waiting for the <machine>" (from `summary.crews`, joined by " and "), "<name>: locked". `admin_closed` drops "or at <time>".

## 9. Tests

**Unit:** `test_dial_rules.gd` (marks; answers lock all; `start` never the answer; beats answers hit `targets`). `test_finale_data.gd` (indices exactly 0 to 2; `needs` name real notes; six unique codes matching `^[A-Z]+ [0-9]{2}$`; 21 lucky and handoff words unique; six valid README triggers). `test_finale_state.gd` (round trip, idempotence, reset). `test_finale_client.gd` with `FakeScoreboard` (posts, 403/409 kept then resent, 404 registers first, polls only while watched).

**Scene:** DialsPuzzle (lock signals, `solved(true)`, reveal, `locked_indices`, 44 px); HandoffHost messages; handoff words; Archive codes (valid, repeat, invalid, before open, twin); FinaleView states; ClueBoard notes.

**Pytest:** the two `readme.json` files are equal.

## 10. Questions for Trevor

1. Will organizers allow the six physical notes at these spots?
2. Who runs the big screen and the admin secret on day two?
3. Is 18:00 on day one right for the safety net?
4. Start whenever ready (default), or on stage at closing with a Pack A and a Pack B holder?
