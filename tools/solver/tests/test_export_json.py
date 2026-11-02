# SPDX-License-Identifier: AGPL-3.0-or-later
"""The JSON exporter for the game (game/ARCHITECTURE.md section 2)."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from solver.export_json import export_dir, machine_to_json, render
from solver.puzzlefile import load_machine

from . import FIXTURES, PUZZLES, REPO_ROOT

SAMPLE = FIXTURES / "sample_cookie_machine.yaml"
STYLES = ["security", "poem", "animal", "trivia", "code", "hardware"]


class SampleExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = machine_to_json(load_machine(SAMPLE))

    def test_top_level_shape(self):
        self.assertEqual(
            sorted(self.data),
            ["answer", "clues", "domain", "machine", "puzzle_title", "schema_version", "title"],
        )
        self.assertEqual(self.data["schema_version"], 1)
        self.assertEqual(self.data["machine"], "sample_cookie_machine")
        self.assertEqual(self.data["puzzle_title"], "Batter recipe")
        self.assertEqual(
            self.data["domain"],
            {
                "items": ["sugar", "flour", "butter", "vanilla", "egg"],
                "positions": ["Jar 1", "Jar 2", "Jar 3", "Jar 4", "Jar 5"],
                "position_noun": "jar",
            },
        )

    def test_answer_is_one_based(self):
        self.assertEqual(self.data["answer"], {"sugar": 1, "flour": 2, "vanilla": 3, "butter": 4, "egg": 5})

    def test_clues(self):
        clues = self.data["clues"]
        self.assertEqual([c["style"] for c in clues], STYLES)
        for clue in clues:
            self.assertEqual(
                sorted(clue), ["approachable", "fact", "fortune_text", "id", "lucky_word", "nudge", "style"]
            )
            self.assertEqual(clue["id"], "sample_cookie_machine." + clue["style"])
            self.assertNotIn("Lucky word", clue["fortune_text"])
            self.assertFalse(clue["fortune_text"].endswith(" "))
        security = clues[0]
        self.assertEqual(security["fortune_text"], "ROT13 says: Fhtne vf va wne bar.")
        self.assertEqual(security["lucky_word"], "CIPHER")
        self.assertTrue(security["approachable"])

    def test_fact_mapping(self):
        facts = {c["style"]: c["fact"] for c in self.data["clues"]}
        self.assertEqual(facts["security"], {"kind": "position", "a": "sugar", "value": 1})
        self.assertEqual(facts["poem"], {"kind": "offset", "a": "butter", "b": "vanilla", "value": 1})
        self.assertEqual(facts["hardware"], {"kind": "offset", "a": "butter", "b": "egg", "value": -1})
        # pos(a) = pos(b) + value holds for the answer
        answer = self.data["answer"]
        for fact in facts.values():
            if fact["kind"] == "offset":
                self.assertEqual(answer[fact["a"]], answer[fact["b"]] + fact["value"])
            else:
                self.assertEqual(answer[fact["a"]], fact["value"])

    def test_render_is_deterministic(self):
        text = render(self.data)
        self.assertTrue(text.endswith("}\n"))
        self.assertEqual(json.loads(text), self.data)
        self.assertEqual(render(json.loads(text)), text)


class ExportDirTests(unittest.TestCase):
    def test_idempotent_and_matches_committed_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            first, second = Path(tmp) / "a", Path(tmp) / "b"
            written = export_dir(PUZZLES, first)
            export_dir(PUZZLES, second)
            export_dir(PUZZLES, second)  # overwrite in place
            names = sorted(p.name for p in written)
            self.assertEqual(names, ["cookie_machine.json", "fortune_machine.json", "oven.json"])
            committed = REPO_ROOT / "game" / "data" / "puzzles"
            for name in names:
                a = (first / name).read_bytes()
                self.assertTrue(a == (second / name).read_bytes(), f"{name} differs between runs")
                self.assertTrue(
                    a == (committed / name).read_bytes(),
                    f"{name} is stale: run python -m solver export-json puzzles/ game/data/puzzles/",
                )

    def test_refuses_broken_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            text = SAMPLE.read_text(encoding="utf-8").replace("  puzzle_title: Batter recipe\n", "")
            (src / "sample.yaml").write_text(text, encoding="utf-8")
            from solver.export_json import ExportError

            with self.assertRaises(ExportError):
                export_dir(src, Path(tmp) / "out")
            self.assertFalse((Path(tmp) / "out").exists())


if __name__ == "__main__":
    unittest.main()
