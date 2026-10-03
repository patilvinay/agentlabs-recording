#!/usr/bin/env bash
# Install agentlabs-recording: the rec-* tools on PATH and the skill for
# Claude Code and (when present) Codex. Re-run to update.
#
#   ./install.sh [--no-codex]
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BINDIR="$HOME/.local/bin"
codex=1
[ "${1:-}" = "--no-codex" ] && codex=0

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }

say "Installing agentlabs-recording"
mkdir -p "$BINDIR"
install -m 0755 "$REPO"/bin/rec-init "$REPO"/bin/rec-step "$REPO"/bin/rec-build \
  "$REPO"/bin/rec-tts "$REPO"/bin/rec-animate "$BINDIR"/
ok "rec-init, rec-step, rec-build, rec-animate → $BINDIR"

# rec-animate's renderer and its one dependency (playwright-core drives Chrome).
LIB="$HOME/.local/share/agentlabs-recording/animate"
mkdir -p "$LIB"
install -m 0644 "$REPO"/lib/animate/player.html "$REPO"/lib/animate/render.mjs "$REPO"/lib/animate/package.json "$LIB"/
if command -v npm >/dev/null && (cd "$LIB" && npm install --no-audit --no-fund --silent >/dev/null 2>&1); then
  ok "rec-animate renderer → $LIB"
else
  warn "rec-animate needs node + npm (then re-run install.sh); rec-build works without it"
fi

install_skill() {
  local dest="$1/agentlabs-recording"
  mkdir -p "$dest" && install -m 0644 "$REPO/skills/agentlabs-recording/SKILL.md" "$dest/SKILL.md"
  ok "skill → $dest"
}
install_skill "$HOME/.claude/skills"
if [ "$codex" = 1 ] && [ -d "${CODEX_HOME:-$HOME/.codex}" ]; then
  install_skill "${CODEX_HOME:-$HOME/.codex}/skills"
fi

say "Checking tools"
if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then ok "ffmpeg"
elif command -v docker >/dev/null; then ok "docker (ffmpeg runs in ${REC_FFMPEG_IMAGE:-jrottenberg/ffmpeg:6.1-alpine})"
else warn "neither ffmpeg nor docker found — install one (sudo apt install ffmpeg)"; fi
if command -v edge-tts >/dev/null || [ -x "$HOME/.venvs/tts/bin/edge-tts" ]; then ok "edge-tts"
else warn "edge-tts not found — pipx install edge-tts (or set REC_TTS=espeak)"; fi
if [ -x /usr/bin/google-chrome ] || [ -x /opt/google/chrome/chrome ] || command -v chromium >/dev/null || [ -n "${REC_CHROME:-}" ]; then ok "Chrome (rec-animate)"
else warn "no Chrome found — rec-animate needs one (or REC_CHROME=/path/to/chrome)"; fi
if command -v voice-offer >/dev/null; then ok "live narration via agentlabs-voice"
else warn "agentlabs-voice not installed — recordings work, but are not spoken live"; fi
case ":$PATH:" in *":$BINDIR:"*) ;; *) warn "$BINDIR is not on PATH" ;; esac
