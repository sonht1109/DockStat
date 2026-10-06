#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./Scripts/package-app.sh

APP="dist/DockStat.app"
# Ad-hoc signature — enough for local use. CI handles Developer ID
# signing/notarization for releases.
codesign --force -s - "$APP"

echo "Run with: open $APP"
