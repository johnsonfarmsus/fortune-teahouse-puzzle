# SPDX-License-Identifier: AGPL-3.0-or-later
"""Big-screen finale data and the /summary fields the page relies on (WP12b)."""
import json
from pathlib import Path

import pytest

from .conftest import ADMIN, API

REPO = Path(__file__).resolve().parents[2]
SERVER_README = REPO / "server" / "static" / "bigscreen" / "readme.json"
GAME_README = REPO / "game" / "data" / "finale" / "readme.json"


def test_readme_json_shape(client):
    data = json.loads(SERVER_README.read_text(encoding="utf-8"))
    assert data["title"] == "The gnu's shop: README"
    assert [s["id"] for s in data["sections"]] == [
        "fortune_machine", "cookie_machine", "oven",
        "cookie_to_oven", "fortune_to_oven", "oven_to_packaging",
    ]
    for sec in data["sections"]:
        assert set(sec) == {"id", "heading", "trigger", "body"}
        (kind, ident), = sec["trigger"].items()
        assert kind in ("machine_runs", "handoff_connected") and ident == sec["id"]
    assert set(data["closing"]) == {"heading", "line", "fortune"}
    # The page fetches it relative to /bigscreen/.
    r = client.get("/bigscreen/readme.json")
    assert r.status_code == 200 and r.json() == data


def test_readme_matches_game_copy():
    if not GAME_README.exists():
        pytest.skip(f"{GAME_README.relative_to(REPO)} is not in this checkout yet; "
                    "the equality check runs once the game's copy lands")
    assert json.loads(SERVER_README.read_text(encoding="utf-8")) == \
        json.loads(GAME_README.read_text(encoding="utf-8"))


def test_bigscreen_page_has_no_unknown_summary_fields(client, h):
    """Every summary field the big screen reads exists in /summary (no API change needed)."""
    s = client.get(f"{API}/summary").json()
    fin = s["finale"]
    for key in ("open", "open_reason", "safety_net_at", "line_ready", "started", "notes", "handoffs"):
        assert key in fin
    for key in ("found", "total", "needed"):
        assert key in fin["notes"]
    for ho in fin["handoffs"]:
        for key in ("id", "name", "from_machine", "to_machine", "settings_total",
                    "settings_solved", "status"):
            assert key in ho
    for crew in s["crews"]:
        for key in ("machine", "name", "runs", "parts", "parts_solved", "parts_total"):
            assert key in crew
    assert {"total", "recent"} <= set(s["contributors"])
    assert "server_time" in s and "repo_url" in s
    assert client.get(f"{API}/contributors").json()["contributors"] == []


def test_summary_supports_waiting_rows_and_admin_closed(client, h):
    """The waiting row text is built from from_machine/to_machine plus crews[].runs."""
    h.run_machine("oven", "Zed")
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    s = client.get(f"{API}/summary").json()
    runs = {c["machine"]: c["runs"] for c in s["crews"]}
    hand = {x["id"]: x for x in s["finale"]["handoffs"]}
    assert hand["cookie_to_oven"]["status"] == "waiting"
    waiting = [m for m in (hand["cookie_to_oven"]["from_machine"], hand["cookie_to_oven"]["to_machine"])
               if m in runs and not runs[m]]
    assert waiting == ["cookie_machine"]
    assert hand["oven_to_packaging"]["status"] == "not_started"   # packaging is not a crew
    client.post(f"{API}/admin/finale/close", headers=ADMIN)
    fin = client.get(f"{API}/summary").json()["finale"]
    assert fin["open"] is False and fin["open_reason"] == "admin_closed"
