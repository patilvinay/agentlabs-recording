# agentlabs-recording

Narrated product demos, recorded by a coding agent. Real screenshots of your
app, one per step, a natural voice explaining each, spoken live while the
agent drives the app, then built into a small MP4 with subtitles.

```
rec-init DIR "Title"           start a demo folder
rec-step -C DIR 03 "…"         narrate step 03: save, speak, print seconds to wait
rec-build -C DIR               → DIR/demo.mp4 + DIR/demo.srt
```

It is a narrated slideshow, not a screen capture: deterministic, about 3 MB
for 2½ minutes, and any one step can be redone (`rec-step` + a new
screenshot) and rebuilt in seconds.

Works with **Claude Code** (driving the browser with Claude in Chrome) and
**Codex** (driving it with Playwright): both read the same
[`SKILL.md`](skills/agentlabs-recording/SKILL.md), which holds the recipe and
the lessons behind it. Ask your agent to "record a demo of …".

## Install

```bash
git clone https://github.com/patilvinay/agentlabs-recording
cd agentlabs-recording && ./install.sh
```

Puts `rec-init`, `rec-step`, `rec-build` in `~/.local/bin` and the skill in
`~/.claude/skills/` and `~/.codex/skills/`.

Needs:
- **ffmpeg**, or Docker (it then runs `jrottenberg/ffmpeg:6.1-alpine`)
- **edge-tts** for the voice (`pipx install edge-tts`); offline it falls back
  to espeak-ng
- optional: [agentlabs-voice](https://github.com/patilvinay/agentlabs-voice),
  to hear the narration live as the demo is recorded

## Output

```
demo/
  README.md        step table
  shots/NN.jpg     one full-size screenshot per step
  audio/NN.txt     narration text
  audio/NN.mp3     narration audio
  demo.mp4         the video (1600×832 by default; -s to change)
  demo.srt         subtitles, timed to the narration
  seg/             per-step segments, disposable
```

## Test

```bash
tests/test.sh      # offline, end to end, silent narration
```

Companion projects: [agentlabs-voice](https://github.com/patilvinay/agentlabs-voice),
[agentlabs-ideas-skill](https://github.com/patilvinay/agentlabs-ideas-skill).
