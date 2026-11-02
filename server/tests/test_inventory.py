# SPDX-License-Identifier: AGPL-3.0-or-later
"""Crew inventory: shared found/installed items per crew."""
import sqlite3
import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from tests.conftest import ADMIN, API

ITEM = ["item_id", "state", "found_by", "found_at", "installed_by", "installed_at", "place"]


def put(client, machine, item, device, state, place=None):
    body = {"device_id": device, "state": state}
    if place is not None:
        body["place"] = place
    return client.post(f"{API}/crews/{machine}/inventory/{item}", json=body)


def inv(client, machine):
    r = client.get(f"{API}/crews/{machine}/inventory")
    assert r.status_code == 200
    return r.json()["items"]


def test_empty_inventory(client):
    assert client.get(f"{API}/crews/oven/inventory").json() == {"items": []}


def test_found_then_installed(client, h, clock):
    a = h.device("oven")
    b = h.device("oven")
    r = put(client, "oven", "brass_key", a, "found", "depot_locker")
    assert r.status_code == 200
    row = r.json()
    assert list(row) == ITEM
    assert row["state"] == "found" and row["found_by"] == a and row["found_at"] == "2027-10-29T17:00:00Z"
    assert row["installed_by"] is None and row["installed_at"] is None and row["place"] == "depot_locker"
    clock.advance(minutes=5)
    row = put(client, "oven", "brass_key", b, "installed", "oven_door").json()
    assert row["state"] == "installed" and row["found_by"] == a and row["found_at"] == "2027-10-29T17:00:00Z"
    assert row["installed_by"] == b and row["installed_at"] == "2027-10-29T17:05:00Z"
    assert row["place"] == "oven_door"
    assert inv(client, "oven") == [row]


def test_install_without_place_keeps_found_place(client, h):
    a = h.device("oven")
    put(client, "oven", "fuse", a, "found", "harbour")
    assert put(client, "oven", "fuse", a, "installed").json()["place"] == "harbour"


def test_repeat_writes_are_no_ops(client, h, clock):
    a, b = h.device("oven"), h.device("oven")
    first = put(client, "oven", "fuse", a, "found", "harbour").json()
    clock.advance(minutes=1)
    assert put(client, "oven", "fuse", a, "found", "harbour").json() == first
    assert put(client, "oven", "fuse", b, "found", "elsewhere").json() == first
    inst = put(client, "oven", "fuse", b, "installed", "oven_door").json()
    clock.advance(minutes=1)
    assert put(client, "oven", "fuse", a, "installed", "other").json() == inst
    # state never moves back
    assert put(client, "oven", "fuse", a, "found").json() == inst
    assert len(inv(client, "oven")) == 1


def test_first_writer_is_found_by(client, h):
    a, b = h.device("cookie_machine"), h.device("cookie_machine")
    put(client, "cookie_machine", "spoon", a, "found")
    row = put(client, "cookie_machine", "spoon", b, "found").json()
    assert row["found_by"] == a


def test_install_unfound_item_credits_installer_as_finder(client, h):
    a = h.device("oven")
    row = put(client, "oven", "gear", a, "installed", "oven_door").json()
    assert row["state"] == "installed" and row["found_by"] == a and row["installed_by"] == a
    assert row["found_at"] == row["installed_at"]


def test_inventories_are_per_crew(client, h):
    a, b = h.device("oven"), h.device("cookie_machine")
    put(client, "oven", "key", a, "found")
    put(client, "cookie_machine", "key", b, "found")
    assert [i["found_by"] for i in inv(client, "oven")] == [a]
    assert [i["found_by"] for i in inv(client, "cookie_machine")] == [b]
    assert inv(client, "fortune_machine") == []


def test_list_order_is_oldest_find_first(client, h, clock):
    a = h.device("oven")
    for name in ("zebra", "apple", "mango"):
        put(client, "oven", name, a, "found")
        clock.advance(seconds=10)
    assert [i["item_id"] for i in inv(client, "oven")] == ["zebra", "apple", "mango"]


def test_wrong_crew_is_403(client, h):
    a = h.device("cookie_machine")
    r = put(client, "oven", "key", a, "found")
    assert r.status_code == 403 and r.json()["error"]["code"] == "not_in_crew"
    nocrew = h.device()
    assert put(client, "oven", "key", nocrew, "found").status_code == 403
    assert inv(client, "oven") == []
    # switching crews moves the permission
    client.post(f"{API}/devices", json={"device_id": a, "crew": "oven"})
    assert put(client, "oven", "key", a, "found").status_code == 200


