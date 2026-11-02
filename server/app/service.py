# SPDX-License-Identifier: AGPL-3.0-or-later
"""Game rules and queries. Everything here takes an open sqlite3 connection."""
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime
from typing import Any, Iterator

from .config import (
    HANDOFFS,
    MACHINES,
    NUDGES,
    PARTS,
    Settings,
    fmt_time,
    normalize_code,
    parse_time,
)

MACHINE_NAMES = {
    "fortune_machine": "Fortune Machine",
    "cookie_machine": "Cookie Machine",
    "oven": "Oven",
}
ANONYMOUS = "anonymous"


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status = status
        self.code = code
        self.message = message


@contextmanager
def tx(conn: sqlite3.Connection) -> Iterator[None]:
    """Write transaction (takes the write lock up front so check-then-insert is safe)."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")


# ---------------------------------------------------------------- validation

def check_device_id(value: str) -> str:
    """device_id is an opaque string (the client sends 32 hex chars); stored and echoed unchanged."""
    if not value or len(value) > 64 or value != value.strip() or not value.isprintable():
        raise ValueError("device_id must be a non-empty string of at most 64 printable characters")
    return value


def check_machine(machine: str) -> str:
    if machine not in MACHINES:
        raise ApiError(404, "unknown_crew", f"Unknown crew {machine!r}. Use one of {list(MACHINES)}.")
    return machine


def check_part(part: str) -> str:
    if part not in PARTS:
        raise ApiError(404, "unknown_part", f"Unknown part {part!r}. Use one of {list(PARTS)}.")
    return part


def clean_display_name(value: str | None) -> str | None:
    if value is None:
        return None
    name = " ".join("".join(ch for ch in value if ch.isprintable()).split())
    if not name:
        return None
    if len(name) > 24:
        raise ValueError("display_name must be 24 characters or fewer")
    return name


# ------------------------------------------------------------------- devices

def get_device(conn: sqlite3.Connection, device_id: str) -> sqlite3.Row:
    row = conn.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
    if row is None:
        raise ApiError(404, "device_not_registered",
                       "Unknown device. POST /api/v1/devices first.")
    return row


def device_view(row: sqlite3.Row, created: bool | None = None) -> dict[str, Any]:
    out = {
        "device_id": row["id"],
        "display_name": row["display_name"],
        "crew": row["crew"],
        "created_at": row["created_at"],
    }
    if created is not None:
        out["created"] = created
    return out


def upsert_device(conn: sqlite3.Connection, device_id: str, fields: dict[str, Any], now: str) -> dict:
    """fields holds only the keys the caller sent (display_name, crew)."""
    if fields.get("crew") is not None and fields["crew"] not in MACHINES:
        raise ApiError(400, "unknown_crew", f"Unknown crew {fields['crew']!r}. Use one of {list(MACHINES)}.")
    with tx(conn):
        row = conn.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
        created = row is None
        if created:
            conn.execute(
                "INSERT INTO devices (id, display_name, crew, created_at, updated_at) VALUES (?,?,?,?,?)",
                (device_id, fields.get("display_name"), fields.get("crew"), now, now),
            )
        elif fields:
            merged = {"display_name": row["display_name"], "crew": row["crew"], **fields}
            conn.execute(
                "UPDATE devices SET display_name=?, crew=?, updated_at=? WHERE id=?",
                (merged["display_name"], merged["crew"], now, device_id),
            )
        row = conn.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
    return device_view(row, created)


# --------------------------------------------------------------------- crews

def machine_runs(conn: sqlite3.Connection, machine: str) -> bool:
    n = conn.execute(
        "SELECT COUNT(DISTINCT part) FROM part_solves WHERE machine=?", (machine,)
    ).fetchone()[0]
    return n >= len(PARTS)


def machines_running(conn: sqlite3.Connection) -> dict[str, bool]:
    rows = conn.execute(
        "SELECT machine, COUNT(DISTINCT part) AS n FROM part_solves GROUP BY machine"
    ).fetchall()
    counts = {r["machine"]: r["n"] for r in rows}
    return {m: counts.get(m, 0) >= len(PARTS) for m in MACHINES}


def contributors(conn: sqlite3.Connection, machine: str | None = None,
                 limit: int | None = None) -> list[dict[str, Any]]:
    sql = (
        "SELECT COALESCE(d.display_name, ?) AS name, c.machine, c.via, c.first_merged_at"
        " FROM contributors c JOIN devices d ON d.id=c.device_id"
    )
    args: list[Any] = [ANONYMOUS]
    if machine:
        sql += " WHERE c.machine=?"
        args.append(machine)
    sql += " ORDER BY c.first_merged_at DESC, c.rowid DESC"
    if limit:
        sql += " LIMIT ?"
        args.append(limit)
    rows = conn.execute(sql, args).fetchall()
    return [
        {"name": r["name"], "machine": r["machine"], "via": r["via"],
         "first_merged_at": r["first_merged_at"]}
        for r in rows
    ]


def contributor_count(conn: sqlite3.Connection) -> int:
    return conn.execute("SELECT COUNT(*) FROM contributors").fetchone()[0]


def crew_view(conn: sqlite3.Connection, machine: str, with_contributors: bool = True) -> dict[str, Any]:
    rows = conn.execute(
        "SELECT part, COUNT(*) AS n, MIN(solved_at) AS first FROM part_solves"
        " WHERE machine=? GROUP BY part", (machine,)
    ).fetchall()
    by_part = {r["part"]: r for r in rows}
    parts = []
    for p in PARTS:
        r = by_part.get(p)
        parts.append({
            "part": p,
            "solved": r is not None,
            "solved_count": r["n"] if r else 0,
            "first_solved_at": r["first"] if r else None,
        })
    solved = sum(1 for p in parts if p["solved"])
    members = conn.execute("SELECT COUNT(*) FROM devices WHERE crew=?", (machine,)).fetchone()[0]
    out: dict[str, Any] = {
        "machine": machine,
        "name": MACHINE_NAMES[machine],
        "runs": solved >= len(PARTS),
        "parts_solved": solved,
        "parts_total": len(PARTS),
        "members": members,
        "parts": parts,
    }
    if with_contributors:
        out["contributors"] = contributors(conn, machine)
    return out


def solve_part(conn: sqlite3.Connection, device_id: str, machine: str, part: str, now: str,
               credited: bool = True) -> dict:
    with tx(conn):
        dev = get_device(conn, device_id)
        if dev["crew"] != machine:
            raise ApiError(403, "not_in_crew",
                           f"Device is in crew {dev['crew']!r}, not {machine!r}. "
                           "POST /api/v1/devices to join first.")
        cur = conn.execute(
            "INSERT OR IGNORE INTO part_solves (device_id, machine, part, solved_at, credited)"
            " VALUES (?,?,?,?,?)", (device_id, machine, part, now, int(credited)),
        )
        newly = cur.rowcount == 1
        if credited:
            # A credited solve upgrades an earlier uncredited one for the same part.
            conn.execute(
                "UPDATE part_solves SET credited=1 WHERE device_id=? AND machine=? AND part=?",
                (device_id, machine, part))
            conn.execute(
                "INSERT OR IGNORE INTO contributors (device_id, machine, via, first_merged_at)"
                " VALUES (?,?,?,?)", (device_id, machine, "solve", now),
            )
        is_credited = conn.execute(
            "SELECT credited FROM part_solves WHERE device_id=? AND machine=? AND part=?",
            (device_id, machine, part)).fetchone()[0] == 1
    view = crew_view(conn, machine)
    return {"newly_solved": newly, "credited": is_credited, "crew": view}


# -------------------------------------------------------------------- finale

def _setting(conn: sqlite3.Connection, key: str) -> str | None:
    r = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return r["value"] if r else None


def set_setting(conn: sqlite3.Connection, key: str, value: str | None) -> None:
    if value is None:
        conn.execute("DELETE FROM settings WHERE key=?", (key,))
    else:
        conn.execute("INSERT INTO settings (key, value) VALUES (?,?)"
                     " ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))


def safety_net_at(conn: sqlite3.Connection, settings: Settings) -> datetime | None:
    """Admin-set time (stored in the database) wins over the environment variable."""
    stored = _setting(conn, "safety_net_at")
    if stored == "none":
        return None
    if stored:
        return parse_time(stored)
    return settings.finale_safety_net_at


def finale_gate(conn: sqlite3.Connection, settings: Settings, now: datetime) -> tuple[bool, str]:
    override = _setting(conn, "finale_override")
    if override == "open":
        return True, "admin"
    if override == "closed":
        return False, "admin_closed"
    if all(machines_running(conn).values()):
        return True, "all_machines_run"
    net = safety_net_at(conn, settings)
    if net is not None and now >= net:
        return True, "safety_net"
    return False, "closed"


def notes_view(conn: sqlite3.Connection, settings: Settings) -> dict[str, Any]:
    found = conn.execute("SELECT COUNT(*) FROM gnu_notes").fetchone()[0]
    return {
        "found": found,
        "total": settings.notes_total,
        "needed": settings.notes_needed,
        "complete": found >= settings.notes_needed,
    }


def handoffs_view(conn: sqlite3.Connection, is_open: bool, running: dict[str, bool]) -> list[dict]:
    solved = {
        (r["handoff_id"], r["setting_index"])
        for r in conn.execute("SELECT DISTINCT handoff_id, setting_index FROM handoff_settings")
    }
    out = []
    # keep the canonical order from config
    order = {h[0]: i for i, h in enumerate(HANDOFFS)}
    rows = sorted(conn.execute("SELECT * FROM handoffs").fetchall(), key=lambda r: order.get(r["id"], 99))
    for r in rows:
        total = r["settings_total"]
        idx = sorted(i for (h, i) in solved if h == r["id"] and 0 <= i < total)
        # A handoff waits for any crew machine it touches; "packaging" is not a crew.
        waiting = not running.get(r["from_machine"], True) or not running.get(r["to_machine"], True)
        if len(idx) >= total:
            status = "connected"
        elif not is_open:
            status = "locked"
        elif waiting:
            status = "waiting"
        elif idx:
            status = "in_progress"
        else:
            status = "not_started"
        out.append({
            "id": r["id"],
            "name": r["name"],
            "from_machine": r["from_machine"],
            "to_machine": r["to_machine"],
            "settings_total": total,
            "settings_solved": len(idx),
            "solved_indices": idx,
            "complete": len(idx) >= total,
            "available": is_open and not waiting,
            "status": status,
        })
    return out


def finale_view(conn: sqlite3.Connection, settings: Settings, now: datetime) -> dict[str, Any]:
    is_open, reason = finale_gate(conn, settings, now)
    running = machines_running(conn)
    handoffs = handoffs_view(conn, is_open, running)
    notes = notes_view(conn, settings)
    net = safety_net_at(conn, settings)
    started_at = _setting(conn, "line_started_at")
    return {
        "open": is_open,
        "open_reason": reason,
        "override": _setting(conn, "finale_override"),
        "safety_net_at": fmt_time(net) if net else None,
        "all_machines_run": all(running.values()),
        "handoffs": handoffs,
        "notes": notes,
        "line_ready": all(h["complete"] for h in handoffs) and notes["complete"],
        "started": started_at is not None,
        "started_at": started_at,
    }


def require_open(conn: sqlite3.Connection, settings: Settings, now: datetime) -> None:
    if not finale_gate(conn, settings, now)[0]:
        raise ApiError(403, "finale_closed",
                       "The finale is not open yet. It opens when all three machines run "
                       "or at the safety-net time.")


def solve_setting(conn: sqlite3.Connection, settings: Settings, now: datetime,
                  handoff_id: str, device_id: str, setting_index: int) -> dict:
    nowstr = fmt_time(now)
    with tx(conn):
        get_device(conn, device_id)
        h = conn.execute("SELECT * FROM handoffs WHERE id=?", (handoff_id,)).fetchone()
        if h is None:
            raise ApiError(404, "unknown_handoff", f"Unknown handoff {handoff_id!r}.")
        require_open(conn, settings, now)
        if not 0 <= setting_index < h["settings_total"]:
            raise ApiError(400, "bad_setting_index",
                           f"setting_index must be 0 to {h['settings_total'] - 1}.")
        running = machines_running(conn)
        if not running.get(h["from_machine"], True) or not running.get(h["to_machine"], True):
            raise ApiError(409, "handoff_waiting",
                           "This handoff waits for a machine that is not running yet.")
        cur = conn.execute(
            "INSERT OR IGNORE INTO handoff_settings (handoff_id, setting_index, device_id, solved_at)"
            " VALUES (?,?,?,?)", (handoff_id, setting_index, device_id, nowstr))
        newly = cur.rowcount == 1
    is_open, _ = finale_gate(conn, settings, now)
    hv = next(x for x in handoffs_view(conn, is_open, machines_running(conn)) if x["id"] == handoff_id)
    return {"newly_recorded": newly, "handoff": hv}


def submit_note(conn: sqlite3.Connection, settings: Settings, now: datetime,
                device_id: str, code: str) -> dict:
    nowstr = fmt_time(now)
    with tx(conn):
        get_device(conn, device_id)
        require_open(conn, settings, now)
        norm = normalize_code(code)
        valid = norm in settings.note_codes_normalized
        already = False
        if valid:
            cur = conn.execute(
                "INSERT OR IGNORE INTO gnu_notes (code, found_by, found_at) VALUES (?,?,?)",
                (norm, device_id, nowstr))
            already = cur.rowcount == 0
    return {"valid": valid, "already_found": already, "notes": notes_view(conn, settings)}


def start_line(conn: sqlite3.Connection, settings: Settings, now: datetime,
               device_id: str, code: str) -> dict:
    with tx(conn):
        get_device(conn, device_id)
        require_open(conn, settings, now)
        if normalize_code(code) != normalize_code(settings.start_code):
            return {"valid": False, "started": _setting(conn, "line_started_at") is not None,
                    "started_at": _setting(conn, "line_started_at")}
        fin = finale_view(conn, settings, now)
        if not fin["line_ready"] and not fin["started"]:
            raise ApiError(409, "line_not_ready",
                           "The start code is right, but not every handoff is connected and "
                           "enough of the gnu's notes are found yet.")
        if not fin["started"]:
            set_setting(conn, "line_started_at", fmt_time(now))
        at = _setting(conn, "line_started_at")
    return {"valid": True, "started": True, "started_at": at}


# --------------------------------------------------------------------- hints

def push_hint(conn: sqlite3.Connection, device_id: str, to_crew: str, nudge_id: str, now: str) -> dict:
    if to_crew not in MACHINES:
        raise ApiError(400, "unknown_crew", f"Unknown crew {to_crew!r}. Use one of {list(MACHINES)}.")
    if nudge_id not in NUDGES:
        raise ApiError(400, "unknown_nudge", f"Unknown nudge {nudge_id!r}. See GET /api/v1/hints/nudges.")
    with tx(conn):
        dev = get_device(conn, device_id)
        if dev["crew"] is None or not machine_runs(conn, dev["crew"]):
            raise ApiError(403, "not_a_maintainer",
                           "Only members of a crew whose machine runs can send hints.")
        if dev["crew"] == to_crew:
            raise ApiError(400, "own_crew", "Hints go to other crews.")
        cur = conn.execute(
            "INSERT OR IGNORE INTO hints (from_device, to_crew, nudge_id, created_at) VALUES (?,?,?,?)",
            (device_id, to_crew, nudge_id, now))
        created = cur.rowcount == 1
        # Mentors also appear on the helped crew's contributors list.
        conn.execute(
            "INSERT OR IGNORE INTO contributors (device_id, machine, via, first_merged_at)"
            " VALUES (?,?,?,?)", (device_id, to_crew, "mentor", now))
        row = conn.execute(
            "SELECT h.*, d.display_name FROM hints h JOIN devices d ON d.id=h.from_device"
            " WHERE h.from_device=? AND h.to_crew=? AND h.nudge_id=?",
            (device_id, to_crew, nudge_id)).fetchone()
    return {"created": created, "hint": hint_view(row, dev["crew"])}


def hint_view(row: sqlite3.Row, from_crew: str | None) -> dict[str, Any]:
    return {
        "id": row["id"],
        "to_crew": row["to_crew"],
        "from_crew": from_crew,
        "from_name": row["display_name"] or ANONYMOUS,
        "nudge_id": row["nudge_id"],
        "created_at": row["created_at"],
    }


def list_hints(conn: sqlite3.Connection, crew: str, after_id: int | None = None,
               limit: int = 50) -> list[dict]:
    """Oldest-first. With after_id: the oldest `limit` unseen hints (so a client that
    pages forward never skips any). Without it: the newest `limit` hints."""
    base = ("SELECT h.*, d.display_name, d.crew AS from_crew FROM hints h"
            " JOIN devices d ON d.id=h.from_device WHERE h.to_crew=?")
    if after_id is not None:
        rows = conn.execute(base + " AND h.id>? ORDER BY h.id ASC LIMIT ?",
                            (crew, after_id, limit)).fetchall()
    else:
        rows = list(reversed(conn.execute(base + " ORDER BY h.id DESC LIMIT ?",
                                          (crew, limit)).fetchall()))
    return [hint_view(r, r["from_crew"]) for r in rows]


# ------------------------------------------------------------------- summary

def summary(conn: sqlite3.Connection, settings: Settings, now: datetime) -> dict[str, Any]:
    crews = [crew_view(conn, m, with_contributors=False) for m in MACHINES]
    return {
        "server_time": fmt_time(now),
        "crews": crews,
        "machines_running": sum(1 for c in crews if c["runs"]),
        "finale": finale_view(conn, settings, now),
        "contributors": {
            "total": contributor_count(conn),
            "recent": contributors(conn, limit=40),
        },
        "devices_total": conn.execute("SELECT COUNT(*) FROM devices").fetchone()[0],
        "repo_url": settings.repo_url,
    }


# --------------------------------------------------------------------- admin

def reset(conn: sqlite3.Connection, scope: str) -> None:
    from .db import PROGRESS_TABLES
    with tx(conn):
        for t in PROGRESS_TABLES:
            conn.execute(f"DELETE FROM {t}")
        for key in ("finale_override", "line_started_at"):
            set_setting(conn, key, None)
        if scope == "all":
            set_setting(conn, "safety_net_at", None)
            conn.execute("DELETE FROM devices")
