# Fast Codebase Navigation

Fallback machine-oriented map. Use only when `domain-manifest.yaml` keywords and `brief.ps1` classification do not resolve the query.

## Truth order

1. Code and tests
2. `.ai/HANDOFF.md`
3. `agents/domain-manifest.yaml` (primary routing — check FIRST)
4. This map (fallback when manifest keywords miss)
5. `agents/conventions.md`
6. Obsidian explanations

## Backend path

`{{BACKEND_ENTRY}}` -> handler -> service -> repository -> DB

Search anchors (adapt patterns to your stack):

- route: `rg -n '<route-registration-pattern>' {{BACKEND_DIR}}`
- handler/service/repo symbol: `rg -n '<symbol>' {{BACKEND_DIR}}`
- schema: `rg -n '<table|column>' {{BACKEND_DIR}}/migrations {{BACKEND_DIR}}`
- regression: `rg -n '<route|symbol|error>' {{BACKEND_DIR}}`

Backend domains: *(fill in your project's domain areas here)*

## Frontend path

`{{FRONTEND_ENTRY}}` -> routes -> page/module -> hook/API -> apiClient -> backend

Search anchors (adapt patterns to your stack):

- route/page: `rg -n '<route-pattern>' {{FRONTEND_DIR}}/src/routes`
- module export/API: `rg -n '<symbol|route>' {{FRONTEND_DIR}}/src/modules`
- shared UI: `rg -n '<component>' {{FRONTEND_DIR}}/src/components`
- state: `rg -n '<state-pattern>' {{FRONTEND_DIR}}/src/store`

Frontend domains: *(fill in your project's frontend modules here)*

## Cross-stack trace

1. Find visible page/component text or route in frontend src.
2. Follow imported hook/API to apiClient call.
3. Search exact HTTP path in backend handlers.
4. Follow handler method -> service interface/method -> repository query.
5. Stop at DB/external API; inspect migrations/tests for contract proof.

## Pre-search: Deterministic indexes (check BEFORE any rg on source)

- symbol lookup: `agents/references/symbol_index.md`
- endpoint lookup: `agents/references/endpoint_index.md`
- Regenerate: `powershell -NoProfile -File ai-workspace/scripts/generate-index.ps1`

## Documentation routing

- current task/state: `.ai/HANDOFF.md`
- module→file routing: `agents/domain-manifest.yaml`
- error→fix lookup: `generated/hot-cache.jsonl`
- project conventions: `agents/conventions.md`
- known fixes: `agents/lessons-learned.md`
- persistent memory: `agents/brain/` (via brain-recall.ps1)
- incidents: `Obsidian/Incidents/` (via compile-incident-cache.ps1)
- decisions: `Obsidian/Decisions/`

Never load all docs. Start with brief.ps1 classification, choose one domain, then open only linked source/docs.

