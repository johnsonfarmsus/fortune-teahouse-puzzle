#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Download Godot 4.7.2-stable (the editor binary, which runs headless) and the
# matching export templates, then print the path to the binary. Supports Linux
# x86_64 and macOS (universal build, Apple silicon or Intel).
#
# Usage:  GODOT=$(tools/dev/get-godot.sh)   # progress goes to stderr
# Env:    FORTUNE_GODOT_CACHE  cache dir (default ~/.cache/fortune-godot)
#         GODOT_TEMPLATES_DIR  template install dir (default: where Godot looks,
#                              ~/.local/share/godot/export_templates/4.7.2.stable on
#                              Linux, ~/Library/Application Support/Godot/export_templates/
#                              4.7.2.stable on macOS)
set -euo pipefail

VERSION="4.7.2"
TAG="${VERSION}-stable"
BASE="https://github.com/godotengine/godot/releases/download/${TAG}"
TPL_TPZ="Godot_v${TAG}_export_templates.tpz"

log() { echo "get-godot: $*" >&2; }

CACHE="${FORTUNE_GODOT_CACHE:-$HOME/.cache/fortune-godot}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    BIN_ZIP="Godot_v${TAG}_linux.x86_64.zip"
    BIN="$CACHE/Godot_v${TAG}_linux.x86_64"
    DEFAULT_TPL_DIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
    ;;
  Darwin-*)
    # The zip holds Godot.app; keep each version's app in its own directory.
    BIN_ZIP="Godot_v${TAG}_macos.universal.zip"
    BIN="$CACHE/Godot_v${TAG}_macos/Godot.app/Contents/MacOS/Godot"
    DEFAULT_TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${VERSION}.stable"
    ;;
  *)
    log "unsupported platform $(uname -s) $(uname -m); install Godot ${VERSION} and its export templates yourself"
    exit 1
    ;;
esac
TPL_DIR="${GODOT_TEMPLATES_DIR:-$DEFAULT_TPL_DIR}"

fetch() { # url dest
  if [ -s "$2" ]; then log "cached: $2"; return; fi
  log "downloading $1"
  curl -fSL --retry 3 --retry-delay 2 -o "$2.part" "$1"
  mv "$2.part" "$2"
}

mkdir -p "$CACHE"

if [ ! -x "$BIN" ]; then
  fetch "$BASE/$BIN_ZIP" "$CACHE/$BIN_ZIP"
  case "$BIN_ZIP" in
    *macos*) unzip -oq "$CACHE/$BIN_ZIP" -d "$CACHE/Godot_v${TAG}_macos" ;;
    *)       unzip -oq "$CACHE/$BIN_ZIP" -d "$CACHE" ;;
  esac
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
