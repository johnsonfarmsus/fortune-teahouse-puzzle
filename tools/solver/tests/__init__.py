# SPDX-License-Identifier: AGPL-3.0-or-later
"""Tests for the puzzle solver. Run from the repo root:

    python -m unittest discover -s tools/solver/tests -t tools

Assertions about the real puzzles never print answers on failure.
"""

from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
FIXTURES = TESTS_DIR / "fixtures"
REPO_ROOT = TESTS_DIR.parents[2]
PUZZLES = REPO_ROOT / "puzzles"
