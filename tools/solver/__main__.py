# SPDX-License-Identifier: AGPL-3.0-or-later
"""Command line: python -m solver {check,report,generate} ...

  check DIR [--profile vendor-140|alt-99]
      Run every check and print an answer-free summary. Exit 1 on failure.
  report DIR --json OUT [--profile ...]
      Same checks; also write the full (still answer-free) JSON report.
  generate --items a,b,c,d,e [--seed N]
      Print a new verified fact set for a domain. This DOES print the answer
      and facts: run it locally when writing clues, never in CI.
  export-json DIR OUT
      Write OUT/<machine>.json for the game (game/ARCHITECTURE.md section 2).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from .checks import DEFAULT_PROFILE, LIMIT_PROFILES, run_checks
from .export_json import main as export_main
from .generate import generate_facts


def _summary(report: dict[str, Any]) -> str:
    lines = [f"Puzzle checks (profile {report['profile']}: limit {report['limit']} chars, threshold {report['threshold']} of 6)"]

    def emit(prefix: str, checks: list[dict[str, Any]]) -> None:
        for c in checks:
            mark = "PASS" if c["passed"] else "FAIL"
            subjects = f" [{', '.join(c['subjects'])}]" if c["subjects"] and not c["passed"] else ""
            lines.append(f"  {mark} {prefix}{c['check']}: {c['detail']}{subjects}")

    lines.append("Global")
    emit("", report["global"])
    lines.append("Backs")
    emit("", report["backs"]["checks"])
    for m in report["machines"]:
        lines.append(f"Machine {m['machine']} ({m['file']}): {'PASS' if m['passed'] else 'FAIL'}, longest front {m['longest_front']}")
        emit("", m["checks"])
        over_99 = [c["id"] for c in m["clues"] if not c["fits"]["alt-99"]]
        if over_99:
            lines.append(f"  info: over the alt-99 profile: {', '.join(over_99)}")
        for mis in m["misreading"]:
            broken = mis["broken_subsets"]
            note = " (breaks the approachable four)" if mis["breaks_approachable"] else ""
            lines.append(
                f"  info: misreading {mis['clue']} as either-order breaks {len(broken)} of {mis['subsets_containing_clue']} 4-subsets{note}"
            )
    lines.append("RESULT: " + ("PASS" if report["passed"] else "FAIL"))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m solver", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "report"):
        p = sub.add_parser(name)
        p.add_argument("puzzle_dir", type=Path)
        p.add_argument("--profile", choices=sorted(LIMIT_PROFILES), default=DEFAULT_PROFILE)
        if name == "report":
            p.add_argument("--json", type=Path, required=True, help="where to write the JSON report")
    g = sub.add_parser("generate")
    g.add_argument("--items", required=True, help="comma-separated item ids")
    g.add_argument("--seed", type=int, default=None)
    e = sub.add_parser("export-json")
    e.add_argument("puzzle_dir", type=Path)
    e.add_argument("out_dir", type=Path)
    args = parser.parse_args(argv)

    if args.command == "export-json":
        return export_main([str(args.puzzle_dir), str(args.out_dir)])

    if args.command == "generate":
        items = [s.strip() for s in args.items.split(",") if s.strip()]
        result = generate_facts(items, seed=args.seed)
        out = {
            "answer": result.answer,
            "facts": [{"role": role, **fact.to_dict()} for role, fact in result.facts],
        }
        print(json.dumps(out, indent=2))
        return 0

    if not args.puzzle_dir.is_dir():
        print(f"error: {args.puzzle_dir} is not a directory", file=sys.stderr)
        return 2
    report = run_checks(args.puzzle_dir, args.profile)
    print(_summary(report))
    if args.command == "report":
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {args.json}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
