# AI Workspace

Project-local context, indexes, scripts, and durable notes for AI agents.

## Start here

- Agent rules: `../.ai/AGENTS.md` ← canonical; read this first
- Active task: `../.ai/HANDOFF.md`
- Human walkthrough: `../walkthrough.md`
- Workflow check: `scripts/check-workflow.ps1`

## Layout

```
scripts/
  brief.ps1               — session startup: routes query, emits next-phase prompt,
                            warns on HANDOFF line-count, stale research, writes session capsule
  traverse.ps1            — zero-grep lookup (Symbol/Endpoint/Err/Module/Brain/Caller)
  validate-handoff.ps1    — pre-build gate: fields, line cap, placeholders, index freshness
  generate-index.ps1      — rebuilds symbol_index + endpoint_index (-Incremental for hooks)
  complete-task.ps1       — end-of-task capture + brain write
  brain-capture.ps1       — manual brain entry
  brain-recall.ps1        — manual brain search (brief.ps1 inlines this)
  compile-hot-cache.ps1
  compile-incident-cache.ps1
  check-workflow.ps1      — checks workflow structure + brain IDs + index staleness
  check-staleness.ps1     — Obsidian incident freshness vs git commits
  generate-diff-brief.ps1

agents/
  skills.index.yaml       — lazy project-skill catalog (load max 2)
  domain-manifest.yaml    — module keyword → file routing
  research.md             — verified discoveries (check before grep)
  lessons-learned.md      — permanent bug memory (check before RCA)
  brain/
    brain-index.md        — compact index (brief inlines top-3 hits)
    brain.md              — full brain entries
  references/
    symbol_index.md       — commit-stamped symbol table
    endpoint_index.md     — commit-stamped endpoint table
  meta/                   — agent operational meta
    skill-routing.md
    issue-tracker.md
    triage-labels.md
    domain.md

generated/              — rebuildable machine output (hot/incident caches)
Obsidian/               — single vault; durable architecture + decisions
templates/              — shared note templates
```

## Zero-grep rule

Call `traverse.ps1` before any `rg`. Only fall back on `TRAVERSE_MISS`.

## Obsidian vault

Open only `ai-workspace/Obsidian` as an Obsidian vault.
Source code and tests are the truth; this directory is not a Git repo.

## How to use this template in a new project

1. Copy `.ai/` and `ai-workspace/` folders into the root directory of the new project.
2. Update the absolute path in `.ai/PROJECT` to point to the new project's root directory.
3. Replace `{{PROJECT_NAME}}` in `.ai/AGENTS.md` and `.ai/HANDOFF.md` with the new project's name.
4. Fill in `agents/conventions.md` with the details of the new project's development stack, setup commands, and directory structure rules.
5. Rebuild code indexes automatically by running `generate-index.ps1` from the scripts folder.
6. Customize the module mappings in `domain-manifest.yaml` to match the new codebase's module structure.
7. Start fresh with the new project's architecture, decisions, and tasks in your Obsidian vault.
