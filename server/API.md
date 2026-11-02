# Scoreboard API v1

Base URL: the server root (for example `https://scoreboard.example.org`). Every endpoint below
lives under `/api/v1`. All bodies and responses are JSON (`Content-Type: application/json`).
Timestamps are UTC, ISO 8601, second precision, always ending in `Z`
(`2027-10-29T17:00:00Z`). CORS is enabled for the origins in `CORS_ORIGINS`.

This file is the contract for the game client (WP7). If the code and this file disagree, that is
a bug in one of them; please say so.

## Concepts

| Term | Values |
| --- | --- |
| Crew / machine id | `fortune_machine`, `cookie_machine`, `oven` |
| Part id | `logic`, `wiring`, `sequence`, `word`, `rhythm`, `helper` |
| Handoff id | `cookie_to_oven`, `fortune_to_oven`, `oven_to_packaging` |
| Nudge id | `reread_the_clue`, `ask_a_crewmate`, `start_with_the_sure_thing`, `try_the_help_button`, `check_neighbours`, `look_at_the_order`, `follow_the_wires`, `listen_for_the_beat`, `take_a_short_break`, `compare_with_another_crew` (also `GET /hints/nudges`) |
| `device_id` | An opaque string of 1 to 64 printable characters (the game sends 32 hex characters), generated once per phone and kept in local storage. It is the only identity. The server stores and echoes it exactly as sent: no reformatting, and it is case-sensitive. Treat it as a secret: it is never returned by any list endpoint. |

Rules the server enforces (decision D1: every player solves on their own device):

- A **machine runs** when each of its six parts has been solved by at least one device that was
  in that crew at the time. A machine that has run stays running.
- Solving is **idempotent** per device, machine and part.
- The **finale opens** when all three machines run, or when the safety-net time has passed, or
  when an admin opens it (and an admin can hold it closed). See `GET /finale`.
- A **handoff waits** for any crew machine it touches that is not running. `oven_to_packaging`
  only touches the oven (packaging is not a crew).
- A device **appears on a crew's contributors list** when it solves a part for that crew
  (`via: "solve"`), or when it, as a member of a running crew, sends that crew a hint
  (`via: "mentor"`). Names are the device's current display name or `"anonymous"`.

## Errors

Every error has the same shape:

```json
{"error": {"code": "not_in_crew", "message": "Device is in crew 'oven', not 'cookie_machine'. ..."}}
```

| HTTP | `code` | When |
| --- | --- | --- |
| 400 | `unknown_crew`, `unknown_nudge`, `own_crew`, `bad_setting_index`, `confirm_required`, `bad_scope` | Well-formed request with a bad value |
| 401 | `bad_admin_secret` | Missing or wrong `X-Admin-Secret` |
| 403 | `not_in_crew`, `not_a_maintainer`, `finale_closed` | Not allowed (yet) |
| 404 | `device_not_registered`, `unknown_crew`, `unknown_part`, `unknown_handoff`, `not_found` | Unknown id or path |
| 405 | `method_not_allowed` | Wrong HTTP method for the path |
| 409 | `handoff_waiting`, `line_not_ready` | Valid request, wrong state |
| 422 | `validation_error` | Malformed body (bad `device_id`, missing field, name over 24 characters). Has a `details` array of `{loc, msg}`. |
| 429 | `rate_limited` | Per-IP limit hit; retry after the `Retry-After` header (seconds) |
| 503 | `admin_disabled` | Admin call while `ADMIN_SECRET` is unset |

### Crew switching

Switching crew (`POST /devices` with a different `crew`) is allowed, but a solve for a crew the
device is no longer in is rejected with `403 not_in_crew`. A client that queues writes while the
scoreboard is unreachable must **flush its offline queue before switching crews**, and drop (not
retry forever) any queued solve that returns `403 not_in_crew`. Solves already recorded stay
counted for the old crew.

### Polling budget

A whole venue may share one public IP. Per IP the server allows about 200 requests per second
(burst 1000), and 10 per second (burst 30) on `POST /finale/notes` and `POST /finale/start`.
Please stay well inside that: poll `GET /crews/{machine}` (or `/summary`) no more often than every
10 seconds, `GET /finale` and `GET /hints` every 10 to 15 seconds, and only while the relevant
screen is open. Only the big-screen page polls `/summary` every 5 seconds. On `429` wait for
`Retry-After` and back off.

