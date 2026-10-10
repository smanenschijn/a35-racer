#!/usr/bin/env bash
# Copy the Blender exports, the music and the route into the Godot project (Godot needs them inside res://).
set -euo pipefail
cd "$(dirname "$0")/.."
G=godot/assets
mkdir -p "$G/models" "$G/music" "$G/route"
cp public/models/*.glb "$G/models/"
cp public/music/*.mp3 "$G/music/" 2>/dev/null || true
cp src/track/routes/campaign.json "$G/route/"
echo "synced $(ls $G/models/*.glb | wc -l | tr -d ' ') models, $(ls $G/music/*.mp3 2>/dev/null | wc -l | tr -d ' ') tracks, route"
