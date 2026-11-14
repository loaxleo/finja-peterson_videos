#!/usr/bin/env bash
# Wandelt neue Videos aus neu/ um, erzeugt Vorschaubilder und aktualisiert videos.json.
set -euo pipefail
shopt -s nullglob
mkdir -p videos posters

ffmpeg_da() {
  command -v ffmpeg >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg)
}

# 1) Neue Videos umwandeln (H.264, max. 1080p, faststart)
#    Name = Zeitstempel -> wird nie wiederverwendet (kein alter Cache nach Löschen)
for f in neu/*; do
  [ -f "$f" ] && [ "$(basename "$f")" != ".gitkeep" ] || continue
  ffmpeg_da
  id=$(basename "$f" | grep -oE '^[0-9]+' || true)
  id=${id:-$(date +%s%3N)}
  while [ -e "videos/$id.mp4" ]; do id=$((id+1)); done
  echo "Video: $f -> videos/$id.mp4"
  ffmpeg -nostdin -v error -y -i "$f" \
    -vf "scale='if(gt(iw,ih),-2,min(1080,iw))':'if(gt(iw,ih),min(1080,ih),-2)'" \
    -c:v libx264 -crf 24 -preset veryfast -pix_fmt yuv420p \
    -c:a aac -b:a 128k -movflags +faststart "videos/$id.mp4"
  git rm -q "$f" 2>/dev/null || rm -f "$f"
done

# 2) Vorschaubilder für Videos ohne Bild
for v in videos/*.mp4; do
  id=$(basename "$v" .mp4)
  [ -f "posters/$id.jpg" ] && continue
  ffmpeg_da
  echo "Vorschau: $v"
  vf="scale='if(gt(iw,ih),-2,min(720,iw))':'if(gt(iw,ih),min(720,ih),-2)'"
  ffmpeg -nostdin -v error -y -ss 0.5 -i "$v" -frames:v 1 -vf "$vf" -q:v 4 "posters/$id.jpg" || true
  [ -s "posters/$id.jpg" ] || ffmpeg -nostdin -v error -y -i "$v" -frames:v 1 -vf "$vf" -q:v 4 "posters/$id.jpg"
done

# 3) Vorschaubilder gelöschter Videos entfernen
for p in posters/*.jpg; do
  id=$(basename "$p" .jpg)
  [ -f "videos/$id.mp4" ] || rm -f "$p"
done

# 4) videos.json: bestehende Reihenfolge behalten, Gelöschtes raus, Neues ans Ende
python3 - <<'EOF'
import json, os, re
try:
    alt = json.load(open('videos.json'))
except Exception:
    alt = []
da = sorted((f for f in os.listdir('videos') if re.fullmatch(r'\d+\.mp4', f)),
            key=lambda f: int(f[:-4]))
liste = [f for f in alt if f in da] + [f for f in da if f not in alt]
json.dump(liste, open('videos.json', 'w'))
print(liste)
EOF
