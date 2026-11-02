# Phone smoke test

A 20 to 30 minute check of the real web build on a real phone. Nobody has run the game on a phone yet; the desktop browser run (Chromium, 390x844, touch) found no errors, so this list is about what only a phone shows: touch feel, Safari quirks, memory, and venue Wi-Fi. Do it on **iPhone Safari** and on **Android Chrome**, once each.

Mark each item `[x]` for pass or `[!]` for fail, and write what you saw on the note line. A fail needs a note: what you tapped, what you expected, what happened. A screenshot helps.

## Addresses

- **Game (GitHub Pages build):** `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/`
  The pattern is `https://<owner>.github.io/<repository>/`. It exists only after the first deploy from `main` and after Pages is switched on (Settings > Pages > Source: GitHub Actions).
- **Game with a scoreboard:** add `?scoreboard=<server address>` after the game address, for example
  `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/?scoreboard=https://scoreboard.example.org`
  Use `https` (a phone browser blocks a plain `http` scoreboard from an `https` page). The server must list `https://johnsonfarmsus.github.io` in its `CORS_ORIGINS`. The override lasts for that page load only, so keep the `?scoreboard=` in the address you bookmark.
- **Big screen:** `<server address>/bigscreen/` on a laptop, to watch the phones' progress.

## Before you start

- Use a private tab, or clear site data first, so the phone starts as a new player.
- Note the phone model and OS version: ______________________
- Note the browser and version: ______________________
- Note the network (venue Wi-Fi, home Wi-Fi, mobile data): ______________________

## 1. Loading and start

- [ ] Page loads on venue-like Wi-Fi (not your fastest connection). Time from tapping the link to "Tap to start": ______ seconds. Over 20 seconds is a fail; the build downloads about 10 MB.
  Note: ______________________
- [ ] The title screen fits the phone with nothing cut off, in portrait. Rotating the phone does not break it.
  Note: ______________________
- [ ] Tap to start works on the first tap, and the Lucky word screen appears.
  Note: ______________________

## 2. Walking around

Tap "Back" on the Lucky word screen to see the town.

- [ ] Tapping empty ground walks the yellow "You" square there; tapping again redirects it.
  Note: ______________________
- [ ] Tapping **Teahouse** (Red Panda) walks there and opens the Lucky word screen.
  Note: ______________________
- [ ] Tapping **Pier** (Crab) walks there and opens the Contributors list.
  Note: ______________________
- [ ] Tapping **Shop** walks there and opens the shop with the three machines. The **Town** button comes back.
  Note: ______________________
- [ ] The top bar (crew name, Clues, Menu) is easy to hit and not hidden under the browser's toolbar or the iPhone notch.
  Note: ______________________

## 3. The six Cookie Machine lucky words

On the Lucky word screen, type each word with the in-game keys and tap Enter. (The browser keyboard must not pop up.) The first word you enter also puts you in the Cookie Machine crew.

| Word | Pass | Note |
| --- | --- | --- |
| `SPRINKLE` | [ ] | |
| `HUDDLE` | [ ] | |
| `TUX` | [ ] | |
| `CIPHER` | [ ] | |
| `PATCH` | [ ] | |
| `SOLDER` | [ ] | |

- [ ] Each word shows "Clue collected!" and the first one also says you joined the Cookie Machine crew.
  Note: ______________________
- [ ] Typing a word again says "You already have that clue." A made-up word says it is not on any cookie.
  Note: ______________________
- [ ] Keys are big enough: no mistyped letters while tapping at normal speed; Delete removes one letter.
  Note: ______________________
- [ ] **No cookie?** After a reset (section 10), pick a crew with one of the three buttons under "No cookie? Choose a crew:" instead of typing a word. It joins that crew.
  Note: ______________________

## 4. Clue board

- [ ] "Clues N" opens the clue board; the Cookie Machine shows "N of 6, 4 needed (your crew)".
  Note: ______________________
- [ ] Every clue is readable without zooming. "Help me read this" shows a plain nudge.
  Note: ______________________

## 5. Solve the batter puzzle with four clues

Collect four of the six words. In the Shop, tap the Cookie Machine, then the first part ("Logic": the batter recipe).

- [ ] The batter puzzle opens with five jars and five ingredients and shows your four clues below.
  Note: ______________________
- [ ] Tap an ingredient, then tap a jar to place it; tapping a filled jar swaps or clears it. Check enables when all jars are filled.
  Note: ______________________
- [ ] A wrong answer says so and lets you try again without losing your place.
  Note: ______________________
