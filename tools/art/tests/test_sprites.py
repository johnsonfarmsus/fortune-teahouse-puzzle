# SPDX-License-Identifier: AGPL-3.0-or-later
"""Text sprites: parsing, errors, rendering, build and the stale check."""

import tempfile
import unittest
from pathlib import Path

from PIL import Image

from art import sprites
from art.palette import load_palette

PAL = load_palette()

GOOD = """# test
out: art/items/test.png
colors: . transparent, k black, o orange
---
.kk.
kook
.kk.
"""


class SpritesTest(unittest.TestCase):
    def test_parse_and_render(self):
        s = sprites.parse(GOOD, PAL)
        self.assertEqual(s.out, "art/items/test.png")
        self.assertEqual(s.size, (4, 3))
        img = sprites.render(s)
        self.assertEqual(img.getpixel((0, 0))[3], 0)
        self.assertEqual(img.getpixel((1, 1)), (*PAL["orange"], 255))
        self.assertEqual(img.getpixel((0, 1)), (*PAL["black"], 255))

    def test_errors_name_the_problem(self):
        cases = {
            "no '---' line": GOOD.replace("---\n", ""),
            "expected 4": GOOD.replace("kook", "kooko"),
            "undeclared characters 'x'": GOOD.replace("kook", "kxok"),
            "'mauve' is not in the palette": GOOD.replace("o orange", "o mauve"),
            "needs 'out:'": GOOD.replace("out: art/items/test.png\n", ""),
        }
        for want, text in cases.items():
            with self.subTest(want), self.assertRaises(ValueError) as ctx:
                sprites.parse(text, PAL)
            self.assertIn(want, str(ctx.exception))

    def test_build_writes_pngs_and_check_finds_stale_ones(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, game = Path(tmp, "src"), Path(tmp, "game")
            src.mkdir()
            (src / "test.txt").write_text(GOOD)
            self.assertEqual(sprites.build(src, game, PAL, check=True), ["art/items/test.png"])
            sprites.build(src, game, PAL)
            self.assertTrue((game / "art/items/test.png").exists())
            self.assertEqual(sprites.build(src, game, PAL, check=True), [])
            Image.new("RGBA", (4, 3)).save(game / "art/items/test.png")
            self.assertEqual(sprites.build(src, game, PAL, check=True), ["art/items/test.png"])


if __name__ == "__main__":
    unittest.main()


class CompositesTest(unittest.TestCase):
    def test_bakes_tiles_onto_their_ground_and_repoints_assets(self):
        import json

        with tempfile.TemporaryDirectory() as tmp:
            game = Path(tmp)
            sheet = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
            for x in range(16):  # ground: solid green cell at (0, 0)
                for y in range(16):
                    sheet.putpixel((x, y), (0, 200, 0, 255))
            sheet.putpixel((24, 8), (200, 0, 0, 255))  # a lone red pixel on a clear cell at (16, 0)
            (game / "art").mkdir()
            sheet.save(game / "art/sheet.png")
            (game / "assets.json").write_text(json.dumps({"assets": {"tile.bush": {"file": "art/sheet.png", "origin": [16, 0]}}}))
            spec = game / "spec.json"
            spec.write_text(json.dumps({"out": "art/tiles/c.png", "tiles": [
                {"asset": "tile.bush", "over": {"file": "art/sheet.png", "origin": [16, 0]},
                 "under": {"file": "art/sheet.png", "origin": [0, 0]}}]}))
            self.assertTrue(sprites.build_composites(spec, game, check=True))
            sprites.build_composites(spec, game)
            out = Image.open(game / "art/tiles/c.png").convert("RGBA")
            self.assertEqual(out.getpixel((8, 8)), (200, 0, 0, 255))
            self.assertEqual(out.getpixel((0, 0)), (0, 200, 0, 255))
            entry = json.loads((game / "assets.json").read_text())["assets"]["tile.bush"]
            self.assertEqual((entry["file"], entry["origin"]), ("art/tiles/c.png", [0, 0]))
            self.assertEqual(sprites.build_composites(spec, game, check=True), [])
