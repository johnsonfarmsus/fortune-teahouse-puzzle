# Playtest protocol

Three playtests of the game on real phones, each with one exit metric. Humans play; this document says how to run them and what to do with what they say. Run the [phone smoke test](SMOKE-TEST.md) first. Its open failures become round 1 watch items. The plan entry is WP14 in [PLAN.md](../PLAN.md).

## Addresses

- **Game:** `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/`, with `?scoreboard=<test server>` added when a scoreboard is used.
- **Throwaway scoreboard:** a local or staging instance, reset before every round. Never point a playtest at the event instance.
- **Big screen:** `<test server address>/bigscreen/` (round 3).

## 1. Goals and exit metrics

Each round has one exit metric, read from the observer sheets (section 4). If a round misses its metric, fix the blockers and repeat that round before the next one.

| Round | Who and what | Goal | Exit metric |
| --- | --- | --- | --- |
| 1 | 4 to 6 people, one phone each, the Cookie Machine only | Find usability blockers: can a cold player get from a fortune to a fixed part? | Every player fixes their first part with zero interventions |
| 2 | 8 to 12 people, three crews, paper cookies, throwaway scoreboard | Crews form, pool clues and finish with mixed packs | Three of three machines running within 60 minutes of T0, with zero interventions |
| 3 | Dress rehearsal: 8 to 12 cold players (nobody from rounds 1 or 2), scoreboard and big screen on | Phase 3 exit criterion (PLAN.md): a cold group finishes a machine in under 60 minutes with no help | One crew's machine running within 60 minutes of T0, with zero interventions |

**T0** is the moment the facilitator says "go" and every player has the start screen open. Finale and big-screen behaviour in round 3 are checked for a live feed; they are not timed.

**Intervention:** any words or action from a facilitator beyond the script in section 3, including pointing at something the app shows and reloading a broken page. The note taker logs each one with its time.

## 2. Materials

- **Fortune slips, printed from the data.** Do not retype any fortune. Load each `puzzles/*.yaml` with the solver's own loader (`load_machine` and `load_backs` in `tools/solver/puzzlefile.py`) and print each clue's `fortune_text` exactly as stored; it already ends in ` Lucky word: WORD`. Print backs from `puzzles/backs.yaml` (Pack A or Pack B). Round 1: one copy of each Cookie Machine front. Round 2: two copies of each of the 18 fronts (36 slips), one copy on each pack's back. Spot-check three printed fronts against the YAML before the round. No print script exists in the repository yet; writing one is a separate task.
- **Game URL and scoreboard URL** on a card at the table, one for players and one for the facilitator.
- **Timer:** a phone stopwatch the note taker can see. The game has no timers; this one is for observers only.
- **Observer sheets** (section 4), one per player plus spares.
- **Phones:** a spare for anyone without one. Use private tabs, or clear site data first, so each phone starts as a new player.
- **Consent cards and pens** (section 7).
- **The answer sections of the data files stay closed.** The `answer` key in `puzzles/*.yaml` and `game/data/` is never opened during a session.

## 3. Roles and facilitator script

- **Facilitator** runs the script and is the only person who speaks to players.
- **Observer:** one per two or three players (one per crew in rounds 2 and 3). Silent. Fills the sheet and writes quotes word for word.
- **Note taker:** runs the timer, keeps the intervention log, watches the scoreboard (and big screen in round 3), and files issues afterwards. In round 1 one person can hold two roles.

**Opening, read aloud:** "This tests the game, not you. If something confuses you, say so out loud; that is the most useful thing you can do. I will stay quiet unless you are stuck for five minutes or the app breaks. Here is your fortune. Tell me when you are on the start screen."

**Say, at any time:**

- "What do you see, and what did you expect to happen?"
- "What have you tried so far?"
- "Read that out loud."
- "Tell me what you are looking at right now."

**Never say:**

- What a clue means, what style it is, or what it refers to ("it is a rhyme", "the penguin one", "that is ROT13").
- Which jar, slot or part an item belongs to, or "try one to the left".
- An answer, part of an answer, or whether a guess is right.
- Which machine a fortune or lucky word belongs to.
- Anything about the hint ladder beyond "the app has a hint on that screen", and never explain a hint.
- That the problem is the player's fault.

