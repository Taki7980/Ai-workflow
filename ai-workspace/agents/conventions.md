# Project Conventions & Guidelines

Repo: `{{PROJECT_DIR}}/` | Stack: {{PROJECT_STACK}}

## Development Environment Setup
- **Primary runtime/version**: {{RUNTIME_VERSION}}
- **Required databases/services**: {{DATABASES_AND_SERVICES}}

## Commands
```bash
# Fill in your project's development, build, test, and lint commands here
# e.g.:
# <run-dev-server>      # Run dev server
# <build-command>       # Build production package
# <test-command>        # Run all tests
# <lint-command>        # Run static analysis / linters
# <clean-deps>          # Clear and reinstall dependencies
```

## Directory Structure Map
```
# Define the core directory structure of your repository here
# e.g.:
# src/                  Source code files
# tests/                Unit, integration, and E2E tests
# config/               Configuration files / environment variables
```

## Conventions & Rules
- **Formatting & Style**: Follow the project's standard linter and formatter.
- **Error Handling**: Use explicit, wrapped errors/exception propagation appropriate for the language.
- **Testing Requirements**: Write unit/integration tests for any new or modified behaviors. Ensure 100% test pass rate before task completion.
- **Persistent Memory**: Log novel bug resolutions to `lessons-learned.md`.
- **Handoff Rules**: Replace `.ai/HANDOFF.md` at the end of each session with the current task state.
