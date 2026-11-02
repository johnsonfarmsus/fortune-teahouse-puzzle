# Playtest protocol

Three playtests on real phones, each with one exit metric. Run the [phone smoke test](SMOKE-TEST.md) first. Plan entry: WP14 in [PLAN.md](../PLAN.md).

## Addresses

- **Game:** `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/`, plus `?scoreboard=<test server>` when a scoreboard is used.
- **Throwaway scoreboard:** local or staging, reset before every round. Never the event instance.
- **Big screen:** `<test server address>/bigscreen/` (round 3).

## 1. Goals and exit metrics

Exit metrics come from the observer sheets (section 4). If a round misses its metric, fix the blockers and repeat that round before the next.

| Round | Who and what | Goal | Exit metric |
| --- | --- | --- | --- |
| 1 | 4 to 6 people, one phone each, Cookie Machine only | Find usability blockers | Every player fixes a first part with zero interventions |
| 2 | 8 to 12 people, three crews, paper cookies, throwaway scoreboard | Crews form, pool clues, finish with mixed packs | Three of three machines running within 60 minutes of T0, zero interventions |
| 3 | Dress rehearsal: 8 to 12 cold players (none from rounds 1 or 2), scoreboard and big screen on | PLAN.md Phase 3 criterion | One crew's machine running within 60 minutes of T0, zero interventions |

**T0** is when the facilitator says "go" and every player has the start screen open. The round 3 finale is checked for a live feed, not timed.

**Intervention:** anything a facilitator says or does beyond section 3, including pointing at something the app shows and reloading a broken page. The note taker logs each one with its time.

## 2. Materials

- **Fortune slips, printed from the data.** Never retype a fortune. Load each `puzzles/*.yaml` with the solver's loader (`load_machine` and `load_backs` in `tools/solver/puzzlefile.py`) and print each `fortune_text` exactly as stored. Print backs from `puzzles/backs.yaml`. Round 1: the six Cookie Machine fronts. Round 2: two copies of each of the 18 fronts (36 slips), one on each pack's back. Spot-check three fronts against the YAML.
- **Game and scoreboard URLs** on a card at the table.
- **Timer:** a phone stopwatch the note taker can see. The game has no timers; this one is for observers.
- **Observer sheets** (section 4), one per player plus spares. Spare phones in private tabs, so each starts as a new player.
- **Answers stay closed.** The `answer` key in `puzzles/*.yaml` and `game/data/` is never opened during a session.

## 3. Roles and facilitator script

- **Facilitator:** runs the script and is the only person who speaks to players.
- **Observer:** one per two or three players (one per crew in rounds 2 and 3). Silent. Writes quotes word for word.
- **Note taker:** runs the timer, keeps the intervention log and files issues. Round 1 can combine two roles.

**Opening, read aloud:** "This tests the game, not you. If something confuses you, say so out loud. I will stay quiet unless you are stuck for five minutes or the app breaks. Tell me when you are on the start screen."

**Say at any time:** "What do you see, and what did you expect?" / "What have you tried?" / "Read that out loud."

**Never say:**

- What a clue means, its style, or what it refers to ("it is a rhyme", "that is ROT13").
- Which jar, slot or part an item belongs to, or "try one to the left".
- An answer, part of one, or whether a guess is right.
- Which machine a fortune or lucky word belongs to.
- Anything about hints beyond "the app has a hint on that screen".
- That the problem is the player's fault.

**Stuck rule:** after five minutes without progress, ask "What do you think the game wants next?" and write the answer down. Do not explain. If the app breaks, reload it and log an intervention.

## 4. Observer sheet

Copy this table once per player. Name players P1, P2 and so on, never by a real name. Times are minutes:seconds from T0; write `none` if it did not happen before the round ended, and `no` if the player stopped.

| Player | Time to first clue | Time to crew joined | Time to first part fixed | Time to machine running | Hints per part, P1 to P6 (N nudge, R reveal) | Moments of confusion (verbatim quote, time) | Device and browser |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

- **First clue:** the game accepts a lucky word and the clue appears on the clue board.
- **Crew joined:** the game shows the player's crew.
- **First part fixed:** the part's fix plays and the machine visibly changes.
- **Machine running:** each of the six parts has been solved by a crew member.
- **Quotes** are copied exactly, typos included. A stated answer becomes `[answer stated]`.

## 5. Post-session questions

Read aloud within five minutes of the player leaving; record answers on the sheet.

1. On a scale of 1 to 5, how clear was it what to do after your first lucky word? (1 = no idea, 5 = obvious)
2. Which clue style did you read first? (poem, animal, trivia, security, code, hardware, or none)
3. Did you talk to someone you did not know during the game? If so, about what?
4. On a scale of 1 to 5, how much did you need another player to progress? (1 = not at all, 5 = could not alone)
5. On a scale of 1 to 5, how much did you enjoy it?
6. Was there a moment you wanted to stop? What did you do next?
7. Accessibility: could you read every clue and tap every button at your text size, in your light, with one hand? What did not work?
8. If you could change one thing before SeaGL, what would it be?

## 6. From notes to issues

Every confusion quote becomes a GitHub issue or a documented decision before the next round starts.

- **Issues** use the bug template (`.github/ISSUE_TEMPLATE/bug.md`), with the verbatim quote under "Actual" and the round and player number. Never include puzzle answers.
- **Labels:** `playtest-1`, `playtest-2` or `playtest-3`, plus one severity tag (create the new labels once, beside `bug`):
  - `sev-1` blocks: progress needed an intervention. Fix before the next round.
  - `sev-2` confusing: progress happened after a long pause or a wrong turn. Fix before round 3.
  - `sev-3` polish: wording, layout, delight. Schedule later.
- **Decisions** are quotes the team keeps, for example "by design: lucky words leak, so no anti-cheat". Record the date, quote, reason and decider in the round's notes, and link any DESIGN.md change.

## 7. Consent and privacy

- **Before the first move**, say what the session is, that the game is being tested, that anyone may stop at any time, and that notes use display names only. A player who does not sign a consent card still plays, but no observer sheet is kept for them.
- **Display names only:** the names players chose for the contributors list (anonymous is allowed), or P-numbers. No real names.
- **No photos** of screens or people without permission for that photo.
- **Data stays local:** sheets and notes stay on the facilitator's device, not in the repository or a shared drive. Only issue text goes to GitHub. Delete sheets 30 days after the round, once issues are filed. Reset the throwaway scoreboard after each round.

## 8. Sign-off

Copy this list into each round's notes.

- [ ] Round ____ Date ____ Players ____ Crews ____
- [ ] Exit metric value ____ Target met: yes / no
- [ ] Interventions logged ____ (pointing at app hints ____)
- [ ] Every confusion quote filed as an issue or recorded as a decision
- [ ] Observer sheets deleted (date ____)
