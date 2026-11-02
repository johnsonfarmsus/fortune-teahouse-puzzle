# Deploying the scoreboard (Hetzner VM)

This puts the scoreboard and big screen on one Debian or Ubuntu VM you already run, behind Caddy
with automatic HTTPS. Everything lives in [`server/deploy/`](../server/deploy/):

| File | What it is |
| --- | --- |
| `compose.prod.yaml` | The scoreboard container plus Caddy (TLS), volumes, restart policies, log rotation |
| `Caddyfile` | Caddy site config; uses `DOMAIN` from the environment |
| `.env.example` | Every setting, documented. Copy to `.env` (git-ignored) and fill in |
| `backup.sh`, `fortune-scoreboard-backup.{service,timer}` | Daily online backup of the SQLite database, 14 copies kept |
| `healthcheck.sh` | External check of `/api/v1/health`, the big screen and the certificate |

Run all `docker compose` commands from the repository root. Throughout, `$C` is shorthand for
`docker compose -f server/deploy/compose.prod.yaml`:

```sh
alias C='docker compose -f server/deploy/compose.prod.yaml'   # optional, per shell
```

## 0. Decide first

- **The domain**, for example `scoreboard.example.org` (a subdomain you control; `fortune.ataary.com`
  is still a placeholder for the game itself, not this server).
- **Where backups go.** They land in `/var/backups/fortune-scoreboard` on the VM. That does not
  survive losing the VM, so set `BACKUP_RSYNC_TARGET` to another machine (or a Hetzner Storage
  Box) before the event, or copy the folder off by hand.
- **Ports 80 and 443 must be free** on the VM. Check: `sudo ss -ltnp | grep -E ':(80|443)\b'`. If
  another web server already uses them, see "If 80/443 are taken" at the end.

## 1. Install Docker and git

```sh
sudo apt-get update && sudo apt-get install -y git curl ca-certificates openssl
curl -fsSL https://get.docker.com | sudo sh        # Docker Engine + the compose plugin
sudo systemctl enable --now docker
docker compose version                              # needs v2.20 or newer
```

(Add your user to the `docker` group, or prefix the commands below with `sudo`.)

## 2. Clone and configure

```sh
sudo git clone https://github.com/johnsonfarmsus/fortune-teahouse-puzzle.git /opt/fortune-teahouse-puzzle
sudo chown -R "$USER": /opt/fortune-teahouse-puzzle
cd /opt/fortune-teahouse-puzzle
cp server/deploy/.env.example server/deploy/.env
chmod 600 server/deploy/.env
openssl rand -hex 24          # use the output as ADMIN_SECRET
nano server/deploy/.env       # fill in the required values
```

Required: `DOMAIN`, `ADMIN_SECRET`, `CORS_ORIGINS` (keep `https://johnsonfarmsus.github.io`),
`GNU_NOTE_CODES` and `START_CODE`. Compose refuses to start while any of them is empty. The other
settings are explained in the file, including the time-zone rule for `FINALE_SAFETY_NET_AT`
(write the venue's local time with its UTC offset, for example `2027-10-29T17:00:00-07:00`; a time
without an offset stops the server from starting). `TRUST_PROXY=true` is already set because Caddy
is in front.

Check the file before starting (this prints the resolved configuration, including secrets, so do
not paste it anywhere):

```sh
docker compose -f server/deploy/compose.prod.yaml config > /dev/null && echo config ok
```

## 3. DNS and firewall

Create an `A` record (and `AAAA` if the VM has IPv6) for `DOMAIN` pointing at the VM's public
address, and wait until `dig +short scoreboard.example.org` returns it. Do this **before** the
first start, or Caddy's first certificate attempts fail and it backs off for a while.

Open ports 80/tcp, 443/tcp and 443/udp in the Hetzner Cloud Firewall (if you use one) and on the
VM (`sudo ufw allow 80,443/tcp && sudo ufw allow 443/udp` if ufw is active). Port 80 must stay
open: Let's Encrypt validates over it and Caddy redirects it to https.

## 4. Start

```sh
docker compose -f server/deploy/compose.prod.yaml up -d --build
docker compose -f server/deploy/compose.prod.yaml ps
docker compose -f server/deploy/compose.prod.yaml logs --tail 50 caddy
```

The first build takes a minute or two. In the Caddy log look for `certificate obtained
successfully`. Both containers restart by themselves after a crash or a reboot
(`restart: unless-stopped`), as long as Docker starts at boot.

## 5. Verify

TLS, health and the big screen:

```sh
curl -sSI https://scoreboard.example.org/api/v1/health | head -5     # HTTP/2 200, valid certificate
curl -sS  https://scoreboard.example.org/api/v1/health                # {"ok":true}
curl -sSI http://scoreboard.example.org/ | head -3                    # 308 redirect to https
```

