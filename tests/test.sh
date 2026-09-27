#!/usr/bin/env bash
# End to end, offline: init a demo, narrate three silent steps (one PNG, two
# JPGs of different sizes), build, and check the video, subtitles and errors.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATH="$REPO/bin:$PATH"
export REC_TTS=silent REC_LIVE=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
image="${REC_FFMPEG_IMAGE:-jrottenberg/ffmpeg:6.1-alpine}"
ff() {  # run an ffmpeg-family tool with $tmp visible as /t
  local tool="$1"; shift
  if command -v "$tool" >/dev/null; then "$tool" "${@//\/t\//$tmp/}"
  else docker run --rm -u "$(id -u):$(id -g)" -v "$tmp":/t --entrypoint "$tool" "$image" "$@"; fi
}

d=$(rec-init "$tmp/demo" "Test demo")
[ -d "$d/shots" ] && [ -d "$d/audio" ] && grep -q "Test demo" "$d/README.md" || fail "rec-init layout"

ff ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=blue:s=1600x832 -frames:v 1 /t/demo/shots/01.png
ff ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=red:s=1280x720 -frames:v 1 /t/demo/shots/02.jpg
ff ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=green:s=900x1200 -frames:v 1 /t/demo/shots/03.jpg

for n in 01 02 03; do
  secs=$(rec-step -C "$d" "$n" "Step $n. Something worth saying about this screen.")
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 2 ] || fail "rec-step $n printed '$secs'"
  [ -s "$d/audio/$n.mp3" ] && [ -s "$d/audio/$n.txt" ] || fail "rec-step $n files"
done
rec-step -C "$d" 7 "bad" 2>/dev/null && fail "one-digit step accepted"

rec-build -C "$d" >/dev/null
[ -s "$d/demo.mp4" ] || fail "no demo.mp4"
info=$(ff ffprobe -v error -show_entries stream=width,height:format=duration -of csv=p=0 /t/demo/demo.mp4)
grep -q '^1600,832' <<< "$info" || fail "video size: $info"
[ "$(grep -c -- '-->' "$d/demo.srt")" = 3 ] || fail "subtitle count"
grep -q '^00:00:00,000 --> ' "$d/demo.srt" || fail "first subtitle timing"
grep -q 'Step 03. Something worth saying' "$d/demo.srt" || fail "subtitle text"

rm "$d/shots/02.jpg"
rec-build -C "$d" 2>/dev/null && fail "built with a missing screenshot"
rec-build -C "$d" -o '../x.mp4' 2>/dev/null && fail "accepted an output path outside the folder"
echo "ok: agentlabs-recording end to end"