- [ ] A right answer ends the puzzle.
  Note: ______________________

## 6. Hint ladder and reveal

Use a second part or reset first if you already solved the batter puzzle.

- [ ] "Hint" gives a first hint; each further tap gives a stronger one.
  Note: ______________________
- [ ] On the last rung, "Hint" asks "Reveal the answer? You will not get credit." with Reveal and Keep trying. Keep trying closes it with nothing revealed.
  Note: ______________________
- [ ] Reveal shows the answer and says "Answer revealed. No credit this time."
  Note: ______________________

## 7. Merge celebration and display name

- [ ] After a real solve, "Patch submitted: ..." plays and Crab says one of his merged lines (for example "Merged! Your fix is in. Clack clack!").
  Note: ______________________
- [ ] The first merge shows Crab explaining a pull request, then asks "Want your name on the contributors list?"; type a name on the in-game keys (up to 20 characters) and tap "Add my name". "Stay anonymous" works too, and it is not asked again.
  Note: ______________________
- [ ] The name appears in the Contributors list at the Pier. After a revealed solve, you are not listed (Crab says "Solve one yourself next time, and I'll add your name to the list.").
  Note: ______________________

## 8. All six Cookie Machine parts

Open each part from the Cookie Machine view and solve it (with hints if needed). Check that each is playable with a thumb.

- [ ] Logic (batter recipe)
  Note: ______________________
- [ ] Wiring
  Note: ______________________
- [ ] Sequence
  Note: ______________________
- [ ] Word
  Note: ______________________
- [ ] Rhythm (tap in time: check the timing feels fair on this phone)
  Note: ______________________
- [ ] Helper (the machine's helper character asks you to choose; this is the dialogue part)
  Note: ______________________
- [ ] After the fourth part the Cookie Machine **runs**, and the shop fixtures turn from "off" to "on" as parts are fixed.
  Note: ______________________

## 9. One Fortune Machine part and one Oven part

Switch crew in Menu (Settings) or type words from the lists below, then try one part from each. Fortune Machine words: `INKWELL`, `SQUAWK`, `COPYLEFT`, `SHIFTY`, `STDOUT`, `PINOUT`. Oven words: `TOASTY`, `MIGRATE`, `TARBALL`, `HEXDUMP`, `LAMBDA`, `FUSEBOX`. (These come from `game/data/puzzles/*.json`.)

- [ ] A Fortune Machine part opens, can be solved, and merges.
  Part tried: ______________  Note: ______________________
- [ ] An Oven part opens, can be solved, and merges.
  Part tried: ______________  Note: ______________________

## 10. Settings

- [ ] Menu opens Settings: name, crew buttons, sound switch, Source code (AGPL) link, Reset this device.
  Note: ______________________
- [ ] Switching crew changes the top bar and keeps your clues and solves.
  Note: ______________________
- [ ] Sound on/off works (the first tap on the start screen is what allows audio on iPhone; check that sound plays after it).
  Note: ______________________
- [ ] "Source code (AGPL)" opens the GitHub repository.
  Note: ______________________
- [ ] "Reset this device" asks for confirmation ("Yes, reset" and "Cancel"); Yes forgets name, clues, crew and solves; Cancel does nothing.
  Note: ______________________
- [ ] Reload the page mid-game: progress, name and crew are still there (saved on the phone). In a private tab this may not hold; note it.
  Note: ______________________

## 11. Scoreboard (open the game with `?scoreboard=`)

Needs a running scoreboard server. Open the big screen on a laptop.

- [ ] Menu > Scoreboard shows the address, "Use scoreboard" is on, and "Sync now" works.
  Note: ______________________
- [ ] After entering a word, the crew member count on the big screen goes up within about 10 seconds.
  Note: ______________________
- [ ] A solved part lights up on the big screen. "See crew progress" (in the machine view) says "Online, showing your whole crew" and lists the parts fixed by crewmates.
  Note: ______________________
- [ ] **Maintainer badge:** when your crew's machine runs (four parts), the top bar shows "Maintainer".
  Note: ______________________
- [ ] **Nudge:** as a maintainer, "Send a nudge" lets you pick another crew and a nudge; on a second phone in that crew a banner shows the nudge and can be dismissed.
  Note: ______________________
- [ ] Turn the server off or put the phone in airplane mode: the game keeps playing. Turn it back on and "Sync now" sends what waited.
  Note: ______________________

## Result

- Overall: [ ] pass  [ ] pass with notes  [ ] fail
- The three worst things: 1. ______________________  2. ______________________  3. ______________________
