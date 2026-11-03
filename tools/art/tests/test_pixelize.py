# SPDX-License-Identifier: AGPL-3.0-or-later
"""The pixelizer: background removal, palette lock, size, colour limit, outline."""

import unittest

from PIL import Image, ImageDraw

from art.palette import load_palette
from art.pixelize import Options, pixelize

PAL = load_palette()
NAMES = {v: k for k, v in PAL.items()}


def render_like(bg=(250, 250, 250), size=512):
    """A soft, off-palette "render": a shaded orange disc on a light backdrop."""
    img = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(img)
    for i in range(40):
        shade = (230 - i, 120 - i, 60)
        r = size * 0.35 - i * 2
        d.ellipse((size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r), fill=shade)
    d.rectangle((size * 0.45, size * 0.75, size * 0.55, size * 0.9), fill=(40, 60, 140))
    return img


def opaque(img):
    return [(x, y) for y in range(img.height) for x in range(img.width) if img.getpixel((x, y))[3]]


class PixelizeTest(unittest.TestCase):
    def test_output_has_the_requested_size_and_only_palette_colours(self):
        out = pixelize(render_like(), Options(size=(32, 32), palette=PAL))
        self.assertEqual(out.size, (32, 32))
        for x, y in opaque(out):
            self.assertIn(out.getpixel((x, y))[:3], NAMES)

    def test_backdrop_is_transparent_and_corners_clear(self):
        out = pixelize(render_like(), Options(size=(16, 16), palette=PAL))
        for corner in ((0, 0), (15, 0), (0, 15), (15, 15)):
            self.assertEqual(out.getpixel(corner)[3], 0)
        self.assertTrue(opaque(out))

    def test_outline_surrounds_the_subject(self):
        out = pixelize(render_like(), Options(size=(16, 16), palette=PAL, outline="black"))
        ink = PAL["black"]
        solid = set(opaque(out))
        for x, y in solid:
            if out.getpixel((x, y))[:3] == ink:
                continue
            for n in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                self.assertIn(n, solid, "every subject pixel is enclosed by subject or outline")

    def test_max_colours_is_respected_outline_aside(self):
        out = pixelize(render_like(), Options(size=(32, 32), palette=PAL, max_colors=3, outline="black"))
        colours = {out.getpixel(p)[:3] for p in opaque(out)} - {PAL["black"]}
        self.assertLessEqual(len(colours), 3)

    def test_subset_palette_and_background_fill(self):
        sub = {k: PAL[k] for k in ("orange", "blue_dark")}
        out = pixelize(render_like(), Options(size=(16, 16), palette=sub, outline="black", background="sky"), PAL)
        self.assertEqual(out.getpixel((0, 0)), (*PAL["sky"], 255))
        allowed = {PAL["orange"], PAL["blue_dark"], PAL["black"], PAL["sky"]}
        for x in range(16):
            for y in range(16):
                self.assertIn(out.getpixel((x, y))[:3], allowed)

    def test_crop_keeps_part_of_the_subject(self):
        # Top half of the disc only: the blue stand at the bottom is gone.
        out = pixelize(render_like(), Options(size=(32, 32), palette=PAL, crop=(0, 0, 1, 0.5)))
        colours = {out.getpixel(p)[:3] for p in opaque(out)}
        self.assertNotIn(PAL["blue_dark"], colours)
        self.assertNotIn(PAL["blue"], colours)

    def test_bottom_anchor_puts_the_subject_on_the_floor(self):
        tall = Image.new("RGB", (200, 400), (255, 255, 255))
        ImageDraw.Draw(tall).rectangle((60, 40, 140, 360), fill=(200, 60, 50))
        out = pixelize(tall, Options(size=(32, 32), palette=PAL, anchor="bottom", outline=None))
        self.assertEqual(max(y for _, y in opaque(out)), 31)

    def test_small_islands_are_dropped_unless_asked_to_keep(self):
        img = Image.new("RGB", (400, 400), (255, 255, 255))
        d = ImageDraw.Draw(img)
        d.rectangle((40, 40, 300, 360), fill=(200, 60, 50))
        d.rectangle((350, 340, 370, 360), fill=(40, 60, 140))  # a speck off to the side
        dropped = pixelize(img, Options(size=(32, 32), palette=PAL, outline=None))
        kept = pixelize(img, Options(size=(32, 32), palette=PAL, outline=None, speck_share=0))
        blue = lambda im: [p for p in opaque(im) if im.getpixel(p)[:3] in (PAL["blue_dark"], PAL["blue"], PAL["purple"])]
        self.assertFalse(blue(dropped))
        self.assertTrue(blue(kept))

    def test_a_blank_render_is_an_error(self):
        with self.assertRaises(ValueError):
            pixelize(Image.new("RGB", (64, 64), (255, 255, 255)), Options(size=(16, 16), palette=PAL))


if __name__ == "__main__":
    unittest.main()
