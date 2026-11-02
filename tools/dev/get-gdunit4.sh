#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Install the pinned GdUnit4 addon into game/addons/gdUnit4 for local test runs.
# The addon is NOT committed (game/.gitignore); CI installs it through
# godot-gdunit-labs/gdUnit4-action, pinned to the same version.
#
# Env: GDUNIT4_VERSION  release tag to install (default v6.2.3)
set -euo pipefail

VERSION="${GDUNIT4_VERSION:-v6.2.3}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/game/addons/gdUnit4"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "get-gdunit4: cloning GdUnit4 $VERSION" >&2
git clone --quiet -c advice.detachedHead=false --depth 1 --branch "$VERSION" --single-branch \
  https://github.com/godot-gdunit-labs/gdUnit4 "$tmp/gdUnit4"

rm -rf "$DEST"
mkdir -p "$ROOT/game/addons"
cp -R "$tmp/gdUnit4/addons/gdUnit4" "$DEST"
rm -rf "$DEST/test"          # the addon's own self-tests
chmod +x "$DEST/runtest.sh"
echo "get-gdunit4: installed $VERSION into $DEST" >&2
