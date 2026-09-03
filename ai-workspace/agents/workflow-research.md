# Token-efficient project agent workflow: official-source findings

Research date: 2026-08-19. Scope: project-local Codex, Gemini CLI/Antigravity, skills, code navigation, RTK, caching, and measurement.

## Hard limits

- "Zero-token" code traversal is impossible once search results enter model context. Local scripts and indexes can do computation without model tokens; only their small, selected output should be returned.
- "Zero quality loss" cannot be promised. Treat quality as an eval gate: compare representative tasks before and after every prompt/tool change. OpenAI explicitly says lower resource use counts as improvement only when final results still pass evals.

## Recommended shape

### Always loaded

Keep project `AGENTS.md`/`GEMINI.md` adapters tiny: authority, safety boundary, task router, four-stage large flow, small flow, and pointers to on-demand skills/scripts. Do not copy full workflows into every adapter. Codex concatenates global-to-local `AGENTS.md` files and caps the combined project guidance at 32 KiB by default, so duplication directly consumes every run's context. Gemini likewise concatenates hierarchical context files; component instructions can load just in time when tools enter that directory.

Use stable instruction order and wording. OpenAI prompt caching requires exact prefix matches; changing early instructions, tools, schemas, or ordering reduces reuse. Put stable policy first and task-specific state last.

### Big work: preserve four stages

1. **Brief**: deterministic repo state, handoff, task classification, relevant cached evidence only.
2. **Locate**: query symbol/route/index first; return paths, lines, callers, tests, and freshness marker. Read source only for selected hits.
3. **Change**: smallest scoped edit; use on-demand task skill only.
4. **Verify and handoff**: focused checks, diff review, compact state with exact next action.

### Small work

Run brief classification, then direct locate/change/check in one agent. No research stage, panel, or subagent unless scope expands.

## Skills and instructions

- Put cross-agent project skills under `.agents/skills/<name>/SKILL.md`; Gemini officially recognizes `.agents/skills/` as a workspace alias, and Codex supports project skills.
- Keep each description short, distinct, and trigger-rich. Both Codex and Gemini load skill metadata first and the body only after activation. Codex budgets the initial skill catalog to at most 2% of context or 8,000 characters when context size is unknown.
- Keep `SKILL.md` procedural and small. Move schemas/examples to `references/`; move deterministic work to `scripts/`; load either only when the procedure requires it.
- Persistent context is for universal facts only. Occasional workflows belong in skills or project commands. Antigravity workspace rules live under `.agents/rules/`; workflows are on-demand under `.agents/workflows/`.

## Deterministic navigation

- Build commit-addressed manifests outside the model: tracked files, endpoints, exported symbols, callers/imports, tests, migrations, and ownership/domain mapping.
- Use `rg` for exact text and bounded file-type/glob searches. It already respects ignore files, skips hidden/binary files, and supports `--files`, types, globs, counts, and line output.
- Use Universal Ctags JSON Lines for language-aware symbol records where available; records can include path, kind, scope, and scope kind.
- Each index must store source commit/hash and generator version. Reject stale indexes instead of returning confident stale evidence.
- Query output contract should be tiny and loss-aware: `path:line | symbol | relation | confidence`; cap normal results, but report truncation and offer an exact/raw mode. Search computation is local; returned output still costs tokens.
- Prefer `git diff --name-status`/scoped diffs for review tasks before loading whole files.

## RTK and command output

- Initialize RTK only in this project, not globally; preview with `rtk init --dry-run -v`, then use the project-specific Codex/Gemini init supported by the installed RTK version.
- Route noisy supported commands through RTK: tests, builds, linters, large Git output, and broad searches. Do not wrap short outputs where RTK overhead can exceed savings.
- Preserve an escape hatch: `rtk proxy <command>` or direct command for exact raw evidence. RTK's own design says explicit verbose/detail requests should preserve correctness.
- Treat RTK metrics as shell-output reduction only. `rtk gain` estimates tokens as bytes divided by four; it is not billed model-token measurement.

## Subagents and handoffs

