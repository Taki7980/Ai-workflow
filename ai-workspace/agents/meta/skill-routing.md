# Skill Routing

Use installed helpers inside the active workflow phase. Project-local skills win. Load at most two task skills.

## Plan phase

- Unclear product intent: `grilling`.
- Missing or disputed domain language: `domain-modeling`.
- Module boundary or interface decision: `codebase-design`.
- External evidence required: `research`.

Use only the smallest matching set. A clear plan needs none.

## Build phase

- Non-trivial behavior with a clean test seam: `tdd`.
- Hard or repeated bug: prefer `root-cause-analysis`; use `diagnosing-bugs` only when default guidance does not cover it.
- Design uncertainty requiring disposable proof: `prototype`.

Small text, style, configuration, and obvious one-line changes need no helper.

## Review phase

- Review uses `AGENTS.md`; load global `code-review` only when user requests its two-axis review.
- Active merge or rebase conflict: `resolving-merge-conflicts`.
- Human-only dashboard, credential, provisioning, or cutover steps: `wizard` only when a Bash wizard is requested; otherwise give numbered PowerShell instructions.
- Agent-facing instructions: `writing-for-agents`.

## Explicit workflows

Never auto-run `ask-matt`, `grill-with-docs`, `triage`, `improve-codebase-architecture`, `to-spec`, `to-tickets`, `implement`, or `wayfinder`. They replace or expand workflow ownership and require user invocation.

## Agent-specific enhancements (optional)

Install these for extra token savings — none are required for the workflow to function:

| Enhancement | Agent | What it does |
|---|---|---|
| `ponytail` skill | Gemini/Antigravity | Ultra-lean coding mode — cuts boilerplate, marks corners |
| `rtk` CLI tool | Gemini/Antigravity | Compresses noisy shell output before it enters model context |
| `--compact` flag | Claude Code CLI | Reduces verbose command output |
| `caveman` skill | Gemini/Antigravity | Blunt, direct output style — fewer filler words |

