# SPDX-License-Identifier: AGPL-3.0-or-later
"""Configuration and fixed vocabularies (crews, parts, handoffs, nudges)."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone

MACHINES = ("fortune_machine", "cookie_machine", "oven")
PARTS = ("logic", "wiring", "sequence", "word", "rhythm", "helper")

# (id, display name, from machine, to). `to` is a machine id or "packaging"
# (not a crew machine, so it never blocks a handoff).
HANDOFFS = (
    ("cookie_to_oven", "Cookie Machine to Oven", "cookie_machine", "oven"),
    ("fortune_to_oven", "Fortune Machine to Oven", "fortune_machine", "oven"),
    ("oven_to_packaging", "Oven to packaging", "oven", "packaging"),
)

# Fixed allowlist of mentor nudges. The game client maps ids to text.
NUDGES = (
    "reread_the_clue",
    "ask_a_crewmate",
    "start_with_the_sure_thing",
    "try_the_help_button",
    "check_neighbours",
    "look_at_the_order",
    "follow_the_wires",
    "listen_for_the_beat",
    "take_a_short_break",
    "compare_with_another_crew",
)

DEFAULT_REPO_URL = "https://github.com/johnsonfarmsus/fortune-teahouse-puzzle"


def parse_time(value: str) -> datetime:
    """Parse an ISO 8601 timestamp; an explicit offset (or Z) is required."""
    dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    if dt.tzinfo is None:
        raise ValueError(f"timestamp {value!r} needs a UTC offset, e.g. 2027-10-30T01:00:00Z")
    return dt.astimezone(timezone.utc)


def fmt_time(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_code(value: str) -> str:
    """Case-fold and drop punctuation/spaces so '3.141 592-653' == '3141592653'."""
    return re.sub(r"[^0-9a-z]", "", value.casefold())


def _csv(value: str) -> list[str]:
    return [p.strip() for p in value.split(",") if p.strip()]


@dataclass
class Settings:
    database_path: str = "/data/scoreboard.db"
    admin_secret: str = ""
    cors_origins: list[str] = field(default_factory=lambda: ["*"])
    finale_safety_net_at: datetime | None = None
    gnu_note_codes: list[str] = field(default_factory=list)
    gnu_notes_k: int = 3
    start_code: str = "3141592653"
    repo_url: str = DEFAULT_REPO_URL
    handoff_settings_total: int = 3
    rate_limit_rps: float = 50.0
    rate_limit_burst: int = 200
    trust_proxy: bool = False

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Settings":
        e = os.environ if env is None else env
        s = cls()
        s.database_path = e.get("DATABASE_PATH", s.database_path)
        s.admin_secret = e.get("ADMIN_SECRET", "")
        if e.get("CORS_ORIGINS", "").strip():
            s.cors_origins = _csv(e["CORS_ORIGINS"])
        if e.get("FINALE_SAFETY_NET_AT", "").strip():
            s.finale_safety_net_at = parse_time(e["FINALE_SAFETY_NET_AT"])
        s.gnu_note_codes = _csv(e.get("GNU_NOTE_CODES", ""))
        s.gnu_notes_k = int(e.get("GNU_NOTES_K", s.gnu_notes_k))
        s.start_code = e.get("START_CODE", s.start_code)
        s.repo_url = e.get("REPO_URL", s.repo_url)
        s.handoff_settings_total = int(e.get("HANDOFF_SETTINGS_TOTAL", s.handoff_settings_total))
        s.rate_limit_rps = float(e.get("RATE_LIMIT_RPS", s.rate_limit_rps))
        s.rate_limit_burst = int(e.get("RATE_LIMIT_BURST", s.rate_limit_burst))
        s.trust_proxy = e.get("TRUST_PROXY", "").lower() in ("1", "true", "yes")
        return s

    @property
    def note_codes_normalized(self) -> set[str]:
        return {normalize_code(c) for c in self.gnu_note_codes} - {""}

    @property
    def notes_total(self) -> int:
        return len(self.note_codes_normalized)

    @property
    def notes_needed(self) -> int:
        return min(self.gnu_notes_k, self.notes_total)
