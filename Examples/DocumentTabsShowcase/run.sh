#!/bin/bash
# Build (via SwiftPM, consuming the Tabberwocky package) and launch the app.
# One command for the on-demand test loop: ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

# Quit any running instance so we always launch the fresh build.
pkill -f 'DocumentTabsShowcase.app/Contents/MacOS' 2>/dev/null || true
sleep 0.5

./build.sh
open DocumentTabsShowcase.app
