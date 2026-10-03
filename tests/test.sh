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
# Word times from a transcript, matched back to the script (the Deepgram path, offline).
python3 - "$REPO/bin/rec-tts" <<'PY' || fail "transcript alignment"
import sys, types
src = open(sys.argv[1]).read().split("\np = argparse.ArgumentParser()")[0]
m = types.ModuleType("rt"); exec(src, m.__dict__)
heard = [{"w": w, "start": i * 0.5, "end": i * 0.5 + 0.4} for i, w in enumerate("about 1000 atoms thick".split())]
out = m.align("about one thousand atoms thick.", heard)
assert [w["w"] for w in out] == ["about", "one", "thousand", "atoms", "thick."], out
assert out[0]["start"] == 0 and out[3]["start"] == 1.0 and out[1]["start"] < out[2]["start"] < 1.0, out
PY
echo "ok: rec-build end to end"

# rec-animate: title, scene and cued screenshot, sound and music; needs node + Chrome.
if ! command -v node >/dev/null || [ ! -d "$REPO/lib/animate/node_modules/playwright-core" ]; then
  echo "skip: rec-animate (run install.sh for node deps)"; exit 0
fi
a=$(rec-init "$tmp/anim" "Animated")
ff ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=white:s=1200x700 -frames:v 1 /t/anim/shots/03.png
rec-step -C "$a" 01 "An animated test." >/dev/null
rec-step -C "$a" 02 "First the boxes, then the line." >/dev/null
rec-step -C "$a" 03 "Zoom here, then click the button." >/dev/null
[ -s "$a/audio/02.words.json" ] || fail "rec-step wrote no word timings"
before=$(stat -c %Y "$a/audio/02.mp3"); sleep 1
rec-step -C "$a" 02 "First the boxes, then the line." >/dev/null
[ "$(stat -c %Y "$a/audio/02.mp3")" = "$before" ] || fail "unchanged narration was rendered again"
mkdir -p "$a/scenes"
cat > "$a/scenes/02.svg" <<'SVG'
<svg viewBox="0 0 1600 800" xmlns="http://www.w3.org/2000/svg">
  <rect data-at="boxes" data-anim="pop" x="200" y="300" width="300" height="120" fill="#2563eb"/>
  <path data-at="line" data-anim="draw" pathLength="1" d="M500 360 L1100 360" stroke="#111" stroke-width="4" fill="none"/>
  <path id="track" d="M500 360 L1100 360" fill="none"/>
  <circle data-at="line" data-anim="travel" data-path="#track" data-dur="1" data-delay="0.2" r="8" fill="red"/>
  <rect data-at="First" data-anim="popup" data-burst="" data-emph="line" x="1200" y="300" width="100" height="100" fill="#0a0"/>
  <text data-at="boxes," data-anim="count" data-to="12000" data-format="1 in #" x="200" y="600" font-size="40">0</text>
  <text data-at="then" data-anim="type" x="200" y="700" font-size="40">typed text</text>
  <rect data-at="the" data-anim="slide-left" x="900" y="600" width="80" height="40"/>
</svg>
SVG
cat > "$a/steps.json" <<'JSON'
{ "music": "pad", "steps": [
  { "n": "01", "title": "Animated test", "subtitle": "rec-animate" },
  { "n": "02", "svg": "scenes/02.svg", "chapter": "Scene", "transition": "slide" },
  { "n": "03", "chapter": "Screenshot", "cursor": [100, 100], "cues": [
    { "at": "Zoom", "zoom": [400, 200, 400, 200], "box": [400, 200, 400, 200] },
    { "at": "click", "cursor": [600, 300] }, { "at": "button.", "click": true } ] } ] }
JSON
rec-animate -C "$a" >/dev/null 2>&1 || fail "rec-animate failed"
info=$(ff ffprobe -v error -show_entries stream=codec_type,width,height -of csv=p=0 /t/anim/demo.mp4)
grep -q '^video,1600,900' <<< "$info" && grep -q '^audio' <<< "$info" || fail "animated video streams: $info"
[ "$(grep -c -- '-->' "$a/demo.srt")" = 3 ] || fail "animated subtitle count"
rec-animate -C "$a" --only 1-2 >/dev/null 2>&1 && one=$(md5sum < "$a/preview.mp4")
rec-animate -C "$a" --only 1-2 >/dev/null 2>&1 && [ "$(md5sum < "$a/preview.mp4")" = "$one" ] || fail "re-render differs"
sed -i 's/"button."/"nowhere"/' "$a/steps.json"
err=$(rec-animate -C "$a" 2>&1) && fail "built with a missing cue word"
grep -q 'cue word "nowhere" is not in the narration' <<< "$err" || fail "missing cue word not reported: $err"
echo "ok: rec-animate end to end"
