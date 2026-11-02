<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Puzzle data

This folder holds the three machines' core logic puzzles and the 18 fortune-cookie
fronts that carry their clues, plus the two cookie backs. The game reads these files;
`tools/solver` checks them in CI (`.github/workflows/puzzle-checks.yml`).

**Spoiler warning.** The machine files contain the answers. That is fine for a
cooperative game in a public AGPL repo, but CI never prints them: the checker's output
names machines, clue ids and subset ids only.

## Files

| File | What it is |
| --- | --- |
| `schema.json` | JSON Schema (draft 2020-12) for a machine file; `$defs/backs` covers `backs.yaml` |
| `cookie_machine.yaml` | Cookie Machine: five ingredients in jars 1 to 5, left to right |
| `fortune_machine.yaml` | Fortune Machine: five phrase banks feeding printer slots 1 to 5, top to bottom |
| `oven.yaml` | Oven: five temperatures (120 to 200 C) set on heat zones 1 to 5 along the conveyor |
| `backs.yaml` | The two back messages (one per pack) and the finale start code |

## The schema in words

A machine file has:

- `machine`: a stable `id` (`cookie_machine`) and a display `name`.
- `domain`: the puzzle shape (decision D3: always 5 items matched to 5 ordered
  positions). `items` are 5 ids with display names; `positions` are indexes 1 to 5 with
  labels; `order` says which way positions run ("left to right", "top to bottom", "along
  the conveyor"); `item_noun` and `position_noun` name them for the game's UI.
- `generator`: the seed that produced the shuffled answer, so it can be regenerated.
- `answer`: item id to position index. Shuffled, never the listed item order.
- `clues`: exactly six, one per style. Each clue has
  - `id`, e.g. `oven_poem`;
  - `style`: `poem`, `animal`, `trivia`, `security`, `code` or `hardware`;
  - `approachable`: true for the first four styles, false for code and hardware;
  - `fortune_text`: the exact printed front, ending in ` Lucky word: WORD`;
  - `lucky_word`: 3 to 8 capital letters, unique across all 18 fortunes;
  - `fact`: what the clue means, machine-readable. Either
    `{kind: position, item, position}` ("item is at position") or
    `{kind: offset, item, relative_to, offset}` where offset `+1` means the item is
    immediately right of / below / after `relative_to` and `-1` means immediately left
    of / above / before it;
  - `nudge`: the optional in-app "help me read this" hint. It explains how to read the
    style and must never give the fact away;
  - `char_count`: the length of `fortune_text` (checked).

`backs.yaml` has two `packs` (`id`, exact `text`, `lucky_numbers`, `char_count`) and the
`start_code` `3141592653`: Pack A's numbers then Pack B's spell the first ten digits of
pi (decision D7). The address `fortune.ataary.com` is a placeholder.

### YAML subset

The solver is standard-library Python, so it reads a small YAML subset: block mappings
and sequences, comments, double- or single-quoted strings, integers, `true`/`false`.
Flow collections (`[...]`, `{...}`), block scalars (`|`, `>`), anchors and tags are
rejected. Quote any string that contains `: ` or ` #`. A test checks that every file
here parses identically with PyYAML.

## The rules

CI fails unless, for every machine:

1. **Any 4 of 6.** Every 4 of the 6 clues give exactly one answer, and no 3 do (every
   3-subset leaves at least two answers). A crew can always finish without the full set,
   and nobody finishes alone.
2. **Approachable four.** The poem, animal, trivia and security clues alone give exactly
   one answer, so a crew with no coders or hardware people can always finish. (Rule 1
   implies this; it is checked separately because it is the promise players rely on.)

Also checked: all clues hold for the declared answer and it is the only solution; the
answer is shuffled; one clue per style; the approachable flags; every offset clue states
its direction in words (right, left, before, after, above, below; a code clue may use an
explicit `+ 1` or `- 1`); fronts and backs fit the character limit; fronts are printable
ASCII; `char_count` is right; lucky words are unique across all 18; Pack A then Pack B
spells the start code.

**Character limit.** The vendor (Fortune Cookie Guy) prints 140 characters per side, the
default `vendor-140` profile. The limit stays a parameter: `--profile alt-99` checks the
99-character alternative. All fronts are 122 characters or fewer; twelve need trimming to
fit 99, which the report lists.

**Misreading report (informational).** The checker re-reads each offset clue as plain
adjacency ("next to, either order") and lists the 4-subsets that would stop being unique.
The current sets put both anchors and the two end links in the approachable styles, so a
misread direction never breaks the approachable four; each link breaks exactly one of the
ten 4-subsets that contain it.

## How the sets are built

Each set is two anchors plus a four-link chain over a shuffled answer: two `position`
facts fix the items in positions 1 and 5, and four `offset` facts tie each neighbouring
pair. Anchors anywhere other than the two ends fail the rules. The approachable styles
carry both anchors and the two links that touch them; code and hardware carry the two
middle links.

## Commands

From the repository root (the package lives in `tools/solver`):

```sh
PYTHONPATH=tools python -m solver check puzzles/                      # answer-free summary, exit 1 on failure
PYTHONPATH=tools python -m solver check puzzles/ --profile alt-99     # 99-character profile
PYTHONPATH=tools python -m solver report puzzles/ --json report.json  # full answer-free JSON report
python -m unittest discover -s tools/solver/tests -t tools            # tests
```

After any change here, regenerate the game's copy and commit it (CI fails if it is stale):
`PYTHONPATH=tools python -m solver export-json puzzles/ game/data/puzzles/`.

### Regenerating a machine

```sh
PYTHONPATH=tools python -m solver generate --items sugar,flour,butter,vanilla,egg --seed 2
```

This prints a verified answer and six facts (and so is a spoiler: never run it in CI).
List the items in the file's `domain.items` order so the seed reproduces the answer.
Then rewrite the six fronts by hand so each one says exactly its fact, record the seed
under `generator`, update `answer`, `fact` and `char_count`, and run the check. A link
can be written either way round (`flour` +1 from `butter` is the same as `butter` -1 from
`flour`); write the fact the way the text reads.

## Human read-through (required before ordering cookies)

The solver checks facts, not words. Before the fortunes are frozen, a human (Trevor)
reads every front and confirms it says its fact and nothing more, that the direction is
unmistakable, that the trivia answer is unambiguous, and that each nudge helps without
giving the fact away. Tick the clue-meaning checkbox in the pull request template for
every changed clue.

## The 18 lucky words

| Style | Cookie Machine | Fortune Machine | Oven |
| --- | --- | --- | --- |
| Poem | SPRINKLE | INKWELL | TOASTY |
| Animal | HUDDLE (penguin) | SQUAWK (seagull) | MIGRATE (gnu) |
| Trivia | TUX | COPYLEFT | TARBALL |
| Security | CIPHER (ROT13) | SHIFTY (Caesar shift) | HEXDUMP (hex) |
| Code | PATCH (Python) | STDOUT (C) | LAMBDA (Python) |
| Hardware | SOLDER (pin header) | PINOUT (ribbon cable) | FUSEBOX (thermostat pins) |

The Cookie Machine keeps the six lucky words of the `DESIGN.md` sample so the game shell's
tests can use them, but its clues and answer are new.