Wrong guesses are not errors: `POST /finale/notes` and `POST /finale/start` answer `200` with
`"valid": false`.

The client should treat any network error or 5xx as "scoreboard down", queue writes and carry on
(all writes below are safe to retry).

---

## Devices

### `POST /api/v1/devices`

Register a device, or update its display name and crew. Idempotent. Fields you leave out are
unchanged; an explicit `null` clears `display_name` or `crew`. Switching crew is allowed.

| Field | Type | Notes |
| --- | --- | --- |
| `device_id` | string, required | Opaque string, 1 to 64 characters |
| `display_name` | string or null | Whitespace is collapsed. Max 24 characters. Empty means anonymous. |
| `crew` | crew id or null | |

```http
POST /api/v1/devices
{"device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90", "display_name": "Ada", "crew": "cookie_machine"}
```

```json
{
  "device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90",
  "display_name": "Ada",
  "crew": "cookie_machine",
  "created_at": "2027-10-29T17:02:11Z",
  "created": true
}
```

`created` is `false` when the device already existed. Errors: `422` bad device id or name, `400 unknown_crew`.

---

## Crews

### `GET /api/v1/crews/{machine}`

Progress for one crew, including its contributors (newest first).

```json
{
  "machine": "cookie_machine",
  "name": "Cookie Machine",
  "runs": false,
  "parts_solved": 2,
  "parts_total": 6,
  "members": 14,
  "parts": [
    {"part": "logic",    "solved": true,  "solved_count": 3, "first_solved_at": "2027-10-29T17:20:00Z"},
    {"part": "wiring",   "solved": true,  "solved_count": 1, "first_solved_at": "2027-10-29T17:31:40Z"},
    {"part": "sequence", "solved": false, "solved_count": 0, "first_solved_at": null},
    {"part": "word",     "solved": false, "solved_count": 0, "first_solved_at": null},
    {"part": "rhythm",   "solved": false, "solved_count": 0, "first_solved_at": null},
    {"part": "helper",   "solved": false, "solved_count": 0, "first_solved_at": null}
  ],
  "contributors": [
    {"name": "Ada", "machine": "cookie_machine", "via": "solve", "first_merged_at": "2027-10-29T17:31:40Z"}
  ]
}
```

`parts` always lists all six parts in the order above. `solved_count` is the number of distinct
devices that solved the part. `members` is the number of devices whose current crew this is.
Errors: `404 unknown_crew`.

### `POST /api/v1/crews/{machine}/parts/{part}/solve`

Report that this device solved a part ("submit a patch"). The device must currently be in
`{machine}`. Idempotent: repeating it changes nothing and returns `newly_solved: false`. Also adds
the device to the crew's contributors on its first **credited** solve there.

| Field | Type | Notes |
| --- | --- | --- |
| `device_id` | string, required | |
| `credited` | boolean, optional, default `true` | Send `false` when the answer was revealed through the hint ladder. The solve still counts for part progress and the machine-runs rule, but the device is not added to contributors for it. |

A credited solve of a part the device earlier solved uncredited upgrades it: the device becomes a
contributor then (`newly_solved` is `false` in that case, `credited` is `true`). Credit is never
taken back by a later uncredited repeat.

```http
POST /api/v1/crews/cookie_machine/parts/logic/solve
{"device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90", "credited": true}
```

```json
{
  "newly_solved": true,
  "credited": true,
  "crew": { "...": "same object as GET /crews/cookie_machine" }
}
```

Errors: `404 device_not_registered` (register first), `403 not_in_crew`, `404 unknown_crew`,
`404 unknown_part`.

---

## Contributors

### `GET /api/v1/contributors[?machine={machine}]`

All contributors, newest first, optionally for one crew. No device ids are exposed.

```json
{
  "total": 2,
  "contributors": [
    {"name": "Mina", "machine": "cookie_machine", "via": "mentor", "first_merged_at": "2027-10-29T18:05:00Z"},
    {"name": "anonymous", "machine": "oven", "via": "solve", "first_merged_at": "2027-10-29T17:40:12Z"}
  ]
}
```

`via` is `"solve"` or `"mentor"`. A device has at most one entry per machine.

---

## Finale

### `GET /api/v1/finale`

