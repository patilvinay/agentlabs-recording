---
name: agentlabs-recording
description: Record a narrated product demo as an MP4 — real screenshots of the app, one per step, with a natural voice explaining each, spoken live as you go and built into a video with subtitles; or an animated one, with camera moves, highlights, cursor, animated SVG explainer scenes, title cards, captions, sound effects and music, every motion cued by the spoken word. Use when the user asks to record, film, animate or make a video of a demo, walkthrough or explainer, or to change or redo part of an existing recording.
---

# Recording a narrated demo

The result is a **narrated slideshow of real screens**, not a screen capture:
one full-size screenshot per step, 2–4 sentences of narration per step, built
into `demo.mp4` (plus `demo.srt`). It is deterministic, small (~3 MB for 2½
minutes), and any single step can be redone without re-recording the rest.
The same narration is spoken live while you drive the app, so whoever is
watching hears it as it happens.

Tools, installed on PATH by this repo:

| Command | Does |
|---|---|
| `rec-init DIR "Title"` | creates `DIR/shots/`, `DIR/audio/`, a `README.md` with a step table |
| `rec-step [-C DIR] NN "narration"` | saves `audio/NN.txt`, renders `audio/NN.mp3`, speaks it live, **prints seconds to wait** |
| `rec-build [-C DIR] [-o demo.mp4] [-s 1600x832]` | one segment per step, concatenated, plus subtitles |
| `rec-animate [-C DIR] [-o demo.mp4] [--only FROM-TO]` | the animated build: see **Animated demos** below |

## 1. Plan before touching the app

Write the step list first, in the demo's `README.md` table: one screen state
per step, 6–10 steps, ~20–30 s of narration each. Say what is on screen and
why it matters — not which button you are about to press. Put the recording
folder in the session's scratch area (e.g. `00-scratch/NN-<name>-demo/`).

## 2. The step loop

For each step `NN` (01, 02, …):

1. **Drive the app to the state** — navigate, click, fill the form.
2. **Screenshot at full size** to `DIR/shots/NN.jpg` (or `.png`).
3. **Narrate:** `rec-step -C DIR NN "…"`. It prints a number of seconds.
4. **Wait that long before changing the screen**, so the live voice stays on
   the screen it is describing. Browser tools often cap one wait at ~10 s:
   wait in several chunks.

Re-recording one step later is the same three actions for that `NN` only,
then `rec-build` again.

### Driving the browser

- **Claude Code** — Claude in Chrome: `screenshot` with `save_to_disk: true`
  and **scale 1**. Smaller scales save smaller files, which look blurry in
  the video. `form_input` sets React form values reliably; typing with the
  computer tool sometimes does not register.
- **Codex, or headless** — Playwright:
  `page.screenshot(path=f"{dir}/shots/{nn}.png")` at the viewport you want
  in the video (1600×832 fills the default canvas exactly).
- Whatever the driver, the contract is the same: `shots/NN.*` matches
  `audio/NN.mp3`.

## 3. Build and deliver

```bash
rec-build -C DIR            # → DIR/demo.mp4 and DIR/demo.srt
```

Fill in the README table, give the user the MP4 path (open it for them when
asked), and keep `shots/`, `audio/` and the README: they are what makes a
one-step fix a ten-second rebuild. `seg/` is disposable.

## Animated demos

`rec-animate` builds the same folder into a motion video: the camera zooms
and pans across a screenshot, a highlight glides to what is being described,
a cursor moves and clicks, explainer steps are animated SVG diagrams that
draw themselves, and a title card, chapter labels, karaoke captions, a
progress bar, sound effects and an optional music bed tie it together.
**Every motion is cued by a spoken word**: `rec-step` also writes
`audio/NN.words.json`, the time each word is said.

### The folder is the source

Keep editing the source, never the video:

```
steps.json        the steps and their cues (below)
scenes/NN.svg     explainer diagrams
shots/NN.*        screenshots
audio/NN.txt      narration; NN.mp3 + NN.words.json from rec-step
demo.mp4/.srt     output, rebuilt from the above
```

