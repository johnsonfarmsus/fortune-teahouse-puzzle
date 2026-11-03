# SPDX-License-Identifier: AGPL-3.0-or-later
"""Text-file sprites: a grid of characters, one per pixel, built into PNGs.

A sprite file (``art-src/sprites/*.txt``) looks like this::

    # A wrench for the inventory.
    out: art/items/wrench.png
    colors: . transparent, k black, s silver, g grey
    ---
    ......kk
    .....ksk
    ....ksgk
    ...ksgk.

``out`` is relative to ``game/``. ``colors`` maps one character to a palette
name (or ``transparent``). Rows below ``---`` must all be the same width; lines
starting with ``#`` above it are comments. Several frames go side by side on
one line or as separate files, to match the frame layout in game/assets.json.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .palette import RGB


@dataclass
class Sprite:
    source: Path
    out: str
    colors: dict[str, RGB | None]
    rows: list[str]

    @property
    def size(self) -> tuple[int, int]:
        return (len(self.rows[0]), len(self.rows))


def parse(text: str, palette: dict[str, RGB], source: Path = Path("<text>")) -> Sprite:
    head, sep, body = text.partition("\n---\n")
    if not sep:
        raise ValueError(f"{source}: no '---' line between the header and the pixels")
    fields: dict[str, str] = {}
    for line in head.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, colon, value = line.partition(":")
        if not colon:
            raise ValueError(f"{source}: header line without ':': {line!r}")
        fields[key.strip()] = value.strip()
    for key in ("out", "colors"):
        if key not in fields:
            raise ValueError(f"{source}: header needs '{key}:'")
    colors: dict[str, RGB | None] = {}
    for pair in fields["colors"].split(","):
        parts = pair.split()
        if len(parts) != 2 or len(parts[0]) != 1:
            raise ValueError(f"{source}: colour entries are '<char> <palette name>', got {pair.strip()!r}")
        char, name = parts
        if name == "transparent":
            colors[char] = None
        elif name in palette:
            colors[char] = palette[name]
        else:
            raise ValueError(f"{source}: {name!r} is not in the palette")
    rows = [r for r in body.splitlines() if r.strip()]
    if not rows:
        raise ValueError(f"{source}: no pixel rows")
    width = len(rows[0])
    for n, row in enumerate(rows, 1):
        if len(row) != width:
            raise ValueError(f"{source}: row {n} is {len(row)} wide, expected {width}")
        unknown = sorted(set(row) - set(colors))
        if unknown:
            raise ValueError(f"{source}: row {n} uses undeclared characters {''.join(unknown)!r}")
    return Sprite(source=source, out=fields["out"], colors=colors, rows=rows)


def render(sprite: Sprite) -> Image.Image:
    img = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(sprite.rows):
        for x, ch in enumerate(row):
            c = sprite.colors[ch]
            if c is not None:
                px[x, y] = (*c, 255)
    return img


def same_pixels(a: Image.Image, b: Image.Image) -> bool:
    return a.size == b.size and a.convert("RGBA").tobytes() == b.convert("RGBA").tobytes()


def build(src_dir: Path, game_dir: Path, palette: dict[str, RGB], check: bool = False) -> list[str]:
    """Build every sprite; with ``check``, build nothing and return the stale outputs."""
    stale: list[str] = []
    for path in sorted(Path(src_dir).glob("*.txt")):
        sprite = parse(path.read_text(encoding="utf-8"), palette, path)
        img = render(sprite)
        dest = Path(game_dir) / sprite.out
        if check:
            if not dest.exists() or not same_pixels(img, Image.open(dest)):
                stale.append(sprite.out)
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest)
    return stale
