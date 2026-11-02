#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Size budget for the web export. Prints uncompressed and gzip sizes (also to
# $GITHUB_STEP_SUMMARY when set) and fails when the budget is exceeded.
#
# The budget applies to the gzip size, which is what a phone downloads from
# GitHub Pages: Godot's engine .wasm alone is ~39 MB uncompressed, so an
# uncompressed 12 MB limit can never pass. See README "Size budget".
#
# Usage: tools/dev/check-size.sh [dir]        (default game/build/web)
# Env:   WEB_BUDGET_MB   gzip budget in MB (default 12)
set -euo pipefail

DIR="${1:-game/build/web}"
BUDGET_MB="${WEB_BUDGET_MB:-12}"
BUDGET=$((BUDGET_MB * 1024 * 1024))

[ -d "$DIR" ] || { echo "check-size: $DIR not found" >&2; exit 2; }

raw=0
gz=0
rows=""
while IFS= read -r -d '' f; do
  r=$(stat -c %s "$f")
  g=$(gzip -9 -c "$f" | wc -c)
  raw=$((raw + r))
  gz=$((gz + g))
  rows+="| \`${f#"$DIR"/}\` | $r | $g |"$'\n'
done < <(find "$DIR" -type f -print0 | sort -z)

mb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1048576 }'; }

report="### Web export size

| | Size |
| --- | --- |
| Uncompressed | $(mb "$raw") MB ($raw bytes) |
| Gzip (per file, -9) | $(mb "$gz") MB ($gz bytes) |
| Budget (gzip) | ${BUDGET_MB} MB |

| File | Bytes | Gzip bytes |
| --- | --- | --- |
${rows}"

echo "$report"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$report" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$gz" -gt "$BUDGET" ]; then
  echo "check-size: FAIL gzip size $(mb "$gz") MB exceeds ${BUDGET_MB} MB budget" >&2
  exit 1
fi
echo "check-size: OK gzip size $(mb "$gz") MB within ${BUDGET_MB} MB budget"
