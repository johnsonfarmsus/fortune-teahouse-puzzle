# Scoreboard server

A small FastAPI + SQLite service that holds the shared state of The Fortune Teahouse: crew
progress, the finale, the gnu's notes, mentor hints and the contributors list. It also serves the
big-screen page for the conference hallway. The game still plays if this service is down; only
shared progress pauses.

- API reference: [API.md](API.md)
- Big screen: `/bigscreen/` (large type, dark, polls `/api/v1/summary` every 5 seconds)
  - States follow the finale (locked, open, line ready, running). When the line starts the screen
    plays the closing reveal, then shows the full README and the contributors. Replay it with
    `/bigscreen/?replay=1` or by pressing **R**; any key skips it. Polling pauses during the reveal.
  - `static/bigscreen/readme.json` is the README text; keep it equal to `game/data/finale/readme.json`
    (a pytest checks that once the game file exists).
- Licence: GNU AGPL-3.0-or-later. Because this runs as a network service, the big-screen footer
  links to the source repository (`REPO_URL`). Keep that link pointing at the code you run.

## Run with Docker

```sh
cd server
docker compose up --build
# big screen: http://localhost:8000/bigscreen/
curl localhost:8000/api/v1/summary
```

The compose file stores the SQLite database in the named volume `scoreboard-data` (mounted at
`/data`) and runs as the non-root user `10001`. If you bind-mount a host directory instead,
`chown 10001 <dir>` first. The compose file has no default admin secret or note codes: with
`ADMIN_SECRET` unset the admin API is disabled, and with `GNU_NOTE_CODES` unset there are no notes
(N = 0, so the notes requirement is trivially met). Set real values for the event, for example:

```sh
ADMIN_SECRET=$(openssl rand -hex 16) \
CORS_ORIGINS=https://johnsonfarmsus.github.io \
GNU_NOTE_CODES=code1,code2,code3,code4,code5,code6,code7,code8 GNU_NOTES_K=5 \
FINALE_SAFETY_NET_AT=2027-10-29T17:00:00-07:00 \
TRUST_PROXY=true docker compose up -d --build
```

Back up `/data/scoreboard.db` (SQLite in WAL mode: copy with `sqlite3 scoreboard.db ".backup out.db"`).
Run a single container; the in-memory rate limiter and SQLite are not meant to be shared by replicas.

## Run without Docker

```sh
cd server
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
DATABASE_PATH=./scoreboard.db ADMIN_SECRET=dev uvicorn app.main:create_app --factory --reload
pytest
```

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `DATABASE_PATH` | `/data/scoreboard.db` | SQLite file (parent directory is created) |
| `ADMIN_SECRET` | empty | Shared secret for `/api/v1/admin/*` (header `X-Admin-Secret`). Empty disables admin. |
| `CORS_ORIGINS` | `*` | Comma-separated allowed origins, for example `https://johnsonfarmsus.github.io` |
| `FINALE_SAFETY_NET_AT` | unset | ISO 8601 time **with offset** after which the finale opens regardless. Admins can override it at runtime. |
| `GNU_NOTE_CODES` | empty | Comma-separated valid note codes; their count is N. Matched ignoring case and punctuation. |
| `GNU_NOTES_K` | `3` | How many notes the finale needs (capped at N; with N = 0 nothing is needed) |
| `START_CODE` | `3141592653` | The line's start code (matched ignoring punctuation) |
| `REPO_URL` | the GitHub repository | Source link in the big-screen footer (AGPL source offer) |
| `HANDOFF_SETTINGS_TOTAL` | `3` | Settings per handoff (applied to all three at startup) |
| `RATE_LIMIT_RPS` | `200` | Per-IP token refill rate; `0` disables limiting |
| `RATE_LIMIT_BURST` | `1000` | Per-IP burst size |
| `TRUST_PROXY` | `false` | Use the rightmost `X-Forwarded-For` address (the hop your reverse proxy appended) as the client IP. Set to `true` only behind a proxy that appends it. |

The rate limit is deliberately light and per IP. A whole conference may share one Wi-Fi address,
so the defaults are generous; the note and start-code endpoints get a tighter extra limit
(10 requests per second, burst 30, per IP).

## Layout

```
app/config.py     settings from env, fixed ids (crews, parts, handoffs, nudges)
app/db.py         SQLite schema
app/service.py    all game rules and queries
app/main.py       FastAPI routes, CORS, rate limit, big-screen route
app/ratelimit.py  in-memory token bucket
static/bigscreen/ the big-screen page and readme.json (plain HTML and JS, no build step)
tests/            pytest suite (httpx TestClient)
```

## Notes

- There is no real authentication. A device id is a random UUID the game keeps locally; display
  names are not moderated, so the big screen shows whatever players type (it escapes everything).
- Keep the admin secret private, since
  it can reset progress and force the finale open.
