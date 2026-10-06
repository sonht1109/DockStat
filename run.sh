#!/bin/bash
cd "$(dirname "$0")"
pkill -f 'DockStat.app/Contents/MacOS/dockstat' 2>/dev/null || true
open dist/DockStat.app
