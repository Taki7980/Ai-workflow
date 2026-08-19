---
description: Review the built project plan with a focused diff inspection
---

Review phase. Read `.ai/AGENTS.md` and `.ai/HANDOFF.md`; run `brief.ps1 -Role reviewer` once with task keywords. Inspect only the actual diff (use `diff-scope` skill). Verify correctness, contracts, security, regressions, tests, and over-engineering. Report findings with `path:line`. No product edits unless user overrides. If findings require edits, allow one focused Antigravity repair and one re-review; then stop for user direction. After verified clean review, run `complete-task.ps1` once. Replace HANDOFF with outcome.