```json
{
  "open": false,
  "open_reason": "closed",
  "override": null,
  "safety_net_at": "2027-10-30T01:00:00Z",
  "all_machines_run": false,
  "handoffs": [
    {
      "id": "cookie_to_oven", "name": "Cookie Machine to Oven",
      "from_machine": "cookie_machine", "to_machine": "oven",
      "settings_total": 3, "settings_solved": 2, "solved_indices": [0, 2],
      "complete": false, "available": false, "status": "locked"
    },
    {
      "id": "fortune_to_oven", "name": "Fortune Machine to Oven",
      "from_machine": "fortune_machine", "to_machine": "oven",
      "settings_total": 3, "settings_solved": 0, "solved_indices": [],
      "complete": false, "available": false, "status": "locked"
    },
    {
      "id": "oven_to_packaging", "name": "Oven to packaging",
      "from_machine": "oven", "to_machine": "packaging",
      "settings_total": 3, "settings_solved": 0, "solved_indices": [],
      "complete": false, "available": false, "status": "locked"
    }
  ],
  "notes": {"found": 3, "total": 8, "needed": 5, "complete": false},
  "line_ready": false,
  "started": false,
  "started_at": null
}
```

- `open`: whether finale actions are allowed. `open_reason` is one of `all_machines_run`,
  `safety_net`, `admin` (forced open), `closed` (not open yet), `admin_closed` (held closed).
  `override` is `"open"`, `"closed"` or `null` (automatic).
- `safety_net_at`: when the finale opens regardless, or `null` if none is set.
- `handoffs[].settings_solved`: the number of distinct settings (indices `0` to
  `settings_total - 1`) that at least one device has solved. `solved_indices` lists them.
- `handoffs[].status`: `connected` (all settings done), `locked` (finale closed), `waiting`
  (finale open but a machine it touches is not running), `in_progress`, `not_started`.
  `available` is true when settings can be submitted now.
- `notes`: gnu's notes found out of `total` (N); `needed` is k (never more than N); `complete` when
  `found >= needed` (so always true when N is 0). The codes themselves are never returned.
- `line_ready`: every handoff is complete and the notes are complete. `started` becomes true after
  a correct `POST /finale/start`.

### `POST /api/v1/finale/handoffs/{id}/settings`

Report that this device solved one setting of a handoff. Idempotent per device and `setting_index`;
several devices solving the same index count once toward `settings_solved`.

```http
POST /api/v1/finale/handoffs/cookie_to_oven/settings
{"device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90", "setting_index": 1}
```

```json
{"newly_recorded": true, "handoff": { "...": "one element of GET /finale handoffs" }}
```

`newly_recorded` is true only for this device's first report of that index. Errors:
`403 finale_closed`, `409 handoff_waiting`, `404 unknown_handoff`, `404 device_not_registered`,
`400 bad_setting_index`.

### `POST /api/v1/finale/notes`

Submit a code found on one of the gnu's notes. Codes are compared ignoring case, spaces and
punctuation. The first device to submit a code gets the credit; later submissions of it are valid
but `already_found`.

```http
POST /api/v1/finale/notes
{"device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90", "code": "sticky-label"}
```

```json
{"valid": true, "already_found": false, "notes": {"found": 4, "total": 8, "needed": 5, "complete": false}}
```

An unknown code returns `{"valid": false, "already_found": false, "notes": {...}}`. Errors:
`403 finale_closed`.

### `POST /api/v1/finale/start`

Start the line with the start code (the pi digits from the cookie backs; default `3141592653`;
compared ignoring punctuation, so `3.141592653` works).

```http
POST /api/v1/finale/start
{"device_id": "3f0c2a8e6d514c2e9a340b5f6f7e8d90", "code": "3.141592653"}
```

```json
{"valid": true, "started": true, "started_at": "2027-10-30T20:30:00Z"}
```

Wrong code: `{"valid": false, "started": false, "started_at": null}`. A correct code only starts
the line when `line_ready` is true; otherwise `409 line_not_ready`. Also `403 finale_closed`.
Starting again returns the original `started_at`.

---

## Hints

### `GET /api/v1/hints/nudges`

```json
{"nudges": ["reread_the_clue", "ask_a_crewmate", "..."]}
```

### `POST /api/v1/hints`

