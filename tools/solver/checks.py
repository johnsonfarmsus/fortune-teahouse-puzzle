# SPDX-License-Identifier: AGPL-3.0-or-later
"""Run every puzzle check over a puzzles/ directory and build the report.

The report names machines, clue ids, subset ids, rule names, lengths and
lucky words. It never contains answers, items placed at positions or facts.
"""

from __future__ import annotations

import itertools
import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .core import OFFSET, check_fact_set, count_solutions, misreading_report, subset_id
from .puzzlefile import (
    APPROACHABLE_STYLES,
    DIRECTION_WORDS,
    LUCKY_SUFFIX,
    LUCKY_WORD_RE,
    STYLES,
    Backs,
    Machine,
    discover,
    load_backs,
    load_machine,
)

LIMIT_PROFILES = {"vendor-140": 140, "alt-99": 99}
DEFAULT_PROFILE = "vendor-140"
THRESHOLD = 4
PI_DIGITS = "3141592653"  # decision D7: the finale start code "3.141592653"


@dataclass
class Check:
    name: str
    passed: bool
    detail: str
    subjects: list[str] = field(default_factory=list)  # clue ids, subset ids or pack ids

    def to_dict(self) -> dict[str, Any]:
        return {"check": self.name, "passed": self.passed, "detail": self.detail, "subjects": self.subjects}


_CODE_OFFSET = re.compile(r"[+-]\s*1\b")


def _states_direction(text: str, style: str) -> bool:
    """A direction word in plain text; a code clue may instead use explicit +1/-1."""
    words = set(re.findall(r"[a-z]+", text.lower()))
    if any(w in words for w in DIRECTION_WORDS):
        return True
    return style == "code" and bool(_CODE_OFFSET.search(text))


def check_machine(machine: Machine, limit: int) -> dict[str, Any]:
    checks: list[Check] = []
    checks.append(
        Check("structure", not machine.errors, "file matches the schema" if not machine.errors else "; ".join(machine.errors))
    )
    clues = machine.clues

    styles = [c.style for c in clues]
    style_ok = len(clues) == len(STYLES) and sorted(styles) == sorted(STYLES)
    checks.append(Check("one-clue-per-style", style_ok, f"{len(clues)} clues covering {len(set(styles))} of 6 styles"))

    wrong_flag = [c.id for c in clues if c.approachable != (c.style in APPROACHABLE_STYLES)]
    checks.append(
        Check(
            "approachable-flags",
            not wrong_flag,
            "approachable is true exactly for poem, animal, trivia and security",
            wrong_flag,
        )
    )

    bad_suffix = [c.id for c in clues if not (LUCKY_WORD_RE.match(c.lucky_word) and c.fortune_text.endswith(LUCKY_SUFFIX + c.lucky_word))]
    checks.append(
        Check("lucky-word-format", not bad_suffix, "front ends with ' Lucky word: WORD', WORD is 3 to 8 capitals", bad_suffix)
    )

    bad_count = [c.id for c in clues if c.char_count != len(c.fortune_text)]
    checks.append(Check("char-count-field", not bad_count, "char_count equals the front's length", bad_count))

    too_long = [c.id for c in clues if len(c.fortune_text) > limit]
    checks.append(Check("front-length", not too_long, f"every front is {limit} characters or fewer", too_long))

    non_ascii = [c.id for c in clues if not all(32 <= ord(ch) < 127 for ch in c.fortune_text)]
    checks.append(Check("front-printable-ascii", not non_ascii, "fronts use printable ASCII only (vendor safety)", non_ascii))

    no_direction = [
        c.id
        for c in clues
        if c.fact is not None and c.fact.kind == OFFSET and not _states_direction(c.fortune_text, c.style)
    ]
    checks.append(
        Check(
            "direction-word",
            not no_direction,
            "every offset clue says right/left/before/after/above/below (code clues may use explicit +1/-1)",
            no_direction,
        )
    )

    item_order = [i for i, _ in machine.items]
    shuffled = bool(machine.answer) and [machine.answer.get(i) for i in item_order] != list(range(1, len(item_order) + 1))
    checks.append(Check("answer-shuffled", shuffled, "the answer is not the listed item order"))

    facts = {c.id: c.fact for c in clues if c.fact is not None}
    rule_results: list[dict[str, Any]] = []
    misreadings: list[dict[str, Any]] = []
    subset_counts: dict[str, dict[str, int]] = {}
    if machine.errors or len(facts) != len(clues) or not machine.items:
        checks.append(Check("solver-rules", False, "skipped because the file has structural errors"))
    else:
        domain = machine.domain
        approachable = [c.id for c in clues if c.approachable]
        for result in check_fact_set(domain, facts, approachable, machine.answer, THRESHOLD):
            rule_results.append(result.to_dict())
            checks.append(Check(result.rule, result.passed, result.detail, result.failing_subsets))
        misreadings = misreading_report(domain, facts, approachable, THRESHOLD)
        ids = sorted(facts)
        for k in range(THRESHOLD - 1, len(ids) + 1):
            subset_counts[str(k)] = {
                subset_id(sub): count_solutions(domain, (facts[c] for c in sub))
                for sub in itertools.combinations(ids, k)
            }

    lengths = {c.id: len(c.fortune_text) for c in clues}
    return {
        "machine": machine.id,
        "name": machine.name,
        "file": machine.path.name,
        "passed": all(c.passed for c in checks),
        "checks": [c.to_dict() for c in checks],
        "clues": [
            {
                "id": c.id,
                "style": c.style,
                "approachable": c.approachable,
                "lucky_word": c.lucky_word,
                "length": len(c.fortune_text),
                "fits": {name: len(c.fortune_text) <= lim for name, lim in LIMIT_PROFILES.items()},
            }
            for c in clues
        ],
        "longest_front": max(lengths.values(), default=0),
        "subset_solution_counts": subset_counts,
        "misreading": misreadings,
    }


