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

## 0. The adventure slice (WP16)

Since WP16 the game opens in the adventure layer: a walkable pixel-art town. Sections 2, 5 and 8 below describe the old menu screens; to reach them, open **Menu > Old screens (debug)** (the game restarts into the old town; switch it off the same way). Everything here is played with placeholder art (labelled blocks) until the art session lands real files. For a quick jump while testing, add `?room=<id>` to the address (`teahouse`, `square`, `shop`, `workshop`, `depot`, `pier`, `scrapyard`, `harbour`).

**Look and feel**

- [ ] After "Tap to start" (and the Lucky word screen, Back), you are in the **Teahouse**: a pixel room with sharp, unblurred pixels, letterboxed, the inventory bar above (Clues, Menu) and the dialogue bar below. Nothing is cut off by the notch or the browser bar.
  Note: ______________________
- [ ] Every tap answers at once with a blip and a small ring where you tapped. With sound on, taps, steps, doors, pickups and dialogue all make sounds; with Menu > Sound off, nothing does.
  Note: ______________________
- [ ] Tapping the floor walks the player there (4 directions, legs moving); tapping again redirects. Red Panda, the lanterns and the kettle's steam move on their own.
  Note: ______________________
- [ ] Tapping **Red Panda** walks to her and she speaks in the dialogue bar with a portrait, typed out with beeps. A tap finishes the line, the next tap moves on. Her line is a hint for the next step of the cutter chain.
  Note: ______________________
- [ ] Walking out of the door at the bottom fades to the **Town square**; the camera follows as you walk down it. Walking off the left or right edge slides the screen to the **Scrapyard** or the **Pier**; the pier's bottom edge leads to the **Harbour**. Every way out leads back.
  Note: ______________________
- [ ] It feels smooth (no stutter while walking or sliding). Rough guess of smoothness: ______
  Note: ______________________

**The cutter-die chain** (Cookie Machine crew; enter four Cookie Machine lucky words first so the batter can be solved)

- [ ] **Shop.** The Cookie Machine is a contraption with a jar shelf, mixer, panel, the gnu's note, a cutter and a lamp; the parts not yet fixed look dull. Tapping the **cutter** shows the gnu's sticky label ("Die out for sharpening").
  Note: ______________________
- [ ] **Batter shelf.** Tapping the jar shelf zooms into a close-up. Drag each jar from the counter onto a shelf place; it tumbles and bounces into place with a clink. A jar dropped on a full place swaps it back to the counter. Five jars up checks itself: wrong wobbles and says "Not quite"; right glows and Crab's merge screen follows. Back in the shop the jars now stand on the machine's shelf, with a burst of sparks, a shake and a caption.
  Note: ______________________
- [ ] **Workshop.** Penguin says the gnu mailed everything and hands over a **spanner**; it appears in the inventory bar with a little pop. Tapping it says what it is and "Found by you".
  Note: ______________________
- [ ] **Misdirect: scrapyard.** Tapping the junk pile gives a look-alike die. Dragging it onto the cutter says it has 10 teeth, not 12. Dragging it back onto the junk pile puts it back.
  Note: ______________________
- [ ] **Decoy: Seagull's scrap.** On the pier, Seagull hands over an old scrap with a locker code. In the **Depot**, tapping the yellow locker opens its dials (tap the top or bottom of a dial, or drag it; then pull the handle). Seagull's code flashes "CODE CHANGED / FORWARDED: HARBOUR".
  Note: ______________________
- [ ] **Harbour.** Arriving after the decoy, Anglerfish pitches FortuneCloud and the forwarding slip explains that the scrap is from March, before the code changed, and that the code is in the batter. Anglerfish's shiny die, dragged onto the cutter, has a connector that fits nothing; dragging it back onto Anglerfish returns it.
  Note: ______________________
- [ ] **Locker, for real.** The gnu's label on the locker says the code is the jars of egg, vanilla and sugar. With the batter solved, that code opens the locker: a bent die.
  Note: ______________________
- [ ] **Bench.** Dragging the bent die onto Penguin's bench opens a close-up; tapping each marked tooth brings the mallet down (clang, sparks); when all are flat the die is straight and replaces the bent one in the bar.
  Note: ______________________
- [ ] **Install.** Dragging the die onto the cutter opens the bolts close-up; tap or drag the spanner over each bolt to turn it until all four are tight. Penguin cheers, Crab merges it, and back in the shop the cutter stamps rounds onto the belt.
  Note: ______________________
- [ ] Tapping an item, then tapping something in the room, uses it too (no dragging needed).
  Note: ______________________

**Shared inventory (with `?scoreboard=`)**

- [ ] On two phones in the same crew, an item one finds (the spanner, the bent die) shows up on the other within about 15 seconds, and tapping it there says "Found by a crewmate". Seagull's scrap and the look-alike dies stay on the phone that took them.
  Note: ______________________
