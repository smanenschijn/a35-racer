#!/usr/bin/env bash
# Export A35 Racer as a Mac app (universal: Apple silicon + Intel) to godot/build/macos/A35 Racer.app.
# Usage: scripts/macos-build.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
scripts/sync-godot-assets.sh
rm -rf "godot/build/macos" && mkdir -p godot/build/macos
"$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
"$GODOT" --headless --path godot --export-release "macOS" "build/macos/A35 Racer.app" 2>&1 | grep -E "ERROR|error" || true
[ -d "godot/build/macos/A35 Racer.app" ] || { echo "Export mislukt (export templates geïnstalleerd? Godot → Editor → Manage Export Templates)"; exit 1; }
echo "Klaar: godot/build/macos/A35 Racer.app"
[ "${1:-}" = "--open" ] && open "godot/build/macos/A35 Racer.app"
