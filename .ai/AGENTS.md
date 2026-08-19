# {{PROJECT_NAME}} AI Workflow

One shared task record: `.ai\HANDOFF.md`. Code and tests outrank notes. One owner edits at a time.

## Choose lane

- **Answer**: questions and explanations are read-only; answer directly. No workflow files.
- **Small**: one obvious behavior, at most 2 product files, known edit site, focused check, no API/schema/migration/security/payment/state/concurrency/data-loss risk. Use Antigravity `/small`; Codex review only when requested or risk appears.
- **Full**: everything else uses plan, build, and review. Refine only when the plan-readiness gate fails.

## Full-lane startup

Read `C:\Users\{{USERNAME}}\AI_CONTEXT.md` and HANDOFF, then run once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File {{PROJECT_ROOT}}\ai-workspace\scripts\brief.ps1 -Role <planner|builder|reviewer> -Query "<task keywords>"
```

Do not rerun brief, reread included content, or paste plan text into prompts.
If `AI_CONTEXT.md` cannot be read, report that as a blocker; do not claim global context was loaded.

**Traversal rule**: Before any `rg`/grep, call `traverse.ps1` with the matching mode:
```powershell
powershell -File ai-workspace/scripts/traverse.ps1 -Symbol <name>
powershell -File ai-workspace/scripts/traverse.ps1 -Endpoint <route>
powershell -File ai-workspace/scripts/traverse.ps1 -Err <text>
powershell -File ai-workspace/scripts/traverse.ps1 -Module <keyword>
powershell -File ai-workspace/scripts/traverse.ps1 -Brain <keywords>
```
Only fall back to `rg` on `TRAVERSE_MISS`. Never grep for a symbol that exists in the index.


## Full-lane phases

1. **Agy CLI / plan** `/plan`: verify current flow from routed source. HANDOFF names goal/non-goals, exact paths+symbols+callers, ordered edits, reuse/deletions, invariants, focused checks, dirty-file boundaries, risks/TBD. No product edits. Brief auto-emits next prompt.
2. **Plan-readiness gate**: build directly when HANDOFF has exact edit sites, scope, invariants, checks, and no blocking TBD. Otherwise Codex uses `reviewer` to replace it with at most 8 builder-ready bullets; one targeted lookup only. Project-local rule overrides coordinators that always refine.
3. **Antigravity IDE / build** `/build`: use `builder`; run `validate-handoff.ps1` first — stop if it fails; edit only named scope, reuse existing patterns, run named checks. Stop and mark `blocked` on mismatch. Update HANDOFF once at phase end. Brief auto-emits next prompt.
4. **Codex / review** `/review`: use `reviewer`; inspect actual diff. Verify correctness, contracts, security, regressions, tests, and over-engineering. Findings first with `path:line`. No product edits unless user overrides. If findings require edits, allow one focused Antigravity repair and one Codex re-review; then stop for user direction. After verified completion, run `complete-task.ps1` once; capture only a reusable lesson and resolve only an explicitly named open incident.

## Agent skills

Automatically route planning, debugging, building, domain/design, research, conflict, and human-only work through `ai-workspace/agents/meta/skill-routing.md`. Project-local skills win; user-invoked orchestrators stay explicit.

### Issue tracker

GitHub Issues split by ownership. See `ai-workspace/agents/meta/issue-tracker.md`.

### Triage labels

Use canonical triage labels. See `ai-workspace/agents/meta/triage-labels.md`.

### Domain docs

Existing Obsidian glossary, indexes, and decisions are authoritative. See `ai-workspace/agents/meta/domain.md`.

## Context budget

- Open only brief-routed files. Use current `research.md`; one linked Obsidian note only for durable rationale.
- Load matching task skill directly; maximum two. `ponytail` and `caveman` are modes.
- Raw output is disposable. Store reusable verified facts in `research.md`, novel bug cause+fix in `lessons-learned.md`, durable decisions in Obsidian.
- `brief.ps1` routing metrics record classification/cache facts only. They do not measure model tokens. Do not report percentage savings without external usage data.
- Capture brain memory only for genuinely reusable discoveries, never routine completion or estimated savings.
- HANDOFF stays under 30 lines. Next prompt only names phase and says `read .ai/HANDOFF.md`.

## RTK

- Gemini CLI hook inspects every shell command and rewrites supported commands automatically.
- Antigravity and Codex are rules-based: prefix supported noisy commands (`git`, tests, builds, lint, broad `rg`) with `rtk`.
- Keep short `Get-Content`, targeted `rg`, brief, and exact diagnostic commands direct. Use `rtk proxy` only when exact raw output must be preserved.
- Never wrap unsupported commands through `rtk run`; that adds overhead without compression.

Run Git inside each sub-project directory; never create a parent monorepo or mix commits across sub-projects.
