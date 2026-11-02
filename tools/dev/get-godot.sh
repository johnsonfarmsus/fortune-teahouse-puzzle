#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Download Godot 4.7.2-stable (linux x86_64 editor binary, which runs headless)
# and the matching export templates, then print the path to the binary.
#
# Usage:  GODOT=$(tools/dev/get-godot.sh)   # progress goes to stderr
# Env:    FORTUNE_GODOT_CACHE  cache dir (default ~/.cache/fortune-godot)
#         GODOT_TEMPLATES_DIR  template install dir
#                              (default ~/.local/share/godot/export_templates/4.7.2.stable)
set -euo pipefail

VERSION="4.7.2"
TAG="${VERSION}-stable"
BASE="https://github.com/godotengine/godot/releases/download/${TAG}"
BIN_ZIP="Godot_v${TAG}_linux.x86_64.zip"
TPL_TPZ="Godot_v${TAG}_export_templates.tpz"

CACHE="${FORTUNE_GODOT_CACHE:-$HOME/.cache/fortune-godot}"
TPL_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/${VERSION}.stable}"
BIN="$CACHE/Godot_v${TAG}_linux.x86_64"

log() { echo "get-godot: $*" >&2; }

fetch() { # url dest
  if [ -s "$2" ]; then log "cached: $2"; return; fi
  log "downloading $1"
  curl -fSL --retry 3 --retry-delay 2 -o "$2.part" "$1"
  mv "$2.part" "$2"
}

mkdir -p "$CACHE"

if [ ! -x "$BIN" ]; then
  fetch "$BASE/$BIN_ZIP" "$CACHE/$BIN_ZIP"
  unzip -oq "$CACHE/$BIN_ZIP" -d "$CACHE"
  chmod +x "$BIN"
fi

if [ ! -f "$TPL_DIR/web_nothreads_release.zip" ]; then
  fetch "$BASE/$TPL_TPZ" "$CACHE/$TPL_TPZ"
  tmp="$(mktemp -d)"
  unzip -oq "$CACHE/$TPL_TPZ" -d "$tmp"
  mkdir -p "$TPL_DIR"
  cp -a "$tmp"/templates/. "$TPL_DIR"/
  rm -rf "$tmp"
  log "export templates installed in $TPL_DIR"
fi

echo "$BIN"
