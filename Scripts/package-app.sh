#!/bin/bash
# Build the release binary and assemble dist/DockStat.app (unsigned).
# Shared by the Makefile, build.sh and GitHub Actions (CI + release).
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer a universal (arm64 + x86_64) binary so both Apple Silicon and Intel
# Macs can run it. Needs full Xcode (macOS CI runners have it); falls back to
# the native arch when unavailable (e.g. local Command Line Tools only).
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/dockstat"
else
  echo "Universal build not available, falling back to native arch"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/dockstat"
fi

APP="dist/DockStat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/dockstat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo "App at: $APP"