**Stuck rule:** after five minutes without progress, ask "What do you think the game wants you to do next?" and write down the answer. Do not explain. If the app breaks, reload it, log an intervention and note the time.

## 4. Observer sheet

Copy this table once per player. Write the player as P1, P2 and so on, never a real name. Times are minutes:seconds from T0; write `none` if the round ended before it happened and `no` if the player stopped.

| Player | Time to first clue | Time to crew joined | Time to first part fixed | Time to machine running | Hints per part, P1 to P6 (N = nudge, R = reveal) | Moments of confusion (verbatim quote, time) | Device and browser |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

- **First clue:** the game accepts the first lucky word and the clue appears on the clue board.
- **Crew joined:** the game shows which crew the player is in.
- **First part fixed:** the first part's fix plays and the machine visibly changes.
- **Machine running:** the crew's machine runs, meaning each of its six parts has been solved by a crew member.
- **Quotes** are copied exactly, including typos. If a player says an answer, write `[answer stated]` and move on.

## 5. Post-session questions

Read these aloud within five minutes of the player leaving the table, and write the answers on the sheet. Ask all eight.

1. On a scale of 1 to 5, how clear was it what to do after your first lucky word? (1 = no idea, 5 = obvious)
2. Which clue style did you read first? (poem, animal, trivia, security, code, hardware, or none)
3. Did you talk to someone you did not know during the game? If so, what about?
4. On a scale of 1 to 5, how much did you need another player to make progress? (1 = not at all, 5 = could not progress alone)
5. On a scale of 1 to 5, how much did you enjoy it?
6. Was there a moment you wanted to stop? What did you do next?
7. Accessibility: could you read every clue and tap every button at your phone's text size, in the light you were in, with one hand? What did not work?
8. If you could change one thing before SeaGL, what would it be?

## 6. From notes to issues

Every confusion quote becomes either a GitHub issue or a documented decision before the next round starts. No quote is left only in the notes.

- **Issues** use the bug template (`.github/ISSUE_TEMPLATE/bug.md`). Fill in device and browser, the steps, what was expected and what happened. Put the verbatim quote in "Actual", with the round and player number. Never include puzzle answers.
- **Labels:** `playtest-1`, `playtest-2` or `playtest-3`, plus one severity tag:
  - `sev-1` blocks: a player or crew could not progress without an intervention. Fix before the next round.
  - `sev-2` confusing: progress happened, but after a long pause or a wrong turn. Fix before round 3.
  - `sev-3` polish: wording, layout or delight. Schedule later.
  - Create the four new labels once, next to `bug`.
- **Decisions** are quotes the team keeps as they are, for example "by design: lucky words leak, so there is no anti-cheat" (DESIGN.md). Record each with the date, the quote, the reason and the person who decided. If it changes DESIGN.md, link the change.

## 7. Consent and privacy

- **Before the first move**, say what the session is, that the game is being tested, that anyone can stop at any time, and that notes use numbers and display names only. Hand out a consent card. A player who does not sign still plays, but no observer sheet is kept for them.
- **Display names only.** The contributors list shows names the player chose, anonymous is allowed. Notes, sheets and issues use P-numbers and those display names. No real names.
- **No photos** of screens or people without permission given for that photo. A screenshot of the game is fine if the player agrees and no other person is visible.
- **Data stays local.** Observer sheets and notes live on the facilitator's device, not in the repository and not on a shared drive. Only issue text goes to GitHub. Delete the sheets 30 days after the round, once their issues are filed and the exit metric is recorded.
- **Scoreboard data** from a playtest is deleted when the throwaway instance is reset after the round.

## 8. Sign-off

Copy this list into each round's notes.

- [ ] Round number: ____ Date: ____ Players: ____ Crews: ____
- [ ] Exit metric value: ____ Target met: yes / no
- [ ] Interventions logged: ____ (of which pointing at app hints: ____)
- [ ] Every confusion quote filed as an issue or recorded as a decision
- [ ] Observer sheets deleted (date: ____)