def check_backs(backs: Backs | None, limit: int) -> dict[str, Any]:
    checks: list[Check] = []
    if backs is None:
        checks.append(Check("backs-present", False, "puzzles/backs.yaml is missing"))
        return {"passed": False, "checks": [c.to_dict() for c in checks], "packs": []}
    checks.append(Check("structure", not backs.errors, "file matches the schema" if not backs.errors else "; ".join(backs.errors)))
    checks.append(Check("two-packs", len(backs.packs) == 2, f"{len(backs.packs)} back messages (one per pack)"))
    long_packs = [p["id"] for p in backs.packs if len(p["text"]) > limit]
    checks.append(Check("back-length", not long_packs, f"every back is {limit} characters or fewer", long_packs))
    bad_count = [p["id"] for p in backs.packs if p["char_count"] != len(p["text"])]
    checks.append(Check("char-count-field", not bad_count, "char_count equals the back's length", bad_count))
    bad_numbers = [
        p["id"] for p in backs.packs if not p["text"].endswith("Lucky numbers: " + p["lucky_numbers"])
    ]
    checks.append(Check("numbers-printed", not bad_numbers, "each back ends with its lucky numbers", bad_numbers))
    digits = "".join(re.sub(r"\s+", "", p["lucky_numbers"]) for p in backs.packs)
    pi_ok = backs.start_code == PI_DIGITS == digits and str(math.pi).replace(".", "").startswith(PI_DIGITS)
    checks.append(Check("start-code", pi_ok, "pack lucky numbers in order spell the start code 3.141592653 (D7)"))
    return {
        "passed": all(c.passed for c in checks),
        "checks": [c.to_dict() for c in checks],
        "packs": [
            {
                "id": p["id"],
                "length": len(p["text"]),
                "fits": {name: len(p["text"]) <= lim for name, lim in LIMIT_PROFILES.items()},
            }
            for p in backs.packs
        ],
    }


def run_checks(puzzle_dir: Path, profile: str = DEFAULT_PROFILE) -> dict[str, Any]:
    if profile not in LIMIT_PROFILES:
        raise ValueError(f"unknown limit profile {profile!r}")
    limit = LIMIT_PROFILES[profile]
    machine_files, backs_path = discover(puzzle_dir)
    machines = [load_machine(p) for p in machine_files]
    machine_reports = [check_machine(m, limit) for m in machines]

    global_checks: list[Check] = []
    global_checks.append(Check("machine-files", len(machines) == 3, f"{len(machines)} machine files (expected 3)"))
    ids = [m.id for m in machines]
    dup_machines = sorted({i for i in ids if ids.count(i) > 1})
    global_checks.append(Check("machine-ids-unique", not dup_machines, "machine ids are unique", dup_machines))
    words = [c.lucky_word for m in machines for c in m.clues]
    dup_words = sorted({w for w in words if words.count(w) > 1})
    global_checks.append(
        Check("lucky-words-unique", not dup_words, f"{len(set(words))} distinct lucky words across {len(words)} fortunes", dup_words)
    )
    clue_ids = [c.id for m in machines for c in m.clues]
    dup_ids = sorted({i for i in clue_ids if clue_ids.count(i) > 1})
    global_checks.append(Check("clue-ids-unique", not dup_ids, "clue ids are unique across machines", dup_ids))

    backs_report = check_backs(load_backs(backs_path) if backs_path else None, limit)
    passed = all(c.passed for c in global_checks) and backs_report["passed"] and all(r["passed"] for r in machine_reports)
    return {
        "profile": profile,
        "limit": limit,
        "threshold": THRESHOLD,
        "passed": passed,
        "global": [c.to_dict() for c in global_checks],
        "backs": backs_report,
        "machines": machine_reports,
    }
