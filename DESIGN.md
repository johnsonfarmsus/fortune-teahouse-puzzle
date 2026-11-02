# The Fortune Teahouse: SeaGL Puzzle Game Design

Nov 1, 2026 · @Trevor Johnson · revised Nov 2, 2026 (the world, game feel, art and sound)

## Overview

The Fortune Teahouse is a collaborative puzzle game for SeaGL 2027. It starts with custom fortune cookies handed out at TeaGL and ends with the whole conference finishing a shared puzzle at the closing session. Attendees play in a phone browser, form crews by the fortune they got, and fix a retired gnu's fortune cookie machines by pooling clues no one can solve alone.

**Audience:** everyone at SeaGL, from kernel maintainers and hardware hackers to hobbyists who have never written code.

**Design principles**

- **Nobody wins alone.** A single fortune is never enough; every machine needs clues from several people.
- **Anyone can finish.** Each crew can always win using only the non-technical clues. Technical clues are shortcuts and conversation starters, not gates.
- **Every crew gets every kind of puzzle.** Developers, hardware people and riddle-lovers all have something to do in every crew.
- **There is always a path to the end.** Thresholds (any 4 of 6 clues, any k of N of the gnu's notes) mean a missing person or a lost cookie never blocks a win.
- **About 40 to 60 minutes of play per player,** in short bursts between talks over day one, plus a conference-wide finale on day two. TeaGL itself is only a 30 to 40 minute tea break, so it is the kickoff, not the whole game.
- **Built entirely through GitHub.** Godot project as plain text, cloud sessions write the code, CI proves every puzzle is solvable, every merge deploys. Free software under the GNU AGPL.

## Story and characters

The story is about the maintainer who left, not a villain. On a little seaside pier, an old gnu ran a fortune cookie shop for decades. He built every machine himself, kept them running alone, and has finally retired to migrate somewhere warm. He left behind three machines nobody else understands and no documentation. Now the line is jammed, the fortunes coming out are scrambled, and the town is in a muddle.

The fortune in each attendee's real cookie is one of those scrambled fortunes, so the physical cookie belongs to the story.

**Characters.** Each character is one animal, named after its species (Gnu, Seagull, Crab), with only one of each animal in the game. Wherever possible the animal is a nod to an open-source project. Their game role is a job, not a name. All are original designs inspired by these animals, not the projects' official mascot artwork.

Nobody in town has the whole manual, but lots of characters hold a piece of it. That is the point of the story: no consistent, well-understood documentation, just many people with bits of knowledge.

| Character | Open-source nod | Game role | What they know and do |
| --- | --- | --- | --- |
| Gnu | The GNU Project | Retired maintainer | Built and ran every machine alone. Appears only through notes, voicemails and sticky labels. Apologetic, brilliant, disorganized. |
| Seagull | SeaGL itself | Collector of lost fortunes | Has gathered fortunes that were dropped or thrown away around the Fortune Machine, so knows some fortunes exactly and has big gaps everywhere else. Specific but limited knowledge. |
| Penguin | Linux (Tux) | Cookie Machine helper | Practical tinkerer who knows the Cookie Machine's moving parts but not the gnu's settings. |
| Gopher | Go's gopher, and the old Gopher protocol | Courier | Runs packaging and delivery at the end of the Oven. |
| Crab | Rust's crab, known for a newcomer-friendly community | Apprentice | A young crab from the pier who "merges" every fix and keeps the contributors list. |
| Elephant | PostgreSQL's (and PHP's) elephant | Archivist | Keeps the town records and collects the gnu's scattered notes during the finale. |
| Red Panda | Firefox (a "fire fox" is a red panda) | Teahouse keeper | Runs the teahouse where players meet; the game's hub. |
| Anglerfish | None, on purpose | FortuneCloud salesperson (comic relief) | Dangles a glowing "FREE TRIAL" lure, offers to replace the machines with a subscription service, and carries a clamshell briefcase that never opens. Leaves for good when the line runs. |

**The ending:** the machines no longer belong to one gnu. They belong to everyone who fixed them. The point is the bus factor, told warmly: no project should rest on one person.

## How it plays at SeaGL

Three crews each fix one machine, starting at TeaGL and carrying on through day one; when all three run, a conference-wide finale opens for the rest of the event. TeaGL is a 30 to 40 minute tea break held at about 3:30pm on both days of SeaGL (in 2026, Fri-Sat Oct 23-24 at the UW HUB; the 2027 dates are not yet announced).

**Crews.** Each of the 18 fortunes belongs to one machine. Entering a fortune's lucky word in the game puts the player in that crew: Fortune Machine, Cookie Machine or Oven. With roughly 33 cookies per crew, crewmates are scattered across the room, so the first job is getting up and finding them.

