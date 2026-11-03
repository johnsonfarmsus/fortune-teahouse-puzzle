#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Forced command for the CI deploy key (authorized_keys `command="..."`). The key can do exactly
# two things and nothing else, whatever the client asks for:
#   1. rsync into /srv/fortune/releases/<id>/        (rsync --server ... . <that directory>/)
#   2. activate <id>   swap the `current` symlink to releases/<id> and prune old releases
# Install: sudo install -m 755 server/deploy/fortune-deploy-shell.sh /usr/local/bin/fortune-deploy-shell
# Env: FORTUNE_ROOT (default /srv/fortune), FORTUNE_KEEP releases to keep (default 5).
set -euo pipefail

ROOT="${FORTUNE_ROOT:-/srv/fortune}"
KEEP="${FORTUNE_KEEP:-5}"
cmd="${SSH_ORIGINAL_COMMAND:-}"
id_re='[A-Za-z0-9][A-Za-z0-9._-]{0,63}'
rsync_re="^rsync --server [-A-Za-z0-9=._ ]+ \\. ${ROOT}/releases/(${id_re})/\$"
activate_re="^activate (${id_re})\$"

deny() {
	echo "fortune-deploy-shell: refused: ${cmd:-<interactive>}" >&2
	exit 126
}

if [[ "$cmd" =~ $rsync_re ]] && [[ "$cmd" != *..* ]]; then
	# Only characters from the pattern above reach here, so word splitting is safe.
	# shellcheck disable=SC2086
	exec $cmd
elif [[ "$cmd" =~ $activate_re ]]; then
	id="${BASH_REMATCH[1]}"
	if [ ! -s "$ROOT/releases/$id/index.html" ]; then
		echo "no such release: $id" >&2
		exit 1
	fi
	cd "$ROOT"
	ln -sfn "releases/$id" current.new # relative target: valid inside the Caddy container too
	mv -T current.new current          # atomic rename over the old symlink
	# Prune: keep the newest $KEEP releases, never the one now live.
	live="$(readlink current)"
	ls -1dt releases/*/ 2>/dev/null | sed 's:/$::' | tail -n +"$((KEEP + 1))" | while read -r old; do
		[ "$old" = "$live" ] || rm -rf -- "$old"
	done
	echo "active release: $id"
else
	deny
fi