- [ ] Offline, finds still work on the phone and reach the crew after reconnecting (Menu > Sync now).
  Note: ______________________

## 1. Loading and start

- [ ] Page loads on venue-like Wi-Fi (not your fastest connection). Time from tapping the link to "Tap to start": ______ seconds. Over 20 seconds is a fail; the build downloads about 10 MB.
  Note: ______________________
- [ ] The title screen fits the phone with nothing cut off, in portrait. Rotating the phone does not break it.
  Note: ______________________
- [ ] Tap to start works on the first tap, and the Lucky word screen appears (over the adventure layer; Back shows the Teahouse).
  Note: ______________________

## 2. Walking around (old screens)

Switch on Menu > Old screens (debug) first. Tap "Back" on the Lucky word screen to see the town.

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

## 12. Finale

Needs a running scoreboard with the finale settings (`GNU_NOTE_CODES`, `GNU_NOTES_K=4`, the start code) and at least two phones, each in a different crew, plus the big screen on a laptop. Open the game with `?scoreboard=` on every phone. To skip solving 18 parts, run the three machines from the admin side or with `tools/dev/finale_integration.gd` against a scratch server; to rehearse again, reset progress (`POST /api/v1/admin/reset`). Handoff words: `BATTERBOWL` (Cookie Machine note), `PAPERCHUTE` (Fortune Machine note), `GOLDENROUND` (Oven note). Gnu note codes: `KETTLE 27`, `GULLWING 41`, `DRIPCOFFEE 08`, `CROSSWIND 63`, `INKBLOT 19`, `SALTWATER 52`. Start code: `3141592653`.

- [ ] **Handoff notes appear when the machine runs.** When your crew's machine runs, Clues shows "Handoff notes" first with your crew's note, ending "Handoff word: <WORD>. Share it with someone from another crew." The maintainer line in The line says "Your crew's handoff word: <WORD>. Share it!"
  Note: ______________________
- [ ] **The line, before and after it opens.** Before all three machines run, Shop > "The line" says it opens when they all run (or at the safety-net time) and shows each machine's progress. Once it is open, it says "The finale is open: make the line run!" with three handoff rows, the notes row and the start-code row. The "The line" button is easy to hit (the gnu's voicemail marker next to it must not catch the tap).
  Note: ______________________
- [ ] **Share handoff words.** Tell a phone from another crew your word; on that phone type it on the Lucky word keypad. It says "Handoff note collected! See it under Clues." Typing it again says "You already have that note."
  Note: ______________________
- [ ] **Gate messages.** Opening a handoff without the second note says "You need <note>. Find someone from the <crew> crew and ask for their handoff word." Opening one while a machine it touches does not run says it waits for that machine.
  Note: ______________________
- [ ] **Dials and the test batch.** With both notes, the handoff opens with three dials, a preview, and "- / +" buttons you can hit with a thumb (48 px). Setting one dial right and tapping "Run a test batch" locks it ("Set - OK") and the others say too low or too high. The header counts "Settings set by everyone: N of 3. On this phone: M of 3." and the big screen shows the same count within about 5 seconds. Finishing all three dials shows "connected on this phone" and Continue. The hint ladder works and the last rung asks before revealing.
  Note: ______________________
- [ ] **Archive codes.** In Town, Archive (Elephant) takes a code from one of the six gnu notes with the keypad. A right code says "Elephant files it. Thank you!" and the count "Notes found by everyone: F of 6 (4 needed)" goes up on every phone; a repeat says Elephant already has it; a wrong one says it is not one of the gnu's notes. A code typed before the finale opens waits ("It goes in when the finale opens") and posts when it opens. A note's in-game twin puzzle files the note when solved without the answer being revealed.
  Note: ______________________
- [ ] **Start code.** When all three handoffs are connected and four notes are found, The line says "The line is ready!" and shows the keypad. A wrong code says "Wrong code. Read both cookie backs again." The right code says "The line is running!" on that phone, and the others show it within about 15 seconds. ClueBoard gains "The gnu's last fortune". The start code is online only: with no connection it is not sent or queued.
  Note: ______________________
- [ ] **Big screen.** At `<server address>/bigscreen/` the page goes from "Finale locked" to "The finale is open: make the line run!" (handoff rows, notes count), to "The line is ready!", then plays the reveal ("Starting the line..." over 3.141592653, the four machines lighting in turn, the gnu's message, the README) and settles on "The line is running!" with the full README and the contributors. `?replay=1` (or the R key) plays the reveal again and any key skips it.
  Note: ______________________
- [ ] **Offline and late joiners.** With the scoreboard off, settings and notes queue and send after "Sync now". A phone that joins a running crew late gets its crew's note straight away and can play the whole finale.
  Note: ______________________

## Result

- Overall: [ ] pass  [ ] pass with notes  [ ] fail
- The three worst things: 1. ______________________  2. ______________________  3. ______________________
