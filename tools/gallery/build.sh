#!/bin/sh
# Rebuilds the asset gallery (claude.ai artifact) in tools/gallery/out from the current
# renders and models. Publish tools/gallery/out/index.html with its img/ and models/ files.
set -e
cd "$(dirname "$0")/../.."
OUT=tools/gallery/out
rm -rf "$OUT" && mkdir -p "$OUT/img" "$OUT/models"
cp tools/gallery/index.html "$OUT/"
for f in assets/renders/*_front.png; do
  n=$(basename "$f" .png)
  sips -s format jpeg -s formatOptions 78 -Z 760 "$f" --out "$OUT/img/$n.jpg" >/dev/null
done
# The artifact host serves .json but not .glb: wrap each model in base64.
python3 - <<'PY'
import base64, glob, json, os
for f in glob.glob('public/models/*.glb'):
    name = os.path.basename(f)[:-4]
    json.dump({'glb': base64.b64encode(open(f, 'rb').read()).decode()}, open(f'tools/gallery/out/models/{name}.json', 'w'))
PY
echo "Gallery ready in $OUT"
