# SPDX-License-Identifier: AGPL-3.0-or-later
import uuid

from fastapi.testclient import TestClient

from app.config import MACHINES, NUDGES, PARTS, Settings, parse_time
from app.main import create_app
from app.ratelimit import TokenBuckets
from tests.conftest import ADMIN, API


# ------------------------------------------------------------ registration

def test_register_and_update_device(client):
    did = str(uuid.uuid4())
    r = client.post(f"{API}/devices", json={"device_id": did})
    assert r.status_code == 200
    body = r.json()
    assert body["created"] is True and body["display_name"] is None and body["crew"] is None

    r = client.post(f"{API}/devices", json={"device_id": did, "display_name": "  Tux   Fan ", "crew": "oven"})
    body = r.json()
    assert body["created"] is False
    assert body["display_name"] == "Tux Fan" and body["crew"] == "oven"

    # omitted fields are left alone, explicit null clears
    r = client.post(f"{API}/devices", json={"device_id": did, "crew": "cookie_machine"})
    assert r.json()["display_name"] == "Tux Fan" and r.json()["crew"] == "cookie_machine"
    r = client.post(f"{API}/devices", json={"device_id": did, "display_name": None})
    assert r.json()["display_name"] is None and r.json()["crew"] == "cookie_machine"


def test_register_validation(client):
    assert client.post(f"{API}/devices", json={"device_id": "nope"}).status_code == 422
    did = str(uuid.uuid4())
    r = client.post(f"{API}/devices", json={"device_id": did, "crew": "submarine"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "unknown_crew"
    r = client.post(f"{API}/devices", json={"device_id": did, "display_name": "x" * 25})
    assert r.status_code == 422 and r.json()["error"]["code"] == "validation_error"


def test_device_id_is_case_insensitive(client):
    did = str(uuid.uuid4())
    client.post(f"{API}/devices", json={"device_id": did})
    r = client.post(f"{API}/devices", json={"device_id": did.upper(), "crew": "oven"})
    assert r.json()["created"] is False and r.json()["device_id"] == did


def test_unregistered_device_cannot_solve(client):
    r = client.post(f"{API}/crews/oven/parts/logic/solve", json={"device_id": str(uuid.uuid4())})
    assert r.status_code == 404 and r.json()["error"]["code"] == "device_not_registered"


# ------------------------------------------------------------ parts / runs

def test_part_solve_is_idempotent_per_device(client, h):
    d = h.device("cookie_machine", "Ada")
    first = h.solve(d, "cookie_machine", "logic").json()
    again = h.solve(d, "cookie_machine", "logic").json()
    assert first["newly_solved"] is True and again["newly_solved"] is False
    logic = next(p for p in again["crew"]["parts"] if p["part"] == "logic")
    assert logic["solved_count"] == 1
    assert client.get(f"{API}/contributors").json()["total"] == 1


def test_solve_requires_membership_and_valid_ids(client, h):
    d = h.device("oven")
    r = h.solve(d, "cookie_machine", "logic")
    assert r.status_code == 403 and r.json()["error"]["code"] == "not_in_crew"
    assert h.solve(d, "toaster", "logic").status_code == 404
    assert h.solve(d, "oven", "teleport").status_code == 404
    nocrew = h.device()
    assert h.solve(nocrew, "oven", "logic").status_code == 403


def test_machine_runs_when_six_parts_solved_across_devices(client, h):
    devs = [h.device("oven") for _ in range(3)]
    # Overlapping solves: four distinct parts in total.
    for d, parts in zip(devs, [PARTS[:2], PARTS[1:3], PARTS[2:4]]):
        for p in parts:
            h.solve(d, "oven", p)
    crew = client.get(f"{API}/crews/oven").json()
    assert crew["parts_solved"] == 4 and crew["runs"] is False

    h.solve(devs[0], "oven", "word")
    h.solve(devs[1], "oven", "helper")
    assert client.get(f"{API}/crews/oven").json()["runs"] is False  # rhythm still missing
    h.solve(devs[2], "oven", "rhythm")
    crew = client.get(f"{API}/crews/oven").json()
    assert crew["runs"] is True and crew["parts_solved"] == 6
    by = {p["part"]: p["solved_count"] for p in crew["parts"]}
    assert by["wiring"] == 2 and by["rhythm"] == 1
    assert client.get(f"{API}/crews/cookie_machine").json()["runs"] is False


def test_one_device_alone_can_run_a_machine(client, h):
    d = h.device("fortune_machine")
    for p in PARTS:
        h.solve(d, "fortune_machine", p)
    assert client.get(f"{API}/crews/fortune_machine").json()["runs"] is True


def test_solves_do_not_count_for_other_crews_machine(client, h):
    d = h.device("oven")
    for p in PARTS:
        h.solve(d, "oven", p)
    h.c.post(f"{API}/devices", json={"device_id": d, "crew": "cookie_machine"})
    assert client.get(f"{API}/crews/cookie_machine").json()["parts_solved"] == 0
    assert client.get(f"{API}/crews/oven").json()["runs"] is True  # earlier solves stick


def test_contributors_names_and_anonymous(client, h):
    named = h.device("oven", "Grace")
    anon = h.device("oven")
    h.solve(named, "oven", "logic")
    h.solve(anon, "oven", "wiring")
    items = client.get(f"{API}/contributors").json()["contributors"]
    assert {i["name"] for i in items} == {"Grace", "anonymous"}
    assert all(i["machine"] == "oven" and i["via"] == "solve" for i in items)
    assert "device_id" not in items[0]
    h.c.post(f"{API}/devices", json={"device_id": anon, "display_name": "Linus"})
    names = {i["name"] for i in client.get(f"{API}/contributors?machine=oven").json()["contributors"]}
    assert names == {"Grace", "Linus"}
    assert client.get(f"{API}/contributors?machine=nope").status_code == 404


# ------------------------------------------------------------------ finale

def test_finale_closed_then_opens_at_safety_net(client, h, clock):
    r = client.put(f"{API}/admin/finale/safety-net", headers=ADMIN, json={"at": "2027-10-29T23:00:00Z"})
    assert r.status_code == 200
    f = client.get(f"{API}/finale").json()
    assert f["open"] is False and f["safety_net_at"] == "2027-10-29T23:00:00Z"
    d = h.device("oven")
    r = client.post(f"{API}/finale/notes", json={"device_id": d, "code": "alpha-1"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "finale_closed"

    clock.advance(hours=5, minutes=59)
    assert client.get(f"{API}/finale").json()["open"] is False
    clock.advance(minutes=1)
    f = client.get(f"{API}/finale").json()
    assert f["open"] is True and f["open_reason"] == "safety_net"


def test_finale_opens_when_all_machines_run(client, h):
    h.run_machine("fortune_machine")
    h.run_machine("cookie_machine")
    assert client.get(f"{API}/finale").json()["open"] is False
    h.run_machine("oven")
    f = client.get(f"{API}/finale").json()
    assert f["open"] is True and f["open_reason"] == "all_machines_run"


def test_safety_net_from_env_setting(settings, clock):
    settings.finale_safety_net_at = parse_time("2027-10-29T18:00:00Z")
    with TestClient(create_app(settings, clock)) as c:
        assert c.get(f"{API}/finale").json()["open"] is False
        clock.advance(hours=1)
        assert c.get(f"{API}/finale").json()["open"] is True
        # an admin clear beats the env value
        c.put(f"{API}/admin/finale/safety-net", headers=ADMIN, json={"at": None})
        assert c.get(f"{API}/finale").json()["open"] is False


def test_admin_open_close_auto(client, h):
    assert client.post(f"{API}/admin/finale/open", headers=ADMIN).json()["open"] is True
    h.run_all()
    assert client.post(f"{API}/admin/finale/close", headers=ADMIN).json()["open"] is False
    assert client.post(f"{API}/admin/finale/auto", headers=ADMIN).json()["open"] is True


def test_handoffs_wait_for_unfinished_machines(client, h):
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    h.run_machine("cookie_machine")
    d = h.device("oven")
    f = client.get(f"{API}/finale").json()
    st = {x["id"]: x["status"] for x in f["handoffs"]}
    assert st == {"cookie_to_oven": "waiting", "fortune_to_oven": "waiting", "oven_to_packaging": "waiting"}
    url = f"{API}/finale/handoffs/%s/settings"
    r = client.post(url % "cookie_to_oven", json={"device_id": d, "setting_index": 0})
    assert r.status_code == 409 and r.json()["error"]["code"] == "handoff_waiting"

    h.run_machine("oven")  # cookie_to_oven can go; fortune_to_oven still waits for the fortune machine
    r = client.post(url % "cookie_to_oven", json={"device_id": d, "setting_index": 0})
    assert r.status_code == 200 and r.json()["handoff"]["status"] == "in_progress"
    r = client.post(url % "fortune_to_oven", json={"device_id": d, "setting_index": 0})
    assert r.status_code == 409
    # packaging is not a crew machine: it only needs the oven
    r = client.post(url % "oven_to_packaging", json={"device_id": d, "setting_index": 1})
    assert r.status_code == 200


def test_handoff_settings_idempotent_and_counted_once_per_index(client, h):
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    h.run_all()
    a, b = h.device("oven"), h.device("cookie_machine")
    url = f"{API}/finale/handoffs/cookie_to_oven/settings"
    r1 = client.post(url, json={"device_id": a, "setting_index": 0}).json()
    r2 = client.post(url, json={"device_id": a, "setting_index": 0}).json()
    r3 = client.post(url, json={"device_id": b, "setting_index": 0}).json()  # same setting, other device
    assert r1["newly_recorded"] is True and r2["newly_recorded"] is False and r3["newly_recorded"] is True
    assert r3["handoff"]["settings_solved"] == 1
    client.post(url, json={"device_id": b, "setting_index": 1})
    last = client.post(url, json={"device_id": a, "setting_index": 2}).json()["handoff"]
    assert last["settings_solved"] == 3 and last["status"] == "connected" and last["complete"] is True
    r = client.post(url, json={"device_id": a, "setting_index": 3})
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_setting_index"
    r = client.post(f"{API}/finale/handoffs/nope/settings", json={"device_id": a, "setting_index": 0})
    assert r.status_code == 404


def test_notes_k_of_n(client, h):
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    d, e = h.device("oven"), h.device("oven")
    n = client.get(f"{API}/finale").json()["notes"]
    assert n == {"found": 0, "total": 4, "needed": 3, "complete": False}

    r = client.post(f"{API}/finale/notes", json={"device_id": d, "code": "wrong"}).json()
    assert r["valid"] is False and r["notes"]["found"] == 0
    r = client.post(f"{API}/finale/notes", json={"device_id": d, "code": " ALPHA-1 "}).json()
    assert r["valid"] and not r["already_found"] and r["notes"]["found"] == 1
    r = client.post(f"{API}/finale/notes", json={"device_id": e, "code": "alpha1"}).json()
    assert r["valid"] and r["already_found"] and r["notes"]["found"] == 1
    client.post(f"{API}/finale/notes", json={"device_id": e, "code": "bravo-2"})
    assert client.get(f"{API}/finale").json()["notes"]["complete"] is False
    r = client.post(f"{API}/finale/notes", json={"device_id": e, "code": "charlie3"}).json()
    assert r["notes"] == {"found": 3, "total": 4, "needed": 3, "complete": True}
    assert "alpha" not in client.get(f"{API}/finale").text.lower()  # codes never leak


def test_start_code(client, h):
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    h.run_all()
    d = h.device("oven")
    start = f"{API}/finale/start"
    assert client.post(start, json={"device_id": d, "code": "1234"}).json() == {
        "valid": False, "started": False, "started_at": None}
    r = client.post(start, json={"device_id": d, "code": "3.141592653"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "line_not_ready"
    for hid in ("cookie_to_oven", "fortune_to_oven", "oven_to_packaging"):
        for i in range(3):
            client.post(f"{API}/finale/handoffs/{hid}/settings", json={"device_id": d, "setting_index": i})
    for code in ("alpha-1", "bravo-2", "charlie3"):
        client.post(f"{API}/finale/notes", json={"device_id": d, "code": code})
    assert client.get(f"{API}/finale").json()["line_ready"] is True
    r = client.post(start, json={"device_id": d, "code": "3141592653"}).json()
    assert r["valid"] is True and r["started"] is True and r["started_at"]
    assert client.get(f"{API}/finale").json()["started"] is True


def test_start_code_requires_open_finale(client, h):
    d = h.device("oven")
    r = client.post(f"{API}/finale/start", json={"device_id": d, "code": "3141592653"})
    assert r.status_code == 403


# ------------------------------------------------------------------- hints

def test_hint_permission_and_flow(client, h):
    mentor = h.device("oven", "Mina")
    other = h.device("cookie_machine")
    body = {"device_id": mentor, "to_crew": "cookie_machine", "nudge_id": NUDGES[0]}
    r = client.post(f"{API}/hints", json=body)
    assert r.status_code == 403 and r.json()["error"]["code"] == "not_a_maintainer"

    h.run_machine("oven")
    r = client.post(f"{API}/hints", json=body)
    assert r.status_code == 200 and r.json()["created"] is True
    again = client.post(f"{API}/hints", json=body).json()
    assert again["created"] is False and again["hint"]["id"] == r.json()["hint"]["id"]

    hints = client.get(f"{API}/hints?crew=cookie_machine").json()["hints"]
    assert len(hints) == 1 and hints[0]["from_name"] == "Mina" and hints[0]["nudge_id"] == NUDGES[0]
    assert client.get(f"{API}/hints?crew=oven").json()["hints"] == []
    assert client.get(f"{API}/hints?crew=cookie_machine&after_id={hints[0]['id']}").json()["hints"] == []

    items = client.get(f"{API}/contributors?machine=cookie_machine").json()["contributors"]
    assert [(i["name"], i["via"]) for i in items] == [("Mina", "mentor")]

    r = client.post(f"{API}/hints", json={**body, "nudge_id": "free text!"})
    assert r.json()["error"]["code"] == "unknown_nudge"
    r = client.post(f"{API}/hints", json={**body, "to_crew": "oven"})
    assert r.json()["error"]["code"] == "own_crew"
    assert client.post(f"{API}/hints", json={**body, "to_crew": "x"}).status_code == 400
    body2 = {"device_id": other, "to_crew": "oven", "nudge_id": NUDGES[1]}
    assert client.post(f"{API}/hints", json=body2).status_code == 403


def test_nudge_list(client):
    assert client.get(f"{API}/hints/nudges").json()["nudges"] == list(NUDGES)


# ----------------------------------------------------------------- summary

def test_summary_has_everything(client, h):
    h.run_machine("oven", "Zed")
    s = client.get(f"{API}/summary").json()
    assert [c["machine"] for c in s["crews"]] == list(MACHINES)
    assert s["machines_running"] == 1
    assert s["crews"][2]["runs"] is True
    assert s["finale"]["open"] is False and len(s["finale"]["handoffs"]) == 3
    assert s["contributors"]["total"] == 6 and s["contributors"]["recent"][0]["name"] == "Zed"
    assert s["devices_total"] == 6 and s["repo_url"].startswith("https://")


# ------------------------------------------------------------------- admin

def test_admin_requires_secret(client):
    for method, path in [("get", "/admin/state"), ("post", "/admin/finale/open"),
                         ("post", "/admin/finale/close"), ("put", "/admin/finale/safety-net"),
                         ("post", "/admin/reset")]:
        assert getattr(client, method)(API + path).status_code == 401
        r = getattr(client, method)(API + path, headers={"X-Admin-Secret": "wrong"})
        assert r.status_code == 401
    assert client.get(f"{API}/admin/state", headers=ADMIN).status_code == 200


def test_admin_disabled_without_secret(settings, clock):
    settings.admin_secret = ""
    with TestClient(create_app(settings, clock)) as c:
        r = c.get(f"{API}/admin/state", headers={"X-Admin-Secret": ""})
        assert r.status_code == 503


def test_admin_reset(client, h):
    h.run_all()
    d = h.device("oven", "Keep me")
    client.post(f"{API}/admin/finale/open", headers=ADMIN)
    assert client.post(f"{API}/admin/reset", headers=ADMIN, json={"scope": "progress"}).status_code == 422
    r = client.post(f"{API}/admin/reset", headers=ADMIN, json={"confirm": "reset"})
    assert r.json() == {"reset": "progress"}
    s = client.get(f"{API}/summary").json()
    assert s["machines_running"] == 0 and s["contributors"]["total"] == 0
    assert s["finale"]["open"] is False and s["devices_total"] == 19  # devices kept
    assert h.solve(d, "oven", "logic").status_code == 200
    client.post(f"{API}/admin/reset", headers=ADMIN, json={"confirm": "reset", "scope": "all"})
    assert client.get(f"{API}/summary").json()["devices_total"] == 0


def test_admin_bad_safety_net_time(client):
    r = client.put(f"{API}/admin/finale/safety-net", headers=ADMIN, json={"at": "2027-10-29T23:00:00"})
    assert r.status_code == 422  # no UTC offset


def test_admin_line_override(client):
    r = client.post(f"{API}/admin/finale/line", headers=ADMIN, json={"started": True}).json()
    assert r["started"] is True
    r = client.post(f"{API}/admin/finale/line", headers=ADMIN, json={"started": False}).json()
    assert r["started"] is False


# --------------------------------------------------------- cors, limits, ui

def test_cors_preflight(settings, clock):
    settings.cors_origins = ["https://johnsonfarmsus.github.io"]
    with TestClient(create_app(settings, clock)) as c:
        r = c.options(f"{API}/devices", headers={
            "Origin": "https://johnsonfarmsus.github.io",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type"})
        assert r.status_code == 200
        assert r.headers["access-control-allow-origin"] == "https://johnsonfarmsus.github.io"
        r = c.get(f"{API}/health", headers={"Origin": "https://evil.example"})
        assert "access-control-allow-origin" not in r.headers


def test_rate_limit(settings, clock):
    settings.rate_limit_rps = 0.001
    settings.rate_limit_burst = 5
    with TestClient(create_app(settings, clock)) as c:
        codes = [c.get(f"{API}/health").status_code for _ in range(8)]
    assert codes[:5] == [200] * 5 and codes[5:] == [429] * 3


def test_token_bucket_refills():
    t = [0.0]
    b = TokenBuckets(1.0, 2, clock=lambda: t[0])
    assert b.allow("a") and b.allow("a") and not b.allow("a")
    assert b.allow("b")
    t[0] += 1.0
    assert b.allow("a") and not b.allow("a")


def test_bigscreen_served_with_repo_link(client, settings):
    r = client.get("/bigscreen/")
    assert r.status_code == 200 and settings.repo_url in r.text and "{{REPO_URL}}" not in r.text
    assert client.get("/bigscreen/bigscreen.js").status_code == 200
    assert client.get("/", follow_redirects=False).status_code in (302, 307)


def test_config_from_env():
    s = Settings.from_env({"GNU_NOTE_CODES": "a, b ,c,,", "GNU_NOTES_K": "9",
                           "FINALE_SAFETY_NET_AT": "2027-10-30T01:00:00-07:00", "ADMIN_SECRET": "x"})
    assert s.notes_total == 3 and s.notes_needed == 3
    assert s.finale_safety_net_at.isoformat() == "2027-10-30T08:00:00+00:00"
    assert s.start_code == "3141592653" and s.cors_origins == ["*"]


# ------------------------------------------------------- review follow-ups

def test_start_works_with_no_notes_configured(settings, clock):
    settings.gnu_note_codes = []
    with TestClient(create_app(settings, clock)) as c:
        c.post(f"{API}/admin/finale/open", headers=ADMIN)
        assert c.get(f"{API}/finale").json()["notes"] == {
            "found": 0, "total": 0, "needed": 0, "complete": True}
        did = str(uuid.uuid4())
        c.post(f"{API}/devices", json={"device_id": did, "crew": "oven"})
        for m in MACHINES:
            for p in PARTS:
                d = str(uuid.uuid4())
                c.post(f"{API}/devices", json={"device_id": d, "crew": m})
                c.post(f"{API}/crews/{m}/parts/{p}/solve", json={"device_id": d})
        for hid in ("cookie_to_oven", "fortune_to_oven", "oven_to_packaging"):
            for i in range(3):
                c.post(f"{API}/finale/handoffs/{hid}/settings", json={"device_id": did, "setting_index": i})
        r = c.post(f"{API}/finale/start", json={"device_id": did, "code": "3141592653"})
        assert r.status_code == 200 and r.json()["started"] is True


def test_hints_after_id_pages_oldest_first(client, h):
    h.run_machine("oven")
    mentors = [h.device("oven") for _ in range(6)]
    # 6 mentors x 10 nudges = 60 distinct hints to the cookie machine
    for m in mentors:
        for n in NUDGES:
            r = client.post(f"{API}/hints", json={"device_id": m, "to_crew": "cookie_machine", "nudge_id": n})
            assert r.status_code == 200
    newest = client.get(f"{API}/hints?crew=cookie_machine").json()["hints"]
    assert len(newest) == 50 and newest[-1]["id"] == 60
    seen, after = [], 0
    while True:
        page = client.get(f"{API}/hints?crew=cookie_machine&after_id={after}").json()["hints"]
        if not page:
            break
        seen += [x["id"] for x in page]
        after = page[-1]["id"]
    assert seen == list(range(1, 61))


def test_trust_proxy_uses_rightmost_forwarded_address(settings, clock):
    settings.trust_proxy = True
    settings.rate_limit_rps = 0.001
    settings.rate_limit_burst = 2
    with TestClient(create_app(settings, clock)) as c:
        # A client rotating its own leftmost entries still shares one bucket (same proxy hop).
        codes = [c.get(f"{API}/health", headers={"X-Forwarded-For": f"10.0.0.{i}, 203.0.113.7"}).status_code
                 for i in range(4)]
        assert codes == [200, 200, 429, 429]
        # A different real client address gets its own bucket.
        assert c.get(f"{API}/health", headers={"X-Forwarded-For": "1.1.1.1, 203.0.113.8"}).status_code == 200


def test_http_errors_use_documented_shape(client):
    r = client.get(f"{API}/nope")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"
    r = client.get(f"{API}/devices")
    assert r.status_code == 405 and r.json()["error"]["code"] == "method_not_allowed"


def test_cors_origins_trailing_slash_stripped():
    s = Settings.from_env({"CORS_ORIGINS": "https://a.example/, https://b.example"})
    assert s.cors_origins == ["https://a.example", "https://b.example"]


def test_bucket_cleanup_is_periodic_not_per_request():
    t = [0.0]
    b = TokenBuckets(1.0, 2, clock=lambda: t[0])
    for i in range(50):
        b.allow(f"ip{i}")
    t[0] += 10.0  # buckets are full again, but the sweep is not due yet
    b.allow("x")
    assert len(b._buckets) == 51
    t[0] += 30.0
    b.allow("y")
    assert list(b._buckets) == ["y"]  # idle, fully refilled buckets swept; y is in use