Open `https://scoreboard.example.org/bigscreen/` in a browser: the page loads, polls the API on
the same origin, and its footer links to the source repository.

CORS from the GitHub Pages origin (a preflight, as the browser sends it). The reply must contain
`access-control-allow-origin: https://johnsonfarmsus.github.io`:

```sh
curl -sS -i -X OPTIONS https://scoreboard.example.org/api/v1/devices \
  -H 'Origin: https://johnsonfarmsus.github.io' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
```

An origin that is not listed gets no `access-control-allow-origin` header, which is what you want:

```sh
curl -sS -i -X OPTIONS https://scoreboard.example.org/api/v1/devices \
  -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: POST' | grep -i access-control || echo "no CORS header (good)"
```

Admin access works and the settings were picked up:

```sh
export ADMIN_SECRET='...'    # the value from server/deploy/.env
curl -sS https://scoreboard.example.org/api/v1/admin/state -H "X-Admin-Secret: $ADMIN_SECRET"
```

`config.notes_total` should equal the number of note codes you set, and `env_safety_net_at` should
show your time in UTC (`...Z`).

Rate limiting uses the real client address because of `TRUST_PROXY=true`. If two phones on
different networks ever share one limit, check that the app container has no published port
(`docker compose ... ps` must show none for `scoreboard`).

## 6. Point the game at it

The scoreboard address is the server root, with no path: `https://scoreboard.example.org`.

- **Permanent (build time):** in `game/project.godot`, section `[fortune]`, set
  `scoreboard_url="https://scoreboard.example.org"`, merge to `main`, and let the Pages deploy run.
- **Per page load (no rebuild):** open the game with `?scoreboard=`, for example
  `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/?scoreboard=https://scoreboard.example.org`.
  Use this for the rehearsal and for QR codes until the setting is merged.

Then in the game, Menu > Scoreboard should show the address, and two browsers in the same crew
should see each other's solved parts on the big screen.

## 7. Rehearsal reset

After testing, clear the test data. `scope: progress` clears solves, contributors, notes, hints,
the finale override and the line start, and keeps devices and the safety-net time. `scope: all`
also deletes devices and the stored safety-net time.

```sh
curl -sS -X POST https://scoreboard.example.org/api/v1/admin/reset \
  -H "X-Admin-Secret: $ADMIN_SECRET" -H 'Content-Type: application/json' \
  -d '{"confirm": "reset", "scope": "progress"}'
```

Take a backup right before and right after a reset you might regret (`server/deploy/backup.sh`).

## 8. Backups

```sh
sudo cp server/deploy/fortune-scoreboard-backup.service server/deploy/fortune-scoreboard-backup.timer /etc/systemd/system/
# The units assume the repo is in /opt/fortune-teahouse-puzzle; edit the paths if it is not.
sudo systemctl daemon-reload
sudo systemctl enable --now fortune-scoreboard-backup.timer
sudo systemctl start fortune-scoreboard-backup.service     # run one now
sudo journalctl -u fortune-scoreboard-backup.service -n 20
systemctl list-timers fortune-scoreboard-backup.timer
ls -lh /var/backups/fortune-scoreboard
```

`backup.sh` uses SQLite's online backup (safe while the game is running), checks the copy with
`PRAGMA integrity_check`, writes `scoreboard-YYYYmmdd-HHMMSS.db.gz` (UTC) and keeps the newest 14
(`BACKUP_KEEP`). The timer runs daily at 03:30 server time. On event days run
`sudo systemctl start fortune-scoreboard-backup.service` yourself before the finale, or change
`OnCalendar=` to `hourly` with `sudo systemctl edit --full fortune-scoreboard-backup.timer`.
Set `BACKUP_RSYNC_TARGET` in `.env` for an off-VM copy (the VM's root user needs an SSH key for
that host).

### Restore

```sh
cd /opt/fortune-teahouse-puzzle
docker compose -f server/deploy/compose.prod.yaml stop scoreboard
gunzip -c /var/backups/fortune-scoreboard/scoreboard-YYYYmmdd-HHMMSS.db.gz > /tmp/restore.db
# Copy into the data volume and fix ownership (the app runs as uid 10001), dropping stale WAL files:
docker run --rm -v fortune-scoreboard_scoreboard-data:/data -v /tmp/restore.db:/restore.db:ro \
  python:3.12-slim sh -c 'rm -f /data/scoreboard.db-wal /data/scoreboard.db-shm \
  && cp /restore.db /data/scoreboard.db && chown 10001:10001 /data/scoreboard.db'
rm /tmp/restore.db
docker compose -f server/deploy/compose.prod.yaml start scoreboard
curl -sS https://scoreboard.example.org/api/v1/summary | head -c 300
```

