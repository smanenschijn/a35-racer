#!/usr/bin/env bash
# Export the Godot project for iOS, build it signed (free personal team) and install it on the connected
# iPhone or iPad. Usage: scripts/ios-deploy.sh [device-udid]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
TEAM=4JPRJ9VXZ4
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone|iPad/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/ || $i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/) print $i}' | head -1)}"
[ -n "$DEVICE" ] || { echo "Geen iPhone of iPad gevonden: sluit hem aan en ontgrendel hem."; exit 1; }

scripts/sync-godot-assets.sh
rm -rf godot/build/ios && mkdir -p godot/build/ios
"$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
"$GODOT" --headless --path godot --export-debug "iOS" build/ios/A35Racer.xcodeproj >/dev/null 2>&1
cd godot/build/ios
xcodebuild -project A35Racer.xcodeproj -scheme A35Racer -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=$TEAM build 2>&1 | grep -E "error:|BUILD"
xcrun devicectl device install app --device "$DEVICE" DerivedData/Build/Products/Debug-iphoneos/A35Racer.app | grep -E "App installed|error"
xcrun devicectl device process launch --device "$DEVICE" nl.manenschijn.a35racer >/dev/null 2>&1 && echo "Gestart op je toestel" || echo "Geïnstalleerd; open de app op je toestel"