**No cookie, no problem.** The whole game is playable without a cookie. Players can explore, solve side puzzles and join a crew by teaming up with cookie holders.

**Fast finishers become mentors.** Once a crew's machine runs, its members become "maintainers": the game lets them send hints to other crews, and their names go on those crews' contributors lists too. The people who finish first spend the rest of day one helping.

**Latecomers.** About 10 cookies are held back in a "lost fortunes" jar at registration for day two. The handful is drawn at random from the mixed pile, not stacks of one fortune, so no machine is left short.

**Two-day timeline**

1. **TeaGL on day one (30 to 40 minutes, about 3:30pm):** the kickoff. Cookies come out, crews form and the first clues get pooled.
2. **Rest of day one:** crews fix their machines in short bursts between talks (40 to 60 minutes of play per player in all); finished players mentor.
3. **When all three machines run** (or at end of day one as a safety net): the finale opens: making the three machines work together as one line.
4. **Day two:** the whole conference works out the handoffs between machines. TeaGL on day two is a second chance for latecomers, who draw from the lost fortunes jar.
5. **Closing session:** the full line runs end to end on the big screen and the first cookie comes out.

If the organizers would rather kick off on day two, the finale shrinks to fit the remaining hours.

### Rules the code needs

These are the rules the game and the scoreboard are built on.

- **Everyone solves on their own device.** Every player solves each part for themselves, so everyone plays. A crew's machine runs when each of its six parts has been solved by at least one crew member. Progress syncs through the scoreboard; offline, the device shows its own progress (device-local) and syncs later.
- **Crew assignment.** The first lucky word a player enters sets their crew; later words only collect clues. A player can switch crews from the menu, and players with no cookie choose a crew.
- **Lucky words will leak.** They will be said aloud, and that is fine: finding people is the only gate. There is no anti-cheat.
- **Hint ladder.** Nudge, then a stronger nudge, then reveal the solution without credit. Maintainers (see above) can push one nudge to another crew.
- **Contributors list.** Names go on a big screen, so the list uses a display name the player chooses, and anonymous is allowed.

## The world: a town to explore

The game lives in the town, not the shop. The machines sit in the gnu's shop, but almost nothing needed to fix them is there: clues and puzzles send players around town to find the parts, tools and knowledge each repair needs. That is what makes it a full world, and what makes room for dead ends and misdirects.

**Three things to find**

- **Parts:** physical pieces, such as a cutter die, a mixer belt, a heat-zone dial or an ink cartridge.
- **Tools:** things that let you repair or install a part, such as a spanner from Penguin or the gnu's key ring.
- **Knowledge:** settings, codes and how-tos, from fortunes, the gnu's notes, signs and what characters remember.

**The town**

| Place | Who is there | What you find there |
| --- | --- | --- |
| Teahouse | Red Panda | The hub: lucky-word entry, crew meetups, gentle hints |
| The gnu's shop | Nobody; the gnu's sticky labels | The three machines and what each one is missing |
| The pier | Crab, Seagull | The contributors board; Seagull's nest of lost fortune scraps, some useful, some outdated |
| Penguin's workshop | Penguin | Tools, and a bench for repairing bent or broken parts |
| Parcel depot | Gopher | Lockers, misdelivered parcels, the gnu's forwarded mail |
| Town archive | Elephant | Records and old manuals, some for older versions of the machines; the gnu's notes during the finale |
| The gnu's cottage | Nobody | Locked drawers, half-finished notes, things he forgot to pass on |
| Scrapyard | Nobody | Look-alike parts: the home of misdirects |
| Harbour | Anglerfish | Shiny FortuneCloud "replacement parts" that never quite fit |

**Example chain: the Cookie Machine's cutter**

1. The cutter is missing its die. A sticky label says: "Die out for sharpening. – G."
2. Penguin says the gnu never sharpened anything at the workshop: "Try the depot, he mailed everything."
3. At the depot, a parcel addressed to the gnu sits in a locker with a code lock. The code comes from the crew's fortune clues, or a lucky find in Seagull's scraps.
4. The parcel holds the die, but it is bent.
5. Misdirects along the way: the scrapyard has a die that looks right but has the wrong number of teeth; Anglerfish offers a gleaming FortuneCloud die with a connector that fits nothing.
6. Straighten the die on Penguin's bench, a hands-on physical interaction.
7. Install it at the machine: drag the die into place and tighten it. The cutter starts stamping rounds.

Each machine has six chains like this, one per puzzle type in the table below. The puzzle happens wherever it belongs in the chain: a lock at the depot, a wiring job in the workshop, a smudged manual in the archive.