A mentor pushes one nudge to another crew. Allowed only when the sender's own crew machine runs.
Idempotent per (sender, target crew, nudge): repeating it returns the existing hint with
`created: false`. The sender is added to the target crew's contributors (`via: "mentor"`).

```http
POST /api/v1/hints
{"device_id": "3f0c2a8e6d51...", "to_crew": "cookie_machine", "nudge_id": "reread_the_clue"}
```

```json
{
  "created": true,
  "hint": {
    "id": 7, "to_crew": "cookie_machine", "from_crew": "oven", "from_name": "Mina",
    "nudge_id": "reread_the_clue", "created_at": "2027-10-29T18:05:00Z"
  }
}
```

Errors: `403 not_a_maintainer` (no crew, or crew's machine not running), `400 own_crew`,
`400 unknown_nudge`, `400 unknown_crew`, `404 device_not_registered`.

### `GET /api/v1/hints?crew={machine}[&after_id={n}]`

Hints sent to a crew, oldest first, at most 50 per call. Without `after_id` you get the newest 50.
With `after_id` you get the oldest 50 hints with a larger `id`, so page forward by passing the
highest `id` you have seen and repeat while 50 come back; none are skipped. An unknown `crew` returns
`404 unknown_crew`.

```json
{"crew": "cookie_machine", "hints": [ {"id": 7, "to_crew": "cookie_machine", "from_crew": "oven",
  "from_name": "Mina", "nudge_id": "reread_the_clue", "created_at": "2027-10-29T18:05:00Z"} ]}
```

---

## Summary (big screen)

### `GET /api/v1/summary`

Everything the big screen needs in one call.

```json
{
  "server_time": "2027-10-29T18:10:00Z",
  "crews": [ { "...": "three objects like GET /crews/{machine} but without `contributors`, in the order fortune_machine, cookie_machine, oven" } ],
  "machines_running": 1,
  "finale": { "...": "same object as GET /finale" },
  "contributors": {
    "total": 41,
    "recent": [ {"name": "Ada", "machine": "oven", "via": "solve", "first_merged_at": "2027-10-29T18:09:00Z"} ]
  },
  "devices_total": 97,
  "repo_url": "https://github.com/johnsonfarmsus/fortune-teahouse-puzzle"
}
```

`contributors.recent` is the newest 40. The game client can also use this endpoint to show
crew progress; it is cheap.

### `GET /api/v1/health`

`{"ok": true}`

---

## Admin

All admin calls need the header `X-Admin-Secret: <ADMIN_SECRET>`. If `ADMIN_SECRET` is unset the
admin API answers `503 admin_disabled`. Every call that changes the finale returns the new
`GET /finale` object.

| Call | Body | Effect |
| --- | --- | --- |
| `GET /api/v1/admin/state` | none | `{"finale": {...}, "config": {"notes_total", "notes_k", "handoff_settings_total", "env_safety_net_at"}}` |
| `PUT /api/v1/admin/finale/safety-net` | `{"at": "2027-10-30T01:00:00-07:00"}` or `{"at": null}` | Set the safety-net time (offset required, stored, overrides `FINALE_SAFETY_NET_AT`). `null` clears it, including the env value. |
| `POST /api/v1/admin/finale/open` | none | Force the finale open |
| `POST /api/v1/admin/finale/close` | none | Hold the finale closed, even after the safety net |
| `POST /api/v1/admin/finale/auto` | none | Remove the override (automatic rules) |
| `POST /api/v1/admin/finale/line` | `{"started": true}` | Force the line started (or `false` to un-start), skipping `line_ready` |
| `POST /api/v1/admin/reset` | `{"confirm": "reset", "scope": "progress"}` | Rehearsal reset. `progress` (default) clears solves, contributors, handoff settings, notes, hints, finale override and line start, and keeps devices and the safety-net time. `all` also deletes devices and the stored safety-net time. |

```sh
curl -X PUT https://scoreboard.example.org/api/v1/admin/finale/safety-net \
  -H 'X-Admin-Secret: ...' -H 'Content-Type: application/json' \
  -d '{"at": "2027-10-29T17:00:00-07:00"}'
```

---

## Other URLs

- `GET /bigscreen/` the big-screen page (polls `/api/v1/summary` every 5 seconds).
- `GET /api/docs` interactive OpenAPI docs generated by FastAPI; `GET /api/openapi.json`.
