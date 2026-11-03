# SPDX-License-Identifier: AGPL-3.0-or-later
"""Turn a large, softly shaded render into true pixel art for the game.

Steps (DESIGN.md "The generation pipeline", step 3):

1. Remove the background: flood-fill from the border through every pixel close
   to the border's dominant colour, so the subject must sit on a plain backdrop.
2. Crop to the subject (optionally to part of it, such as head and shoulders).
3. Lock to the palette at a working size, then shrink to the sprite grid by
   taking the most common palette colour in each cell. This is nearest-neighbour
   in spirit (every output pixel is a real palette colour from its cell) without
   the noise of sampling single pixels from a 1024 px render.
4. Drop small islands (crop leftovers such as the tip of a tail), then keep at
   most ``max_colors`` colours, merging the rarest into their nearest.
5. Add a 1 px outline around the subject.
"""

from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass

from PIL import Image

from .palette import RGB, Matcher, distance2

# Work at this many pixels per output pixel: enough for a stable "most common"
# vote per cell, small enough to stay fast in pure Python.
WORK_SCALE = 8


@dataclass
class Options:
    size: tuple[int, int]
    palette: dict[str, RGB]
    max_colors: int = 0  # 0 means no limit beyond the palette
    outline: str | None = "black"  # palette name, or None for no outline
    background: str | None = None  # palette name to fill behind the subject
    crop: tuple[float, float, float, float] = (0.0, 0.0, 1.0, 1.0)  # of the subject box
    anchor: str = "center"  # "center" or "bottom"
    bg_tolerance: float = 60.0  # redmean distance from the backdrop colour
    alpha_threshold: int = 128
    keep_alpha: bool = False  # trust the source alpha; skip background removal
    speck_share: float = 0.15  # drop islands under this share of the largest; 0 keeps all
    holes: bool = True  # also clear enclosed backdrop (ring middles)