**Rules for dead ends and misdirects**

- **They cost time, never progress.** Nothing is lost for good, no choice is permanent, and wrong parts can be put back.
- **Fair in hindsight.** Every misdirect has a tell: the wrong tooth count, "v1" on an old manual, a date on a scrap.
- **On theme.** Outdated docs (Seagull's old scraps, the archive's manual for an older model), lock-in (Anglerfish's parts) and knowledge nobody wrote down.
- **Never a trap.** Red Panda's hint ladder gets anyone out of a dead end within a couple of minutes.
- **Still approachable.** No misdirect can only be spotted with technical knowledge.

**Wrong answers that lead somewhere.** A handful of puzzles, about one or two per machine, have a tempting wrong answer that sends players to the wrong place instead of simply saying "wrong".

- **Each decoy comes from one believable mistake:** trusting one of Seagull's outdated scraps, misreading a cipher, following the archive's manual for the older model, or skipping a clue.
- **Decoys lead to real places:** the harbour (Anglerfish's lock-in pitch), the scrapyard, the archive's old-manual shelf, or a drawer in the gnu's cottage.
- **The wrong place explains the mistake** and points back toward the right path. A drawer might hold a note: "Not this one. I changed it after the flood. – G."

Example: at the depot, a locker code from Seagull's scrap is out of date. The locker screen flashes "Code changed. Parcel forwarded: HARBOUR." At the harbour, Anglerfish offers a FortuneCloud die "compatible with all your old codes." The date on his forwarding slip is newer than Seagull's scrap, which is the tell: the scrap was old, so the real code has to come from the crew's fortunes.

**Exploring together.** Each crew shares an inventory through the scoreboard: a part one crewmate finds appears for the whole crew, with "found by" credit. Crews naturally split up to search different places and call out across the room. Without the scoreboard, everything can still be found alone.

**Where the fortunes fit.** Fortune clues still solve each machine's core logic puzzle, and they also point around town: where to look, which part is the real one, what a lock's code is.

## Game feel

The game should feel like a hands-on adventure, not a form. These requirements apply to every scene and every pull request, because an agent cannot play the game and will leave feel out unless it is spelled out.

- **Direct manipulation.** No puzzle is played mainly through buttons or lists. Players drag, turn, pull and tap things in the scene. Items are used by dragging them from the inventory onto what they act on.
- **Feedback on every action.** Every tap answers within a tenth of a second with a sound, an animation or both. A success gets a bigger moment: sparks, steam, a clunk, a short camera shake.
- **A world that moves.** The player is a walking character, not a block. Characters idle and walk. Water, lanterns, gulls and steam give every place ambient motion.
- **Scenes, not screens.** Places are walkable scenes joined by paths and doors, with a camera that follows the player. Menus are only for settings, the inventory and the clue board.
- **Machines come alive part by part.** Each fix starts its piece moving. A fully repaired machine runs on its own, with cookies visibly moving through it.
- **Physics where it is fun.** Cables that sag and swing in wiring puzzles, parts that tumble into bins, cookies sliding along conveyors, and the finale's line simulation.
- **Characters talk.** Portraits with expressions, short lines, tap to continue.
- **NES-style pixel art.** See Art and sound. Art is loaded by filename, so better art can replace placeholders without changing the gameplay.
- **Sound everywhere.** An effect for every interaction and a quiet ambient loop per place, unlocked by a tap-to-start screen on phones.
- **Smooth on real phones.** Aim for 60 frames per second, never below 30, on a mid-range Android and a recent iPhone, within the existing download budget.
- **Accessibility as an option, not the default.** A text-assist mode lists interactive objects and offers button alternatives for anyone who needs them.
- **Judged by a person.** Every gameplay pull request includes screenshots or a short capture, and Trevor plays each slice on a phone before the next one starts.

## Art and sound

The game looks like an NES-era top-down Zelda: pixel art on a 16×16 grid with a strict palette. Open CC0 tiles set the style, Trevor's local AI stack on the steam-machine fills the gaps, and a script turns everything into true pixel art so it all looks like one game.

**The look**

- **Top-down, 16×16 tiles.** Characters are 16×16 or 16×32 sprites.
- **Room by room.** Each place is one screen; walking off an edge slides to the next. Doors lead into interiors.
- **One strict palette** for the whole game, based on the Ninja Adventure pack, with at most 3 colours plus transparency per sprite.
- **Chunky and readable,** with 2 to 4 animation frames per action.
- **Inspired by, not copied.** No Link, Triforce, Zelda item sprites, fonts or map layouts. One nod is fine: Red Panda hands over the first tool with "It's dangerous to code alone."
- **Godot does the rest:** tilemaps, palette-swap shaders for crew colours and dusk lighting, flip-screen transitions, pixel sparks and steam, an optional subtle retro-screen filter.

**On a phone**

- **Portrait rooms** about 11 tiles wide and taller than they are wide, scaled up by whole numbers with no smoothing. The inventory and dialogue box use the space above and below.
- **Tap to walk** by default, with an optional on-screen D-pad.
- **Repairs zoom in** to larger pixel-art close-ups, so hands-on puzzles still have room.

**Where the art comes from**

| Asset | Source | Notes |
| --- | --- | --- |
| Base tiles: ground, water, buildings | [Ninja Adventure pack](https://pixel-boy.itch.io/ninja-adventure-asset-pack) (CC0); Kenney 16×16 packs (CC0) | Also the style and palette reference for everything else |
| Props, items, machine parts | Text-file sprites in the repo, or generated and pixelized | A text sprite is a grid of characters, one per pixel, turned into an image by the build |
| The 8 characters | Generated reference, pixelized, then hand-polished in Pixelorama | Walk frames by hand; poses and expressions by editing the approved reference |
| Dialogue portraits, machine close-ups, title screen | Generated on the steam-machine, pixelized | Where AI generation works best |
| Concept art and mood boards | Generated | Reference only, not shipped |
| Trailer | MiniMax H3 on the steam-machine | For SeaGL and the blog |

**The generation pipeline**

1. **Pinned, cleanly licensed models only:** Z-Image-Turbo and Qwen-Image-2512 for images, Qwen-Image-Edit-2511 for edits, all Apache 2.0. Newer Qwen-Image releases (2.1 and later) carry a research-only license, so no upgrades without a license check.
2. **Generate large** on the steam-machine through ComfyUI or the pairvis media API.
3. **Pixelize with one script,** `tools/art/pixelize.py`: shrink to the sprite grid, lock to the game palette, remove the background, add the outline. Every asset goes through it.
4. **Consistency through edits.** One approved reference image per character; new poses and expressions are edits of that image, never fresh generations.
5. **Hand cleanup** in Pixelorama where needed.
6. **Finished sprites go in the repo;** raw generations stay on the steam-machine.

**Sound**

- **Sound effects:** classic retro blips and clunks generated by a script, with their settings committed.
- **Music:** FamiStudio for true NES-style tracks; ACE-Step 1.5 on the steam-machine for quick drafts.
- **Ambience:** Stable Audio 3, sparingly, where it suits the 8-bit look (Stability AI Community License; outputs are ours).
- **No voice acting.** Text dialogue with short per-character babble beeps, as on the NES.

**Provenance**

- `ASSETS.md` lists every asset with its source (pack, text sprite, generated, hand-made), license and author.
- Generated assets are labelled AI-generated, with model, prompt, seed and ComfyUI workflow file kept in `art-src/`.
- Pixel-boy and AAA (Ninja Adventure) and Kenney are credited, even though CC0 does not require it.

**Who does what**

- **Cloud sessions write code.** The game loads art by filename from the asset list and shows placeholders until each real file lands, so art and code never block each other.
- **Claude on Trevor's Mac makes art and audio** on the steam-machine and opens art pull requests. It follows the steam-machine access brief: one render at a time on the B70, and free ComfyUI's memory after a batch if the model lane needs it.

## The three machines

The gnu's shop is one production line made of three machines. A cookie moves through it like this:

1. **Fortune Machine** comes up with a fortune, prints it and sends it to the end of the Oven.
2. **Cookie Machine** mixes the batter and presses it into thin, flat rounds.
3. The raw rounds drop onto the **Oven** conveyor and ride through until perfectly baked.
4. As each warm round leaves the Oven, the printed fortune drops onto it. The timing matters: a cookie can only be folded while it is still warm.
5. The **Oven**'s folding arms fold the round around the fortune, and the cookie cools into its shape.
6. The finished cookie drops into its package.

This matches how real fortune cookies are made: baked flat first, then filled and folded while warm.

Each machine is a set of broken parts, and every machine has every puzzle type. All three core logic puzzles have the same shape: five items matched to five ordered positions (five jars, five phrase banks feeding five printer slots, five heat zones at five temperatures), so one solver and one puzzle scene serve all three.

| Puzzle type | Fortune Machine (composes and prints) | Cookie Machine (mixes and presses) | Oven (bakes, folds and packages) |
| --- | --- | --- | --- |
| Helper | Seagull | Penguin | Gopher |
| Logic | Which phrase bank feeds which line of a fortune | Batter recipe: which jar holds which ingredient | Which heat zone on the conveyor is set to which temperature |
| Wiring / hardware | Fix the ink pump circuit | Repair the mixer's motor controller | Rewire the thermostat |
| Sequence (code without typing) | Order the compose, print and send steps | Order the mix, rest and press steps | Order the bake, fold, cool and package stages |
| Word / poem | Fix the jumbled fortunes in the phrase bank | Decode the gnu's rhyming maintenance note | Restore the smudged packaging label |
| Pattern / rhythm | Tune the printer's rhythm | Sync the batter press to the conveyor beat | Time the folding arms to the warm cookies coming out |

Rhythm puzzles are visual-first (pulsing lights, a conveyor beat), with sound and haptics as optional extras, because the hall is loud and phones are muted.

**Where the fortunes come in.** Each machine has one core logic puzzle that can only be solved with that crew's fortune clues: the phrase banks, the batter jars and the heat zones. The other parts are solvable in-game, with optional hints, so a player is never stuck waiting for clues.

**Fixing things changes the world.** Each repaired part visibly changes the shop: a light comes on, a gear turns, a character gets their right fortune back.

**Fixes are contributions.** Solving a part "submits a patch"; Crab, the apprentice, merges it and the player's name joins the contributors list. Non-coders learn what a pull request is without anyone explaining it.

## The fortune cookies

100 cookies with 18 different fortunes for $198, from Fortune Cookie Guy (fortunecookieguy.com; custom messages, individually wrapped): 3 machines × 6 clues, one clue in each of six styles. Each machine needs any 4 of its 6 clues.

**Vendor limits**

- Packs of 50 cookies; up to 9 different front messages per pack.
- One back message per pack (the same on all 50).
- 140 characters maximum on the front and on the back (confirmed with the vendor).

**Six clue styles, one of each per machine**

| Style | Who reads it easily | Notes |
| --- | --- | --- |
| Poem | Anyone | One rhyming couplet; hardest to fit in 140 characters |
| Penguin, gnu or seagull | Anyone | Animal fact or behaviour carries the clue |
| Open source trivia | Enthusiasts and up | Linux, GNU, licenses, community lore |
| Light security | Anyone, with the app's hint | ROT13, Caesar shift, short binary or hex |
| Code | Developers | One line: an assert or a condition |
| Hardware | Hardware people | Resistor bands, pins, chips, wiring |

The first four styles can always reach the 4-clue threshold alone, so a crew of non-coders can always finish. Code and hardware clues are shortcuts and backups. Each clue has an optional "help me read this" nudge in the app that never gives the answer away.

**Front format:** the clue plus a lucky word, which players type into the game to collect that clue and join its crew. The lucky word costs 13 to 20 characters, leaving about 120 for the clue.

**Sample set: the Cookie Machine's batter puzzle** (five jars, numbered 1 to 5 from left to right; which ingredient is in which jar?)

| Style | Front of fortune | Chars |
| --- | --- | --- |
| Security | ROT13 says: Fhtne vf va wne bar. Lucky word: CIPHER | 51 |
| Poem | Vanilla came first, then butter so near: one jar to the right, and the butter is here. Lucky word: SPRINKLE | 107 |
| Penguin | Like a penguin and her chick, sugar and flour stand close: sugar on the left, flour just beside. Lucky word: HUDDLE | 115 |
| Open source | Count the letters in the kernel Linus Torvalds wrote. That number is the egg's jar. Lucky word: TUX | 99 |
| Code | `assert jar.index("vanilla") == jar.index("flour") + 1` Lucky word: PATCH | 71 (73 if the backticks print) |
| Hardware | Read the jars like resistor bands, left to right: butter's band comes just before egg's. Lucky word: SOLDER | 107 |

Verified with a solver: any 4 of these 6 give exactly one answer, and no 3 are enough. The structure that makes this work is two clues that fix a jar outright plus four that link neighbouring jars into a chain; random clue sets almost never meet the rule. The real puzzle will use a shuffled answer, not the jars in order.

**Back message (one per pack)**

- Pack A: Fix the gnu's fortune machine! Play at fortune.ataary.com  Lucky numbers: 3 1 4 1 5 (83 characters)
- Pack B: Fix the gnu's fortune machine! Play at fortune.ataary.com  Lucky numbers: 9 2 6 5 3 (83 characters)

Together the lucky numbers are the first ten digits of pi (3.141592653), needed in the finale, which quietly makes people from both packs meet. The address is a placeholder.

**Distribution**

- Each pack holds 9 fortunes: 3 Fortune Machine, 3 Cookie Machine, 3 Oven. That is about 5 or 6 copies of each fortune.
- **Mix both packs together before handing out. This is a required step:** each pack holds only 3 of each machine's 6 clues, so a crew whose cookies all came from one pack could never collect more than 3 and could never finish.
- Hold about 10 back for the lost fortunes jar, picked at random from the mixed pile. Never hold back stacks of one fortune: two whole fortunes gone would leave a machine at exactly its 4-clue threshold.

**Budget**

| Item | Cost |
| --- | --- |
| 2 packs of 50 cookies with 9 fortunes each (2 × $69) | $138 |
| Back message on both packs (2 × $30) | $60 |
| **Total: 100 cookies, 18 fortunes** | **$198** |

## The finale: make the line run

Repairing the three machines is not enough: they still don't work together. The gnu ran the handoffs between them by hand and never wrote down how. On day two, the whole conference works out how to connect them into one running line, finishing at the closing session.

**The three handoffs**

1. **Cookie Machine to Oven:** each raw round drops onto the Oven conveyor, whose speed has to match the bake time, or rounds come out raw or burnt. A rate puzzle.
2. **Fortune Machine to Oven:** each printed fortune must land on a warm round the moment it leaves the oven, right before folding. Too late and the cookie has cooled and cracks. A timing puzzle between the printer and the oven.
3. **Oven to packaging:** each finished cookie must go to the right package. A sorting and routing puzzle, with Gopher.

**How it plays**

- **Cross-crew handoffs.** Each handoff connects two machines, so it needs people from both crews. Fixing a machine gives you a handoff note only your crew knows.
- **The gnu's notes around the venue** (with organizers' blessing): codes on the registration sign, a seagull hidden in a speaker's slides, one at the hallway-track coffee. Elephant, the archivist, keeps them in the game. Any k of the N notes are enough.
- **Pack A meets Pack B.** The line's start code is the combined lucky numbers from the backs of both cookie packs.
- **The README writes itself.** Every solved handoff adds a section to the README the gnu never wrote.
- **Big screen.** Shared progress shows live in a common area, e.g. "Cookie to Oven: connected. Fortune to Oven: 2 of 3 settings. Oven to packaging: not started."
- **Closing reveal.** The full line runs end to end on the big screen. The first cookie out holds the gnu's last fortune: *"You figured out what I never wrote down. It's yours now. – G."* The README is complete, and the machines belong to everyone who fixed them.

**Safety net:** if the machines are not all repaired by the end of day one, the finale opens anyway. Handoffs that touch an unfinished machine wait for it, while the others go ahead. Nobody misses the finale because one crew stalled.

## Technology and pipeline

The game is a 2D Godot project that nobody opens in the editor: cloud sessions write it as text, GitHub Actions tests and builds it, and every merge to main goes live on the web.

&#91;embedded content: build and play pipeline · checks gate every change\]

A failing check sends the work back to the session that wrote it; only passing changes reach the web build players open.

**Engine choices**

- **Godot 4.7.2-stable with GDScript,** pinned everywhere (engine, export templates, test action) and bumped on purpose. Scenes and resources are plain text, so agents can write them and every change is a readable diff.
- **2D, phone-first.** Tap-to-move town and touch puzzles. Web export uses Godot's Compatibility renderer (WebGL 2), which runs on most phones.
- **Web build only for SeaGL.** Attendees open it from the address on the cookie; no install, no app store.
- **Single-threaded web export** (thread support off), so it runs on GitHub Pages without special headers.
- **Tap-to-start screen** before anything else, so audio is unlocked by a gesture on phones.

**Repository layout**

| Path | What lives there |
| --- | --- |
| `game/` | The Godot project: scenes, scripts, art |
| `puzzles/` | Every clue as data: styled fortune text, lucky word, style, and the machine-readable fact it encodes |
| `tools/solver/` | Python solver and clue generator |
| `server/` | Scoreboard service and big-screen page |
| `tools/art/` | Pixelize script, text-sprite builder, sound-effect generator |
| `art-src/` | Prompts, seeds and ComfyUI workflow files for every generated asset |
| `ASSETS.md` | Source, license and author of every asset |
| `.github/workflows/` | CI checks, builds and deploys |

**What CI checks on every pull request**

- For each machine: every 4 of its 6 clues gives exactly one answer; no 3 do.
- The four approachable styles alone reach the threshold.
- Every fortune front and back is 140 characters or fewer.
- Lucky words are unique across all 18 fortunes. Every decoy answer follows from its named mistake and matches no valid set of clues.
- Godot imports headless, unit tests pass (GUT or gdUnit4), and a web export builds.
- Size budget: the exported web build fails CI above 12 MB uncompressed, and its gzip size is reported. About 100 phones will load it at once on venue Wi-Fi.
- A human (or reviewing agent) confirms each styled clue says what its fact says. The solver checks facts, not poems.

**Deploys:** every merge to main exports the web build and publishes it (GitHub Pages first; itch.io via butler optional).

**Scoreboard:** shared crew progress, the finale and the big-screen view need a small service and database. It will run on the existing Hetzner server. The game still plays if the scoreboard is down; only shared progress pauses.

**License:** the whole project is licensed under the GNU Affero General Public License, version 3 or later (AGPL-3.0-or-later). That covers the game, the solver and tools, the puzzle data and the scoreboard server. The repo carries the full license text in `LICENSE`, and each source file starts with an `SPDX-License-Identifier: AGPL-3.0-or-later` line. Because the scoreboard runs as a network service, the AGPL requires offering its source to players; the game and the big-screen page link to the public repo to do that.

## Cloud session plan

The live build plan is `PLAN.md`: dated, dependency-ordered work packages, each with a model assignment, inputs, outputs and acceptance criteria. The two prompts under "Next sessions" below are live and are mirrored there; the original five are kept for history.

### Original session prompts (superseded by PLAN.md)

The $250 credit expires Tuesday, November 4 at 11:59 PM PST, so it goes on the hard engineering: the foundation, the solver, the game shell, the machines and the scoreboard. Art, writing polish and characters can follow over the year on the normal plan.

**Before starting**

1. Create an empty GitHub repo (e.g. `fortune-teahouse`).
2. Export this doc as Markdown and commit it as `DESIGN.md`. Every prompt below points to it.
3. Start session 1 alone. When its branch is merged, start sessions 2, 3 and 5 at the same time. Start session 4 once session 3 is merged, since both build the game in game/.

If a session cannot download Godot in its own sandbox, it should still write the code and rely on CI to run Godot.

**Session 1: foundation (run first)**

```text
Read DESIGN.md. Set up the repository for a Godot 4.7 (GDScript) 2D web game built entirely through GitHub: create the folder layout in the Technology and pipeline section, a minimal Godot project in game/ with one placeholder scene, a puzzles/ data schema (YAML or JSON) for clues with fields for machine, style, lucky word, fortune text and a machine-readable fact, and GitHub Actions that import the project headless, run unit tests (gdUnit4 or GUT), export a web build with the Compatibility renderer, and deploy it to GitHub Pages on merge to main. License the project under the GNU AGPL-3.0-or-later: add the full license text as LICENSE and an SPDX-License-Identifier: AGPL-3.0-or-later header to every source file. Document how to run everything in README.md. Open a pull request.
```

**Session 2: solver, clue generator and puzzle checks**

```text
Read DESIGN.md, especially The fortune cookies section. In tools/solver/, write a Python solver and generator for the three machines' core logic puzzles (Fortune Machine phrase banks, Cookie Machine batter jars, Oven heat zones). For each machine produce 6 clues, one per style, where every 4 give exactly one answer and no 3 do; use the two-anchors-plus-chain structure described in the doc as a starting point, and shuffle the answer. Write all 18 fortunes into puzzles/ with styled text under 140 characters including the lucky word. Add CI checks for: the 4-of-6 rule, the four approachable styles reaching the threshold alone, the 140-character limit on fronts and both backs, and unique lucky words. Open a pull request.
```

**Session 3: game shell and the Cookie Machine, end to end**

```text
Read DESIGN.md. In game/, build the phone-first game shell in Godot 4.7: a small tap-to-move town with the gnu's shop, the pier and the teahouse; a lucky-word entry screen that collects clues from puzzles/ and assigns the player's crew; a clue board; the patch-and-merge flow where Crab (the apprentice) adds the player to a contributors list; and the Cookie Machine as a complete vertical slice with its batter logic puzzle wired to the Cookie Machine's fortune clues plus one in-game puzzle of each other type. Use placeholder art. Add tests for clue collection and puzzle completion. Open a pull request.
```

**Session 4: the Fortune Machine and the Oven**

```text
Read DESIGN.md, especially The three machines. In game/, build reusable puzzle components for wiring, sequence (drag-to-order steps), word/poem and pattern/sound puzzles, then build the Fortune Machine and the Oven with one puzzle of each type per the table, each machine's core logic puzzle reading its clues from puzzles/. Keep scenes as plain text, use placeholder art, add tests, and coordinate with the existing game shell rather than replacing it. Open a pull request.
```

**Session 5: scoreboard and big screen**

```text
Read DESIGN.md, especially The finale and Technology and pipeline. In server/, build a small scoreboard service with a database (deployable with Docker to a single Linux server) that tracks each crew's machine progress, the finale's handoff progress, the gnu's notes found, and the contributors list, with a simple API for the game. Build a big-screen web page that shows live progress for display in a conference hallway. Add a client in game/ behind a setting so the game still works offline. Include the finale safety-net unlock at a configurable time. Open a pull request.
```

**Watch the spend:** each session draws from the credit while it works. Check remaining credit after the first round; any left after Monday can go to a second round on whatever needs the most work.

### Next sessions

**Rebuild: the town and one full chain (after phase 1)**

The first build delivered solid plumbing (solver, fortunes, game state, scoreboard, CI) but a menu-style game layer. The next step is one focused session, not a fleet of workers, that rebuilds the player-facing layer as a vertical slice. Trevor plays it on a phone before anything else is built on it.

```text
Read DESIGN.md, especially The world, Game feel and The three machines, and game/ARCHITECTURE.md. The current game works but plays like a set of menus: the town is coloured rectangles and the puzzles are button lists. Rebuild the player-facing layer as a hands-on 2D adventure, keeping what already works underneath: puzzle data, the solver, game state, the scoreboard client and CI. Scope this pull request to a vertical slice: (1) a walkable town with the teahouse, the gnu's shop, the pier, Penguin's workshop, the parcel depot and the scrapyard as connected scenes, a walking player character and a camera that follows; (2) characters with idle animation and portrait dialogue; (3) a drag-to-use inventory shared by the crew through the existing scoreboard client; (4) the Cookie Machine as an animated contraption whose parts visibly start working as they are fixed; (5) one complete chain, the cutter die, as in the example chain, including the scrapyard and Anglerfish misdirects and the outdated-locker-code decoy that leads to the harbour, plus the batter-jar logic puzzle rebuilt as dragging jars onto the shelf. Use the NES pixel style in Art and sound: Ninja Adventure tiles for the town, and art loaded by filename from the asset list with placeholders where a file has not landed yet. Give every interaction a sound, generated in code or by a script in the repo. Meet every Game feel requirement. Keep the old screens reachable behind a debug setting until the slice replaces them. Keep all tests passing and add tests for the chain logic. Include screenshots in the pull request where possible. Open a pull request.
```

**Local art and audio session (Claude on Trevor's Mac)**

Runs alongside the cloud sessions, on the normal plan rather than the credit, because only a machine on Trevor's network can reach the steam-machine. Give it the steam-machine access brief along with this prompt.

```text
Read DESIGN.md (especially Art and sound, The world and the character table) and the steam-machine access brief. You are the art and audio session for the fortune-teahouse-puzzle repo, working from Trevor's Mac with SSH access to the steam-machine. Setup: (1) get the Ninja Adventure asset pack (CC0; if it cannot be downloaded automatically, ask Trevor to download it) and choose the game palette and tile scale from it; (2) write tools/art/pixelize.py (shrink to the sprite grid, lock to the palette, remove the background, add the outline) and a build step that turns text-file sprites into PNGs; (3) rewrite docs/ART-BRIEF.md for the NES pixel style, replacing the flat sticker style, with an asset list (file name, size, frames, scene) the game code loads by filename; (4) create ASSETS.md for provenance. Then produce for review: an approved reference image for each of the 8 characters (generated with Qwen-Image-2512 or Z-Image-Turbo, pixelized, with prompt, seed and ComfyUI workflow saved in art-src/), the tiles for the town slice, and sound effects for walking, picking up, using an item, success and failure. Use only the pinned models in DESIGN.md. Follow the access brief: one render at a time on the B70, free ComfyUI memory after each batch, never edit /opt. Open one pull request per batch, and stop for Trevor's review after the character references.
```

## Open questions and next steps

- [x] Which day is TeaGL, and roughly how many people attend? Answered: TeaGL is 30 to 40 minutes at about 3:30pm on both days, so the kickoff is day one's. Attendance is still a rough guess (sponsor prospectuses say 400+ over two days, in person and online).
- [x] Pick a cookie vendor. Answered: Fortune Cookie Guy (fortunecookieguy.com).
- [x] Is 140 characters really the limit? Answered: yes, confirmed for both fronts and backs.
- [ ] Confirm with Fortune Cookie Guy that the two cookie packs can carry different back messages. If not, the pi digits move elsewhere in the finale.
- [ ] Confirm SeaGL organizers are happy with the game, cookies at TeaGL, codes around the venue and a big screen.
- [ ] Pick the game's address (fortune.ataary.com is a placeholder).
- [ ] Note allergens on or near the cookies (they usually contain wheat and egg), and get a written allergen statement from the vendor.
- [ ] Choose how many of the gnu's notes to hide around the venue (N) and how many the finale needs (k).
- [ ] Order cookies with enough lead time once all 18 fortunes pass CI and a human read-through.
- [ ] Art style and original character designs (after the credit; normal plan).
