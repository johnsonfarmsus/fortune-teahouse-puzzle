# SPDX-License-Identifier: AGPL-3.0-or-later
"""The command line: exit codes, the JSON report and answer-free output."""

import contextlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from solver.__main__ import main

from . import FIXTURES, PUZZLES


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        code = main(argv)
    return code, out.getvalue()


class CliTests(unittest.TestCase):
    def test_check_passes(self):
        code, out = run(["check", str(PUZZLES)])
        self.assertEqual(code, 0)
        self.assertIn("RESULT: PASS", out)

    def test_report_writes_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "out" / "report.json"
            code, _ = run(["report", str(PUZZLES), "--json", str(target)])
            self.assertEqual(code, 0)
            report = json.loads(target.read_text(encoding="utf-8"))
        self.assertTrue(report["passed"])
        self.assertEqual(len(report["machines"]), 3)
        for machine in report["machines"]:
            self.assertEqual(len(machine["subset_solution_counts"]["4"]), 15)
            self.assertTrue(all(n == 1 for n in machine["subset_solution_counts"]["4"].values()))
            self.assertNotIn("answer", machine)

    def test_broken_directory_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            shutil.copy(FIXTURES / "sample_cookie_machine.yaml", Path(tmp) / "sample.yaml")
            code, out = run(["check", tmp])
        self.assertEqual(code, 1)  # only one machine file and no backs.yaml
        self.assertIn("FAIL machine-files", out)
        self.assertIn("FAIL backs-present", out)

    def test_missing_directory(self):
        code, _ = run(["check", "/nonexistent/puzzles"])
        self.assertEqual(code, 2)

    def test_generate(self):
        code, out = run(["generate", "--items", "a,b,c,d,e", "--seed", "4"])
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(len(data["facts"]), 6)


if __name__ == "__main__":
    unittest.main()
