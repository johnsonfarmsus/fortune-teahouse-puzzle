# SPDX-License-Identifier: AGPL-3.0-or-later
"""Export puzzles/<machine>.yaml to game/data/puzzles/<machine>.json.

The JSON shape is the game's contract (game/ARCHITECTURE.md section 2):

* clue ids are "<machine>.<style>";
* fortune_text drops the " Lucky word: WORD" suffix;
* facts become {"kind": "position", "a", "value"} (pos(a) = value) or
  {"kind": "offset", "a", "b", "value"} (pos(a) = pos(b) + value).

Output is deterministic (sorted object keys, 2-space indent, trailing
newline), so re-running gives byte-identical files and CI can diff them.

Run: python -m solver export-json puzzles/ game/data/puzzles/
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from .core import POSITION, Fact
from .puzzlefile import LUCKY_SUFFIX, Machine, discover, load_machine


class ExportError(ValueError):
    pass


def _fact(fact: Fact) -> dict[str, Any]:
    if fact.kind == POSITION:
        return {"kind": "position", "a": fact.item, "value": fact.position}
    return {"kind": "offset", "a": fact.item, "b": fact.relative_to, "value": fact.offset}


def machine_to_json(machine: Machine) -> dict[str, Any]:
    if machine.errors:
        # field paths only, never values
        raise ExportError(f"{machine.path.name}: fix structural errors first ({'; '.join(machine.errors)})")
    clues = []
    for clue in machine.clues:
        suffix = LUCKY_SUFFIX + clue.lucky_word
        if not clue.fortune_text.endswith(suffix) or clue.fact is None:
            raise ExportError(f"{machine.path.name}: clue {clue.id} does not end with its lucky word")
        clues.append(
            {
                "id": f"{machine.id}.{clue.style}",
                "style": clue.style,
                "approachable": clue.approachable,
                "fortune_text": clue.fortune_text[: -len(suffix)],
                "lucky_word": clue.lucky_word,
                "fact": _fact(clue.fact),
                "nudge": clue.nudge,
            }
        )
    return {
        "schema_version": 1,
        "machine": machine.id,
        "title": machine.name,
        "puzzle_title": machine.puzzle_title,
        "domain": {
            "items": [item_id for item_id, _ in machine.items],
            "positions": [label for _, label in machine.positions],
            "position_noun": machine.position_noun,
        },
        "answer": dict(machine.answer),
        "clues": clues,
    }


def render(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def export_dir(puzzle_dir: Path, out_dir: Path) -> list[Path]:
    machine_files, _ = discover(puzzle_dir)
    if not machine_files:
        raise ExportError(f"no machine files in {puzzle_dir}")
    rendered = {}
    for path in machine_files:
        machine = load_machine(path)
        rendered[f"{machine.id}.json"] = render(machine_to_json(machine))
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for name, text in sorted(rendered.items()):
        target = out_dir / name
        target.write_text(text, encoding="utf-8", newline="\n")
        written.append(target)
    return written


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        print("usage: python -m solver export-json PUZZLE_DIR OUT_DIR", file=sys.stderr)
        return 2
    try:
        written = export_dir(Path(args[0]), Path(args[1]))
    except ExportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    for path in written:
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
