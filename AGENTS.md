# agentlabs-recording — agent instructions

When asked to record, film or make a video of a demo or walkthrough, follow
[`skills/agentlabs-recording/SKILL.md`](skills/agentlabs-recording/SKILL.md).
It is the single source of instructions for both Claude Code and Codex; the
installer copies it to `~/.claude/skills/` and `~/.codex/skills/`.

Working on this repo itself: the tools are `bin/rec-init`, `bin/rec-step`,
`bin/rec-build` and `bin/rec-animate` (renderer in `lib/animate/`); run `tests/test.sh` after changing any of them. It
builds a small demo end to end with silent narration, so it needs Docker or
ffmpeg but no network.