def _border_colour(img: Image.Image) -> RGB:
    w, h = img.size
    px = img.load()
    border = [px[x, 0][:3] for x in range(w)] + [px[x, h - 1][:3] for x in range(w)]
    border += [px[0, y][:3] for y in range(h)] + [px[w - 1, y][:3] for y in range(h)]
    # Bucket to 8 levels per channel so JPEG-ish noise votes together.
    buckets = Counter((r >> 5, g >> 5, b >> 5) for r, g, b in border)
    top = buckets.most_common(1)[0][0]
    members = [c for c in border if (c[0] >> 5, c[1] >> 5, c[2] >> 5) == top]
    n = len(members)
    return (sum(c[0] for c in members) // n, sum(c[1] for c in members) // n, sum(c[2] for c in members) // n)


def remove_background(img: Image.Image, tolerance: float, holes: bool = True) -> Image.Image:
    """Make the backdrop connected to the border transparent. With ``holes``, also
    clear enclosed patches of backdrop (the middle of a ring, the gap under a
    handle) that are at least a few pixels across and closer to the backdrop
    colour than ``tolerance``."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    bg = _border_colour(img)
    tol2 = tolerance * tolerance
    seen = bytearray(w * h)
    queue: deque[tuple[int, int]] = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))
    while queue:
        x, y = queue.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, a = px[x, y]
        if a and distance2((r, g, b), bg) > tol2:
            continue
        px[x, y] = (0, 0, 0, 0)
        if x > 0:
            queue.append((x - 1, y))
        if x < w - 1:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y < h - 1:
            queue.append((x, y + 1))
    if holes:
        _clear_holes(px, w, h, bg, tol2)
    return img


def _clear_holes(px, w: int, h: int, bg: RGB, tol2: float, min_size: int = 24) -> None:
    """Clear enclosed regions of backdrop colour big enough not to be detail."""
    seen = bytearray(w * h)
    for start in range(w * h):
        if seen[start]:
            continue
        sx, sy = start % w, start // w
        r, g, b, a = px[sx, sy]
        if not a or distance2((r, g, b), bg) > tol2:
            seen[start] = 1
            continue
        region, stack = [], [start]
        seen[start] = 1
        while stack:
            i = stack.pop()
            region.append(i)
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if not seen[j]:
                        rr, gg, bb, aa = px[nx, ny]
                        if aa and distance2((rr, gg, bb), bg) <= tol2:
                            seen[j] = 1
                            stack.append(j)
        if len(region) >= min_size:
            for i in region:
                px[i % w, i // w] = (0, 0, 0, 0)


def _subject_box(img: Image.Image, threshold: int) -> tuple[int, int, int, int]:
    alpha = img.getchannel("A").point(lambda a: 255 if a >= threshold else 0)
    box = alpha.getbbox()
    if box is None:
        raise ValueError("nothing left after background removal; is the backdrop plain?")
    return box


def _reduce_colours(cells: list[RGB | None], limit: int) -> list[RGB | None]:
    counts = Counter(c for c in cells if c is not None)
    if limit <= 0 or len(counts) <= limit:
        return cells
    keep = [c for c, _ in counts.most_common(limit)]
    remap = {c: min(keep, key=lambda k: distance2(c, k)) for c in counts if c not in keep}
    return [remap.get(c, c) if c is not None else None for c in cells]


def _drop_specks(cells: list[RGB | None], w: int, h: int, keep_share: float) -> list[RGB | None]:
    """Clear opaque islands smaller than ``keep_share`` of the largest one."""
    label = [-1] * len(cells)
    sizes: list[int] = []
    for start, c in enumerate(cells):
        if c is None or label[start] >= 0:
            continue
        n = len(sizes)
        label[start] = n
        stack, size = [start], 0
        while stack:
            i = stack.pop()
            size += 1
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                j = ny * w + nx
                if 0 <= nx < w and 0 <= ny < h and cells[j] is not None and label[j] < 0:
                    label[j] = n
                    stack.append(j)
        sizes.append(size)
    if not sizes:
        return cells
    floor = max(sizes) * keep_share
    return [c if c is None or sizes[label[i]] >= floor else None for i, c in enumerate(cells)]


def pixelize(src: Image.Image, opts: Options, names: dict[str, RGB] | None = None) -> Image.Image:
    """``names`` resolves the outline and background names (default: ``opts.palette``)."""
    names = names or opts.palette
    out_w, out_h = opts.size
    pad = 1 if opts.outline else 0
    inner_w, inner_h = out_w - 2 * pad, out_h - 2 * pad
    if inner_w < 1 or inner_h < 1:
        raise ValueError(f"size {out_w}x{out_h} leaves no room inside the outline")

    img = src.convert("RGBA")
    # Bring huge renders down first so background removal stays fast.
    longest = max(img.size)
    limit = max(out_w, out_h) * WORK_SCALE * 2
    if longest > limit:
        f = limit / longest
        img = img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.LANCZOS)
    if not opts.keep_alpha:
        img = remove_background(img, opts.bg_tolerance, opts.holes)

    x0, y0, x1, y1 = _subject_box(img, opts.alpha_threshold)
    cx0, cy0, cx1, cy1 = opts.crop
    bw, bh = x1 - x0, y1 - y0
    img = img.crop((x0 + round(cx0 * bw), y0 + round(cy0 * bh), x0 + round(cx1 * bw), y0 + round(cy1 * bh)))

    # Fit the subject in the inner area, keeping its aspect ratio.
    scale = min(inner_w / img.width, inner_h / img.height)
    cells_w = max(1, min(inner_w, round(img.width * scale)))
    cells_h = max(1, min(inner_h, round(img.height * scale)))
    work = img.resize((cells_w * WORK_SCALE, cells_h * WORK_SCALE), Image.LANCZOS)

    matcher = Matcher(opts.palette)
    wpx = work.load()
    cells: list[RGB | None] = []
    for cy in range(cells_h):
        for cx in range(cells_w):
            votes: Counter[RGB] = Counter()
            clear = 0
            for y in range(cy * WORK_SCALE, (cy + 1) * WORK_SCALE):
                for x in range(cx * WORK_SCALE, (cx + 1) * WORK_SCALE):
                    r, g, b, a = wpx[x, y]
                    if a < opts.alpha_threshold:
                        clear += 1
                    else:
                        votes[matcher.nearest((r, g, b))] += 1
            if clear * 2 > WORK_SCALE * WORK_SCALE or not votes:
                cells.append(None)
            else:
                cells.append(votes.most_common(1)[0][0])
    if opts.speck_share > 0:
        cells = _drop_specks(cells, cells_w, cells_h, opts.speck_share)
    cells = _reduce_colours(cells, opts.max_colors)

    out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    ox = pad + (inner_w - cells_w) // 2
    oy = pad + (inner_h - cells_h if opts.anchor == "bottom" else (inner_h - cells_h) // 2)
    opx = out.load()
    for i, c in enumerate(cells):
        if c is not None:
            opx[ox + i % cells_w, oy + i // cells_w] = (*c, 255)

    if opts.outline:
        ink = (*names[opts.outline], 255)
        solid = {(x, y) for y in range(out_h) for x in range(out_w) if opx[x, y][3]}
        for x, y in list(solid):
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < out_w and 0 <= ny < out_h and (nx, ny) not in solid:
                    opx[nx, ny] = ink

    if opts.background:
        bg = Image.new("RGBA", out.size, (*names[opts.background], 255))
        bg.alpha_composite(out)
        out = bg
    return out


def preview(img: Image.Image, scale: int) -> Image.Image:
    """Whole-number upscale with no smoothing, for looking at the result."""
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)
