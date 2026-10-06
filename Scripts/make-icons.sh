#!/bin/bash
# Render Resources/DockStat.icns from Scripts/make-icon.swift.
# The icon is code: edit the script, not the .icns.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=".build/DockStat.iconset"
OUT="Resources/DockStat.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

swift Scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Icon: $OUT"
