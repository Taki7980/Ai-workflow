# Issue Tracker

Issues and specs live in GitHub Issues. External writes require explicit user instruction.

## Repository routing

- Primary: `{{GITHUB_ORG}}/{{REPO_NAME}}`
- Secondary (if applicable): `{{GITHUB_ORG}}/{{REPO_NAME_2}}`
- Cross-cutting work: use the repository owning the user-visible behavior; create a linked second issue only when work can ship independently.

Run `gh` inside the matching clone or pass `--repo <owner/repo>`.

## Operations

- Create: `gh issue create --repo <owner/repo> --title "..." --body "..."`
- Read: `gh issue view <number> --repo <owner/repo> --comments`
- List: `gh issue list --repo <owner/repo> --state open`
- Comment: `gh issue comment <number> --repo <owner/repo> --body "..."`
- Label: `gh issue edit <number> --repo <owner/repo> --add-label "..."`

PRs as a request surface: no.

When a skill says "publish to the issue tracker," create an issue in the routed repository. When it says "fetch the relevant ticket," read that issue and its comments.

## Wayfinder

- Map: one issue labelled `wayfinder:map`.
- Child: GitHub sub-issue; fall back to a task-list link when sub-issues are unavailable.
- Blocking: native issue dependency; fall back to `Blocked by: #<number>`.
- Claim: assign the frontier issue to the current user.
- Resolve: comment with decision, close child, add a linked decision summary to the map.