- Delegate only independent, broad work that benefits from parallelism or isolates noisy exploration. OpenAI states each subagent performs its own model/tool work and generally consumes more tokens than a comparable single-agent run.
- Require bounded ownership and a compact evidence schema. Return conclusions plus file/line proof, never raw logs. Main thread keeps requirements, decisions, and final validation.
- Handoff should contain only goal, current state, decisions, changed files, checks, blockers, and exact next action. Replace stale state; do not append transcripts.

## Truthful measurement

Track three separate lanes; never combine them into one "tokens saved" number:

1. **Provider usage**: input, output, reasoning, cached input, and cache-write tokens from the provider response/CLI when exposed.
2. **RTK**: raw vs filtered shell bytes and estimated tokens; label as estimated command-output reduction.
3. **Quality**: fixed representative tasks with correctness, evidence completeness, build/test result, and regression count.

Gemini CLI exposes `/stats` cached-token data only for API-key or Vertex AI authentication; OAuth Code Assist does not support cached content. OpenAI exposes `cached_tokens` and, for GPT-5.6+, `cache_write_tokens`; stable exact prefixes matter. Do not fabricate unavailable fields.

## Native enforcement worth adding

- One project-local lifecycle hook/script for: index freshness check, brief generation, maximum normal output size, and handoff validation. Keep hook stdout machine-readable and minimal.
- One benchmark command that runs the same small and large fixtures before/after workflow changes and records provider usage, RTK metrics, wall time, and quality gates.
- No vector database, embeddings, autonomous memory writer, or new orchestration service until measured misses justify them. `rg` + Ctags + Git + compact skills cover the current need with fewer moving parts.

## Primary sources

