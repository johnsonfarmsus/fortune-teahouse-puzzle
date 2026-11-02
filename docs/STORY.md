# Story bible

The one-page reference for anyone writing words for The Fortune Teahouse. The design is
`DESIGN.md`; the text itself lives in `game/data/story/*.json` (format in `schema.json`),
checked by `python3 tools/dev/check-story.py`.

## Premise

On a little seaside pier, an old gnu ran a fortune cookie shop for decades. He built three
machines, kept them running alone, and has retired somewhere warm, leaving no documentation.
The line is jammed and the fortunes come out scrambled; the one in each attendee's real cookie
is one of them. Nobody in town has the manual, but lots of characters hold a piece of it.
Fixing the machines together, then working out the handoffs he did by hand, the town ends up
owning what one gnu used to carry. The point is the bus factor, told warmly: no project should
rest on one person. His last fortune: "You figured out what I never wrote down. It's yours now. - G."

## Voices

| Character | Voice | Sample |
| --- | --- | --- |
| Gnu (retired maintainer) | Only notes, voicemails, sticky labels. Apologetic, brilliant, disorganized; tangents in brackets, signs "- G.". Never a villain, never blamed. | "I write my maintenance notes in rhyme, so I'll remember them. I did not remember where I put them." |
| Seagull (lost fortunes) | Excitable collector, "Squawk!". Knows some things word for word and has big gaps, and says so happily. | "Some fortunes I know word for word. The rest? Not a feather of a clue." |
| Penguin (Cookie Machine) | Practical tinkerer, short sentences, tools and sounds, "Flap flap". Knows the parts, not the settings. | "The press should go thump. If it goes thunk, something's wrong." |
| Gopher (courier) | Folksy, unhurried, proud of the job; "Well, hello there!", "Ask me how I know." | "Every cookie gets a wrapper and a ride. That's my promise." |
| Crab (apprentice) | Young, eager, celebrates every fix, sideways jokes. Explains contributing in plain words. | "Merged! That's one more thing that isn't only in one head anymore." |
| Elephant (archivist) | Careful, gently formal, never forgets; files things where everyone can read them. | "We don't need every note. Just enough. That's the good thing about lots of people." |
| Red Panda (teahouse, hub) | Warm host, tea and cushions; sends people to find each other. | "Everyone here is missing a piece. That's how you find each other." |
| Anglerfish (FortuneCloud) | Comic salesperson: glowing FREE TRIAL lure, a stuck clamshell briefcase, terrible puns. Harmless; leaves graciously. | "The first month is free! The second month costs a fortune." |

## Tone rules

1. Warm. Mistakes are funny and forgivable, the gnu's most of all.
2. No villain. The problem is a missing manual, not a person. The Anglerfish is a joke, not a threat.
3. No insults, of characters, players, projects or companies. Never mock newcomers or anyone
   who asks for a hint; "stay anonymous" and "reveal" are always fine.
4. Jargon only when a character explains it in the same breath (Crab on pull requests).
5. No puzzle answers in story text, ever; hint at a part's story, not its solution.
6. Phone first: at most 3 lines per piece, about 90 characters per line, plain ASCII
   punctuation, American spelling.

## Text in this pass (WP10)

| File | What | Shown on |
| --- | --- | --- |
| `gnu.json` | 18 part notes, 6 town notes, the last fortune | PuzzleHost (first open), Town, Shop, big screen |
| `red_panda.json` | Welcome, no crew, has crew, machine runs, finale opens | LuckyWordEntry (the Teahouse) |
| `crab.json` | 8 merged lines, first contribution, name prompt, uncredited, Pier intro | MergeCelebration, Contributors |
| `helpers.json` | 3 idle lines each for Seagull, Penguin, Gopher | MachineView |
| `elephant.json` | Generic finale archive lines | Finale archive (WP9/WP12) |
| `anglerfish.json` | 6 timed town bits, farewell | Town |
| `interface.json` | Start tagline, 3 loading tips, Settings about | StartScreen, loading, Settings |
| `side_puzzles.json` | 6 side puzzle concepts (not shown in game) | For a later package |

## Content plan: still unwritten

- **Hooks before any of this shows** (scene code, a later Sonnet package): a `StoryText` loader
  and one dialogue box; a "seen" set in `GameState` for `first_visit`; the piece triggers in
  `schema.json`. New places and screens the text assumes: town spots for the noticeboard, pier
  bottle and Anglerfish; tappable counter and answering machine in the Shop; an idle timer on
  MachineView; a boot or loading screen for tips; the finale archive and big-screen reveal.
- **Finale (after WP9):** handoff intros and success lines, the README sections the gnu never
  wrote (one per handoff), the venue notes' wording (k of N), big-screen captions, the
  Pack A meets Pack B prompt for the start code.
- **Side puzzles (after a package picks them up):** in-scene text, hints and success lines.
- **Mentor flow:** a line from Red Panda or Crab when a nudge is sent or received.
- **Fixtures:** short world-change captions per part ("The ink pump hums."), one per part.
- **Later polish:** character art direction notes (WP11), accessibility read-through, a human
  read-through of every line on a 390 px phone.
