# SPDX-License-Identifier: AGPL-3.0-or-later
"""SQLite schema and connection helpers."""
from __future__ import annotations

import os
import sqlite3

from .config import HANDOFFS, Settings

SCHEMA = """
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  display_name TEXT,
  crew TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS part_solves (
  device_id TEXT NOT NULL REFERENCES devices(id),
  machine TEXT NOT NULL,
  part TEXT NOT NULL,
  solved_at TEXT NOT NULL,
  credited INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (device_id, machine, part)
);
CREATE INDEX IF NOT EXISTS part_solves_machine ON part_solves(machine, part);
CREATE TABLE IF NOT EXISTS contributors (
  device_id TEXT NOT NULL REFERENCES devices(id),
  machine TEXT NOT NULL,
  via TEXT NOT NULL,
  first_merged_at TEXT NOT NULL,
  PRIMARY KEY (device_id, machine)
);
CREATE TABLE IF NOT EXISTS handoffs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  from_machine TEXT NOT NULL,
  to_machine TEXT NOT NULL,
  settings_total INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS handoff_settings (
  handoff_id TEXT NOT NULL REFERENCES handoffs(id),
  setting_index INTEGER NOT NULL,
  device_id TEXT NOT NULL REFERENCES devices(id),
  solved_at TEXT NOT NULL,
  PRIMARY KEY (handoff_id, setting_index, device_id)
);
CREATE TABLE IF NOT EXISTS gnu_notes (
  code TEXT PRIMARY KEY,
  found_by TEXT NOT NULL REFERENCES devices(id),
  found_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS hints (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_device TEXT NOT NULL REFERENCES devices(id),
  to_crew TEXT NOT NULL,
  nudge_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (from_device, to_crew, nudge_id)
);
CREATE TABLE IF NOT EXISTS crew_items (
  machine TEXT NOT NULL,
  item_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('found', 'installed')),
  found_by TEXT NOT NULL REFERENCES devices(id),
  found_at TEXT NOT NULL,
  installed_by TEXT REFERENCES devices(id),
  installed_at TEXT,
  place TEXT,
  PRIMARY KEY (machine, item_id)
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""

# Tables cleared by a rehearsal reset (devices are kept unless scope is "all").
PROGRESS_TABLES = ("crew_items", "hints", "gnu_notes", "handoff_settings", "contributors", "part_solves")


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=10, isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(settings: Settings) -> None:
    parent = os.path.dirname(os.path.abspath(settings.database_path))
    os.makedirs(parent, exist_ok=True)
    conn = connect(settings.database_path)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.executescript(SCHEMA)
        cols = {r["name"] for r in conn.execute("PRAGMA table_info(part_solves)")}
        if "credited" not in cols:  # databases created before the credited flag
            conn.execute("ALTER TABLE part_solves ADD COLUMN credited INTEGER NOT NULL DEFAULT 1")
        for hid, name, frm, to in HANDOFFS:
            conn.execute(
                "INSERT INTO handoffs (id, name, from_machine, to_machine, settings_total)"
                " VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET"
                " name=excluded.name, settings_total=excluded.settings_total",
                (hid, name, frm, to, settings.handoff_settings_total),
            )
    finally:
        conn.close()
