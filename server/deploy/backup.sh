#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Online backup of the scoreboard SQLite database (safe while the service is running).
#
# Uses SQLite's backup API (python3 inside the container, same as `sqlite3 .backup`), checks the
# copy, gzips it to $BACKUP_DIR/scoreboard-YYYYmmdd-HHMMSS.db.gz and keeps the newest $BACKUP_KEEP
# files (default 14). Optionally rsyncs the directory to $BACKUP_RSYNC_TARGET.
#
# Settings come from the environment, falling back to server/deploy/.env:
#   BACKUP_DIR (default /var/backups/fortune-scoreboard), BACKUP_KEEP (14), BACKUP_RSYNC_TARGET.
# Run it by hand or from the systemd timer (fortune-scoreboard-backup.timer).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_file="${COMPOSE_FILE_PATH:-$here/compose.prod.yaml}"
env_file="$here/.env"

# Read one KEY from .env without sourcing it (values can contain shell-special characters).
env_value() {
  local key="$1"
  [[ -f "$env_file" ]] || return 0
  grep -E "^${key}=" "$env_file" | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true
}

backup_dir="${BACKUP_DIR:-$(env_value BACKUP_DIR)}"
backup_dir="${backup_dir:-/var/backups/fortune-scoreboard}"
keep="${BACKUP_KEEP:-$(env_value BACKUP_KEEP)}"
keep="${keep:-14}"
rsync_target="${BACKUP_RSYNC_TARGET:-$(env_value BACKUP_RSYNC_TARGET)}"

if ! [[ "$keep" =~ ^[0-9]+$ ]] || (( keep < 1 )); then
  echo "backup: BACKUP_KEEP must be a positive integer, got '$keep'" >&2
  exit 2
fi

dc() { docker compose -f "$compose_file" "$@"; }

umask 077
mkdir -p "$backup_dir"

stamp="$(date -u +%Y%m%d-%H%M%S)"
final="$backup_dir/scoreboard-$stamp.db.gz"
partial="$final.partial"
trap 'rm -f "$partial"; dc exec -T scoreboard rm -f /data/.backup-tmp.db >/dev/null 2>&1 || true' EXIT

# 1. Consistent copy inside the container (the data volume), then verify it.
dc exec -T scoreboard python3 - <<'PY'
import os, sqlite3, sys
src_path = os.environ.get("DATABASE_PATH", "/data/scoreboard.db")
dst_path = "/data/.backup-tmp.db"
if os.path.exists(dst_path):
    os.remove(dst_path)
src = sqlite3.connect(src_path, timeout=30)
dst = sqlite3.connect(dst_path)
with dst:
    src.backup(dst)
result = dst.execute("PRAGMA integrity_check").fetchone()[0]
dst.close()
src.close()
if result != "ok":
    sys.exit(f"integrity_check failed: {result}")
PY

# 2. Stream it to the host, compressed.
dc exec -T scoreboard cat /data/.backup-tmp.db | gzip -9 > "$partial"
gzip -t "$partial"
mv "$partial" "$final"
echo "backup: wrote $final ($(du -h "$final" | cut -f1))"

# 3. Keep only the newest $keep backups (names sort by timestamp).
mapfile -t old < <(ls -1 "$backup_dir"/scoreboard-*.db.gz 2>/dev/null | sort | head -n -"$keep")
for f in "${old[@]}"; do
  [[ -n "$f" ]] && rm -f -- "$f" && echo "backup: pruned $f"
done

# 4. Optional off-VM copy.
if [[ -n "$rsync_target" ]]; then
  rsync -a --delete "$backup_dir"/ "$rsync_target"
  echo "backup: synced to $rsync_target"
fi