A change the user asks for ("zoom on the total sooner", "say Finance
first", "make the diagram blue") is an edit to one of those files and a
re-render. **Re-renders are reproducible**: frames are computed from time
alone and sounds are synthesised with fixed seeds, so an unchanged source
gives a byte-identical video, and a change touches only what it changes.
`rec-step` keeps the audio of unchanged narration (a TTS service never
returns the same audio twice, and every cue hangs on its word times);
`REC_FORCE=1` renders it again. Preview a stretch with `--only 20-30`
(writes `preview.mp4`, ~5 s) before a full build (~30 s a minute).

### steps.json

```json
{ "music": "pad",
  "steps": [
    { "n": "00", "title": "Departments in the HRMS", "subtitle": "Setting up the organisation" },
    { "n": "01", "svg": "scenes/01.svg", "chapter": "How it fits together" },
    { "n": "02", "chapter": "Create a department", "cursor": [1210, 345], "cues": [
      { "at": "form",        "zoom": [229, 255, 1320, 165], "box": [229, 255, 1320, 165] },
      { "at": "Engineering", "box": [249, 324, 633, 30], "cursor": [600, 340] },
      { "at": "Pressing",    "box": [1466, 368, 62, 30], "cursor": [1497, 384] },
      { "at": "adds",        "click": true },
      { "at": "list",        "zoom": "full", "box": null } ] } ] }
```

- A step is a **title** (`title`, `subtitle`), a **scene** (`svg`) or a
  **shot** (the default: `shots/NN.*`). Every step is narrated with
  `rec-step`, the title card too; `chapter` adds a lower-third label.
- **Cues** (shots): `at` is a word of the narration (`"Create#2"` for its
  second time, or a number of seconds). `zoom` is a rectangle `[x, y, w, h]`
  in screenshot pixels or `"full"`; `box` moves the highlight (`null` hides
  it, `label` adds text); `cursor` glides there (give the step a starting
  `cursor` to show one); `click` ripples. Read the coordinates off the
  screenshot itself.
- **Scenes**: an SVG with `viewBox="0 0 1600 800"`; any element with
  `data-at="<word>"` appears when that word is said, `data-anim` `pop`,
  `rise`, `fade` or `draw` (a path with `pathLength="1"` draws itself).
  `data-at="0"` is there from the start.
- **Sound**: whoosh on transitions, rise on title cards, click, tick on
  highlight moves, pop on scene elements (`"sfx": false` turns them off).
  `"music": "pad"` synthesises a soft bed, or name an audio file; it is
  ducked under the voice. Also: `captions`, `progress`, `accent`,
  `highlight`, `musicVolume`, `sfxVolume`, `hold` (seconds after a step).
- `patch: [[x, y, w, h, fill]]` covers a mouse pointer baked into a
  screenshot; a number in place of `fill` clones the strip that many
  pixels to the side. Better: take screenshots without the pointer.
- Without `steps.json` every narrated step is a plain shot with captions
  and cross-fades, so any old recording can be re-rendered animated.

## Lessons (each learned by getting it wrong)

- **Live speech needs explicit text.** Mid-turn, the agent's own words are
  not in the transcript yet, so narration must be passed as text — which
  `rec-step` does through agentlabs-voice's `voice-offer --force --text`.
  Without agentlabs-voice installed the recording still works, silently.
- **Auto-speak off means an offer pane, not speech.** For a demo someone
  asked to *hear*, turn auto-speak on for the session (agentlabs-voice:
  `prefix A`, or `<scratch>/<session>/.auto` containing `1`).
- **The browser window must be on the viewer's current workspace.** Check
  with `wmctrl -lx` after opening it; move only your own windows
  (`wmctrl -i -r <id> -t <desktop>`).
- **Signing in:** agents may only use test credentials on local hosts
  (`localhost`, `*.localhost`, `*.test`). Point the demo at such a host.
- **Privacy:** never narrate secrets, and make sure sensitive values are
  masked on screen before the screenshot — the video outlives the session.
- **Screens of different sizes** are letterboxed onto one white canvas, so a
  window resize mid-demo is harmless.

## Configuration

| Variable | Default | |
|---|---|---|
| `REC_TTS` | `edge` | `edge`, `espeak` (offline), `silent` (tests); edge falls back to espeak-ng when offline |
| `REC_VOICE` | `en-US-AvaMultilingualNeural` | any `edge-tts --list-voices` name |
| `REC_RATE` | `+0%` | Edge speaking rate |
| `REC_LIVE` | `1` | `0` records without speaking aloud |
| `REC_FORCE` | `0` | `1` renders narration again even when the text is unchanged |
| `REC_CHROME` | found | Chrome for `rec-animate` |
| `REC_FFMPEG_IMAGE` | `jrottenberg/ffmpeg:6.1-alpine` | used when ffmpeg is not installed |
