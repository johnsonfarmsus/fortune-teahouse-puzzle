#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Check the story text in game/data/story/ (stdlib only).

Validates every story file against game/data/story/schema.json (a small subset
of JSON Schema: type, enum, required, properties, additionalProperties, items,
minItems, maxItems, minLength, maxLength, pattern, anyOf and local $ref), then:

- ASCII only (printable, no smart quotes or dashes) in every string;
- at most 3 lines per piece and 90 characters per line, with placeholders
  expanded to their longest value;
- only known placeholders; unique ids across all files;
- machine and part ids in 'where' and 'when' exist in game/data/machines/;
- every machine part has a Gnu note;
- no puzzle answers: logic item plus position, wiring sockets, filled-in rhyme
  words, step labels and correct helper choices.

Usage: python3 tools/dev/check-story.py [repo_root]
Exit status 0 when everything passes, 1 otherwise.
"""

import json
import re
import sys
from pathlib import Path

MAX_LINES = 3
MAX_CHARS = 90
NAME_MAX = 20  # LetterKeypad display-name limit (ARCHITECTURE.md section 5)


def validate(value, schema, root, path, errors):
    """Validate value against the schema subset; append messages to errors."""
    if "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/"):
            errors.append(f"{path}: unsupported $ref {ref}")
            return
        target = root
        for key in ref[2:].split("/"):
            target = target[key]
        validate(value, target, root, path, errors)
        return
    kind = schema.get("type")
    checks = {
        "object": lambda v: isinstance(v, dict),
        "array": lambda v: isinstance(v, list),
        "string": lambda v: isinstance(v, str),
        "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    }
    if kind and not checks[kind](value):
        errors.append(f"{path}: expected {kind}")
        return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} is not one of {schema['enum']}")
    if "anyOf" in schema:
        if not any(not _errors_for(value, s, root, path) for s in schema["anyOf"]):
            errors.append(f"{path}: matches none of anyOf")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing '{key}'")
        props = schema.get("properties", {})
        for key, item in value.items():
            if key in props:
                validate(item, props[key], root, f"{path}.{key}", errors)
            elif schema.get("additionalProperties") is False and "properties" in schema:
                errors.append(f"{path}: unexpected '{key}'")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{path}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: more than {schema['maxItems']} items")
        if "items" in schema:
            for i, item in enumerate(value):
                validate(item, schema["items"], root, f"{path}[{i}]", errors)
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{path}: longer than {schema['maxLength']} ({len(value)})")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{path}: {value!r} does not match {schema['pattern']}")


def _errors_for(value, schema, root, path):
    errs = []
    validate(value, schema, root, path, errs)
    return errs


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def load_game_data(repo):
    """Machines, parts, placeholder maxima and forbidden answer patterns."""
    machines = {}
    part_titles = []
    forbidden = []  # (regex, reason)
    machine_titles = []
    for path in sorted((repo / "game/data/machines").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        machine = data["machine"]
        machines[machine] = [p["part"] for p in data["parts"]]
        for part in data["parts"]:
            part_titles.append(part["title"])
            config = part.get("config", {})
            where = f"{machine}/{part['part']}"
            if part["type"] == "wiring":
                for socket in config.get("sockets", []):
                    label = re.split(r"[(:]", socket["label"])[0].strip()
                    forbidden.append((r"\b" + re.escape(label) + r"\b", f"wiring socket in {where}"))
            elif part["type"] == "word":
                answers = {b["index"]: b["answer"] for b in config.get("blanks", [])}
                for line in config.get("lines", []):
                    for n, answer in answers.items():
                        mark = "{%d}" % n
                        if mark in line:
                            before = line.split(mark)[0].split()[-2:]
                            phrase = r"\s+".join(re.escape(w) for w in before + [answer])
                            forbidden.append((r"\b" + phrase + r"\b", f"rhyme answer in {where}"))
            elif part["type"] == "sequence":
                for step in config.get("steps", []):
                    forbidden.append((re.escape(step["label"]), f"step label in {where}"))
            elif part["type"] == "helper":
                correct = config["choices"][int(config["correct"])]
                forbidden.append((re.escape(correct), f"helper answer in {where}"))
    for path in sorted((repo / "game/data/puzzles").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        machine_titles.append(data["title"])
        domain = data["domain"]
        names = domain.get("item_names", {})
        noun = domain.get("position_noun", "").split()[-1]
        position = r"\b(%s|%s|slot|jar|zone|position)s?\s*(no\.?\s*)?[1-5]\b" % (
            re.escape(noun), "|".join(re.escape(p.split()[0]) for p in domain["positions"]))
        for item in domain["items"]:
            name = names.get(item, item)
            forbidden.append(("ITEM:" + r"\b" + re.escape(name) + r"\b", position))
    ids_gd = (repo / "game/scripts/core/ids.gd").read_text(encoding="utf-8")
    match = re.search(r'REPO_URL\s*:?=\s*"([^"]+)"', ids_gd)
    longest = {
        "name": "W" * NAME_MAX,
        "machine": max(machine_titles, key=len),
        "part": max(part_titles, key=len),
        "repo_url": match.group(1) if match else "https://example.org/" + "x" * 40,
    }
    return machines, longest, forbidden


def check_answers(line, forbidden):
    problems = []
    for pattern, reason in forbidden:
        if pattern.startswith("ITEM:"):
            item = pattern[5:]
            if re.search(item, line, re.I) and re.search(reason, line, re.I):
                problems.append("logic item and position in one line")
        elif re.search(pattern, line, re.I):
            problems.append(reason)
    return problems


def main():
    repo = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    story_dir = repo / "game/data/story"
    schema = json.loads((story_dir / "schema.json").read_text(encoding="utf-8"))
    machines, longest, forbidden = load_game_data(repo)
    errors = []
    seen = {}
    counts = {}
    covered = set()
    files = sorted(p for p in story_dir.glob("*.json") if p.name != "schema.json")
    if not files:
        errors.append(f"{story_dir}: no story files")
    for path in files:
        rel = path.relative_to(repo)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            errors.append(f"{rel}: not valid JSON: {exc}")
            continue
        validate(data, schema, schema, str(rel), errors)
        for text in strings_in(data):
            bad = sorted({c for c in text if not (" " <= c <= "~")})
            if bad:
                errors.append(f"{rel}: non-ASCII {bad!r} in {text[:40]!r}")
        for i, entry in enumerate(data.get("pieces", []) + data.get("concepts", [])):
            if not isinstance(entry, dict):
                continue
            ident = entry.get("id", f"#{i}")
            where = f"{rel} {ident}"
            if ident in seen:
                errors.append(f"{where}: duplicate id (also in {seen[ident]})")
            seen[ident] = rel
        for piece in data.get("pieces", []):
            if not isinstance(piece, dict):
                continue
            ident = piece.get("id", "?")
            where = f"{rel} {ident}"
            counts[piece.get("speaker")] = counts.get(piece.get("speaker"), 0) + 1
            lines = piece.get("lines", [])
            if len(lines) > MAX_LINES:
                errors.append(f"{where}: {len(lines)} lines (max {MAX_LINES})")
            for line in lines if isinstance(lines, list) else []:
                if not isinstance(line, str):
                    continue
                for key in re.findall(r"\{([^}]*)\}", line):
                    if key not in longest:
                        errors.append(f"{where}: unknown placeholder {{{key}}}")
                expanded = re.sub(r"\{([a-z_]+)\}", lambda m: longest.get(m.group(1), m.group(0)), line)
                if len(expanded) > MAX_CHARS:
                    errors.append(f"{where}: {len(expanded)} characters expanded (max {MAX_CHARS}): {line!r}")
                for problem in check_answers(line, forbidden):
                    errors.append(f"{where}: possible puzzle answer ({problem}): {line!r}")
            for field in ("where", "when"):
                value = str(piece.get(field, ""))
                m = re.search(r":([a-z_]+)(?:/([a-z_]+))?$", value)
                if not m or value.startswith("town:") or value.startswith("room:"):
                    continue
                machine, part = m.group(1), m.group(2)
                if machine == "crew" and value.startswith("machine_running:"):
                    continue
                if machine not in machines:
                    errors.append(f"{where}: unknown machine '{machine}' in {field}")
                elif part is not None and part not in machines[machine]:
                    errors.append(f"{where}: unknown part '{machine}/{part}' in {field}")
            if piece.get("speaker") == "Gnu" and str(piece.get("where", "")).startswith("puzzle:"):
                covered.add(piece["where"][len("puzzle:"):])
    for machine, parts in machines.items():
        for part in parts:
            if f"{machine}/{part}" not in covered:
                errors.append(f"no Gnu note for {machine}/{part}")
    for message in errors:
        print("ERROR:", message)
    summary = ", ".join(f"{k}: {v}" for k, v in sorted(counts.items(), key=lambda kv: str(kv[0])))
    print(f"{len(files)} story files, {sum(counts.values())} pieces ({summary}).")
    print("FAILED" if errors else "OK")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
