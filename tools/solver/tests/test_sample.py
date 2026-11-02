# SPDX-License-Identifier: AGPL-3.0-or-later
"""The sample Cookie Machine set from DESIGN.md must pass every check.

This replaces the review's tools/solver/verify_sample_clues.py script.
"""

import math
import unittest

from solver.checks import LIMIT_PROFILES, check_machine
from solver.core import check_fact_set, count_solutions, misreading_report
from solver.puzzlefile import load_machine

from . import FIXTURES

SAMPLE = FIXTURES / "sample_cookie_machine.yaml"
DESIGN_COUNTS = {
    "sample_security": 51,
    "sample_poem": 107,
    "sample_animal": 115,
    "sample_trivia": 99,
    "sample_code": 71,
    "sample_hardware": 107,
}


class SampleSetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.machine = load_machine(SAMPLE)
        cls.facts = {c.id: c.fact for c in cls.machine.clues}
        cls.approachable = [c.id for c in cls.machine.clues if c.approachable]

    def test_loads_cleanly(self):
        self.assertEqual(self.machine.errors, [])

    def test_all_checks_pass(self):
        report = check_machine(self.machine, LIMIT_PROFILES["vendor-140"])
        failed = [c["check"] for c in report["checks"] if not c["passed"]]
        self.assertEqual(failed, [])
        self.assertEqual(report["longest_front"], 115)

    def test_review_findings(self):
        d = self.machine.domain
        self.assertEqual(count_solutions(d, self.facts.values()), 1)
        results = {r.rule: r for r in check_fact_set(d, self.facts, self.approachable, self.machine.answer)}
        self.assertEqual(results["every-4-unique"].detail, "15 of 15 4-subsets have exactly one solution")
        # the review: every 3-subset leaves exactly two answers
        import itertools

        ids = sorted(self.facts)
        for sub in itertools.combinations(ids, 3):
            self.assertEqual(count_solutions(d, (self.facts[c] for c in sub)), 2, sub)

    def test_poem_misreading_breaks_the_approachable_four(self):
        report = {m["clue"]: m for m in misreading_report(self.machine.domain, self.facts, self.approachable)}
        self.assertTrue(report["sample_poem"]["breaks_approachable"])
        for clue in ("sample_animal", "sample_code", "sample_hardware", "sample_poem"):
            self.assertEqual(len(report[clue]["broken_subsets"]), 1, clue)

    def test_character_counts_match_design(self):
        for clue in self.machine.clues:
            self.assertEqual(len(clue.fortune_text), DESIGN_COUNTS[clue.id], clue.id)
        code = next(c for c in self.machine.clues if c.style == "code")
        # with Markdown backticks printed it would be 73
        self.assertEqual(len("`" + code.fortune_text.split(" Lucky word:")[0] + "`") + len(" Lucky word: PATCH"), 73)

    def test_alt_99_profile_flags_long_fronts(self):
        report = check_machine(self.machine, LIMIT_PROFILES["alt-99"])
        length = next(c for c in report["checks"] if c["check"] == "front-length")
        self.assertFalse(length["passed"])
        self.assertEqual(sorted(length["subjects"]), ["sample_animal", "sample_hardware", "sample_poem"])

    def test_pi_digits(self):
        # review 1.4 and decision D7: Pack A + Pack B is ten digits of pi
        self.assertEqual("31415" + "92653", str(math.pi).replace(".", "")[:10])


if __name__ == "__main__":
    unittest.main()
