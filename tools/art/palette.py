# SPDX-License-Identifier: AGPL-3.0-or-later
"""The game's one palette, read from game/assets.json, and colour matching."""

from __future__ import annotations

import json
from pathlib import Path

RGB = tuple[int, int, int]

ROOT = Path(__file__).resolve().parents[2]
ASSETS_JSON = ROOT / "game" / "assets.json"


def parse_hex(value: str) -> RGB:
    v = value.lstrip("#")
    if len(v) != 6:
        raise ValueError(f"not a #rrggbb colour: {value!r}")
    return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))


def to_hex(rgb: RGB) -> str:
    return "#%02x%02x%02x" % rgb


def load_palette(path: Path = ASSETS_JSON, names: list[str] | None = None) -> dict[str, RGB]:
    """Name -> RGB, in file order. ``names`` limits it to a subset (in that order)."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    pal = {k: parse_hex(v) for k, v in data["palette"].items()}
    if names is None:
        return pal
    missing = [n for n in names if n not in pal]
    if missing:
        raise KeyError(f"not in the palette: {', '.join(missing)}")
    return {n: pal[n] for n in names}


def distance2(a: RGB, b: RGB) -> float:
    """Squared "redmean" distance: cheap and much closer to how eyes judge than plain RGB."""
    rmean = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return (2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db


class Matcher:
    """Nearest palette colour, cached per input colour."""

    def __init__(self, palette: dict[str, RGB]):
        if not palette:
            raise ValueError("empty palette")
        self.palette = palette
        self._colours = list(palette.values())
        self._cache: dict[RGB, RGB] = {}

    def nearest(self, rgb: RGB) -> RGB:
        hit = self._cache.get(rgb)
        if hit is None:
            hit = min(self._colours, key=lambda c: distance2(rgb, c))
            self._cache[rgb] = hit
        return hit
