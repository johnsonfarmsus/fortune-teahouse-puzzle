# Deploying the game and scoreboard (Hetzner VM)

This puts the scoreboard and big screen on one Debian or Ubuntu VM you already run, behind Caddy
with automatic HTTPS. Everything lives in [`server/deploy/`](../server/deploy/):

| File | What it is |
| --- | --- |
| `compose.prod.yaml` | The scoreboard container plus Caddy (TLS), volumes, restart policies, log rotation |
| `Caddyfile` | Caddy site config; uses `DOMAIN` from the environment. Serves the game, `/api/` and `/bigscreen/` on one origin |
| `fortune-deploy-shell.sh` | Forced SSH command for the CI deploy key (rsync into `releases/`, swap `current`) |
| `.env.example` | Every setting, documented. Copy to `.env` (git-ignored) and fill in |
| `backup.sh`, `fortune-scoreboard-backup.{service,timer}` | Daily online backup of the SQLite database, 14 copies kept |
| `healthcheck.sh` | External check of `/api/v1/health`, the big screen and the certificate |

Run all `docker compose` commands from the repository root. Throughout, `$C` is shorthand for
`docker compose -f server/deploy/compose.prod.yaml`:

```sh
alias C='docker compose -f server/deploy/compose.prod.yaml'   # optional, per shell
```

## 0. Decide first