def test_unregistered_device_is_404(client):
    r = put(client, "oven", "key", str(uuid.uuid4()), "found")
    assert r.status_code == 404 and r.json()["error"]["code"] == "device_not_registered"


def test_unknown_crew_is_404(client, h):
    a = h.device("oven")
    r = put(client, "submarine", "key", a, "found")
    assert r.status_code == 404 and r.json()["error"]["code"] == "unknown_crew"
    r = client.get(f"{API}/crews/submarine/inventory")
    assert r.status_code == 404 and r.json()["error"]["code"] == "unknown_crew"


@pytest.mark.parametrize("item", ["Brass", "has-dash", "x" * 65, "sp%20ace", "caf%C3%A9", "a.b"])
def test_bad_item_id_is_400(client, h, item):
    a = h.device("oven")
    r = put(client, "oven", item, a, "found")
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_item_id"
    assert inv(client, "oven") == []


def test_item_id_limits_are_accepted(client, h):
    a = h.device("oven")
    assert put(client, "oven", "x" * 64, a, "found").status_code == 200
    assert put(client, "oven", "a_1", a, "found").status_code == 200


@pytest.mark.parametrize("state", ["lost", "", "FOUND", "Installed"])
def test_bad_state_is_400(client, h, state):
    a = h.device("oven")
    r = put(client, "oven", "key", a, state)
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_state"
    assert inv(client, "oven") == []


def test_bad_place_and_malformed_body(client, h):
    a = h.device("oven")
    r = put(client, "oven", "key", a, "found", "p" * 65)
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_place"
    assert client.post(f"{API}/crews/oven/inventory/key", json={"device_id": a}).status_code == 422
    assert client.post(f"{API}/crews/oven/inventory/key", json={"state": "found"}).status_code == 422


def test_summary_counts(client, h):
    a, b = h.device("oven"), h.device("cookie_machine")
    put(client, "oven", "k1", a, "found")
    put(client, "oven", "k2", a, "found")
    put(client, "oven", "k3", a, "found")
    put(client, "oven", "k2", a, "installed")
    put(client, "oven", "k3", a, "installed")
    put(client, "cookie_machine", "k1", b, "found")
    crews = {c["machine"]: c for c in client.get(f"{API}/summary").json()["crews"]}
    assert (crews["oven"]["items_found"], crews["oven"]["items_installed"]) == (3, 2)
    assert (crews["cookie_machine"]["items_found"], crews["cookie_machine"]["items_installed"]) == (1, 0)
    assert (crews["fortune_machine"]["items_found"], crews["fortune_machine"]["items_installed"]) == (0, 0)
    one = client.get(f"{API}/crews/oven").json()
    assert (one["items_found"], one["items_installed"]) == (3, 2)


def test_reset_clears_inventory(client, h):
    a = h.device("oven")
    put(client, "oven", "key", a, "found")
    client.post(f"{API}/admin/reset", headers=ADMIN, json={"confirm": "reset"})
    assert inv(client, "oven") == []
    crews = client.get(f"{API}/summary").json()["crews"]
    assert all(c["items_found"] == 0 and c["items_installed"] == 0 for c in crews)
    assert put(client, "oven", "key", a, "found").status_code == 200  # devices kept
    client.post(f"{API}/admin/reset", headers=ADMIN, json={"confirm": "reset", "scope": "all"})
    assert inv(client, "oven") == []


def test_inventory_requests_are_rate_limited(settings, clock):
    settings.rate_limit_rps = 0.001
    settings.rate_limit_burst = 3
    with TestClient(create_app(settings, clock)) as c:
        codes = [c.get(f"{API}/crews/oven/inventory").status_code for _ in range(5)]
    assert codes[:3] == [200, 200, 200] and codes[3:] == [429, 429]


def test_existing_database_gets_the_table(settings, clock):
    conn = sqlite3.connect(settings.database_path)
    conn.execute("CREATE TABLE devices (id TEXT PRIMARY KEY, display_name TEXT, crew TEXT,"
                 " created_at TEXT NOT NULL, updated_at TEXT NOT NULL)")
    conn.commit()
    conn.close()
    with TestClient(create_app(settings, clock)) as c:
        assert c.get(f"{API}/crews/oven/inventory").json() == {"items": []}
