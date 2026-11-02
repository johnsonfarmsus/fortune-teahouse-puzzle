# SPDX-License-Identifier: AGPL-3.0-or-later
"""A loader for the small YAML subset used in puzzles/ (standard library only).

Supported: block mappings, block sequences (including "- key: value" items),
full-line and trailing comments, double-quoted strings (JSON escapes),
single-quoted strings, integers, true/false/null, and plain strings.
Not supported (rejected with an error): flow collections, block scalars
(| and >), anchors, aliases, tags, multi-document streams and tabs.
Every puzzles/ file must also parse identically with a full YAML parser; the
test suite checks that when PyYAML is installed.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

_INT = re.compile(r"[-+]?(0|[1-9][0-9]*)\Z")
_KEY = re.compile(r"([A-Za-z0-9_][A-Za-z0-9_\-]*)\s*:(?:\s+|\Z)")


class YamlSubsetError(ValueError):
    pass


@dataclass
class _Line:
    number: int
    indent: int
    text: str  # without indentation, comments kept until parsed


def _lines(source: str) -> list[_Line]:
    out = []
    for number, raw in enumerate(source.splitlines(), start=1):
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise YamlSubsetError(f"line {number}: tabs are not allowed for indentation")
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped in ("---", "..."):
            if out:
                raise YamlSubsetError(f"line {number}: only one document per file")
            continue
        out.append(_Line(number, len(raw) - len(raw.lstrip(" ")), raw.strip()))
    return out


def _scan_quoted(text: str, number: int) -> tuple[str, str]:
    """Split a leading quoted string from the rest of the text."""
    quote = text[0]
    i = 1
    while i < len(text):
        ch = text[i]
        if quote == '"' and ch == "\\":
            i += 2
            continue
        if ch == quote:
            if quote == "'" and i + 1 < len(text) and text[i + 1] == "'":
                i += 2
                continue
            body, rest = text[: i + 1], text[i + 1 :]
            if quote == '"':
                try:
                    value = json.loads(body)
                except json.JSONDecodeError as exc:
                    raise YamlSubsetError(f"line {number}: bad double-quoted string ({exc.msg})") from None
            else:
                value = body[1:-1].replace("''", "'")
            return value, rest
        i += 1
    raise YamlSubsetError(f"line {number}: unterminated quoted string")


def _scalar(text: str, number: int) -> object:
    text = text.strip()
    if not text:
        return None
    if text[0] in "\"'":
        value, rest = _scan_quoted(text, number)
        rest = rest.strip()
        if rest and not rest.startswith("#"):
            raise YamlSubsetError(f"line {number}: unexpected text after quoted string")
        return value
    if text[0] in "[{|>&*!%@`":
        raise YamlSubsetError(f"line {number}: unsupported YAML syntax {text[0]!r}")
    # trailing comment on a plain scalar
    hash_at = text.find(" #")
    if hash_at >= 0:
        text = text[:hash_at].rstrip()
    if ": " in text or text.endswith(":"):
        raise YamlSubsetError(f"line {number}: quote plain strings that contain ': '")
    if text in ("null", "~", "Null", "NULL"):
        return None
    if text in ("true", "True", "TRUE"):
        return True
    if text in ("false", "False", "FALSE"):
        return False
    if _INT.match(text):
        return int(text)
    return text


class _Parser:
    def __init__(self, lines: list[_Line]):
        self.lines = lines
        self.i = 0

    def peek(self) -> _Line | None:
        return self.lines[self.i] if self.i < len(self.lines) else None

    def parse_block(self, indent: int) -> object:
        line = self.peek()
        if line is None:
            return None
        if line.indent != indent:
            raise YamlSubsetError(f"line {line.number}: unexpected indentation")
        if line.text == "-" or line.text.startswith("- "):
            return self.parse_sequence(indent)
        return self.parse_mapping(indent)

    def parse_mapping(self, indent: int, first: str | None = None, first_number: int = 0) -> dict:
        result: dict[str, object] = {}
        pending = first
        while True:
            if pending is not None:
                text, number = pending, first_number
                pending = None
            else:
                line = self.peek()
                if line is None or line.indent < indent:
                    break
                if line.indent > indent:
                    raise YamlSubsetError(f"line {line.number}: unexpected indentation")
                if line.text.startswith("- ") or line.text == "-":
                    raise YamlSubsetError(f"line {line.number}: sequence item inside a mapping")
                text, number = line.text, line.number
                self.i += 1
            match = _KEY.match(text)
            if not match:
                raise YamlSubsetError(f"line {number}: expected 'key: value'")
            key = match.group(1)
            if key in result:
                raise YamlSubsetError(f"line {number}: duplicate key {key!r}")
            rest = text[match.end() :]
            if rest.strip() and not rest.strip().startswith("#"):
                result[key] = _scalar(rest, number)
            else:
                nxt = self.peek()
                if nxt is not None and nxt.indent > indent:
                    result[key] = self.parse_block(nxt.indent)
                elif nxt is not None and nxt.indent == indent and (nxt.text.startswith("- ") or nxt.text == "-"):
                    # a sequence may sit at the same indentation as its key
                    result[key] = self.parse_sequence(indent)
                else:
                    result[key] = None
        return result

    def parse_sequence(self, indent: int) -> list:
        result: list[object] = []
        while True:
            line = self.peek()
            if line is None or line.indent < indent:
                break
            if line.indent > indent or not (line.text.startswith("- ") or line.text == "-"):
                if line.indent == indent:
                    break  # back to the parent mapping's keys
                raise YamlSubsetError(f"line {line.number}: unexpected indentation")
            self.i += 1
            body = line.text[1:].lstrip(" ")
            item_indent = indent + (len(line.text) - len(body))
            if not body or body.startswith("#"):
                nxt = self.peek()
                result.append(self.parse_block(nxt.indent) if nxt is not None and nxt.indent > indent else None)
            elif body.startswith("- "):
                raise YamlSubsetError(f"line {line.number}: nested inline sequences are not supported")
            elif _KEY.match(body) and body[0] not in "\"'":
                result.append(self.parse_mapping(item_indent, first=body, first_number=line.number))
            else:
                result.append(_scalar(body, line.number))
        return result


def loads(source: str) -> object:
    lines = _lines(source)
    if not lines:
        return None
    parser = _Parser(lines)
    value = parser.parse_block(lines[0].indent)
    if parser.peek() is not None:
        raise YamlSubsetError(f"line {parser.peek().number}: unexpected indentation")
    return value


def load_path(path: str | Path) -> object:
    return loads(Path(path).read_text(encoding="utf-8"))