- **The domain**, for example `scoreboard.example.org` (a subdomain you control; `fortune.johnsonfarms.us`
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

When the game is served from the VPS itself (section "Serving the game from the VPS") this is done
for you by `config.json`; the options below are for the Pages mirror and other hosts.

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

## Serving the game from the VPS

The same Caddy that fronts the scoreboard also serves the game's static web build, so the game,
the API (`/api/`) and the big screen (`/bigscreen/`) share one origin, `https://$DOMAIN`. That is
the production address; players need no `?scoreboard=` link and the browser needs no CORS. The
GitHub Pages deploy keeps running as a **staging mirror** (see "The Pages mirror" below).

How it fits together:

- Files live in `/srv/fortune/` on the VPS: `releases/<id>/` (one directory per deploy) and
  `current`, a relative symlink to the live release. `compose.prod.yaml` mounts `/srv/fortune`
  read-only into Caddy (change the host path with `GAME_DIR` in `.env`).
- `Caddyfile` sends `/api/*` and `/bigscreen*` to the app and everything else to
  `/srv/fortune/current`. `index.html` and `config.json` are `Cache-Control: no-cache`, so every
  merge is picked up at once. The Godot export has fixed file names (`index.wasm`, `index.pck`), so
  they are also revalidated each load (a cheap 304 via ETag); file names containing an 8+ hex hash
  (`name.<hash>.ext`) get `max-age=31536000, immutable`. `.wasm` is `application/wasm`, `.pck` is
  `application/octet-stream`.
- Caddy has no built-in Brotli encoder, so CI writes `.br` and `.gz` copies of every `.wasm`,
  `.js`, `.pck`, `.html` and `.json`, and Caddy serves them with `precompressed br gzip`. The API
  and big screen use Caddy's `encode zstd gzip`.
- CI also writes `config.json` (`{"scoreboard_url": "/api/v1"}`) next to `index.html`. The web
  build fetches it at startup (never blocking; a 404 or error is ignored, which is what happens on
  Pages) and then talks to the scoreboard on its own origin. Order: `?scoreboard=` in the address,
  then `config.json`, then the `fortune/scoreboard_url` project setting, then offline only.
  `fortune/scoreboard_url` itself also accepts `/api/v1` or `/` (same origin).
- Cross-origin isolation headers (COOP/COEP) are in the Caddyfile as comments, off, because the
  export is single-threaded.

### One-time setup on the VPS

Run as a sudo-capable user, after sections 1 to 4 above.

```sh
# 1. A deploy user with no password and no shell access beyond the forced command.
sudo adduser --disabled-password --gecos "" deploy

# 2. The directories. deploy writes releases/ and the symlink; Caddy (root in its container) reads.
sudo install -d -o deploy -g deploy -m 755 /srv/fortune /srv/fortune/releases

# 3. The restricted shell that the key is bound to.
sudo install -m 755 server/deploy/fortune-deploy-shell.sh /usr/local/bin/fortune-deploy-shell
sudo apt-get install -y rsync

# 4. A key pair for CI (do this on your own machine, not on the VPS).
ssh-keygen -t ed25519 -N "" -C "fortune-ci-deploy" -f fortune_deploy_key
```

Put the **public** key in `/home/deploy/.ssh/authorized_keys` (`sudo -u deploy mkdir -m 700
/home/deploy/.ssh`, file mode 600), as one line, bound to the restricted shell:

```
command="/usr/local/bin/fortune-deploy-shell",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA... fortune-ci-deploy
```

`fortune-deploy-shell` accepts only two requests from that key, and rejects everything else: an
rsync into `/srv/fortune/releases/<id>/`, and `activate <id>`, which atomically re-points
`current` at that release and deletes all but the newest 5 releases. It cannot get a shell or write
anywhere else.

Then restart the stack so Caddy picks up the new mount and Caddyfile:
`docker compose -f server/deploy/compose.prod.yaml up -d`. Until the first deploy runs,
`https://$DOMAIN/` answers 404 for the game (the API and `/bigscreen/` already work).

### GitHub secrets

Add these four under Settings > Secrets and variables > Actions > Repository secrets. If any is
missing the `deploy-vps` job prints a notice and skips, and the rest of CI is unaffected (forks too).

| Secret | Value |
| --- | --- |
| `VPS_HOST` | The VPS hostname or IP, for example `scoreboard.example.org` |
| `VPS_USER` | `deploy` |
| `VPS_SSH_KEY` | The full **private** key file (`fortune_deploy_key`), including the BEGIN/END lines |
| `VPS_KNOWN_HOSTS` | Output of `ssh-keyscan -t ed25519 <host>` run from a machine you trust, verified against the server's fingerprint (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the VPS) |

Delete `fortune_deploy_key` locally once it is stored as the secret.

### How a deploy flows

1. A push to `main` runs `test` and `build` (import, export, 12 MB gzip budget) and uploads the
   `web-build` artifact.
2. `deploy-vps` downloads that artifact, adds `config.json`, makes the `.br` and `.gz` copies, and
   picks a release id like `20271001T120000Z-abc1234`.
3. It runs `rsync` over SSH into `/srv/fortune/releases/<id>/`, then `activate <id>`, which swaps
   the `current` symlink in one atomic rename. Visitors see either the old build or the new one,
   never a mix. `deploy` (Pages) runs in parallel and is unchanged.

### Roll back

Releases stay on disk (the newest 5). On the VPS:

```sh
ls -1t /srv/fortune/releases                      # newest first
cd /srv/fortune && ln -sfn releases/<previous-id> current.new && mv -T current.new current
```

Nothing is restarted; the next request is served from the older build. The next push to `main`
moves `current` forward again, so fix or revert on `main` as well.

### Verify

```sh
curl -sI --compressed https://$DOMAIN/index.wasm | grep -iE 'content-type|content-encoding|cache-control'
# expect: content-type: application/wasm, content-encoding: br (or gzip), cache-control: no-cache
curl -sI -H 'Accept-Encoding: gzip' https://$DOMAIN/index.pck | grep -iE 'content-type|content-encoding'
curl -s https://$DOMAIN/config.json                # {"scoreboard_url": "/api/v1"}
curl -s https://$DOMAIN/api/v1/health              # the app, same origin
```

Open `https://$DOMAIN/` on a phone: Menu > Scoreboard should show the scoreboard without any
`?scoreboard=` in the address. Brotli is sent only to clients that ask for it
(`Accept-Encoding: br`, which every current browser does); `curl --compressed` asks for whatever
that build of curl supports (often only gzip), so add `-H 'Accept-Encoding: br'` to see
`content-encoding: br`.

### The Pages mirror

Every merge still publishes to `https://johnsonfarmsus.github.io/fortune-teahouse-puzzle/`. Use it
as staging, and as a fallback. It is a different origin from the scoreboard, so it only talks to the
scoreboard when opened with `?scoreboard=https://$DOMAIN` and when `CORS_ORIGINS` in `.env` lists
`https://johnsonfarmsus.github.io`. Keep that value; the VPS origin itself needs no CORS entry.

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