The volume is named `fortune-scoreboard_scoreboard-data` (check with `docker volume ls`).

## 9. Monitoring

`GET /api/v1/health` returns `{"ok": true}` and costs almost nothing. Point an uptime monitor at
`https://scoreboard.example.org/api/v1/health` (UptimeRobot, Better Stack or similar; expect
HTTP 200, check every minute, alert by email or phone). Also useful: `server/deploy/healthcheck.sh`
checks health, the big screen and the certificate (warns under 14 days) and exits non-zero on
failure. To run it every five minutes from cron and get alerted when checks stop arriving, create a
free check at healthchecks.io, put its ping URL in `HEALTHCHECK_PING_URL` in `.env`, and add:

```sh
*/5 * * * * /opt/fortune-teahouse-puzzle/server/deploy/healthcheck.sh >> /var/log/fortune-healthcheck.log 2>&1
```

Remember the game plays without the scoreboard; an outage only pauses shared progress.

## 10. Event-day checklist

- [ ] Morning: `healthcheck.sh` passes; `curl .../api/v1/admin/state` shows the right N, k and safety-net time.
- [ ] Reset the rehearsal data (section 7) and confirm the big screen shows all zeroes.
- [ ] Take a backup; confirm the off-VM copy arrived.
- [ ] The game opens from the QR code and shows the scoreboard as connected.
- [ ] Watch logs during the event: `docker compose -f server/deploy/compose.prod.yaml logs -f --tail 100`
  (`429` lines mean someone is being rate limited; many `5xx` means look at the scoreboard container).
- [ ] **Safety-net time.** Check it matches the schedule; change it without restarting:

  ```sh
  curl -sS -X PUT https://scoreboard.example.org/api/v1/admin/finale/safety-net \
    -H "X-Admin-Secret: $ADMIN_SECRET" -H 'Content-Type: application/json' \
    -d '{"at": "2027-10-29T17:00:00-07:00"}'
  ```

- [ ] **Open the finale manually** when all three machines run, or earlier if you decide to:

  ```sh
  curl -sS -X POST https://scoreboard.example.org/api/v1/admin/finale/open -H "X-Admin-Secret: $ADMIN_SECRET"
  ```

  `.../admin/finale/close` holds it closed even past the safety net, and `.../admin/finale/auto`
  returns to the automatic rules. `.../admin/finale/line` with `{"started": true}` forces the
  line started.
- [ ] Back up again right after the finale opens and at the end of the day.

## Rollback

Deploy updates with:

```sh
cd /opt/fortune-teahouse-puzzle
git pull --ff-only
# Optional, to keep the old image for rollback: set SCOREBOARD_IMAGE_TAG in server/deploy/.env to a new value.
docker compose -f server/deploy/compose.prod.yaml up -d --build
```

To roll back the code, check out the previous good commit and rebuild:

```sh
git log --oneline -5
git checkout <previous-commit>
docker compose -f server/deploy/compose.prod.yaml up -d --build
```

(If you had changed `SCOREBOARD_IMAGE_TAG`, set it back to the earlier tag and use `up -d` without
`--build`: the old image is still on the VM.) Return to the branch afterwards with `git checkout main`.
The database is not touched by a code rollback; if the data itself is bad, restore a backup
(section 8). To take the scoreboard offline entirely: `docker compose -f server/deploy/compose.prod.yaml down`
(volumes, and so the database and certificates, are kept; `down -v` would delete them, so never use it).

## If 80/443 are taken

If another web server on the VM already owns those ports, do not run the bundled Caddy. Add a
site to the existing proxy that forwards `scoreboard.example.org` to `127.0.0.1:8000`, keep
`TRUST_PROXY=true` only if that proxy sets `X-Forwarded-For` (nginx:
`proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`), and start only the app on the
loopback with this override saved as `server/deploy/compose.override.yaml` (not committed):

```yaml
services:
  scoreboard:
    ports: ["127.0.0.1:8000:8000"]
  caddy:
    profiles: ["disabled"]
```

and `docker compose -f server/deploy/compose.prod.yaml -f server/deploy/compose.override.yaml up -d --build scoreboard`.
(`DOMAIN` is still required by the compose file; any value works then.) The health check and
backups work the same.

## Licence note (AGPL)

The scoreboard is GNU AGPL-3.0-or-later and runs as a network service, so people using it must be
able to get its source. The big-screen footer already links to the repository (`REPO_URL`, default
`https://github.com/johnsonfarmsus/fortune-teahouse-puzzle`), and the game links there too. Keep
`REPO_URL` pointing at the code you actually run: if you deploy a fork or local changes, publish
them and point `REPO_URL` at that fork.
