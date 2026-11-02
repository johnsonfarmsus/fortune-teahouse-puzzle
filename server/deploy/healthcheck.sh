#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# External health check for the deployed scoreboard. Exit 0 = healthy, 1 = unhealthy.
#
#   ./healthcheck.sh                      # uses DOMAIN from the environment or server/deploy/.env
#   ./healthcheck.sh https://scoreboard.example.org
#
# Checks: GET /api/v1/health returns {"ok": true} over valid TLS, the big screen answers 200, and
# (when openssl is available) the certificate has at least CERT_MIN_DAYS (default 14) left.
# On success it pings $HEALTHCHECK_PING_URL if set (a dead-man switch such as healthchecks.io).
# Run it from cron or a systemd timer on this VM, or point an external uptime monitor straight at
# /api/v1/health (see docs/DEPLOY.md).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$here/.env"

env_value() {
  local key="$1"
  [[ -f "$env_file" ]] || return 0
  grep -E "^${key}=" "$env_file" | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true
}

base="${1:-}"
if [[ -z "$base" ]]; then
  domain="${DOMAIN:-$(env_value DOMAIN)}"
  if [[ -z "$domain" ]]; then
    echo "healthcheck: pass a URL or set DOMAIN" >&2
    exit 2
  fi
  base="https://$domain"
fi
base="${base%/}"
ping_url="${HEALTHCHECK_PING_URL:-$(env_value HEALTHCHECK_PING_URL)}"
min_days="${CERT_MIN_DAYS:-14}"

fail() {
  echo "healthcheck: FAIL: $*" >&2
  exit 1
}

body="$(curl -fsS --max-time 10 "$base/api/v1/health")" || fail "$base/api/v1/health did not answer 2xx"
compact="$(printf '%s' "$body" | tr -d '[:space:]')"
[[ "$compact" == *'"ok":true'* ]] || fail "unexpected health body: $body"

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$base/bigscreen/")" || fail "big screen unreachable"
[[ "$code" == "200" ]] || fail "big screen returned HTTP $code"

if [[ "$base" == https://* ]] && command -v openssl >/dev/null 2>&1; then
  host="${base#https://}"
  host="${host%%/*}"
  if ! openssl s_client -connect "${host}:443" -servername "${host%%:*}" </dev/null 2>/dev/null \
      | openssl x509 -noout -checkend "$(( min_days * 86400 ))" >/dev/null 2>&1; then
    fail "certificate for $host expires within $min_days days (or could not be read)"
  fi
fi

echo "healthcheck: ok ($base)"
if [[ -n "$ping_url" ]]; then
  curl -fsS --max-time 10 -o /dev/null "$ping_url" || echo "healthcheck: ping to monitor failed" >&2
fi
exit 0
