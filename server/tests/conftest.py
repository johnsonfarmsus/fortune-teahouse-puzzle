# SPDX-License-Identifier: AGPL-3.0-or-later
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import MACHINES, PARTS, Settings  # noqa: E402
from app.main import create_app  # noqa: E402

START = datetime(2027, 10, 29, 17, 0, tzinfo=timezone.utc)
API = "/api/v1"
ADMIN = {"X-Admin-Secret": "s3cret"}


class Clock:
    def __init__(self):
        self.now = START

    def __call__(self):
        return self.now

    def advance(self, **kw):
        self.now += timedelta(**kw)


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def settings(tmp_path):
    return Settings(
        database_path=str(tmp_path / "t.db"),
        admin_secret="s3cret",
        gnu_note_codes=["alpha-1", "BRAVO-2", "charlie3", "delta4"],
        gnu_notes_k=3,
        handoff_settings_total=3,
        rate_limit_rps=0,  # disabled; rate limiting has its own tests
    )


@pytest.fixture
def client(settings, clock):
    with TestClient(create_app(settings, clock)) as c:
        yield c


class Helper:
    def __init__(self, client):
        self.c = client

    def device(self, crew=None, name=None):
        did = str(uuid.uuid4())
        body = {"device_id": did}
        if crew:
            body["crew"] = crew
        if name:
            body["display_name"] = name
        r = self.c.post(f"{API}/devices", json=body)
        assert r.status_code == 200, r.text
        return did

    def solve(self, did, machine, part):
        return self.c.post(f"{API}/crews/{machine}/parts/{part}/solve", json={"device_id": did})

    def run_machine(self, machine, name=None):
        """Six different devices, one part each."""
        ids = []
        for part in PARTS:
            d = self.device(machine, name)
            assert self.solve(d, machine, part).status_code == 200
            ids.append(d)
        return ids

    def run_all(self):
        return {m: self.run_machine(m) for m in MACHINES}


@pytest.fixture
def h(client):
    return Helper(client)
