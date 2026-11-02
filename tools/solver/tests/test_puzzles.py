# SPDX-License-Identifier: AGPL-3.0-or-later
"""Checks on the real puzzles/ data.

These tests run in public CI, so failure messages must never show answers
or facts: compare with assertTrue and answer-free messages only.
"""

import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from solver import yamlsub
from solver.checks import run_checks
from solver.generate import generate_facts
from solver.puzzlefile import discover, load_machine

from . import PUZZLES

try:
    import yaml  # optional cross-check, installed in CI
except ImportError:  # pragma: no cover
    yaml = None

try:
    import jsonschema  # optional cross-check, installed in CI
except ImportError:  # pragma: no cover
    jsonschema = None


def _failed(report):
    out = [f"global:{c['check']}" for c in report["global"] if not c["passed"]]
    out += [f"backs:{c['check']}" for c in report["backs"]["checks"] if not c["passed"]]
    for m in report["machines"]:
        out += [f"{m['machine']}:{c['check']}" for c in m["checks"] if not c["passed"]]
    return out


class PuzzleDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = run_checks(PUZZLES)
        cls.machine_files, cls.backs_file = discover(PUZZLES)
        cls.machines = [load_machine(p) for p in cls.machine_files]

    def test_all_checks_pass(self):
        self.assertTrue(self.report["passed"], f"failed checks: {_failed(self.report)}")

    def test_three_machines(self):
        self.assertEqual(sorted(m.id for m in self.machines), ["cookie_machine", "fortune_machine", "oven"])

    def test_eighteen_unique_lucky_words(self):
        words = [c.lucky_word for m in self.machines for c in m.clues]
        self.assertEqual(len(words), 18)
        self.assertEqual(len(set(words)), 18)

    def test_alt_99_profile_is_a_real_parameter(self):
        report = run_checks(PUZZLES, "alt-99")
        self.assertEqual(report["limit"], 99)
        self.assertIn("passed", report)

    def test_answers_regenerate_from_recorded_seed(self):
        for path in self.machine_files:
            data = yamlsub.load_path(path)
            items = [i["id"] for i in data["domain"]["items"]]
            regenerated = generate_facts(items, seed=data["generator"]["seed"]).answer
            self.assertTrue(regenerated == data["answer"], f"{path.name}: answer does not match its generator seed")

    def test_report_and_summary_are_answer_free(self):
        from solver.__main__ import _summary

        text = _summary(self.report) + json.dumps(self.report)
        leaked = []
        for m in self.machines:
            for item_id, name in m.items:
                for token in (item_id, name):
                    if re.search(rf"(?<![A-Za-z0-9_]){re.escape(token)}(?![A-Za-z0-9_])", text, re.IGNORECASE):
                        leaked.append(token)
            for clue in m.clues:
                if clue.nudge in text or clue.fortune_text in text:
                    leaked.append(clue.id)
        self.assertFalse(leaked, f"item names or clue text found in report: {sorted(set(leaked))}")

    def test_broken_copy_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            for path in PUZZLES.glob("*.yaml"):
                shutil.copy(path, tmp_dir / path.name)
            target = tmp_dir / "oven.yaml"
            text = target.read_text(encoding="utf-8")
            # flip every offset in the Oven: the declared answer stops fitting
            flipped = re.sub(r"offset: (-?)1", lambda m: "offset: 1" if m.group(1) else "offset: -1", text)
            target.write_text(flipped, encoding="utf-8")
            # and duplicate a lucky word across machines
            cookie = tmp_dir / "cookie_machine.yaml"
            ctext = cookie.read_text(encoding="utf-8").replace("lucky_word: TUX", "lucky_word: TARBALL")
            cookie.write_text(ctext, encoding="utf-8")
            report = run_checks(tmp_dir)
        failed = _failed(report)
        self.assertFalse(report["passed"])
        self.assertIn("oven:answer-consistent", failed)
        self.assertIn("global:lucky-words-unique", failed)
        self.assertIn("cookie_machine:lucky-word-format", failed)  # front still says TUX


@unittest.skipIf(yaml is None, "PyYAML not installed")
class YamlCrossCheckTests(unittest.TestCase):
    def test_subset_loader_matches_pyyaml(self):
        for path in sorted(PUZZLES.glob("*.yaml")):
            text = path.read_text(encoding="utf-8")
            self.assertTrue(yamlsub.loads(text) == yaml.safe_load(text), f"{path.name} parses differently")


@unittest.skipIf(jsonschema is None, "jsonschema not installed")
class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads((PUZZLES / "schema.json").read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator.check_schema(cls.schema)

    def _errors(self, schema, data):
        validator = jsonschema.Draft202012Validator(schema)
        # report paths and messages' validator names only, never instance values
        return [f"{'/'.join(map(str, e.absolute_path))}: {e.validator}" for e in validator.iter_errors(data)]

    def test_machine_files_match_schema(self):
        machine_files, _ = discover(PUZZLES)
        for path in machine_files:
            errors = self._errors(self.schema, yamlsub.load_path(path))
            self.assertEqual(errors, [], path.name)

    def test_backs_match_schema(self):
        schema = dict(self.schema["$defs"]["backs"])
        schema["$defs"] = self.schema["$defs"]
        errors = self._errors(schema, yamlsub.load_path(PUZZLES / "backs.yaml"))
        self.assertEqual(errors, [])

    def test_schema_rejects_bad_clue(self):
        data = yamlsub.load_path(PUZZLES / "cookie_machine.yaml")
        data["clues"][0]["approachable"] = not data["clues"][0]["approachable"]
        data["clues"][1]["lucky_word"] = "lowercase"
        self.assertTrue(len(self._errors(self.schema, data)) >= 2)


if __name__ == "__main__":
    unittest.main()
