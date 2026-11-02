# SPDX-License-Identifier: AGPL-3.0-or-later
"""Solver, checker and generator for the Fortune Teahouse core logic puzzles.

Each core puzzle is an n-to-n matching (n = 5 for all three machines): every
item goes to exactly one ordered position. Clues are facts of two kinds:

* ``position``: an item sits at a given position (1-based).
* ``offset``: an item sits immediately after (+1) or before (-1) another item.

Standard library only; Python 3.11 or newer. Run from the ``tools`` directory
(or with ``PYTHONPATH=tools``) as ``python -m solver check puzzles/``.
"""

from .core import (
    Domain,
    Fact,
    RuleResult,
    check_fact_set,
    count_solutions,
    misreading_report,
    solve,
)
from .generate import generate_facts

__all__ = [
    "Domain",
    "Fact",
    "RuleResult",
    "check_fact_set",
    "count_solutions",
    "generate_facts",
    "misreading_report",
    "solve",
]