- [OpenAI: AGENTS.md discovery and precedence](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [OpenAI: skills progressive disclosure](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI: subagent context and token tradeoffs](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [OpenAI: deterministic lifecycle hooks](https://learn.chatgpt.com/docs/hooks)
- [OpenAI: lean prompts, evals, tool routing, and measurement](https://developers.openai.com/api/docs/guides/latest-model)
- [OpenAI: exact-prefix caching and usage fields](https://developers.openai.com/api/docs/guides/prompt-caching)
- [Gemini CLI: hierarchical and just-in-time project context](https://geminicli.com/docs/cli/gemini-md/)
- [Gemini CLI: skills and `.agents/skills` alias](https://geminicli.com/docs/cli/skills/)
- [Gemini CLI: skill progressive-disclosure guidance](https://geminicli.com/docs/cli/skills-best-practices/)
- [Gemini CLI: token caching and `/stats`](https://geminicli.com/docs/cli/token-caching/)
- [Gemini CLI: subagents and independent context](https://geminicli.com/docs/core/subagents/)
- [Google Antigravity codelab: workspace rules and workflows](https://codelabs.developers.google.com/getting-started-agy-ide)
- [RTK official guide](https://github.com/rtk-ai/rtk/blob/develop/docs/guide/index.md)
- [RTK official analytics and estimator limits](https://github.com/rtk-ai/rtk/blob/develop/docs/guide/analytics/gain.md)
- [RTK correctness-versus-compression policy](https://github.com/rtk-ai/rtk/blob/develop/CONTRIBUTING.md)
- [ripgrep official guide](https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md)
- [Universal Ctags JSON output](https://docs.ctags.io/en/stable/man/ctags-json-output.5.html)
- [Git diff official documentation](https://git-scm.com/docs/git-diff)

---

## Formal Mathematical Foundations & Algorithmic Rigor

The Universal AI Workflow is grounded in five key domains of statistical learning, information theory, and cognitive science:

### 1. Probabilistic Information Retrieval: Okapi BM25+ & Lower-Bound Relevance
Standard BM25 suffers from over-penalization of lengthy documents when matching rare queries. To guarantee monotonicity and avoid zero-relevance pathologies, the retrieval engine implements **BM25+** (Lv & Zhai, CIKM 2011):

$$Score(D, Q) = \sum_{i=1}^{n} \text{IDF}(q_i) \cdot \left[ \frac{f(q_i, D) \cdot (k_1 + 1)}{f(q_i, D) + k_1 \cdot \left(1 - b + b \cdot \frac{|D|}{\text{avgdl}}
ight)} + \delta 
ight]$$

Where:
- $\text{IDF}(q_i) = \ln \left( \frac{N - n(q_i) + 0.5}{n(q_i) + 0.5} + 1 
ight)$ is the Robertson-Spärck Jones Inverse Document Frequency with non-negative smoothing.
- $k_1 \in [1.2, 2.0]$ governs term frequency saturation.
- $b = 0.75$ controls document length normalization.
- $\delta = 1.0$ guarantees that any document containing query term $q_i$ receives a strictly positive lower bound of $\delta \cdot \text{IDF}(q_i)$, preventing recall starvation in dense incident catalogs.

### 2. Cognitive Memory Activation: Anderson's ACT-R & Ebbinghaus Forgetting Decay
Durable agent memory requires temporal decay balanced by periodic reinforcement. Following Anderson's ACT-R cognitive architecture (Anderson & Schooler, 1991) and the Ebbinghaus forgetting dynamics:

$$R(t) = \exp\left( -\frac{\Delta t}{S \cdot (1 + \ln(1 + k))} 
ight)$$

$$\text{Score}_{\text{retrieval}}(E) = \text{Score}_{\text{BM25+}}(Q, E) \cdot R(\Delta t)$$

Where:
- $\Delta t$ is elapsed time in days since memory capture.
- $S$ is memory base stability factor ($S = 30$ days).
- $k$ is the reinforcement count (number of verified task recalls).
- As recalls increase ($k \to \infty$), memory half-life grows logarithmically, replicating human expert long-term potentiation while filtering transient noise.

### 3. Spectral Graph Theory & Personalized PageRank (PPR)
Symbol dependency navigation models the codebase as a directed graph $G = (V, E)$ with transition probability matrix $\mathbf{P}$. The stationary distribution $\boldsymbol{\pi}$ under random walks with restart is solved via the power iteration algorithm:

$$\boldsymbol{\pi}^{(k+1)} = (1 - \alpha) \mathbf{P}^T \boldsymbol{\pi}^{(k)} + \alpha \mathbf{v}$$

Where:
- $\mathbf{v}$ is the personalization vector (concentrated on seed symbols in the current task).
- $\alpha = 0.15$ is the teleportation parameter.
- By the **Perron-Frobenius Theorem**, the primitive, irreducible Markov transition matrix possesses a unique dominant eigenvalue $\lambda_1 = 1$, guaranteeing geometric convergence $\|\boldsymbol{\pi}^{(k)} - \boldsymbol{\pi}^*\|_1 \le (1 - \alpha)^k$. This identifies high-centrality dependents and blast-radius vulnerabilities deterministically in $O(|E|)$ time without LLM traversal.

### 4. Information-Theoretic State Compression: Rate-Distortion & Entropy Bounds
The 30-line constraint in `.ai/HANDOFF.md` enforces a finite rate-distortion code. Let $X$ represent the high-dimensional codebase state and $\hat{X}$ represent the compressed handoff capsule. By Shannon's Rate-Distortion Theorem:

$$R(D) = \min_{p(\hat{x}|x): \mathbb{E}[d(X, \hat{X})] \le D} I(X; \hat{X})$$

Empirical Shannon entropy of the handoff text:

$$H(X) = - \sum_{i=1}^{|\Sigma|} P(x_i) \log_2 P(x_i)$$

The diagnostics monitor:
- Information Density: $I_D = \frac{H(X)}{\log_2 |\Sigma|} \in [0, 1]$.
- If $I_D < 0.3$, the capsule exhibits excessive repetitive redundancy (wasting LLM context tokens).
- If $I_D > 0.85$, the state approaches maximal entropy, signaling that unstructured unstructured noise has displaced actionable invariant contracts.

### 5. String Metric Spaces: Jaccard N-gram Metric
To resolve symbol typos and identifiers without language server overhead, strings are embedded into an $n$-gram multiset space equipped with the Jaccard distance:

$$d_J(s_1, s_2) = 1 - \frac{|S_n(s_1) \cap S_n(s_2)|}{|S_n(s_1) \cup S_n(s_2)|}$$

$d_J$ forms a valid metric space satisfying identity of indiscernibles, symmetry, and triangle inequality $d_J(A, C) \le d_J(A, B) + d_J(B, C)$, providing a robust similarity filter with threshold $J \ge 0.3$.

