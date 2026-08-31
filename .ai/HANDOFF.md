# Handoff

- **Goal / state**: Require evidence for durable brain captures; implemented and checked.
- **Exact paths+symbols**: ai-workspace/scripts/brain-capture.ps1 params+entry; ai-workspace/scripts/complete-task.ps1 capture gate.
- **Ordered edits**: 1. Add required Evidence input. 2. Store evidence in brain entry. 3. Pass it through completion. 4. Run focused checks.
- **Reuse/deletions**: Reuse existing parameter validation and Markdown entry format; no new files or dependencies.
- **Invariants**: Recall format remains readable; no memory write without evidence; incident-only completion unchanged.
- **Changed files**: ai-workspace/scripts/brain-capture.ps1; ai-workspace/scripts/complete-task.ps1; .ai/HANDOFF.md.
- **Checks**: validate-handoff PASS; missing Evidence rejected; supplied Evidence PASS; check-workflow PASS.
- **Blockers**: None
- **Exact next step**: Review diff; complete task without reusable self-capture.

