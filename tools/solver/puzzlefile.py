# SPDX-License-Identifier: AGPL-3.0-or-later
"""Load and structurally validate puzzles/ files (machine files and backs.yaml).

The structure mirrors puzzles/schema.json. Error messages name field paths,
never field values, so they cannot leak answers into CI logs.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import yamlsub
from .core import Domain, Fact

STYLES = ("poem", "animal", "trivia", "security", "code", "hardware")
APPROACHABLE_STYLES = STYLES[:4]
DIRECTION_WORDS = ("right", "left", "before", "after", "above", "below")
LUCKY_SUFFIX = " Lucky word: "
LUCKY_WORD_RE = re.compile(r"[A-Z]{3,8}\Z")
ID_RE = re.compile(r"[a-z][a-z0-9_]*\Z")
BACKS_FILE = "backs.yaml"


@dataclass
class Clue:
    id: str
    style: str
    approachable: bool
    fortune_text: str
    lucky_word: str
    fact: Fact | None
    nudge: str
    char_count: int


@dataclass
class Machine:
    path: Path
    id: str
    name: str
    items: list[tuple[str, str]]
    positions: list[tuple[int, str]]
    answer: dict[str, int]
    clues: list[Clue]
    errors: list[str] = field(default_factory=list)
    puzzle_title: str = ""
    position_noun: str = ""
    item_noun: str = ""

    @property
    def domain(self) -> Domain:
        return Domain(tuple(item_id for item_id, _ in self.items))


@dataclass
class Backs:
    path: Path
    packs: list[dict[str, Any]]
    start_code: str
    errors: list[str] = field(default_factory=list)


def _get(data: Any, key: str, kind: type | tuple[type, ...], errors: list[str], where: str) -> Any:
    if not isinstance(data, dict) or key not in data:
        errors.append(f"{where}.{key}: missing")
        return None
    value = data[key]
    if kind is int and isinstance(value, bool):
        errors.append(f"{where}.{key}: must be an integer")
        return None
    if not isinstance(value, kind):
        errors.append(f"{where}.{key}: wrong type")
        return None
    return value


def load_machine(path: Path) -> Machine:
    errors: list[str] = []
    try:
        data = yamlsub.load_path(path)
    except (OSError, yamlsub.YamlSubsetError) as exc:
        return Machine(path, path.stem, path.stem, [], [], {}, [], [f"{path.name}: {exc}"])
    if not isinstance(data, dict):
        return Machine(path, path.stem, path.stem, [], [], {}, [], [f"{path.name}: top level must be a mapping"])

    allowed_top = {"schema_version", "machine", "domain", "answer", "clues", "generator"}
    for key in data:
        if key not in allowed_top:
            errors.append(f"{key}: unknown top-level key")
    if data.get("schema_version") != 1:
        errors.append("schema_version: must be 1")

    meta = _get(data, "machine", dict, errors, "") or {}
    mid = _get(meta, "id", str, errors, "machine") or path.stem
    name = _get(meta, "name", str, errors, "machine") or mid
    puzzle_title = _get(meta, "puzzle_title", str, errors, "machine") or ""
    if not ID_RE.match(mid):
        errors.append("machine.id: must be lowercase letters, digits and underscores")

    domain = _get(data, "domain", dict, errors, "") or {}
    raw_items = _get(domain, "items", list, errors, "domain") or []
    items: list[tuple[str, str]] = []
    for i, item in enumerate(raw_items):
        iid = _get(item, "id", str, errors, f"domain.items[{i}]")
        iname = _get(item, "name", str, errors, f"domain.items[{i}]")
        if iid is not None and not ID_RE.match(iid):
            errors.append(f"domain.items[{i}].id: must be lowercase letters, digits and underscores")
        if iid is not None and iname is not None:
            items.append((iid, iname))
    if len({i for i, _ in items}) != len(items):
        errors.append("domain.items: ids must be unique")
    raw_positions = _get(domain, "positions", list, errors, "domain") or []
    positions: list[tuple[int, str]] = []
    for i, pos in enumerate(raw_positions):
        index = _get(pos, "index", int, errors, f"domain.positions[{i}]")
        label = _get(pos, "label", str, errors, f"domain.positions[{i}]")
        if index is not None and label is not None:
            positions.append((index, label))
    if [p for p, _ in positions] != list(range(1, len(positions) + 1)):
        errors.append("domain.positions: indexes must run 1..n in order")
    if len(items) != 5 or len(positions) != 5:
        errors.append("domain: needs exactly 5 items and 5 positions (decision D3)")
    for key in ("item_noun", "position_noun", "order"):
        _get(domain, key, str, errors, "domain")

    answer_raw = _get(data, "answer", dict, errors, "") or {}
    answer: dict[str, int] = {}
    for key, value in answer_raw.items():
        if isinstance(value, bool) or not isinstance(value, int):
            errors.append("answer: every value must be an integer position")
        else:
            answer[key] = value
    item_ids = [i for i, _ in items]
    if items and (set(answer) != set(item_ids) or sorted(answer.values()) != list(range(1, len(item_ids) + 1))):
        errors.append("answer: must place every item at a distinct position 1..n")

    clues: list[Clue] = []
    raw_clues = _get(data, "clues", list, errors, "") or []
    for i, raw in enumerate(raw_clues):
        where = f"clues[{i}]"
        cid = _get(raw, "id", str, errors, where) or f"{mid}_clue{i}"
        if not ID_RE.match(cid):
            errors.append(f"{where}.id: must be lowercase letters, digits and underscores")
        where = f"clue {cid}"
        allowed = {"id", "style", "approachable", "fortune_text", "lucky_word", "fact", "nudge", "char_count"}
        for key in raw if isinstance(raw, dict) else ():
            if key not in allowed:
                errors.append(f"{where}.{key}: unknown key")
        style = _get(raw, "style", str, errors, where) or ""
        if style and style not in STYLES:
            errors.append(f"{where}.style: must be one of {', '.join(STYLES)}")
        approachable = _get(raw, "approachable", bool, errors, where)
        text = _get(raw, "fortune_text", str, errors, where) or ""
        word = _get(raw, "lucky_word", str, errors, where) or ""
        nudge = _get(raw, "nudge", str, errors, where) or ""
        if not nudge.strip():
            errors.append(f"{where}.nudge: must not be empty")
        count = _get(raw, "char_count", int, errors, where)
        fact = None
        raw_fact = _get(raw, "fact", dict, errors, where)
        if raw_fact is not None:
            kind = raw_fact.get("kind")
            expected = {"position": {"kind", "item", "position"}, "offset": {"kind", "item", "relative_to", "offset"}}
            if kind not in expected or set(raw_fact) != expected[kind]:
                errors.append(f"{where}.fact: must be a position or offset fact with exactly its fields")
            else:
                try:
                    fact = Fact.from_dict(raw_fact)
                    if item_ids:
                        Domain(tuple(item_ids)).validate_fact(fact)
                except (ValueError, KeyError):
                    errors.append(f"{where}.fact: invalid for this domain")
                    fact = None
        clues.append(
            Clue(cid, style, bool(approachable), text, word, fact, nudge, count if count is not None else -1)
        )
    if len({c.id for c in clues}) != len(clues):
        errors.append("clues: ids must be unique")
    return Machine(
        path,
        mid,
        name,
        items,
        positions,
        answer,
        clues,
        errors,
        puzzle_title=puzzle_title,
        position_noun=domain.get("position_noun", "") if isinstance(domain.get("position_noun"), str) else "",
        item_noun=domain.get("item_noun", "") if isinstance(domain.get("item_noun"), str) else "",
    )


def load_backs(path: Path) -> Backs:
    errors: list[str] = []
    try:
        data = yamlsub.load_path(path)
    except (OSError, yamlsub.YamlSubsetError) as exc:
        return Backs(path, [], "", [f"{path.name}: {exc}"])
    if not isinstance(data, dict):
        return Backs(path, [], "", [f"{path.name}: top level must be a mapping"])
    if data.get("schema_version") != 1:
        errors.append("schema_version: must be 1")
    packs_raw = _get(data, "packs", list, errors, "") or []
    packs = []
    for i, pack in enumerate(packs_raw):
        where = f"packs[{i}]"
        pid = _get(pack, "id", str, errors, where)
        text = _get(pack, "text", str, errors, where)
        numbers = _get(pack, "lucky_numbers", str, errors, where)
        count = _get(pack, "char_count", int, errors, where)
        if None not in (pid, text, numbers, count):
            packs.append({"id": pid, "text": text, "lucky_numbers": numbers, "char_count": count})
    start_code = _get(data, "start_code", str, errors, "") or ""
    return Backs(path, packs, start_code, errors)


def discover(puzzle_dir: Path) -> tuple[list[Path], Path | None]:
    machine_files = sorted(p for p in puzzle_dir.glob("*.yaml") if p.name != BACKS_FILE)
    backs = puzzle_dir / BACKS_FILE
    return machine_files, backs if backs.exists() else None
