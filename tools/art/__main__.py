# SPDX-License-Identifier: AGPL-3.0-or-later
"""Command line: python -m art {pixelize,sprites,tiles,list,render,batch} ...

  pixelize IN OUT --size WxH [--colors a,b,c] [--max-colors N] [--outline NAME|none]
           [--background NAME] [--crop x0,y0,x1,y1] [--anchor center|bottom]
           [--tolerance N] [--keep-alpha] [--specks SHARE] [--preview PATH --scale N]
      Turn a render into palette-locked pixel art (see art/pixelize.py).
  sprites [--src art-src/sprites] [--check]
      Build every text sprite into game/; --check exits 1 if a PNG is stale.
  tiles [--check]
      Bake transparent tiles onto their ground (art-src/tiles/composites.json).
  batch JOBS.jsonl
      Run a queue of renders one at a time, skipping outputs that already exist.
  list [--prefix NAME] [--missing]
      The asset list in game/assets.json as a Markdown table, with what has landed.
  render KIND PROMPT OUT [--quality fast|best] [--shape square|wide|tall] [--source NAME]
      One render through the steam-machine's media API (env: MEDIA_API_URL,
      MEDIA_API_KEY, MEDIA_API_USER). Writes OUT and OUT.json (provenance).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

from . import media, sprites
from .palette import ASSETS_JSON, ROOT, load_palette
from .pixelize import Options, pixelize, preview


def _size(text: str) -> tuple[int, int]:
    w, _, h = text.lower().partition("x")
    return (int(w), int(h))


def _floats(text: str) -> tuple[float, float, float, float]:
    parts = [float(p) for p in text.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("crop is x0,y0,x1,y1 as fractions of the subject")
    return (parts[0], parts[1], parts[2], parts[3])


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="python -m art", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    px = sub.add_parser("pixelize")
    px.add_argument("input", type=Path)
    px.add_argument("output", type=Path)
    px.add_argument("--size", type=_size, required=True)
    px.add_argument("--assets", type=Path, default=ASSETS_JSON)
    px.add_argument("--colors", help="comma-separated palette names to allow (default: all)")
    px.add_argument("--max-colors", type=int, default=0)
    px.add_argument("--outline", default="black", help="palette name, or 'none'")
    px.add_argument("--background")
    px.add_argument("--crop", type=_floats, default=(0.0, 0.0, 1.0, 1.0))
    px.add_argument("--anchor", choices=["center", "bottom"], default="center")
    px.add_argument("--tolerance", type=float, default=60.0)
    px.add_argument("--keep-alpha", action="store_true")
    px.add_argument("--specks", type=float, default=0.15, help="drop islands under this share of the largest (0 keeps all)")
    px.add_argument("--preview", type=Path)
    px.add_argument("--scale", type=int, default=8)

    sp = sub.add_parser("sprites")
    sp.add_argument("--src", type=Path, default=ROOT / "art-src" / "sprites")
    sp.add_argument("--game", type=Path, default=ROOT / "game")
    sp.add_argument("--check", action="store_true")

    tp = sub.add_parser("tiles")
    tp.add_argument("--spec", type=Path, default=ROOT / "art-src" / "tiles" / "composites.json")
    tp.add_argument("--game", type=Path, default=ROOT / "game")
    tp.add_argument("--check", action="store_true")

    bp = sub.add_parser("batch")
    bp.add_argument("jobs", type=Path, help="JSON lines: id, kind, prompt, out, [quality, shape, source, seconds]")

    lp = sub.add_parser("list")
    lp.add_argument("--assets", type=Path, default=ASSETS_JSON)
    lp.add_argument("--prefix", help="only names starting with this (tile, char, portrait, prop, machine, ...)")
    lp.add_argument("--missing", action="store_true", help="only assets still drawn as placeholders")

    rp = sub.add_parser("render")
    rp.add_argument("kind", choices=["image", "edit"])
    rp.add_argument("prompt")
    rp.add_argument("output", type=Path)
    rp.add_argument("--quality", choices=["fast", "best"], default="best")
    rp.add_argument("--shape", choices=["square", "wide", "tall"], default="square")
    rp.add_argument("--source", help="library item name to edit")

    args = p.parse_args(argv)

    if args.cmd == "pixelize":
        full = load_palette(args.assets)
        allowed = load_palette(args.assets, args.colors.split(",")) if args.colors else full
        outline = None if args.outline == "none" else args.outline
        for name in (outline, args.background):
            if name and name not in full:
                p.error(f"{name!r} is not in the palette")
        # The subject is matched against the allowed colours only; the outline and
        # backdrop are looked up by name, so they may sit outside that subset.
        opts = Options(size=args.size, palette=allowed, max_colors=args.max_colors,
                       outline=outline, background=args.background, crop=args.crop,
                       anchor=args.anchor, bg_tolerance=args.tolerance, keep_alpha=args.keep_alpha,
                       speck_share=args.specks)
        img = pixelize(Image.open(args.input), opts, full)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        img.save(args.output)
        if args.preview:
            preview(img, args.scale).save(args.preview)
        return 0

    if args.cmd == "sprites":
        stale = sprites.build(args.src, args.game, load_palette(), check=args.check)
        if args.check and stale:
            print("stale text sprites (run: PYTHONPATH=tools python -m art sprites):", *stale, sep="\n  ")
            return 1
        return 0

    if args.cmd == "tiles":
        stale = sprites.build_composites(args.spec, args.game, check=args.check)
        if args.check and stale:
            print("stale composite tiles (run: PYTHONPATH=tools python -m art tiles):", *stale, sep="\n  ")
            return 1
        return 0

    if args.cmd == "batch":
        summary = media.batch(media.Client(), args.jobs, log=lambda m: print(m, flush=True))
        print(json.dumps(summary))
        return 1 if summary["failed"] else 0

    if args.cmd == "list":
        data = json.loads(args.assets.read_text(encoding="utf-8"))
        game = args.assets.parent
        print("| Name | File (under game/) | Frame px | Frames | Kind | Landed |")
        print("| --- | --- | --- | --- | --- | --- |")
        for name, a in data["assets"].items():
            if args.prefix and not name.startswith(args.prefix.rstrip(".") + "."):
                continue
            landed = (game / a["file"]).exists()
            if args.missing and landed:
                continue
            w, h = a["frame_size"]
            print(f"| `{name}` | `{a['file']}` | {w}x{h} | {a.get('frames', 1)} | {a.get('kind', '')} | {'yes' if landed else 'no'} |")
        return 0

    if args.cmd == "render":
        opts = {"quality": args.quality}
        if args.kind == "image":
            opts["shape"] = args.shape
        if args.source:
            opts["source"] = {"library": args.source}
        record = media.render(media.Client(), args.kind, args.prompt, args.output, **opts)
        print(json.dumps(record, indent=2))
        return 1 if record["problems"] else 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
